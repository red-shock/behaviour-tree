local Runner = if script then require(script.Parent.Runner) else require("./Runner")

local Reporter = {}

function Reporter.new(write, writeFailure)
	local activeSuite
	return {
		onCaseStart = function(record)
			if record.workload ~= activeSuite then
				activeSuite = record.workload
				write(`describe {record.workload}`)
			end
			write(`  RUN {record.name} [{record.id}]`)
		end,
		onCase = function(record)
			if record.status == "measured" then
				local checked = 0
				for _, checks in pairs(record.checks) do
					checked += #checks
				end
				local summary = record.summary
				write(
					string.format(
						"  PASS %s [%s] (%d checks): %.3f -> %.3f us/%s; paired reduction %.1f%% (p10 %.1f%%, p90 %.1f%%)%s",
						record.name,
						record.id,
						checked,
						summary.baselineMicroseconds.median,
						summary.candidateMicroseconds.median,
						record.unit,
						summary.pairedReductionPercent.median,
						summary.pairedReductionPercent.p10,
						summary.pairedReductionPercent.p90,
						if record.belowTargetDuration then " [short batch: inspect timer noise]" else ""
					)
				)
			elseif record.status == "skipped" then
				write(`  SKIP {record.name} [{record.id}]: {record.reason}`)
			else
				writeFailure(`  FAIL {record.name} [{record.id}]`)
				for _, detail in ipairs(record.failures) do
					writeFailure(`    {Runner.formatFailure(detail)}`)
				end
			end
		end,
		finish = function(records)
			local summary = { measured = 0, skipped = 0, failed = 0 }
			for _, record in ipairs(records) do
				summary[record.status] += 1
			end
			local report = if summary.failed > 0 then writeFailure else write
			report(`Benchmark results: {summary.measured} passed, {summary.skipped} skipped, {summary.failed} failed`)
			return summary
		end,
	}
end

return Reporter
