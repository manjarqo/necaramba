import AppKit
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
    private let requestAccess: (PermissionKind) -> Void
    private let openSettings: (URL) -> Bool
    private let settingsBase: String
    public init(requestAccess: ((PermissionKind) -> Void)? = nil,
                openSettings: ((URL) -> Bool)? = nil,
                osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.requestAccess = requestAccess ?? Self.requestSystemAccess
        self.openSettings = openSettings ?? { NSWorkspace.shared.open($0) }
        settingsBase = osMajorVersion >= 13
            ? "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
            : "x-apple.systempreferences:com.apple.preference.security"
    }
    public func listenAllowed() -> Bool { CGPreflightListenEventAccess() }
    public func postAllowed() -> Bool { CGPreflightPostEventAccess() }
    public func axAllowed() -> Bool { AXIsProcessTrusted() }
    public func secureInputEnabled() -> Bool { IsSecureEventInputEnabled() }
    public func request(_ kind: PermissionKind) {
        requestAccess(kind)
        // Permission APIs may stop showing prompts after a previous denial. An
        // explicit user request must still navigate to the corresponding pane.
        let pane = kind == .listen ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        if !openSettings(URL(string: "\(settingsBase)?\(pane)")!) {
            _ = openSettings(URL(string: settingsBase)!)
        }
    }
    private static func requestSystemAccess(_ kind: PermissionKind) {
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
