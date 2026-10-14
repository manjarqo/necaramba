# Safari and Spotlight input compatibility

2026-10-14. The user confirmed Orca works and reported one-way manual conversion in a Safari page, no conversion in Safari's address field, and no double-Shift conversion in Spotlight.

## Observations

A readable textarea transaction posted its batch at 15:17:00.116 but returned uncertain on its first AX readback at .121. The runtime correctly quarantined that unverified edit and discarded reverse state. The adapter previously waited only on an entirely unchanged pre-edit snapshot and rejected even intermediate states of its own asynchronous batch.

A controlled physical address-field retry at 15:19:53 and 15:19:56 retained six characters, proved a collapsed selection and found a layout mapping, but rejected the captured word's context/layout before posting. The CUA-reported role was a text field, not an unsupported combo box. Additional static diagnostics distinguish context and layout mismatch without logging text or URLs.

Duplicate focus notifications were independently reproduced advancing the focus epoch despite unchanged field identity. Another attempt at 15:23:13 failed AX observer subscription with notificationUnsupported (-25204); the existing early return discarded the usable application AX reference and prevented any focused field from becoming editable.

## Changes and boundaries

Readable edits may wait through only states derivable from their already-posted batch: deletion prefixes and insertion prefixes with exact unchanged surrounding text and matching caret. Progress cannot move backward. Verification remains bounded to 100 ms and 21 reads, requires exact final value/caret and unchanged identity/context/input generation, and never retries or rolls back a mutation.

Duplicate focus notifications now reconcile authoritative identity without advancing epochs for the same field. Cached edit and gesture contexts are hidden during that remote reconciliation; changed/missing/secure fields remain inadmissible. Known noneditable focus preserves single-Shift layout switching.

When observer creation or subscription fails, the app AX reference remains available. The monitor performs an immediate authoritative refresh and main-thread polling every 250 ms only for the fallback case. Detach/stop/deinit cancel polling; generation checks reject stale callbacks. No unsupported role was added based on speculation; Secure Input and password checks remain mandatory.

## Validation

RED/GREEN tests cover duplicate identity, admission hiding during reconciliation, genuine changes and absence, noneditable gesture continuity, fallback scheduling/cancellation, asynchronous deletion/insertion prefixes and rejected unrelated/backward/caret/identity/generation changes. Integrated Swift suite: 191 Mac + 65 Core = 256 tests passed. Device confirmation follows the rebuilt signed app; these unit tests do not establish Safari/Spotlight qualification.

Release rebuilt successfully (60.9 MB) and passed deep/strict codesign verification with the existing certificate requirement. The app launched without permission onboarding and reached active status. Final independent review found no unresolved blockers. Updated physical Safari/address-bar/Spotlight checks have been requested; their result remains pending.
