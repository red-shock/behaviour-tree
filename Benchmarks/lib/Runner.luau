local Statistics = if script then require(script.Parent.Statistics) else require("./Statistics")
local Checks = if script then require(script.Parent.Checks) else require("./Checks")

local Runner = {}

local function failure(variant, phase, batchIndex, stage, message, check)
	return {
		variant = variant,
		phase = phase,
		batch = batchIndex,
		stage = stage,
		message = tostring(message),
		check = check,
	}
end

local function stop(failures)
	error({ kind = "benchmarkFailure", failures = failures }, 0)
end

function Runner.formatFailure(detail)
	local location = `{detail.variant} / {detail.phase}`
	if detail.batch then
		location ..= ` {detail.batch}`
	end
	location ..= ` / {detail.stage}`
	if detail.check then
		location ..= ` / {detail.check}`
	end
	return `{location}: {detail.message}`
end

-- Check collection, error context, setup, and cleanup stay outside the timed loop.
local function batch(case, variant, iterations, probe, clock, phase, batchIndex)
	local checks = Checks.new()
	local fixture, stage = nil, "setup"
	local ok, result = pcall(function()
		fixture = case.create(variant.library, variant.role, probe)
		stage = "step"
		local step = fixture.step
		local started = clock()
		for _ = 1, iterations do
			step()
		end
		local elapsed = clock() - started
		stage = "verify"
		local signature = fixture.verify(iterations, checks.test)
		stage = "metrics"
		return {
			seconds = elapsed,
			signature = signature,
			metrics = if probe then fixture.metrics() else nil,
			checks = checks.results,
		}
	end)
	local failures = {}
	for _, check in ipairs(checks.results) do
		if check.status == "failed" then
			table.insert(failures, failure(variant.role, phase, batchIndex, "verify", check.message, check.name))
		end
	end
	if not ok then
		table.insert(failures, failure(variant.role, phase, batchIndex, stage, result))
	end
	if fixture then
		local cleaned, message = pcall(function()
			fixture.cleanup()
		end)
		if not cleaned then
			table.insert(failures, failure(variant.role, phase, batchIndex, "cleanup", message))
		end
	end
	if #failures > 0 then
		stop(failures)
	end
	return result
end

local function compareSignatures(left, right, phase, batchIndex)
	if left ~= right then
		stop({
			failure(
				"comparison",
				phase,
				batchIndex,
				"verify",
				"Baseline and candidate execution traces differ",
				"equivalent execution trace"
			),
		})
	end
end

local function pair(case, variants, iterations, round, hooks, phase, batchIndex)
	local results = {}
	local first = if round % 2 == 1 then 1 else 2
	for _, index in ipairs({ first, 3 - first }) do
		hooks.yieldBetweenBatches()
		results[index] = batch(case, variants[index], iterations, false, hooks.clock, phase, batchIndex)
	end
	compareSignatures(results[1].signature, results[2].signature, phase, batchIndex)
	return results
end

local function runCase(record, case, variants, config, hooks)
	for _, variant in ipairs(variants) do
		local ok, reason = pcall(case.unsupported, variant.library, variant.role)
		if not ok then
			stop({ failure(variant.role, "support", nil, "capability", reason) })
		end
		if reason then
			record.status = "skipped"
			record.reason = `{variant.role}: {reason}`
			return
		end
	end

	local probes = {}
	for index, variant in ipairs(variants) do
		hooks.yieldBetweenBatches()
		probes[index] = batch(case, variant, 3, true, hooks.clock, "preflight", nil)
		record.checks[variant.role] = probes[index].checks
	end
	compareSignatures(probes[1].signature, probes[2].signature, "preflight", nil)
	record.probes = { baseline = probes[1].metrics, candidate = probes[2].metrics }

	local iterations, round = 1, 0
	local limit = math.min(config.maxIterations, case.maxIterations or config.maxIterations)
	local calibration
	while true do
		round += 1
		calibration = pair(case, variants, iterations, round, hooks, "calibration", round)
		if
			math.min(calibration[1].seconds, calibration[2].seconds) >= config.targetSeconds
			or math.max(calibration[1].seconds, calibration[2].seconds) >= 0.05
			or iterations >= limit
		then
			break
		end
		iterations = math.min(iterations * 2, limit)
	end
	for warmup = 1, config.warmupBatches do
		round += 1
		pair(case, variants, iterations, round, hooks, "warmup", warmup)
	end

	local baseline, candidate, order = {}, {}, {}
	for sample = 1, config.samples do
		round += 1
		local results = pair(case, variants, iterations, round, hooks, "sample", sample)
		baseline[sample], candidate[sample] = results[1].seconds, results[2].seconds
		order[sample] = if round % 2 == 1 then "baseline-first" else "candidate-first"
	end
	local ok, summary = pcall(Statistics.compare, baseline, candidate, iterations)
	if not ok then
		stop({ failure("comparison", "summary", nil, "statistics", summary) })
	end
	record.status = "measured"
	record.iterationsPerBatch = iterations
	record.rawBatchSeconds = { baseline = baseline, candidate = candidate, order = order }
	record.summary = summary
	record.belowTargetDuration = math.min(summary.baselineMicroseconds.median, summary.candidateMicroseconds.median)
			* iterations
			/ 1e6
		< config.targetSeconds
end

function Runner.run(baseline, candidate, cases, config, hooks)
	assert(config.samples >= 3 and config.samples % 1 == 0, "Use at least three samples")
	assert(config.warmupBatches >= 1 and config.warmupBatches % 1 == 0, "Use at least one warmup batch")
	assert(config.maxIterations >= 1 and config.maxIterations % 1 == 0, "Invalid iteration limit")
	assert(config.targetSeconds > 0 and config.targetSeconds <= 0.05, "Target batch duration must be in (0, 50ms]")
	local variants = {
		{ role = "baseline", library = baseline },
		{ role = "candidate", library = candidate },
	}
	local records = {}
	for _, case in ipairs(cases) do
		if
			(config.workload == "All" or case.workload == config.workload)
			and (not config.case or config.case == "" or case.id == config.case)
		then
			local record = {
				id = case.id,
				name = case.name or case.id,
				workload = case.workload,
				unit = case.unit,
				checks = {},
			}
			if hooks.onCaseStart then
				hooks.onCaseStart(record)
			end
			local ok, message = pcall(runCase, record, case, variants, config, hooks)
			if not ok then
				record.status = "failed"
				record.failures = if type(message) == "table" and message.kind == "benchmarkFailure"
					then message.failures
					else { failure("comparison", "runner", nil, "unexpected error", message) }
				local reasons = {}
				for _, detail in ipairs(record.failures) do
					table.insert(reasons, Runner.formatFailure(detail))
				end
				record.reason = table.concat(reasons, "\n")
			end
			table.insert(records, record)
			hooks.onCase(record)
		end
	end
	assert(#records > 0, "No matching benchmark workloads")
	return records
end

return Runner
