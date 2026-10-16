import AppKit
import ApplicationServices
import Carbon
import NecarambaCore

public struct AXTextSnapshot {
  public let identity: UUID
  public let value: String
  public let range: NSRange
  public init(identity: UUID, value: String, range: NSRange) {
    self.identity = identity
    self.value = value
    self.range = range
  }
}
/// A post-dispatch observation may be incomplete or combine independently read attributes.
/// Missing identity means a transport timeout while looking up focus, never a proven match.
public enum AXSelectionObservation {
  case snapshot(AXTextSnapshot)
  case opaque(OpaqueFocusProof)
  case transient(identity: UUID?, value: String?)
  case rejected
}
public protocol AXSelectionReading: AnyObject {
  func read(in token: ContextToken) -> AXTextSnapshot?
  func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot?
  func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation
}
extension AXSelectionReading {
  public func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    read(in: token, deadline: deadline).map(AXSelectionObservation.snapshot) ?? .rejected
  }
  public func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot? {
    read(in: token)
  }
}
/// Some reactive overlay fields must replace a selected range instead of receiving
/// a burst of Backspaces. Preparation changes only selection, never text.
enum ManualCaretWord {
  case notRequired, unavailable
  case word(SelectionEvidence)
}
protocol ManualCaretWordReading: AnyObject {
  func wordBeforeCaret(in token: ContextToken) -> ManualCaretWord
}

enum AXSuffixPreparation { case notRequired, selected, rejected }
protocol AXSuffixSelectionPreparing: AnyObject {
  func requiresCaretWord(in token: ContextToken) -> Bool
  func prepareSuffix(_ evidence: SelectionEvidence, before: AXTextSnapshot,
    authorized: () -> Bool) -> AXSuffixPreparation
}

extension AXSuffixSelectionPreparing {
  func requiresCaretWord(in token: ContextToken) -> Bool { false }
}

/// Explicit absence is distinct from timeout, malformed data, and a real selection.
enum AXOpaqueMetadata {
  static func selection(valueStatus: AXError, value: String?, rangeStatus: AXError,
    range: CFRange?, directLayout: Bool = true, authorized: Bool = true) -> OpaqueSelectionState? {
    guard directLayout, authorized else { return nil }
    let missingValue = valueStatus == .attributeUnsupported || valueStatus == .noValue
    let missingRange = rangeStatus == .attributeUnsupported || rangeStatus == .noValue
    guard missingValue || missingRange,
      missingValue || (valueStatus == .success && value == "") else { return nil }
    if missingRange { return .unavailable }
    guard rangeStatus == .success, let range, range.location >= 0, range.length == 0 else { return nil }
    return .collapsed
  }
}

/// Direct system proof. This reader performs no mutations and is called only outside the tap.
public final class SystemAXSelectionReader: AXSelectionReading {
  private let context: ContextAccess
  private let qualifies: (String, String) -> Bool
  private let allowMissingMarkedTextRange: () -> Bool
  private let allowAutomaticBoundary: () -> Bool
  private var retained: (id: UUID, element: AXUIElement)?
  public init(
    context: ContextAccess, qualifies: @escaping (String, String) -> Bool,
    allowMissingMarkedTextRange: @escaping () -> Bool = { false },
    allowAutomaticBoundary: @escaping () -> Bool = { false }
  ) {
    self.context = context
    self.qualifies = qualifies
    self.allowMissingMarkedTextRange = allowMissingMarkedTextRange
    self.allowAutomaticBoundary = allowAutomaticBoundary
  }
  public func read(in token: ContextToken) -> AXTextSnapshot? {
    read(in: token, deadline: ProcessInfo.processInfo.systemUptime + 0.1)
  }
  public func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot? {
    guard case .snapshot(let snapshot) = observe(in: token, deadline: deadline),
      snapshot.range.location <= snapshot.value.utf16.count,
      snapshot.range.length <= snapshot.value.utf16.count - snapshot.range.location
    else { return nil }
    return snapshot
  }
  public func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    precondition(Thread.isMainThread)
    func trace(_ reason: String, detail: Int = 0) {
      if allowMissingMarkedTextRange() || allowAutomaticBoundary() {
        InputDiagnostics.event(reason, detail: detail)
      }
    }
    func stillSafe() -> Bool {
      !IsSecureEventInputEnabled() && context.isSafe(token)
    }
    func budget(_ element: AXUIElement) -> Bool {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { trace("ax.readDeadlineExceeded"); return false }
      return AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining))) == .success
    }
    func transient(identity: UUID?, value: String? = nil) -> AXSelectionObservation {
      guard stillSafe(), ProcessInfo.processInfo.systemUptime < deadline else { return .rejected }
      return .transient(identity: identity, value: value)
    }
    guard stillSafe() else { trace("ax.unsafeContext"); return .rejected }
    let resolved = AXFocusedElementResolver.system.resolve(expectedPID: token.pid, deadline: deadline)
    trace("ax.readFocus", detail: Int(resolved.status.rawValue))
    if resolved.status == .cannotComplete { return transient(identity: nil) }
    guard let focus = resolved.focus, focus.bundleID == token.bundleID else {
      trace("ax.invalidFocus"); return .rejected
    }
    let element = focus.element
    // Record every positively observed identity, even when a later attribute times out.
    if retained == nil || !CFEqual(retained!.element, element) { retained = (UUID(), element) }
    let identity = retained!.id
    func readAttribute(_ name: String) -> (AXError, CFTypeRef?) {
      guard budget(element) else { return (.cannotComplete, nil) }
      var value: CFTypeRef?
      let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
      switch name {
      case kAXRoleAttribute: trace("ax.readRole", detail: Int(status.rawValue))
      case kAXSubroleAttribute: trace("ax.readSubrole", detail: Int(status.rawValue))
      case kAXValueAttribute: trace("ax.readValue", detail: Int(status.rawValue))
      case kAXSelectedTextRangeAttribute: trace("ax.readSelectedRange", detail: Int(status.rawValue))
      case "AXMarkedTextRange": trace("ax.readMarkedRange", detail: Int(status.rawValue))
      default: break
      }
      return (status, value)
    }
    let (roleStatus, roleValue) = readAttribute(kAXRoleAttribute)
    if roleStatus == .cannotComplete { return transient(identity: identity) }
    guard roleStatus == .success, let role = roleValue as? String,
      qualifies(token.bundleID, role) else { trace("ax.invalidRole"); return .rejected }
    let (subroleStatus, subroleValue) = readAttribute(kAXSubroleAttribute)
    if subroleStatus == .cannotComplete { return transient(identity: identity) }
    if subroleStatus == .success {
      guard let subrole = subroleValue as? String, subrole != kAXSecureTextFieldSubrole
      else { trace("ax.secureOrMalformedSubrole"); return .rejected }
    } else if subroleStatus != .attributeUnsupported && subroleStatus != .noValue {
      trace("ax.subroleUnproven"); return .rejected
    }
    let (markedStatus, marked) = readAttribute("AXMarkedTextRange")
    if markedStatus == .cannotComplete { return transient(identity: identity) }
    var markedRange: CFRange?
    if markedStatus == .success {
      guard let marked, CFGetTypeID(marked) == AXValueGetTypeID()
      else { trace("ax.malformedMarkedRange"); return .rejected }
      var decoded = CFRange()
      guard AXValueGetValue(unsafeBitCast(marked, to: AXValue.self), .cfRange, &decoded)
      else { trace("ax.malformedMarkedRange"); return .rejected }
      markedRange = decoded
    }
    let directLayout = Self.isDirectKeyboardLayout()
    trace("ax.compositionDirectLayout", detail: directLayout ? 1 : 0)
    guard AXCompositionProof.permits(
      markedRange: markedRange,
      attributeUnavailable: markedStatus == .attributeUnsupported || markedStatus == .noValue,
      manual: allowMissingMarkedTextRange(), directKeyboardLayout: directLayout,
      automaticBoundary: allowAutomaticBoundary())
    else { trace("ax.compositionRejected"); return .rejected }
    let (textStatus, textValue) = readAttribute(kAXValueAttribute)
    if textStatus == .cannotComplete { return transient(identity: identity) }
    let textUnavailable = textStatus == .attributeUnsupported || textStatus == .noValue
    let text = textValue as? String
    guard textUnavailable || (textStatus == .success && text != nil && text!.utf8.count <= 1024 * 1024)
    else { trace("ax.invalidTextMetadata"); return .rejected }
    let (rangeStatus, rangeValue) = readAttribute(kAXSelectedTextRangeAttribute)
    if rangeStatus == .cannotComplete { return transient(identity: identity, value: text) }
    let rangeUnavailable = rangeStatus == .attributeUnsupported || rangeStatus == .noValue
    var range = CFRange()
    if !rangeUnavailable {
      guard rangeStatus == .success, let raw = rangeValue, CFGetTypeID(raw) == AXValueGetTypeID(),
        AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range),
        range.location >= 0, range.length >= 0,
        range.location <= 1024 * 1024, range.length <= 1024 * 1024
      else { trace("ax.malformedSelectedRange"); return .rejected }
    }
    var terminalProxy = false
    if AXTerminalProxyMetadata.isHost(token.bundleID) {
      let (classStatus, classes) = readAttribute("AXDOMClassList")
      if classStatus == .cannotComplete { return transient(identity: identity) }
      terminalProxy = AXTerminalProxyMetadata.matches(bundleID: token.bundleID, role: role,
        status: classStatus, classes: classes)
      trace(terminalProxy ? "ax.terminalProxy.matched" : "ax.terminalProxy.missing")
      if terminalProxy {
        // A helper selection is not a terminal-buffer selection. Reject it rather
        // than offering selected-text replacement against the wrong document.
        guard AXTerminalProxyMetadata.permits(rangeStatus: rangeStatus,
          range: rangeUnavailable ? nil : range, directLayout: directLayout,
          authorized: allowMissingMarkedTextRange() || allowAutomaticBoundary())
        else { return .rejected }
      }
    }
    let opaque = terminalProxy || textUnavailable || rangeUnavailable
    if opaque && !terminalProxy {
      guard AXOpaqueMetadata.selection(valueStatus: textStatus, value: text,
        rangeStatus: rangeStatus, range: rangeUnavailable ? nil : range, directLayout: directLayout,
        authorized: allowMissingMarkedTextRange() || allowAutomaticBoundary()) != nil else {
        trace("ax.opaque.nonemptyOrSelected"); return .rejected
      }
    }
    guard stillSafe(), ProcessInfo.processInfo.systemUptime <= deadline else { return .rejected }
    let finalFocus = AXFocusedElementResolver.system.resolve(expectedPID: token.pid, deadline: deadline)
    guard let finalElement = finalFocus.focus?.element, CFEqual(finalElement, element) else {
      if finalFocus.status == .cannotComplete { return transient(identity: identity) }
      trace("ax.focusChangedDuringRead"); return .rejected
    }
    guard stillSafe(), ProcessInfo.processInfo.systemUptime <= deadline else { return .rejected }
    // Value and range are independent AX calls. They may describe different instants
    // of this posted batch; only read() and a final exact proof treat them as one state.
    if opaque {
      return .opaque(.init(context: token, identity: identity,
        selection: rangeUnavailable ? .unavailable : .collapsed, terminalProxy: terminalProxy))
    }
    return .snapshot(AXTextSnapshot(identity: identity, value: text!,
      range: NSRange(location: range.location, length: range.length)))
  }

  private static func isDirectKeyboardLayout() -> Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
    else { return false }
    let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
    return type == kTISTypeKeyboardLayout
  }
}
extension SystemAXSelectionReader: AXSuffixSelectionPreparing {
  func requiresCaretWord(in token: ContextToken) -> Bool {
    // Spark rich-text fields may expose a physical Space as NBSP. Read the
    // actual bounded word so manual conversion retains its exact delimiter.
    token.bundleID == "com.readdle.SparkDesktop" ||
      NSWorkspace.shared.frontmostApplication?.processIdentifier != token.pid
  }
  func prepareSuffix(_ evidence: SelectionEvidence, before: AXTextSnapshot,
    authorized: () -> Bool) -> AXSuffixPreparation {
    // Explicit conversion in system overlays may require selecting the proven range.
    let manualOverlay = allowMissingMarkedTextRange() &&
      NSWorkspace.shared.frontmostApplication?.processIdentifier != evidence.context.pid
    guard evidence.mode == .suffix, manualOverlay else { return .notRequired }
    guard let current = read(in: evidence.context), current.identity == before.identity,
      current.value == before.value, current.range == before.range,
      let retained, retained.id == before.identity else { return .rejected }
    let element = retained.element
    var subrole: CFTypeRef?
    let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    guard subroleStatus == .success, let subrole = subrole as? String else { return .rejected }
    guard subrole == "AXSearchField" else { return .notRequired }
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
      settable.boolValue, evidence.length > 0, authorized() else { return .rejected }
    let focus = AXFocusedElementResolver.system.resolve(expectedPID: evidence.context.pid,
      deadline: ProcessInfo.processInfo.systemUptime + 0.05)
    guard let focused = focus.focus?.element, CFEqual(focused, element),
      !IsSecureEventInputEnabled(), context.isSafe(evidence.context) else { return .rejected }
    var range = CFRange(location: evidence.location, length: evidence.length)
    guard let value = AXValueCreate(.cfRange, &range) else { return .rejected }
    let status = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    InputDiagnostics.event("ax.overlay.selectRange", detail: Int(status.rawValue))
    // Even a timeout may have changed selection: never fall back to Backspaces.
    return status == .success ? .selected : .rejected
  }
}

/// Selection mode, identity, context and generation are frozen when evidence is first read.
public final class AXSelectionAdapter: SelectionAccess {
  public typealias AsyncMutation = @MainActor (SelectionEvidence, String, Bool, () -> Bool) async -> ApplyResult
  var onStage: @MainActor (EditTransactionCoordinator.State) -> Void = { _ in }
  public var executeAsync: AsyncMutation?
  public typealias PhysicalMutation = @MainActor (PhysicalSuffixMutation, String, () -> Bool) async -> ApplyResult
  public var executePhysicalAsync: PhysicalMutation?
  private var lastSuffixDispatch: PhysicalSuffixMutation?
  public var observeLater: @MainActor (TimeInterval) async -> Void = { delay in
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
  }
  public var inputGeneration: (() -> UInt64)?
  private let context: ContextAccess
  private let reader: AXSelectionReading
  private let manualCommandActive: () -> Bool
  private let automaticBoundaryActive: () -> Bool
  private let now: () -> TimeInterval
  public init(
    context: ContextAccess, qualifies: @escaping (String, String) -> Bool,
    reader: AXSelectionReading? = nil,
    allowMissingMarkedTextRange: @escaping () -> Bool = { false },
    allowAutomaticBoundary: @escaping () -> Bool = { false },
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.context = context
    self.reader = reader ?? SystemAXSelectionReader(
      context: context, qualifies: qualifies, allowMissingMarkedTextRange: allowMissingMarkedTextRange,
      allowAutomaticBoundary: allowAutomaticBoundary)
    self.manualCommandActive = allowMissingMarkedTextRange
    self.automaticBoundaryActive = allowAutomaticBoundary
    self.now = now
  }
  private func snapshot(
    _ token: ContextToken, generation: UInt64, deadline: TimeInterval? = nil
  ) -> AXTextSnapshot? {
    guard !Task.isCancelled, inputGeneration?() == generation, context.isSafe(token),
      let value = deadline.map({ reader.read(in: token, deadline: $0) }) ?? reader.read(in: token),
      value.value.utf8.count <= 1024 * 1024, value.range.location >= 0, value.range.length >= 0,
      value.range.location <= value.value.utf16.count,
      value.range.length <= value.value.utf16.count - value.range.location,
      inputGeneration?() == generation, context.isSafe(token)
    else { return nil }
    return value
  }
  private func trace(_ reason: String, detail: Int = 0) {
    if manualCommandActive() || automaticBoundaryActive() {
      InputDiagnostics.event(reason, detail: detail)
    }
  }
  private func traceMutation(_ result: ApplyResult) {
    switch result {
    case .committed: trace("ax.mutation.committed")
    case .dispatched: trace("ax.mutation.dispatched")
    case .aborted: trace("ax.mutation.aborted")
    case .uncertain: trace("ax.mutation.uncertain")
    }
  }
  public func selected(in token: ContextToken) -> SelectionEvidence? {
    guard let generation = inputGeneration?(), let value = snapshot(token, generation: generation)
    else { return nil }
    return .init(
      context: token, text: (value.value as NSString).substring(with: value.range),
      location: value.range.location, length: value.range.length, identity: value.identity,
      inputGeneration: generation, mode: .selected)
  }
  public func suffix(_ text: String, in token: ContextToken) -> SelectionEvidence? {
    guard let generation = inputGeneration?(), let value = snapshot(token, generation: generation),
      value.range.length == 0, value.range.location >= text.utf16.count
    else { return nil }
    let range = NSRange(location: value.range.location - text.utf16.count, length: text.utf16.count)
    guard (value.value as NSString).substring(with: range) == text else { return nil }
    return .init(
      context: token, text: text, location: range.location, length: range.length,
      identity: value.identity, inputGeneration: generation, mode: .suffix)
  }
  @MainActor public func replaceAsync(_ evidence: SelectionEvidence, with text: String) async -> ApplyResult {
    lastSuffixDispatch = nil
    return await replaceAsync(evidence, with: text, authorized: { true })
  }
  @MainActor private func replaceAsync(
    _ evidence: SelectionEvidence, with text: String, expectedValue: String? = nil, authorized: () -> Bool
  ) async -> ApplyResult {
    guard !Task.isCancelled, authorized(), evidence.text.count <= 128,
      evidence.text.utf8.count <= 1024 * 1024, text.utf8.count <= 1024 * 1024,
      let identity = evidence.identity, let generation = evidence.inputGeneration,
      let mode = evidence.mode, let executeAsync
    else { return .aborted }
    var selected = mode == .selected
    var dispatchEvidence = evidence
    let range = NSRange(location: evidence.location, length: evidence.length)
    var observedRange =
      selected ? range : NSRange(location: evidence.location + evidence.length, length: 0)
    var before: AXTextSnapshot?
    func valid() -> Bool {
      guard !Task.isCancelled, authorized(), let current = snapshot(evidence.context, generation: generation),
        current.identity == identity,
        current.range == observedRange, range.location >= 0, range.length >= 0,
        range.location <= current.value.utf16.count,
        range.length <= current.value.utf16.count - range.location
      else { return false }
      guard (current.value as NSString).substring(with: range) == evidence.text,
        (expectedValue == nil || expectedValue == current.value),
        before == nil || before?.value == current.value
      else { return false }
      before = current
      return true
    }
    onStage(.preflight)
    let preflightStart = InputPerformanceMetrics.nowNanos()
    guard valid(), let initial = before else { return .aborted }
    if manualCommandActive(), !selected,
      let preparer = reader as? AXSuffixSelectionPreparing {
      switch preparer.prepareSuffix(evidence, before: initial, authorized: valid) {
      case .notRequired: break
      case .rejected:
        trace("ax.overlay.selectionRejected"); return .aborted
      case .selected:
        selected = true
        observedRange = range
        dispatchEvidence = SelectionEvidence(context: evidence.context, text: evidence.text,
          location: evidence.location, length: evidence.length, identity: identity,
          inputGeneration: generation, mode: .selected)
        guard valid() else { trace("ax.overlay.selectionUnproven"); return .aborted }
        trace("ax.overlay.selectionPrepared")
      }
    }
    guard let before,
      let progress = ReplacementObservationProgress(beforeValue: before.value,
        beforeSelection: before.range, replacementRange: range, original: evidence.text,
        replacement: text, bundleID: evidence.context.bundleID, selected: selected)
    else { return .aborted }
    let expectedValue = (before.value as NSString).replacingCharacters(in: range, with: text)
    let expectedRange = NSRange(location: evidence.location + text.utf16.count, length: 0)
    InputPerformanceMetrics.shared.record(.preflight, durationNanos: InputPerformanceMetrics.nowNanos() - preflightStart)
    trace("ax.execute.begin")
    onStage(.posting)
    let postingStart = InputPerformanceMetrics.nowNanos()
    let result = await executeAsync(dispatchEvidence, text, selected, valid)
    InputPerformanceMetrics.shared.record(.posting, durationNanos: InputPerformanceMetrics.nowNanos() - postingStart)
    traceMutation(result)
    guard result == .committed else { return result }
    onStage(.verifying)
    let verificationStart = InputPerformanceMetrics.nowNanos()
    defer { InputPerformanceMetrics.shared.record(.verification, durationNanos: InputPerformanceMetrics.nowNanos() - verificationStart) }
    // Posting is asynchronous. Only observe states derivable from the already-posted
    // batch: suffix Backspaces, then Unicode insertion prefixes, with exact surroundings
    // and caret. Nothing is posted again, and backward progress is not accepted.
    // Safari can take >100 ms to answer after a posted edit. Manual commands
    // have a separate settling budget; automatic correction stays at 100 ms.
    let readbackBudget: TimeInterval = manualCommandActive() ? 0.3 : 0.1
    let deadline = now() + readbackBudget
    var observedValueProgress = 0
    var observedRangeProgress = 0
    for _ in 0..<(manualCommandActive() ? 61 : 21) {
      guard !Task.isCancelled, authorized(), now() < deadline else {
        if now() >= deadline { InputPerformanceMetrics.shared.recordCancellation(.deadline) }
        else { InputPerformanceMetrics.shared.recordCancellation(.unsafeContext) }
        trace("ax.readback.scopeOrDeadlineRejected"); return .uncertain
      }
      guard inputGeneration?() == generation, context.isSafe(evidence.context) else {
        trace("ax.readback.contextOrGenerationChanged", detail:
          (inputGeneration?() == generation ? 1 : 0) | (context.isSafe(evidence.context) ? 2 : 0))
        return .uncertain
      }
      let observation = reader.observe(in: evidence.context, deadline: deadline)
      guard !Task.isCancelled, authorized(), inputGeneration?() == generation, context.isSafe(evidence.context) else {
        trace("ax.readback.contextOrGenerationChanged", detail:
          (inputGeneration?() == generation ? 1 : 0) | (context.isSafe(evidence.context) ? 2 : 0))
        return .uncertain
      }
      guard now() <= deadline else { trace("ax.readback.deadlineExceeded"); return .uncertain }
      switch observation {
      case .rejected, .opaque:
        trace("ax.readback.rejectedObservation"); return .uncertain
      case .transient(let observedIdentity, let value):
        if let observedIdentity, observedIdentity != identity {
          trace("ax.readback.identityChanged"); return .uncertain
        }
        if let value {
          guard observedIdentity != nil,
            let next = progress.valueProgress(value, minimum: observedValueProgress) else {
            trace("ax.readback.unprovenPartialValue"); return .uncertain
          }
          observedValueProgress = next
        }
        trace(observedIdentity == nil ? "ax.readback.focusTransportPending" : "ax.readback.attributeTransportPending")
      case .snapshot(let after):
        guard after.identity == identity else { trace("ax.readback.identityChanged"); return .uncertain }
        if after.value == expectedValue && after.range == expectedRange {
          trace("ax.readback.confirmed"); return .committed
        }
        guard let nextValue = progress.valueProgress(after.value, minimum: observedValueProgress),
          let nextRange = progress.rangeProgress(after.range, minimum: observedRangeProgress) else {
          let flags = (after.value == expectedValue ? 1 : 0) | (after.range == expectedRange ? 2 : 0)
            | (after.value == before.value ? 4 : 0) | (after.range == before.range ? 8 : 0)
          trace("ax.readback.unprovenState", detail: flags)
          return .uncertain
        }
        // Separate AX attributes may expose independently cached points in the posted
        // sequence. Track each history without assuming cache freshness from call order;
        // a torn observation only permits waiting, never a successful edit.
        observedValueProgress = nextValue
        observedRangeProgress = nextRange
        trace(nextValue == 0 && nextRange == 0 ? "ax.readback.unchanged"
          : (nextValue == nextRange ? "ax.readback.postedIntermediate" : "ax.readback.tornPostedIntermediate"))
      }
      let remaining = deadline - now()
      guard remaining > 0 else { trace("ax.readback.deadlineExceeded"); return .uncertain }
      await observeLater(min(0.005, remaining))
    }
    trace("ax.readback.attemptsExhausted")
    return .uncertain
  }
}

/// Missing marked-text metadata is not proof that composition is inactive.
/// Explicit manual commands and scoped, opted-in space-boundary correction may accept
/// it for a direct keyboard layout only; this does not establish absence of dead-key state.
enum AXCompositionProof {
  static func permits(
    markedRange: CFRange?, attributeUnavailable: Bool, manual: Bool, directKeyboardLayout: Bool,
    automaticBoundary: Bool = false
  ) -> Bool {
    guard let markedRange else {
      return attributeUnavailable && (manual || automaticBoundary) && directKeyboardLayout
    }
    return markedRange.length == 0 && markedRange.location >= -1
  }
}

extension AXSelectionAdapter: ManualTrackedSuffixReplacing {
  @MainActor public func replaceTrackedSuffixAsync(_ word: BufferedWord, with text: String) async -> ApplyResult {
    lastSuffixDispatch = nil
    guard hasPhysicalLineage(word) else {
      trace("ax.tracked.physicalProofRejected"); return .aborted
    }
    return await replaceEmptyProxySuffixAsync(
      word.text + word.delimiter, in: word.context, identity: nil, with: text)
  }

  private func hasPhysicalLineage(_ word: BufferedWord) -> Bool {
    let original = word.text + word.delimiter
    return !word.text.isEmpty && !word.events.isEmpty
      && word.events.count <= 128 && original.count <= 128 && original.utf16.count <= 512
      && word.events.allSatisfy({
        $0.origin == .physical && $0.kind == .down && $0.context == word.context
          && $0.layout == word.layout && $0.modifiers.isSubset(of: [.shift, .capsLock])
          && $0.text?.count == 1
      }) && word.events.compactMap(\.text).joined() == word.text
      && word.delimiter.allSatisfy({ "!? ".contains($0) })
  }

  @MainActor private func replaceEmptyProxySuffixAsync(
    _ original: String, in context: ContextToken, identity: UUID?, with text: String,
    requiredGeneration: UInt64? = nil, authorized: (() -> Bool)? = nil
  ) async -> ApplyResult {
    // An empty terminal AX proxy cannot prove its suffix. Explicit dispatch keeps
    // that uncertainty even when a prior explicit command supplied the current text.
    let allowed = authorized ?? manualCommandActive
    guard !Task.isCancelled, allowed(), !original.isEmpty, original.count <= 128,
      original.utf16.count <= 512, !text.isEmpty, text.count <= 128, text.utf16.count <= 512
    else { trace("ax.tracked.boundsOrScopeRejected"); return .aborted }
    guard let generation = requiredGeneration ?? inputGeneration?(),
      inputGeneration?() == generation
    else { trace("ax.tracked.generationMissingOrChanged"); return .aborted }
    guard let before = snapshot(context, generation: generation) else {
      return await replaceOpaqueSuffixAsync(original, in: context, identity: identity,
        with: text, generation: generation, authorized: allowed)
    }
    guard identity == nil || before.identity == identity else {
      trace("ax.tracked.identityRejected"); return .aborted
    }
    trace("ax.tracked.nonemptyValue", detail: before.value.isEmpty ? 0 : 1)
    trace("ax.tracked.rangeZero", detail: before.range == NSRange(location: 0, length: 0) ? 1 : 0)
    guard before.value.isEmpty, before.range == NSRange(location: 0, length: 0) else { return .aborted }
    guard let executeAsync else { trace("ax.tracked.executeMissing"); return .aborted }
    func valid() -> Bool {
      guard !Task.isCancelled, allowed(), let current = snapshot(context, generation: generation)
      else { return false }
      return current.identity == before.identity && current.value.isEmpty
        && current.range == NSRange(location: 0, length: 0)
    }
    let evidence = SelectionEvidence(
      context: context, text: original, location: 0, length: original.utf16.count,
      identity: before.identity, inputGeneration: generation, mode: .suffix)
    guard valid() else { trace("ax.tracked.preflightRejected"); return .aborted }
    trace("ax.tracked.execute.begin")
    let result = await executeAsync(evidence, text, false, valid)
    traceMutation(result)
    guard result == .committed else { return result }
    guard !Task.isCancelled, allowed(), let settled = await settledField(like: context, generation: generation),
      let after = snapshot(settled, generation: generation)
    else { trace("ax.tracked.afterSnapshotMissing"); return .uncertain }
    guard after.identity == before.identity else { trace("ax.tracked.afterIdentityChanged"); return .uncertain }
    // The proxy's value is input residue, not the document (VSCodium shows unrelated
    // text after input). Trust the posted keys while the same field stays focused.
    let exact = (after.value == text && after.range == NSRange(location: text.utf16.count, length: 0)) ||
      (after.value.isEmpty && after.range == NSRange(location: 0, length: 0))
    trace("ax.tracked.afterValueExact", detail: exact ? 1 : 0)
    // Even exact output cannot retrospectively prove the original invisible suffix.
    lastSuffixDispatch = .init(focus: .init(context: context, identity: before.identity, selection: .collapsed),
      inputGeneration: generation, deleteCount: original.count)
    return .dispatched
  }
}

extension AXSelectionAdapter: ManualRepeatedSuffixReplacing {
  @MainActor public func replaceRepeatedSuffixAsync(_ candidate: ManualRepeatCandidate, with text: String) async -> ApplyResult {
    lastSuffixDispatch = nil
    // The original events remain the actual physical lineage. Never relabel the
    // transformed suffix as physically observed input to reuse the first-edit path.
    guard hasPhysicalLineage(candidate.original), !candidate.currentText.isEmpty,
      candidate.delimiter == candidate.original.delimiter,
      candidate.context.pid == candidate.original.context.pid,
      candidate.context.bundleID == candidate.original.context.bundleID,
      candidate.context.focusEpoch == candidate.original.context.focusEpoch,
      let identity = candidate.fieldIdentity
    else { trace("ax.repeat.lineageOrContextRejected"); return .aborted }
    return await replaceEmptyProxySuffixAsync(
      candidate.currentText + candidate.delimiter, in: candidate.context,
      identity: identity, with: text)
  }
}

extension AXSelectionAdapter: AutomaticBoundarySuffixReplacing, AutomaticBoundaryEligibilityReading {
  private enum AutomaticPreparation {
    case opaque(String)
    case emptyProxy(String, UUID)
    case readable(SelectionEvidence, String, String)
  }
  @MainActor public func canReplaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> Bool {
    prepareAutomaticBoundary(candidate, with: text) != nil
  }
  @MainActor public func replaceAutomaticBoundaryAsync(_ candidate: AutomaticBoundaryCandidate, with text: String) async -> ApplyResult {
    lastSuffixDispatch = nil
    guard let prepared = prepareAutomaticBoundary(candidate, with: text) else { return .aborted }
    switch prepared {
    case .opaque(let original):
      return await replaceOpaqueSuffixAsync(original, in: candidate.word.context, identity: nil, with: text,
        generation: candidate.inputGeneration, authorized: automaticBoundaryActive)
    case .emptyProxy(let original, let identity):
      return await replaceEmptyProxySuffixAsync(original, in: candidate.word.context, identity: identity, with: text,
        requiredGeneration: candidate.inputGeneration, authorized: automaticBoundaryActive)
    case .readable(let evidence, let replacement, let value):
      return await replaceAsync(evidence, with: replacement, expectedValue: value, authorized: automaticBoundaryActive)
    }
  }
  @MainActor private func prepareAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> AutomaticPreparation? {
    let word = candidate.word
    let boundary = candidate.boundary
    guard automaticBoundaryActive(), hasPhysicalLineage(word), word.delimiter == " ",
      boundary.origin == .physical, boundary.kind == .down, boundary.keyCode == 49,
      boundary.text == " ", !boundary.isRepeat,
      boundary.modifiers.isSubset(of: [.shift, .capsLock]),
      boundary.context == word.context, boundary.layout == word.layout,
      word.events.allSatisfy({ $0.text?.utf16.count == 1 }),
      !text.isEmpty, text.count <= 128, text.utf16.count <= 512,
      text.last == " ", !text.contains(where: { "\n\r\t".contains($0) })
    else { trace("ax.auto.boundaryOrSnapshotRejected"); return nil }
    let original = word.text + word.delimiter
    // Fields without readable text trust the captured buffer: the
    // field cannot contradict it, so an unproven word start no longer blocks it.
    // Readable fields below still require the exact whole word.
    let unprovenStart = candidate.requiresWordStartProof && !candidate.allowsOpaqueWordStart
    guard let before = snapshot(word.context, generation: candidate.inputGeneration) else {
      guard opaqueFocus(in: word.context) != nil else { return nil }
      if unprovenStart { trace("ax.auto.unprovenPrefixTrusted") }
      return .opaque(original)
    }
    if before.value.isEmpty && before.range == NSRange(location: 0, length: 0) {
      if unprovenStart { trace("ax.auto.unprovenPrefixTrusted") }
      else if candidate.requiresWordStartProof { trace("ax.auto.freshOpaqueCapture") }
      trace("ax.auto.emptyProxy")
      return .emptyProxy(original, before.identity)
    }
    guard before.range.length == 0, before.range.location >= original.utf16.count else {
      trace("ax.auto.readableRangeRejected"); return nil
    }
    let range = NSRange(location: before.range.location - original.utf16.count,
      length: original.utf16.count)
    let observed = (before.value as NSString).substring(with: range)
    // Spark's contenteditable body exposes its trailing physical Space as NBSP.
    // Match only this final code point; letters and the entire edit preflight stay exact.
    let sparkNonbreakingBoundary = word.context.bundleID == "com.readdle.SparkDesktop" &&
      observed == word.text + "\u{00a0}"
    guard observed == original || sparkNonbreakingBoundary else {
      trace("ax.auto.readableSuffixMismatch"); return nil
    }
    let replacement = sparkNonbreakingBoundary ? String(text.dropLast()) + "\u{00a0}" : text
    if candidate.requiresWordStartProof {
      guard let stringRange = Range(range, in: before.value),
        stringRange.lowerBound == before.value.startIndex ||
          before.value[before.value.index(before: stringRange.lowerBound)].isWhitespace
      else { return nil }
    }
    trace("ax.auto.readableSuffix")
    let evidence = SelectionEvidence(context: word.context, text: observed,
      location: range.location, length: range.length, identity: before.identity,
      inputGeneration: candidate.inputGeneration, mode: .suffix)
    return .readable(evidence, replacement, before.value)
  }
}


extension AXSelectionAdapter: ManualCaretWordReading {
  func wordBeforeCaret(in token: ContextToken) -> ManualCaretWord {
    guard manualCommandActive(),
      let overlay = reader as? AXSuffixSelectionPreparing,
      overlay.requiresCaretWord(in: token) else { return .notRequired }
    guard let generation = inputGeneration?(), let value = snapshot(token, generation: generation),
      value.range.length == 0,
      let caret = Range(value.range, in: value.value)?.lowerBound else { return .unavailable }
    // A cursor in the middle of a token cannot prove the last complete typed word.
    guard caret == value.value.endIndex || value.value[caret].isWhitespace else { return .unavailable }
    var end = caret
    while end > value.value.startIndex && value.value[value.value.index(before: end)].isWhitespace {
      end = value.value.index(before: end)
    }
    var start = end
    while start > value.value.startIndex && !value.value[value.value.index(before: start)].isWhitespace {
      start = value.value.index(before: start)
    }
    guard start < end else { return .unavailable }
    let text = String(value.value[start..<caret])
    guard text.count <= 128, text.utf16.count <= 512 else { return .unavailable }
    let range = NSRange(start..<caret, in: value.value)
    return .word(.init(context: token, text: text, location: range.location, length: range.length,
      identity: value.identity, inputGeneration: generation, mode: .suffix))
  }
}

extension AXSelectionAdapter {
  /// Synchronous mutation is unsupported; callers must await the verified transaction.
  public func replaceTrackedSuffix(_ word: BufferedWord, with text: String) -> ApplyResult { .aborted }
}

extension AXSelectionAdapter {
  /// Synchronous mutation is unsupported; callers must await the verified transaction.
  public func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult { .aborted }
}

extension AXSelectionAdapter {
  /// Synchronous mutation is unsupported; callers must await the verified transaction.
  public func replaceRepeatedSuffix(_ candidate: ManualRepeatCandidate, with text: String) -> ApplyResult { .aborted }
}

extension AXSelectionAdapter {
  /// Synchronous mutation is unsupported; callers must await the verified transaction.
  public func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> ApplyResult { .aborted }
}


extension AXSelectionAdapter: OpaqueFocusReading {
  public func opaqueFocus(in token: ContextToken) -> OpaqueFocusProof? {
    guard !Task.isCancelled, context.isSafe(token),
      case .opaque(let proof) = reader.observe(in: token, deadline: now() + 0.1),
      proof.context == token, context.isSafe(token) else { return nil }
    return proof
  }
  @MainActor private func replaceOpaqueSuffixAsync(_ original: String, in token: ContextToken,
    identity: UUID?, with text: String, generation: UInt64, authorized: () -> Bool
  ) async -> ApplyResult {
    guard authorized(), !Task.isCancelled, inputGeneration?() == generation,
      !original.isEmpty, original.count <= 128, original.utf16.count <= 512,
      !text.isEmpty, text.count <= 128, text.utf16.count <= 512,
      let proof = opaqueFocus(in: token), identity == nil || identity == proof.identity,
      let executePhysicalAsync else { return .aborted }
    func valid() -> Bool {
      !Task.isCancelled && authorized() && inputGeneration?() == generation
        && opaqueFocus(in: token) == proof && inputGeneration?() == generation
    }
    guard valid() else { return .aborted }
    let mutation = PhysicalSuffixMutation(focus: proof, inputGeneration: generation, deleteCount: original.count)
    let result = await executePhysicalAsync(mutation, text, valid)
    guard result == .committed else { return result }
    // Complete delivery is not proof of editor acceptance. Never retry this batch.
    guard authorized(), let settled = await settledField(like: token, generation: generation),
      opaqueFocus(in: settled)?.identity == proof.identity
    else { trace("ax.tracked.afterOpaqueFocusChanged"); return .uncertain }
    lastSuffixDispatch = mutation
    return .dispatched
  }
  /// Our own layout selection republishes the same field with a new layout epoch and
  /// may hide it briefly. Wait (bounded) for the same pid, bundle and focus epoch.
  @MainActor private func settledField(like token: ContextToken, generation: UInt64) async -> ContextToken? {
    let deadline = now() + 0.15
    while true {
      let generationValid = inputGeneration?() == generation
      let current = context.current()
      if !Task.isCancelled, generationValid, let current, current.pid == token.pid,
        current.bundleID == token.bundleID, current.focusEpoch == token.focusEpoch { return current }
      guard !Task.isCancelled, generationValid, now() < deadline else {
        trace("ax.tracked.afterState", detail: (generationValid ? 1 : 0) | (current == nil ? 2 : 0)
          | (current?.focusEpoch == token.focusEpoch ? 4 : 0))
        return nil
      }
      await observeLater(0.01)
    }
  }
}


extension AXSelectionAdapter: SuffixDispatchProofReading {
  public func dispatchedSuffix(in token: ContextToken, inputGeneration generation: UInt64) -> PhysicalSuffixMutation? {
    guard let lastSuffixDispatch, lastSuffixDispatch.focus.context == token,
      lastSuffixDispatch.inputGeneration == generation, inputGeneration?() == generation,
      context.isSafe(token) else { return nil }
    return lastSuffixDispatch
  }
}
