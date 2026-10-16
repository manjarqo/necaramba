# Caramba replacement delivery — 2026-10-15

Read-only follow-up to partial replacement reported as `рудlo` in VSCodium/Tabby investigation. Reuses retained REA/Ghidra arm64 evidence; no live REA server was available in this turn. No Caramba execution or product-code changes. Static behavior does not establish the cause of the reported runtime failure.

## Findings

| Stage | Caramba core correction | Current Necaramba |
|---|---|---|
| Layout | Select target input source, read current source, compare, bounded retries before deletion | Replace text first, select target layout afterward |
| Delivery | `22c820 → 22caa8 → 2a4d20 → CGEventPost(1, event)`; session event tap | `CGEvent.postToPid(context.pid)` |
| Text | Physical virtual-key codes and modifier flags from target event records | Unicode chunks of up to 16 UTF-16 units with virtual key 0 |
| Timing | Sleep before deletion and again before retyping | Deletion and insertion dispatched in one rapid batch |
| Browser workaround | Temporary Space then one additional Backspace for matched Safari/Brave/Chrome paths | Already represented by explicit browser profile |

The separate Swift PID-posting helper `0x1000816c8` is real, but is not the sender called by this core correction chain. It must not be cited as proof that automatic word correction uses PID-directed injection.

## Evidence ledger

- `decompiled/main-arm64/0x10022c820.c` and `0x10022caa8.c`: REA `ev_753b2a9116934a36b80240968ba17c28445d0a4f5e3315fa252f84331ce02e8d`. Target-layout loop, two waits, Space/Backspace stages, and target records with 32-byte stride, key code at offset0 and flags at offset8.
- `0x1002a4d20.c`, `0x1002a4d38.c`: `ev_9961908752ad1ed810679a79ef7b7cba951646a7a575b73c171c560a30c5049f`; CGEventPost and CGEventSetFlags wrappers. Caller passes location1. Explicit target modifier flags are set on keyDown in this chain; do not assume identical flags are explicitly set on keyUp.
- `0x1003949c4.c`: `ev_5c2481e9314b41118c43d43ff640864e8485823123bfbd6f32f07674a2bb8c61`; real nanosleep, with interrupted-sleep continuation.
- Retained `evidence/model-followup/model-neutral.json`, feats only: activation/backspace delay25, backspace/retype delay25, retries2, retry delay25. The decompiled correction uses the same delay local twice; arm64 instruction review confirms the same stack field at `[sp,#0x6c]` is loaded at `0x10022c928`, with the capped value reused for both waits. Do not claim this procedure independently consumes both named delay fields.
- `evidence/006-overview.json`: `ev_420bc1cb9f76be5f8a351239780b16a5ffb3307920e493bae6d26cfa97cb2db2`; retained arm64 SHA256 `814173224502cb0c40d8dadc01fa7f73c6fbcf98336067c10d9fc453780bf27e`.

Necaramba comparison: `Sources/NecarambaMac/Input/EventTapAdapter.swift`, `postReplacement`; `Sources/NecarambaMac/Input/NativeInputController.swift`, automatic correction result followed by `selectLayout`.

Additional raw-instruction verification (`xcrun llvm-objdump`, retained arm64 binary; no new REA Evidence ID): import stub `0x1003c43a8` is `_TISSelectInputSource`, called at `0x10022c8b4/904`; the decompiler’s Swift-looking import label is misleading. Model buffer starts at `sp+0x38`, so the shared delay field is at model offset `+0x34`. Down/up creation passes true/false at `0x10022cad0/caf0`. Physical key mapping in `0x100229f60 → 0x10022acd4` uses `UCKeyTranslate`, with dead-key state. `0x1003a9450` counts UTF-8 non-continuation bytes (REA `ev_3c306b6a7dd4ba51b3f83fb744b8083b09b9cc9c57ed5ce75062d0da3a99c1e4`).

## Interpretation and implementation direction

The delivery differences offer a concrete hypothesis for partial text replacement: editor event handling may differ for rapid PID-directed Unicode insertion versus session-level physical typing with layout settled first. Static evidence cannot distinguish lost deletion, input interleaving, host composition, or incorrect physical-word history in the reported example. Unconverted words also require distinguishing classification rejection from failed delivery; they do not prove a missing dictionary entry.

Implement an independently written phased replacement strategy for affected hosts: capture and validate physical suffix and target key sequence; acquire bounded input ownership; activate and confirm target layout; wait a bounded settling interval; delete; wait; replay physical key pairs through the session route; finish with readback where available. Revalidate application, focus, Secure Input and cancellation between phases. Do not sleep on the event-tap thread. Preserve user-input ordering while the operation owns input. Do not perform a second destructive attempt after an ambiguous dispatch.

Unlike Caramba’s observed fallthrough after layout retries are exhausted, stop before deletion if target layout cannot be confirmed. Do not transplant its unverified codepoint deletion assumptions into arbitrary Unicode text. Keep proven Unicode replacement for cases that cannot be expressed as supported physical keys.

Validation must cover both directions, repeated double Shift, automatic boundary conversion, typing during replacement, focus change between stages, wrong layout confirmation, and Secure Input. Real physical-key acceptance is still required in VSCodium and Tabby, plus Safari/Chrome regressions. No runtime fix or host acceptance is claimed by this research.
