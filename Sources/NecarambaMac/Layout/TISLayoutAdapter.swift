import Carbon
import NecarambaCore

public final class VerifiedLayoutSwitcher {
    private let access: LayoutAccess
    private let maxAttempts: Int
    private let sleeper: (TimeInterval) -> Void
    public init(access: LayoutAccess, maxAttempts: Int = 3,
                sleeper: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.access = access; self.maxAttempts = min(10, max(0, maxAttempts)); self.sleeper = sleeper
    }
    /// Call only outside tap callback; successful API return alone is insufficient.
    public func select(_ id: LayoutID) -> Bool {
        guard access.supported().contains(id) else { return false }
        if access.current() == id { return true }
        for index in 0..<maxAttempts {
            _ = access.select(id)
            if access.current() == id { return true }
            if index + 1 < maxAttempts { sleeper(0.02) }
        }
        return false
    }
}

public final class TISLayoutAdapter: LayoutAccess {
    public init() {}
    public func current() -> LayoutID? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), hasLayoutData(source) else { return nil }
        return identifier(source)
    }
    public func supported() -> [LayoutID] { sources().filter(hasLayoutData).compactMap(identifier) }
    public func select(_ id: LayoutID) -> Bool {
        guard let source = sources().first(where: { identifier($0) == id && hasLayoutData($0) }) else { return false }
        return TISSelectInputSource(source) == noErr
    }
    public func translate(keyCode: UInt16, modifiers: Set<Modifier>, layout: LayoutID, keyboardType: UInt32) -> String? {
        guard modifiers.isDisjoint(with: [.command, .control, .option, .function]),
              let source = sources().first(where: { identifier($0) == layout }),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard CFDataGetLength(data) > 0, let bytes = CFDataGetBytePtr(data) else { return nil }
        let ucLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var state: UInt32 = 0
        var count = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if modifiers.contains(.capsLock) { carbonModifiers |= UInt32(alphaLock) }
        let result = UCKeyTranslate(ucLayout, keyCode, UInt16(kUCKeyActionDown),
                                    (carbonModifiers >> 8) & 0xff, keyboardType,
                                    0, &state, chars.count, &count, &chars)
        guard result == noErr, state == 0, count > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: count)
    }
    private func sources() -> [TISInputSource] {
        let properties = [kTISPropertyInputSourceIsSelectCapable as String: true,
                          kTISPropertyInputSourceIsEnabled as String: true] as CFDictionary
        return TISCreateInputSourceList(properties, false).takeRetainedValue() as? [TISInputSource] ?? []
    }
    private func identifier(_ source: TISInputSource) -> LayoutID? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let value = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        return LayoutID(rawValue: value)
    }
    private func hasLayoutData(_ source: TISInputSource) -> Bool {
        TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil
    }
}
