import Foundation
import NecarambaCore

/// Run on the serial edit executor, never in a tap callback.
public final class ReplacementCoordinator {
  private let context: ContextAccess
  private let layouts: LayoutAccess
  private let sender: KeySending
  private let journal = UndoJournal()
  public var selectLayout: (@MainActor (LayoutID, ContextToken, UInt64) async -> Bool)?
  public var inputGeneration: () -> UInt64 = { 0 }
  public var authorization: ((ContextToken, UInt64) -> Bool)?
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
  @MainActor public func applyAsync(_ plan: EditPlan) async -> ApplyResult {
    let generation = inputGeneration()
    func authorized() -> Bool {
      guard !Task.isCancelled, inputGeneration() == generation,
        let current = context.current(), context.isSafe(current),
        current.pid == plan.expected.pid, current.bundleID == plan.expected.bundleID,
        current.focusEpoch == plan.expected.focusEpoch else { return false }
      return authorization?(plan.expected, generation) ?? true
    }
    guard authorized(), !applying, quarantined != plan.expected, context.isSafe(plan.expected),
      layouts.current() == plan.sourceLayout
    else { return .aborted }
    applying = true
    defer { applying = false }
    journal.clear()
    // Text mutation precedes the layout change: switching TIS invalidates the expected epoch.
    let result = await sender.replaceVerifiedSuffixAsync(plan)
    guard result == .committed else {
      if result == .uncertain { quarantined = plan.expected }
      return result
    }
    guard authorized(), context.isSafe(plan.expected) else {
      quarantined = plan.expected
      return .uncertain
    }
    if plan.sourceLayout != plan.targetLayout {
      let selected: Bool
      if let selectLayout { selected = await selectLayout(plan.targetLayout, plan.expected, generation) }
      else { selected = await VerifiedLayoutSwitcher(access: layouts).selectAsync(plan.targetLayout, authorized: authorized) }
      guard selected else {
        quarantined = plan.expected
        return .uncertain
      }
    }
    guard let after = (context as? ContextRefreshing)?.refresh() ?? context.current() else {
      quarantined = plan.expected
      return .uncertain
    }
    guard authorized(), after.pid == plan.expected.pid, after.bundleID == plan.expected.bundleID, after.focusEpoch == plan.expected.focusEpoch else {
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
  @MainActor public func undoLastAsync() async -> ApplyResult {
    guard let plan = journal.take() else { return .aborted }
    let result = await applyAsync(plan)
    journal.clear()
    return result
  }
  public func invalidate(_ reason: InvalidationReason) { journal.clear() }
}
