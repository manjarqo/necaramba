import Foundation
import CoreFoundation

public struct NativeCommandFailure: Error {
    public let code: String
    public let requestID: String
    public let retryable: Bool
    public init(_ code: String, requestID: String = "", retryable: Bool = false) {
        self.code = code; self.requestID = requestID; self.retryable = retryable
    }
}
public struct NativeCommandReply {
    public let requestID: String
    public let state: [String: Any]
    public let result: [String: Any]
    public var wire: [String: Any] { ["requestID": requestID, "state": state, "result": result] }
}

/// Serial UI command adapter. Never called by event-tap code.
@MainActor public final class NativeCommandCoordinator {
    public let sessionID = UUID().uuidString
    private var revision = 0
    private let snapshot: () -> [String: Any]
    private let execute: (String, [String: Any]) async throws -> [String: Any]
    private var tail: Task<Void, Never>?
    private var waiting = 0
    private var cache: [String: (Data, [String: Any])] = [:]
    private var cacheOrder: [String] = []
    public var onStateChanged: (([String: Any]) -> Void)?
    private static let allowed: Set<String> = [
        "setPreferences", "addWord", "deleteWord", "clearWords", "chooseApp", "setAppMode", "deleteApp",
        "requestPermission", "refreshCapabilities", "setLoginEnabled", "setHeaderColor", "importHeaderImage",
        "removeHeaderImage", "getThumbnail", "chooseSound", "resetSound", "resetCounters", "checkRules",
        "previewShare", "confirmShare", "cancelShare", "purchase", "restore", "manageSubscription",
        "exportDiagnostics", "exportArchive", "importArchive"
    ]
    public init(snapshot: @escaping () -> [String: Any],
                execute: @escaping (String, [String: Any]) async throws -> [String: Any]) {
        self.snapshot = snapshot; self.execute = execute
    }
    public func state() -> [String: Any] {
        var value = snapshot()
        value["schema"] = 1; value["sessionID"] = sessionID; value["revision"] = revision
        return value
    }
    /// Native-origin changes (menu, permission state) use the same revision stream.
    public func publishChange() {
        revision += 1
        onStateChanged?(state())
    }
    public func command(_ method: String, envelope: [String: Any]) async throws -> NativeCommandReply {
        guard waiting < 32 else { throw NativeCommandFailure("unavailable", requestID: envelope["requestID"] as? String ?? "", retryable: true) }
        waiting += 1
        let previous = tail
        let task = Task { @MainActor [self] in
            await previous?.value
            return try await perform(method, envelope: envelope)
        }
        tail = Task { _ = await task.result }
        defer { waiting -= 1 }
        return try await task.value
    }
    private func perform(_ method: String, envelope: [String: Any]) async throws -> NativeCommandReply {
        let id = envelope["requestID"] as? String ?? ""
        guard Self.allowed.contains(method), !id.isEmpty, id.utf8.count <= 128,
              let arguments = envelope["arguments"] as? [String: Any],
              JSONSerialization.isValidJSONObject(arguments) else { throw NativeCommandFailure("invalidArgument", requestID: id) }
        let fingerprint = try JSONSerialization.data(withJSONObject: ["method": method, "arguments": arguments], options: [.sortedKeys])
        guard fingerprint.count <= 1024 * 1024 else { throw NativeCommandFailure("invalidArgument", requestID: id) }
        if let (original, result) = cache[id] {
            guard original == fingerprint else { throw NativeCommandFailure("conflict", requestID: id) }
            return NativeCommandReply(requestID: id, state: state(), result: result)
        }
        if method != "getThumbnail" {
            guard let expected = envelope["expectedRevision"] as? NSNumber,
                  CFGetTypeID(expected) != CFBooleanGetTypeID(),
                  ["q", "i", "s", "l"].contains(String(cString: expected.objCType)),
                  expected.doubleValue.isFinite,
                  expected.doubleValue.rounded(.towardZero) == expected.doubleValue,
                  expected.int64Value >= 0,
                  expected.int64Value == Int64(revision),
                  envelope["expectedSessionID"] as? String == sessionID else {
                throw NativeCommandFailure("conflict", requestID: id)
            }
        }
        do {
            let result = try await execute(method, arguments)
            if method != "getThumbnail" { revision += 1 }
            let reply = NativeCommandReply(requestID: id, state: state(), result: result)
            cache[id] = (fingerprint, result); cacheOrder.append(id)
            if cacheOrder.count > 128 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
            onStateChanged?(reply.state)
            return NativeCommandReply(requestID: id, state: state(), result: result)
        } catch let failure as NativeCommandFailure {
            throw NativeCommandFailure(failure.code, requestID: id, retryable: failure.retryable)
        } catch {
            throw NativeCommandFailure("ioFailure", requestID: id)
        }
    }
}
