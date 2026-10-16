import XCTest
import NecarambaCore
@testable import NecarambaMac

final class FocusNotificationTests: XCTestCase {
  func testDuplicateOwnerNotificationsPreservePhysicalWordThroughNextKey() throws {
    let layouts = FocusNotificationLayouts()
    let monitor = ContextMonitor(layouts: layouts, permissions: FocusNotificationPermissions(),
      qualifies: { _, _ in true }, observedFocusReader: { state in
        XCTAssertNil(state.current())
        XCTAssertNil(state.gestureContext())
        state.update(pid: 42, bundleID: "editor", focusID: "field", layout: layouts.current(), qualified: true)
        return state.publishedCurrent()
      })
    monitor.state.update(pid: 42, bundleID: "editor", focusID: "field", layout: layouts.current(), qualified: true)
    let runtime = InputRuntime(context: monitor.state, initialLayout: layouts.layout)
    monitor.onLayoutChanged = { if let layout = $0 { runtime.updateLayout(layout) } }
    let original = try XCTUnwrap(monitor.current())
    type("ghbdt", into: runtime, token: original, layout: layouts.layout)
    let generation = runtime.inputGeneration()
    for _ in 0..<3 { monitor.handleObservedFocusChange() }
    XCTAssertEqual(monitor.current(), original)
    XCTAssertEqual(runtime.inputGeneration(), generation)
    // A physical modifier event during the old invalidation window discarded the word.
    _ = runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: [.shift],
      timestampNanos: 20, layout: layouts.layout, context: monitor.current() ?? original,
      origin: .physical, text: nil, isRepeat: false))
    XCTAssertEqual(runtime.manualWord()?.text, "ghbdt")
    if let token = monitor.current() {
      type("n", into: runtime, token: token, layout: layouts.layout)
      XCTAssertEqual(runtime.manualWord()?.text, "ghbdtn")
    }
  }

  func testChangedOrUnavailableOwnerNeverRevivesPhysicalWord() throws {
    for unavailable in [false, true] {
      let layouts = FocusNotificationLayouts()
      var returned = false
      let monitor = ContextMonitor(layouts: layouts, permissions: FocusNotificationPermissions(),
        qualifies: { _, _ in true }, observedFocusReader: { state in
          XCTAssertNil(state.current())
          XCTAssertNil(state.gestureContext())
          if unavailable && !returned { state.invalidate(.unknownInput) }
          else {
            state.update(pid: 42, bundleID: "editor", focusID: returned ? "field" : "other",
              layout: layouts.current(), qualified: true)
          }
          return state.publishedCurrent()
        })
      monitor.state.update(pid: 42, bundleID: "editor", focusID: "field", layout: layouts.current(), qualified: true)
      let runtime = InputRuntime(context: monitor.state, initialLayout: layouts.layout)
      let original = try XCTUnwrap(monitor.current())
      type("ghbdtn", into: runtime, token: original, layout: layouts.layout)
      monitor.handleObservedFocusChange()
      XCTAssertFalse(monitor.isSafe(original))
      if unavailable { XCTAssertNil(monitor.current()); XCTAssertNil(monitor.state.gestureContext()) }
      else { XCTAssertNotNil(monitor.current()) }
      _ = runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: [.shift],
        timestampNanos: 20, layout: layouts.layout, context: original, origin: .physical,
        text: nil, isRepeat: false))
      XCTAssertNil(runtime.manualWord())
      returned = true
      monitor.handleObservedFocusChange()
      XCTAssertNotNil(monitor.current())
      XCTAssertFalse(monitor.isSafe(original))
      XCTAssertNil(runtime.manualWord())
    }
  }

  private func type(_ text: String, into runtime: InputRuntime, token: ContextToken, layout: LayoutID) {
    for (index, character) in text.enumerated() {
      _ = runtime.accept(.init(kind: .down, keyCode: 0, modifiers: [], timestampNanos: UInt64(index),
        layout: layout, context: token, origin: .physical, text: String(character), isRepeat: false))
    }
  }
}

private final class FocusNotificationLayouts: LayoutAccess {
  let layout = LayoutID(rawValue: "US")
  func current() -> LayoutID? { layout }
  func supported() -> [LayoutID] { [layout] }
  func select(_ id: LayoutID) -> Bool { false }
}
private final class FocusNotificationPermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: true, post: true, ax: true, secureInput: false) }
  func request(_ kind: PermissionKind) { XCTFail("No permission requests") }
}
