# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Necaramba is a macOS (12+, universal arm64/x86_64) keyboard-layout switcher (EN↔RU): a Swift native input engine plus a Flutter settings UI. Read `AGENTS.md` first — its engineering rules are binding (Clean Architecture boundaries, integrator ownership of `Package.swift` / `App/pubspec.yaml` / Xcode config, RED/GREEN test evidence, never touching installed Caramba, TCC, login items or personal documents in tests).

## Commands

Native (repo root, SwiftPM):

```sh
swift test                                             # all Core + Mac tests
swift test --filter NativeInputControllerTests         # one test class
swift test --filter 'ReplacementEventSequenceTests|PhasedKeyPostingTests'
swift test --filter testDelayedImportRejectsNativeRevisionChangeAtCommit   # one test method
swift test --scratch-path /tmp/necaramba-<topic>       # separate build dir (use in worktrees / parallel runs)
```

Flutter (from `App/`, Flutter version pinned in `App/.flutter-version`):

```sh
flutter pub get
flutter analyze
flutter test
flutter test test/features/native_cubit_test.dart      # single file
flutter build macos --release                          # → App/build/macos/Build/Products/Release/Necaramba.app
NECARAMBA_OPEN_MODEL=YES flutter build macos --release # build with the open model (Beta 3 configuration); leave NECARAMBA_LOCAL_PATTERN_MODEL unset
```

Tools and gates (repo root):

```sh
swift run ReplayRunner
swift run CorpusRunner --manifest Corpora/ReviewV3/manifest.json --split holdout --output Reports/review-v3-quality.json
swift Tools/Release/validate-release-report.swift docs/release/release-report.json   # currently expected to exit 1 (unfilled draft)
python3 Tools/OpenModel/test_build.py                  # Python tool tests live next to each tool (test_*.py)
python3 Tools/Release/test_local_signing.py
```

Corpus and release gates may intentionally fail while quality targets or required evidence are incomplete. Verify a release build with `codesign --verify --deep --strict` and `lipo -archs` (both slices are expected).

## Build integration

- The Xcode Runner (`App/macos/Runner.xcodeproj`) consumes the root Swift package as the `NecarambaMac` product. A Runner build phase runs `Tools/Packaging/embed-native-resources.sh`, which stages rule packages, the optional open model (`NECARAMBA_OPEN_MODEL=YES`), an optional local pattern model (`NECARAMBA_LOCAL_PATTERN_MODEL=<path>`, requires `NECARAMBA_DEVELOPMENT_RULES=YES`; private, never committed or shipped), the sound, and builds a universal `NecarambaLoginHelper` (macOS 12 login item).
- `App/macos/Runner/Configs/AppInfo.xcconfig` sets `NECARAMBA_DEVELOPMENT_RULES = YES` for local builds. Release signing comes from the git-ignored `LocalSigning.xcconfig` (see `docs/release/local-signing.md`); a stable signing identity keeps TCC grants across rebuilds.
- `NECARAMBA_PERF_TRACE=1` in the app process environment enables redacted input-stage diagnostics (`Tools/Performance/README.md`).

## Architecture

```
NecarambaCore  (Foundation only)  ← NecarambaMac (AppKit/AX/CGEvent/TIS/SQLite adapters) ← App/macos/Runner (composition root) ↔ Flutter UI
```

- **`Sources/NecarambaCore`** — platform-independent domain: `Types` (input events, `PreferencesSnapshot`, rule types), `Ports` (protocols such as `ContextAccess`, `SelectionAccess`, `KeySending`, `PermissionReading`, `ClipboardAccess`, plus edit-proof value types in `Ports/Editing.swift`), `Input` (`WordBuffer`, `GestureRecognizer` — double-Shift etc.), `Layout/LayoutConverter`, `Language` (linguistic/automatic correction engines: conservative vocabulary, pattern model, open lexical model), `Delivery` (rule manifest/package verification). Must not import AppKit, Flutter, SQLite or channel APIs.
- **`Sources/NecarambaMac`** — implements the ports:
  - `Input/`: `EventTapAdapter` (CGEventTap) feeds `InputRuntime`, which buffers words, recognizes gestures and emits `RuntimeCommand`s (gesture, boundary, automaticBoundary, plainPaste). All physical events pass through; deferred commands must re-validate AX evidence. `NativeInputController` is the main-thread facade that owns the runtime, engines, `ContextMonitor` / `AXFocusedElementResolver` (focused-field identity, Chromium AX activation) and dispatches to replacement.
  - `Replacement/`: `ReplacementCoordinator`, `AXSelectionAdapter` and the key-posting path (`ReplacementEventSequence`, `PhasedKeyPosting`, `KeyBatchPosting`) perform the edit. A replacement counts as verified only after checking the resulting text, caret and field identity; opaque/terminal fields (no readable AX value) use narrower physical-capture proofs.
  - `Application/ApplicationComposition` + `ApplicationServices` assemble storage (`Storage/SQLiteStore`), preferences, appearance/statistics, lifecycle/login, and rule delivery. `Bridge/NativeCommandCoordinator` handles UI commands with session/revision checks.
- **`App/macos/Runner`** — `AppDelegate` is the native composition root (status-bar accessory app; input service keeps running when Settings is closed). `MainFlutterWindow` is created on demand and exposes method channels `necaramba/control.v1` and `necaramba/window.v1`.
- **`App/lib`** — Dart Clean Architecture: `domain/` (entities, repository interfaces, use cases; pure Dart), `data/` (channel repositories and `native_state_decoder`), `presentation/` (`NativeCubit`, workspace) and `features/<name>/` UI. Native is the source of truth; no keyboard/typed text ever crosses into Dart — only settings state and aggregate counters.

## Tests and evidence

- Swift tests use fakes/test doubles for AX, event posting, clipboard and stores (temporary directories). `Tests/NecarambaCoreTests/Fixtures` holds corpus/rule fixtures; Flutter fakes live in `App/test/support/native_fakes.dart`.
- Input-engine changes need a regression test and must preserve secure-field, focus and field-identity checks.
- Work reports with RED/GREEN evidence go in `docs/implementation/reports/`; `docs/implementation/acceptance-status.md` tracks what is qualified. Never claim device, manual, Intel/macOS 12 or release checks passed unless actually run — unit tests are not editor-compatibility evidence.
- Design spec and plans: `docs/superpowers/specs/`, `docs/superpowers/plans/`. Research evidence stays under `docs/research/` (partly git-ignored), outside product targets.
