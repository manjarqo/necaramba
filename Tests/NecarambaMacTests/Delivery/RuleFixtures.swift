import Foundation
import CryptoKit
import NecarambaCore
struct RuleFixtures {
    let key = Curve25519.Signing.PrivateKey()
    var verifier: RulePackageVerifier { .init(trustedKeys: ["test": key.publicKey.rawRepresentation], appVersion: "1.0.0") }
    func package(version: UInt64, protectedToken: String = "API") throws -> RulePackage {
        let snapshot = RuleSnapshot(modelVersion: version, lexicon: [.init(word: "hello", language: .english, frequencyBand: 1), .init(word: "привет", language: .russian, frequencyBand: 1)], protectedTokens: [protectedToken], mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["f": "а"]), .init(source: .init(rawValue: "RU"), target: .init(rawValue: "US"), pairs: ["а": "f"])])
        let payload = try JSONEncoder().encode(snapshot); let digest = Data(SHA256.hash(data: payload))
        let manifest = try canonicalManifest(.init(schemaVersion: 1, modelVersion: version, minimumAppVersion: "1.0.0", payloadSize: UInt64(payload.count), payloadSHA256: digest.map { String(format: "%02x", $0) }.joined(), keyID: "test"))
        return .init(manifest: manifest, signature: try key.signature(for: Data("NecarambaRules-v1\0".utf8) + manifest + Data([0]) + digest), payload: payload)
    }
}
