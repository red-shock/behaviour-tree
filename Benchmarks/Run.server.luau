local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "Run benchmarks in a dedicated Studio place")

local benchmark = ServerScriptService:WaitForChild("Benchmark")
local manifest = HttpService:JSONDecode(require(benchmark.Manifest))
local Runner = require(benchmark.Harness.Runner)
local Workloads = require(benchmark.Harness.Workloads)
local baseline = require(benchmark.Baseline)
local candidate = require(benchmark.Candidate)

print(`BehaviourTree benchmark: {manifest.baseline.label} -> {manifest.candidate.label}`)
local records = Runner.run(baseline, candidate, Workloads.create(), manifest.config, {
	clock = os.clock,
	yieldBetweenBatches = function()
		task.wait()
	end,
	onCase = function(record)
		if record.status == "measured" then
			local summary = record.summary
			print(
				string.format(
					"%s: %.3f -> %.3f us/%s; paired median reduction %.1f%% (p10 %.1f%%, p90 %.1f%%)%s",
					record.id,
					summary.baselineMicroseconds.median,
					summary.candidateMicroseconds.median,
					record.unit,
					summary.pairedReductionPercent.median,
					summary.pairedReductionPercent.p10,
					summary.pairedReductionPercent.p90,
					if record.belowTargetDuration then " [short batch: inspect timer noise]" else ""
				)
			)
		else
			print(`{record.id}: {record.status}: {record.reason}`)
		end
	end,
})

-- Roblox's version() global is absent from the pinned Selene standard library.
-- selene: allow(undefined_variable)
local engineVersion = version()
local report = {
	schemaVersion = 1,
	manifest = manifest,
	environment = {
		robloxVersion = engineVersion,
		isStudio = RunService:IsStudio(),
		capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	},
	workloads = records,
}
local result = Instance.new("StringValue")
result.Name = "BehaviourTreeBenchmarkResults"
result.Value = HttpService:JSONEncode(report)
result.Parent = ServerStorage
print("Full JSON saved in ServerStorage.BehaviourTreeBenchmarkResults.Value (server view, before stopping Play).")
if manifest.printJson then
	print("BT_BENCH_JSON_BEGIN")
	for offset = 1, #result.Value, 4000 do
		print(string.sub(result.Value, offset, offset + 3999))
	end
	print("BT_BENCH_JSON_END")
end
