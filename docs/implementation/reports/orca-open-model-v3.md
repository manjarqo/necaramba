# Orca terminal, open model v3 and posting admission

User reports (2026-10-16): automatic correction never ran while typing in Orca's terminal (a terminal UI); `dc\` stayed instead of `всё`; `вщтэе` stayed instead of `don't`; after an aborted automatic edit the layout remained switched, so the next word was typed in the other layout.

## Causes

- Orca (`com.stablyai.orca`) is Electron + xterm.js. Without `AXManualAccessibility` its AX tree exposed no editable element (12 elements before, `AXTextField` with `xterm-helper-textarea` after activation). Activation and terminal-proxy qualification were bound to `org.tabby` only.
- Automatic posting aborted with admission code 10 (`tap.post.contextMismatch` detail 1 = nil token). Our own layout switch posts a TIS notification whose focus reconciliation hides cached safety (`ContextState.current()` is nil while reconciling); the tap-thread admission sometimes read it at that instant.
- An aborted automatic edit left the layout selected by `prepareMutation`.
- macOS Russian layout carries ё on the backslash key; `\` was not an accepted source mark.
- `все/всё` were fully protected in the open rules and, separately, in the rule package `protectedTokens`, which `NativeInputController` merges into the automatic exclusion policy.
- The open English lexicon contains no apostrophe words; contractions were rejected by `TokenGuard`.

## Changes

- Orca added to `ChromiumAccessibilityActivation` and `AXTerminalProxyMetadata.isHost` (shared by `AXSelectionAdapter`).
- `EventTapAdapter.admission(...)`: only a nil token during authoritative reconciliation is retried (2 ms timer) within the existing 100 ms admission deadline; a different published token or invalidation still rejects. Fixed abort reason codes (`tap.post.aborted`, `tap.post.contextMismatch`, `tap.post.reconcileRetry`).
- `restoreUnchangedLayout`: an aborted automatic edit (no key posted, unchanged input generation) restores the typing layout. `uncertain` results keep the layout.
- `OpenCorrectionEngine`: `\` accepted as a source mark (still requires a known all-letter candidate).
- Open rules schema 2 / `open-3`: `protectedWords` (fully protected, only `ру`), `yoProtectedWords` (never gain or lose ё, layout conversion allowed), `contractions` (54 authored contractions validated against en_US dictionary forms). Schema 1 keeps its meaning.
- `preparedOpenPolicy`: rule-package tokens that the open model classifies as ё-ambiguous are not exclusions for the open engine; user exclusions and other tokens still apply.
- Diagnostics: fixed `auto.decision.*` and `auto.eligibility.rejected` stages.

## Verification

- RED → GREEN: `TerminalProxy|ChromiumAccessibilityActivation` (4 Orca assertions failing first), `OpenCorrectionEngineTests` backslash (2 failures) and schema v2 cases, `ConservativeAutomaticTests.testAbortedAutomaticReplacementRestoresSourceLayout` (layout stayed RU), `NativeInputControllerTests.testOpenModelYoAmbiguityOverridesRulePackageTokensButNotUserExclusions` (no replacement), generator `test_corrections` (1 failure, 1 error). `PostingAdmissionTests` RED was compile-only; behavioural RED is the live trace (`contextMismatch` detail 1 at 12:05:07, 12:10:01, 12:30:01).
- Full `swift test`: 380 Mac (1 optional skipped) + 152 Core, 0 failures. Python model/packaging tests OK. `OpenModelV2Runner`: 37/37 regressions; calibration TP 2387, FP 0, FN 15 (unchanged).
- Release build with `NECARAMBA_OPEN_MODEL=YES`, universal, strict codesign verified.
- Live (owner's Orca terminal, traced): Orca field attaches and automatic replacements dispatch; `ghbdtn→привет`, `руддщ→hello`, `to\→ещё`, `dc\→всё` (`вщтэе→don't` is covered by the shipped-model test only, not identified in a trace); aborted edit kept the layout before the fix. Orca results are usually `uncertain` (code 2) after posting — dispatch is not a verified commit. No admission mismatch in later sessions, but the race fix is not yet live-confirmed under the failing timing.

Not run: Intel, macOS 12, other terminals, release/notarization.
