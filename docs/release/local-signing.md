# Stable identity for local macOS testing

Use a certificate-signed **Release** app for repeated Accessibility and Input
Monitoring checks. An ad-hoc rebuild can change the code identity associated with
an existing macOS privacy grant. A visible enabled row does not prove that the
currently running executable has permission. Debug/test hosts previously shared
Release's bundle identifier, which also made the privacy entries ambiguous.

The configurations now use:

| Configuration | Bundle ID | Display name |
| --- | --- | --- |
| Release | `local.necaramba.app` | Necaramba |
| Debug | `local.necaramba.app.debug` | Necaramba Debug |
| Profile | `local.necaramba.app.profile` | Necaramba Profile |
| DeveloperID / MAS | `NECARAMBA_BUNDLE_ID` | Necaramba |

The executable, product filename and Swift module remain `Necaramba`; the native
RunnerTests host path and imports remain compatible. Local Release uses
`Runner/Configs/LocalRelease.xcconfig`. That target alone optionally includes
`LocalSigning.xcconfig`. Neither distribution configuration includes it.

## Local setup

1. List valid signing identities with `security find-identity -v -p codesigning`.
   Select your own Apple Development certificate and team, with the matching
   private key available. Use its exact SHA-1 fingerprint when multiple identities
   are installed; do not select another person's identity.
2. Copy `App/macos/Runner/Configs/LocalSigning.xcconfig.example` to
   `App/macos/Runner/Configs/LocalSigning.xcconfig`. Replace both placeholders with
   your certificate fingerprint and team ID. This file is gitignored and must not
   be committed. Do not put private keys or credentials in it.
3. From `App`, run `flutter build macos --release`. The normal Release target now
   picks up that local identity; no command-line signing override is required.
   Keep the same bundle identifier and certificate/team across local rebuilds.
4. Inspect the result before running it:

   ```sh
   codesign --verify --deep --strict App/build/macos/Build/Products/Release/Necaramba.app
   codesign -dv --verbose=4 App/build/macos/Build/Products/Release/Necaramba.app
   codesign -dr - App/build/macos/Build/Products/Release/Necaramba.app
   ```

   These inspection commands assume the repository root. Confirm the expected
   identifier, certificate authority and team, and retain the designated
   requirement when comparing rebuilds. A changed CDHash alone is expected for a
   new binary; the certificate-based designated requirement is the stable part.
5. Quit other copies and launch that Release artifact from a consistent location.
   If an old grant referred to an ad-hoc executable, manually remove that stale
   entry and add/enable the new app in System Settings → Privacy & Security →
   Accessibility and Input Monitoring. Quit and relaunch the signed app if macOS
   requests it. Verify the app's actual permission diagnostics and input behavior.
   This configuration change does not itself grant permissions or repair stale
   grants automatically. Do not automate TCC resets or grants.

Without the optional file, the repository retains the portable ad-hoc Release
fallback; that fallback is unsuitable for testing permission persistence across
rebuilds. Apple Development signing is for local testing and does not replace
Developer ID notarization or MAS distribution. DeveloperID/MAS retain their
existing identity, team, bundle ID and provisioning overrides; command-line Xcode
build settings still take precedence.

## Configuration regression check

Run `python3 Tools/Release/test_local_signing.py` on macOS with Xcode. It resolves
real project build settings in a temporary project, uses an inert generated
Flutter-package fixture, and checks distinct identities, unchanged test-host
paths, absent/present local settings, distribution isolation and CLI override
precedence. It never compiles, signs, accesses the keychain or changes TCC. Actual
signed app execution, permissions and release qualification require separate
host verification.
