import XCTest
import CryptoKit
@testable import NecarambaCore

final class RulePackageVerifierTests: XCTestCase {
    func package(version: UInt64 = 2) throws -> (Data, Data, Data, Data) {
        let key = Curve25519.Signing.PrivateKey()
        let snapshot = RuleSnapshot(modelVersion: version,
            lexicon: [.init(word: "hello", language: .english, frequencyBand: 1), .init(word: "привет", language: .russian, frequencyBand: 1)],
            protectedTokens: ["API"], mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["f": "а"]), .init(source: .init(rawValue: "RU"), target: .init(rawValue: "US"), pairs: ["а": "f"])])
        let payload = try JSONEncoder().encode(snapshot)
        let digest = Data(SHA256.hash(data: payload))
        let manifest = try canonicalManifest(.init(schemaVersion: 1, modelVersion: version, minimumAppVersion: "1.0.0", payloadSize: UInt64(payload.count), payloadSHA256: digest.map { String(format: "%02x", $0) }.joined(), keyID: "test"))
        return (manifest, try key.signature(for: Data("NecarambaRules-v1\0".utf8) + manifest + Data([0]) + digest), payload, key.publicKey.rawRepresentation)
    }
    func testTamperedPayloadIsRejected() throws {
        let p = try package(); var changed = p.2; changed[0] ^= 1
        let verifier = RulePackageVerifier(trustedKeys: ["test": p.3], appVersion: "1.0.0")
        XCTAssertThrowsError(try verifier.verify(manifest: p.0, signature: p.1, payload: changed, installedVersion: 1)) { XCTAssertEqual($0 as? RuleVerificationError, .hashMismatch) }
        XCTAssertEqual(try verifier.verify(manifest: p.0, signature: p.1, payload: p.2, installedVersion: 1).modelVersion, 2)
    }
    func testSignatureUnknownKeyDowngradeAndCanonicalBytes() throws {
        let p = try package()
        let verifier = RulePackageVerifier(trustedKeys: ["test": p.3], appVersion: "1.0.0")
        XCTAssertThrowsError(try verifier.verify(manifest: p.0, signature: Data(repeating: 0, count: 64), payload: p.2, installedVersion: 0))
        XCTAssertThrowsError(try verifier.verify(manifest: p.0, signature: p.1, payload: p.2, installedVersion: 3))
        XCTAssertThrowsError(try verifier.verify(manifest: Data(" ".utf8) + p.0, signature: p.1, payload: p.2, installedVersion: 0))
        XCTAssertThrowsError(try RulePackageVerifier(trustedKeys: [:], appVersion: "1.0.0").verify(manifest: p.0, signature: p.1, payload: p.2, installedVersion: 0))
    }
}
extension RulePackageVerifierTests {
    func resign(_ p: (Data, Data, Data, Data), mutateManifest: (RuleManifest) -> RuleManifest = { $0 }, payload: Data? = nil) throws -> (Data, Data, Data, Data) {
        let key = Curve25519.Signing.PrivateKey(); let bytes = payload ?? p.2
        let old = try JSONDecoder().decode(RuleManifest.self, from: p.0)
        let digest = Data(SHA256.hash(data: bytes))
        let base = RuleManifest(schemaVersion: old.schemaVersion, modelVersion: old.modelVersion, minimumAppVersion: old.minimumAppVersion, payloadSize: UInt64(bytes.count), payloadSHA256: digest.map { String(format: "%02x", $0) }.joined(), keyID: old.keyID)
        let manifest = try canonicalManifest(mutateManifest(base))
        return (manifest, try key.signature(for: Data("NecarambaRules-v1\0".utf8) + manifest + Data([0]) + digest), bytes, key.publicKey.rawRepresentation)
    }
    func testBoundsMalformedAndUInt64Maximum() throws {
        let p = try package(version: UInt64.max)
        XCTAssertEqual(try RulePackageVerifier(trustedKeys: ["test": p.3], appVersion: "1.0.0").verify(manifest: p.0, signature: p.1, payload: p.2, installedVersion: UInt64.max).modelVersion, UInt64.max)
        for manifest in [Data("{}".utf8), Data(repeating: 32, count: 65537), Data(String(data: p.0, encoding: .utf8)!.replacingOccurrences(of: "18446744073709551615", with: "18446744073709551616").utf8)] {
            XCTAssertThrowsError(try RulePackageVerifier(trustedKeys: ["test": p.3], appVersion: "1.0.0").verify(manifest: manifest, signature: p.1, payload: p.2, installedVersion: 0))
        }
    }
    func testSignedInvalidSchemaAppSizeAndPayloadAreRejected() throws {
        let p = try package()
        let mutations: [(RuleManifest) -> RuleManifest] = [
            { .init(schemaVersion: 2, modelVersion: $0.modelVersion, minimumAppVersion: $0.minimumAppVersion, payloadSize: $0.payloadSize, payloadSHA256: $0.payloadSHA256, keyID: $0.keyID) },
            { .init(schemaVersion: 1, modelVersion: $0.modelVersion, minimumAppVersion: "2.0.0", payloadSize: $0.payloadSize, payloadSHA256: $0.payloadSHA256, keyID: $0.keyID) },
            { .init(schemaVersion: 1, modelVersion: $0.modelVersion, minimumAppVersion: "1.0.0", payloadSize: 0, payloadSHA256: $0.payloadSHA256, keyID: $0.keyID) }
        ]
        for mutate in mutations { let bad = try resign(p, mutateManifest: mutate); XCTAssertThrowsError(try RulePackageVerifier(trustedKeys: ["test": bad.3], appVersion: "1.0.0").verify(manifest: bad.0, signature: bad.1, payload: bad.2, installedVersion: 0)) }
        let empty = try JSONEncoder().encode(RuleSnapshot(modelVersion: 2)); let bad = try resign(p, payload: empty)
        XCTAssertThrowsError(try RulePackageVerifier(trustedKeys: ["test": bad.3], appVersion: "1.0.0").verify(manifest: bad.0, signature: bad.1, payload: bad.2, installedVersion: 0))
        let original = String(data: p.2, encoding: .utf8)!
        for changed in ["{\"surprise\":true," + original.dropFirst(), "{\"modelVersion\":2," + original.dropFirst()] {
            let q = try resign(p, payload: Data(changed.utf8)); XCTAssertThrowsError(try RulePackageVerifier(trustedKeys: ["test": q.3], appVersion: "1.0.0").verify(manifest: q.0, signature: q.1, payload: q.2, installedVersion: 0))
        }
    }
    func testTwoMappingsInSameDirectionAreNotProductionRules() throws {
        let p = try package()
        let original = try JSONDecoder().decode(RuleSnapshot.self, from: p.2)
        let forward = LayoutMapping(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["f": "а"])
        let invalid = RuleSnapshot(modelVersion: original.modelVersion, lexicon: original.lexicon,
                                   typos: original.typos, yoRules: original.yoRules,
                                   protectedTokens: original.protectedTokens, mappings: [forward, forward])
        let signed = try resign(p, payload: JSONEncoder().encode(invalid))
        XCTAssertThrowsError(try RulePackageVerifier(trustedKeys: ["test": signed.3], appVersion: "1.0.0")
            .verify(manifest: signed.0, signature: signed.1, payload: signed.2, installedVersion: 0)) {
            XCTAssertEqual($0 as? RuleVerificationError, .invalidPayload)
        }
    }
}
