import XCTest
import Carbon
import NecarambaCore
@testable import NecarambaMac

final class SelectedLayoutNotificationTests: XCTestCase {
  func testSelectedSourceNotificationDoesNotPreserveLineageForChangedOrUnavailableFocus() throws {
    for focusAvailable in [true, false] {
      let center = NotificationCenter()
      let layouts = NotificationLayouts()
      let monitor = ContextMonitor(layouts: layouts, permissions: NotificationPermissions(), qualifies: { _, _ in true }, observedFocusReader: { state in
        XCTAssertNil(state.current())
        if focusAvailable {
          state.update(pid: 42, bundleID: "test", focusID: "other-field", layout: layouts.current(), qualified: true)
        } else {
          state.invalidate(.unknownInput)
        }
        return state.publishedCurrent()
      })
      monitor.state.update(pid: 42, bundleID: "test", focusID: "same-field", layout: layouts.current(), qualified: true)
      let old = try XCTUnwrap(monitor.current())
      var callbacks = 0
      monitor.onLayoutChanged = { _ in
        callbacks += 1
        XCTAssertFalse(monitor.isSafe(old))
        if focusAvailable { XCTAssertNotEqual(monitor.current()?.focusEpoch, old.focusEpoch) }
        else { XCTAssertNil(monitor.current()); XCTAssertNil(monitor.state.gestureContext()) }
      }
      monitor.observeSelectedLayoutChanges(center)
      layouts.layout = .init(rawValue: "RU")
      center.post(name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
      XCTAssertEqual(callbacks, 1)
      monitor.onLayoutChanged = nil
      monitor.stop()
    }
  }
  func testSelectedSourceNotificationReconcilesSameFieldBeforeLayoutCallback() throws {
    let center = NotificationCenter()
    let layouts = NotificationLayouts()
    var reads = 0
    var old: ContextToken!
    let monitor = ContextMonitor(layouts: layouts, permissions: NotificationPermissions(), qualifies: { _, _ in true }, observedFocusReader: { state in
      reads += 1
      XCTAssertNil(state.current(), "Cached safety must be hidden throughout authoritative read")
      XCTAssertNil(state.gestureContext())
      state.update(pid: 42, bundleID: "test", focusID: "same-field", layout: layouts.current(), qualified: true)
      return state.publishedCurrent()
    })
    monitor.state.update(pid: 42, bundleID: "test", focusID: "same-field", layout: layouts.current(), qualified: true)
    old = try XCTUnwrap(monitor.current())
    var callbacks = 0
    monitor.onLayoutChanged = { layout in
      callbacks += 1
      XCTAssertEqual(reads, callbacks, "Authoritative refresh must precede synchronization")
      XCTAssertEqual(monitor.current()?.focusEpoch, old.focusEpoch)
      XCTAssertEqual(monitor.current()?.layoutEpoch, old.layoutEpoch + UInt64(callbacks))
      XCTAssertEqual(layout, layouts.current())
    }
    monitor.observeSelectedLayoutChanges(center)
    layouts.layout = .init(rawValue: "RU")
    center.post(name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
    layouts.layout = .init(rawValue: "US")
    center.post(name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(callbacks, 2)
    XCTAssertFalse(monitor.isSafe(old))
    monitor.onLayoutChanged = nil
    monitor.stop()
  }
}

private final class NotificationLayouts: LayoutAccess {
  var layout = LayoutID(rawValue: "US")
  func current() -> LayoutID? { layout }
  func supported() -> [LayoutID] { [layout] }
  func select(_ id: LayoutID) -> Bool { layout = id; return true }
}
private final class NotificationPermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: true, post: true, ax: true, secureInput: false) }
  func request(_ kind: PermissionKind) { XCTFail("No permission requests") }
}
