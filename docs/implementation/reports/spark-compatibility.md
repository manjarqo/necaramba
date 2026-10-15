# Spark Desktop compatibility — 2026-10-15

Target: installed Spark Desktop 3.31.6, bundle `com.readdle.SparkDesktop` (Electron).

## Evidence and implementation

- Composer exposes `AXTextArea` with a rich-text editor description. Initial focus can instead be an `AXWebArea`.
- Enable Electron's documented `AXManualAccessibility` attribute on Spark activation, then refresh the AX observation. Keep Chrome's `AXEnhancedUserInterface` path unchanged. Source: https://www.electronjs.org/docs/latest/tutorial/accessibility
- Spark represents a trailing physical Space as NBSP. The automatic adapter accepts only an exact word followed by that one alternate boundary, in Spark only, and preserves the observed boundary. Whole-value preflight, field identity, input generation and exact post-edit readback remain required.
- Manual correction reads the whole bounded AX caret word in Spark. A physical repeat candidate is refreshed from AX; a literal alternate pair remains authoritative for subsequent toggles.
- Automatic undo records the actual boundary only after exact same-field and same-generation suffix proof. Missing/raced proof invalidates the journal.
- User verified last-word conversion and selected-text conversion after the first build. Automatic correction remained broken. Local diagnostics showed successful activation and `auto.decision.layout`, followed by `ax.auto.readableRangeRejected` / `ax.auto.readableSuffixMismatch`.
- A 60 ms initial automatic-command deferral gives Spark's editor time to consume the physical Space. This is an engineering hypothesis for the AX lag, not a measured universal latency guarantee. New physical input cancels the pending generation. No retry is made after mutation, no suffix proof is weakened, and other applications retain zero-delay dispatch.

## Verification

- RED: activation, NBSP replacement, automatic-to-manual reversal, actual-boundary undo and delayed delivery regressions failed before their respective fixes.
- GREEN: full `swift test`: 244 Mac + 73 Core tests, 0 failures.
- Release build: `flutter build macos --release --build-name=1.0.0 --build-number=2` passed; strict deep codesign verification passed.
- Restarted the local app with the latest build. Physical Spark automatic correction after the 60 ms deferral is pending user verification. Synthetic test events are not presented as physical device tests.
- No version bump, push or GitHub release performed for this fix.
