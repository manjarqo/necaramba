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

Release follow-up: `flutter build macos --release` succeeded (61.0 MB); deep/strict codesign verification passed with the same Apple Development requirement, and `lipo` reports x86_64 and arm64. Relaunched PID 62334 reached Active without onboarding.

Live Chrome observation: the installed browser returned AXError.notImplemented (-25208) for the best-effort AXEnhancedUserInterface request. Therefore activation is not claimed to have succeeded on this Chrome build. A new local-only test page (`/tmp/necaramba-input-check/index.html`) nevertheless exposes its input and textarea through CUA, and the runtime publishes an editable textfield token. This confirms local field discovery, not physical conversion. Browser-specific custom editors and repeated physical conversion still require user confirmation.

## Rapid repetition follow-up

The user confirmed that Safari still stops after one or two conversions, and Chrome stops after a longer rapid sequence. PID 62334 provides distinct failures: Safari at 15:53:04 rejects AXRole cannotComplete after 50 ms, and at 15:53:20 exceeds the 100 ms readback deadline; Chrome at 15:55:31 reports contextOrGenerationChanged during verification following several committed conversions.

The runtime counted every flagsChanged event as new input, including bare physical Shift release. A regression reproduced 40 harmless Shift transitions changing the proof generation from 6 to 46. Bare physical Shift flags now preserve text proof generation; modified shortcuts, foreign synthetic events, text input and invalid context continue to invalidate. An integration test performs 20 alternating manual conversions while injecting a physical Shift transition during each replacement and checks retained reversal state throughout.

Read-only post-dispatch verification treats role/subrole/marked-range transport timeouts as pending observations, just like focus/value/range timeouts. No missing security metadata is accepted as a completed proof. Manual settling has a 300 ms/61-observation budget; automatic settling remains 100 ms/21 observations. Exact final identity/value/caret and safe context remain mandatory, with no repost or rollback. This is a bounded compatibility change, not a guarantee that an unresponsive browser will complete.

RED: bare Shift generation and 150 ms manual-settling regressions failed before fixes (`/tmp/repeat-red.log`). GREEN: integrated 207 Mac + 65 Core = 272 Swift tests passed (`/tmp/repeat-final-tests.log`), including the 20-conversion regression. Physical rapid repetition awaits the rebuilt app.

## Repeat-state lifecycle correction

PID 79221 narrowed the continuing failure beyond AX transport: Chrome completed numerous conversions, then at 16:05:23.271 delivered a single-Shift command and subsequent double-Shift commands reported wordMissing. Safari likewise completed three conversions, delivered single Shift at 16:05:51.064, and then reported wordMissing. A separate Chrome sequence at 16:05:28 began with nonempty selection, converted once and undid once, then lost the word on the third command. These are lifecycle defects: explicit input-layout switching erased the repeated text, and selected-text conversion retained only a one-shot undo entry.

Text layout is now distinct from current system input layout. An explicit single-Shift transition may rebase the repeat candidate only with unchanged input generation and the same proven process/field focus epoch. External layout changes still invalidate normally. Subsequent conversion derives its target from the retained text layout and verifies the currently visible suffix before writing. Selected conversions retain their two exact proven text alternatives, without inventing physical key events; empty-proxy physical fallback still requires actual physical lineage.

RED: the new integration test failed after the first single Shift and after the one-shot selected undo. GREEN: twelve alternating conversions for both typed and initially selected text, with a single Shift every third round. Full integrated suite: 208 Mac + 65 Core = 273 tests passed (`/tmp/repeat-state-final.log`). This reproduces the specific observed state transitions; physical browser confirmation remains pending.

## Safari page input role

User confirmed Chrome and Safari's address bar now work; Safari page input still fails. PID 97097 at 16:51:06.723 reports context.role.combobox=0, followed by repeated contextMismatch with no editable token. Address-bar conversions at 16:51:39–47 are committed. The page failure occurs before replacement: the manual role filter excluded AXComboBox.

Added AXComboBox to manual role qualification. This only admits the role to existing proof collection: secure-field/composition checks, string AXValue, valid AXSelectedTextRange, identity, focus and exact replacement verification still apply. Pop-up buttons/web areas remain excluded. RED reproduced role rejection; GREEN full suite 208 Mac + 65 Core = 273 tests passed (`/tmp/safari-combobox-green.log`). No automatic compatibility profile was broadened.

## Selected-text direction and pending Spotlight reproduction

User confirmed conversion now works in browsers, and reported failures in Spotlight and selected text. PID 54904 at 16:58:19–20 shows a valid nonempty selected-text proof and mapping, followed immediately by aborted without any mutation. The selected branch previously chose its conversion direction solely from active input layout; when selection belonged to the other alphabet the mapping left it unchanged.

Selected direction now uses alphabetic evidence from the two captured mapping directions, retaining active-direction preference for ties/punctuation-only text. The exact original selection is retained for subsequent reversal. RED reproduced Russian selection with US active and Latin selection with RU active; GREEN covers both directions and reversal. Full suite 209 Mac + 65 Core = 274 tests passed (`/tmp/selected-spotlight-tests.log`).

Spotlight remains unresolved. CUA launch of com.apple.Spotlight returned launchd spawn failure (POSIX 162), and a CUA Command-Space attempt did not expose a Spotlight app/field. Requested an explicit physical Spotlight attempt from the user. Added static diagnostics when focused field resolution fails or reports unsupported role: whether system-wide AX focus belongs to the expected process and whether its bundle family is Spotlight. No text, title, URL, arbitrary bundle ID or PID is logged; this diagnostic does not broaden edit admission or claim a Spotlight fix.

## Spotlight system-focus owner

The next physical attempt (PID 71861, 17:05:26–36) returned app-local focusedUIElement noValue (-25212), while system-wide focus existed and belonged to a different process. No manual command was delivered. This invalidates the assumption that workspace frontmostApplication always owns the focused text field.

ContextMonitor and SystemAXSelectionReader now share AXFocusedElementResolver: system-wide focused element → actual AX PID → running application bundle. There is no fallback to the underlying app on missing/unknown focus. Selection proof rejects a PID different from the frozen context and rechecks focused element identity after reading attributes. Existing role, secure-input, composition, generation and exact readback checks remain in place. While an overlay owns focus independently of the frontmost application, a 250 ms main-run-loop poll follows field changes/dismissal; ordinary application focus notifications remain active. No AX call is introduced in the event tap.

RED: resolver behavior tests failed before implementation (`/tmp/spotlight-owner-red.log`). GREEN: 212 Mac + 65 Core = 277 tests passed (`/tmp/spotlight-owner-tests.log`). Tests cover overlay ownership, rejection of the underlying app's token, missing focus, transport failure and unidentified owner. These are controlled adapter tests, not a physical Spotlight qualification. Release build and deep/strict signature verification passed; binary contains x86_64 and arm64. CUA still cannot expose Spotlight via Command-Space; physical repeated conversion has been requested and remains pending.
