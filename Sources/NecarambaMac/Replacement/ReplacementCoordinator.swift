import Foundation
import NecarambaCore

/// Run on the serial edit executor, never in a tap callback.
public final class ReplacementCoordinator {
  private let context: ContextAccess
  private let layouts: LayoutAccess
  private let sender: KeySending
  private let journal = UndoJournal()
  private var applying = false
  private var quarantined: ContextToken?
  public private(set) var lastCommittedID: UUID?
  public init(context: ContextAccess, layouts: LayoutAccess, sender: KeySending) {
    self.context = context
    self.layouts = layouts
    self.sender = sender
  }
  public func apply(_ plan: EditPlan) -> ApplyResult {
    guard !applying, quarantined != plan.expected, context.isSafe(plan.expected),
      layouts.current() == plan.sourceLayout
    else { return .aborted }
    applying = true
    defer { applying = false }
    journal.clear()
    // Text mutation precedes the layout change: switching TIS invalidates the expected epoch.
    let result = sender.replaceVerifiedSuffix(plan)
    guard result == .committed else {
      if result == .uncertain { quarantined = plan.expected }
      return result
    }
    guard context.isSafe(plan.expected) else {
      quarantined = plan.expected
      return .uncertain
    }
    if plan.sourceLayout != plan.targetLayout {
      guard layouts.select(plan.targetLayout), layouts.current() == plan.targetLayout else {
        quarantined = plan.expected
        return .uncertain
      }
    }
    guard let after = (context as? ContextRefreshing)?.refresh() ?? context.current() else {
      quarantined = plan.expected
      return .uncertain
    }
    journal.record(plan, after: after)
    lastCommittedID = plan.id
    return .committed
  }
  public var hasUndo: Bool { journal.hasEntry }
  public func recordCommitted(_ plan: EditPlan, after: ContextToken) {
    journal.record(plan, after: after)
    lastCommittedID = plan.id
  }
  public func undoLast() -> ApplyResult {
    guard let plan = journal.take() else { return .aborted }
    let result = apply(plan)
    journal.clear()
    return result
  }
  public func invalidate(_ reason: InvalidationReason) { journal.clear() }
}
