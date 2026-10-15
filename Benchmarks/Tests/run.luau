local Statistics = require("../lib/Statistics")
local Runner = require("../lib/Runner")
local Workloads = require("../lib/Workloads")
local loadLibrary = require("./LibraryFixture")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, message = pcall(fn)
	if ok then
		passed += 1
		print(`PASS {name}`)
	else
		failed += 1
		print(`FAIL {name}: {message}`)
	end
end

local function near(actual, expected)
	assert(math.abs(actual - expected) < 1e-6, `{actual} differs from {expected}`)
end

local function simulation(options)
	options = options or {}
	local now, created, cleaned, yields = 0, 0, 0, 0
	local case = {
		id = "fake",
		workload = "Diagnostics",
		unit = "operation",
		unsupported = function(_, role)
			return if options.skip and role == "candidate" then "missing capability" else nil
		end,
		create = function(library, role, probe)
			created += 1
			local steps = 0
			return {
				step = function()
					if options.stepError and role == "candidate" then
						error("step failed")
					end
					steps += 1
					now += library.cost
				end,
				verify = function(iterations)
					assert(steps == iterations, "Wrong iteration count")
					if options.verifyError then
						error("verification failed")
					end
					return if options.mismatch and role == "candidate" and probe then "different" else tostring(steps)
				end,
				metrics = function()
					return { steps = steps }
				end,
				cleanup = function()
					cleaned += 1
					if options.cleanupError then
						error("cleanup failed")
					end
				end,
			}
		end,
	}
	local config = { workload = "All", samples = 5, warmupBatches = 2, maxIterations = 32, targetSeconds = 0.005 }
	local results = Runner.run({ cost = 0.001 }, { cost = 0.00075 }, { case }, config, {
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
	return results[1], created, cleaned, yields
end

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
end)

for _, option in ipairs({ "stepError", "verifyError", "cleanupError" }) do
	test(`cleanup and failure reporting for {option}`, function()
		local record, created, cleaned = simulation({ [option] = true })
		assert(record.status == "failed" and record.summary == nil, "Invalid workload was timed")
		assert(created == cleaned, "Failed batch leaked a fixture")
	end)
end

test("workloads have distinct stable ids and prerequisite gates", function()
	local seen, counts = {}, {}
	for _, case in ipairs(Workloads.create()) do
		assert(not seen[case.id], `Duplicate workload {case.id}`)
		seen[case.id] = true
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
			and counts.Cancellation == 4,
		"Unexpected workload inventory"
	)
end)

test("workload probes execute against unchanged library source and dispose events", function()
	local baseline, baselineClean = loadLibrary()
	local candidate, candidateClean = loadLibrary()
	local checked, skipped = 0, 0
	for _, case in ipairs(Workloads.create()) do
		if case.unsupported(baseline, "baseline") or case.unsupported(candidate, "candidate") then
			skipped += 1
			continue
		end
		for _, probe in ipairs({ true, false }) do
			local signatures = {}
			for index, library in ipairs({ baseline, candidate }) do
				local fixture = case.create(library, if index == 1 then "baseline" else "candidate", probe)
				local ok, message = pcall(function()
					for _ = 1, 3 do
						fixture.step()
					end
					signatures[index] = fixture.verify(3)
					assert(type(fixture.metrics()) == "table", "Missing probe measurements")
				end)
				fixture.cleanup()
				assert(ok, `{case.id}: {message}`)
			end
			assert(signatures[1] == signatures[2], `A/A mismatch in {case.id}`)
		end
		checked += 1
	end
	baselineClean()
	candidateClean()
	assert(checked >= 13, "Expected all legacy workloads to run")
	print(`Source fixture smoke checks: {checked} pairs passed, {skipped} require additional library capabilities`)
end)

print(`Benchmark harness: {passed} passed, {failed} failed`)
assert(failed == 0, "Benchmark harness tests failed")
