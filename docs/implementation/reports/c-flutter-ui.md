# C3/C4, C5 presentation and E3 Flutter flows

2026-10-14. Isolated `.worktrees/ui`; Flutter presentation/domain-use-case/localization ownership only. No Swift Runner changes, platform wire protocol changes, installed Caramba access, real TCC changes, login item changes or personal-store access.

## Implemented

- Composition supports injected NativeRepository, locale and WindowInteractionPort. Cubit owns the native snapshot reducer, stream lifetime, pending-command set, connection/error state and bounded thumbnail. UI never optimistically writes preferences or rows; failed operations preserve native truth and drafts. Stream failure disables writes until authoritative reconnection. No automatic share or purchase retry.
- Eight preference toggles, documented Double Shift behavior, independent listen/post/AX/Secure Input onboarding; permission requests only follow explicit buttons. Activation refreshes capability truth.
- Word addition/deletion, confirmed clear, full legacy values/labels and separate application rules identified by bundle ID. Native .app chooser, allow/deny and confirmed application deletion. Failed word validation retains draft. No add-then-delete pseudo-edit: integrator explicitly removed it because Wire v1 lacks an atomic edit command. Original C3 add/delete/clear flows are supported.
- Own 25-color header palette and reset, image thumbnail refresh/removal, opaque native image drop hook, native sound chooser/reset. HeaderDropRegion reports only the visible header rectangle in logical Flutter coordinates, including resize, and null on disposal; WindowInteractionPort receives only opaque handles, never paths. Root owns the window-channel adapter/real native overlay. Drop import failure remains visible; session changes clear stale image thumbnails.
- Rules version, freshness/check state/manual update, explicit rule draft and immutable sharing preview with exact word/language/modelVersion/feedback/destination host. Send confirms only previewID; Cancel/dismiss invokes cancelShare and never confirmShare.
- Aggregate counters and pure domain EstimateTimeSaved v1 (layout/manual1s, typo/doubleCaps/yo2s, undo0), transparent formula and confirmed reset.
- All license wire states checking/trial/active/grace/pending/expired/revoked/unavailable, purchase/restore/manage actions. Purchase disabled and unavailable explanation shown when NECARAMBA_PRODUCT_ID is empty; no invented product identifier or successful purchase claim.
- About/help/privacy, native login preference and status, explicit diagnostics/archive export and confirmed import; unavailable native services display a redacted unavailable error rather than invented success.
- RU/EN standard Flutter generated localization, light/dark Material themes, desktop sidebar and narrow-window selector, native-style focusable controls, explicit palette selected/button semantics, live status/error semantics and full selectable exception/preview values. Palette header foreground contrast >=4.5 verified for all25 base colors. No copied assets.

## RED / GREEN evidence

Initial `flutter test test/features/native_cubit_test.dart` failed at compilation for absent `NativeCubit.run` and pending state. After implementation, pending failed-save/authoritative preferences and stale streamed-state reply tests PASS.

Initial feature widget scenarios failed at compilation for missing injected locale and absent UI. Subsequent widget runs exposed a real narrow RU header overflow and sharing-test offscreen taps. Header single-line bounds fixed the overflow; tests now scroll and wait before taps. The suite verifies failed preference change, Cancel clear with zero mutation, Cancel share with zero confirm, confirmed exact previewID, failed word save preserving draft, independent capability state, stream disconnect/reconnect, RU narrow layout, palette contrast/estimate weights and header geometry/opaque drop dispatch.

Final verification (App):

- `flutter gen-l10n`: PASS; complete matching RU/EN ARB keys.
- `flutter analyze`: PASS, no issues.
- `flutter test`: PASS,31 tests total (18 prior bridge/bootstrap +13 presentation/domain cases).
- `flutter build macos --release`: PASS,42.9MB scaffold app. Existing generated always-run Flutter Assemble warning remains.
- Executable `lipo -archs`: x86_64 arm64; `vtool -show-build`: both slices minos12.0. These inspections are not hardware qualification.

## Integration and remaining gates

Root must inject its WindowInteractionPort data adapter, native bridge/coordinator/services and matching native palette. This branch builds the Flutter shell against the existing disconnected native scaffold; its successful release build does not qualify later native integration. WindowInteractionPort signatures: Stream<String> headerDropHandles; Future<void> updateHeaderDropRegion(HeaderDropRegion?); HeaderDropRegion(double x,y,width,height).

Pubspec changes explicitly approved by root: flutter.generate=true, integration_test SDK dependency and intl0.20.3 (matching current SDK); lock updated.

Synthetic `integration_test/settings_flow_test.dart` exists and uses fake native repository only. It has NOT been run on macOS because the task explicitly prohibited launching/capturing the app. Actual NSOpenPanel sound/app/archive operations, real drag/drop overlay and managed image persistence, native login/TCC, native menu-to-UI synchronization, StoreKit/backend sharing, actual keyboard-only/VoiceOver/Reduce Motion/dark visual review and Intel/macOS12 / Apple Silicon launches remain host gates. No claim of E-03 manual accessibility or E-01 hardware acceptance. No support/payment URL or backend is fabricated; help is in-app and configured native services may remain unavailable.

## Review fix round 1

Split the former971-line WorkspacePage state into cohesive feature presentation modules: settings, exceptions, applications, permissions, appearance, rules, statistics, licensing and about. WorkspacePage now255 lines and owns navigation, connection/error display and activation refresh. Shared WorkspaceHeader owns header rendering/geometry; FeatureUI contains small presentation helpers. Exceptions and rules own and dispose their draft controllers. An IndexedStack of independently scrollable feature views preserves those drafts/scroll positions across navigation. NativeCubit remains the single confirmed-snapshot/pending/error coordinator; no additional Cubits or data adapters were introduced.

All window-region Future failures (including the null region during disposal) are caught by NativeCubit.updateHeaderRegion. Drop stream errors now use NativeCubit.reportWindowFailure. Only typed failure codes or unavailable reach the visible localized error banner; exception messages/paths are ignored. Root's main.dart platform-adapter import/entry-point injection must be preserved when applying the one-line drop listener onError change.

Sharing preview content now has a viewport-relative max height and SingleChildScrollView; Send/Cancel remain outside the scroll area. RU/EN legacy labels describe the preserved original and no longer promise editing.

RED: new regression suite on the original implementation produced uncaught NativeFailure(ioFailure) from header region publication/disposal and uncaught drop-stream permissionDenied. Its first short-window setup did not mount the offscreen preview button; the test was corrected to open the modal in a tall viewport and then resize to800×450 with long feedback. No claim that this initial setup failure proved the production overflow.

GREEN: `flutter gen-l10n` PASS; `flutter analyze` PASS/no issues; `flutter test` PASS/35 tests. The four added regressions cover failing geometry including disposal, failing drop stream, long feedback preview resized to a short window with safe Cancel, and feature-owned draft preservation across navigation with no implicit save. No release rebuild, app launch, screenshots, platform-adapter changes or manual host claims in this widget-only review round, per integrator scope.
