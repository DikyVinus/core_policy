# CorePolicy

CorePolicy is a native Android policy module that coordinates memory residency, CPU scheduling, and process prioritization using system-supported kernel and framework mechanisms.

It is designed to operate safely across a wide range of environments, including rooted and non-rooted devices, adapting its behavior at runtime based on available privileges.

---

## Overview

CorePolicy provides a unified policy layer that:

- Improves foreground application responsiveness  
- Reduces background interference  
- Preserves system stability and compatibility  
- Avoids device-specific tuning and hardcoded assumptions  

All actions are applied dynamically and reverted when no longer required.

---

## Supported Environments

CorePolicy is compatible with the following managers and execution environments:

- Magisk  
- KernelSU  
- APatch  
- Axeron Manager (root or non-root mode )  
- Other root managers capable of loading native binaries and shared libraries  

Root access is **not required**.  
When root privileges are unavailable, CorePolicy transparently falls back to Android framework–managed task profiles.

---

## Architecture

CorePolicy is composed of independent native components that cooperate at runtime.

### Memory Policy (Preload)

- Preloads shared libraries used by the current foreground application  
- Permanently locks a limited set of critical system libraries  
- Dynamically locks and unlocks application-specific libraries on foreground transitions  
- Uses `mlock()` only when permitted and safe  

### Performance Policy (CPU & Scheduling)

Identifies the foreground application using a prioritized detection chain:

1. `cpuset / cpuctl` (kernel-level)  
2. ActivityManager stack (framework-level fallback)  

Applies performance boosts to:

- The current foreground application  
- SurfaceFlinger  

Uses:

- Kernel cgroups and schedulers when root is available  
- Android `settaskprofile` when operating without root  

### Background Policy (Demotion)

- Demotes background and non-critical processes  
- Preserves essential system services  
- Uses kernel controls or task profiles depending on permissions  

---

## Privilege-Aware Behavior

CorePolicy automatically detects available capabilities and selects the appropriate execution path.

| Capability                     | Root | Non-Root |
|--------------------------------|------|----------|
| cpuset / cpuctl control        | Yes  | No       |
| Kernel scheduler control       | Yes  | No       |
| mlock()                        | Yes  | Limited  |
| Android task profiles          | Yes  | Yes      |
| Foreground app detection       | Yes  | Yes      |
| Background demotion            | Yes  | Yes      |

No user configuration is required.

---

## Design Principles

- Alignment with Android’s scheduling and memory model  
- No persistent or irreversible system changes  
- No forced behavior when a capability is unavailable  
- ABI-correct execution on 32-bit and 64-bit systems  
- Minimal overhead and predictable behavior  

If a mechanism cannot be used safely, it is skipped rather than emulated.

---

## Intended Use

CorePolicy is intended for users who require:

- Consistent foreground performance  
- Controlled background behavior  
- Compatibility across devices and Android versions  
- Support for both rooted and non-rooted environments  

The module is suitable for continuous operation.

---

## Updates

CorePolicy supports optional update checks via `update.json`.  
Updates do not alter existing behavior unless explicitly installed.

---

## License

Refer to the `LICENSE` file for licensing terms.
