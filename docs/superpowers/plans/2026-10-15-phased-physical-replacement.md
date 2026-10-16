# Phased physical replacement

User authorized the four delivery changes from the Caramba research: target layout activation/readback before mutation, physical key replay, session-level posting, 25 ms settling before deletion and retyping. Implement independently; no proprietary model data is added.

## Acceptance

- Automatic correction, manual suffix conversion, repeated conversion and selected conversion all use the physical route when the target text has an unambiguous supported key sequence.
- Target layout must be confirmed before any destructive event. Failed confirmation aborts without deleting text.
- Settling uses asynchronous scheduling, never a sleep on the event-tap executor.
- Input ownership spans destructive phases; physical input is ordered safely, with bounded buffering/deadline. A partial send is uncertain and never retried destructively.
- Focus, application, Secure Input, cancellation, layout and physical generation changes stop unsafe continuation.
- Own session-posted events are marked and excluded from physical word tracking.
- Existing readback remains the distinction between verified commit and unverified dispatch. No fabricated AX evidence.
- Unsupported physical mappings cannot silently emit wrong keycodes; retain explicit safe fallback where appropriate.

## Work

1. Map layout epochs, AX evidence and input ownership to the new sequence.
2. Add regression tests and observe failure for missing physical replay/phase ordering.
3. Implement preparation, activation, pauses and session delivery with existing architecture boundaries.
4. Check failure before deletion, interruption after deletion, changed focus/layout, repeated conversion and queued input.
5. Run native regression suite; build universal local open-model release and verify signing.
6. Restart local application for physical-key acceptance in VSCodium/Tabby and browser regression checks. Automated tests do not establish real host acceptance.

No version bump, commit or public release is part of this change.
