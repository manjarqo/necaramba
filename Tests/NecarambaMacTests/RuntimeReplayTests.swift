import NecarambaCore
import XCTest

@testable import NecarambaMac

final class RuntimeReplayTests: XCTestCase {
  func testOneHundredThousandEventsPreserveDisposition() {
    let context = ContextState()
    context.update(
      pid: 42, bundleID: "test", focusID: "field", layout: LayoutID(rawValue: "US"), qualified: true
    )
    let runtime = InputRuntime(context: context, initialLayout: LayoutID(rawValue: "US"))
    let token = context.current()!
    for n in 0..<100000 {
      let event = InputEvent(
        kind: n % 2 == 0 ? .down : .up, keyCode: 0, modifiers: [], timestampNanos: UInt64(n),
        layout: LayoutID(rawValue: "US"), context: token, origin: n % 7 == 0 ? .ours : .physical,
        text: "a", isRepeat: n % 11 == 0)
      XCTAssertEqual(runtime.accept(event), .pass)
    }
    XCTAssertEqual(runtime.forwardedCount, 100000)
  }
  func testPhysicalChangesCoalesceUndoInvalidation() {
    let done = expectation(description: "invalidated")
    let context = ContextState()
    context.update(
      pid: 42, bundleID: "test", focusID: "field", layout: LayoutID(rawValue: "US"), qualified: true
    )
    let runtime = InputRuntime(context: context, initialLayout: LayoutID(rawValue: "US"))
    runtime.onInputInvalidation = { done.fulfill() }
    for n in 0..<100 {
      _ = runtime.accept(
        InputEvent(
          kind: .down, keyCode: 0, modifiers: [], timestampNanos: UInt64(n),
          layout: LayoutID(rawValue: "US"), context: context.current()!, origin: .physical,
          text: "a", isRepeat: false))
    }
    wait(for: [done], timeout: 1)
  }
  func testLayoutGestureWorksWithoutEditableFocus() {
    let context = ContextState()
    let layout = LayoutID(rawValue: "US")
    context.update(
      pid: 42, bundleID: "unsupported.editor", focusID: nil, layout: layout, qualified: false)
    XCTAssertNil(context.current())
    let token = context.gestureContext()!
    let done = expectation(description: "layout gesture")
    let runtime = InputRuntime(
      context: context, initialLayout: layout,
      command: { command in
        guard case .gesture(.switchLayout, _) = command else { return }
        done.fulfill()
      })
    _ = runtime.accept(
      .init(
        kind: .flagsChanged, keyCode: 56, modifiers: [.shift], timestampNanos: 0, layout: layout,
        context: token, origin: .physical, text: nil, isRepeat: false))
    _ = runtime.accept(
      .init(
        kind: .flagsChanged, keyCode: 56, modifiers: [], timestampNanos: 1, layout: layout,
        context: token, origin: .physical, text: nil, isRepeat: false))
    runtime.advance(to: 300_000_001)
    wait(for: [done], timeout: 1)
  }
  func testPreferenceGestureWorksWithoutEditableFocus() {
    let context = ContextState()
    let layout = LayoutID(rawValue: "US")
    context.update(
      pid: 42, bundleID: "unsupported.editor", focusID: nil, layout: layout, qualified: false)
    let token = context.gestureContext()!
    let done = expectation(description: "preference gesture")
    let runtime = InputRuntime(
      context: context, initialLayout: layout, preferences: .init(splitShiftEnabled: true),
      command: { command in
        guard case .gesture(.toggleAuto, _) = command else { return }
        done.fulfill()
      })
    _ = runtime.accept(
      .init(
        kind: .flagsChanged, keyCode: 56, modifiers: [.shift], timestampNanos: 0, layout: layout,
        context: token, origin: .physical, text: nil, isRepeat: false))
    _ = runtime.accept(
      .init(
        kind: .flagsChanged, keyCode: 60, modifiers: [.shift], timestampNanos: 1, layout: layout,
        context: token, origin: .physical, text: nil, isRepeat: false))
    wait(for: [done], timeout: 1)
  }
  func testConfiguredLayoutChordSurvivesPreferencePublicationAndWorksWithoutEditor() {
    for (shortcut, key, modifier): (LayoutSwitchShortcut, UInt16, Modifier) in [
      (.altShift, 58, .option), (.controlShift, 59, .control)
    ] {
      let context = ContextState()
      let layout = LayoutID(rawValue: "US")
      context.update(pid: 42, bundleID: "test", focusID: nil, layout: layout, qualified: false)
      let token = context.gestureContext()!
      var actions: [GestureAction] = []
      // Use a command sink with the same freshly published preferences.
      let configured = InputRuntime(context: context, initialLayout: layout,
        command: { if case .gesture(let action, _) = $0 { actions.append(action) } })
      configured.updatePreferences(.init(layoutSwitchShortcut: shortcut))
      let sequence: [(UInt16, Set<Modifier>)] = [(key, [modifier]), (56, [modifier, .shift]),
        (key, [.shift]), (56, [])]
      for (index, pair) in sequence.enumerated() {
        XCTAssertEqual(configured.accept(.init(kind: .flagsChanged, keyCode: pair.0,
          modifiers: pair.1, timestampNanos: UInt64(index + 1), layout: layout,
          context: token, origin: .physical, text: nil, isRepeat: false)), .pass)
      }
      let drained = expectation(description: "shortcut delivered")
      DispatchQueue.main.async { drained.fulfill() }
      wait(for: [drained], timeout: 1)
      XCTAssertEqual(actions, [.switchLayout])
    }
  }

  func testForeignSyntheticInvalidatesAndDoesNotCommand() {
    var commands: [RuntimeCommand] = []
    let runtime = InputRuntime(
      context: ContextState(), initialLayout: LayoutID(rawValue: "US"),
      command: { commands.append($0) })
    let token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    XCTAssertEqual(
      runtime.accept(
        InputEvent(
          kind: .down, keyCode: 56, modifiers: [.shift], timestampNanos: 0,
          layout: LayoutID(rawValue: "US"), context: token, origin: .foreignSynthetic, text: nil,
          isRepeat: false)), .pass)
    XCTAssertTrue(commands.isEmpty)
  }
}
