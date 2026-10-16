import Foundation

public struct EditPlan: Equatable, Sendable {
  public let id: UUID
  public let expected: ContextToken
  public let original: String
  public let replacement: String
  public let sourceLayout: LayoutID
  public let targetLayout: LayoutID
  public let delimiter: String
  public init(
    id: UUID = UUID(), expected: ContextToken, original: String, replacement: String,
    sourceLayout: LayoutID, targetLayout: LayoutID, delimiter: String
  ) {
    self.id = id
    self.expected = expected
    self.original = original
    self.replacement = replacement
    self.sourceLayout = sourceLayout
    self.targetLayout = targetLayout
    self.delimiter = delimiter
  }
}
public enum ApplyResult: Equatable, Sendable {
  case committed, aborted, uncertain
  /// Complete manual or automatic physical batch posted to a proved focused
  /// empty or opaque input proxy without verified text acceptance. Never journal,
  /// count as a verified commit, or retry this batch.
  case dispatched
}

/// Explicit manual fallback for editors whose input proxy hides its text.
/// Implementations must revalidate focused field, physical input and generation;
/// this port is never used by automatic correction.
public protocol ManualTrackedSuffixReplacing: AnyObject {
  func replaceTrackedSuffix(_ word: BufferedWord, with text: String) -> ApplyResult
  @MainActor func replaceTrackedSuffixAsync(_ word: BufferedWord, with text: String) async -> ApplyResult
}
public protocol KeySending: AnyObject {
  func replaceVerifiedSuffix(_ plan: EditPlan) -> ApplyResult
  @MainActor func replaceVerifiedSuffixAsync(_ plan: EditPlan) async -> ApplyResult
}
/// Evidence is immutable and tied to a focus token and exact UTF16 range.
public enum SelectionMode: Sendable, Equatable { case selected, suffix }
public struct SelectionEvidence: Equatable, Sendable {
  public let identity: UUID?
  public let inputGeneration: UInt64?
  public let mode: SelectionMode?
  public let context: ContextToken
  public let text: String
  public let location: Int
  public let length: Int
  public init(
    context: ContextToken, text: String, location: Int, length: Int, identity: UUID? = nil,
    inputGeneration: UInt64? = nil, mode: SelectionMode? = nil
  ) {
    self.identity = identity
    self.inputGeneration = inputGeneration
    self.mode = mode
    self.context = context
    self.text = text
    self.location = location
    self.length = length
  }
}
public protocol SelectionAccess: AnyObject {
  func selected(in context: ContextToken) -> SelectionEvidence?
  func suffix(_ text: String, in context: ContextToken) -> SelectionEvidence?
  func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult
  @MainActor func replaceAsync(_ evidence: SelectionEvidence, with text: String) async -> ApplyResult
}

public protocol ContextRefreshing: ContextAccess {
  @discardableResult func refresh() -> ContextToken?
}

/// Application/layout identity for non-editing gestures; never proves editable focus.
public protocol GestureContextReading: AnyObject { func gestureContext() -> ContextToken? }

/// Explicit conversion lineage. Original events remain the physically observed input;
/// current text/layout describe the last manual result, not newly observed keystrokes.
public struct ManualRepeatCandidate: Sendable {
  /// Physical lineage, or an empty-event source for an explicitly selected conversion.
  public let original: BufferedWord
  public let alternateText: String?
  public let currentText: String
  public let context: ContextToken
  public let layout: LayoutID
  public let delimiter: String
  public let fieldIdentity: UUID?
  public init(original: BufferedWord, currentText: String, context: ContextToken,
              layout: LayoutID, delimiter: String, fieldIdentity: UUID?, alternateText: String? = nil) {
    self.original = original
    self.alternateText = alternateText
    self.currentText = currentText
    self.context = context
    self.layout = layout
    self.delimiter = delimiter
    self.fieldIdentity = fieldIdentity
  }
  public func rebased(in context: ContextToken) -> ManualRepeatCandidate {
    .init(original: original, currentText: currentText, context: context, layout: layout,
          delimiter: delimiter, fieldIdentity: fieldIdentity, alternateText: alternateText)
  }
}
public protocol ManualRepeatedSuffixReplacing: AnyObject {
  /// `text` includes delimiter. Empty proxies return dispatched, never verified committed.
  func replaceRepeatedSuffix(_ candidate: ManualRepeatCandidate, with text: String) -> ApplyResult
  @MainActor func replaceRepeatedSuffixAsync(_ candidate: ManualRepeatCandidate, with text: String) async -> ApplyResult
}

/// A physical space boundary frozen at event consumption, before deferred AX work.
public struct AutomaticBoundaryCandidate: Sendable {
  public let word: BufferedWord
  public let boundary: InputEvent
  public let inputGeneration: UInt64
  /// Lost prefix history requires word-start proof in readable editors.
  /// Opaque fallback additionally requires explicit allowsOpaqueWordStart.
  public let requiresWordStartProof: Bool
  /// Fresh physical capture may be dispatched to an opaque proxy without text readback.
  public let allowsOpaqueWordStart: Bool
  public init(word: BufferedWord, boundary: InputEvent, inputGeneration: UInt64,
              requiresWordStartProof: Bool = false, allowsOpaqueWordStart: Bool = false) {
    self.word = word
    self.boundary = boundary
    self.inputGeneration = inputGeneration
    self.requiresWordStartProof = requiresWordStartProof
    self.allowsOpaqueWordStart = allowsOpaqueWordStart
  }
}
/// Read-only eligibility before activating a different input layout. Mutation
/// must repeat every proof against its final context; this grants no write lease.
public protocol AutomaticBoundaryEligibilityReading: AnyObject {
  @MainActor func canReplaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> Bool
}
public protocol AutomaticBoundarySuffixReplacing: AnyObject {
  /// `text` includes the physical trailing space. Empty proxy writes remain dispatched.
  func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> ApplyResult
  @MainActor func replaceAutomaticBoundaryAsync(_ candidate: AutomaticBoundaryCandidate, with text: String) async -> ApplyResult
}

public extension ManualTrackedSuffixReplacing {
  @MainActor func replaceTrackedSuffixAsync(_ word: BufferedWord, with text: String) async -> ApplyResult {
    guard !Task.isCancelled else { return .aborted }
    return replaceTrackedSuffix(word, with: text)
  }
}

public extension KeySending {
  @MainActor func replaceVerifiedSuffixAsync(_ plan: EditPlan) async -> ApplyResult {
    guard !Task.isCancelled else { return .aborted }
    return replaceVerifiedSuffix(plan)
  }
}

public extension SelectionAccess {
  @MainActor func replaceAsync(_ evidence: SelectionEvidence, with text: String) async -> ApplyResult {
    guard !Task.isCancelled else { return .aborted }
    return replace(evidence, with: text)
  }
}

public extension ManualRepeatedSuffixReplacing {
  @MainActor func replaceRepeatedSuffixAsync(_ candidate: ManualRepeatCandidate, with text: String) async -> ApplyResult {
    guard !Task.isCancelled else { return .aborted }
    return replaceRepeatedSuffix(candidate, with: text)
  }
}

public extension AutomaticBoundarySuffixReplacing {
  @MainActor func replaceAutomaticBoundaryAsync(_ candidate: AutomaticBoundaryCandidate, with text: String) async -> ApplyResult {
    guard !Task.isCancelled else { return .aborted }
    return replaceAutomaticBoundary(candidate, with: text)
  }
}

/// Real focused editable identity; neither case asserts that text was accepted.
public enum OpaqueSelectionState: Equatable, Sendable { case collapsed, unavailable }
public struct OpaqueFocusProof: Equatable, Sendable {
  public let context: ContextToken
  public let identity: UUID
  public let selection: OpaqueSelectionState
  /// A terminal input transport: its selection is terminal output, not editable text.
  public let terminalProxy: Bool
  public init(context: ContextToken, identity: UUID, selection: OpaqueSelectionState = .unavailable,
              terminalProxy: Bool = false) {
    self.context = context; self.identity = identity; self.selection = selection
    self.terminalProxy = terminalProxy
  }
}
public protocol OpaqueFocusReading: AnyObject {
  func opaqueFocus(in context: ContextToken) -> OpaqueFocusProof?
}
/// Physical suffix dispatch contains no invented AX range or text evidence.
public struct PhysicalSuffixMutation: Sendable {
  public let focus: OpaqueFocusProof
  public let inputGeneration: UInt64
  public let deleteCount: Int
  public init(focus: OpaqueFocusProof, inputGeneration: UInt64, deleteCount: Int) {
    self.focus = focus; self.inputGeneration = inputGeneration; self.deleteCount = deleteCount
  }
}


/// Proof from the actual completed suffix dispatch, never a separate focus sample.
/// Implementations clear the record before every replacement attempt.
public protocol SuffixDispatchProofReading: AnyObject {
  func dispatchedSuffix(in context: ContextToken, inputGeneration: UInt64) -> PhysicalSuffixMutation?
}
