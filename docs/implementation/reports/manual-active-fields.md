# Manual conversion in active fields — 2026-10-14

## User-directed scope change

The user explicitly requested manual double-Shift conversion across active input fields, naming Orca as the failing editor. This supersedes the earlier design §6 requirement for a shipped static editor profile for manual commands. It does not waive secure-field, focus, permissions, physical-event or automatic-correction gates.

Observed root cause: the application constructed NativeInputController with empty CapabilityProfiles. ContextMonitor therefore never produced an editable token. Single Shift used gestureContext and worked; double Shift was recognized but failed ready(), and typed-word tracking never populated. This was missing functionality, not a permission-refresh failure.

## Implementation decisions

- Runtime manual eligibility depends on a current nonsecure AX text field/area, with current permissions, focus identity and supported layout. No application-name allowlist or fabricated qualification evidence.
- Automatic correction retains its independent corpus and static profile gates. No automatic qualification claim is made by this change.
- For explicit manual commands, an unsupported optional marked-text attribute is accepted only for a direct keyboard-layout source. A present active/malformed marked range still rejects editing. Missing marked text does not prove that every editor has no private composition state; this is a deliberate compatibility tradeoff for the explicit command.
- Normal editors require exact original text/caret/element/generation evidence before posting, and exact full expected text/caret readback afterward. Bounded verification permits asynchronous event delivery without resending the edit.
- Empty terminal input proxies may not expose the terminal's document text. The explicit fallback requires a focused nonsecure field with empty value, collapsed zero range, unchanged identity/generation and a recent physically observed word. It uses the existing bounded keyboard-event transaction. Complete posting without editor readback returns `dispatched`, never a verified commit, undo entry or correction statistic. It is not retried. This physical-input evidence cannot prove that a remote terminal accepted every preceding character or that application code has not moved its private cursor; it is a best-effort manual compatibility path.
- Mouse/navigation, foreign input, permission/focus changes and preference changes invalidate eligible tracked text. Physical punctuation corresponding to Russian letters is retained.

## Device evidence and limits

CUA inspection found Orca exposing a settable “Terminal input” field in an Electron window. No user text was edited, submitted or logged for this inspection. The implementation targets active text controls without naming Orca. Fields that conceal focus/selection as well as text, password fields and Secure Input remain unsupported rather than guessing an edit destination.

Actual physical-key verification in Orca is separate from synthetic replay: the runtime intentionally ignores externally synthesized input, including automation-generated typing. Synthetic unit tests are not reported as a device pass.

Related primary documentation: [Apple selected-text range](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute?language=objc), [Electron accessibility](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md).

## Verification

- RED/GREEN: tracked punctuation, foreign/focus/preference invalidation, first word followed by a space after rule install, submission/Tab, and plain-paste invalidation.
- Controller regressions cover typed double Shift, selected text, static automatic gate, dispatch layout switch without undo/statistics and no fallback retry after uncertain mutation.
- AX regressions cover optional composition metadata, delayed exact readback, surrounding-text mismatch, empty proxy dispatch, and rejecting Enter/Tab before posting.
- Final integrated `swift test`: 144 Mac + 63 Core = 207 passed. No Flutter source changed.
- Independent review found three defects (false verified proxy result, terminal submission replay, stale word after plain paste); all reproduced and fixed, rereview found no remaining actionable issues.

- Final `flutter build macos --release` succeeded (60.6 MB), universal x86_64/arm64. Deep/strict codesign verification passed with the same certificate-based designated requirement as the prior granted local Release. Updated app launched without a missing-permissions onboarding dialog.
- Physical Orca check requested from the user after launch: type `ghbdtn`, double Shift within 300 ms before Enter; user reported no text change. This is a FAILED device check, not a completed Orca qualification. No synthetic UI action is counted as that device check.

- Follow-up diagnosis adds redacted stage/AX status logging only (no keyboard strings, AX values, titles or clipboard contents), to distinguish gesture delivery, editable focus, proof and posting failures on the actual Orca path.

## Orca physical diagnosis

First diagnostic reproduction reached a recognized double-Shift command but was cancelled on a context mismatch. A later controlled reproduction passed context and AX value/range proofs and retained a six-character physical word, but logged `manual.mappingExists=0`; no mutation was attempted. Read-only input-source configuration shows ABC (252) and Russian (19456). The manual command was incorrectly dependent on the classifier package's strictly resolved alias mappings. Manual physical-layout conversion must be derived independently from the installed TIS keyboard tables; automatic linguistic mappings remain unchanged.


The independent manual mapping fix was verified against actual read-only TIS tables on this Mac: ABC/Russian strict package resolution produced zero mappings for the fixture containing the incompatible ё pair, while the physical manual mapping converted `ghbdtn` to `привет` and preserved uppercase. A host-specific temporary test was removed after recording the result; portable fixtures retain the regression.

Mapping-fix verification: 148 Mac + 63 Core = 211 Swift tests passed. Universal Release build succeeded (60.7 MB), deep/strict codesign validation passed with the unchanged certificate requirement. The user subsequently confirmed the first `ghbdtn` → `привет` conversion in Orca. The following Russian `как` and Latin `ltkf` did not convert. Logs showed retained words and available mappings, but no mutation was attempted.

## Consecutive words and event Unicode

Read-only actual TIS tests confirmed both `как` → `rfr` and `ltkf` → `дела` map correctly. The runtime associated raw keyboard-event Unicode with a separately observed layout; these can disagree after switching layouts. Manual typed-word conversion now reconstructs both the original word and replacement from physical key codes/modifiers and captured source/target tables. Normalized events preserve context, layout, timestamps and origin. Ambiguous entries are rejected; generation checks and exact readable AX suffix proof remain in place. Selected-text conversion and automatic resolution are unchanged.

RED/GREEN coverage reproduces three consecutive words with stale Unicode in the latter two, then verifies all three conversions. A further regression rejects an unrelated readable editor suffix before permitting the reconstructed original. Integrated `swift test`: 150 Mac + 63 Core = 213 passed. Independent review of `34ab8ba` found no actionable defects. Physical verification of the complete sequence in Orca remains pending.

The consecutive-word fix was built as a universal arm64/x86_64 Release (60.7 MB); deep/strict signature verification passed with the same certificate requirement. The rebuilt app launched without a permissions onboarding dialog. The requested physical sequence is `ghbdtn` + double Shift, space, `как` + double Shift, space, `ltkf` + double Shift; expected result `привет rfr дела`.

The user subsequently confirmed conversion works, but reported that repeating double Shift does not convert the same word back. The user explicitly requests alternating the last typed word on every double Shift. The existing empty-proxy path discarded the tracked word when switching layout and did not create an undo record; this prevented repeat conversion. The next change must preserve a bounded manual conversion candidate while maintaining invalidation on unrelated input/context changes. Proxy results remain unverified dispatches, not verified commits.

## Repeated explicit toggles

The runtime now retains a separate manual result: immutable original physical input plus current expected text, layout, context, delimiter and field identity. Each new explicit double Shift derives the opposite-layout output from that lineage. It is independent of the verified undo journal. Readable controls still require exact suffix evidence; empty proxies require the retained field identity and a fresh empty-proxy/context/generation proof on every dispatch. No converted output is relabeled as a new physical keyboard event.

Unrelated input, navigation, focus/layout changes, paste, preference/rule changes and lifecycle invalidation discard the candidate. A duplicate notification for the already-selected layout does not erase it. Atomic retention fails if input changed during the operation. Tests cover four physical double-Shift gesture cycles through the runtime for both editor types, duplicate layout notifications, trailing delimiters, subsequent words and invalidation. Adapter tests cover repeated dispatches without fictitious verified commits and reject changed fields/uncertain mutations.

Review found and resolved stale WordBuffer resurrection after direct paste and retained candidates after an outer permission-denied gesture. Both were reproduced before their fixes. Final integrated verification: 158 Mac + 63 Core = 221 tests passed; final read-only review found no outstanding actionable issues. Universal Release (60.7 MB) rebuilt, deep/strict signature validation passed with the unchanged certificate requirement, and the new app launched without permission onboarding. Physical repeated-toggle confirmation in Orca is still pending; automated gesture tests are not device qualification.
