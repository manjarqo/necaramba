# Necaramba engineering rules

Approved spec: docs/superpowers/specs/2026-10-14-necaramba-design.md.
Implementation plans: docs/superpowers/plans/2026-10-14-necaramba-{a-core,b-input,c-ui-storage,d-delivery,e-flutter-bridge}.md.

User requires Clean Architecture, Flutter UI and Swift native runtime, macOS12+, arm64/x86_64. Domain entities and repository ports must not import Flutter, AppKit, SQLite or channel APIs. Use cases depend on ports; data adapters implement them; presentation depends on use cases/domain. Composition roots wire dependencies. Native domain NecarambaCore stays platform independent; NecarambaMac implements system adapters. Dart features use domain/data/presentation directories. No keyboard data crosses into Dart.

Independent assigned owners may work in parallel worktrees. Do not revert others' changes. Root integrator owns Package.swift, App/pubspec.yaml and Xcode configuration unless specifically delegated. Read assigned plans/spec; implement behavior tests first and report RED/GREEN evidence. Do not claim device/manual/release tests passed unless run. Preserve research evidence outside product targets. Never modify installed Caramba, user TCC, login items or personal documents in tests. Use temporary stores/test doubles by default.
