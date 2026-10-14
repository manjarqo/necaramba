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
  /// Explicit manual command: complete event batch posted to a proved focused
  /// empty input proxy; the editor exposes no text readback. Never journal/count
  /// this as a verified commit or retry it automatically.
  case dispatched
}

/// Explicit manual fallback for editors whose input proxy hides its text.
/// Implementations must revalidate focused field, physical input and generation;
/// this port is never used by automatic correction.
public protocol ManualTrackedSuffixReplacing: AnyObject {
  func replaceTrackedSuffix(_ word: BufferedWord, with text: String) -> ApplyResult
}
public protocol KeySending: AnyObject {
  func replaceVerifiedSuffix(_ plan: EditPlan) -> ApplyResult
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
}

public protocol ContextRefreshing: ContextAccess {
  @discardableResult func refresh() -> ContextToken?
}

/// Application/layout identity for non-editing gestures; never proves editable focus.
public protocol GestureContextReading: AnyObject { func gestureContext() -> ContextToken? }

/// Explicit conversion lineage. Original events remain the physically observed input;
/// current text/layout describe the last manual result, not newly observed keystrokes.
public struct ManualRepeatCandidate: Sendable {
  public let original: BufferedWord
  public let currentText: String
  public let context: ContextToken
  public let layout: LayoutID
  public let delimiter: String
  public let fieldIdentity: UUID?
  public init(original: BufferedWord, currentText: String, context: ContextToken,
              layout: LayoutID, delimiter: String, fieldIdentity: UUID?) {
    self.original = original
    self.currentText = currentText
    self.context = context
    self.layout = layout
    self.delimiter = delimiter
    self.fieldIdentity = fieldIdentity
  }
}
public protocol ManualRepeatedSuffixReplacing: AnyObject {
  /// `text` includes delimiter. Empty proxies return dispatched, never verified committed.
  func replaceRepeatedSuffix(_ candidate: ManualRepeatCandidate, with text: String) -> ApplyResult
}

/// A physical space boundary frozen at event consumption, before deferred AX work.
public struct AutomaticBoundaryCandidate: Sendable {
  public let word: BufferedWord
  public let boundary: InputEvent
  public let inputGeneration: UInt64
  public init(word: BufferedWord, boundary: InputEvent, inputGeneration: UInt64) {
    self.word = word
    self.boundary = boundary
    self.inputGeneration = inputGeneration
  }
}
public protocol AutomaticBoundarySuffixReplacing: AnyObject {
  /// `text` includes the physical trailing space. Empty proxy writes remain dispatched.
  func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with text: String) -> ApplyResult
}
