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

## Follow-up: Safari reversal and Chrome

The user reported that the rebuilt app still converted Safari's address and page fields only once, and did not convert Chrome page fields. The prior device checks therefore did not pass.

New redacted runtime evidence:

- 15:35:23: the batch was posted, then AXSelectedTextRange timed out after about 50 ms; cached context and physical input generation were unchanged. The immediate uncertain result discarded reversal state.
- 15:36:09: AX readback returned a nonfinal value/range pair after an unchanged snapshot; independent attribute reads can straddle asynchronous processing.
- 15:39:11: focused-element lookup itself timed out after posting.
- 15:43:34: two commands were rejected with cachedLayoutMatchesCurrent=0 and wordLayoutMismatch. External focus observation needs to synchronize the runtime's layout before collecting a word.
- Repeated publication of a noneditable focus compared against the absent editable token, advancing focus epochs at every fallback poll. A regression test reproduces this without changing the focused element.

CUA inspection of Chrome exposed its toolbar and address field but not the active web page. Chromium's application implementation explicitly supports AXEnhancedUserInterface to enable complete accessibility after a two-second debounce: https://chromium.googlesource.com/chromium/src/+/master/chrome/browser/chrome_browser_application_mac.mm . This supports adding the missing activation step; it does not by itself prove that it accounts for every reported Chrome failure.

Implemented follow-up:

- Post-dispatch reads distinguish a transport timeout from a positively rejected observation. Focus lookup can be temporarily unproven; value/range timeouts retain any identity/value already observed. No mutation is retried. Known identity changes, rejected security/composition metadata, unrelated text, generation changes and deadline expiry remain terminal.
- Text and caret progress are tracked separately because AX attributes can be independently cached. Each must remain within states derivable from the posted batch and cannot regress within its own observed history. Success still requires the exact final text/caret and pinned identity. The original 100 ms/21-observation bound remains.
- External focus observations synchronize cached layout after reconciliation has published a visible context. Explicit edit-time refresh does not invoke this callback, preserving intentional conversion/reversal transactions.
- Noneditable focus polling preserves gesture identity when unchanged.
- Chrome alone requests AXEnhancedUserInterface. A cancellable 2.2-second callback refreshes focus or retries observer subscription on the existing app reference, without detaching or discarding unchanged field identity. It never disables accessibility shared with other clients.

Integrated verification after follow-up: 203 Mac + 65 Core = 268 Swift tests passed. New tests exercise transport timeouts, independently cached caret/value, permanent rejection, bounded no-repost behavior, Chrome activation cancellation and focus-driven layout synchronization. Physical compatibility remains pending; unit tests are not device qualification.
