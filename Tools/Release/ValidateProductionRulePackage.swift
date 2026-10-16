import Foundation

/// Checks the exact package that the Runner embed phase will copy into Rules/Production.
@main struct ValidateProductionRulePackage {
    enum Failure: Error { case invalid }
    static let files: Set<String> = ["manifest.json", "signature.ed25519", "payload.json", "TrustedRuleKeys.json", "Licenses"]

    static func main() {
        do {
            guard CommandLine.arguments.count == 4 else { throw Failure.invalid }
            try validate(directory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
                         appVersion: CommandLine.arguments[2],
                         developmentKeys: URL(fileURLWithPath: CommandLine.arguments[3]))
            print("Production rule package validated")
        } catch {
            // Paths and package content can be private owner inputs.
            FileHandle.standardError.write(Data("Production rule package validation failed\n".utf8))
            exit(1)
        }
    }

    static func validate(directory: URL, appVersion: String, developmentKeys: URL) throws {
        let manager = FileManager.default
        let present = Set(try manager.contentsOfDirectory(atPath: directory.path))
        let profileFiles: Set<String> = ["profiles.json", "profiles.signature.ed25519"]
        // Application profiles are optional, but only as a complete signed pair.
        guard try isDirectory(directory), present == files || present == files.union(profileFiles) else { throw Failure.invalid }
        let licenses = directory.appendingPathComponent("Licenses", isDirectory: true)
        guard try isDirectory(licenses) else { throw Failure.invalid }
        let licenseNames = try manager.contentsOfDirectory(atPath: licenses.path)
        guard !licenseNames.isEmpty, licenseNames.count <= 50 else { throw Failure.invalid }
        for name in licenseNames {
            guard name.range(of: "^[A-Za-z0-9._-]+\\.txt$", options: .regularExpression) != nil,
                  !(try boundedRead(licenses.appendingPathComponent(name), limit: 1024 * 1024)).isEmpty else { throw Failure.invalid }
        }
        let keyBytes = try boundedRead(directory.appendingPathComponent("TrustedRuleKeys.json"), limit: 65536)
        let encoded = try JSONDecoder().decode([String: String].self, from: keyBytes)
        let canonical = try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys, .withoutEscapingSlashes])
        guard !encoded.isEmpty, canonical == keyBytes else { throw Failure.invalid }
        let developmentEncoded = try JSONDecoder().decode([String: String].self,
            from: boundedRead(developmentKeys, limit: 65536))
        let developmentKeyBytes = Set(developmentEncoded.values.compactMap { Data(base64Encoded: $0) })
        guard !developmentKeyBytes.isEmpty else { throw Failure.invalid }
        var keys: [String: Data] = [:]
        for (id, value) in encoded {
            let lower = id.lowercased()
            guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
                  !lower.contains("development"), !lower.contains("test"),
                  let key = Data(base64Encoded: value), key.count == 32,
                  !developmentKeyBytes.contains(key) else { throw Failure.invalid }
            keys[id] = key
        }
        let manifest = try boundedRead(directory.appendingPathComponent("manifest.json"), limit: 65536)
        let signature = try boundedRead(directory.appendingPathComponent("signature.ed25519"), limit: 64)
        let payload = try boundedRead(directory.appendingPathComponent("payload.json"), limit: RulePackageVerifier.maximumPayloadSize)
        let verifier = RulePackageVerifier(trustedKeys: keys, appVersion: appVersion)
        _ = try verifier.verify(manifest: manifest, signature: signature, payload: payload, installedVersion: 0)
        if present.isSuperset(of: profileFiles) {
            _ = try verifier.verifyProfiles(manifest: manifest,
                profiles: boundedRead(directory.appendingPathComponent("profiles.json"), limit: ApplicationProfiles.maximumSize),
                signature: boundedRead(directory.appendingPathComponent("profiles.signature.ed25519"), limit: 64))
        }
    }

    static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalid }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw Failure.invalid }
        return bytes
    }
}
