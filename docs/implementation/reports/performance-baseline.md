# Performance baseline — 2026-10-15

Source baseline: `3f1fea238d611b066a5a66de6225d3dd14648d30` plus pre-existing uncommitted Open Model 2 and input fixes. The execution worktree preserves original-file SHA256 values in its ignored SDD ledger. A plain checkout of that commit is not the baseline.

- Swift baseline: 142 Core tests; 277 Mac tests, one optional private-model test skipped; zero failures. Log: `/tmp/perf-baseline-tests.log`.
- Running open universal Release app, PID94225, observed after approximately17m35s uptime: physical footprint162.8MiB, peak285.5MiB; ps CPU0.0%, RSS22016KiB. Log: `/tmp/perf-baseline-vmmap.log`.
- This is a single process snapshot with existing UI/history, not a controlled ten-minute idle run, leak measurement, model-only footprint or before/after comparison.
- Hardware execution: Apple Silicon. Actual Intel hardware qualification is unavailable in this session; universal compilation is a distinct check.
- Existing dictionary/holdout hashes and behavior remain the Open Model 2 baseline. No private model is a benchmark construction input.

## Missing baseline evidence

No original per-stage p95 trace existed before instrumentation. Hardware-driven fixture runs in Orca/Safari/Chrome/Zen/Spark/Spotlight and paired Instruments Energy/Allocations runs are not represented by Swift tests or CLI microbenchmarks. End-to-end speedup must not be asserted from those substitutes.

The implementation therefore uses deterministic correctness gates and a scoped pure-policy A/B microbenchmark first. The live matrix in `Tools/Performance/scenarios.md` remains required before declaring broad performance/release qualification.
