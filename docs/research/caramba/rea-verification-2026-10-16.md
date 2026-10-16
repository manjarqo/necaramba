# REA verification of the Caramba/Necaramba comparison (2026-10-16)

Target: `evidence/binaries/caramba-arm64`, Mach-O arm64, sha256 `814173224502cb0c40d8dadc01fa7f73c6fbcf98336067c10d9fc453780bf27e`.
Engine: REA 6.5.0 MCP, Ghidra 12.1.4, analysis profile digest `966e6016724421ad282356f583a9d5bf24577db4ac77a75c7099d236b88bcc28`.
Snapshot: `evidence/caramba-arm64.rea-ghidra-12.1.4.snapshot` (git-ignored; reuse with `open_binary` `snapshot_path`).

Static analysis only. Nothing was executed; the installed Caramba was not touched.

## Finding ledger

| # | Claim | Status | Evidence | Boundary |
|---|---|---|---|---|
| 1 | Field text is never read through Accessibility | Observed | `ev_a62877a2…` imports: only `_AXIsProcessTrustedWithOptions`; `ev_7222a609…` no `AXUIElement`/`kAX…` strings | Defined strings and procedure names only; packed or computed `dlsym` names are not excluded. `dlsym` has 41 call sites, unexamined. |
| 2 | Active HID-level keyboard tap, gated on AX trust | Observed | `ev_dd07af72…` `FUN_100049b20`: `CGEventTapCreate(0, 0, 0, 0x1c06, FUN_100049bec)` after `AXIsProcessTrustedWithOptions` | Mask = mouse down/up, key down/up, flags changed. The second call site `0x1001ac6a0` was not examined. |
| 3 | Replacement posts key codes only (no Unicode transport) | Observed | `ev_a62877a2…` no `CGEventKeyboardSetUnicodeString` import; `ev_988d27e8…`/`ev_3869ec6e…` key pair → `CGEventPost(1, …)` (session tap) | |
| 4 | Layout is switched through `TISSelectInputSource` | Observed | `ev_a128de69…` stub `0x1003c43a8`, callers `0x100224de4…0x10022c904` | Retry and verification logic not re-examined. |
| 5 | Selection conversion uses the pasteboard with fixed 200 ms blocking waits | Observed | `ev_d909a7e2…` `FUN_10022b95c`: save → clear → post keys → `nanosleep` 200 ms (`ev_62e9eb56…`) → read → convert/select layout → write → post keys → 200 ms → restore | Which keys are posted (Cmd+C/Cmd+V) is inferred from `caramba_selection_switch`, not traced to key codes. The executing thread is unknown. |
| 6 | Saved and restored pasteboard content is string-only; no `changeCount` check | Observed | `ev_95e5880c…` read = `stringForType:`; `ev_81b8b360…` write declares only `NSPasteboardTypeString`; `ev_4a559cae…` no `changeCount` selector string | Non-string content (images, RTF, files) is therefore replaced by the restored string or lost — inference from code, not observed at runtime. `pasteboardItems` exists elsewhere; its use was not traced. |
| 7 | Core is written in Rust (objc2-style bridge) | Observed | Rust panic strings, `rustc_…` and `…/.cargo/registry/src/…` paths in `ev_2e9cd1a1…`, `ev_81b8b360…`, `ev_62e9eb56…` | |

Not re-verified with REA in this pass (sources are the earlier reports in this folder): pattern classifier size and weights, typo/ё rule counts, per-application policy table, word-boundary keys, CLM1 model format, Spotlight overlay handling.
