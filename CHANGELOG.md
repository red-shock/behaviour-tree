# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-14

### Added

- Added the initial `BehaviourTree` package for building and running Roblox behaviour trees.
- Added tree creation with a default fallback root, custom root support, ticking via `Tree:run()`, pausing via `Tree:pause()`, and cancellation of active execution actions.
- Added action and condition execution nodes backed by coroutines, including `SUCCESS`, `FAILURE`, `RUNNING`, and `IDLE` statuses.
- Added terminator actions that pause the tree after successful completion.
- Added sequence, fallback, and parallel control nodes, including configurable parallel success and failure thresholds.
- Added decorator nodes with custom wrapper and completion callbacks.
- Added built-in `Inverter`, `Succeeder`, `Failer`, and `Repeater` decorators.
- Added node hierarchy helpers for adding, removing, cloning, and printing tree structures.
- Added debug levels for basic tick output, node transition output, and verbose coroutine lifecycle output.
- Added public enums for node types, statuses, and debug levels.
- Added a Roblox Studio test script demonstrating tree composition, decorators, parallel nodes, terminator actions, and paused-tree cleanup.
