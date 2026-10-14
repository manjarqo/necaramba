import CoreGraphics
import NecarambaCore
import XCTest
@testable import NecarambaMac

final class EventTapLifecycleTests: XCTestCase {
    func testStoppedAdapterPassesLateCallbacksWithoutTouchingRuntime() throws {
        let runtime = InputRuntime(context: ContextState(), initialLayout: LayoutID(rawValue: "US"))
        let adapter = EventTapAdapter(runtime: runtime)
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        adapter.stop()
        let generation = runtime.inputGeneration()
        XCTAssertTrue(adapter.receive(.leftMouseDown, event))
        XCTAssertTrue(adapter.receive(.tapDisabledByTimeout, event))
        XCTAssertTrue(adapter.receive(.tapDisabledByUserInput, event))
        XCTAssertEqual(runtime.inputGeneration(), generation)
        XCTAssertFalse(adapter.isInstalled)
    }

    func testStopWaitsForInflightCallbackBeforeReturningToReplacementTap() throws {
        let context = BlockingTapContext()
        let runtime = InputRuntime(context: context, initialLayout: LayoutID(rawValue: "US"))
        let adapter = EventTapAdapter(runtime: runtime)
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        let received = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = adapter.receive(.keyDown, event)
            received.signal()
        }
        XCTAssertEqual(context.entered.wait(timeout: .now() + 1), .success)
        let stopping = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            stopping.signal()
            adapter.stop()
            stopped.signal()
        }
        XCTAssertEqual(stopping.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(stopped.wait(timeout: .now() + 0.05), .timedOut)
        context.resume.signal()
        XCTAssertEqual(received.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(stopped.wait(timeout: .now() + 1), .success)
    }

    func testStoppedTimerCannotFirePendingGesture() {
        let context = ContextState()
        let layout = LayoutID(rawValue: "US")
        context.update(pid: 42, bundleID: "test", focusID: "field", layout: layout, qualified: true)
        var commands: [RuntimeCommand] = []
        let runtime = InputRuntime(context: context, initialLayout: layout, command: { commands.append($0) })
        let adapter = EventTapAdapter(runtime: runtime)
        let token = context.current()!
        _ = runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: [.shift],
            timestampNanos: 0, layout: layout, context: token, origin: .physical, text: nil, isRepeat: false))
        _ = runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: [],
            timestampNanos: 1, layout: layout, context: token, origin: .physical, text: nil, isRepeat: false))
        adapter.stop()
        adapter.tick()
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertTrue(commands.isEmpty)
    }
}

private final class BlockingTapContext: ContextAccess {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func current() -> ContextToken? {
        entered.signal()
        _ = resume.wait(timeout: .now() + 2)
        return ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    }
    func isSafe(_ token: ContextToken) -> Bool { true }
}
