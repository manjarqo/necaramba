# Input performance measurements

Use the current open Release build, with an unchanged model and fixtures. Never run two keyboard interceptors together. Do not use personal documents or send forms/messages.

`InputPerformanceMetrics.shared` stores ten inclusive histogram buckets per fixed stage: ≤1, 2, 5, 10, 20, 50, 100, 200, 500 ms, and overflow. Counters saturate at UInt64.max. `record` and `recordCancellation` accept only enums and integers, retain no individual samples, and do no disk I/O. A short NSLock serializes updates; measure its contention overhead before claiming a hot-path benefit. Export with `snapshotAndReset()` and `cancellationSnapshotAndReset()` outside the tap. Snapshots reset their respective counters atomically.

Use `InputPerformanceMetrics.nowNanos()` consistently. Total command time begins when the command is recognized (automatic commands at the boundary event), ending after verification or cancellation. Gesture release→recognition belongs in `.gestureRecognition`, separate from `.total`. Queue wait belongs in `.commandQueue`. No typed text, keycodes, titles, URL, paths, or per-key event traces belong in metrics.

Ordinary native stage diagnostics are quiet by default. Start the app process with `NECARAMBA_PERF_TRACE=1` for reviewed redacted stages; other values do not enable it. The process-scoped session expires after ten monotonic minutes from first diagnostic use. Expiry is checked on access and schedules no timer. Restart to create a new session. Lifecycle failures and mutation aborted/uncertain outcomes remain visible. Unknown stage strings and word-length traces are discarded even during opt-in.

Run adapter checks from the repository root:

```sh
swift test --scratch-path /tmp/necaramba-perf-metrics-build --filter InputPerformanceMetricsTests
```

For qualification, follow stage 7 of `docs/superpowers/plans/2026-10-15-performance-optimization.md`. Capture revision, dirty diff hash, model manifest hash, hardware/OS, settings, host versions and anonymized raw aggregates. Alternate A/B/A/B on the same hardware; report per-host p50/p95 and histogram tails, cancellations/errors, AX calls, CPU/wakeups, physical footprint and startup-ready time. Use at least 30 repeats per host, at least 1000 events for callback p99, ten-minute idle/typing runs and Instruments. Compare instrumentation on/off separately. Histogram percentiles are bucket bounds, not precise raw-sample percentiles. Real Intel qualification needs Intel hardware. Record unavailable runs as unrun; unit tests are not release or host qualification.

To export aggregates, launch the process with the opt-in environment above and quit normally: `InputPerformanceReport.flush()` writes only fixed `aggregate=timing.<stage>=...` and `aggregate=cancel.<reason>=...` rows under subsystem `local.necaramba.app`, category `Performance`. No periodic exporter runs in idle. This explicit aggregate export remains available after the detailed ten-minute trace expires. Inspect with `log show --last 15m --predicate 'subsystem == "local.necaramba.app" AND category == "Performance"'`.

The separate pure-policy A/B benchmark needs no app permissions or user data:

```sh
python3 Tools/Performance/benchmark-policy.py > /tmp/necaramba-policy-benchmark.json
```

It compiles the core in optimized mode, alternates convenience/prepared paths, validates identical decisions and reports all samples for0/100/1000 exclusions. It exercises a tiny synthetic fallback engine, not the open dictionary, hardware events, AX or whole-app latency. Preparation cost occurs outside the timed steady-state path; both methods share the same engine and inputs.

`python3 Tools/Performance/benchmark-policy.py --metrics` measures optimized single-thread aggregate recording overhead. It excludes clock reads, export and contention; it is not a tap latency measurement. Both benchmark commands use temporary executables and preserve the installed app.
