CorePolicy

CorePolicy is a native Android policy module that dynamically manages memory residency, CPU scheduling, and process priority using Android’s own kernel and framework mechanisms.

It is designed to work both with and without root, automatically adapting its behavior based on the privileges available at runtime.


---

Key Features

Dynamic shared library preloading for the current foreground app

Safe memory locking of critical system libraries

Foreground performance boosting with automatic fallback paths

Background process demotion to reduce interference

No hardcoded device profiles

No permanent boosts or unsafe pinning



---

Compatibility

It works with:

Magisk

KernelSU

APatch

Axeron Manager (non-root mode)

Other root managers that support native binaries and libraries


Root access is optional.
When root is unavailable, CorePolicy switches to Android-managed task profiles and framework APIs.


---

How CorePolicy Works

CorePolicy is composed of coordinated native components:

1. Preload Policy (Memory)

Preloads shared libraries used by the current foreground app

Permanently locks a small set of critical system libraries

Dynamically locks and unlocks app-specific libraries when the top app changes

Uses mlock() only when safe and supported


2. Performance Policy (CPU & Scheduling)

Detects the current foreground app using:

1. cpuset / cpuctl (primary)


2. ActivityManager stack (framework fallback)



Boosts:

The foreground app

SurfaceFlinger


Applies:

Kernel cgroups and schedulers when root is available

Android settaskprofile when running non-root



3. Background Demotion Policy

Demotes background and non-critical processes

Avoids system-critical services

Uses kernel controls or task profiles depending on permissions



---

Root vs Non-Root Behavior

Capability	Root	Non-Root

cpuset / cpuctl control	✔	✖
Kernel scheduler (SCHED_IDLE / RR)	✔	✖
mlock()	✔	Limited
Android task profiles	✔	✔
Foreground app detection	✔	✔
Background demotion	✔	✔


No manual configuration is required.
Capability detection is automatic.


---

Design Principles

System-aligned behavior (no fighting Android)

Graceful fallback instead of hard failure

No shell execution in hot paths

No persistent or irreversible state changes

ABI-correct handling on 32-bit and 64-bit systems


If a mechanism is unavailable, it is skipped — not forced.


---

Intended Use

CorePolicy is intended for users who want:

Improved foreground responsiveness

Reduced background interference

Predictable behavior across devices

Support for both rooted and non-rooted environments


It is suitable for daily use and long-running sessions.


---

Updates

CorePolicy supports update checking via update.json.
Updates are optional and do not affect existing installations.


---

License

See LICENSE for details.


---
