import Foundation

/// Corpus contracts have no file-system or cryptographic dependency. The CLI supplies both adapters.
public struct CorpusManifest: Decodable, Sendable {
    public struct Asset: Decodable, Sendable { public let path: String; public let sha256: String }
    public struct CorpusFile: Decodable, Sendable { public let path: String; public let sha256: String; public let count: Int; public let split: CorpusSplit }
    public struct Source: Decodable, Sendable { public let id: String; public let licensePath: String; public let licenseSHA256: String; public let description: String }
    public struct Provenance: Decodable, Sendable {
        public struct File: Decodable, Sendable { public let path: String; public let url: String; public let sha256: String }
        public let repository: String; public let revision: String; public let files: [File]
    }
    public let schemaVersion: Int
    public let corpusVersion: String
    public let rules: Asset
    public let files: [CorpusFile]
    public let sources: [Source]
    public let provenance: Provenance
    public let minimumTotal: Int
    public static func validateRelativePath(_ value: String) throws {
        let components = value.components(separatedBy: "/")
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !components.contains(".."), !components.contains("."), !components.contains("") else {
            throw CorpusValidationError.invalid("Unsafe manifest path")
        }
    }
    public static func decode(_ data: Data) throws -> CorpusManifest {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == Set(["schemaVersion", "corpusVersion", "rules", "files", "sources", "provenance", "minimumTotal"]) else { throw CorpusValidationError.invalid("Invalid manifest schema") }
        func keys(_ value: Any?, _ expected: Set<String>) throws {
            guard let dictionary = value as? [String: Any], Set(dictionary.keys) == expected else { throw CorpusValidationError.invalid("Unknown/missing nested manifest fields") }
        }
        try keys(object["rules"], ["path", "sha256"])
        for value in object["files"] as? [Any] ?? [] { try keys(value, ["path", "sha256", "count", "split"]) }
        for value in object["sources"] as? [Any] ?? [] { try keys(value, ["id", "licensePath", "licenseSHA256", "description"]) }
        try keys(object["provenance"], ["repository", "revision", "files"])
        if let provenance = object["provenance"] as? [String: Any] {
            for value in provenance["files"] as? [Any] ?? [] { try keys(value, ["path", "url", "sha256"]) }
        }
        let manifest = try JSONDecoder().decode(CorpusManifest.self, from: data)
        guard manifest.schemaVersion == 1, !manifest.corpusVersion.isEmpty, manifest.minimumTotal >= 10000, !manifest.sources.isEmpty,
              Set(manifest.sources.map(\.id)).count == manifest.sources.count,
              Set(manifest.files.map(\.split)) == Set([.train, .calibration, .holdout]),
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              manifest.provenance.revision.count == 40, !manifest.provenance.files.isEmpty else { throw CorpusValidationError.invalid("Invalid manifest values") }
        let paths = [manifest.rules.path] + manifest.files.map(\.path) + manifest.sources.map(\.licensePath) + manifest.provenance.files.map(\.path)
        for path in paths { try validateRelativePath(path) }
        let hashes = [manifest.rules.sha256] + manifest.files.map(\.sha256) + manifest.provenance.files.map(\.sha256) + manifest.sources.map(\.licenseSHA256)
        guard hashes.allSatisfy({ $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }), manifest.files.allSatisfy({ $0.count > 0 }), manifest.sources.allSatisfy({ !$0.id.isEmpty && !$0.description.isEmpty }) else { throw CorpusValidationError.invalid("Invalid manifest hash/count/license") }
        return manifest
    }
    public func validate(read: (String) throws -> Data, digest: (Data) -> String) throws -> [CorpusCase] {
        guard digest(try read(rules.path)) == rules.sha256 else { throw CorpusValidationError.invalid("Rules SHA256 mismatch") }
        for file in provenance.files {
            guard file.url.hasPrefix("https://"), file.url.contains(provenance.revision), digest(try read(file.path)) == file.sha256 else { throw CorpusValidationError.invalid("Source provenance mismatch") }
        }
        for source in sources {
            guard digest(try read(source.licensePath)) == source.licenseSHA256 else { throw CorpusValidationError.invalid("Missing source license") }
        }
        var all: [CorpusCase] = []
        for file in files {
            let data = try read(file.path)
            guard digest(data) == file.sha256 else { throw CorpusValidationError.invalid("Corpus SHA256 mismatch: \(file.path)") }
            let rows = try CorpusValidator.decodeJSONL(data)
            guard rows.count == file.count, rows.allSatisfy({ $0.split == file.split }) else { throw CorpusValidationError.invalid("Corpus count/split mismatch") }
            all += rows
        }
        try CorpusValidator.validate(all)
        let licenses = Set(sources.map(\.id))
        guard all.count >= minimumTotal, all.allSatisfy({ licenses.contains($0.sourceLicense) }) else { throw CorpusValidationError.invalid("Corpus size or source license failed") }
        return all
    }
}
