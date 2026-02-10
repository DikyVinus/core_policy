# CorePolicy v5.0

## Executive Summary
CorePolicy v5.0 is a **foundational release** focused on correctness, determinism, and long-term maintainability.  
The priority of this version is **doing less work, fewer syscalls, fewer processes, and doing it exactly once**.

The release introduces a **fully language-aware CLI and logging system** while simultaneously **reducing runtime complexity**.  
No new user configuration is required.

---

## 1. Core Architecture

- All policy logic unified into **a single execution path**.
- Previously split components merged into one shared core:
  - Removed duplicated state.
  - Removed redundant execution paths.
- `core_policy_perf` and preload helpers fully absorbed into `coreshift`.
- Eliminated inter-process handoff and helper binaries.
- Centralized environment detection:
  - root
  - non-root
  - Axeron  
  This prevents repeated checks and inconsistent behavior.
- Runtime dependency graph significantly reduced.

Result:
- Fewer forks
- Fewer execs
- Lower failure surface
- Fully deterministic behavior

---

## 2. Execution Model (Determinism First)

- Single-pass execution model replaces staged invocations.
- Strict, deterministic ordering:
  1. Preload
  2. Policy lock
  3. Foreground / top-app boost
  4. Cleanup
- Removed race windows caused by multiple independent entry points.
- Resolved state is reused across phases.
- Syscall count reduced by avoiding repeated discovery and validation.

---

## 3. Preload System (Rebuilt)

- Preload lists consumed directly by the main executable.
- Removed fork/exec-based preload dispatch entirely.
- Optimized memory handling:
  - Batched `mmap` operations
  - Conditional `mlock` only when memory pressure allows
- Static and dynamic preload logic unified.
- Strict failure accounting:
  - No retries
  - No spin loops
- Graceful degradation:
  - Missing libraries
  - Kernel rejection
  - Memory constraints
- Zero wasted cycles on failed preload entries.

---

## 4. Scheduler and Boosting (Refined)

- Boosting logic is now **context-aware and whitelist-driven**.
- Thread-level boosting resolved dynamically at runtime.
- Over-boosting reduced by:
  - Filtering non-render and transient threads
  - Ignoring background and cached processes
- Improved detection of:
  - Top-app execution context
  - Render-critical threads
  - SurfaceFlinger involvement
- Boost windows are:
  - Short
  - Bounded
  - Non-persistent
- No priority elevation beyond foreground necessity.

---

## 5. Localization and Language Support (New)

### Language-Aware System
- CLI, logs, and status output are now **fully localized**.
- Language is selected automatically from system locale.
- No user configuration required.
- Localization does not alter execution logic or state.

### Supported Languages (10)
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

### Localized Components
- CLI usage and command descriptions
- Status output titles
- Service and activity logs
- Installer and verification messages
- Module description text

Localization is strictly **read-only** and does not affect integrity verification.

---

## 6. CLI Support

- Lightweight CLI interface for diagnostics and controlled execution.
- No additional runtime dependencies.
- Works in:
  - root environments
  - non-root environments
- No persistent state written by CLI commands.
- CLI execution does not interfere with daemon behavior.

---

## 7. Installer and Integrity

- Fixed `customize.sh` false-positive integrity failures.
- Integrity verification logic simplified while preserving guarantees.
- Removed abort paths caused by benign file layout differences.
- Axeron-aware execution prevents background misclassification.
- BusyBox-safe execution retained.

---

## 8. Performance and Efficiency

- Fewer forks and execs during normal operation.
- Reduced scheduler churn.
- Lower idle CPU usage.
- Reduced syscall pressure during preload and boost phases.
- Improved cache locality from consolidated code paths.
- Reduced memory pressure from aggressive locking strategies.

---

## 9. Stability and Compatibility

- Safe fallback behavior when preload or boost operations fail.
- No regressions on constrained or unsupported devices.
- Improved compatibility across:
  - AOSP ROMs
  - OEM ROMs
- No boot-time blocking.
- No persistent background activity.

---

## Notes

- No user-facing configuration changes.
- Existing installations upgrade cleanly.
- No manual intervention required.
- Behavior remains fully automatic and adaptive.
