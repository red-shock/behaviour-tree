local Statistics = if script then require(script.Parent.Statistics) else require("./Statistics")

local Runner = {}

-- Setup, assertions, probes, and cleanup are deliberately outside the timed loop.
local function batch(case, variant, iterations, probe, clock)
	local fixture = case.create(variant.library, variant.role, probe)
	local ok, result = pcall(function()
		local step = fixture.step
		local started = clock()
		for _ = 1, iterations do
			step()
		end
		local elapsed = clock() - started
		local signature = fixture.verify(iterations)
		return {
			seconds = elapsed,
			signature = signature,
			metrics = if probe then fixture.metrics() else nil,
		}
	end)
	local cleaned, cleanupError = pcall(fixture.cleanup)
	if not ok then
		error(tostring(result) .. (if cleaned then "" else `; cleanup also failed: {cleanupError}`), 0)
	end
	assert(cleaned, cleanupError)
	return result
end

local function pair(case, variants, iterations, round, hooks)
	local results = {}
	local first = if round % 2 == 1 then 1 else 2
	for _, index in ipairs({ first, 3 - first }) do
		hooks.yieldBetweenBatches()
		results[index] = batch(case, variants[index], iterations, false, hooks.clock)
	end
	assert(results[1].signature == results[2].signature, "Timed variants produced different results")
	return results
end

local function runCase(case, variants, config, hooks)
	local record = { id = case.id, workload = case.workload, unit = case.unit }
	for _, variant in ipairs(variants) do
		local reason = case.unsupported(variant.library, variant.role)
		if reason then
			record.status = "skipped"
			record.reason = `{variant.role}: {reason}`
			return record
		end
	end

	local probes = {}
	for index, variant in ipairs(variants) do
		hooks.yieldBetweenBatches()
		probes[index] = batch(case, variant, 3, true, hooks.clock)
	end
	assert(probes[1].signature == probes[2].signature, "Preflight execution traces differ")
	record.probes = { baseline = probes[1].metrics, candidate = probes[2].metrics }

	local iterations, round = 1, 0
	local limit = math.min(config.maxIterations, case.maxIterations or config.maxIterations)
	local calibration
	while true do
		round += 1
		calibration = pair(case, variants, iterations, round, hooks)
		if
			math.min(calibration[1].seconds, calibration[2].seconds) >= config.targetSeconds
			or math.max(calibration[1].seconds, calibration[2].seconds) >= 0.05
			or iterations >= limit
		then
			break
		end
		iterations = math.min(iterations * 2, limit)
	end
	for _ = 1, config.warmupBatches do
		round += 1
		pair(case, variants, iterations, round, hooks)
	end

	local baseline, candidate, order = {}, {}, {}
	for sample = 1, config.samples do
		round += 1
		local results = pair(case, variants, iterations, round, hooks)
		baseline[sample], candidate[sample] = results[1].seconds, results[2].seconds
		order[sample] = if round % 2 == 1 then "baseline-first" else "candidate-first"
	end
	record.status = "measured"
	record.iterationsPerBatch = iterations
	record.rawBatchSeconds = { baseline = baseline, candidate = candidate, order = order }
	record.summary = Statistics.compare(baseline, candidate, iterations)
	record.belowTargetDuration = math.min(
		record.summary.baselineMicroseconds.median,
		record.summary.candidateMicroseconds.median
	) * iterations / 1e6 < config.targetSeconds
	return record
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
		if config.workload == "All" or case.workload == config.workload then
			local ok, record = pcall(runCase, case, variants, config, hooks)
			if not ok then
				record = {
					id = case.id,
					workload = case.workload,
					unit = case.unit,
					status = "failed",
					reason = tostring(record),
				}
			end
			table.insert(records, record)
			hooks.onCase(record)
		end
	end
	assert(#records > 0, "No matching benchmark workloads")
	return records
end

return Runner
