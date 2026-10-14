import ApplicationServices
import Carbon
import NecarambaCore

public protocol PermissionAPI: AnyObject {
    func listenAllowed() -> Bool
    func postAllowed() -> Bool
    func axAllowed() -> Bool
    func secureInputEnabled() -> Bool
    func request(_ kind: PermissionKind)
}
public final class SystemPermissionAPI: PermissionAPI {
    public init() {}
    public func listenAllowed() -> Bool { CGPreflightListenEventAccess() }
    public func postAllowed() -> Bool { CGPreflightPostEventAccess() }
    public func axAllowed() -> Bool { AXIsProcessTrusted() }
    public func secureInputEnabled() -> Bool { IsSecureEventInputEnabled() }
    public func request(_ kind: PermissionKind) {
        switch kind {
        case .listen: _ = CGRequestListenEventAccess()
        case .post: _ = CGRequestPostEventAccess()
        case .ax:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
}
public final class PermissionMonitor: PermissionReading {
    private let api: PermissionAPI
    public init(api: PermissionAPI = SystemPermissionAPI()) { self.api = api }
    public func current() -> PermissionState {
        PermissionState(listen: api.listenAllowed(), post: api.postAllowed(),
                        ax: api.axAllowed(), secureInput: api.secureInputEnabled())
    }
    public func request(_ kind: PermissionKind) { api.request(kind) }
}
