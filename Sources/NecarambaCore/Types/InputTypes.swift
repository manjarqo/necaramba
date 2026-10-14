public struct LayoutID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum Language: String, Codable, Sendable {
    case english, russian
}

public enum Modifier: String, Codable, Hashable, Sendable {
    case shift, option, command, control, capsLock, function
}

public enum EventKind: String, Codable, Sendable {
    case down, up, flagsChanged
}

public enum EventOrigin: String, Codable, Sendable {
    case physical, ours, foreignSynthetic, unknown
}

public enum InvalidationReason: String, Codable, Sendable {
    case focusChanged, layoutChanged, secureInput, permissionRevoked, mouseNavigation, unknownInput, sleep, sessionLock
}

public struct ContextToken: Codable, Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let focusEpoch: UInt64
    public let layoutEpoch: UInt64

    public init(pid: Int32, bundleID: String, focusEpoch: UInt64, layoutEpoch: UInt64) {
        self.pid = pid
        self.bundleID = bundleID
        self.focusEpoch = focusEpoch
        self.layoutEpoch = layoutEpoch
    }
}

public struct InputEvent: Sendable, Equatable {
    public let kind: EventKind
    public let keyCode: UInt16
    public let modifiers: Set<Modifier>
    public let timestampNanos: UInt64
    public let layout: LayoutID
    public let context: ContextToken
    public let origin: EventOrigin
    public let text: String?
    public let isRepeat: Bool

    public init(kind: EventKind, keyCode: UInt16, modifiers: Set<Modifier>, timestampNanos: UInt64, layout: LayoutID, context: ContextToken, origin: EventOrigin, text: String?, isRepeat: Bool) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.timestampNanos = timestampNanos
        self.layout = layout
        self.context = context
        self.origin = origin
        self.text = text
        self.isRepeat = isRepeat
    }
}
