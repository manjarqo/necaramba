# Implementation architecture

User approved Flutter/Swift plan and explicitly requested Clean Architecture.

- `NecarambaCore`: domain entities, value objects, deterministic use cases and repository ports. Foundation only; no AppKit, Flutter, SQLite or channel imports.
- `NecarambaMac`: data/system adapters for domain ports (permissions, TIS, event capture/posting, persistence, network, StoreKit). Dependency points inward to Core.
- Flutter `lib/domain`: entities, repository interfaces, use cases; pure Dart.
- Flutter `lib/data`: channel DTO codecs and repository implementations.
- Flutter `lib/presentation`: widgets/Cubit, depends on domain use cases/interfaces.
- Runner AppDelegate/native composition root and Dart bootstrap construct dependencies. UI never owns native input state and never receives captured keystrokes.

Plan path refinements follow these boundaries. Swift permission UI DTO uses PermissionState, native editing result uses InputCapabilities, avoiding the two different CapabilityState definitions in B/C prose. Source of truth remains native.

Status: implementation in progress. Unavailable Intel/macOS12 physical hosts, Developer ID signing/notarization and commercial credentials remain explicit release gates, not passing tests.
