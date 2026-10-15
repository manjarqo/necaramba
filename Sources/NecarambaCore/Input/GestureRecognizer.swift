public enum GestureAction: String, Sendable, Equatable { case switchLayout, manualCorrection, toggleAuto }
public struct GestureConfiguration: Sendable, Equatable {
    public let layoutSwitchShortcut: LayoutSwitchShortcut
    public var singleShift: Bool { layoutSwitchShortcut == .singleShift }
    public let option: Bool
    public let splitShift: Bool
    public let doubleWindowNanos: UInt64
    public init(singleShift: Bool, option: Bool, splitShift: Bool, doubleWindowNanos: UInt64 = 300_000_000, layoutSwitchShortcut: LayoutSwitchShortcut? = nil) {
        self.layoutSwitchShortcut = layoutSwitchShortcut ?? (singleShift ? .singleShift : .disabled); self.option = option; self.splitShift = splitShift; self.doubleWindowNanos = doubleWindowNanos
    }
}
/// Produces actions only; the runtime remains responsible for passing every physical chord through.
public struct GestureRecognizer: Sendable {
    private let configuration: GestureConfiguration
    private var held: Set<UInt16> = []
    private var cancelled = false
    private var second = false
    private var layoutChord = false
    private var pendingRelease: UInt64?
    private var context: ContextToken?
    private var layout: LayoutID?
    private var lastTimestamp: UInt64 = 0
    public init(configuration: GestureConfiguration) { self.configuration = configuration }
    /// Only a released pending gesture needs a wakeup; held modifiers wait for input.
    public var nextDeadlineNanos: UInt64? {
        guard held.isEmpty, let release = pendingRelease else { return nil }
        let (deadline, overflow) = release.addingReportingOverflow(configuration.doubleWindowNanos)
        return overflow ? UInt64.max : deadline
    }
    public mutating func invalidate() {
        held.removeAll(); cancelled = false; second = false; layoutChord = false; pendingRelease = nil; context = nil; layout = nil
    }
    private func expired(_ release: UInt64, at now: UInt64) -> Bool {
        now >= release && now - release >= configuration.doubleWindowNanos
    }
    public mutating func advance(to timestampNanos: UInt64) -> [GestureAction] {
        guard timestampNanos >= lastTimestamp else { invalidate(); return [] }
        lastTimestamp = timestampNanos
        guard held.isEmpty, let release = pendingRelease, expired(release, at: timestampNanos) else { return [] }
        pendingRelease = nil
        return configuration.singleShift ? [.switchLayout] : []
    }
    public mutating func consume(_ event: InputEvent) -> [GestureAction] {
        if event.origin == .ours { return [] }
        guard event.origin == .physical, event.timestampNanos >= lastTimestamp else { invalidate(); return [] }
        lastTimestamp = event.timestampNanos
        if let context, context != event.context || layout != event.layout { invalidate(); return [] }
        context = event.context; layout = event.layout
        let isShift = event.keyCode == 56 || event.keyCode == 60
        let isOption = event.keyCode == 58 || event.keyCode == 61
        let isControl = event.keyCode == 59 || event.keyCode == 62
        let isCommand = event.keyCode == 55 || event.keyCode == 54
        if event.isRepeat && (isShift || isOption || isControl || isCommand) { return [] }
        guard (isShift || isOption || isControl || isCommand), event.kind == .flagsChanged || event.kind == .down || event.kind == .up else {
            pendingRelease = nil; cancelled = !held.isEmpty; second = false; return []
        }
        if event.kind == .down && held.contains(event.keyCode) { return [] }
        let modifier: Modifier = isShift ? .shift : (isOption ? .option : (isControl ? .control : .command))
        let releasing = event.kind == .up || (event.kind == .flagsChanged && held.contains(event.keyCode))
        if !releasing && !event.modifiers.contains(modifier) { return [] }
        let chordModifier: Modifier? = configuration.layoutSwitchShortcut == .altShift ? .option :
            (configuration.layoutSwitchShortcut == .controlShift ? .control :
             (configuration.layoutSwitchShortcut == .commandShift ? .command : nil))
        let participatesInChord = isShift || modifier == chordModifier
        let allowed: Set<Modifier> = participatesInChord && chordModifier != nil
            ? [.shift, chordModifier!] : [modifier]
        let unwanted = event.modifiers.subtracting(allowed)
        // A chord must be observed from its first physical press. Flags alone
        // cannot authorize a gesture that began before focus/context tracking.
        let unobservedModifier = !releasing && held.isEmpty &&
            !event.modifiers.subtracting([modifier]).isEmpty
        if !unwanted.isEmpty || unobservedModifier { cancelled = true; pendingRelease = nil; second = false }
        if releasing {
            guard held.remove(event.keyCode) != nil else { return [] }
            guard held.isEmpty else { return [] }
            defer { cancelled = false; second = false; layoutChord = false }
            guard !cancelled else { return [] }
            if layoutChord { pendingRelease = nil; return [.switchLayout] }
            if isControl || isCommand { pendingRelease = nil; return [] }
            if isOption { return configuration.option ? [.manualCorrection] : [] }
            if second, let release = pendingRelease, !expired(release, at: event.timestampNanos) {
                pendingRelease = nil; return [.manualCorrection]
            }
            pendingRelease = event.timestampNanos
            return []
        }
        if !held.isEmpty {
            let partnerKeys: Set<UInt16> = chordModifier == .option ? [58, 61] :
                (chordModifier == .control ? [59, 62] : [55, 54])
            let completesChord = held.count == 1 && !layoutChord && chordModifier != nil &&
                ((isShift && !held.isDisjoint(with: partnerKeys)) ||
                 (modifier == chordModifier && !held.isDisjoint(with: [56, 60])))
            if !cancelled, completesChord, unwanted.isEmpty {
                held.insert(event.keyCode); pendingRelease = nil; second = false; layoutChord = true
                return []
            }
            let wasCancelled = cancelled
            held.insert(event.keyCode); pendingRelease = nil; cancelled = true; second = false
            if !wasCancelled, isShift, configuration.splitShift, held == [56, 60], event.modifiers.subtracting([.shift]).isEmpty { return [.toggleAuto] }
            return []
        }
        var actions: [GestureAction] = []
        if isShift, let release = pendingRelease {
            if expired(release, at: event.timestampNanos) {
                pendingRelease = nil
                if configuration.singleShift { actions = [.switchLayout] }
            } else { second = true }
        } else if isOption || isControl || isCommand { pendingRelease = nil }
        held.insert(event.keyCode)
        return actions
    }
}
