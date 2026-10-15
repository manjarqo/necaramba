# Intermittent input recovery

2026-10-15. User reports that single Shift and automatic correction stop across applications, a retry after one second does not help, and both recover after approximately 20–30 seconds.

## Evidence and limits

The running application showed both features enabled. Redacted stage logs include successful single-Shift deliveries and automatic replacements, along with repeated `context.refresh.systemFocusUnavailable` failures. This does not establish permanent tap shutdown or a dictionary defect. Offline classification gives `gthbjlbxtcrb` a score of −16 and `периодически` zero; the selector can prefer the Russian candidate without a known-word assertion.

A deterministic code-level recovery gap exists: when AX notification registration succeeds, `FocusRefreshPolling` previously refreshed once and installed no fallback timer. A transient failed read invalidates cached editing and gesture context. Without another notification, neither command path can recover its context.

A second mechanism could explain long pauses: observed refresh hides cached context during reconciliation, and commands execute on the main queue. A stalled refresh/main queue can temporarily prevent both features. No live stack was captured during the user's stall, so its cause and duration remain unproven. AX system-wide messaging timeout is already bounded; absence of a separate timeout on a returned element does not establish a default 20-second delay.

Do not weaken editing evidence, bypass secure input, or assume missing-word data explains a global stall. Add recovery for the proven notification gap and redacted timing/tap lifecycle diagnostics to distinguish a future incident.

## Change

A 250 ms recovery timer now remains installed with registered focus notifications. A cached pending-recovery flag enables authoritative AX retries only after a failed resolver/role read. Successful noneditable observations clear that flag too. Secure Input or missing permissions pauses AX requests while retaining the pending recovery, so the next eligible tick can recover without a new focus notification. Timer generations suppress callbacks after stop or reattach; editing never uses stale evidence.

Redacted diagnostics now include slow refresh duration (100 ms and above), focus lost/recovered, and tap disable/re-enable/stop events. They contain no typed text. Tap retry limits and security policies are unchanged.

## Verification

Full Swift suite: 263 Mac tests (one optional external-model test skipped) and 125 Core tests, zero failures. Local optimized universal build succeeded with the same model digest; strict deep signature verification passed. The application was restarted. The original intermittent 20–30-second incident has not been reproduced physically, so the change is verified for the recovery gap, not claimed as proof that every global stall is resolved.
