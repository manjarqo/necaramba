import Foundation
import NecarambaCore

public enum RuntimeOutcome: Equatable {
  case pass
  case suppressed(ShortcutLease)
}
public enum RuntimeCommand: Sendable {
  case gesture(GestureAction, ContextToken)
  case boundary(BufferedWord, RuleSnapshot, PreferencesSnapshot)
  case automaticBoundary(AutomaticBoundaryCandidate, RuleSnapshot, PreferencesSnapshot)
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
  private let conservativeAutomaticEnabled: Bool
  private var automaticEvents: [InputEvent] = []
  private var localAutomaticReady = false
  private var automaticTokenUnsafe = false
  // A missing prefix differs from a known interrupted token/paste. Only the
  // former may use physical capture in editors that never expose their value.
  private var automaticPrefixBlocked = false
  // A key passed while editable focus was unavailable. A recovered AX epoch
  // cannot prove this is a new word rather than the tail of that missing input.
  private var captureHasMissingInput = false
  private var missingInputOwner: ContextToken?
  private var automaticCaptureContext: ContextToken?
  // Printable keys typed while the application is known but its field is not yet
  // confirmed. They may only prefix a word whose whole text a readable field proves.
  private var pendingEvents: [InputEvent] = []
  private var buffer = WordBuffer()
  private var tracked: [InputEvent] = []
  private var recentWord: BufferedWord?
  private var repeatedManual: ManualRepeatCandidate?
  private var gestures: GestureRecognizer
  /// Set only on main immediately before command delivery. Contains no input payload.
  var commandRecognizedAtNanos: UInt64?
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
    conservativeAutomaticEnabled: Bool = false,
    engine: LinguisticEngine? = nil, command: @escaping (RuntimeCommand) -> Void = { _ in }
  ) {
    self.context = context
    layout = initialLayout
    self.preferences = preferences
    self.snapshot = snapshot
    self.command = command
    self.earlyEnabled = earlyEnabled
    self.conservativeAutomaticEnabled = conservativeAutomaticEnabled
    self.engine = engine ?? LinguisticEngine(snapshot: snapshot)
    gestures = GestureRecognizer(configuration: Self.configuration(preferences))
  }
  private static func configuration(_ p: PreferencesSnapshot) -> GestureConfiguration {
    .init(
      singleShift: p.singleShiftEnabled, option: p.optionEnabled, splitShift: p.splitShiftEnabled,
      layoutSwitchShortcut: p.layoutSwitchShortcut)
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
    automaticPrefixBlocked = automaticPrefixBlocked || !automaticEvents.isEmpty
    automaticEvents.removeAll()
    automaticTokenUnsafe = true
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
    automaticPrefixBlocked = automaticPrefixBlocked || !automaticEvents.isEmpty
    automaticTokenUnsafe = automaticTokenUnsafe || !automaticEvents.isEmpty
    automaticEvents.removeAll()
    gestures = GestureRecognizer(configuration: Self.configuration(snapshot))
    buffer.invalidate(.unknownInput)
  }
  /// Local compiled models do not depend on the fallback snapshot lexicon.
  public func updateLocalAutomaticReadiness(_ enabled: Bool) {
    lock.lock()
    defer { lock.unlock() }
    guard localAutomaticReady != enabled else { return }
    localAutomaticReady = enabled
    generation &+= 1
    automaticPrefixBlocked = automaticPrefixBlocked || !automaticEvents.isEmpty
    automaticTokenUnsafe = automaticTokenUnsafe || !automaticEvents.isEmpty
    automaticEvents.removeAll()
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
    automaticPrefixBlocked = automaticPrefixBlocked || !automaticEvents.isEmpty
    automaticTokenUnsafe = automaticTokenUnsafe || !automaticEvents.isEmpty
    automaticEvents.removeAll()
    buffer.invalidate(.unknownInput)
  }
  public var installedModelVersion: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return snapshot.modelVersion
  }
  public func updateLayout(_ id: LayoutID, preservingManualIn after: ContextToken? = nil,
                           expectedGeneration: UInt64? = nil) {
    lock.lock()
    defer { lock.unlock() }
    guard layout != id else { return }
    let retained = repeatedManual.flatMap { candidate -> ManualRepeatCandidate? in
      guard let after, expectedGeneration == generation, context.isSafe(after),
        candidate.context.pid == after.pid, candidate.context.bundleID == after.bundleID,
        candidate.context.focusEpoch == after.focusEpoch else { return nil }
      return candidate.rebased(in: after)
    }
    generation &+= 1
    layout = id
    tracked.removeAll()
    recentWord = nil
    repeatedManual = retained
    automaticPrefixBlocked = automaticPrefixBlocked || !automaticEvents.isEmpty
    automaticTokenUnsafe = automaticTokenUnsafe || !automaticEvents.isEmpty
    automaticEvents.removeAll()
    buffer.invalidate(.layoutChanged)
    gestures.invalidate()
  }
  func missedInput(keyCode: UInt16, command: Bool) {
    lock.lock()
    defer { lock.unlock() }
    // Command-Tab changes applications; it cannot insert a missing word prefix.
    if !(keyCode == 48 && command) { recordMissingInput(in: nil) }
    invalidateContext(reason: .unknownInput)
  }
  private func recordMissingInput(in token: ContextToken?) {
    captureHasMissingInput = true
    missingInputOwner = token
    automaticPrefixBlocked = true
  }
  public func invalidateContext(reason: InvalidationReason) {
    lock.lock()
    defer { lock.unlock() }
    generation &+= 1
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    automaticPrefixBlocked = automaticPrefixBlocked || !automaticEvents.isEmpty
    automaticEvents.removeAll()
    pendingEvents.removeAll()
    automaticTokenUnsafe = true
    notifyInvalidation()
    buffer.invalidate(reason)
    gestures.invalidate()
  }
  public func manualWord() -> BufferedWord? {
    lock.lock()
    defer { lock.unlock() }
    guard !captureHasMissingInput else { return nil }
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
    automaticCaptureContext = context.current() ?? automaticCaptureContext
    repeatedManual = nil
    automaticEvents.removeAll()
    automaticTokenUnsafe = true
    automaticPrefixBlocked = true
    tracked.removeAll()
    recentWord = nil
    buffer.invalidate(.unknownInput)
  }
  public func manualRepeatCandidate() -> ManualRepeatCandidate? {
    lock.lock()
    defer { lock.unlock() }
    guard let candidate = repeatedManual,
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
    captureHasMissingInput = false
    missingInputOwner = nil
    layout = candidate.layout
    automaticCaptureContext = candidate.context
    tracked.removeAll()
    recentWord = nil
    buffer.invalidate(.layoutChanged)
    gestures.invalidate()
    repeatedManual = candidate
    automaticEvents.removeAll()
    automaticTokenUnsafe = candidate.delimiter != " "
    automaticPrefixBlocked = candidate.delimiter != " "
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
    automaticCaptureContext = context.current() ?? automaticCaptureContext
    generation &+= 1
    buffer.invalidate(.unknownInput)
    tracked.removeAll()
    recentWord = nil
    repeatedManual = nil
    automaticEvents.removeAll()
    automaticTokenUnsafe = true
    automaticPrefixBlocked = true
    notifyInvalidation()
  }
  public func finishShortcut(_ lease: ShortcutLease, _ result: ApplyResult) {
    lock.lock()
    let adapter = tap
    lock.unlock()
    adapter?.finishShortcut(lease, result)
  }
  private func currentTap() -> EventTapAdapter? {
    lock.lock(); defer { lock.unlock() }
    return tap
  }
  @MainActor public func replaceByKeysAsync(
    _ evidence: SelectionEvidence, with text: String, selected: Bool, lease: ShortcutLease? = nil,
    physicalKeys: [PhysicalLayoutMapping.Entry]? = nil,
    phaseAuthorization: (@MainActor () -> Bool)? = nil,
    preflight: () -> Bool
  ) async -> ApplyResult {
    let adapter = currentTap()
    guard let adapter else { return .aborted }
    return await adapter.replaceAsync(
      evidence, with: text, selected: selected, lease: lease, physicalKeys: physicalKeys, phaseAuthorization: phaseAuthorization, preflight: preflight)
  }
  @MainActor public func replacePhysicalSuffixAsync(
    _ mutation: PhysicalSuffixMutation, with text: String, lease: ShortcutLease? = nil,
    physicalKeys: [PhysicalLayoutMapping.Entry]? = nil,
    phaseAuthorization: (@MainActor () -> Bool)? = nil,
    preflight: () -> Bool
  ) async -> ApplyResult {
    guard let adapter = currentTap() else { return .aborted }
    return await adapter.replacePhysicalAsync(mutation, with: text, lease: lease, physicalKeys: physicalKeys, phaseAuthorization: phaseAuthorization, preflight: preflight)
  }
  /// Distinguishes a transient authoritative read from an invalidated context.
  public func contextReconciling() -> Bool { (context as? ContextState)?.isReconciling ?? false }
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
    // Bare physical Shift controls conversion but cannot change text or caret.
    // In particular its release may arrive while AX verifies the preceding edit.
    let plainShift = event.origin == .physical && event.kind == .flagsChanged
      && [56, 60].contains(event.keyCode) && event.modifiers.isSubset(of: [.shift, .capsLock])
    if event.kind != .up && !plainShift { generation &+= 1 }
    if event.kind != .up && ![56, 60].contains(event.keyCode) { repeatedManual = nil }
    if event.kind == .down && ![56, 60, 58, 61].contains(event.keyCode) { notifyInvalidation() }
    guard event.origin == .physical else {
      automaticCaptureContext = event.context
      pendingEvents.removeAll()
      tracked.removeAll()
      recentWord = nil
      repeatedManual = nil
      automaticEvents.removeAll()
      automaticTokenUnsafe = true
      automaticPrefixBlocked = true
      notifyInvalidation()
      buffer.invalidate(.unknownInput)
      gestures.invalidate()
      return .pass
    }
    for action in gestures.consume(event) { deliver(.gesture(action, event.context)) }
    guard context.isSafe(event.context) else {
      if event.kind == .down, !(event.keyCode == 48 && event.modifiers.contains(.command)) {
        recordMissingInput(in: event.context)
      }
      if conservativeAutomaticEnabled { holdPendingCapture(event) }
      automaticCaptureContext = event.context
      tracked.removeAll()
      recentWord = nil
      repeatedManual = nil
      automaticEvents.removeAll()
      automaticTokenUnsafe = true
      automaticPrefixBlocked = true
      notifyInvalidation()
      buffer.invalidate(.unknownInput)
      return .pass
    }
    if captureHasMissingInput, let owner = missingInputOwner,
      owner.pid != event.context.pid || owner.bundleID != event.context.bundleID {
      captureHasMissingInput = false
      missingInputOwner = nil
    }
    if event.kind == .down, event.keyCode == 9, event.modifiers == [.command, .shift],
      preferences.plainPasteEnabled
    {
      automaticCaptureContext = event.context
      tracked.removeAll()
      recentWord = nil
      repeatedManual = nil
      automaticEvents.removeAll()
      automaticTokenUnsafe = true
      automaticPrefixBlocked = true
      buffer.invalidate(.unknownInput)
      guard tap?.canSuppress == true else { return .pass }
      let lease = ShortcutLease(
        context: event.context, generation: generation, startedNanos: event.timestampNanos)
      deliver(.plainPaste(lease))
      return .suppressed(lease)
    }
    if conservativeAutomaticEnabled { consumeAutomaticBoundary(event) }
    if captureHasMissingInput {
      // Readable automatic editors can still prove a complete word from AX.
      // Physical/manual suffix history cannot: resume it only after a boundary
      // actually observed with valid focus, never merely after an AX recovery.
      if event.kind == .down, event.modifiers.isSubset(of: [.shift, .capsLock]),
        (event.keyCode == 49 && event.text == " ") ||
          ([36, 76].contains(event.keyCode) && (event.text == "\n" || event.text == "\r")) {
        captureHasMissingInput = false
        missingInputOwner = nil
        tracked.removeAll()
        recentWord = nil
        buffer.invalidate(.unknownInput)
      }
      return .pass
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
        (text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || (0x30...0x39).contains($0.value) })
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
      if !conservativeAutomaticEnabled, preferences.autoEnabled, !snapshot.lexicon.isEmpty {
        deliver(.boundary(word, snapshot, preferences))
      }
    }
    return .pass
  }
  private func consumeAutomaticBoundary(_ event: InputEvent) {
    guard event.kind == .down else { return }
    if [56, 60].contains(event.keyCode) { return }
    if !pendingEvents.isEmpty {
      // The first confirmed key decides once: same application and layout may
      // continue the held word, but only behind a readable whole-word proof.
      let recovered = pendingEvents.allSatisfy {
        $0.context.pid == event.context.pid && $0.context.bundleID == event.context.bundleID
          && $0.layout == event.layout
      }
      automaticEvents = recovered ? pendingEvents.map { rebased($0, in: event.context) } : []
      automaticTokenUnsafe = true
      automaticPrefixBlocked = recovered || captureHasMissingInput
      automaticCaptureContext = event.context
      pendingEvents.removeAll()
    }
    if let previous = automaticCaptureContext,
      previous.pid != event.context.pid || previous.bundleID != event.context.bundleID ||
        previous.focusEpoch != event.context.focusEpoch {
      // A new field must not inherit a shortcut/prefix from the old one.
      // Readable fields still prove the prefix. Opaque capture is fresh only
      // when no physical key was lost while editable focus was unavailable.
      automaticEvents.removeAll()
      automaticTokenUnsafe = true
      automaticPrefixBlocked = captureHasMissingInput
    }
    automaticCaptureContext = event.context
    let ordinary = event.modifiers.isSubset(of: [.shift, .capsLock])
    // Return starts a new line or submits the current message. It never edits
    // the preceding word, but the next physical token has a known boundary.
    if ordinary, [36, 76].contains(event.keyCode),
      event.text == "\n" || event.text == "\r" {
      automaticEvents.removeAll()
      automaticTokenUnsafe = false
      automaticPrefixBlocked = false
      return
    }
    if ordinary, event.keyCode == 49, event.text == " " {
      defer { automaticEvents.removeAll(); automaticTokenUnsafe = false; automaticPrefixBlocked = false }
      guard !automaticEvents.isEmpty,
        preferences.autoEnabled, (localAutomaticReady || !snapshot.lexicon.isEmpty),
        automaticEvents.allSatisfy({ $0.context == event.context && $0.layout == event.layout })
      else { return }
      let word = BufferedWord(text: automaticEvents.compactMap(\.text).joined(), events: automaticEvents,
        context: event.context, layout: event.layout, delimiter: " ")
      deliver(.automaticBoundary(.init(word: word, boundary: event, inputGeneration: generation,
        requiresWordStartProof: automaticTokenUnsafe,
        allowsOpaqueWordStart: !automaticPrefixBlocked), snapshot, preferences))
      return
    }
    guard ordinary, let text = event.text, text.count == 1,
      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      automaticEvents.count < 128 else {
      automaticEvents.removeAll()
      automaticTokenUnsafe = true
      automaticPrefixBlocked = true
      return
    }
    if let first = automaticEvents.first,
      first.context != event.context || first.layout != event.layout {
      automaticEvents.removeAll()
      automaticTokenUnsafe = true
      automaticPrefixBlocked = true
    }
    automaticEvents.append(event)
  }
  private func holdPendingCapture(_ event: InputEvent) {
    guard event.kind == .down else { return }
    let printable = event.modifiers.isSubset(of: [.shift, .capsLock]) && event.text?.count == 1
      && event.text != " " && ![36, 48, 76].contains(event.keyCode)
      && event.text?.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) == false
    guard printable, pendingEvents.count < 128 else { pendingEvents.removeAll(); return }
    let sameApplication = { (other: InputEvent) in
      other.context.pid == event.context.pid && other.context.bundleID == event.context.bundleID
        && other.layout == event.layout
    }
    if let first = pendingEvents.first, !sameApplication(first) { pendingEvents.removeAll() }
    if pendingEvents.isEmpty, !automaticEvents.isEmpty, automaticEvents.allSatisfy(sameApplication) {
      pendingEvents = automaticEvents
    }
    pendingEvents.append(event)
  }
  private func rebased(_ event: InputEvent, in token: ContextToken) -> InputEvent {
    .init(kind: event.kind, keyCode: event.keyCode, modifiers: event.modifiers,
      timestampNanos: event.timestampNanos, layout: event.layout, context: token,
      origin: event.origin, text: event.text, isRepeat: event.isRepeat)
  }
  public var nextDeadlineNanos: UInt64? {
    lock.lock()
    defer { lock.unlock() }
    return gestures.nextDeadlineNanos
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
    let recognizedAt = InputPerformanceMetrics.nowNanos()
    let expected = generation
    // Electron's rich-text AX range can lag the physical Space event. Defer
    // Spark's initial read only; new input still cancels this generation and
    // the replacement adapter must prove the exact suffix before editing.
    let delay: TimeInterval
    if case .automaticBoundary(let candidate, _, _) = value,
      candidate.word.context.bundleID == "com.readdle.SparkDesktop" {
      delay = 0.06
    } else { delay = 0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.deliveryPending = false
      let valid = self.generation == expected
      self.lock.unlock()
      if case .automaticBoundary = value {
        InputDiagnostics.event(valid ? "auto.boundary.delivered" : "auto.boundary.cancelledGeneration")
      }
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
      self.commandRecognizedAtNanos = recognizedAt
      self.command(value)
      self.commandRecognizedAtNanos = nil
    }
  }
}
