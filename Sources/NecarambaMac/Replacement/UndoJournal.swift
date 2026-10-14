import NecarambaCore

public final class UndoJournal {
  private var entry: EditPlan?
  public init() {}
  public func record(_ plan: EditPlan, after: ContextToken) {
    entry = EditPlan(
      expected: after, original: plan.replacement, replacement: plan.original,
      sourceLayout: plan.targetLayout, targetLayout: plan.sourceLayout, delimiter: plan.delimiter)
  }
  public var hasEntry: Bool { entry != nil }
  public func take() -> EditPlan? {
    defer { entry = nil }
    return entry
  }
  public func clear() { entry = nil }
}
