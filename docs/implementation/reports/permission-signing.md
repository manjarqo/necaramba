# Permission status versus signing identity — 2026-10-14

The user enabled Necaramba in System Settings, but all native permission preflights remained false, including after restarting the same binary. The visible switch was on. The UI was faithfully rendering the native result; a second restart did not repair it.

Root cause confirmed by the macOS tccd log: `Failed to match existing code requirement for subject local.necaramba.app` for both ListenEvent and Accessibility. The saved ListenEvent requirement was cdhash 49ee8bd63860de890d94dc2fb544aeb0b441da5c, matching the Debug Runner test host. Accessibility referenced an older Release's hashes 30bd59e2bb2bf4ed4297323850f49d4a10cfc6ff/041a1e0193acd094e71bda69c549c928e9a7f76e. The actual Release executable had d84b70d3b673d97bd072e2cd3184f8e967a5567f/decf0c1a4e1bfb05dfd5717b07a451f39f278f02. Both variants had shared bundle ID local.necaramba.app and ad-hoc signatures. `codesign --verify --strict` passed: this was identity mismatch, not a corrupt signature.

Apple DTS explains why TCC needs a stable signing identity: https://developer.apple.com/forums/thread/663889 . A read-only attempt to inspect the TCC database was denied; no access workaround, permission reset or database mutation was attempted. The unified log provided the necessary evidence.

Fix strategy: give Debug/Profile separate application identities, configure local Release with the owner's existing Apple Development signing identity through an ignored local configuration, and retain DeveloperID/MAS overrides. Existing grants refer to old ad-hoc identities and need a one-time user-driven remove/re-add of the current app. The UI must continue to report denied until native APIs actually grant access; refresh now needs explicit feedback and recovery instructions, not a fabricated green state.


## Verification

- Configuration regression: three real Xcode build-settings tests passed, including optional local settings, Debug/Profile isolation and distribution/CLI overrides.
- Flutter analyze passed; all 49 Flutter tests passed after integration. Follow-up regressions cover unrelated native revisions and automatic lifecycle refresh retaining the acknowledgement, plus capability changes clearing it.
- Scoped independent review of signing and initial feedback found no actionable issues.
- Actual `flutter build macos --release` succeeded (60.5 MB). `codesign --verify --deep --strict` passed. The app is universal x86_64/arm64, signed with the owner's existing Apple Development certificate, team H2NWX8R287. Its designated requirement uses the bundle identifier, Apple anchor and certificate identity instead of an ad-hoc binary hash.
- Launching the signed artifact still reports missing permissions, as expected while TCC stores the old requirements. No permission was granted or reset during verification. One-time user removal/re-addition of stale entries remains necessary.

- Final rebuild succeeded; deep/strict signature verification passed again with the same certificate-based designated requirement. Scoped review of the two feedback follow-ups found no actionable issues.
- Final running Release UI was observed displaying “Проверено. macOS пока не предоставила доступ этой копии Necaramba…” and recovery instructions. All three native capabilities remained denied. The final device grant/regrant step is intentionally left to the user.
