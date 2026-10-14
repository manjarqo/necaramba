public struct PreferencesSnapshot: Codable, Sendable, Equatable {
    public let autoEnabled: Bool
    public let typoEnabled: Bool
    public let yoEnabled: Bool
    public let singleShiftEnabled: Bool
    public let optionEnabled: Bool
    public let splitShiftEnabled: Bool
    public let plainPasteEnabled: Bool
    public let soundEnabled: Bool

    public init(autoEnabled: Bool = true, typoEnabled: Bool = true, yoEnabled: Bool = true, singleShiftEnabled: Bool = true, optionEnabled: Bool = false, splitShiftEnabled: Bool = false, plainPasteEnabled: Bool = true, soundEnabled: Bool = true) {
        self.autoEnabled = autoEnabled
        self.typoEnabled = typoEnabled
        self.yoEnabled = yoEnabled
        self.singleShiftEnabled = singleShiftEnabled
        self.optionEnabled = optionEnabled
        self.splitShiftEnabled = splitShiftEnabled
        self.plainPasteEnabled = plainPasteEnabled
        self.soundEnabled = soundEnabled
    }

    public static let defaults = PreferencesSnapshot()
}
