import Foundation
import NecarambaCore
public enum RuntimeOutcome:Equatable { case pass }
public enum RuntimeCommand:Sendable { case gesture(GestureAction,ContextToken); case boundary(BufferedWord,RuleSnapshot,PreferencesSnapshot); case plainPaste(ContextToken) }
/// All physical events pass through. Deferred commands must independently revalidate AX evidence.
public final class InputRuntime:InputRuntimeControl,RuleSnapshotConsumer {
 private let lock=NSRecursiveLock()
 private let context:ContextAccess
 private var layout:LayoutID
 private var preferences:PreferencesSnapshot
 private var snapshot:RuleSnapshot
 private var buffer=WordBuffer()
 private var gestures:GestureRecognizer
 private let command:(RuntimeCommand)->Void
 private var tap:EventTapAdapter?
 private var generation:UInt64=0
 private var deliveryPending=false
 public private(set) var forwardedCount=0
 public init(context:ContextAccess,initialLayout:LayoutID,preferences:PreferencesSnapshot = .defaults,snapshot:RuleSnapshot = RuleSnapshot(modelVersion:0),command:@escaping(RuntimeCommand)->Void = {_ in}) {
  self.context=context; layout=initialLayout; self.preferences=preferences; self.snapshot=snapshot; self.command=command
  gestures=GestureRecognizer(configuration:Self.configuration(preferences))
 }
 private static func configuration(_ p:PreferencesSnapshot)->GestureConfiguration { .init(singleShift:p.singleShiftEnabled,option:p.optionEnabled,splitShift:p.splitShiftEnabled) }
 @discardableResult public func start()->Bool {
  lock.lock(); defer { lock.unlock() }
  if tap != nil { return true }
  let adapter=EventTapAdapter(runtime:self); guard adapter.start() else { return false }; tap=adapter; return true
 }
 public func stop() { lock.lock(); let old=tap; tap=nil; buffer.invalidate(.unknownInput); gestures.invalidate(); lock.unlock(); old?.stop() }
 public func updatePreferences(_ snapshot:PreferencesSnapshot) { lock.lock(); defer { lock.unlock() }; preferences=snapshot; gestures=GestureRecognizer(configuration:Self.configuration(snapshot)); buffer.invalidate(.unknownInput) }
 public func install(_ snapshot:RuleSnapshot) { lock.lock(); defer { lock.unlock() }; self.snapshot=snapshot; buffer.invalidate(.unknownInput) }
 public func updateLayout(_ id:LayoutID) { lock.lock(); defer { lock.unlock() }; layout=id; buffer.invalidate(.layoutChanged); gestures.invalidate() }
 public func invalidateContext(reason:InvalidationReason) { lock.lock(); defer { lock.unlock() }; generation &+= 1; buffer.invalidate(reason); gestures.invalidate() }
 public func cachedInputContext()->(ContextToken,LayoutID)? { lock.lock(); defer { lock.unlock() }; guard let token=context.current() else { return nil }; return (token,layout) }
 @discardableResult public func accept(_ event:InputEvent)->RuntimeOutcome {
  lock.lock(); defer { lock.unlock() }; forwardedCount += 1
  guard event.origin != .ours else { return .pass }
  if event.kind != .up { generation &+= 1 }
  guard event.origin == .physical,context.isSafe(event.context) else { buffer.invalidate(.unknownInput); gestures.invalidate(); return .pass }
  for action in gestures.consume(event) { deliver(.gesture(action,event.context)) }
  if event.kind == .down,event.keyCode==9,event.modifiers == [.command,.shift],preferences.plainPasteEnabled {
   // Cannot suppress until qualified selection has been proven; the normal chord remains untouched.
   buffer.invalidate(.unknownInput)
   return .pass
  }
  if let word=buffer.consume(event),preferences.autoEnabled,!snapshot.lexicon.isEmpty { deliver(.boundary(word,snapshot,preferences)) }
  return .pass
 }
 public func advance(to time:UInt64) { lock.lock(); defer { lock.unlock() }; guard let token=context.current() else { gestures.invalidate(); return }; for action in gestures.advance(to:time) { deliver(.gesture(action,token)) } }
 private func deliver(_ value:RuntimeCommand) {
  guard !deliveryPending else { return }
  deliveryPending=true; let expected=generation
  DispatchQueue.main.async { [weak self] in
   guard let self else { return }; self.lock.lock()
   self.deliveryPending=false
   let valid=self.generation==expected; self.lock.unlock()
   guard valid else { return }
   self.command(value)
  }
 }
}
