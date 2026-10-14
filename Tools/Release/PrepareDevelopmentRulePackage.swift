// DEVELOPMENT ONLY. Private key exists in memory and is never written.
// Compile with RuleManifest.swift, like SignRulePackage.swift. Arguments: payload.json output-directory
import Foundation
import CryptoKit
@main struct PrepareDevelopmentRulePackage {
    static func main() {
        do {
            guard CommandLine.arguments.count == 3 else { throw PreparationError.invalidInput }
            let source = URL(fileURLWithPath: CommandLine.arguments[1])
            guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 20 * 1024 * 1024 else { throw PreparationError.invalidInput }
            let payload = try Data(contentsOf: source)
            guard let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any], let number = json["modelVersion"] as? NSNumber, let modelVersion = UInt64(number.stringValue) else { throw PreparationError.invalidInput }
            let digest = Data(SHA256.hash(data: payload)); let key = Curve25519.Signing.PrivateKey()
            let manifest = try canonicalManifest(.init(schemaVersion: 1, modelVersion: modelVersion, minimumAppVersion: "1.0.0", payloadSize: UInt64(payload.count), payloadSHA256: digest.map { String(format: "%02x", $0) }.joined(), keyID: "development-only"))
            let signature = try key.signature(for: Data("NecarambaRules-v1\0".utf8) + manifest + Data([0]) + digest)
            let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try manifest.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
            try signature.write(to: output.appendingPathComponent("signature.ed25519"), options: .atomic)
            try JSONSerialization.data(withJSONObject: ["development-only": key.publicKey.rawRepresentation.base64EncodedString()], options: [.sortedKeys]).write(to: output.appendingPathComponent("DevelopmentTrustedRuleKeys.json"), options: .atomic)
            try Data("{\"developmentOnly\":true,\"releaseAllowed\":false}\n".utf8).write(to: output.appendingPathComponent("DevelopmentOnly.json"), options: .atomic)
            // Caller copies the independently licensed payload only after integration. No release credentials are produced.
        } catch {
            FileHandle.standardError.write(Data("Development package preparation failed\n".utf8)); exit(1)
        }
    }
    enum PreparationError: Error { case invalidInput }
}
