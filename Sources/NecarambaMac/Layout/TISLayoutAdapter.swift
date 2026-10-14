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

extension TISLayoutAdapter {
    /// Captures the actual hardware/layout pair outside input callbacks; IME sources lack key-layout data.
    public func physicalMappings(for snapshot: RuleSnapshot, keyboardType: UInt32 = UInt32(LMGetKbdType())) -> [PhysicalLayoutMapping] {
        let ids = Set(supported())
        return snapshot.mappings.compactMap { mapping in
            guard ids.contains(mapping.source), ids.contains(mapping.target) else { return nil }
            var entries: [PhysicalLayoutMapping.Entry] = []
            for code in UInt16(0)..<UInt16(128) {
                for modifiers: Set<Modifier> in [[], [.shift], [.capsLock], [.shift, .capsLock]] {
                    guard translate(keyCode: code, modifiers: modifiers, layout: mapping.source, keyboardType: keyboardType) != nil,
                          let translated = translate(keyCode: code, modifiers: modifiers, layout: mapping.target, keyboardType: keyboardType) else { continue }
                    entries.append(.init(keyCode: code, modifiers: modifiers, text: translated))
                }
            }
            return entries.isEmpty ? nil : .init(source: mapping.source, target: mapping.target, entries: entries)
        }
    }
}

extension TISLayoutAdapter {
    /// Resolves corpus aliases by checking every advertised pair against actual hardware translations.
    /// Multiple matching pairs are ambiguous and remain disabled; names are never treated as proof.
    public func resolveMappings(in snapshot: RuleSnapshot, keyboardType: UInt32 = UInt32(LMGetKbdType())) -> RuleSnapshot {
        let ids=supported()
        let actual=snapshot.mappings.compactMap { mapping -> LayoutMapping? in
            if ids.contains(mapping.source),ids.contains(mapping.target) { return mapping }
            guard !mapping.pairs.isEmpty else { return nil }
            var matches:[LayoutMapping]=[]
            for source in ids {
                let sourceKeys=(UInt16(0)..<UInt16(128)).compactMap { code -> (UInt16,String)? in
                    guard let text=translate(keyCode:code,modifiers:[],layout:source,keyboardType:keyboardType) else { return nil }
                    return (code,text)
                }
                for target in ids where target != source {
                    let proven=mapping.pairs.allSatisfy { original,replacement in
                        sourceKeys.contains { code,text in
                            text==original && translate(keyCode:code,modifiers:[],layout:target,keyboardType:keyboardType)==replacement
                        }
                    }
                    if proven { matches.append(.init(source:source,target:target,pairs:mapping.pairs)) }
                }
            }
            return matches.count==1 ? matches[0]:nil
        }
        return .init(modelVersion:snapshot.modelVersion,lexicon:snapshot.lexicon,typos:snapshot.typos,yoRules:snapshot.yoRules,protectedTokens:snapshot.protectedTokens,mappings:actual)
    }
}
