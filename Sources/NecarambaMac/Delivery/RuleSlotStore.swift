import Foundation
import Darwin
import NecarambaCore

public enum RuleStorageError: Error { case invalidState, ioFailure, noVerifiedRules }

/// One writer, durable state-file commit. The root is application-owned, never a user document location.
public final class RuleSlotStore {
    private struct State: Codable {
        var current: UInt64?
        var previous: UInt64?
        var highestAcceptedVersion: UInt64
        var digests: [String: String]
    }
    private let root: URL
    private let verifier: RulePackageVerifier
    private let lock = NSLock()
    private var bundledIdentity: (version: UInt64, digest: String)?
    private let durability: RuleDurability
    public init(root: URL, verifier: RulePackageVerifier, durability: RuleDurability = POSIXRuleDurability()) { self.root = root; self.verifier = verifier; self.durability = durability }
    public func promote(_ package: RulePackage) throws -> VerifiedRuleSnapshot {
        lock.lock(); defer { lock.unlock() }
        var state = try readState()
        let verified = try verifier.verify(manifest: package.manifest, signature: package.signature, payload: package.payload, installedVersion: max(state.highestAcceptedVersion, bundledIdentity?.version ?? 0))
        let id = String(verified.modelVersion)
        if let bundledIdentity, verified.modelVersion == bundledIdentity.version, verified.digest != bundledIdentity.digest { throw RuleVerificationError.conflictingVersion }
        if let digest = state.digests[id] {
            guard digest == verified.digest else { throw RuleVerificationError.conflictingVersion }
            // Never call an equal-version package current if the state hasn't committed it.
            if state.current == verified.modelVersion { return try readVerified(version: verified.modelVersion, state: state) }
        }
        let fm = FileManager.default
        let generations = root.appendingPathComponent("generations", isDirectory: true)
        try fm.createDirectory(at: generations, withIntermediateDirectories: true)
        let staging = generations.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try write(package, to: staging)
        let reread = try readPackage(at: staging)
        let checked = try verifier.verify(manifest: reread.manifest, signature: reread.signature, payload: reread.payload, installedVersion: max(state.highestAcceptedVersion, bundledIdentity?.version ?? 0))
        guard checked.digest == verified.digest else { throw RuleVerificationError.hashMismatch }
        try durability.syncDirectory(staging)
        let destination = generations.appendingPathComponent(id, isDirectory: true)
        if fm.fileExists(atPath: destination.path) {
            let existing = try readPackage(at: destination)
            let candidate = try verifier.verify(manifest: existing.manifest, signature: existing.signature, payload: existing.payload, installedVersion: max(state.highestAcceptedVersion, bundledIdentity?.version ?? 0))
            guard candidate.digest == verified.digest else { throw RuleVerificationError.conflictingVersion }
        } else { try durability.rename(staging, to: destination) }
        try durability.syncDirectory(generations)
        // Preserve only a verified old slot as last-known-good.
        let old = [state.current, state.previous].compactMap { $0 }.first { (try? readVerified(version: $0, state: state)) != nil }
        state.previous = old; state.current = verified.modelVersion
        state.highestAcceptedVersion = max(state.highestAcceptedVersion, verified.modelVersion)
        state.digests[id] = verified.digest
        let retained = Set([state.current, state.previous, state.highestAcceptedVersion].compactMap { $0 }.map(String.init))
        state.digests = state.digests.filter { retained.contains($0.key) }
        let temp = root.appendingPathComponent(".state-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        try durability.write(JSONEncoder().encode(state), to: temp)
        try durability.rename(temp, to: root.appendingPathComponent("state.json"))
        try durability.syncDirectory(root)
        return verified
    }
    public func load(bundled: RulePackage) throws -> VerifiedRuleSnapshot {
        lock.lock(); defer { lock.unlock() }
        let bundledVerified = try? verifier.verify(manifest: bundled.manifest, signature: bundled.signature,
                                                   payload: bundled.payload, installedVersion: 0)
        if let bundledVerified { bundledIdentity = (bundledVerified.modelVersion, bundledVerified.digest) }
        // A missing or malformed state cannot authenticate installed generations or their
        // high-water mark. Keep verified bundled input available, but do not reset state.
        guard let state = try? readState() else {
            guard let bundledVerified else { throw RuleStorageError.noVerifiedRules }
            return bundledVerified
        }
        for id in [state.current, state.previous].compactMap({ $0 }) {
            if let verified = try? readVerified(version: id, state: state) { cleanup(state: state); return verified }
        }
        // Previously bundled material is a local fallback, never a remote promotion.
        guard let bundledVerified else { throw RuleStorageError.noVerifiedRules }
        cleanup(state: state); return bundledVerified
    }
    private func cleanup(state: State) {
        let generations = root.appendingPathComponent("generations")
        let retained = Set([state.current, state.previous].compactMap { $0 }.map(String.init))
        guard let items = try? FileManager.default.contentsOfDirectory(at: generations, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let name = item.lastPathComponent
            if !retained.contains(name), UInt64(name) != nil || name.hasPrefix(".staging-") { try? FileManager.default.removeItem(at: item) }
        }
    }
    private func readState() throws -> State {
        let url = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            let generations = root.appendingPathComponent("generations")
            if FileManager.default.fileExists(atPath: generations.path) {
                let entries = try FileManager.default.contentsOfDirectory(atPath: generations.path)
                guard entries.allSatisfy({ $0.hasPrefix(".staging-") }) else { throw RuleStorageError.invalidState }
            }
            return State(current: nil, previous: nil, highestAcceptedVersion: 0, digests: [:])
        }
        do {
            let data = try boundedRead(url, limit: 65536)
            let state = try JSONDecoder().decode(State.self, from: data)
            guard state.current.map({ $0 <= state.highestAcceptedVersion }) ?? true,
                  state.previous.map({ $0 <= state.highestAcceptedVersion }) ?? true else { throw RuleStorageError.invalidState }
            return state
        } catch { throw RuleStorageError.invalidState }
    }
    private func readVerified(version: UInt64, state: State) throws -> VerifiedRuleSnapshot {
        let package = try readPackage(at: root.appendingPathComponent("generations/\(version)"))
        let verified = try verifier.verify(manifest: package.manifest, signature: package.signature, payload: package.payload, installedVersion: 0)
        guard verified.modelVersion == version, state.digests[String(version)] == verified.digest else { throw RuleStorageError.invalidState }
        return verified
    }
    private func readPackage(at path: URL) throws -> RulePackage {
        .init(manifest: try boundedRead(path.appendingPathComponent("manifest.json"), limit: 65536), signature: try boundedRead(path.appendingPathComponent("signature.ed25519"), limit: 64), payload: try boundedRead(path.appendingPathComponent("payload.json"), limit: RulePackageVerifier.maximumPayloadSize))
    }
    private func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw RuleStorageError.ioFailure }; return data
    }
    private func write(_ package: RulePackage, to path: URL) throws {
        try durability.write(package.manifest, to: path.appendingPathComponent("manifest.json"))
        try durability.write(package.signature, to: path.appendingPathComponent("signature.ed25519"))
        try durability.write(package.payload, to: path.appendingPathComponent("payload.json"))
    }
}

/// Filesystem durability boundary used by the slot adapter. Faulted implementations can exercise commit failures without touching real stores.
public protocol RuleDurability {
    func write(_ data: Data, to url: URL) throws
    func rename(_ source: URL, to destination: URL) throws
    func syncDirectory(_ url: URL) throws
}
public struct POSIXRuleDurability: RuleDurability {
    public init() {}
    public func rename(_ source: URL, to destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else { throw RuleStorageError.ioFailure }
    }
    public func write(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuleStorageError.ioFailure }; defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw RuleStorageError.ioFailure }; offset += result
            }
        }
        guard fsync(fd) == 0 else { throw RuleStorageError.ioFailure }
    }
    public func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY); guard fd >= 0 else { throw RuleStorageError.ioFailure }; defer { close(fd) }
        guard fsync(fd) == 0 else { throw RuleStorageError.ioFailure }
    }
}
