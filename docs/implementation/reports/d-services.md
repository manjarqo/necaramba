# D1–D4 delivery handoff — 2026-10-14

Scope: independently signed rule packages, offline slot installation and bounded download, explicit rule sharing, and optional own StoreKit licensing. D5 release gate and Runner/Xcode integration are owned by the integrator and are not claimed here.

## Evidence

- Fresh `swift test` in the delivery worktree: 51 NecarambaMacTests and 45 NecarambaCoreTests passed, zero failures. These are unit and URLProtocol tests on the local arm64 host (verified by root: macOS27.0.1, build26A434; the XCTest target triple is not the host OS), not device/editor/release tests.
- Both `SignRulePackage.swift` and `PrepareDevelopmentRulePackage.swift` compiled with the shared RuleManifest format source using `swiftc`.
- The independent corpus SHA256 was checked against the development manifest: `c5b8ffaae684f053cb57203bc364115fec413224f659d0bbac8b9b2d1b04a133`; the manifest records 12,376,802 bytes and the development signature is 64 bytes. The matching payload is still in the corpus worktree for the integrator to copy into the prototype bundle.
- Existing D1–D4 tests arrived with the worktree; their original RED logs were unavailable. This takeover observed RED for `testReplayingIdenticalSignedMaterialCannotExtendGrace` and for the new `testBundledVersionRemainsRemoteFloorWhenInstalledSlotLoads`; both passed after fixes, and the full suite passed.

## Implemented boundaries

- The verifier checks canonical manifest bytes, key/schema/app/version/size/digest/signature and strict payload structure before returning a verified snapshot. Production trusted keys are deliberately empty. Development signing uses a generated in-memory key and an explicit development marker.
- The slot store writes and verifies immutable generations, atomically commits a state file, keeps previous verified rules, and preserves the high-water mark on corrupt-current fallback. Startup now records a verified bundled identity even when an installed slot loads, so later remote packages cannot fall below the bundled version.
- Downloads are constrained to HTTPS on one configured host, with an ephemeral session, streaming byte limits, identity encoding, and no keyboard text in requests. Update scheduling and status are separate from the input executor. Sharing requires preview and explicit confirmation; Cancel sends nothing.
- Commercial licensing is optional. Only StoreKit verified transactions with configured own IDs can establish entitlement. The offline material cache rechecks signed material, limits grace to 72 hours and signed expiry, and does not reset the grace clock when the same signed transaction is observed again.

## Open gates and limitations

- No owner production rule-signing key, rule endpoint, Apple Team/bundle/Product IDs, or approved commercial policy is present. Development signing material must never be treated as release material.
- The development payload has not been copied into the Runner bundle by this branch. Runner project wiring, release configurations, acceptance report, signing/notarization and D5 compatibility gates remain with the integrator.
- No real HTTPS endpoint, redirect/cancellation integration, AppKit input swap/replay, purchase/restore/revocation StoreKit configuration test, or clean-host/manual/editor test was run. URLProtocol and synthetic entitlement tests establish only the local behavior exercised.
- `RuleUpdateStatus.current` denotes a durably delivered model, not acknowledgement that the input runtime has activated it; the runtime must publish its actual active version after its transaction boundary.
- AC-053–062, AC-070, AC-086–090 and AC-101 are only partially supported by the unit evidence above. None is marked fully accepted on this report alone.

## Review fixes — 2026-10-14

- RED regressions reproduced: rollback after observed grace expiry restored access; missing state with retained generation accepted an older remote package; malformed state prevented verified bundled startup; two same-direction mappings passed production validation. The three focused suites then passed (12 Mac and 5 Core tests, zero failures).
- The entitlement cache now persists the latest observed clock value before returning a cached grant, rejects rollback below it, and requires a distinct verified transaction at a non-rolled-back time to establish a new record. Legacy cache records without this field use their original checked date as the floor.
- Missing state with installed generations and malformed state block remote promotion. Startup still loads a verified bundled package when state integrity is unavailable; it neither deletes the installed generations nor resets their recorded version.
- Production payload validation now requires both `US->RU` and `RU->US` layout mapping directions, matching the independently generated corpus.
- A one-off local verifier executable checked the development manifest, signature and actual independent corpus together after this change: model 1, 179,000 lexemes, digest `c5b8ffaae684f053cb57203bc364115fec413224f659d0bbac8b9b2d1b04a133`. No private key was used or saved by that check.
- Same-version redelivery cannot repair a corrupted current generation: the generation path is immutable and replacing a nonempty directory is not an atomic state transition under this slot design. Startup uses verified previous/bundled rules, and a higher signed version can install. A future repair needs a separately designed generation identity and crash-tested commit protocol; no unverified or conflicting same-version bytes are activated.
