# Flutter SDK qualification

Pinned installed toolchain, qualified 2026-10-14:

- Flutter stable3.47.1, framework `6655482ec06e547f90abf8ae7590466f4415978d`
- Engine `5d531788691ec3404cac0cee66ead4007b177363`, content hash `11d79658c444477b06513d32b52c8c4ccb7276b0`
- Dart3.13.1, DevTools2.60.0
- Xcode27.0 build27A266a, build host macOS arm64
- flutter_bloc9.1.1; all transitives pinned in App/pubspec.lock

Release engine, App.framework and runner executable inspected with lipo/vtool: arm64+x86_64; macOS12.0 minimum on each slice. No native plugins. Keep universal builds enabled; do not enable Flutter macOS arm64-only configuration. CI should verify this exact framework revision before building; `.flutter-version` records version, revision above is authoritative.

Real Intel/macOS12 and Apple Silicon launch checks, code signing/notarization, full native linkage and performance/lifecycle qualification are pending. SDK artifact inspection is not release approval.
