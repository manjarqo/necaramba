import Foundation

public struct RuleManifest: Codable, Equatable, Sendable {
    public let schemaVersion: UInt32
    public let modelVersion: UInt64
    public let minimumAppVersion: String
    public let payloadSize: UInt64
    public let payloadSHA256: String
    public let keyID: String
    public init(schemaVersion: UInt32, modelVersion: UInt64, minimumAppVersion: String, payloadSize: UInt64, payloadSHA256: String, keyID: String) {
        self.schemaVersion = schemaVersion; self.modelVersion = modelVersion
        self.minimumAppVersion = minimumAppVersion; self.payloadSize = payloadSize
        self.payloadSHA256 = payloadSHA256; self.keyID = keyID
    }
}

public enum RuleVerificationError: Error, Equatable {
    case invalidSignature, unknownKey, hashMismatch, sizeMismatch
    case incompatibleSchema, incompatibleApp, downgrade, invalidPayload, invalidManifest
    case conflictingVersion
}

public func canonicalManifest(_ manifest: RuleManifest) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(manifest)
}

public struct RulePackage: Sendable {
    public let manifest: Data
    public let signature: Data
    public let payload: Data
    public init(manifest: Data, signature: Data, payload: Data) {
        self.manifest = manifest; self.signature = signature; self.payload = payload
    }
}
