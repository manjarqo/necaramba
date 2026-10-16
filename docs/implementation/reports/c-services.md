# C native services implementation

Owned worktree: `.worktrees/services`; Tasks C2/C5/C6. No Runner, Dart, Package.swift, or SQLite ownership edits.

## Implemented APIs

- `@MainActor PreferencesController(defaults:publish:)`: `settings:StoredPreferencesV1`, computed immutable `snapshot`, `replace`, `replaceSettings`, `setAuto`, `setSelectedColor`, `setLoginPreferred`, `setDiagnosticsOptIn`, `exportPreferences`, `importPreferences`. Version/color validation precedes persistence and one publication. Corrupt defaults produce approved domain defaults plus the redacted `recoveredInvalidStorage` flag. Root explicitly clarified stored default is A `.defaults` (auto=true); effective release gating is separate. `StoredPreferencesV1` holds version/snapshot/selectedColor/loginPreferred/diagnosticsOptIn only.
- `HeaderPalette`: 25 colors/defaultIndex0, WCAG luminance contrast and black/white foreground selection.
- `HeaderImageStore(directory:) throws`: `importImage(data:)`, `importImage(from:)`, `loadImageData`, `remove`. Local security-scoped files only; 10 MiB input, 8192 per dimension, 16 million pixels; ImageIO metadata inspected before rasterization, first frame only, orientation applied, normalized PNG atomic replacement. Previous image survives rejected imports.
- `SoundStore(directory:defaultSoundURL:)`: `importSound(from:) -> URL`, `reset`, `customSoundURL`, `setEnabled`, `playCorrection`, `playCorrection(committedID:)`. Utility queue, 5 MiB/10 seconds and full bounded decode before atomic replacement; 192 kHz/8 channel/32 MiB decoded safety bounds. Disabled playback stops current playback and does not play queued later events. Recent committed UUID dedup window1024; producer owns duplication guarantees beyond window. Default URL must be bundled and injected by root.
- `StatisticsStore(directory:) throws`: separate atomic aggregate-only JSON store by explicit root ruling, `recordCommitted(id:kind:day:)`, `count`, `totals`, `estimatedSeconds`, `reset`. Date and persisted schema/counter validation. UUID window1024 updated after successful disk commit. Saturating total/estimate arithmetic. Weights version1: layout/manual1, typo/doubleCaps/yo2, undo0 seconds; estimate, not measured timing. Reset does not touch rules. Never call disk methods from tap or main UI executor.
- `LoginBackend`, `LoginStatus`, `LoginController`: status refreshed even when a setter throws; approval is never replaced with assumed success. `SystemLoginBackend(mainBundleID:defaults:)` uses SMAppService on13+, validated own helper ID on12. Legacy status is unavailable because its API has no authoritative query. Tracked legacy registration disabled before modern registration.
- `LifecycleController(runtime:source:)`: start/stop idempotent; callback generations reject already queued stale delivery. Injectable source callbacks are annotated `@MainActor`; default notifications hop to the actor before controller state is accessed. Default `SystemLifecycleNotificationSource` owns sleep/wake/lock/unlock only, removes observer from its original center. B remains sole focus/layout/secure-input owner; integrator can call `handle` for explicit A invalidation reasons.
- `App/NecarambaLoginHelper`: validates enclosing `.app/Contents/Library/LoginItems/*.app` nesting and matching own bundle identifiers; launches enclosing app only if no matching running instance and exits. LSUIElement, macOS12 minimum. Root must create, sign and embed helper target with mainID + `.LoginHelper`.

## Original asset

`Resources/Sounds/correction.wav`: generated independent 120 ms880 Hz PCM sine tone; origin/formula in sibling README. No third-party resources. Root owns copying/bundling and defaultSoundURL wiring.

## Verification

RED commands ran before corresponding service files existed:

- `swift test --filter PreferencesControllerTests`: missing PreferencesController.
- `swift test --filter AppearanceStatisticsTests`: missing StatisticsStore/HeaderPalette/HeaderImageStore.
- `swift test --filter LifecycleControllerTests`: missing LoginBackend/LoginStatus/controllers.

GREEN focused tests: preferences persistence/single publication/corrupt fallback/validation/archive; aggregate duplicate/persistence/reset/estimate; all25 palette contrast; image persistence/corruption/size/dimension preservation/removal; sound valid decode/corrupt/oversize/overduration preservation/reset; login fake approval; lifecycle start/start/stop/restart and stale callbacks. Full `swift test` passes32 Mac +5 Core tests on this arm64 host. Helper `swiftc -typecheck App/NecarambaLoginHelper/main.swift` passes.

Real login settings/TCC untouched. Physical sound playback, helper launch/logout/login, real notifications, TIFF/FileURL Flutter drag/drop, accessibility, macOS12 backend, native Intel, release/signing, and xcodebuild Runner host tests remain UNRUN. No host/device compatibility claim.

## Integration ownership

Combined rules/preferences import recovery journal and transaction marker are explicitly owned by root (requires SQLite owner hook). This work makes no cross-store ACID claim. Flutter/header drop/menus/defaultSoundURL/configuration and native runtime preference wiring are composition-root work. Counters only receive committed actions; no keyboard text enters these APIs.


## Review follow-up: sound snapshot and lifecycle actor

Sound import now reads at most5MiB+1 in bounded chunks from a single file handle,
creates a unique managed temporary file, decodes exactly that file, then POSIX
renames it atomically to the managed destination. It never rereads the source
path for persisted bytes. Temporary files are removed on every failure path.
An internal snapshotCaptured test hook permits deterministic source mutation;
production initialization supplies a no-op.

Behavior RED: the deterministic valid→corrupt source mutation test failed with
19 persisted bytes versus7296 validated bytes under the old reread implementation.
GREEN: same test now preserves the captured valid bytes, and corrupt→valid source
mutation still rejects the corrupt snapshot without changing the previous asset.
LifecycleNotificationSource callback contract is now `@MainActor`; default
notification delivery uses a main-actor Task before invoking it. Existing observer
ownership/stale generation tests remain passing, and a detached-task invocation
test verifies delivery on main actor and no delivery after stop.
Fresh full suite passes34 Mac +5 Core tests. Real host gates remain UNRUN.
