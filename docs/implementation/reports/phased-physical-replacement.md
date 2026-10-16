# Phased physical replacement implementation

User-approved behavior: activate and verify target layout before mutation, then 25 ms settling, deletion, 25 ms settling, and physical-key session replay. Research basis: prior compatibility research.

Implementation complete; native automated checks and local release packaging passed. This report does not claim host acceptance.

## Design decisions

- The async production controller verifies target layout before acquiring fresh mutation evidence. It permits only a layout-epoch rebase when PID, bundle, focused-field epoch and physical input generation still match.
- The captured target layout maps the full output to printable physical keys. Enter, Tab, navigation and other action keys are excluded. Unsupported selected text retains the Unicode route; no partial mapping is sent.
- A tap-owned staged scheduler waits25ms before deletion and25ms before retyping. Own events carry the existing marker and use a private event source. Ownership revision prevents an old callback from cancelling a newer operation.
- Session-wide posting needs foreground stability in addition to focused-field identity. The expected foreground application is tracked separately from the focused process so Spotlight overlays remain supported.
- Foreground validation uses the supported NSWorkspace API on the main thread; no deprecated Carbon process bridge is introduced. Apple documents frontmostApplication as the application receiving key events: https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication .
- The synchronous legacy coordinator is outside the async production execution path; the new sequencing is applied to runtime async operations.


## Regression findings during integration

The first full run exposed a pre-existing test-only handshake race in ApplicationDeliveryTests: a fixed count of Task.yield calls could finish before startup installed its snapshot continuation, then release was lost. The fake now uses bounded event expectations and a retained release flag; production service code is unchanged.

The next full run exposed two automatic-correction regressions from changing layout before rejecting an untrusted word start. A readable-field counterpart reproduced the same issue even when the suffix itself matched. Automatic eligibility must therefore be checked read-only before layout activation, and checked again before mutation; a suffix match alone is insufficient for URL/appended-word prefixes. Regression tests assert unchanged text and unchanged layout after rejection, followed by successful correction of a fresh word.

## Physical-key acceptance checklist

Use a disposable empty input; do not use personal documents. VSCodium accessibilitySupport stays off.

- In VSCodium and Tabby: type `ghbdtn` with English layout, press double Shift, expect `привет`. Repeat double Shift at least20 times; alternate exact original/converted text.
- Type `руддщ ` in Russian layout; expect `hello ` automatically. Repeat in fresh empty inputs and after previous words.
- Type multiple words quickly through the correction boundary. Verify no lost, duplicated or mixed-script suffix caused by interleaved replay.
- Select mixed text and convert; verify selection boundaries and punctuation remain intact.
- Regression in Safari address bar and GitHub releases “Find a release”, Chrome text field, and Spotlight. Repeat both directions.
- Numeric dotted text: Russian `1ю3ю166` should convert to `1.3.166` on double Shift.

Automated safety checks must cover rejection before deletion when target layout fails, context changes after activation, cancellation or ownership expiry after deletion, held input ordering, and synthetic event exclusion. No destructive retry is permitted after uncertain delivery.

## Automated verification

- Native full suite: `NSUnbufferedIO=YES swift test --scratch-path /tmp/necaramba-perf-final-validation`, exit0. 360 Mac tests (one optional private-model test skipped) and148 Core tests, zero failures. Log `/tmp/necaramba-phased-verified.log`.
- Sender focused:17 tests, zero failures, `/tmp/necaramba-phased-final.log`. Wrong navigation-key mapping was observed failing before the whitelist fix. Initial new API checks failed compilation before implementation; these are not described as behavioral RED.
- Controller focused:39 tests, zero failures; automatic/readable-prefix and real AX subset132 tests, zero failures. Readable-prefix regression first failed two assertions, `/tmp/necaramba-readable-prefix-red.log`, then passed `/tmp/necaramba-readable-prefix-green.log`.
- Shared test-fixture handshake:5 ApplicationDeliveryTests passed, `/tmp/necaramba-delivery-handshake.log`.
- `git diff --check` passed.

Production runtime uses the asynchronous coordinator. No public release, version bump or commit was made for this change.

## Local release verification

Open-model release built successfully with `NECARAMBA_OPEN_MODEL=YES` and no local pattern model override, build1.0.0+3. Log `/tmp/necaramba-phased-build-final.log`. `codesign --verify --deep --strict` passed; executable contains both x86_64 andarm64. Restarted the local build through the app UI and observed status “Активен”, automatic correction enabled. Physical host acceptance remains pending; synthetic computer-use typing does not substitute for physical-input lineage.
