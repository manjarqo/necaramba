import NecarambaCore
/// AX range replacement avoids guessing a count of Backspace events or replaying physical modifiers.
public final class KeySender:KeySending {
 private let selection:SelectionAccess
 public init(selection:SelectionAccess) { self.selection=selection }
 public func replaceVerifiedSuffix(_ plan:EditPlan)->ApplyResult {
  let old=plan.original+plan.delimiter
  guard !old.isEmpty,let evidence=selection.suffix(old,in:plan.expected),evidence.text==old else { return .aborted }
  return selection.replace(evidence,with:plan.replacement+plan.delimiter)
 }
}
