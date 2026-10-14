public enum AppOverride: String, Sendable, Equatable { case allow, deny }
public enum PolicyReason: String, Sendable, Equatable {
    case allowed, secureInput, cannotListen, cannotPost, unsupportedContext, appDenied, profileDenied, globallyDisabled
}
public struct PolicyInput: Sendable, Equatable {
    public let preferences: PreferencesSnapshot
    public let appOverride: AppOverride?
    public let profileAllowsAuto: Bool
    public let secureInput: Bool
    public let canListen: Bool
    public let canPost: Bool
    public let supportedContext: Bool
    public init(preferences: PreferencesSnapshot, appOverride: AppOverride?, profileAllowsAuto: Bool, secureInput: Bool, canListen: Bool, canPost: Bool, supportedContext: Bool) {
        self.preferences = preferences; self.appOverride = appOverride; self.profileAllowsAuto = profileAllowsAuto; self.secureInput = secureInput; self.canListen = canListen; self.canPost = canPost; self.supportedContext = supportedContext
    }
}
public struct PolicyDecision: Sendable, Equatable {
    public let autoAllowed: Bool
    public let manualAllowed: Bool
    public let reason: PolicyReason
    public init(autoAllowed: Bool, manualAllowed: Bool, reason: PolicyReason) {
        self.autoAllowed = autoAllowed; self.manualAllowed = manualAllowed; self.reason = reason
    }
}
public enum PolicyResolver {
    public static func resolve(_ input: PolicyInput) -> PolicyDecision {
        let safety: PolicyReason?
        if input.secureInput { safety = .secureInput }
        else if !input.canListen { safety = .cannotListen }
        else if !input.canPost { safety = .cannotPost }
        else if !input.supportedContext { safety = .unsupportedContext }
        else { safety = nil }
        if let safety { return .init(autoAllowed: false, manualAllowed: false, reason: safety) }
        if input.appOverride == .allow { return .init(autoAllowed: true, manualAllowed: true, reason: .allowed) }
        if input.appOverride == .deny { return .init(autoAllowed: false, manualAllowed: true, reason: .appDenied) }
        if !input.profileAllowsAuto { return .init(autoAllowed: false, manualAllowed: true, reason: .profileDenied) }
        if !input.preferences.autoEnabled { return .init(autoAllowed: false, manualAllowed: true, reason: .globallyDisabled) }
        return .init(autoAllowed: true, manualAllowed: true, reason: .allowed)
    }
}
