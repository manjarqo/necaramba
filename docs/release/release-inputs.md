# Release inputs and gates

Current build is a local development prototype. Production release requires owner-supplied Apple Team ID, registered bundle/helper IDs, Developer ID signing certificate, notarytool Keychain profile, support/privacy URLs, own production rule public key and endpoint. Commercial distribution additionally requires product IDs and approved entitlement/trial policy. No secrets belong in Git.

`Runner/Release/*.xcconfig` are channel templates; Runner's ordinary Release remains local prototype. They must be connected to channel-specific Xcode configurations after channel qualification; MAS is blocked by current AX strategy.

`swift Tools/Release/validate-release-report.swift docs/release/release-report.json` intentionally fails until every required tuple has current artifact hash and a real evidence file with SHA256. Build/Swift/widget tests are not replacements for native Intel/macOS12, editors, real keyboard, TCC, sleep/wake or clipboard races. Commercial AC086–090 and MAS AC096 are excluded only from DeveloperID prototype manifest, not marked passed or declared generally unnecessary.

`Tools/Release/verify-artifact.sh Final.app` checks nested Mach-O architectures/deployment/signatures plus Developer ID, hardened runtime, notarization and Gatekeeper. It never signs or publishes. Sign nested components inside-out; after notarization staple and create a fresh final ZIP, then validate the extracted ZIP and a quarantined downloaded copy on a clean Mac.

Compatibility keys are `AC/architecture/OS/host/adapter`. `qualified-hosts` in the draft manifest must be expanded into the actual named TextEdit/Safari/Chromium/Electron/version tuples before acceptance; no placeholder evidence may authorize a release. Terminal/IDE automatic correction remains denied pending independent qualification.
