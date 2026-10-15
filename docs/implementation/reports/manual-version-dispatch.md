# Manual version dispatch follow-up

2026-10-15. User reports that `1ю3ю166` still does not convert to `1.3.166` after double Shift.

## Evidence

The latest captured attempt at 10:51:49 reports manual word length 7, a valid mapping, matching reconstructed physical text and an empty AX proxy with zero selection. AX preparation reaches dispatch, then returns `uncertain` roughly 12 ms later. Earlier attempts reported no captured word; these are separate failures and are not explained by a mapping change.

`EventTapAdapter` formerly permitted only 10 ms for a destructive key batch. Seven deletions followed by one insertion require eight complete down/up pairs. A deterministic fake-clock reproduction at one millisecond per event reaches that limit after five deletions and cannot post the insertion. This proves the cutoff can interrupt an ordinary version replacement, although the original runtime lacked a reason code to prove which safety check failed in that particular attempt.

The numeric manual-capture fix remains necessary and is working in the seven-character attempt. Its original tests used a replacement double and therefore did not cover this posting-budget failure.

A related recovery defect exists: controller quarantine directly invalidated `ContextMonitor.state`, bypassing the pending-recovery flag. Subsequent commands could remain unavailable until another focus notification. Recovery must obtain fresh evidence and must never retry a partially dispatched replacement automatically.

## Changes and verification

Posting now uses the remaining budget of the existing 100 ms ownership lease instead of a separate 10 ms limit. Context, generation and Secure Input are checked before each complete event pair; releases always follow posted downs. The 200 ms outer wait remains unchanged. No remote AX call or automatic mutation retry is added. Diagnostics record only stop reason, pair count and elapsed time after posting ownership ends.

Controller invalidations now call an explicit monitor recovery method. It clears old editable/gesture evidence and automatic eligibility, arms authoritative refresh, and respects permission/Secure Input gates. It never resubmits the failed edit.

The regression tests reproduce a 16-event version batch, verify its completion at 16 ms, confirm an already-expiring ownership lease is not renewed, and retain cancellation on generation/context/security changes. Full Swift suite: 269 Mac tests (one optional external-model skip) + 125 Core tests, zero failures. This covers the concrete dispatch defect; physical reproduction still needs the user's check.
