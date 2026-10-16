# Opaque editable-field physical input fallback

User approval: implement additional delivery path, preserve VSCodium accessibilitySupport=off. Existing Safari mitigation and published model remain intact unless a separately requested browser delivery strategy supersedes them.

## Contract

Distinguish verified readable suffix from unverified physical suffix delivery. A real focused editable AX element, its identity, context generation, permissions, direct keyboard layout and Secure Input checks remain required. No PID-only global typing. Do not synthesize empty text/zero selection as if observed.

Opaque capability: value is genuinely empty or explicitly unavailable; selection is genuinely collapsed or explicitly unavailable. Preserve unavailable states. Any positive nonempty selection, nonempty unmatched value, malformed attribute, timeout, composition, changed identity or stale generation rejects dispatch. Missing attributes alone do not authorize mutation: require bounded uninterrupted physical word lineage and an explicit manual command or validated physical Space auto-boundary. Navigation, foreign input, focus/layout changes invalidate lineage through existing runtime.

Use a dedicated physical suffix mutation transport (delete count, replacement, real context/generation), distinct from SelectionEvidence. Retain guarded event posting, ownership/deadlines, no blind retry. Report dispatched, never committed, and do not journal/count unverified changes. Repeated manual conversion retains original physical lineage and real field identity; unavailable selection is not a selected-text conversion feature. Editor-side transformations remain a residual uncertainty.

## Work

1. RED tests: opaque attributes, boundary validation, missing/changed identity, nonzero selection, malformed/timeout, cancellation and repeated conversion.
2. Domain contracts and native capability reading, with no broadening of editable role allowlist.
3. Separate native posting entry point and controller wiring for manual/auto/repeat.
4. Independent source review, focused and full Swift tests, public-model universal build/signature.
5. Restart local app; preserve off; distinguish synthetic testing from physical host qualification.

The user additionally requested the method identified in prior compatibility research. Implement temporary Space followed by one additional Backspace for exact Safari/Chrome/Brave suffix routes, with transient insertion/deletion represented in readback proof. This supersedes the earlier automatic Safari suffix-selection mitigation. Never treat post success as observed success or combine selected-range replacement with suffix Backspaces.
