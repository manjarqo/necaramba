# E1 shell and Dart bridge boundary

2026-10-14, isolated flutter worktree. Scope is the generated macOS runner and initial Dart E2 boundary; native services and NativeCompositionRoot integration are owned by the root integrator.

## Architecture

- Pure Dart domain snapshot/repository port/use cases under `App/lib/domain`. No Flutter, channel, database, or AppKit imports.
- `App/lib/data` owns strict Wire v1 decoding, method/event channels, signed64 checks, enum/type/field/size validation, subscription and revision reducer integration. Snapshot nested maps and rule lists are immutable.
- Presentation Cubit consumes use cases, owns subscription cancellation, and renders graceful disconnected bootstrap. Composition is in main.dart and accepts a fake repository.
- Eight preference names and all enum values are the native owner's agreed contract. Model version is a decimal string. Dates are nullable UTC ISO strings. License has state/expiresAt; model version/lastChecked/state; login enabled/status. Extra payload fields are rejected, including raw input fields.
- Native replies publish confirmed snapshots before returning. Requests carry unique random IDs and expected session/revision. Conflict refreshes state and requires caller action; ordinary timeout marks state dirty and refreshes before another action. No automatic mutation retry, including share/purchase. Dialog/purchase methods do not use a client timeout. Dispose cancels listener; reconnect cancels then subscribes before getState.
- Only explicit exception/share words can travel through command arguments. There is no input stream or keyboard capture code in this scaffold.

## Verification evidence

RED: `flutter test test/bridge` failed with missing intended domain/data imports/types (unimplemented boundary). Bootstrap widget test failed because NecarambaApp was absent. These are compile-stage RED results, not native runtime RED evidence. First implementation run passed five bridge cases and exposed synchronous disposed-refresh expectation mismatch; corrected assertion to assert the synchronous port failure.

GREEN: `flutter test`: 9 tests pass (schema/nested validation, round trip/private field rejection, command envelope and publish ordering, revision/session/immutability, event ordering, conflict resync/no retry, timeout-before-next-action resync, reconnect listener replacement/dispose, disconnected bootstrap). `flutter analyze`: no issues. Generated default counter app/test was replaced.

`flutter build macos --release`: PASS, app 38.8MB. Generated Flutter Assemble emits an always-run script phase warning. No native plugins are present. `lipo -archs` reports `x86_64 arm64` for executable, FlutterMacOS framework, App framework. `vtool -show-build` reports both slices minos12.0 for all three. Runner minimum is12.0 in Debug/Profile/Release; LSUIElement true; last-window closure does not terminate application.

## Open gates

E1 NativeCompositionRoot start/stop and native start-idempotence test are NOT implemented by this commit. No Swift package is linked until root integrates real services. Generated window currently owns one persistent Flutter engine; engine teardown/reopen, status item, login launch routing and E4 memory/idle/replay budgets are NOT qualified. App boot is intentionally disconnected.

E-01 hardware launch on real Intel/macOS12 and Apple Silicon has NOT run; universal/minimum-load-command inspection alone does not close it. E-02 Dart boundary checks PASS, native channel tests still pending. E-03 feature/localized product flows/accessibility pending (only SDK localization delegates scaffolded). E-04 pending. No TCC changes, input capture, installed Caramba access, device/manual/release-signing tests, login changes or personal document access performed.

The root must replace generated `com.example.necaramba` identity before release and wire the real native owner. Client local concurrent mutations are not queued: optimistic conflict/resync protects native state. Native request-ID cache and duplicate-submission native tests remain native ownership. Pixel dimensions of thumbnail must be verified by native decoder; Dart checks binary payload <=256KiB.

## E2 review corrections (2026-10-14)

Six behavioral regressions were added before the fixes and all failed on the previous implementation: double schema1.0 accepted; sessionA command reply replaced sessionB event; reconnect reused blocked getState and lost listener; ordinary mutation leaked private result fields; mutable nested reply byte/list/map; platform error details dropped ID/retryability. After fixes, all six pass. Additional tests cover the real StandardMethodCodec error envelope, malformed details, nested preview fields and thumbnail dimensions/size. `flutter test` now18 PASS; `flutter analyze` clean. No native/hardware gates changed.

The reducer permanently retires superseded session IDs for the repository lifetime. A command reply from a retired session causes typed conflict and resync; its result is not delivered. An older same-session reply preserves current confirmed revision. Reconnect is coalesced, invalidates outstanding read generation, installs a new listener and performs a fresh getState; old completion cannot clear a newer refresh or restore stale state. All reply maps/lists/Uint8List values are defensively copied and recursively unmodifiable. schema must be integer1.

Result schema agreed with native integrator (no extra keys accepted):

- Ordinary command: empty result map.
- previewShare: `{previewID:UUID-string,preview:{word:String,language:english|russian,modelVersion:decimal-string,feedback:String|null,host:hostname-string}}`. host has no scheme/path; the native configured HTTPS endpoint is authoritative. The `.example` host appears only in synthetic tests and is never a product fallback.
- getThumbnail: `{bytes:Uint8List,width:int,height:int}`. Absent image has empty bytes and dimensions0/0; present image has1..512 dimensions and bytes<=256KiB. This supersedes the earlier report's native-only dimension validation limitation.
- PlatformException details, if present, exactly `{requestID:String,retryable:bool}`; ID is nonempty<=128 characters and must match a mutation request ID. Code is whitelist-mapped and message is ignored. Malformed/extra details fail validation. Absent details retain compatibility fallback mapping.

Public repository/use-case/snapshot signatures remain stable. Changes are Dart-only; original universal release build evidence remains the prior scaffold build, not a new native integration qualification.
