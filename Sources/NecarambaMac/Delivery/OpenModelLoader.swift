import Foundation
import Darwin
import CryptoKit
import NecarambaCore

public struct LoadedOpenModel: Sendable {
  public let version: String
  public let engine: OpenCorrectionEngine
}

/// Bundled open data is hash-verified before compilation off the main thread.
/// This is not a network update or a replacement for the signed-rule update protocol.
public enum OpenModelLoader {
  public enum LoadingError: Error { case invalidFile, resourceLimit, invalidManifest, digestMismatch }
  private struct Manifest: Decodable {
    let schemaVersion: Int
    let version: String
    let files: [String: Entry]
    struct Entry: Decodable { let sha256: String; let bytes: Int }
  }
  public static func load(directory: URL) throws -> LoadedOpenModel {
    guard directory.isFileURL else { throw LoadingError.invalidFile }
    let manifest = try JSONDecoder().decode(Manifest.self,
      from: read(directory.appendingPathComponent("manifest.json"), limit: 64 * 1024))
    let names: Set<String> = ["en.words", "ru.words", "corrections.json"]
    guard manifest.schemaVersion == 1, !manifest.version.isEmpty,
      Set(manifest.files.keys) == names else { throw LoadingError.invalidManifest }
    var declaredTotal = 0
    for name in names {
      let size = manifest.files[name]!.bytes
      let limit = name == "corrections.json" ? 8 * 1024 * 1024 : 64 * 1024 * 1024
      guard size > 0, size <= limit, size <= 64 * 1024 * 1024 - declaredTotal else {
        throw LoadingError.resourceLimit
      }
      declaredTotal += size
    }
    var data: [String: Data] = [:]
    var total = 0
    for name in names.sorted() {
      let entry = manifest.files[name]!
      let limit = name == "corrections.json" ? 8 * 1024 * 1024 : 64 * 1024 * 1024
      guard entry.bytes > 0, entry.bytes <= limit else { throw LoadingError.resourceLimit }
      let bytes = try read(directory.appendingPathComponent(name), limit: entry.bytes)
      let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      guard bytes.count == entry.bytes, hash == entry.sha256 else { throw LoadingError.digestMismatch }
      total += bytes.count
      guard total <= 64 * 1024 * 1024 else { throw LoadingError.resourceLimit }
      data[name] = bytes
    }
    let rules = try OpenCorrectionRules(data: data["corrections.json"]!)
    guard rules.version == manifest.version else { throw LoadingError.invalidManifest }
    let lexicon = try PackedOpenLexicon(english: data["en.words"]!, russian: data["ru.words"]!)
    return LoadedOpenModel(version: manifest.version,
      engine: OpenCorrectionEngine(lexicon: lexicon, rules: rules))
  }
  private static func read(_ url: URL, limit: Int) throws -> Data {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw LoadingError.invalidFile }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var attributes = stat()
    guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw LoadingError.invalidFile }
    guard attributes.st_size > 0, attributes.st_size <= limit else { throw LoadingError.resourceLimit }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw LoadingError.resourceLimit }
    return data
  }
}
