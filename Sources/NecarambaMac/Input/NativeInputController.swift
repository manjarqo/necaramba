import Foundation
import NecarambaCore
/// Native composition facade. Invoke its lifecycle and manual actions on the main thread.
public final class NativeInputController:InputRuntimeControl,RuleSnapshotConsumer {
 public let context:ContextMonitor
 public private(set) var runtime:InputRuntime!
 private let layouts:LayoutAccess
 private let permissions:PermissionReading
 private let selection:SelectionAdapter
 private let replacement:ReplacementCoordinator
 private var preferences:PreferencesSnapshot
 private var rules:RuleSnapshot
 private let corpusQualified:Bool
 private var excluded:Set<String>=[]
 private var appOverrides:[String:AppOverride]=[:]
 public var onResult:(ApplyResult)->Void = {_ in}
 public var onToggleAuto:()->Void = {}
 public init(profiles:CapabilityProfiles = CapabilityProfiles(),layouts:LayoutAccess = TISLayoutAdapter(),permissions:PermissionReading = PermissionMonitor(),preferences:PreferencesSnapshot = .defaults,snapshot:RuleSnapshot = .init(modelVersion:0),corpusQualified:Bool=false) {
  self.layouts=layouts; self.permissions=permissions; self.preferences=preferences; rules=snapshot; self.corpusQualified=corpusQualified
  let monitor=ContextMonitor(layouts:layouts,permissions:permissions,qualifies:{profiles.qualifies(bundleID:$0,role:$1)})
  context=monitor
  let ax=AXSelectionAdapter(context:monitor,qualifies:{profiles.qualifies(bundleID:$0,role:$1)})
  selection=SelectionAdapter(selection:ax)
  replacement=ReplacementCoordinator(context:monitor,layouts:layouts,sender:KeySender(selection:ax))
  runtime=InputRuntime(context:monitor.state,initialLayout:layouts.current() ?? LayoutID(rawValue:"unsupported"),preferences:preferences,snapshot:snapshot,command:{[weak self] in self?.execute($0)})
  runtime.onInputInvalidation={ [weak self] in self?.replacement.invalidate(.unknownInput) }
 }
 @discardableResult public func start()->Bool { precondition(Thread.isMainThread); context.start(); return runtime.start() }
 public func stop() { precondition(Thread.isMainThread); runtime.stop(); context.stop(); replacement.invalidate(.unknownInput) }
 public func updatePreferences(_ snapshot:PreferencesSnapshot) { preferences=snapshot; runtime.updatePreferences(snapshot) }
 public func install(_ snapshot:RuleSnapshot) { rules=snapshot; runtime.install(snapshot) }
 public func updateWordPolicies(_ words:Set<String>) { excluded=words; runtime.invalidateContext(reason:.unknownInput) }
 public func updateAppPolicies(_ policies:[String:AppOverride]) { appOverrides=policies; runtime.invalidateContext(reason:.unknownInput) }
 public func invalidateContext(reason:InvalidationReason) { runtime.invalidateContext(reason:reason); context.state.invalidate(reason); replacement.invalidate(reason) }
 private func ready(_ token:ContextToken)->Bool {
  let p=permissions.current(); guard p.listen,p.post,p.ax,!p.secureInput,context.refresh()==token else { return false }; return true
 }
 private func execute(_ command:RuntimeCommand) {
  precondition(Thread.isMainThread)
  switch command {
  case let .gesture(action,token):
   guard ready(token) else { return }
   switch action {
   case .toggleAuto:onToggleAuto()
   case .manualCorrection:onResult(manualCorrection())
   case .switchLayout:
    guard let current=layouts.current(),let next=layouts.supported().first(where:{$0 != current}) else { return }
    if VerifiedLayoutSwitcher(access:layouts).select(next) { runtime.updateLayout(next); _=context.refresh(); replacement.invalidate(.layoutChanged) }
   }
  case let .boundary(word,snapshot,prefs):
   guard corpusQualified,ready(word.context),appOverrides[word.context.bundleID] != .deny,prefs.autoEnabled else { return }
   if case let .replace(correction)=LinguisticEngine(snapshot:snapshot).decide(word:word,preferences:prefs,excludedWords:excluded) {
    onResult(replacement.apply(.init(expected:word.context,original:correction.original,replacement:correction.replacement,sourceLayout:correction.sourceLayout,targetLayout:correction.targetLayout,delimiter:word.delimiter)))
    if let current=layouts.current() { runtime.updateLayout(current) }
   }
  case .plainPaste:onResult(plainPaste(clipboard:SystemClipboard()))
  }
 }
 public func manualCorrection()->ApplyResult {
  precondition(Thread.isMainThread)
  guard let token=context.current(),ready(token),let current=layouts.current(),let mapping=rules.mappings.first(where:{$0.source==current}) else { return .aborted }
  let result=selection.convert(in:token,transform:{LayoutConverter.convert($0,mapping:mapping)})
  if result == .committed,!VerifiedLayoutSwitcher(access:layouts).select(mapping.target) { return .uncertain }
  if let current=layouts.current() { runtime.updateLayout(current) }; replacement.invalidate(.unknownInput); return result
 }
 public func plainPaste(clipboard:ClipboardAccess)->ApplyResult {
  precondition(Thread.isMainThread)
  guard let token=context.current(),ready(token) else { return .aborted }
  replacement.invalidate(.unknownInput); runtime.invalidateContext(reason:.unknownInput)
  return selection.plainPaste(in:token,clipboard:clipboard)
 }
 public func undoLast()->ApplyResult { precondition(Thread.isMainThread); guard let token=context.current(),ready(token) else { return .aborted }; return replacement.undoLast() }
}
