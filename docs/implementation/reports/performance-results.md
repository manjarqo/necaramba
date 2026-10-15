# Input performance optimization — 2026-10-15

Status: implementation and independent code review completed; automated verification passed. Host and actual Intel qualification not completed. This report distinguishes measured kernel results from application claims.

## Implemented independent components

- Prepared immutable exclusion policies; convenience APIs remain behavior-compatible, prepared paths avoid rebuilding normalized sets per word.
- Bounded aggregate timing/cancellation counters, opt-in redacted stage logging with ten-minute expiry, explicit aggregate export on normal app termination. Snapshot allocation/export occurs outside the short writer lock; no idle export timer.
- Gesture/ownership one-shot deadlines replace the periodic20ms tap tick. Ownership expiry still cancels pending gestures and replays captured input once.
- Focus notifications revoke safety immediately and coalesce authoritative reads. Healthy observer idle polling removed; recovery/overlay use a single conservative250ms obligation. Missing permissions do not silently discard recovery. No stale token is returned during reconciliation.
- Async edit/TIS transactions replace blocking edit waits, with single-operation ownership, cooperative cancellation and existing focus/security proof preserved. Prepared policies and captured layout tables are reused and invalidated on source-list changes.
- Selected-layout notifications reconcile authoritative focus without invalidating the same field during our own layout change; actual notification-handler regression tests cover both directions and unavailable/changed focus.

## Measured, limited-scope results

Machine: MacBookPro18,3, arm64, macOS27.0.1(26A434). Optimized Swift microbenchmarks, same current core and synthetic fixtures, alternating convenience/prepared call order; one warmup plus five reported runs,1000 decisions/run. Every decision is checked for equality.

| Exclusions | Convenience median µs/decision | Prepared median µs/decision |
|---:|---:|---:|
|0|18.17|18.24|
|100|119.22|18.51|
|1000|1040.04|18.45|

The convenience route reconstructs policy sets on each decision; prepared construction is outside the steady-state timed loop. This is a tiny fallback-engine fixture, **not** measured open-model, AX, browser or keyboard-to-editor acceleration. Near-zero difference with no exclusions is expected. Raw samples: `performance-data/policy-benchmark.json`; reproducible command in `Tools/Performance/README.md`.

Aggregate record median approximately34.09ns in a single-thread million-record loop, excluding clock reads and contention. Raw samples: `performance-data/metrics-benchmark.json`. Do not infer a callback p99 from this.

Baseline app snapshot:162.8MiB physical footprint,285.5MiB peak after existing use; see `performance-baseline.md`. It is not comparable to a freshly launched candidate and does not prove a memory reduction.

## Deliberately preserved behavior

Single Shift retains its300ms ambiguity window. Ownership remains100ms; readback budgets remain300ms manual/100ms automatic. Spark60ms settling remains until live readiness evidence supports changing it. AX batching and background AX executor are not introduced without host qualification. These choices avoid speculative weakening of text-replacement proof.

## Qualification still required

No controlled A/B host p95/p99,10-minute idle/typing Energy traces,20-cycle UI memory study, or actual Intel hardware run has been completed. Universal compilation is not Intel runtime evidence. Follow `Tools/Performance/scenarios.md` before claiming broad speedup or a qualified release. No public release/version bump is part of this work.

## Final verification

- Swift: 455 tests executed, zero failures, one existing optional private-model test skipped (307 Mac + 148 Core).
- Flutter: 65 tests passed; flutter analyze clean.
- Release build succeeded with the public open-2 model; strict deep signature verification passed; executable contains arm64 and x86_64. Bundled model hashes verified, private pattern model absent.
- Open-model holdout: all 6006 cases and individual regression decisions unchanged (2383 TP, 21 FN, 3602 TN, 0 FP).
- Independent review resolved focus-epoch, cancellation/retention and deterministic async test-wait findings; no remaining source blockers.
- Cancellation counters represent observed exit reasons and can overlap; they are not a complete unique-command cancellation rate.

Implementation was performed by parallel agents in an isolated worktree, then integrated while checking original-file hashes to preserve existing open-model work. No commit, push or public release was performed.
