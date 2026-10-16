# VSCodium / Tabby follow-up — 2026-10-15

User reports the physical-suffix implementation still fails in both applications. Previous unit tests and build validation do not establish host compatibility.

Observed: VSCodium with accessibilitySupport off exposes a settable editor labelled inaccessible. A disposable Untitled-1 document was opened without editing existing documents. The CUA focus description alone does not establish the raw AX metadata seen by Necaramba. Tabby UI inspection was refused by the computer-use tool; no alternate UI access was attempted.

Added bounded diagnostic opt-in via local application default InputDiagnosticsUntil (Unix expiry). It only enables the existing reviewed stage/code allowlist, never keyboard text or AX values, and expires after the shorter of remaining requested time or ten minutes measured monotonically. Invalid/expired deadlines do not enable tracing. Default remains off.

Validation: expiry test failed with two assertions before implementation; all 9 InputPerformanceMetricsTests then passed. Public-model local universal release build completed and strict deep codesign verification passed. Diagnostic build restarted. Live trace: /tmp/necaramba-codium-live.log. Requested physical VSCodium reproduction (manual double Shift and automatic Space); awaiting confirmation and correlated failure evidence. No compatibility fix is claimed at this stage.

## Reported VSCodium reproduction and recovery fix

The user confirmed manual/automatic failure. The captured session contains AX activation `-25204` (cannotComplete), observer registration `-25204`, unavailable system focus, and unqualified container roles. Earlier logging grouped all non-browser apps as `other`, so the exact application attribution of every line is not proven. It is not a valid basis for declaring all opaque fields unsupported or permitting blind PID-only edits.

A concrete code defect was reproduced: ChromiumAccessibilityActivation dropped failed initial activation without scheduling recovery. It now makes at most three attempts separated by 0.5 seconds, retains the existing 2.2-second successful-activation settling interval, and cancels stale generations. The system closure rechecks app PID, Accessibility permission, Secure Input and controller lifetime before every attempt. No editor settings changed. Added fixed diagnostic categories for VSCodium/Tabby and common unqualified roles to remove attribution ambiguity in the next capture.

RED: recovery, bounded retry and no-retry-on-unsupported-app assertions failed before implementation. GREEN: 10 activation tests passed. Full integrated suite: 482 tests, one optional private-model skip, zero failures (`/tmp/necaramba-activation-final.log`). This verifies activation recovery, not physical VSCodium acceptance; host observation remains required.

## Confirmed second reproduction: physical word lost on AX focus churn

With explicit VSCodium attribution (16:02:28 onward), activation first timed out then succeeded at 16:02:29.406. During typing, focus moved repeatedly from textarea to other roles and back. Double Shift was delivered at 16:02:39/40, and AX selection reads succeeded, but both operations ended in manual.wordMissing. Activation recovery was therefore necessary but insufficient.

Notification handling now synchronously reconciles real focus with ContextState safety hidden during the read, without preemptive epoch invalidation. Duplicate same-owner notifications preserve captured words; real changed/unavailable owners still discard them. The shared AXFocusedElementResolver also resolves a noneditable notification target's AXFocusedUIElement only when it returns an editable owner with Boolean AXFocused=true in the same process, and the system target remains unchanged on a confirming read. No cached owner, arbitrary tree search or PID-only text injection is used. Selection reads and monitor context use the same resolution path.

Reference semantics: [Chromium BrowserAccessibilityCocoa](https://chromium.googlesource.com/chromium/src/+/94b2b3987f70243fcc7b93c8fa32bd98fe21379a/ui/accessibility/platform/browser_accessibility_cocoa.mm) exposes manager.GetFocus through accessibilityFocusedUIElement; [VS Code textAreaEditContext](https://github.com/microsoft/vscode/blob/main/src/vs/editor/browser/controller/editContext/textArea/textAreaEditContext.ts) maintains aria-activedescendant for suggestions. Whether the installed host exposes that relationship must still be observed at runtime.

Tabby's exact bundle org.tabby was added to Electron AXManualAccessibility activation; [upstream packaging](https://github.com/Eugeny/tabby/blob/master/electron-builder.yml) establishes its identity. The UI tool remains blocked from Tabby, so no live Tabby success is claimed.

RED/GREEN: duplicate-focus tests 5 failures before repair; canonical-owner tests failed before routing/attribute implementation; Tabby activation test 2 failures before allowlist addition. Final full Swift run: 491 tests (343 Mac + 148 Core), 1 optional private-model skip, zero failures, `/tmp/necaramba-codium-tabby-final.log`. Independent reviewer found no concrete safety regression; added stability, malformed metadata, and direct-editable-focus regression checks.

Final public-model universal build succeeded (`/tmp/necaramba-codium-tabby-build.log`); strict deep codesign verification passed and lipo confirmed arm64/x86_64. Local app restarted (PID 36996 at observation). Requested fresh physical input to qualify notification/owner handling; old pre-restart word cannot exercise physical history. No commit, push or release.
