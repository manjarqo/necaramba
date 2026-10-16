# Independent rule package v1

This is Necaramba's own format, not a third-party model format. Manifest is exact UTF-8 compact JSON, sorted keys, unescaped slashes, integer numbers. The six keys are `keyID`, `minimumAppVersion`, `modelVersion`, `payloadSHA256`, `payloadSize`, `schemaVersion`. Duplicate/unknown keys and noncanonical bytes are rejected. UInt64 values never pass through floating point. Schema is 1, app versions contain three UInt32 components, key IDs contain 1–64 ASCII letters/digits/underscore/hyphen, digest is lowercase hex SHA256.

Ed25519 signs `UTF8("NecarambaRules-v1\0") || canonical manifest || 0x00 || SHA256(payload)` with CryptoKit Curve25519.Signing. Manifest limit 64 KiB, signature exactly 64 bytes, payload limit 20 MiB. Payload is strict duplicate-free JSON with only RuleSnapshot fields and known nested record fields; bounded strings/collections, both language lexicons and reverse layout maps are required. No scripts/paths execute. Signature/hash are checked before payload parsing.

Compile the local signer using the shared canonical format:

```
swiftc Sources/NecarambaCore/Delivery/RuleManifest.swift Tools/Release/SignRulePackage.swift -o /tmp/necaramba-sign-rules
/tmp/necaramba-sign-rules manifest.json payload.json private-key.bin signature.ed25519
```

Private-key.bin is the owner's 32 raw private-key bytes supplied locally. Never commit it. The signer logs no key, words, path arguments or package contents. Tests generate ephemeral keys only; TrustedRuleKeys.json is intentionally empty until own release keys are supplied. Bundled production corpus belongs to the independent corpus workstream, not test fixtures.

Generation files are fsynced and verified again from disk before committing one atomically renamed state.json; its highest accepted version never decreases on local corruption fallback. Remote downgrade is always rejected. Same-version different digest is rejected. Recovery/cross signing are not supported: key rotation requires an app update. Missing/corrupt state fails closed; missing network leaves verified local rules operational. RuleUpdateStatus.current means durable delivery, while runtime active version is reported separately after the input transaction boundary.

HTTPS requests are ephemeral, no cookies/credentials/body for downloads, identity encoding only, streaming actual-byte bounds, 15-second timeout, same configured host HTTPS redirects only. Missing own endpoint disables downloads. Scheduled launch/daily ±2h checks and 30-second manual throttle never perform tight retries.

An explicitly authorized prototype may use `PrepareDevelopmentRulePackage.swift` compiled alongside RuleManifest.swift. It generates an ephemeral private key in memory and writes only development-marked manifest, signature, public key and marker. It consumes the approved corpus path without copying it. Integrator copies the matching corpus payload separately; production trust keys stay empty. The development-only key ID and DevelopmentOnly.json must block release. This supports verified offline prototype input without fabricating owner release credentials.
