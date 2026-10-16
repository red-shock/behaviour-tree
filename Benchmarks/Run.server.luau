local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "Run benchmarks in a dedicated Studio place")

local benchmark = ServerScriptService:WaitForChild("Benchmark")
local manifest = HttpService:JSONDecode(require(benchmark.Manifest))
local Runner = require(benchmark.Harness.Runner)
local Reporter = require(benchmark.Harness.Reporter)
local Workloads = require(benchmark.Harness.Workloads)
local baseline = require(benchmark.Baseline)
local candidate = require(benchmark.Candidate)

print(`BehaviourTree benchmark: {manifest.baseline.label} -> {manifest.candidate.label}`)
local reporter = Reporter.new(print, warn)
local records = Runner.run(baseline, candidate, Workloads.create(), manifest.config, {
	clock = os.clock,
	yieldBetweenBatches = function()
		task.wait()
	end,
	onCaseStart = reporter.onCaseStart,
	onCase = reporter.onCase,
})
local summary = reporter.finish(records)

-- Roblox's version() global is absent from the pinned Selene standard library.
-- selene: allow(undefined_variable)
local engineVersion = version()
local report = {
	schemaVersion = 2,
	manifest = manifest,
	environment = {
		robloxVersion = engineVersion,
		isStudio = RunService:IsStudio(),
		capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	},
	workloads = records,
	summary = summary,
}
local result = Instance.new("StringValue")
result.Name = "BehaviourTreeBenchmarkResults"
result.Value = HttpService:JSONEncode(report)
result.Parent = ServerStorage
print("Full JSON saved in ServerStorage.BehaviourTreeBenchmarkResults.Value (server view, before stopping Play).")
assert(summary.failed == 0, "Benchmark scenarios failed; inspect the named checks above and the saved JSON report")
