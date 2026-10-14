# Native/Flutter integration — 2026-10-14

Clean boundaries: Core contains value types/policies and ports; Mac adapters implement SQLite, permissions, TIS, clipboard, image/audio, login and input. ApplicationServices composes use cases; NativeCommandCoordinator serializes a versioned wire contract. Flutter domain ports have data channel adapters and feature presentation modules, one authoritative snapshot Cubit.

Native bridge tests cover queued request idempotency, stale-session/revision rejection, unknown commands and redacted errors. Full Swift suite passed before runtime/corpus additions; targeted archive tests21 PASS, release tests2 PASS, window adapter test1 PASS. UI fix report records35 PASS and analyzer clean. Latest integrated `flutter build macos --release` PASS45.8MB; helper embeds universal macOS12 binary, own WAV copied, no Caramba assets.

Preferences are now authoritative in own SQLite application_preferences table; UserDefaults is a migration input/mirror. Rule/preference archive validates first and commits in one SQLite transaction; duplicate conflicts preserve both old rules and preferences. Postcommit preference adoption does not perform another database write. Login preference import does not register OS login without explicit user action.

Native window creates Flutter engine only when opening settings, detaches channels and shuts engine down on close. Native services continue without Flutter. Opaque image-drop handles are engine-local, bounded and expire. Common palette has25 independently selected colors.

Own local app UI was opened with CUA: Russian dark/narrow layout, navigation and native permission page were visible. Listen/post/AX all false; no permission was granted, login enabled or user data inspected. RSS samples90MB open and85MB following close, CPU0% at one sample; these are exploratory samples, not E4 or performance acceptance. Full reopen100cycles and physical typing tests remain UNRUN.

Input facade is connected but default denies unqualified editors and automatic corpus gate is false. Runtime review found incomplete edit ownership, manual priority and interception; assigned fix round. Current code is not a full functioning analogue and must not be released. Independent corpus holdout recall80.867% fails95%; no fake readiness.

Release gate rejects missing tuples/evidence. Production identity/signing/notarization, endpoint, commercial product configuration, native Intel/macOS12 host matrix and MAS feasibility remain blocked/unrun. Config files are templates, not tested release configurations. No release or network purchase/share occurred.
