# Implementation acceptance status — 2026-10-14

This is an internal prototype under review, not a completed full Caramba analogue. Flutter is the UI; Swift owns global input and native services. Neither successful compilation nor simulated tests authorize enabling editor mutation in unqualified applications.

| Area | Implemented evidence | Remaining acceptance |
|---|---|---|
| Domain and contracts | Platform-independent Core, immutable native snapshots, versioned Dart bridge | Application ports refactor passed scoped architecture review |
| Global input | Event tap, bounded ownership, layout capture, context proof, manual/undo/clipboard transactions | Actual editor qualification and physical input tests; default profiles deny edits |
| Independent language model | Signed development bundle, 179,000 independent dictionary entries, corpus harness | Layout recall about 80.9% against required 95%; automatic gate remains false |
| Storage | SQLite rules/preferences, atomic archive import, legacy preservation | Regular and legacy exclusions both reach runtime policy; scoped review passed |
| Flutter settings | Eight preferences, exceptions/apps, permissions, appearance, rules, stats, licensing, RU/EN | VoiceOver and repeated-engine accessibility qualification |
| Images and sound | Bounded file URL image drop, canonical image storage, own/default and custom sound | TIFF-only pasteboard providers rejected; F14 is partial |
| Delivery | Verified packages, rollback-resistant slots, opt-in share consent, local operation | Production keys/endpoints/product IDs; initial/live entitlement ordering fix under review |
| Release | Universal local build, embedded login helper, report/artifact validators | Real macOS12/Intel/current host matrix, signing/notarization, production packages; MAS blocked on AX feasibility |

Local checks completed during integration: 163 Swift tests (100 Mac +63 Core), 36 Flutter tests, clean Flutter analyzer, three Runner drag tests, five release-validator fixture tests, and two ordered 100,000-event replays. Subsequent fixes have focused tests; final verification is recorded in the integration report. These counts are automated checks, not the physical release matrix.

The observed TIS startup trap was fixed and the actual local Release app subsequently displayed active model version1. A closed/reopened window rendered again. The second engine's accessibility tree was incomplete, so that observation does not pass accessibility or the 100-cycle resource gate.

No permission was granted, OS login item enabled, purchase performed, user typing captured, or production distribution published during these tests. The installed Caramba specimen was not modified and its code/resources are not product inputs.
