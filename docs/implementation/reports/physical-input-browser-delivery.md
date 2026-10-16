# Physical input and browser delivery — 2026-10-15

The user requested an additional replacement path without changing VSCodium's `editor.accessibilitySupport: off`, and independently implementing the delivery approach observed in Caramba. No proprietary implementation or dictionary was added to product targets.

## Behavior

- Focused editable elements with explicitly unavailable AX text/range attributes can use bounded uninterrupted physical keystroke history for manual suffix conversion and automatic conversion at a physical Space boundary. Real empty proxies retain their existing route. Timeouts, malformed attributes, observed selections, nonempty unproven values, insecure context, indirect input methods and stale generation are not treated as missing capabilities.
- The new physical mutation port carries actual field identity, context, generation and deletion count. It does not fabricate a text snapshot or selection range. Completed delivery is `dispatched`, not a verified commit; it does not increment verified correction counts or create undo journal entries. There is no blind retry.
- Repeated conversion retains the identity used for the successful dispatch rather than sampling a separate identity before mutation.
- Safari, Chrome and Brave suffix replacement inserts a temporary physical Space, then deletes one extra character before retyping. Selected text replacement does not use this sequence. The verification state machine recognizes this transient state while preserving exact surrounding text and final caret checks.
- This browser sequence supersedes the earlier automatic Safari range-selection mitigation. Manual Spotlight overlay range preparation remains.

## Scope and limits

`editor.accessibilitySupport` remains off. Accessibility/Input Monitoring permissions and a real identifiable editable field are still required. Missing field identity or a noneditable role remains a refusal, not permission to type blindly into the frontmost process. Opaque selected-text conversion is not introduced. Editor-side transformations without readback remain unverified.

The saved Caramba analysis establishes the temporary-Space sequence and process-targeted event delivery statically; it does not establish universal support for every custom editor. See `docs/research/caramba/application-compatibility-2026-10-15.md` for evidence and inference boundaries.

## Validation

Behavioral RED/GREEN coverage includes missing attributes, manual and automatic physical suffix dispatch, repeated identity retention, cancellation, no verified counters/journal, browser transient order and selected/paste separation. Final integrated Swift suite: `NSUnbufferedIO=YES swift test --scratch-path /tmp/necaramba-perf-final-validation` exited 0, 479 tests (331 Mac + 148 Core), one optional private-model skip, zero failures. Log: `/tmp/necaramba-physical-browser-final-tests.log`. Independent final source review found no remaining concrete blocker. Physical typing in VSCodium with off and repeated Safari/GitHub search still require host qualification; automation-generated keystrokes do not establish physical event lineage.

Local public-model release build succeeded with `NECARAMBA_OPEN_MODEL=YES` and `NECARAMBA_LOCAL_PATTERN_MODEL` unset. Build log: `/tmp/necaramba-physical-browser-build.log`. `codesign --verify --deep --strict` passed; `lipo -archs` confirmed x86_64 and arm64. The local app was restarted and its UI reports active with automatic correction enabled. No commit, push, or public release was made.
