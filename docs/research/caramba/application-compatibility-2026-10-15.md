# Caramba application compatibility findings (read-only, 2026-10-15)

Scope: retained arm64 decompilation and retained decoded bundled model, installed resource inventory. No target execution, no private user data, no modifications to app/product. Static evidence is not runtime verification. All source paths below relative to docs/research/caramba.

## Confirmed application identity and policy pipeline

- `decompiled/main-arm64/0x100046648.c` (ev_c9322713fe46a2685a8199a4ed46fb42d9c2582c12629ef3040e2d799a630a86) gets frontmost application and forwards localizedName, bundleIdentifier, executableURL.path and per-app user policy. Missing required metadata returns early.
- `0x100046d84.c` converts these three strings to UTF-8; `0x1002310bc.c` (ev_9f3544eb6be3228a8fc0dc9aaad1da07010914c4c61c172b75dda17cb2c050a7) builds three Rust string triples and calls `0x100227308`.
- `0x100227308.c` (ev_c6c2a1d89bfd8a6c9d9ee547301799329271a9201f9e3f7a74d832e9f489fafb) calls `0x1002ac0bc` with executable path, bundle ID, and empty third input; user policy overrides the computed byte (0 default, 1 disable, 2 enable per Swift materializer; precise remaining mask bits not fully decoded). It resets buffered state and refreshes layout state on app activation.
- `0x1002ac0bc` -> `0x1002b00d4` lowercases/searches inputs via `0x1002b1280`, merges matched rule bytes, and `0x1002b98d8` reduces rule IDs 1..9 into bit masks. This establishes real app metadata matching, not a linguistic use of appex. Full packed rule platform/field semantics remain unknown.
- `0x10000b524.c` (ev_841d8938c15e09bf774f65ad21ac7bb57a22f4e5220c053eb7ef32c2816be409): lowercased bundle ID; own tech.caramba.switcher / .dev force code1; user map false->1 true->2 absent->0. `0x10000b650` materializes Core Data AppException records, requires path and bundleID, nil enabled->false. Resources model current Caramba.8 declares enabled, path, bundleID. No user store read.

## Exact hard-coded block

`0x1001d4b38.c` (ev_a0d76538b6cdd7086a167c715fd3f3edb0705c210fb8d86e3cec5ce709e9197f) lowercases/trims bundleIdentifier and compares `com.apple.systempreferences`; caller 046648 stores result in forceBlockEventTap. Swift literal encoded pointer 0x80000001004a03a0 means bytes at VA 0x1004a03c0 (+0x20 Swift bias), length 27. Verified against retained Mach-O segment mappings. Missing bundle ID returns false.

## Browser workaround, confirmed code chain

`evidence/model-followup/model-neutral.json` feats.special_behaviors_wire decodes three strings: safari.app, brave, chrome, all behavior code1. This is bundled model evidence, not speculative detection from ordinary binary strings.

`0x100224414.c` lines ~848–855 lowercases executable path from app state offsets 0xc0/0xc8, calls `0x1002ade40` for model feats then `0x1002b07e4`. The helper substring-matches each special behavior and checks code==1. Result goes as argument7 to `0x10022c820` at lines ~981–983 (also two other correction branches). In `0x10022c820.c` (ev_753b2a9116934a36b80240968ba17c28445d0a4f5e3315fa252f84331ce02e8d), in_x6&1 emits virtual key 0x31 (Space) before deleting old text, and increments backspace count by one. Therefore browser profile inserts a temporary space and removes it during delete/retype. Purpose (e.g. committing browser composition/autocomplete) is inference, not observed rationale. No Electron-wide feature detection, browser scripting, DOM API, or Spark-specific rule established in this scope.

## Terminal focus layout policy

Bundled feats.switch_to_en_on_focus: iterm, terminus, termius, terminal, zenterm, alacritty, hyper.
`0x100227308` lowercases executablePath, iterates this list using `0x10022ee5c` substring search, then enumerates input source candidates with `0x1003b2684` / `0x100228164`, accepts two-byte en or de IDs against available language-pair state, selects input source. Thus confirmed terminal-family activation policy; not proof that every match always selects English regardless of configured pair. Runtime not exercised.

## Spotlight/overlay window owners

`0x10004d794.c` (ev_d78d36e0de1e44d10126855b98fa14e091e13685cddee77f8392edfb2605e6e3) resolves PIDs for com.apple.Spotlight; OS >=27.0 also com.apple.campo. Confirmed with local llvm-objdump ranges 0x10004d86c–0x10004d890 and 0x10004da38–0x10004da68. First literal VA 0x10048ab20, length19; second inline Swift literal x0=0x6c7070612e6d6f63, x1=0xef6f706d61632e65. It unions PID sets and queries CGWindowListCopyWindowInfo(0x11,0); filters owner, optional window-layer constraints for Campo, alpha>0.01, width/height>0.5. It is a specific system-overlay check, not evidence for generic fullscreen/browser handling. AX/window teammate owns downstream behavior interpretation.

## App corpus boundary

Retained appex graph has 486 records, including name/path substrings, bundle IDs, Windows executables, games and single letters. Examples with raw packed rules: xcode and sublime text [8450]; terminal [8450]; iterm [8450,8457]; jetbrains [4354,8706]; com.microsoft.vscode / com.googlecode.iterm / com.apple.terminal / com.apple.dt.xcode [8706]; com.parallels [8705]; remote desktop [5122,8449]; excel [4356]. These establish a cross-platform compatibility corpus, not 486 supported macOS apps. Do not label each raw code disabled/secure/etc without completing packed rule decoding. No Spark key in bounded graph-key search; absence is limited to bundled model version.

## Timing knobs (app-independent unless further proven)

Bundled feats: layout activation/backspace delay25, backspace/retype delay25, retries2, retry delay25, splitshift delay100. 22c820 reads retries capped10, retry sleep capped500ms (multiply1e6 to nanos), and delay capped500ms before and after deletion. Both delay values happen to equal25; pseudocode uses local_74 twice, so exact distinct-field wiring should be verified via disassembly before asserting separate delays applied correctly. These are global model parameters, not per-browser timers.

## Remaining gaps

Full appex packed-rule decoding/precedence; exact all app-family enum actions; runtime behavior; x86_64 parity; newer downloaded rule data; field-specific reliability. No evidence of Electron/browser engine introspection from name strings alone. Product resources contain UI for per-app on/off and no loose JSON compatibility file; model asset carries the actual lists. All complete proprietary data stays in retained local research evidence.

## Follow-up: packed app rules decoded (same day)

`0x1002b7bc4.c` now resolves the packing sufficiently for VSCode/Xcode comparison. The matcher consumes three prepared streams with required masks `0x2200` (bundleIdentifier), `0x2100` (executablePath), `0x2400` (third input, empty in this macOS caller). The test is `(rule & requiredMask)==requiredMask`, not exact equality; selected low byte must be1..9. `0x1002b00d4` builds these streams from inputs bundle/path/third, lowercases them, gathers selected action bytes, sorts/deduplicates them. The high0x2000 bit is established as the mask used by this macOS implementation; naming other platform values is inferred from corpus evidence, not reconstructed enum symbols.

Thus `8706=0x2202` (VSCode bundle ID, JetBrains bundle substring) and `8450=0x2102` (Xcode executable path substring) both select **action2**. Difference is match field, not a separate editor algorithm. Xcode has both path and bundle patterns; duplicates converge. This is an app policy, not accessibilitySupport manipulation.

`0x1002b98d8` (ev_76e1cde49eb22601d9aa34d608b185cb16081110c909580bbafe3a6902f4cd3e) aggregates the action set:
- action1 initializes all four low mask bits (0xF).
- action2 sets bit0; action6 clears bit0 afterward.
- action3 sets bit1; action7 clears bit1 afterward.
- action4 sets bit2; action8 clears bit2 afterward.
- action5 sets bit3; action9 clears bit3 afterward.
Clear actions therefore win for their bit regardless of matched pattern order. This is action precedence, not longest-match precedence. Exact semantics of bits1/2 remain unresolved by bounded consumer trace.

Important Swift/Rust ABI correction: `0x1002ac0bc` returns TWO values, w0=model-available and w1=mask. The decompiler labels it bool and obscures the second return register. Local llvm-objdump at 0x1002ac210–214 explicitly moves x19->x0, x20->x1. At 0x100227344–3a4, user policy2 sets available0 (bypasses model policy), policy1 keeps availability and ORs mask with1, default keeps values. Saved app bytes are +0xd0 availability, +0xd1 mask.

Consumers in `0x100224414`:
- available && lowMask==0xF returns early (pass/skip engine route).
- available && bit0 skips the automatic correction branch around lines734–745. This closes the semantics needed for VSCode/JetBrains/Xcode: **automatic correction is blocked by their bundled rule** unless overridden; no special AX field implementation inferred.
- available && bit3 skips the layout-switch branch near lines1790–1810 (after a buffered gesture state check and global flag+0x156). Exact gesture name needs state-machine corroboration; single-Shift is plausible but not claimed here.
- Bits1/2 are computed but no individual consumers were established in this bounded function; do not assign invented names.

No disabling of VSCode accessibilitySupport is involved in this observed policy. This evidence cannot demonstrate a universal solution for arbitrary custom editors: the shipped app instead includes selective app-policy limits plus correction delivery workarounds.

## AX boundary and implications for Necaramba

A separate bounded search across saved main/UI/helper/keypath decompiled C found no AXUIElement, AXObserver, AXFocused, AXManualAccessibility or AXEnhancedUserInterface symbols. Saved main imports include AXIsProcessTrustedWithOptions. Main selected-text coverage is 16,301 / 16,301 functions. Dynamic lookup and runtime behavior remain outside this observation.

0x1000816c8 (ev_93b8806593e589b07e8d9ddcc9765b4d46e4e21a2ef643f5f40a844aa6dfdaf9) obtains NSWorkspace.frontmostApplication/processIdentifier and posts CGEvents to PID. 0x1000812cc takes an application object. 0x10004bff4 checks Accessibility trust and Secure Input before passing events to the engine. Neither proves per-field secure-role or text-range validation. The pasteboard chain 0x10002e138 is the plain-paste feature; it must not be presented as proof of selected-text conversion.

VSCodium was locally observed with editor.accessibilitySupport=off and inaccessible-editor labels. The owner explicitly requires preserving off; no editor setting was changed. Added AXManualAccessibility activation alone does not solve that barrier. No proprietary corpus/code was copied into the public model or product.

Independent design direction: feature/capability detection rather than guessed bundle allowlists. Distinguish readable text+range, actual empty proxy, unavailable text/range, and secure/unsupported input. Reuse verified replacement only for real evidence. A separate physical-input dispatch port can retain app/window/field identity, generation and bounded uninterrupted physical lineage; it must not invent an AX range. Navigation, mouse, shortcuts, focus changes, foreign synthetic input, Secure Input and permission loss invalidate pending evidence. Missing reliable field identity is a substantive limitation, not a reason to label PID-only state safe. Delivery is unverified until independently observed, with no blind retries.

Next measurement for VSCodium: raw role/subrole plus status/type/length metadata for AXValue, AXSelectedTextRange and AXMarkedTextRange on a disposable document, retaining off. UI role description alone is insufficient. Confirm identity transitions between tabs/fields and then exercise bounded manual dispatch. Automatic correction needs a separate acceptance policy; arbitrary selected text needs real selection evidence or a separately designed clipboard transaction. This investigation establishes an alternative architecture, not a finished or live-verified fallback.
