# CorePolicy

CorePolicy is a native Android policy module that coordinates memory residency, CPU scheduling, and process prioritization using system-supported kernel and framework mechanisms.

It is designed for **deterministic, low-overhead execution** across both rooted and non-rooted environments, adapting its behavior at runtime based strictly on available capabilities.

---

## Overview

CorePolicy provides a unified policy layer that:

- Improves foreground application responsiveness  
- Reduces background interference  
- Preserves system stability and compatibility  
- Avoids device-specific tuning and hardcoded assumptions  

All actions are applied dynamically, scoped to active foreground contexts, and reverted automatically when no longer required.

No user configuration is required.

---

## Supported Environments

CorePolicy is compatible with the following managers and execution environments:

- Magisk  
- KernelSU  
- APatch  
- Axeron Manager (root & non-root mode)  
- Other root managers capable of loading native binaries and shared libraries  

Root access is **not required**.

When root privileges are unavailable, CorePolicy transparently falls back to Android framework-managed task profiles while preserving functional correctness.

---

## Architecture (v5.x)

Starting with v5.0, CorePolicy is implemented as a **single unified native execution path**.

- All policy logic is consolidated into one primary binary  
- Previously separate helper processes and libraries have been removed  
- No inter-process handoff or duplicated state  
- Reduced runtime dependency graph  

This design minimizes syscall count, eliminates race conditions, and ensures deterministic behavior.

---

## Execution Model

Policy application follows a single-pass, deterministic order:

1. Preload  
2. Policy lock  
3. Foreground / top-app boost  
4. Cleanup  

Resolved state is reused across phases to avoid redundant detection and repeated syscalls.

There are no parallel policy entry points.

---

## Memory Policy (Preload)

- Preload lists are consumed directly by the main executable  
- Static and dynamic preload logic are unified  
- Shared libraries used by the current foreground app are mapped eagerly  
- A small, fixed set of critical system libraries may be locked permanently    

Memory operations are conservative by design:

- `mlock()` is used only when permitted and safe  
- Batched `mmap()` operations reduce syscall pressure  
- No retry loops for failed preload entries  
- Graceful degradation when memory pressure or kernel policy rejects a request  

---

## Performance Policy (CPU & Scheduling)

Foreground context is detected using a prioritized chain:

1. Kernel-level cpuset / scheduler state (when available)  
2. Android framework activity state as fallback  

Boosting behavior in v5.x is **strictly bounded and context-aware**:

- Boosts apply only to render-critical and foreground threads  
- Non-critical, transient, and background threads are filtered out  
- Boost windows are short-lived and tightly scoped  
- No persistent priority elevation beyond foreground necessity  

Targets include:

- Foreground application threads  
- SurfaceFlinger and render-critical system threads  

Execution paths:

- Kernel cgroups and scheduler controls when root is available  
- Android `settaskprofile` when operating without root  

---

## Background Policy (Demotion)

- Background and non-critical processes are demoted safely  
- Essential system services are preserved  
- No interference with cached or stopped apps  
- Uses kernel controls or task profiles depending on permissions  

Background handling is conservative and reversible.

---

## CLI and Localization (v5.x)

CorePolicy includes a lightweight, language-aware CLI for diagnostics and status reporting.

- Automatically selects language based on system locale  
- No configuration flags or user input required  
- Operates in both root and non-root environments  
- No persistent state written by CLI operations  
- XML-based localization with integrity verification  

### Supported Languages

The CLI currently supports the following language codes:

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

## Privilege-Aware Behavior

CorePolicy automatically detects available capabilities and selects the safest valid execution path.

| Capability                     | Root | Non-Root |
|--------------------------------|------|----------|
| cpuset / cpuctl control        | Yes  | No       |
| Kernel scheduler control       | Yes  | No       |
| mlock()                        | Yes  | Limited  |
| Android task profiles          | Yes  | Yes      |
| Foreground app detection       | Yes  | Yes      |
| Background demotion            | Yes  | Yes      |

If a capability cannot be used safely, it is skipped rather than emulated.

---

## Design Principles

- Alignment with Android’s scheduling and memory model  
- No persistent or irreversible system changes  
- No forced behavior when a mechanism is unavailable  
- ABI-correct execution on 32-bit and 64-bit systems  
- Deterministic behavior with minimal overhead  

Safety and correctness take precedence over aggressive optimization.

---

## Intended Use

CorePolicy is intended for users who require:

- Consistent and predictable foreground performance  
- Controlled background behavior  
- Broad compatibility across Android versions and devices  
- Support for both rooted and non-rooted environments  

The module is suitable for continuous operation without user intervention.

---

## Updates and Integrity

- Optional update checks via `update.json`  
- Integrity verification is enforced for core artifacts  
- Benign layout differences do not trigger false positives  
- Existing installations upgrade cleanly  

Updates do not alter behavior unless explicitly installed.

---

## License

Refer to the `LICENSE` file for licensing terms.
