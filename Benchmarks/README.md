# Behaviour tree benchmarks

Compare two snapshots of this library in the same empty Roblox Studio place. The runner warms both versions, alternates their order, verifies results before timing, and saves raw samples and per-operation summaries.

## Why these workloads exist

Behaviour-tree overhead becomes visible when many small callbacks run repeatedly, large trees select only a small part of their branches, or fresh trees are assembled for independent actors. The suite models those usage patterns with synthetic inputs and generic callbacks.

| Workload | Pressure being modelled | What the comparison should reveal |
| --- | --- | --- |
| Diagnostics | A frequent tick performs cheap checks and updates while diagnostics are disabled. Formatting can cost more than the callback itself. | Whether disabled logging avoids formatting work, with enabled logging as the adverse case. |
| Reset | Guards fail or short sequences finish repeatedly, clearing result storage that is often empty. | Whether storage reuse reduces replacement allocations without changing reset behaviour. Larger tables cover the clearing cost; retained capacity still needs separate memory analysis. |
| Construction | A fresh nested tree is assembled bottom-up for each owner. Attaching subtrees can repeatedly copy already-built descendants. | Whether explicit ownership avoids redundant copies while preserving correct links. Deep and wide shapes expose attachment and validation costs. |
| Actions | Many actions only update a small piece of state and finish immediately, while a few actions genuinely span ticks. | Whether an explicit immediate path reduces per-call execution overhead while preserving the ordinary suspended path. |
| Cancellation | Priority guards select one branch and leave large alternative branches untouched; a later priority change can obsolete active work. | Whether cleanup cost follows evaluated work. Sparse, dense, and preemption cases check the tradeoff while requiring equivalent cleanup semantics. |
| DecisionCycle | Maintenance, guarded decisions, cached preparation, and suspended work interact across repeated ticks and multiple independent trees. | Whether a change still helps in a mixed control flow after its isolated mechanism has been measured. |

These are benchmark motivations, not measured improvements. Fixture sizes, names, and input sequences are synthetic choices. Keep one change isolated in an A/B comparison before combining changes in the decision replay.

## Run a comparison

Use PowerShell from the repository root with Git and Rojo on PATH. `foreman install` installs the pinned project tools; the benchmark preparation script itself only needs Git, PowerShell, and Rojo.

First measure the noise in an unchanged-versus-unchanged run:

```powershell
.\Benchmarks\Prepare.ps1 -Baseline HEAD -Candidate HEAD -Build
```

Open the printed `benchmark.rbxlx` path in a separate Studio window and press Play. Use the server Output and server Explorer views. This place contains only the two library snapshots and benchmark code; the Rig demo and your game do not run.

For an uncommitted optimisation, compare the last commit with the working source:

```powershell
.\Benchmarks\Prepare.ps1 -Baseline HEAD -Candidate WORKTREE -Workload Diagnostics -Build
```

For committed work, pass the before/after commit hashes or branch names. Compare only one performance change at a time. Cancellation workloads require recursive cancellation and correct immediate parallel accounting on both revisions; comparing correct cleanup with incomplete cleanup would be misleading.

The preparer writes immutable source and harness snapshots under an ignored `.benchmarks/<run-id>/` directory. It does not change branches, commits, or production source. The manifest includes both resolved commits, SHA-256 source hashes, working-copy status, harness hashes, configuration, and an environment label. Regenerate the place after changing code; editing the repository does not update an already built snapshot.

Supported options:

```powershell
.\Benchmarks\Prepare.ps1 `
    -Baseline HEAD -Candidate WORKTREE `
    -Workload All -Samples 21 -WarmupBatches 3 `
    -TargetMilliseconds 5 -MaxIterations 1024 `
    -EnvironmentLabel 'Desktop foreground Studio, profilers closed' `
    -PrintJson -Build
```

`-Workload` accepts `All`, `Diagnostics`, `Reset`, `Construction`, `Actions`, `Cancellation`, or `DecisionCycle`. Omit `-Build` to obtain a Rojo project for `rojo serve <printed-project-path>`. Every preparation gets its own directory, so earlier snapshots are preserved.

Use `-Case` with an exact scenario ID from Output to rerun only that scenario:

```powershell
.\Benchmarks\Prepare.ps1 -Workload Reset -Case reset-width16 -Build
```

The workload and case filters must both match. An unmatched filter reports an error rather than producing an empty successful run.

For a quick setup check, use `-Samples 3 -WarmupBatches 1 -MaxIterations 4 -TargetMilliseconds 1`. These small batches are smoke checks, not useful evidence of a small speed improvement.

## Workloads

The current suite has 28 cases. Fifteen cases can run on the current library; thirteen require additional APIs or cancellation/accounting capabilities and report `skipped` when those are unavailable.

| Group | Workloads | Untimed mechanism probes |
| --- | --- | --- |
| Diagnostics | 8/64 leaves, alternating conditions/actions, at NONE/TRANSITIONS/VERBOSE | Result string conversions, logger calls, leaf calls |
| Reset | Populate and reset tables with 0/16/128 terminal entries | Status-table identity replacements |
| Construction | Wide, deep, and balanced fresh trees; clone/clone control and clone/adopt comparison | Clone calls, copied-node count, required nodes |
| Actions | Ordinary-action control, 1/32/128 synchronous actions, and immediate actions before a suspended leaf | Distinct callback thread identities, leaf calls |
| Cancellation | Early-failing sequence, early-success fallback, fully visited nested tree, and priority switch | Recursive cancellation calls and callback trace |
| DecisionCycle | Six-tick replay for 1/16 workers; optional synchronous-update and parallel-maintenance profiles | Condition/update counts, callback thread identities, ticks per cycle |

Optional adoption cases use `BT.adopt` and `adoptChild` on the candidate only, while their baseline uses the cloning APIs. Optional synchronous-action cases use `SynchronousActionNode.new` on the candidate only. These adapters describe the APIs a candidate must supply to run those comparisons. If your implementation uses different API names, update the adapters before measuring; never fall back silently to the ordinary path.

The baseline and candidate must share the same callback/status trace in preflight. Every timed batch also checks its final result. Cancellation cases check for recursive cancellation and working immediate parallel accounting on both versions; the priority-switch fixture fails if preempted work still owns a coroutine. A failed workload produces no timing summary.

The preflight checks validate equivalent work within each benchmark fixture. The suite's suspended leaves use an explicitly owned raw `coroutine.yield`, never a task scheduler delay. Correct cancellation of `task.wait` or signal waits requires separate Roblox integration tests.

### Generic decision replay

The [DecisionCycle suite](lib/Suites/DecisionCycle.luau) uses this invented worker tree:

```text
Sequence: worker
  Maintenance: refresh local state, observe inputs
  Fallback: dispatch by priority
    Sequence: unavailable? -> defer
    Sequence: result ready? -> commit
    Sequence: assignment available?
      Fallback: cached plan valid? -> prepare plan
      Process: work that suspends until the driver resumes it
    Idle
```

One operation replays six ticks: unavailable, idle, start assigned work, keep work suspended, complete work, then commit the result. Maintenance runs each tick; priority guards short-circuit lower branches; preparation runs once while its cached result is reused. The fixture checks the full callback trace, each root status, per-worker counters, and released execution handles. Every worker owns independent state and a separate tree.

The ordinary profiles use 1 and 16 workers. The synchronous profile changes only the candidate's immediate actions; the suspended action and conditions retain their ordinary execution path. The parallel profile groups the two maintenance actions under a parallel control on both revisions and requires correct immediate parallel result accounting. Tree construction stays outside these replay timings; use Construction to measure that cost separately.

The driver resumes its own raw coroutine before switching to the completion branch, so the ordinary replay works with the current library's cancellation behaviour. Priority preemption remains an explicit Cancellation workload. Replay timings include input assignment and manual completion delivery as well as tree ticks. The worker count and six-tick cadence describe a synthetic replay, not a real-time scheduler or a capacity prediction.

```powershell
.\Benchmarks\Prepare.ps1 -Workload DecisionCycle -Case decision-cycle-ordinary-workers16 -Build
```

## Scenario modules and named checks

Each workload lives in its own module under `lib/Suites`: [Diagnostics](lib/Suites/Diagnostics.luau), [Reset](lib/Suites/Reset.luau), [Construction](lib/Suites/Construction.luau), [Actions](lib/Suites/Actions.luau), [Cancellation](lib/Suites/Cancellation.luau), and [DecisionCycle](lib/Suites/DecisionCycle.luau). `lib/Workloads.luau` only collects those suites. Shared fixtures and capability checks live under `lib/Fixtures`.

Suites use `Suite.describe` and register named `test` scenarios. Each fixture exposes `step`, `verify`, `metrics`, and `cleanup`. `step` contains the measured operation; `verify(iterations, test)` contains named expectations outside the timed interval:

```luau
return Suite.describe("Reset", function(test)
    test("populate and reset 16 cached results", {
        id = "reset-width16",
        unit = "populate and reset",
        create = function(BT, role, probe)
            -- Return a fresh fixture for this revision and batch.
            return makeFixture(BT, role, probe, 16)
        end,
    })
end)

-- Inside the fixture:
verify = function(iterations, test)
    test("clears the success counter", function()
        assert(root._successCount == 0, `Expected 0, got {root._successCount}`)
    end)
    test("returns to IDLE", function()
        assert(root.status == BT.Enums.Status.IDLE, "Reset retained status")
    end)
    return `empty:{iterations}` -- Comparable execution signature.
end
```

`Suite.describe` also accepts a generic rationale as its third argument. Each suite explains the workload pressure being measured; Output prints it below the suite heading, and each JSON record retains it as `rationale`, including skipped or failed scenarios.

Independent checks all run, collecting each failure. Setup, operation, verification, metrics, and cleanup errors include their stage, revision role, and phase (`support`, `preflight`, `calibration`, `warmup`, or `sample`); repeated phases also include the batch number. Teardown still runs after operation/check failures, and a cleanup error is reported alongside earlier failures.

Output groups scenarios beneath `describe` headings and marks each `RUN`, `PASS`, `SKIP`, or `FAIL`. For example, a broken reset can produce:

```text
describe Reset
  RUN populate and reset 16 cached results [reset-width16]
  FAIL populate and reset 16 cached results [reset-width16]
    candidate / preflight / verify / clears the success counter: Expected 0, got 16
    candidate / preflight / verify / returns to IDLE: Reset retained status
```

A failing batch stops that scenario's measurement. The remaining scenarios continue. Output ends with passed/skipped/failed totals; after saving the full JSON report, the Studio runner raises an error if any scenario failed. A failed scenario never receives a timing summary. `PASS` means its checks and comparison completed, regardless of whether the candidate was faster.

## Read and save results

Output reports baseline and candidate median microseconds per named operation, followed by the median paired percentage reduction and its p10/p90 spread. Positive reduction means the candidate was faster. For priority-switch cases, one operation includes two ticks. Construction measures node creation, attachment, validation, and tree creation; tree verification and event destruction occur outside the timer.

The full report is stored in `ServerStorage.BehaviourTreeBenchmarkResults.Value`. Copy the Value while the play session is still running, in server view, and save it beside that run's `manifest.json` as `results.json`. With `-PrintJson`, Output also prints the JSON in 4,000-character chunks between `BT_BENCH_JSON_BEGIN` and `BT_BENCH_JSON_END`; join those payload chunks without Output timestamps or prefixes when saving.

The JSON report uses schema version 2. It includes scenario names and IDs, generic workload rationale, successful preflight check results by revision, structured failures (`variant`, `phase`, `batch`, `stage`, `check`, `message`), and overall totals. It also includes every completed scenario's raw baseline/candidate batch duration, execution order, iteration count, per-operation statistics, mechanism probe counts, skipped/failed cases, manifest, and Roblox version. Probe counts come from a separate three-iteration instrumented pass, not the timed samples. Distinct callback thread identities demonstrate thread usage; they are not a full allocation or memory measurement.

## Decide whether an optimisation helps

1. Run the A/A comparison first and record its spread. A small apparent gain that is comparable to A/A noise is inconclusive.
2. Compare revisions differing only by the change being measured, on the same machine, Studio build, foreground state, and configuration. Keep other games and profiling tools closed during timing.
3. Repeat the complete A/B run at least three times. Look for a consistent improvement on the intended workload and inspect the adverse cases: enabled logging, large reset tables, deep validation, mixed execution, and dense cancellation.
4. Verify the mechanism counts. Diagnostic formatting guards should remove disabled result formatting, storage reuse should remove table replacements, and adoption should copy zero nodes. Equal callback work and passing correctness tests remain required.
5. If the report flags short batches, raise the iteration limit where practical or treat small deltas as unresolved. Construction is capped at eight retained trees per batch to bound memory; do not infer precision from the number of printed decimal places.

The p10/p90 interval is the observed distribution of paired samples, not a confidence interval or significance test. There is no automatic “5% faster” CI gate. These measurements establish routine cost under a fixture, not FPS, GC pauses, total Lua heap, or server capacity.

The runner uses `os.clock` around non-yielding operation batches. It yields between batches, with setup/assertions/cleanup outside the interval, and keeps raw samples so scheduling/GC outliers remain visible. NONE-level timing uses the normal disabled logger; enabled-level cases use an identical quiet sink to measure call-site formatting without Output rendering. Use a separate [Roblox profiler capture](https://create.roblox.com/docs/performance-optimization/identify) when validating the effect in a full game.

## Validate the harness

```powershell
lute Benchmarks/Tests/run.luau
selene Benchmarks
stylua --check Benchmarks
```

Lute is pinned in the tool manifests. The tests cover statistics, calibration, alternating order, excluding waits, trace mismatches, filters, named checks, failure context, continuing after failures, reporter output, skip handling, and cleanup on failures. Each real scenario also runs as its own source fixture smoke test, so CI identifies individual failures and skips. These use a synthetic clock and test substitutes for GUIDs and BindableEvent lifetime; they do not measure Roblox performance or validate its task scheduler.

CI runs these harness tests and lint/format checks. Studio measurements remain an explicit benchmark run, with results retained alongside the implementation under review.
