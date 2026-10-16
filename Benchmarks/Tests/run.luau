local Statistics = require("../lib/Statistics")
local Runner = require("../lib/Runner")
local Workloads = require("../lib/Workloads")
local Suite = require("../lib/Suite")
local Reporter = require("../lib/Reporter")
local loadLibrary = require("./LibraryFixture")

local passed, failed, skipped = 0, 0, 0
local function test(name, fn)
	local ok, message, reason = pcall(fn)
	if ok and message == "skipped" then
		skipped += 1
		print(`  SKIP {name}: {reason}`)
	elseif ok then
		passed += 1
		print(`  PASS {name}`)
	else
		failed += 1
		print(`  FAIL {name}: {message}`)
	end
end

local function near(actual, expected)
	assert(math.abs(actual - expected) < 1e-6, `{actual} differs from {expected}`)
end

local function simulation(options)
	options = options or {}
	local now, created, cleaned, yields = 0, 0, 0, 0
	local timedBatches = { baseline = 0, candidate = 0 }
	local case = {
		id = "fake",
		name = "fake scenario",
		workload = "Diagnostics",
		rationale = "Cheap callbacks repeat on every tick.",
		unit = "operation",
		unsupported = function(_, role)
			if options.supportError and role == "candidate" then
				error("capability check failed")
			end
			return if options.skip and role == "candidate" then "missing capability" else nil
		end,
		create = function(library, role, probe)
			created += 1
			if not probe then
				timedBatches[role] += 1
			end
			local inject = role == "candidate"
				and (not options.failOnTimedBatch or (not probe and timedBatches[role] == options.failOnTimedBatch))
			if options.setupError and inject then
				error("setup failed")
			end
			local steps = 0
			return {
				step = function()
					if options.stepError and inject then
						error("step failed")
					end
					steps += 1
					now += library.cost
				end,
				verify = function(iterations, check)
					check("runs the requested iterations", function()
						assert(steps == iterations, "Wrong iteration count")
					end)
					check("returns a consistent result", function()
						assert(not (options.verifyError and inject), "verification failed")
					end)
					check("preserves fixture state", function()
						assert(not (options.stateError and inject), "state changed")
					end)
					return if options.mismatch and role == "candidate" and probe then "different" else tostring(steps)
				end,
				metrics = function()
					assert(not (options.metricsError and inject), "metrics failed")
					return { steps = steps }
				end,
				cleanup = function()
					cleaned += 1
					if options.cleanupError and inject then
						error("cleanup failed")
					end
				end,
			}
		end,
	}
	local config = { workload = "All", samples = 5, warmupBatches = 2, maxIterations = 32, targetSeconds = 0.005 }
	if options.failOnTimedBatch then
		config.warmupBatches, config.maxIterations = 1, 1
	end
	config.case = options.case
	config.workload = options.workload or "All"
	local cases = { case }
	if options.followingCase then
		local following = table.clone(case)
		following.id, following.name = "following", "following scenario"
		table.insert(cases, following)
	end
	local results = Runner.run({ cost = 0.001 }, { cost = 0.00075 }, cases, config, {
		clock = function()
			return now
		end,
		yieldBetweenBatches = function()
			yields += 1
			-- Deliberately large; waits must not enter the measured interval.
			now += 10
		end,
		onCase = function() end,
	})
	return results[1], created, cleaned, yields, results
end

print("describe Benchmark harness")

test("percentiles interpolate without mutating samples", function()
	local values = { 4, 1, 3, 2 }
	near(Statistics.percentile(values, 0.5), 2.5)
	near(Statistics.percentile(values, 0.1), 1.3)
	assert(values[1] == 4, "Percentile mutated input")
	near(Statistics.percentile({ 7 }, 0.9), 7)
end)

test("paired reductions and per-operation units", function()
	local result = Statistics.compare({ 0.002, 0.004, 0.006 }, { 0.001, 0.002, 0.003 }, 2)
	near(result.baselineMicroseconds.median, 2000)
	near(result.candidateMicroseconds.median, 1000)
	near(result.pairedReductionPercent.median, 50)
	near(Statistics.compare({ 1 }, { 2 }, 1).pairedReductionPercent.median, -100)
end)

test("empty, mismatched, and zero-duration samples are rejected", function()
	assert(not pcall(Statistics.percentile, {}, 0.5), "Empty sample accepted")
	assert(not pcall(Statistics.compare, { 1 }, { 1, 2 }, 1), "Unpaired samples accepted")
	assert(not pcall(Statistics.compare, { 0 }, { 1 }, 1), "Zero duration accepted")
end)

test("runner calibrates paired batches and excludes waits", function()
	local record, created, cleaned, yields = simulation()
	assert(record.status == "measured", record.reason)
	assert(record.iterationsPerBatch == 8, "Calibration picked the wrong size")
	assert(#record.rawBatchSeconds.baseline == 5, "Wrong number of samples")
	near(record.summary.baselineMicroseconds.median, 1000)
	near(record.summary.candidateMicroseconds.median, 750)
	near(record.summary.pairedReductionPercent.median, 25)
	assert(created == cleaned and yields == created, "Unbalanced fixture lifecycle")
	assert(record.probes.baseline.steps == 3, "Wrong probe count")
	assert(#record.checks.baseline == 3 and #record.checks.candidate == 3, "Preflight check results were not saved")
	assert(record.rationale == "Cheap callbacks repeat on every tick.", "Scenario rationale was not saved")
	for index = 2, #record.rawBatchSeconds.order do
		assert(
			record.rawBatchSeconds.order[index] ~= record.rawBatchSeconds.order[index - 1],
			"Pair order did not alternate"
		)
	end
end)

test("missing capabilities skip without running fixtures", function()
	local record, created, cleaned = simulation({ skip = true })
	assert(record.status == "skipped" and created == 0 and cleaned == 0, "Unsupported workload executed")
	assert(record.summary == nil, "Skipped workload has timings")
end)

test("trace differences cannot be reported as speedups", function()
	local record, created, cleaned = simulation({ mismatch = true })
	assert(record.status == "failed" and record.summary == nil, "Mismatched trace was timed")
	assert(created == cleaned, "Failed preflight leaked a fixture")
	assert(record.failures[1].check == "equivalent execution trace", "Trace mismatch lost its check name")
	assert(record.failures[1].variant == "comparison", "Trace mismatch blamed one variant")
end)

for _, option in ipairs({ "stepError", "verifyError", "cleanupError" }) do
	test(`cleanup and failure reporting for {option}`, function()
		local record, created, cleaned = simulation({ [option] = true })
		assert(record.status == "failed" and record.summary == nil, "Invalid workload was timed")
		assert(created == cleaned, "Failed batch leaked a fixture")
		local detail = record.failures[1]
		assert(detail.variant == "candidate" and detail.phase == "preflight", "Failure lost its execution context")
		assert(detail.stage == string.gsub(option, "Error", ""), "Failure blamed the wrong stage")
	end)
end

test("independent checks and cleanup errors are all reported", function()
	local record = simulation({ verifyError = true, stateError = true, cleanupError = true })
	assert(#record.failures == 3, "Some verification or cleanup failures were lost")
	assert(record.failures[1].check == "returns a consistent result", "First check was not named")
	assert(record.failures[2].check == "preserves fixture state", "Subsequent check did not run")
	assert(record.failures[3].stage == "cleanup", "Cleanup failure was overwritten")
end)

for _, stage in ipairs({ "setup", "metrics", "support" }) do
	test(`reports {stage} errors with the responsible variant`, function()
		local record = simulation({ [`{stage}Error`] = true })
		local detail = record.failures[1]
		assert(record.status == "failed" and record.summary == nil, "Invalid scenario was measured")
		assert(detail.variant == "candidate", "Wrong failing variant")
		assert(detail.stage == (if stage == "support" then "capability" else stage), "Wrong failing stage")
	end)
end

for index, phase in ipairs({ "calibration", "warmup" }) do
	test(`{phase} failures identify their own phase and batch`, function()
		local record, created, cleaned = simulation({ stepError = true, failOnTimedBatch = index })
		assert(record.status == "failed" and record.summary == nil, "Failed preparation was measured")
		assert(record.failures[1].phase == phase and record.failures[1].batch == 1, "Preparation location was lost")
		assert(created == cleaned, "Failed preparation leaked a fixture")
	end)
end

test("sample failures identify the batch and do not stop later scenarios", function()
	local record, created, cleaned, _, records =
		simulation({ stepError = true, failOnTimedBatch = 3, followingCase = true })
	assert(record.status == "failed" and record.summary == nil, "Failed sample was measured")
	assert(record.failures[1].phase == "sample" and record.failures[1].batch == 1, "Sample location was lost")
	assert(records[2].status == "measured", "A failed scenario prevented the next scenario from running")
	assert(created == cleaned, "Failed sample leaked a fixture")
end)

test("workload and exact case filters exclude other scenarios", function()
	local record, _, _, _, records = simulation({ followingCase = true, case = "following", workload = "Diagnostics" })
	assert(#records == 1 and record.id == "following", "Case filter ran another scenario")
	assert(not pcall(simulation, { workload = "Reset" }), "Unmatched workload filter was accepted")
	assert(not pcall(simulation, { case = "missing" }), "Unmatched case filter was accepted")
end)

test("describe/test definitions have scenario names and unique ids", function()
	local cases = Suite.describe("Example", function(defineTest)
		defineTest("named scenario", { id = "named", unit = "operation", create = function() end })
	end, "Repeated visits expose fixed per-node overhead.")
	assert(cases[1].workload == "Example" and cases[1].name == "named scenario", "Scenario hierarchy was lost")
	assert(cases[1].rationale == "Repeated visits expose fixed per-node overhead.", "Suite rationale was lost")
	assert(cases[1].unsupported() == nil, "A default capability check rejected the scenario")
	assert(not pcall(Suite.describe, "Example", function(defineTest)
		for _ = 1, 2 do
			defineTest("duplicate", { id = "same", unit = "operation", create = function() end })
		end
	end), "Duplicate scenario id was accepted")
end)

test("reporter shows group, scenario, check, variant, phase, and totals", function()
	local output, errors = {}, {}
	local reporter = Reporter.new(function(message)
		table.insert(output, message)
	end, function(message)
		table.insert(errors, message)
	end)
	local good = simulation()
	local bad = simulation({ verifyError = true })
	local missing = simulation({ skip = true })
	for _, record in ipairs({ good, bad, missing }) do
		reporter.onCaseStart(record)
		reporter.onCase(record)
	end
	local summary = reporter.finish({ good, bad, missing })
	assert(summary.measured == 1 and summary.failed == 1 and summary.skipped == 1, "Incorrect totals")
	local text, failures = table.concat(output, "\n"), table.concat(errors, "\n")
	assert(string.find(text, "describe Diagnostics", 1, true), "Missing group header")
	assert(string.find(text, "Why: Cheap callbacks repeat on every tick.", 1, true), "Missing workload rationale")
	assert(string.find(text, "PASS fake scenario [fake]", 1, true), "Missing scenario result")
	assert(string.find(text, "SKIP fake scenario", 1, true), "Skipped scenario disappeared")
	assert(
		string.find(failures, "candidate / preflight / verify / returns a consistent result", 1, true),
		"Missing check context"
	)
	assert(string.find(failures, "1 failed", 1, true), "Missing failure summary")
end)

test("workloads have distinct stable ids and prerequisite gates", function()
	local seen, counts = {}, {}
	for _, case in ipairs(Workloads.create()) do
		assert(not seen[case.id], `Duplicate workload {case.id}`)
		seen[case.id] = true
		assert(type(case.name) == "string" and case.name ~= "", "Scenario has no readable test name")
		assert(type(case.rationale) == "string" and case.rationale ~= "", "Scenario has no generic workload rationale")
		counts[case.workload] = (counts[case.workload] or 0) + 1
		assert(type(case.create) == "function" and type(case.unsupported) == "function", "Missing fixture functions")
		if case.workload == "Cancellation" then
			assert(
				case.unsupported({ ControlNode = {} }, "baseline") ~= nil,
				"Missing cancellation support was accepted"
			)
		end
	end
	assert(
		counts.Diagnostics == 6
			and counts.Reset == 3
			and counts.Construction == 6
			and counts.Actions == 5
			and counts.Cancellation == 4
			and counts.DecisionCycle == 4,
		"Unexpected workload inventory"
	)
end)

-- Each real scenario is an independent test so one failure cannot hide later cases.
-- The clock is synthetic; these validate fixtures and reporting, never performance.
local activeSuite
for _, case in ipairs(Workloads.create()) do
	if activeSuite ~= case.workload then
		activeSuite = case.workload
		print(`describe {activeSuite} (source fixture smoke tests)`)
	end
	test(`{case.name} [{case.id}]`, function()
		local baseline, baselineClean = loadLibrary()
		local candidate, candidateClean = loadLibrary()
		local now = 0
		local ok, result = pcall(Runner.run, baseline, candidate, { case }, {
			workload = "All",
			samples = 3,
			warmupBatches = 1,
			maxIterations = 1,
			targetSeconds = 0.001,
		}, {
			clock = function()
				now += 0.001
				return now
			end,
			yieldBetweenBatches = function() end,
			onCase = function() end,
		})
		local baselineCleaned, baselineError = pcall(baselineClean)
		local candidateCleaned, candidateError = pcall(candidateClean)
		assert(ok, result)
		assert(baselineCleaned, `baseline cleanup: {baselineError}`)
		assert(candidateCleaned, `candidate cleanup: {candidateError}`)
		local record = result[1]
		if record.status == "skipped" then
			return "skipped", record.reason
		end
		assert(record.status == "measured", record.reason)
		assert(#record.checks.baseline > 0 and #record.checks.candidate > 0, "Scenario ran without named checks")
	end)
end

print(`Benchmark harness: {passed} passed, {skipped} skipped, {failed} failed`)
assert(failed == 0, "Benchmark harness tests failed")
