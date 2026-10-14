import Foundation

public enum PermissionKind: String, Codable, Sendable { case listen, post, ax }

public struct PermissionState: Equatable, Codable, Sendable {
    public let listen: Bool
    public let post: Bool
    public let ax: Bool
    public let secureInput: Bool
    public init(listen: Bool, post: Bool, ax: Bool, secureInput: Bool) {
        self.listen = listen; self.post = post; self.ax = ax; self.secureInput = secureInput
    }
}
public protocol PermissionReading: AnyObject {
    func current() -> PermissionState
    func request(_ kind: PermissionKind)
}
public enum CapabilityReason: String, Codable, Sendable {
    case available, secureInput, missingListen, missingPost, unsupportedFocus
}
public struct InputCapabilities: Equatable, Sendable {
    public let auto: Bool
    public let manual: Bool
    public let selection: Bool
    public let reason: CapabilityReason
}
public enum CapabilityRegistry {
    public static func evaluate(_ state: PermissionState, supportsFocus: Bool) -> InputCapabilities {
        let reason: CapabilityReason
        if state.secureInput { reason = .secureInput }
        else if !state.listen { reason = .missingListen }
        else if !state.post { reason = .missingPost }
        else if !supportsFocus { reason = .unsupportedFocus }
        else { reason = .available }
        let safe = reason == .available
        return InputCapabilities(auto: safe, manual: safe, selection: safe && state.ax, reason: reason)
    }
}
