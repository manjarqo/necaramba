# Zen page accessibility activation

2026-10-15. Safari version conversion now works according to the user; Zen's currently open page still does not convert `1ю3ю166`.

## Evidence and change

The visible Zen page contains a search input holding the version, but the native accessibility snapshot contains only browser chrome and no web document or input. The existing application activation allowlist covers Chrome and Spark, not Zen. Manual gestures in the reported interval reach runtime dispatch without reaching a qualified editable manual context.

Add the exact stable bundle `app.zen-browser.zen` to the existing `AXEnhancedUserInterface` activation path. Mozilla describes this Gecko activation mechanism in https://bugzilla.mozilla.org/show_bug.cgi?id=1664992. Keep delayed context refresh, cancellation, and all existing focus/security checks. Do not alter browser preferences, enumerate arbitrary descendants for editing, or broaden supported editable roles.

## Verification

The new regression test first failed on missing attribute, missing activation, and missing refresh. After the change all six activation tests pass. Root validation of activation, focus recovery and polling: 13 tests, zero failures. Logs: `/tmp/zen-activation-red.log`, `/tmp/zen-activation-green.log`, `/tmp/zen-accessibility-tests.log`.

Local universal release build completed (`/tmp/zen-accessibility-build.log`); strict deep signature verification passed. New process 48297 launched through the GUI.

On Zen activation at 11:53:09 the attribute call returned cannotComplete at its existing 100 ms deadline, but the application subsequently obtained a qualified search-field context. Do not equate that timeout with no remote side effect. At 11:53:13 selected conversion, 11:53:18 seven-character tracked conversion, and 11:53:19 repeat conversion all logged confirmed AX readback and manual success. The current page's URL search parameter changed from the Cyrillic version to `1.3.166`. These gestures came from the user; automation cannot generate standalone Shift presses. The automation tree still omits page content, so use the app's authoritative readback as the verification evidence, not a claim that the automation snapshot now exposes the page. No broader browser compatibility claim is made.
