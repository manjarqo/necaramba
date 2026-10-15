public enum LayoutSwitchShortcut: String, Codable, Sendable, CaseIterable {
    case singleShift, altShift, controlShift, commandShift, disabled
}

public struct PreferencesSnapshot: Codable, Sendable, Equatable {
    public let autoEnabled: Bool
    public let typoEnabled: Bool
    public let yoEnabled: Bool
    public let layoutSwitchShortcut: LayoutSwitchShortcut
    public var singleShiftEnabled: Bool { layoutSwitchShortcut == .singleShift }
    public let optionEnabled: Bool
    public let splitShiftEnabled: Bool
    public let plainPasteEnabled: Bool
    public let soundEnabled: Bool

    public init(autoEnabled: Bool = true, typoEnabled: Bool = true, yoEnabled: Bool = true, singleShiftEnabled: Bool = true, optionEnabled: Bool = false, splitShiftEnabled: Bool = false, plainPasteEnabled: Bool = true, soundEnabled: Bool = true, layoutSwitchShortcut: LayoutSwitchShortcut? = nil) {
        self.autoEnabled = autoEnabled
        self.typoEnabled = typoEnabled
        self.yoEnabled = yoEnabled
        self.layoutSwitchShortcut = layoutSwitchShortcut ?? (singleShiftEnabled ? .singleShift : .disabled)
        self.optionEnabled = optionEnabled
        self.splitShiftEnabled = splitShiftEnabled
        self.plainPasteEnabled = plainPasteEnabled
        self.soundEnabled = soundEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case autoEnabled, typoEnabled, yoEnabled, singleShiftEnabled, optionEnabled
        case splitShiftEnabled, plainPasteEnabled, soundEnabled, layoutSwitchShortcut
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try values.decodeIfPresent(Bool.self, forKey: .singleShiftEnabled)
        let shortcut = try values.decodeIfPresent(LayoutSwitchShortcut.self, forKey: .layoutSwitchShortcut)
        if let legacy, let shortcut, legacy != (shortcut == .singleShift) {
            throw DecodingError.dataCorruptedError(forKey: .layoutSwitchShortcut, in: values,
                                                  debugDescription: "Conflicting layout shortcut preferences")
        }
        self.init(autoEnabled: try values.decode(Bool.self, forKey: .autoEnabled),
                  typoEnabled: try values.decode(Bool.self, forKey: .typoEnabled),
                  yoEnabled: try values.decode(Bool.self, forKey: .yoEnabled),
                  singleShiftEnabled: legacy ?? true,
                  optionEnabled: try values.decode(Bool.self, forKey: .optionEnabled),
                  splitShiftEnabled: try values.decode(Bool.self, forKey: .splitShiftEnabled),
                  plainPasteEnabled: try values.decode(Bool.self, forKey: .plainPasteEnabled),
                  soundEnabled: try values.decode(Bool.self, forKey: .soundEnabled),
                  layoutSwitchShortcut: shortcut)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(autoEnabled, forKey: .autoEnabled)
        try values.encode(typoEnabled, forKey: .typoEnabled)
        try values.encode(yoEnabled, forKey: .yoEnabled)
        try values.encode(singleShiftEnabled, forKey: .singleShiftEnabled)
        try values.encode(optionEnabled, forKey: .optionEnabled)
        try values.encode(splitShiftEnabled, forKey: .splitShiftEnabled)
        try values.encode(plainPasteEnabled, forKey: .plainPasteEnabled)
        try values.encode(soundEnabled, forKey: .soundEnabled)
        try values.encode(layoutSwitchShortcut, forKey: .layoutSwitchShortcut)
    }

    public static let defaults = PreferencesSnapshot()
}
