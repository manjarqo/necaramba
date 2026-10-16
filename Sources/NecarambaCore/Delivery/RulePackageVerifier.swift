import Foundation
import CryptoKit

public struct VerifiedRuleSnapshot: Sendable {
    public let snapshot: RuleSnapshot
    public let digest: String
    public var modelVersion: UInt64 { snapshot.modelVersion }
    fileprivate init(snapshot: RuleSnapshot, digest: String) { self.snapshot = snapshot; self.digest = digest }
}

public struct RulePackageVerifier: Sendable {
    public static let maximumPayloadSize = 20 * 1024 * 1024
    private let trustedKeys: [String: Data]
    private let appVersion: String
    public init(trustedKeys: [String: Data], appVersion: String) { self.trustedKeys = trustedKeys; self.appVersion = appVersion }
    public func verify(manifest: Data, signature: Data, payload: Data, installedVersion: UInt64) throws -> VerifiedRuleSnapshot {
        guard manifest.count <= 65536 else { throw RuleVerificationError.invalidManifest }
        let m: RuleManifest
        do { m = try JSONDecoder().decode(RuleManifest.self, from: manifest) }
        catch { throw RuleVerificationError.invalidManifest }
        // Exact reserialization also rejects duplicate/unknown keys, whitespace and alternate numeric encodings.
        guard try canonicalManifest(m) == manifest,
              m.keyID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
              m.payloadSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else { throw RuleVerificationError.invalidManifest }
        guard let key = trustedKeys[m.keyID] else { throw RuleVerificationError.unknownKey }
        guard m.schemaVersion == 1 else { throw RuleVerificationError.incompatibleSchema }
        guard let required = Self.version(m.minimumAppVersion), let current = Self.version(appVersion),
              !current.lexicographicallyPrecedes(required) else { throw RuleVerificationError.incompatibleApp }
        guard m.modelVersion >= installedVersion else { throw RuleVerificationError.downgrade }
        guard payload.count <= Self.maximumPayloadSize, m.payloadSize == UInt64(payload.count) else { throw RuleVerificationError.sizeMismatch }
        let hash = Data(SHA256.hash(data: payload))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        guard hex == m.payloadSHA256 else { throw RuleVerificationError.hashMismatch }
        let signed = Data("NecarambaRules-v1\0".utf8) + manifest + Data([0]) + hash
        guard signature.count == 64, let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              publicKey.isValidSignature(signature, for: signed) else { throw RuleVerificationError.invalidSignature }
        let snapshot: RuleSnapshot
        do {
            try Self.validatePayloadFields(payload)
            snapshot = try JSONDecoder().decode(RuleSnapshot.self, from: payload)
        } catch { throw RuleVerificationError.invalidPayload }
        guard snapshot.modelVersion == m.modelVersion, Self.valid(snapshot) else { throw RuleVerificationError.invalidPayload }
        return VerifiedRuleSnapshot(snapshot: snapshot, digest: hex)
    }
    /// Application profiles are a separate file signed by the key of the verified
    /// rule manifest, under their own domain so neither signature validates the other.
    public func verifyProfiles(manifest: Data, profiles: Data, signature: Data) throws -> ApplicationProfiles {
        guard manifest.count <= 65536, let m = try? JSONDecoder().decode(RuleManifest.self, from: manifest),
              (try? canonicalManifest(m)) == manifest else { throw RuleVerificationError.invalidManifest }
        guard let key = trustedKeys[m.keyID] else { throw RuleVerificationError.unknownKey }
        guard profiles.count <= ApplicationProfiles.maximumSize else { throw RuleVerificationError.sizeMismatch }
        let signed = Data("NecarambaAppProfiles-v1\0".utf8) + Data(SHA256.hash(data: profiles))
        guard signature.count == 64, let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              publicKey.isValidSignature(signature, for: signed) else { throw RuleVerificationError.invalidSignature }
        return try ApplicationProfiles(json: profiles)
    }
    private static func version(_ text: String) -> [UInt32]? {
        guard text.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", options: .regularExpression) != nil else { return nil }
        let values = text.split(separator: ".").compactMap { UInt32($0) }; return values.count == 3 ? values : nil
    }
    private static func validatePayloadFields(_ data: Data) throws {
        // A strict recursive JSON scanner rejects duplicate keys before Foundation decoding.
        try StrictRuleJSON.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["modelVersion", "lexicon", "typos", "yoRules", "protectedTokens", "mappings"] else { throw RuleVerificationError.invalidPayload }
        for (name, fields) in [("lexicon", Set(["word", "language", "frequencyBand"])), ("typos", Set(["source", "target", "caseSensitive"])), ("yoRules", Set(["source", "target", "caseSensitive"])), ("mappings", Set(["source", "target", "pairs"]))] {
            guard let records = root[name] as? [[String: Any]], records.allSatisfy({ Set($0.keys) == fields }) else { throw RuleVerificationError.invalidPayload }
        }
    }
    private static func valid(_ s: RuleSnapshot) -> Bool {
        func text(_ value: String, max: Int = 128) -> Bool { !value.isEmpty && value.count <= max && !value.unicodeScalars.contains { $0.properties.generalCategory == .control } }
        guard !s.lexicon.isEmpty, s.lexicon.count <= 500_000,
              s.lexicon.contains(where: { $0.language == .english }), s.lexicon.contains(where: { $0.language == .russian }),
              s.lexicon.allSatisfy({ text($0.word) }), s.typos.count <= 100_000, s.yoRules.count <= 100_000,
              (s.typos + s.yoRules).allSatisfy({ text($0.source) && text($0.target) }),
              s.protectedTokens.count <= 100_000, s.protectedTokens.allSatisfy({ text($0) }),
              s.mappings.count >= 2, s.mappings.count <= 32 else { return false }
        let directions = Set(s.mappings.map { "\($0.source.rawValue)->\($0.target.rawValue)" })
        guard directions.contains("US->RU"), directions.contains("RU->US") else { return false }
        return s.mappings.allSatisfy { m in text(m.source.rawValue) && text(m.target.rawValue) && m.source != m.target && !m.pairs.isEmpty && m.pairs.count <= 256 && m.pairs.allSatisfy { $0.key.count == 1 && $0.value.count == 1 && text($0.key) && text($0.value) } }
    }
}

// Bounded parser used solely for duplicate JSON member detection; Foundation performs actual decoding.
struct StrictRuleJSON {
    var bytes: [UInt8]; var index = 0
    static func validate(_ data: Data) throws { var parser = Self(bytes: Array(data)); try parser.value(depth: 0); parser.space(); guard parser.index == parser.bytes.count else { throw RuleVerificationError.invalidPayload } }
    mutating func space() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ b: UInt8) throws { space(); guard index < bytes.count && bytes[index] == b else { throw RuleVerificationError.invalidPayload }; index += 1 }
    mutating func string() throws -> String {
        space(); let start = index; try take(34)
        while index < bytes.count {
            let b = bytes[index]; index += 1
            if b == 92 { guard index < bytes.count else { break }; index += 1 }
            else if b == 34 { let data = Data(bytes[start..<index]); guard let s = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else { throw RuleVerificationError.invalidPayload }; return s }
        }
        throw RuleVerificationError.invalidPayload
    }
    mutating func value(depth: Int) throws {
        guard depth < 16 else { throw RuleVerificationError.invalidPayload }; space(); guard index < bytes.count else { throw RuleVerificationError.invalidPayload }
        switch bytes[index] {
        case 123:
            index += 1; space(); if index < bytes.count && bytes[index] == 125 { index += 1; return }; var keys = Set<String>()
            while true { let key = try string(); guard keys.insert(key).inserted else { throw RuleVerificationError.invalidPayload }; try take(58); try value(depth: depth + 1); space(); if index < bytes.count && bytes[index] == 125 { index += 1; return }; try take(44) }
        case 91:
            index += 1; space(); if index < bytes.count && bytes[index] == 93 { index += 1; return }
            while true { try value(depth: depth + 1); space(); if index < bytes.count && bytes[index] == 93 { index += 1; return }; try take(44) }
        case 34: _ = try string()
        default:
            let start = index; while index < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }; guard index > start else { throw RuleVerificationError.invalidPayload }
        }
    }
}
