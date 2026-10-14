import Foundation
import AppKit
import NecarambaCore
public protocol LifecycleNotificationSource:AnyObject {
 func start(_ callback:@escaping (InvalidationReason)->Void)
 func stop()
}
/// Owns only sleep/session notifications. B remains the sole focus/layout/secure-input owner.
public final class SystemLifecycleNotificationSource:LifecycleNotificationSource {
 private var tokens:[(NotificationCenter,NSObjectProtocol)]=[]
 public init() { }
 public func start(_ callback:@escaping (InvalidationReason)->Void) {
  guard tokens.isEmpty else { return }
  let workspace=NSWorkspace.shared.notificationCenter
  let distributed=DistributedNotificationCenter.default()
  let bindings:[(NotificationCenter,Notification.Name,InvalidationReason)] = [(workspace,NSWorkspace.willSleepNotification,.sleep),(workspace,NSWorkspace.didWakeNotification,.unknownInput),(distributed,Notification.Name("com.apple.screenIsLocked"),.sessionLock),(distributed,Notification.Name("com.apple.screenIsUnlocked"),.unknownInput)]
  for (center,name,reason) in bindings { tokens.append((center,center.addObserver(forName:name,object:nil,queue:.main) { _ in callback(reason) })) }
 }
 public func stop() { for (center,token) in tokens { center.removeObserver(token) }; tokens.removeAll() }
 deinit { stop() }
}
@MainActor public final class LifecycleController {
 private let runtime:InputRuntimeControl
 private let source:LifecycleNotificationSource
 private var started=false
 private var generation=0
 public init(runtime:InputRuntimeControl,source:LifecycleNotificationSource = SystemLifecycleNotificationSource()) { self.runtime=runtime; self.source=source }
 public func handle(_ reason:InvalidationReason) { runtime.invalidateContext(reason:reason) }
 public func start() {
  guard !started else { return }; started=true; generation+=1
  let current=generation
  source.start { [weak self] reason in
   // Sources deliver on the main thread; the generation also rejects queued callbacks after stop/restart.
   guard let self,self.started,self.generation==current else { return }
   self.handle(reason)
  }
 }
 public func stop() { guard started else { return }; started=false; generation+=1; source.stop() }
 deinit { source.stop() }
}
