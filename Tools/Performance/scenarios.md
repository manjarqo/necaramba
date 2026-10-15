# Controlled host qualification

Use the same open model manifest, preferences, hardware, OS, app versions and fixture text for baseline/candidate. Alternate A/B/A/B; only one keyboard interceptor may run. Do not send forms/messages or type into personal documents. Record sample counts and failures, including cancellations, rather than discarding unsuccessful trials.

| Host | Test fields |
|---|---|
| Orca | New unsent draft |
| TextEdit | New temporary plain-text document |
| Safari | Address bar and a local fixture HTML input/textarea |
| Chrome, Zen | Local fixture HTML input/textarea |
| Spark | New unsent plain/rich-text draft |
| Spotlight | Query field; do not open a result |

For each field, at least30 trials each: first-word automatic correction in both directions (`ground`, `connector`, `тоже`, `переключилось` typed in opposite layout),30 repeated double-Shift conversions, selected-text conversion, `1ю3ю166` manual conversion, continuous typing, focus switch while verification waits. Capture damage/extra/repeated edits as failures. Use dedicated local fixtures for long content and password/secure-input abstention. Synthetic replay does not qualify physical capture.

Record queue/classification/preflight/posting/verification/total stages separately from the300ms gesture recognition window. Fixed histogram percentiles are upper bounds, not exact raw percentiles. For callback p99 use at least1000 samples; report small-sample tails separately. Counters must contain no text/keycodes/URLs/titles/document paths.

Resource runs:10min idle with settings closed and open;10min typing;20 UI open/close cycles;10cold and30warm model starts. Use Instruments Time Profiler/Allocations/Energy and physical footprint (`vmmap -summary PID`), not RSS alone. Record versions/settings and instrumentation overhead. No actual Intel device means Intel runtime remains UNRUN, even if arm64+x86_64 build succeeds.

Acceptance: zero wrong-field/corrupted/duplicate edits; unchanged corpus decisions; no lost deadlines; no idle50Hz timer; no own blocking wait in production main edit path. Repeat any >5% p95/p99 or footprint regression; stable regression blocks that change. Target20% p95 improvement in genuinely slow application scenarios is experimental, not an already achieved result.
