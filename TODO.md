# BehaviourTree Review TODO

## 1) Yield Semantics Contract (Corrected finding)

- [ ] Document coroutine yield ownership in `README.md` and inline comments:
  - Scheduler-managed yields (`task.wait`, `RBXScriptSignal:Wait`) are supported by default.
  - Raw `coroutine.yield` requires explicit resume ownership.
- [ ] Add opt-in protocol for manual coroutine resume in BT:
  - Default path keeps scheduler behavior unchanged.
  - Opt-in path allows BT to resume manual yields on tick.

## 2) Parallel Node Counting Logic

- [ ] Fix `ControlNode:_runParallel()` counting so immediate terminal results are counted.
- [ ] Track status transitions robustly:
  - First-run `SUCCESS` increments success count.
  - First-run `FAILURE` increments failure count.
  - `RUNNING -> SUCCESS/FAILURE` transitions count exactly once.

## 3) Child Input API Consistency

- [ ] Fix `addChild` handling in `Tree` and `ControlNode`:
  - Accept a single Node.
  - Accept list with 1+ nodes.
  - Reject invalid non-node input with clear error.

## 4) Clone Strategy / Allocation

- [ ] Replace generic deep-copy clone with structural clone:
  - Copy topology + config only.
  - Exclude runtime state (`tree`, coroutine handles, status tables, connections).

## 5) Leaf Safety and Traversal Guards

- [ ] Guard child iteration in `Tree:pause()` and `Tree.__tostring` for leaf-root safety.

## 6) Cleanup / Minor Optimization

- [ ] Remove or implement unused fields (e.g., stale type entries in `ExecutionNode`).
- [ ] Convert node type validation arrays to set-lookups for O(1) checks.
- [ ] Avoid debug string construction when debug level is below threshold.

## 7) Add testing and CI/CD pipeline

- [ ] Add tests to cover existing functionality
- [ ] Use github actions to run tests in OpenCloud and deploy to Wally
