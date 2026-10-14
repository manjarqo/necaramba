public enum GestureAction: String, Sendable, Equatable { case switchLayout, manualCorrection, toggleAuto }
public struct GestureConfiguration: Sendable, Equatable {
    public let singleShift: Bool
    public let option: Bool
    public let splitShift: Bool
    public let doubleWindowNanos: UInt64
    public init(singleShift: Bool, option: Bool, splitShift: Bool, doubleWindowNanos: UInt64 = 300_000_000) {
        self.singleShift = singleShift; self.option = option; self.splitShift = splitShift; self.doubleWindowNanos = doubleWindowNanos
    }
}
/// Produces actions only; the runtime remains responsible for passing every physical chord through.
public struct GestureRecognizer: Sendable {
    private let configuration: GestureConfiguration
    private var held: Set<UInt16> = []
    private var cancelled = false
    private var second = false
    private var pendingRelease: UInt64?
    private var context: ContextToken?
    private var layout: LayoutID?
    private var lastTimestamp: UInt64 = 0
    public init(configuration: GestureConfiguration) { self.configuration = configuration }
    public mutating func invalidate() {
        held.removeAll(); cancelled = false; second = false; pendingRelease = nil; context = nil; layout = nil
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
        if event.isRepeat { return [] }
        let isShift = event.keyCode == 56 || event.keyCode == 60
        let isOption = event.keyCode == 58 || event.keyCode == 61
        guard (isShift || isOption), event.kind == .flagsChanged || event.kind == .down || event.kind == .up else {
            pendingRelease = nil; cancelled = !held.isEmpty; second = false; return []
        }
        let modifier: Modifier = isShift ? .shift : .option
        let releasing = event.kind == .up || (event.kind == .flagsChanged && held.contains(event.keyCode))
        if !releasing && !event.modifiers.contains(modifier) { return [] }
        let unwanted = event.modifiers.subtracting([modifier])
        if !unwanted.isEmpty { cancelled = true; pendingRelease = nil; second = false }
        if releasing {
            guard held.remove(event.keyCode) != nil else { return [] }
            guard held.isEmpty else { return [] }
            defer { cancelled = false; second = false }
            guard !cancelled else { return [] }
            if isOption { return configuration.option ? [.manualCorrection] : [] }
            if second, let release = pendingRelease, !expired(release, at: event.timestampNanos) {
                pendingRelease = nil; return [.manualCorrection]
            }
            pendingRelease = event.timestampNanos
            return []
        }
        if !held.isEmpty {
            held.insert(event.keyCode); pendingRelease = nil; cancelled = true; second = false
            if isShift, configuration.splitShift, held == [56, 60], unwanted.isEmpty { return [.toggleAuto] }
            return []
        }
        var actions: [GestureAction] = []
        if isShift, let release = pendingRelease {
            if expired(release, at: event.timestampNanos) {
                pendingRelease = nil
                if configuration.singleShift { actions = [.switchLayout] }
            } else { second = true }
        } else if isOption { pendingRelease = nil }
        held.insert(event.keyCode)
        return actions
    }
}
