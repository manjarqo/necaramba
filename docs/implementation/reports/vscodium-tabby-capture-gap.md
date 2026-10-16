# VSCodium capture gaps and Tabby terminal proxy

User reports after phased physical release: VSCodium `рудlo rfr ltkf xtv занимаеimcz`; Tabby `ghbdtn рщц фку нщг`. VSCodium confirmed ordinary file editor, accessibilitySupport remains off.

## Observed evidence

Local trace `/tmp/necaramba-codium-live.log`, process88252 (2026-10-15):

-17:44:38.774 VSCodium focus changes from textarea to an unsupported role; editable token disappears.17:44:40.733 textarea returns at a new focus epoch31.
-17:44:41.441 automatic boundary arrives.17:44:41.544–41.576 sender posts exactly3 deletion pairs and3 insertion pairs, with stopReason0 and completion1. This is a two-character suffix plus delimiter, not a five-letter word. No sender interruption occurred in this operation. Correlation with the user's `рудlo` is strong but trace deliberately does not store text.
-17:45:23.727 Tabby attaches.17:45:28.181 preflight sees an empty input proxy;17:45:28.214 subsequent read rejects a readable range. No sender begins. Later reads reject suffix mismatch and nonempty tracked proxy. This is evidence rejection, not lost delivery.

## Causes and boundaries

Runtime previously cleared prefix distrust whenever a new focus epoch appeared, including after physically missed input. A suffix captured after recovery could therefore be treated as a new complete word. Missing-input state must survive recovery; it cannot authorize destructive manual/opaque suffix edits until a real observed boundary.

Tabby embeds xterm, whose `xterm-helper-textarea` is an input transport, not the terminal buffer. Installed packaged source forwards input events separately and can retain nonempty textarea residue. Recognizing this exact DOM class in the specific application permits opaque physical-history handling without pretending the residue is real editable text. Genuine selections remain unproven and cannot be converted by this proxy route.

## Implemented safeguards

- Missing ordinary input blocks manual suffix replacement and requires a readable word-start proof for automatic replacement. A new AX focus epoch alone does not clear the gap; an observed safe word boundary does.
- A gap with a known application is scoped to its PID and bundle. Command-Tab does not create a gap, and a proven switch to another application permits a fresh first word. Unknown-context missing letters remain conservative.
- Tabby proxy qualification requires exact `org.tabby`, an editable role, a validated `AXDOMClassList` containing `xterm-helper-textarea`, a collapsed range, a direct keyboard layout and existing authorization/composition checks. Nonempty helper residue remains opaque. Delivery remains `dispatched`, not a verified text commit.
- Diagnostics add fixed list/row/menu/menuitem categories and terminal-proxy matched/missing markers; no typed content or arbitrary class strings are recorded.
- Focus normalization can resolve an actual editable descendant through a direct `AXEditableAncestor` relation, rejecting malformed/secure candidates. It rereads the relation and system focus and verifies process identity. This does not establish ownership for a sibling completion list or authorize a cached textarea.

## Verification

- Capture-gap/app-switch tests: RED assertions then 72 focused tests passing (`/tmp/necaramba-gap-app-scope-green.log`).
- Terminal proxy: 15 focused tests passing (`/tmp/necaramba-tabby-proxy-green.log`). Initial RED was the missing helper API compilation, not a behavioral assertion failure.
- Editable ancestor: 12-test RED with 3 failures, then 13 focused tests passing (`/tmp/necaramba-editable-ancestor-{red,green}.log`).
- Full native suite: 520 tests, 0 failures, 1 optional private-model test skipped (`/tmp/necaramba-capture-final-tests.log`, 2026-10-15 18:33).
- After registering the fixed ancestor diagnostic: 22 targeted tests passed (`/tmp/necaramba-capture-diagnostics-tests.log`).
- Open-model release build succeeded, 96.6MB, x86_64 + arm64; strict deep signature verification passed (`/tmp/necaramba-capture-release-build.log`). Local version unchanged at 1.0.0 build 3. Restarted via CUA; PID 44371, UI reports active and automatic correction on. Ten-minute metadata diagnostics enabled for physical retest.

## Status

Preventing partial-word conversion does not by itself establish stable VSCodium focus or complete first-word conversion. The live unsupported VSCodium role/ancestor relationship and availability of Tabby's DOM class metadata still require physical-input acceptance. Tabby UI automation is unavailable and is not bypassed. No settings changes or commit/public release performed.
