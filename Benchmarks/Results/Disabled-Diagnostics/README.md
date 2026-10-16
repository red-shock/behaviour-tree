# Disabled diagnostic guards benchmark

P01 removes disabled diagnostic formatting and logger calls. Three paired Studio comparisons consistently reduced tick cost with diagnostics disabled. Enabled verbose logging adds guards to the existing work; its timings were generally slower, with enough noise that a precise overhead percentage is unresolved.

## Comparison

The baseline is `88f639d9df0abd3397e03f1dc3d7014c5d67c96a`. The candidate is the P01 working source on `Guard-Disabled-Diagnostics`, identified by source SHA-256 `7a46ff3a183c1d7d222052f892662e9d52779e2df73d1ecabad0901ca28a6fe7`. The captured manifests mark it dirty because these measurements preceded the implementation commit. All three comparisons use that same candidate source hash.

Measurements ran in a separate local Studio place on Roblox `0.743.0.7431133`, without the Weapons FFA place running gameplay. The benchmark Studio was launched hidden, so these are background Studio measurements. Each case uses 21 paired samples, three warmup pairs, alternating execution order, and the harness's automatic calibration. Setup, assertions, mechanism probes, and cleanup are outside the timed interval.

The A/A control replaced the candidate with an independent clone of the baseline module hierarchy in the same isolated place. Its manifest identifies the matching baseline/candidate source hashes. This control ran after the three A/B comparisons.

## Observed paired reductions

Positive percentages mean the candidate was faster. Each entry is the median of that run's paired reductions, not a ratio of independently summarised tick times.

| Debug level / leaves | A/B run 1 | A/B run 2 | A/B run 3 | A/A control |
| --- | --- | --- | --- | --- |
| 0 / 8 | 25.1% | 31.4% | 28.0% | -6.9% |
| 0 / 64 | 35.5% | 32.5% | 35.2% | 0.5% |
| 2 / 8 | 11.0% | 13.9% | 12.8% | -2.5% |
| 2 / 64 | 12.4% | 15.6% | 13.6% | 0.3% |
| 3 / 8 | -2.4% | -4.3% | -11.3% | -3.0% |
| 3 / 64 | -0.3% | -6.1% | -4.0% | 3.3% |

NONE produced 25.1–31.4% lower paired tick cost for eight leaves and 32.5–35.5% for 64 leaves across the three runs. TRANSITIONS also benefited by skipping verbose-only formatting. VERBOSE has no formatting to eliminate; it retains the same messages and adds level checks.

The control and raw p10/p90 spreads show substantial timing noise, especially in the small-tree cases. These results support the disabled-path improvement, but do not establish a precise universal speedup or statistically resolved verbose overhead. Some batches were shorter than the target duration; each raw report retains that flag. These are tree fixture costs, not FPS or whole-game CPU measurements.

## Mechanism and correctness

In each three-tick preflight at NONE, the eight-leaf case changed from 12 result conversions and 51 logger calls to zero of each. The 64-leaf case changed from 96 conversions and 387 logger calls to zero. Leaf invocation counts and callback traces match between revisions.

All 18 A/B case executions and all six A/A cases passed the benchmark checks. Four additional Studio smoke checks passed: an action and a condition each completed through `task.wait` and a BindableEvent wait, with one callback invocation and no retained execution handle after completion.

The focused offline suite adds checks for enabled message wording/order, dynamic levels, raw yields, cancellation, tick boundaries, and direct logger filtering. Its test substitute for Studio output is separate from these engine timings.

## Raw records and reproduction

- [A/B run 1](ab-run1.json), [run 2](ab-run2.json), and [run 3](ab-run3.json).
- [A/A control](aa-control.json).
- [Scheduler smoke script](scheduler-smoke.luau) and [results](scheduler-results.json). Execute the script in the generated benchmark's Server context after timing completes.

From the main checkout, prepare another comparison:

```sh
lute Benchmarks/Prepare.luau --baseline 88f639d --candidate WORKTREE --workload Diagnostics
```

Open the printed place and press Play. For a new control, pass `--candidate 88f639d` too. Run `lute Test/run.luau` for the focused regression tests. See the [benchmark guide](../../README.md) for interpreting samples and preserving results.
