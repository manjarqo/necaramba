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
    guard textStatus == .success, let text = textValue as? String, text.utf8.count <= 1024 * 1024
    else { trace("ax.invalidTextMetadata"); return .rejected }
    let (rangeStatus, rangeValue) = readAttribute(kAXSelectedTextRangeAttribute)
    if rangeStatus == .cannotComplete { return transient(identity: identity, value: text) }
    guard rangeStatus == .success, let raw = rangeValue, CFGetTypeID(raw) == AXValueGetTypeID()
    else { trace("ax.invalidRangeMetadata"); return .rejected }
    var range = CFRange()
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range),
      range.location >= 0, range.length >= 0,
      range.location <= 1024 * 1024, range.length <= 1024 * 1024
    else { trace("ax.malformedSelectedRange"); return .rejected }
    guard stillSafe(), ProcessInfo.processInfo.systemUptime <= deadline else { return .rejected }
    let finalFocus = AXFocusedElementResolver.system.resolve(expectedPID: token.pid, deadline: deadline)
    guard let finalElement = finalFocus.focus?.element, CFEqual(finalElement, element) else {
      if finalFocus.status == .cannotComplete { return transient(identity: identity) }
      trace("ax.focusChangedDuringRead"); return .rejected
    }
    guard stillSafe(), ProcessInfo.processInfo.systemUptime <= deadline else { return .rejected }
    // Value and range are independent AX calls. They may describe different instants
    // of this posted batch; only read() and a final exact proof treat them as one state.
    return .snapshot(AXTextSnapshot(identity: identity, value: text,
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
/// Selection mode, identity, context and generation are frozen when evidence is first read.
public final class AXSelectionAdapter: SelectionAccess {
  public typealias Mutation = (SelectionEvidence, String, Bool, () -> Bool) -> ApplyResult
  public var execute: Mutation?
  public var inputGeneration: (() -> UInt64)?
  private let context: ContextAccess
  private let reader: AXSelectionReading
  private let manualCommandActive: () -> Bool
  private let automaticBoundaryActive: () -> Bool
  private let now: () -> TimeInterval
  private let wait: (TimeInterval) -> Void
  public init(
    context: ContextAccess, qualifies: @escaping (String, String) -> Bool,
    reader: AXSelectionReading? = nil,
    allowMissingMarkedTextRange: @escaping () -> Bool = { false },
    allowAutomaticBoundary: @escaping () -> Bool = { false },
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) {
    self.context = context
    self.reader = reader ?? SystemAXSelectionReader(
      context: context, qualifies: qualifies, allowMissingMarkedTextRange: allowMissingMarkedTextRange,
      allowAutomaticBoundary: allowAutomaticBoundary)
    self.manualCommandActive = allowMissingMarkedTextRange
    self.automaticBoundaryActive = allowAutomaticBoundary
    self.now = now
    self.wait = wait
  }
  private func snapshot(
    _ token: ContextToken, generation: UInt64, deadline: TimeInterval? = nil
  ) -> AXTextSnapshot? {
    guard inputGeneration?() == generation, context.isSafe(token),
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
  public func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult {
    replace(evidence, with: text, authorized: { true })
  }
  private func replace(
    _ evidence: SelectionEvidence, with text: String, authorized: () -> Bool
  ) -> ApplyResult {
    guard authorized(), evidence.text.utf8.count <= 1024 * 1024, text.utf8.count <= 1024 * 1024,
      let identity = evidence.identity, let generation = evidence.inputGeneration,
      let mode = evidence.mode, let execute
    else { return .aborted }
    let selected = mode == .selected
    let range = NSRange(location: evidence.location, length: evidence.length)
    let observedRange =
      selected ? range : NSRange(location: evidence.location + evidence.length, length: 0)
    var before: AXTextSnapshot?
    func valid() -> Bool {
      guard authorized(), let current = snapshot(evidence.context, generation: generation),
        current.identity == identity,
        current.range == observedRange, range.location >= 0, range.length >= 0,
        range.location <= current.value.utf16.count,
        range.length <= current.value.utf16.count - range.location
      else { return false }
      guard (current.value as NSString).substring(with: range) == evidence.text,
        before == nil || before?.value == current.value
      else { return false }
      before = current
      return true
    }
    guard valid(), let before else { return .aborted }
    let expectedValue = (before.value as NSString).replacingCharacters(in: range, with: text)
    let expectedRange = NSRange(location: evidence.location + text.utf16.count, length: 0)
    trace("ax.execute.begin")
    let result = execute(evidence, text, selected, valid)
    traceMutation(result)
    guard result == .committed else { return result }
    // Posting is asynchronous. Only observe states derivable from the already-posted
    // batch: suffix Backspaces, then Unicode insertion prefixes, with exact surroundings
    // and caret. Nothing is posted again, and backward progress is not accepted.
    // Safari can take >100 ms to answer after a posted edit. Manual commands
    // have a separate settling budget; automatic correction stays at 100 ms.
    let readbackBudget: TimeInterval = manualCommandActive() ? 0.3 : 0.1
    let deadline = now() + readbackBudget
    let prefix = (before.value as NSString).substring(to: range.location)
    let suffix = (before.value as NSString).substring(from: range.location + range.length)
    let prefixLength = prefix.utf16.count
    let suffixLength = suffix.utf16.count
    let deletionSteps = selected ? 0 : evidence.text.count
    func valueProgress(_ value: String, minimum: Int) -> Int? {
      guard value.utf8.count <= 1024 * 1024 else { return nil }
      let length = value.utf16.count
      guard length >= prefixLength + suffixLength else { return nil }
      let source = value as NSString
      guard source.substring(to: prefixLength) == prefix,
        source.substring(from: length - suffixLength) == suffix else { return nil }
      let middleLength = length - prefixLength - suffixLength
      let middle = source.substring(with: NSRange(location: prefixLength, length: middleLength))
      var steps: [Int] = []
      if value == before.value { steps.append(0) }
      if !selected, middle.count <= evidence.text.count,
        String(evidence.text.prefix(middle.count)) == middle {
        steps.append(deletionSteps - middle.count)
      }
      if text.unicodeScalars.starts(with: middle.unicodeScalars) {
        steps.append(deletionSteps + 1 + middleLength)
      }
      return steps.filter { $0 >= minimum }.min()
    }
    var possibleRanges: [(range: NSRange, step: Int)] = [(before.range, 0)]
    if !selected {
      var offset = prefixLength
      possibleRanges.append((NSRange(location: offset, length: 0), deletionSteps))
      for (index, character) in evidence.text.enumerated() {
        offset += String(character).utf16.count
        possibleRanges.append((NSRange(location: offset, length: 0), deletionSteps - index - 1))
      }
    }
    var inserted = 0
    possibleRanges.append((NSRange(location: prefixLength, length: 0), deletionSteps + 1))
    for scalar in text.unicodeScalars {
      inserted += scalar.value > 0xFFFF ? 2 : 1
      possibleRanges.append((NSRange(location: prefixLength + inserted, length: 0), deletionSteps + 1 + inserted))
    }
    var observedValueProgress = 0
    var observedRangeProgress = 0
    for _ in 0..<(manualCommandActive() ? 61 : 21) {
      guard authorized(), now() < deadline else {
        trace("ax.readback.scopeOrDeadlineRejected"); return .uncertain
      }
      guard inputGeneration?() == generation, context.isSafe(evidence.context) else {
        trace("ax.readback.contextOrGenerationChanged", detail:
          (inputGeneration?() == generation ? 1 : 0) | (context.isSafe(evidence.context) ? 2 : 0))
        return .uncertain
      }
      let observation = reader.observe(in: evidence.context, deadline: deadline)
      guard authorized(), inputGeneration?() == generation, context.isSafe(evidence.context) else {
        trace("ax.readback.contextOrGenerationChanged", detail:
          (inputGeneration?() == generation ? 1 : 0) | (context.isSafe(evidence.context) ? 2 : 0))
        return .uncertain
      }
      guard now() <= deadline else { trace("ax.readback.deadlineExceeded"); return .uncertain }
      switch observation {
      case .rejected:
        trace("ax.readback.rejectedObservation"); return .uncertain
      case .transient(let observedIdentity, let value):
        if let observedIdentity, observedIdentity != identity {
          trace("ax.readback.identityChanged"); return .uncertain
        }
        if let value {
          guard observedIdentity != nil,
            let next = valueProgress(value, minimum: observedValueProgress) else {
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
        guard let nextValue = valueProgress(after.value, minimum: observedValueProgress),
          let nextRange = possibleRanges.lazy.filter({
            $0.range == after.range && $0.step >= observedRangeProgress
          }).map({ $0.step }).min() else {
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
      wait(min(0.005, remaining))
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
  public func replaceTrackedSuffix(_ word: BufferedWord, with text: String) -> ApplyResult {
    guard hasPhysicalLineage(word) else {
      trace("ax.tracked.physicalProofRejected"); return .aborted
    }
    return replaceEmptyProxySuffix(
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

  private func replaceEmptyProxySuffix(
    _ original: String, in context: ContextToken, identity: UUID?, with text: String,
    requiredGeneration: UInt64? = nil, authorized: (() -> Bool)? = nil
  ) -> ApplyResult {
    // An empty terminal AX proxy cannot prove its suffix. Explicit dispatch keeps
    // that uncertainty even when a prior explicit command supplied the current text.
    let allowed = authorized ?? manualCommandActive
    guard allowed(), !original.isEmpty, original.count <= 128,
      original.utf16.count <= 512, !text.isEmpty, text.count <= 128, text.utf16.count <= 512
    else { trace("ax.tracked.boundsOrScopeRejected"); return .aborted }
    guard let generation = requiredGeneration ?? inputGeneration?(),
      inputGeneration?() == generation
    else { trace("ax.tracked.generationMissingOrChanged"); return .aborted }
    guard let before = snapshot(context, generation: generation) else {
      trace("ax.tracked.snapshotMissing"); return .aborted
    }
    guard identity == nil || before.identity == identity else {
      trace("ax.tracked.identityRejected"); return .aborted
    }
    trace("ax.tracked.nonemptyValue", detail: before.value.isEmpty ? 0 : 1)
    trace("ax.tracked.rangeZero", detail: before.range == NSRange(location: 0, length: 0) ? 1 : 0)
    guard before.value.isEmpty, before.range == NSRange(location: 0, length: 0) else { return .aborted }
    guard let execute else { trace("ax.tracked.executeMissing"); return .aborted }
    func valid() -> Bool {
      guard allowed(), let current = snapshot(context, generation: generation)
      else { return false }
      return current.identity == before.identity && current.value.isEmpty
        && current.range == NSRange(location: 0, length: 0)
    }
    let evidence = SelectionEvidence(
      context: context, text: original, location: 0, length: original.utf16.count,
      identity: before.identity, inputGeneration: generation, mode: .suffix)
    guard valid() else { trace("ax.tracked.preflightRejected"); return .aborted }
    trace("ax.tracked.execute.begin")
    let result = execute(evidence, text, false, valid)
    traceMutation(result)
    guard result == .committed else { return result }
    guard allowed(), let after = snapshot(context, generation: generation),
      after.identity == before.identity
    else { return .uncertain }
    if after.value == text && after.range == NSRange(location: text.utf16.count, length: 0) {
      // Even exact output cannot retrospectively prove the original invisible suffix.
      return .dispatched
    }
    return after.value.isEmpty && after.range == NSRange(location: 0, length: 0)
      ? .dispatched : .uncertain
  }
}

extension AXSelectionAdapter: ManualRepeatedSuffixReplacing {
  public func replaceRepeatedSuffix(_ candidate: ManualRepeatCandidate, with text: String) -> ApplyResult {
    // The original events remain the actual physical lineage. Never relabel the
    // transformed suffix as physically observed input to reuse the first-edit path.
    guard hasPhysicalLineage(candidate.original), !candidate.currentText.isEmpty,
      candidate.delimiter == candidate.original.delimiter,
      candidate.context.pid == candidate.original.context.pid,
      candidate.context.bundleID == candidate.original.context.bundleID,
      candidate.context.focusEpoch == candidate.original.context.focusEpoch,
      let identity = candidate.fieldIdentity
    else { trace("ax.repeat.lineageOrContextRejected"); return .aborted }
    return replaceEmptyProxySuffix(
      candidate.currentText + candidate.delimiter, in: candidate.context,
      identity: identity, with: text)
  }
}

extension AXSelectionAdapter: AutomaticBoundarySuffixReplacing {
  public func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> ApplyResult {
    let word = candidate.word
    let boundary = candidate.boundary
    guard automaticBoundaryActive(), hasPhysicalLineage(word), word.delimiter == " ",
      boundary.origin == .physical, boundary.kind == .down, boundary.keyCode == 49,
      boundary.text == " ", !boundary.isRepeat,
      boundary.modifiers.isSubset(of: [.shift, .capsLock]),
      boundary.context == word.context, boundary.layout == word.layout,
      word.events.allSatisfy({ $0.text?.utf16.count == 1 }),
      !text.isEmpty, text.count <= 128, text.utf16.count <= 512,
      text.last == " ", !text.contains(where: { "\n\r\t".contains($0) }),
      let before = snapshot(word.context, generation: candidate.inputGeneration)
    else { trace("ax.auto.boundaryOrSnapshotRejected"); return .aborted }
    let original = word.text + word.delimiter
    if before.value.isEmpty && before.range == NSRange(location: 0, length: 0) {
      trace("ax.auto.emptyProxy")
      return replaceEmptyProxySuffix(
        original, in: word.context, identity: before.identity, with: text,
        requiredGeneration: candidate.inputGeneration, authorized: automaticBoundaryActive)
    }
    guard before.range.length == 0, before.range.location >= original.utf16.count else {
      trace("ax.auto.readableRangeRejected"); return .aborted
    }
    let range = NSRange(location: before.range.location - original.utf16.count,
      length: original.utf16.count)
    guard (before.value as NSString).substring(with: range) == original else {
      trace("ax.auto.readableSuffixMismatch"); return .aborted
    }
    trace("ax.auto.readableSuffix")
    let evidence = SelectionEvidence(context: word.context, text: original,
      location: range.location, length: range.length, identity: before.identity,
      inputGeneration: candidate.inputGeneration, mode: .suffix)
    return replace(evidence, with: text, authorized: automaticBoundaryActive)
  }
}
