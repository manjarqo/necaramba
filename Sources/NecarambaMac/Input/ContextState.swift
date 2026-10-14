import Foundation
import NecarambaCore

/// Cached evidence only. A system observer publishes here outside event callbacks.
public final class ContextState: ContextAccess, GestureContextReading {
  private let lock = NSLock()
  private var reconciliationDepth = 0
  private var token: ContextToken?
  private var gestureToken: ContextToken?
  private var focusID: String?
  private var layout: LayoutID?
  private var focusEpoch: UInt64 = 0
  private var layoutEpoch: UInt64 = 0
  public init() {}
  public func update(
    pid: Int32, bundleID: String, focusID: String?, layout: LayoutID?, qualified: Bool
  ) {
    lock.lock()
    defer { lock.unlock() }
    if self.layout != layout { layoutEpoch &+= 1 }
    if token?.pid != pid || token?.bundleID != bundleID || self.focusID != focusID {
      focusEpoch &+= 1
    }
    self.focusID = focusID
    self.layout = layout
    gestureToken =
      layout == nil
      ? nil
      : ContextToken(pid: pid, bundleID: bundleID, focusEpoch: focusEpoch, layoutEpoch: layoutEpoch)
    guard qualified, focusID != nil, layout != nil else {
      token = nil
      return
    }
    token = ContextToken(
      pid: pid, bundleID: bundleID, focusEpoch: focusEpoch, layoutEpoch: layoutEpoch)
  }
  /// Hide cached evidence while the publisher revalidates identity and invalidates failed reads.
  public func reconcileFocus(_ readAndPublish: () -> ContextToken?) {
    lock.lock()
    reconciliationDepth += 1
    lock.unlock()
    defer {
      lock.lock()
      reconciliationDepth -= 1
      lock.unlock()
    }
    _ = readAndPublish()
  }
  public func current() -> ContextToken? {
    lock.lock()
    defer { lock.unlock() }
    return reconciliationDepth == 0 ? token : nil
  }
  /// Only the main-thread AX publisher may inspect this while reconciling.
  func publishedCurrent() -> ContextToken? {
    lock.lock()
    defer { lock.unlock() }
    return token
  }
  public func gestureContext() -> ContextToken? {
    lock.lock()
    defer { lock.unlock() }
    return reconciliationDepth == 0 ? gestureToken : nil
  }
  public func isSafe(_ expected: ContextToken) -> Bool { current() == expected }
  public func invalidate(_ reason: InvalidationReason) {
    lock.lock()
    defer { lock.unlock() }
    focusEpoch &+= 1
    token = nil
    gestureToken = nil
    focusID = nil
    if reason == .layoutChanged { layoutEpoch &+= 1 }
  }
}
