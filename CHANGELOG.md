# CorePolicy v5.0

## Overview
CorePolicy v5.0 focuses on **execution efficiency, syscall minimization, and deterministic behavior**.  
This release significantly refines preload and boost logic while introducing a **language-aware CLI** without adding user-facing configuration complexity.

---

## Architectural Changes
- Unified all policy logic into a single execution path.
- Merged previously separate policy libraries into one shared core to eliminate duplicated state and redundant execution.
- Collapsed `core_policy_perf` and preload handling directly into `core_policy_exe`, removing inter-process handoff overhead.
- Reduced runtime dependency graph by removing unnecessary helper binaries.
- Centralized environment detection (root / non-root / Axeron) to avoid repeated checks.

---

## Execution Model
- Single-pass execution for policy application instead of staged invocations.
- Deterministic ordering:
  1. Preload
  2. Policy lock
  3. Foreground / top-app boost
  4. Cleanup
- Eliminated race windows caused by multiple independent entry points.
- Reduced syscall count by reusing resolved state across execution phases.

---

## Preload System (Improved)
- Preload lists are now consumed directly by the main executable.
- Removed helper-process based preload dispatch to avoid fork/exec overhead.
- Optimized mmap and mlock usage:
  - Batched mappings to reduce syscall pressure.
  - Conditional locking only when memory pressure allows.
- Static and dynamic preload logic unified with strict failure accounting.
- Graceful degradation when preload targets are unavailable or rejected by the kernel.
- Zero retry loops for failed preload entries to prevent wasted cycles.

---

## Scheduler and Boosting (Refined)
- Boosting logic is now **context-aware and whitelist-driven**.
- Thread-level boosting resolved dynamically at runtime.
- Reduced over-boosting by:
  - Filtering non-render, non-critical, and transient threads.
  - Avoiding background and cached process interference.
- Improved detection of:
  - Top-app execution context
  - SurfaceFlinger and render-critical threads
- Boost windows are shorter and strictly bounded to avoid scheduler churn.
- No persistent priority elevation beyond foreground necessity.

---

## CLI Support
- Lightweight CLI interface added for controlled execution and diagnostics.
- No additional runtime dependencies introduced.
- CLI operates in both root and non-root environments.
- No persistent state written by CLI operations.

### Supported CLI Languages (10)
The CLI automatically selects language based on system locale or explicit argument.

Supported language codes:
- `en` – English
- `id` – Bahasa Indonesia
- `zh` – 中文
- `ar` – العربية
- `ja` – 日本語
- `es` – Español
- `hi` – हिन्दी
- `pt` – Português
- `ru` – Русский
- `de` – Deutsch

---

## Installer and Integrity
- Fixed `customize.sh` false-positive integrity detections.
- Simplified integrity checks while preserving verification guarantees.
- Removed abort paths triggered by benign file layout differences.
- Axeron-aware execution prevents background process misclassification.
- BusyBox-safe execution paths retained for minimal environments.

---

## Performance and Efficiency
- Fewer forks and execs during normal operation.
- Lower idle CPU overhead due to reduced scheduler churn.
- Fewer unnecessary syscalls during preload and boost phases.
- Improved cache locality from consolidated code paths.
- Reduced memory pressure caused by aggressive locking.

---

## Stability
- Safer fallback behavior when preload or boost operations fail.
- No functional regressions on unsupported or constrained devices.
- Improved compatibility across AOSP and OEM ROM variants.
- No boot-time blocking or persistent background activity.

---

## Notes
- No user-facing configuration changes.
- Existing installations upgrade cleanly without manual intervention.
- Behavior remains fully automatic and adaptive.
