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
- Physical Orca check requested from the user after launch: type `ghbdtn`, double Shift within 300 ms before Enter; awaiting result. No synthetic UI action is counted as that device check.
