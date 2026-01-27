CorePolicy v3.0 – Technical Changelog

- Deterministic rebuild of all policy binaries (arm64-v8a, armeabi-v7a) using a fixed API 21 toolchain baseline
- Refactored boost/demote split: foreground boosts are more selective and accurate, background demotion is more aggressive
- libcoreperf: PID-driven boost pipeline with per-thread whitelisting and binder exclusion
- SurfaceFlinger boost converted to gated one-shot behavior (debug.core.policy.perf)
- libcoredemote: UID-aware background demotion with thread-level application
- Reduced daemon and executor overhead; fewer forks and tighter execution paths
- Dynamic preload generator hardened with explicit bounds and size limits
- Static preload filtering refined to avoid framework, HAL, and security-critical libraries
- Behavior between v1.4, v2.0, and v3.0 differs by design; all versions remain stable and supported
