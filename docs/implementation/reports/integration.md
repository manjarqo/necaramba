# Native/Flutter integration — 2026-10-14

Clean boundaries: Core contains value types/policies and ports; Mac adapters implement SQLite, permissions, TIS, clipboard, image/audio, login and input. ApplicationServices composes use cases; NativeCommandCoordinator serializes a versioned wire contract. Flutter domain ports have data channel adapters and feature presentation modules, one authoritative snapshot Cubit.

Native bridge tests cover queued request idempotency, stale-session/revision rejection, unknown commands and redacted errors. Full Swift suite passed before runtime/corpus additions; targeted archive tests21 PASS, release tests2 PASS, window adapter test1 PASS. UI fix report records35 PASS and analyzer clean. Latest integrated `flutter build macos --release` PASS45.8MB; helper embeds universal macOS12 binary, own WAV copied, no third-party assets.

Preferences are now authoritative in own SQLite application_preferences table; UserDefaults is a migration input/mirror. Rule/preference archive validates first and commits in one SQLite transaction; duplicate conflicts preserve both old rules and preferences. Postcommit preference adoption does not perform another database write. Login preference import does not register OS login without explicit user action.

Native window creates Flutter engine only when opening settings, detaches channels and shuts engine down on close. Native services continue without Flutter. Opaque image-drop handles are engine-local, bounded and expire. Common palette has25 independently selected colors.

Own local app UI was opened with CUA: Russian dark/narrow layout, navigation and native permission page were visible. Listen/post/AX all false; no permission was granted, login enabled or user data inspected. RSS samples90MB open and85MB following close, CPU0% at one sample; these are exploratory samples, not E4 or performance acceptance. Full reopen100cycles and physical typing tests remain UNRUN.

Input facade is connected but default denies unqualified editors and automatic corpus gate is false. Runtime review found incomplete edit ownership, manual priority and interception; assigned fix round. Current code is not a full functioning analogue and must not be released. Independent corpus holdout recall80.867% fails95%; no fake readiness.

Release gate rejects missing tuples/evidence. Production identity/signing/notarization, endpoint, commercial product configuration, native Intel/macOS12 host matrix and MAS feasibility remain blocked/unrun. Config files are templates, not tested release configurations. No release or network purchase/share occurred.

## Delivery/runtime integration followup

Integrated build with verified independent development bundle: `flutter build macos --release` PASS60.0MB. Full integrated Swift tests:82 Mac +60 Core PASS, zero failures. ApplicationDeliveryTests2PASS bind exact preview payload/UUID and reject replayed consent, plus disabled-config services; no real sends/purchases. RuleUpdateCoordinator uses main-actor adapter and active model version is published only by runtime install completion, after off-main index construction. Own default sound and aggregate counters use committed edit IDs; background input keeps Dart closed. Actual production endpoints/IDs remain absent and disabled. Status/menu actions retain native authority; RU/EN menu strings and conventional Settings/Close shortcuts added.

Runtime first safety review fix is integrated, with post-edit proof and tap-confined bounded key-event ownership; scoped rereview is ongoing. Physical/editor qualification remains UNRUN, so default-deny is retained. Development rule packages have an explicit marker that artifact verification rejects for release.

## Real launch failure found

Local UI launch of the60MB prototype exposed a deterministic startup trap not covered by fake-only tests. Own crash report2026-10-14-101508: `EXC_BREAKPOINT` on `Necaramba rules compiler`; stack `_dispatch_assert_queue_fail` → `TISCreateInputSourceList` → `TISLayoutAdapter.sources/supported/resolveMappings` → `NativeInputController.install`. The background compiler calls Carbon input-source APIs requiring the main queue. Task owner is fixing capture-on-main versus immutable index construction off-main. No TCC grant or typed user text was involved. The prior build PASS is compilation evidence only; runtime acceptance failed and is not cleared until a fresh app launch succeeds.
## Integration safety fix round 1 — 2026-10-14

- Header image drag reads a file URL first with `FileHandle.read(upToCount: 10 MiB + 1)` and refuses oversized data. TIFF-only pasteboard providers fail the drop because AppKit's `data(forType: .tiff)` eagerly materializes their unbounded payload. Three Runner tests cover TIFF-only refusal, bounded file URL acceptance and oversized file URL refusal; execution is pending the generated Flutter Xcode package in the integration worktree.
- Login preference write failure restores the previous OS login status through the injected backend. If restoration fails, the native `partialFailure` response and `onChanged` publication expose actual system status while the old stored preference remains. No real login item was touched.
- File-panel mutations (`importArchive`, `chooseApp`, `chooseSound`) receive a bridge revision guard checked immediately before commit, after the panel continuation. A delayed archive import test changes native revision while the panel waits and verifies old rule and preference data remain. Existing AppDelegate forwarding passes the guarded argument map without a wiring change.
- Release CLI now hashes the named final artifact, hashes each evidence file, and requires its JSON metadata to match the entire tuple and artifact SHA256. Draft manifest has concrete macOS major versions 12/13/27 and named TextEdit, Safari, Chromium, Electron and Necaramba hosts. The draft report remains blocked; no release evidence was created.

Evidence: initial `swift test --filter 'NativeCommandCoordinatorTests|ApplicationServicesTests'` was RED at compile time because the test-only preference write injection did not exist. With the original coordinator temporarily restored, `swift test --filter testDelayedImportRejectsNativeRevisionChangeAtCommit` was RED: stale import committed (three assertion failures). `python3 Tools/Release/test_validate_release_report.py` was RED with four false acceptances for wrong OS, host, adapter and artifact. After changes, `swift test --filter 'NativeCommandCoordinatorTests|ApplicationServicesTests'` passed 11 selected Mac tests with zero failures; the release CLI fixture passed five tests, including a positive fixture. `swift Tools/Release/validate-release-report.swift docs/release/release-report.json` exited 1 as required for the unfilled draft. `git diff --check` and `swiftc -frontend -parse` of both Runner Swift files passed. Focused `xcodebuild ... test -only-testing:RunnerTests` could not resolve the absent `App/macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage`; Runner tests and full Flutter build are UNRUN in this worktree. This is not device, Intel, macOS12, real drag, login, TCC or release acceptance evidence.

## Integration safety fix round 2 — unknown login status

The macOS 12 legacy login API cannot query registration, so `SystemLoginBackend.status()` remains `unavailable` even after a successful `SMLoginItemSetEnabled`. If persisting the matching preference fails, `ApplicationServices` now publishes `partialFailure` for any previously unknown status even when the before/after status strings match. It leaves the old preference intact and publishes a new state revision through `onChanged`; no real login item was used in the test.

RED: `swift test --filter testUnknownLoginStatusAfterOSActionPublishesPartialFailure` failed with the underlying `persistence` error from the old branch. GREEN: `swift test --filter 'NativeCommandCoordinatorTests|ApplicationServicesTests'` passed 12 selected Mac tests with zero failures. This is a fake-backend unit check, not macOS 12 device qualification.

## Integrated verification after review fixes

Startup regression cleared on the local arm64 macOS27.0.1 host after commit `a466558`: Release60.1MB app remained running, the Rules screen displayed active version1 and current status. TIS data is captured on main; only immutable tables and index compilation cross to the background queue. Closing and reopening settings rendered the Flutter UI again; the second engine accessibility tree was incomplete, so accessibility lifecycle acceptance remains open for final review. No TCC grant or login registration was performed.

Integrated suite at `5d0061d`:100 Mac +63 Core tests PASS; Flutter36 tests PASS and analyzer clean. Subsequent unknown-login-status fix has its focused regression. Runner test host/module names were aligned to the actual Necaramba product; `xcodebuild test` then passed all3 bounded-drop tests on the local arm64 host. ReplayRunner passed exact ordered pass-through for100000 events and ownership replay for100000 events. Release CLI regression fixtures5 PASS; these synthetic reports are not release qualification evidence.

These checks clear the observed startup trap and scoped integration findings. They do not qualify automatic corrections, real editor mutation, macOS12/Intel behavior, production signing, purchase services or release performance budgets.

## Final reviewed integration

Final scoped architecture review approved injected application ports (`b647b97`), normal+legacy exclusion publication (`506f06f`), ordered live entitlement snapshot/update revisions (`f217c4b`), real channel configurations and validated production-package staging (`e38a9e4`). No Important findings remain from those code reviews. Production package fixtures pass signature/hash/schema/key/development-marker/license rejection checks using temporary test keys; no production signing identity was created.

Fresh whole native suite after these application changes:106 Mac +63 Core =169 tests PASS. Flutter remains36 tests PASS and analyzer clean (no Dart changes after that run); Runner3 tests PASS. Final `flutter build macos --release` PASS60.3MB. Main executable, embedded login helper, FlutterMacOS and App frameworks each verified arm64+x86_64 with minOS12.0 via lipo/vtool. The final app was launched with CUA and showed model1/current and permission-required status. No permission or login setting was changed.

Fresh `Reports/review-v3-final-quality.json`:8459 cases, TP3147, FP0, FN493, layout recall0.808688387635756; quality gate FAIL and physical differential UNRUN. The draft release report still exits1. TIFF-only drag and repeated-engine accessibility acceptance remain open; see `docs/implementation/acceptance-status.md`. This is an internal prototype, not full functional parity or a qualified release.
