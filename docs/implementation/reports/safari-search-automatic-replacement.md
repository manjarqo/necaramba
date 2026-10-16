# Safari search automatic replacement — 2026-10-15

## Report and evidence

User reports 2 incorrect results in 30 physical attempts in GitHub Releases' **Find a release** search field: Russian-layout `руддщ` + Space became `руда`, rather than `hello`.

Only Necaramba was running among the inspected switcher processes. The production automatic path posts separate Backspace pairs followed by Unicode insertion. System search overlay manual conversion already avoids this path by selecting and verifying the exact suffix range. Automatic conversion never invoked that selection preparation.

A deterministic reactive-field test demonstrates that the automatic path bypassed preparation and dispatched destructive suffix editing, leaving a partial/unexpected value. Both new tests failed before the change (7 assertions), then all 61 AX selection proof tests passed. This is a model of the vulnerable delivery sequence, **not a reproduction proving the exact cause of the two physical incidents**. Browser spelling correction, host processing and scheduling remain possible contributors. A synthetic CUA text insertion is classified as foreign input and is not a substitute for physical autocorrection testing.

## Change

Allow automatic boundary operations to invoke the existing suffix selection preparer. The system preparer opts in only for Safari search subrole fields, in addition to the existing manual overlay case. It verifies the same identity, original value, caret, authorization, current focus and secure-input state, sets the exact range, then requires exact readback before posting a selected replacement. Selection failure or unproven selection aborts; it never falls back to Backspaces after attempted selection. Other editors retain their delivery strategy. No dictionary/rule changes, sleeps, extended leases or retry mutations were introduced.

## Qualification

The physical 30-attempt GitHub search scenario still needs repetition after the local rebuild. This change is a targeted mitigation of the demonstrated multi-event deletion risk, not proof that the intermittent incident has been eliminated. The published Beta 3 archive remains unchanged.

Final automated checks: 457 Swift tests executed, 1 optional private-model skip, zero failures. Public-model universal Release build and strict deep signature verification passed; updated local app restarted and reports active. No commit or publication for this mitigation.

A CUA selectText/typeText probe on the live GitHub field did not establish correct delivery: readback settled to a space instead of the requested hello. The test text was cleared. This synthetic UI probe does not traverse physical input lineage and is not recorded as a successful host qualification. Physical confirmation remains required.

## Superseded delivery strategy

Later on 2026-10-15, the user requested the browser method identified in Caramba. Automatic Safari range preparation was replaced by a temporary-Space/extra-Backspace sequence with ordered intermediate readback checks. See `physical-input-browser-delivery.md` for the current implementation and validation. Manual Spotlight range preparation remains.
