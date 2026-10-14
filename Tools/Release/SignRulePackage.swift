// Compile with the shared format source:
// swiftc Sources/NecarambaCore/Delivery/RuleManifest.swift Tools/Release/SignRulePackage.swift -o /tmp/necaramba-sign-rules
import Foundation
import CryptoKit

@main struct SignRulePackage {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 5 else { throw SigningError.usage }
            let manifestBytes = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            guard manifestBytes.count <= 65536 else { throw SigningError.invalidInput }
            let manifest = try JSONDecoder().decode(RuleManifest.self, from: manifestBytes)
            let canonical = try canonicalManifest(manifest)
            guard canonical == manifestBytes, manifest.schemaVersion == 1 else { throw SigningError.invalidInput }
            let payloadURL = URL(fileURLWithPath: args[2])
            let size = try payloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 20 * 1024 * 1024 else { throw SigningError.invalidInput }
            let payload = try Data(contentsOf: payloadURL)
            let digest = Data(SHA256.hash(data: payload))
            guard manifest.payloadSize == UInt64(payload.count), manifest.payloadSHA256 == digest.map({ String(format: "%02x", $0) }).joined() else { throw SigningError.invalidInput }
            let rawKey = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
            let signature = try key.signature(for: Data("NecarambaRules-v1\0".utf8) + canonical + Data([0]) + digest)
            try signature.write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        } catch {
            // Do not print arguments, private material, words or package contents.
            FileHandle.standardError.write(Data("Signing failed. Usage: sign-rules manifest.json payload.json private-key.bin signature.ed25519\n".utf8))
            exit(1)
        }
    }
    enum SigningError: Error { case usage, invalidInput }
}
