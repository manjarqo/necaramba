import Foundation
import NecarambaCore

public enum RuntimeOutcome: Equatable {
  case pass
  case suppressed(ShortcutLease)
}
public enum RuntimeCommand: Sendable {
  case gesture(GestureAction, ContextToken)
  case boundary(BufferedWord, RuleSnapshot, PreferencesSnapshot)
  case plainPaste(ShortcutLease)
}
/// All physical events pass through. Deferred commands must independently revalidate AX evidence.
public final class InputRuntime: InputRuntimeControl, RuleSnapshotConsumer {
  private let lock = NSRecursiveLock()
  private let context: ContextAccess
  private var layout: LayoutID
  private var preferences: PreferencesSnapshot
  private var snapshot: RuleSnapshot
  private var engine: LinguisticEngine
  private let earlyEnabled: Bool
  private var buffer = WordBuffer()
  private var tracked: [InputEvent] = []
  private var recentWord: BufferedWord?
  private var repeatedManual: ManualRepeatCandidate?
  private var gestures: GestureRecognizer
  private let command: (RuntimeCommand) -> Void
  private var tap: EventTapAdapter?
  private var generation: UInt64 = 0
  private var deliveryPending = false
  private var invalidationPending = false
  public var onInputInvalidation: () -> Void = {}
  public private(set) var forwardedCount = 0
  public init(
    context: ContextAccess, initialLayout: LayoutID, preferences: PreferencesSnapshot = .defaults,
    snapshot: RuleSnapshot = RuleSnapshot(modelVersion: 0), earlyEnabled: Bool = false,
    engine: LinguisticEngine? = nil, command: @escaping (RuntimeCommand) -> Void = { _ in }
  ) {
    self.context = context
    layout = initialLayout
    self.preferences = preferences
    self.snapshot = snapshot
    self.command = command
    self.earlyEnabled = earlyEnabled
    self.engine = engine ?? LinguisticEngine(snapshot: snapshot)
    gestures = GestureRecognizer(configuration: Self.configuration(preferences))
  }
  private static func configuration(_ p: PreferencesSnapshot) -> GestureConfiguration {
    .init(
      singleShift: p.singleShiftEnabled, option: p.optionEnabled, splitShift: p.splitShiftEnabled)
  }
  @discardableResult public func start() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let tap { return tap.isInstalled }
    let adapter = EventTapAdapter(runtime: self)
    guard adapter.start() else { return false }
    tap = adapter
    return true
  }
  public var isRunning: Bool {
    lock.lock()
    let current = tap
    lock.unlock()
    return current?.isInstalled == true
  }
  public func stop() {
    lock.lock()
    let old = tap
    tap = nil
    lock.unlock()
    // Let the adapter finish any in-flight callback without holding this lock.
    // Invalidate after that barrier so its final event cannot leave a command
    // or buffered word eligible for the replacement runtime.
    old?.stop()
    lock.lock()
    generation &+= 1
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    buffer.invalidate(.unknownInput)
    gestures.invalidate()
    lock.unlock()
  }
  public func updatePreferences(_ snapshot: PreferencesSnapshot) {
    lock.lock()
    defer { lock.unlock() }
    generation &+= 1
    preferences = snapshot
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    gestures = GestureRecognizer(configuration: Self.configuration(snapshot))
    buffer.invalidate(.unknownInput)
  }
  public func install(_ snapshot: RuleSnapshot) {
    install(snapshot, engine: LinguisticEngine(snapshot: snapshot))
  }
  public func install(_ snapshot: RuleSnapshot, engine: LinguisticEngine) {
    lock.lock()
    defer { lock.unlock() }
    generation &+= 1
    self.snapshot = snapshot
    self.engine = engine
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    buffer.invalidate(.unknownInput)
  }
  public var installedModelVersion: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return snapshot.modelVersion
  }
  public func updateLayout(_ id: LayoutID) {
    lock.lock()
    defer { lock.unlock() }
    guard layout != id else { return }
    generation &+= 1
    layout = id
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    buffer.invalidate(.layoutChanged)
    gestures.invalidate()
  }
  public func invalidateContext(reason: InvalidationReason) {
    lock.lock()
    defer { lock.unlock() }
    generation &+= 1
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    notifyInvalidation()
    buffer.invalidate(reason)
    gestures.invalidate()
  }
  public func manualWord() -> BufferedWord? {
    lock.lock()
    defer { lock.unlock() }
    if let first = tracked.first {
      return .init(
        text: tracked.compactMap(\.text).joined(), events: tracked, context: first.context,
        layout: first.layout, delimiter: "")
    }
    return recentWord
  }
  public func discardManualCandidate() {
    lock.lock()
    defer { lock.unlock() }
    repeatedManual = nil
    tracked.removeAll()
    recentWord = nil
  }
  public func manualRepeatCandidate() -> ManualRepeatCandidate? {
    lock.lock()
    defer { lock.unlock() }
    guard let candidate = repeatedManual, candidate.layout == layout,
      context.isSafe(candidate.context) else {
      repeatedManual = nil
      return nil
    }
    return candidate
  }
  /// Update the intentional layout transition and retain lineage atomically against new input.
  @discardableResult public func retainManualResult(_ candidate: ManualRepeatCandidate,
                                                    expectedGeneration: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard generation == expectedGeneration, context.isSafe(candidate.context) else { return false }
    generation &+= 1
    layout = candidate.layout
    tracked.removeAll()
    recentWord = nil
    buffer.invalidate(.layoutChanged)
    gestures.invalidate()
    repeatedManual = candidate
    return true
  }
  public func inputGeneration() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return generation
  }
  public func replayedPhysicalInput() {
    lock.lock()
    defer { lock.unlock() }
    generation &+= 1
    buffer.invalidate(.unknownInput)
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    notifyInvalidation()
  }
  public func finishShortcut(_ lease: ShortcutLease, _ result: ApplyResult) {
    lock.lock()
    let adapter = tap
    lock.unlock()
    adapter?.finishShortcut(lease, result)
  }
  public func replaceByKeys(
    _ evidence: SelectionEvidence, with text: String, selected: Bool, lease: ShortcutLease? = nil,
    preflight: () -> Bool
  ) -> ApplyResult {
    lock.lock()
    let adapter = tap
    lock.unlock()
    guard let adapter else { return .aborted }
    return adapter.replace(
      evidence, with: text, selected: selected, lease: lease, preflight: preflight)
  }
  public func cachedInputContext() -> (ContextToken, LayoutID)? {
    lock.lock()
    defer { lock.unlock() }
    guard let token = context.current() ?? (context as? GestureContextReading)?.gestureContext()
    else { return nil }
    return (token, layout)
  }
  @discardableResult public func accept(_ event: InputEvent) -> RuntimeOutcome {
    lock.lock()
    defer { lock.unlock() }
    forwardedCount += 1
    guard event.origin != .ours else { return .pass }
    if event.kind != .up { generation &+= 1 }
    if event.kind != .up && ![56, 60].contains(event.keyCode) { repeatedManual = nil }
    if event.kind == .down && ![56, 60, 58, 61].contains(event.keyCode) { notifyInvalidation() }
    guard event.origin == .physical else {
      tracked.removeAll()
      recentWord = nil
      repeatedManual = nil
      notifyInvalidation()
      buffer.invalidate(.unknownInput)
      gestures.invalidate()
      return .pass
    }
    for action in gestures.consume(event) { deliver(.gesture(action, event.context)) }
    guard context.isSafe(event.context) else {
      tracked.removeAll()
      recentWord = nil
      repeatedManual = nil
      notifyInvalidation()
      buffer.invalidate(.unknownInput)
      return .pass
    }
    if event.kind == .down, event.keyCode == 9, event.modifiers == [.command, .shift],
      preferences.plainPasteEnabled
    {
      tracked.removeAll()
      recentWord = nil
      repeatedManual = nil
      buffer.invalidate(.unknownInput)
      guard tap?.canSuppress == true else { return .pass }
      let lease = ShortcutLease(
        context: event.context, generation: generation, startedNanos: event.timestampNanos)
      deliver(.plainPaste(lease))
      return .suppressed(lease)
    }
    // Manual conversion can use a newly observed word even while the automatic
    // buffer waits for its first trustworthy boundary after a rule/context reset.
    let manualBoundary: BufferedWord?
    if event.kind == .down, event.modifiers.isSubset(of: [.shift, .capsLock]),
      let delimiter = event.text, delimiter == " ",
      let first = tracked.first, first.context == event.context, first.layout == event.layout {
      manualBoundary = .init(text: tracked.compactMap(\.text).joined(), events: tracked,
        context: first.context, layout: first.layout, delimiter: delimiter)
    } else {
      manualBoundary = nil
    }
    if event.kind == .down {
      if let text = event.text, text.count == 1,
        (text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })
          || [",", ".", ";", "'", "[", "]", "<", ">", ":", "\"", "{", "}"].contains(text)),
        event.modifiers.isSubset(of: [.shift, .capsLock])
      {
        if tracked.first?.context != event.context || tracked.first?.layout != event.layout {
          tracked.removeAll()
        }
        if tracked.count < 128 {
          tracked.append(event)
        } else {
          tracked.removeAll()
          recentWord = nil
          repeatedManual = nil
        }
      } else if ![56, 60, 58, 61].contains(event.keyCode) {
        tracked.removeAll()
        recentWord = nil
        repeatedManual = nil
      }
    }
    if earlyEnabled, preferences.autoEnabled, let first = tracked.first, !tracked.isEmpty {
      let word = BufferedWord(
        text: tracked.compactMap(\.text).joined(), events: tracked, context: first.context,
        layout: first.layout, delimiter: "")
      if case .replace = engine.decide(word: word, preferences: preferences, excludedWords: []) {
        deliver(.boundary(word, snapshot, preferences))
      }
    }
    if let manualBoundary { recentWord = manualBoundary }
    if let word = buffer.consume(event) {
      // Enter can submit a terminal command; Tab can change focus/completion.
      // Neither leaves a suffix eligible for a later explicit destructive edit.
      recentWord = word.delimiter.contains(where: { "\n\r\t".contains($0) }) ? nil : word
      tracked.removeAll()
      if preferences.autoEnabled, !snapshot.lexicon.isEmpty {
        deliver(.boundary(word, snapshot, preferences))
      }
    }
    return .pass
  }
  public func advance(to time: UInt64) {
    lock.lock()
    defer { lock.unlock() }
    guard let token = context.current() ?? (context as? GestureContextReading)?.gestureContext()
    else {
      gestures.invalidate()
      return
    }
    for action in gestures.advance(to: time) { deliver(.gesture(action, token)) }
  }
  private func notifyInvalidation() {
    guard !invalidationPending else { return }
    invalidationPending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.invalidationPending = false
      self.lock.unlock()
      self.onInputInvalidation()
    }
  }
  private func deliver(_ value: RuntimeCommand) {
    guard !deliveryPending else { return }
    deliveryPending = true
    let expected = generation
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.deliveryPending = false
      let valid = self.generation == expected
      self.lock.unlock()
      if case .gesture(let action, _) = value {
        switch action {
        case .manualCorrection:
          InputDiagnostics.event(valid ? "runtime.manual.delivered" : "runtime.manual.cancelled_generation")
        case .switchLayout:
          InputDiagnostics.event(valid ? "runtime.single_shift.delivered" : "runtime.single_shift.cancelled_generation")
        case .toggleAuto: break
        }
      }
      guard valid else { return }
      self.command(value)
    }
  }
}
