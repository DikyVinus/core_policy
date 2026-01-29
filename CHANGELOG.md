# CorePolicy v5.0

## Architectural changes
- Unified all policy logic into a single execution path.
- Merged previously separate policy libraries into one shared core to eliminate duplicated state and redundant execution.
- Collapsed `core_policy_perf` and preload handling directly into `core_policy_exe`, removing inter-process handoff overhead.
- Reduced runtime dependency graph by removing unnecessary helper binaries.

## Execution model
- Single-pass execution for policy application instead of staged invocations.
- Deterministic ordering: preload → policy lock → foreground/top-app boost → cleanup.
- Eliminated race windows caused by multiple independent entry points.

## Preload system
- Preload lists are now consumed directly by the main executable.
- Improved mmap/mlock handling to reduce lock failures under memory pressure.
- Static and dynamic preload logic unified with stricter failure accounting.

## Scheduler and boosting
- Thread-level boosting is now whitelist-driven and resolved at runtime.
- Reduced over-boosting by filtering non-render and non-critical threads.
- More accurate detection of top-app and SurfaceFlinger execution contexts.

## Installer and integrity
- Fixed `customize.sh` false-positive integrity detections.
- Simplified integrity checks while preserving verification guarantees.
- Removed abort paths triggered by benign file layout differences.

## Performance and efficiency
- Fewer forks and execs during normal operation.
- Lower idle CPU overhead due to reduced scheduler churn.
- Improved cache locality from consolidated code paths.

## Stability
- Safer fallback behavior when preload or boost operations fail.
- No functional regressions on unsupported or constrained devices.
- Improved compatibility across AOSP and OEM ROM variants.

## Notes
- No user-facing configuration changes.
- Existing modules upgrade cleanly without manual intervention.
