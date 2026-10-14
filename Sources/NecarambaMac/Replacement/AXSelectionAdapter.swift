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
public protocol AXSelectionReading: AnyObject {
  func read(in token: ContextToken) -> AXTextSnapshot?
  func read(in token: ContextToken, deadline: TimeInterval) -> AXTextSnapshot?
}
extension AXSelectionReading {
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
    precondition(Thread.isMainThread)
    func trace(_ reason: String, detail: Int = 0) {
      if allowMissingMarkedTextRange() || allowAutomaticBoundary() {
        InputDiagnostics.event(reason, detail: detail)
      }
    }
    func budget(_ element: AXUIElement) -> Bool {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { trace("ax.readDeadlineExceeded"); return false }
      return AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining))) == .success
    }
    guard !IsSecureEventInputEnabled(), context.isSafe(token),
      NSWorkspace.shared.frontmostApplication?.processIdentifier == token.pid
    else { trace("ax.unsafeContext"); return nil }
    let app = AXUIElementCreateApplication(token.pid)
    guard budget(app) else { return nil }
    var focused: CFTypeRef?
    let focusStatus = AXUIElementCopyAttributeValue(
      app, kAXFocusedUIElementAttribute as CFString, &focused)
    trace("ax.readFocus", detail: Int(focusStatus.rawValue))
    guard focusStatus == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { trace("ax.invalidFocus"); return nil }
    let element = unsafeBitCast(focused, to: AXUIElement.self)
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
    func attribute(_ name: String) -> CFTypeRef? {
      let (status, value) = readAttribute(name)
      return status == .success ? value : nil
    }
    guard let role = attribute(kAXRoleAttribute) as? String, qualifies(token.bundleID, role),
      attribute(kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
      let text = attribute(kAXValueAttribute) as? String, text.utf8.count <= 1024 * 1024,
      let raw = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID()
    else { trace("ax.invalidFieldMetadata"); return nil }
    let (markedStatus, marked) = readAttribute("AXMarkedTextRange")
    var markedRange: CFRange?
    if markedStatus == .success {
      guard let marked, CFGetTypeID(marked) == AXValueGetTypeID()
      else { trace("ax.malformedMarkedRange"); return nil }
      var decoded = CFRange()
      guard AXValueGetValue(unsafeBitCast(marked, to: AXValue.self), .cfRange, &decoded)
      else { trace("ax.malformedMarkedRange"); return nil }
      markedRange = decoded
    }
    let directLayout = Self.isDirectKeyboardLayout()
    trace("ax.compositionDirectLayout", detail: directLayout ? 1 : 0)
    guard AXCompositionProof.permits(
      markedRange: markedRange,
      attributeUnavailable: markedStatus == .attributeUnsupported || markedStatus == .noValue,
      manual: allowMissingMarkedTextRange(), directKeyboardLayout: directLayout,
      automaticBoundary: allowAutomaticBoundary())
    else { trace("ax.compositionRejected"); return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range),
      range.location >= 0, range.length >= 0,
      range.location <= text.utf16.count, range.length <= text.utf16.count - range.location
    else { trace("ax.malformedSelectedRange"); return nil }
    guard ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
    if retained == nil || !CFEqual(retained!.element, element) { retained = (UUID(), element) }
    return AXTextSnapshot(
      identity: retained!.id, value: text,
      range: NSRange(location: range.location, length: range.length))
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
    let deadline = now() + 0.1
    let prefix = (before.value as NSString).substring(to: range.location)
    let suffix = (before.value as NSString).substring(from: range.location + range.length)
    let prefixLength = prefix.utf16.count
    let suffixLength = suffix.utf16.count
    let deletionSteps = selected ? 0 : evidence.text.count
    func nextProgress(_ after: AXTextSnapshot, minimum: Int) -> Int? {
      if minimum == 0 && after.value == before.value && after.range == before.range { return 0 }
      let length = after.value.utf16.count
      guard after.range.length == 0, length >= prefixLength + suffixLength else { return nil }
      let value = after.value as NSString
      guard value.substring(to: prefixLength) == prefix,
        value.substring(from: length - suffixLength) == suffix else { return nil }
      let middleLength = length - prefixLength - suffixLength
      guard after.range.location == prefixLength + middleLength else { return nil }
      let middle = value.substring(with: NSRange(location: prefixLength, length: middleLength))
      var steps: [Int] = []
      if !selected, middle.count <= evidence.text.count,
        String(evidence.text.prefix(middle.count)) == middle {
        steps.append(deletionSteps - middle.count)
      }
      if text.unicodeScalars.starts(with: middle.unicodeScalars) {
        steps.append(deletionSteps + 1 + middleLength)
      }
      return steps.filter { $0 >= minimum }.min()
    }
    var progress = 0
    for _ in 0..<21 {
      guard authorized(), now() < deadline else {
        trace("ax.readback.scopeOrDeadlineRejected"); return .uncertain
      }
      guard let after = snapshot(evidence.context, generation: generation, deadline: deadline) else {
        let unchangedGeneration = inputGeneration?() == generation
        let safeContext = context.isSafe(evidence.context)
        trace("ax.readback.snapshotUnavailable", detail: (unchangedGeneration ? 1 : 0) | (safeContext ? 2 : 0))
        return .uncertain
      }
      guard now() <= deadline else { trace("ax.readback.deadlineExceeded"); return .uncertain }
      guard after.identity == identity else { trace("ax.readback.identityChanged"); return .uncertain }
      if after.value == expectedValue && after.range == expectedRange {
        trace("ax.readback.confirmed"); return .committed
      }
      guard let next = nextProgress(after, minimum: progress) else {
        let flags = (after.value == expectedValue ? 1 : 0) | (after.range == expectedRange ? 2 : 0)
          | (after.value == before.value ? 4 : 0) | (after.range == before.range ? 8 : 0)
        trace("ax.readback.unprovenState", detail: flags)
        return .uncertain
      }
      progress = next
      trace(progress == 0 ? "ax.readback.unchanged" : "ax.readback.postedIntermediate")
      let remaining = deadline - now()
      guard remaining > 0 else { trace("ax.readback.deadlineExceeded"); return .uncertain }
      // Outside the tap, without pumping the UI runloop or reentering commands.
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
