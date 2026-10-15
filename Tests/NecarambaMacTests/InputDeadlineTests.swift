import XCTest
import NecarambaCore
@testable import NecarambaMac

final class InputDeadlineTests: XCTestCase {
  func testIdleDeduplicationAndStaleWakeupCancellation() {
    var actions: [() -> Void] = []
    var cancellations = 0
    var fired = 0
    let timer = InputDeadlineScheduler { _, action in
      actions.append(action)
      return { cancellations += 1 }
    }
    timer.update(deadline: nil) { fired += 1 }
    XCTAssertTrue(actions.isEmpty)
    timer.update(deadline: 100) { fired += 1 }
    timer.update(deadline: 100) { fired += 1 }
    XCTAssertEqual(actions.count, 1)
    timer.update(deadline: 50) { fired += 1 }
    XCTAssertEqual(cancellations, 1)
    actions[0]()
    XCTAssertEqual(fired, 0)
    actions[1]()
    actions[1]()
    XCTAssertEqual(fired, 1)
    timer.update(deadline: 80) { fired += 1 }
    timer.update(deadline: nil) { fired += 1 }
    actions[2]()
    XCTAssertEqual(fired, 1)
  }
}

extension InputDeadlineTests {
  func testGestureAndOwnershipShareDeadlineAndExpiredWorkRunsOnce() {
    var scheduled: [(UInt64, () -> Void)] = []
    var delivered: [GestureAction] = []
    var replayed: [Int] = []
    let timer = InputDeadlineScheduler { deadline, action in
      scheduled.append((deadline, action))
      return {}
    }
    var gesture = GestureRecognizer(configuration: .init(singleShift: true, option: false, splitShift: false))
    let token = ContextToken(pid: 1, bundleID: "fixture", focusEpoch: 1, layoutEpoch: 1)
    func shift(_ time: UInt64, _ down: Bool) -> InputEvent {
      .init(kind: .flagsChanged, keyCode: 56, modifiers: down ? [.shift] : [],
        timestampNanos: time, layout: .init(rawValue: "US"), context: token, origin: .physical, text: nil, isRepeat: false)
    }
    _ = gesture.consume(shift(0, true))
    _ = gesture.consume(shift(20_000_000, false))
    let owner = EditOwnership<Int>()
    XCTAssertTrue(owner.begin(now: 220_000_000))
    XCTAssertEqual(owner.intercept(7, now: 230_000_000), .held)
    let deadline = [gesture.nextDeadlineNanos, owner.nextDeadlineNanos].compactMap { $0 }.min()
    XCTAssertEqual(deadline, 320_000_000)
    timer.update(deadline: deadline) {
      if owner.expired(at: 320_000_000) {
        replayed += owner.cancel()
        // Production ownership expiry invalidates runtime, including pending gestures.
        gesture.invalidate()
      }
      delivered += gesture.advance(to: 320_000_000)
    }
    scheduled[0].1()
    scheduled[0].1()
    XCTAssertEqual(replayed, [7])
    XCTAssertEqual(delivered, [])
    XCTAssertNil(owner.nextDeadlineNanos)
    XCTAssertNil(gesture.nextDeadlineNanos)
    timer.update(deadline: nil) {}
    XCTAssertEqual(scheduled.count, 1)
  }
  func testRestartRejectsOldCallbackAndLateWakeupClearsPendingGesture() {
    var actions: [() -> Void] = []
    let scheduler = InputDeadlineScheduler { _, action in actions.append(action); return {} }
    var fired = 0
    scheduler.update(deadline: 10) { fired += 1 }
    scheduler.update(deadline: nil) {}
    scheduler.update(deadline: 20) { fired += 10 }
    actions[0]()
    actions[1]()
    XCTAssertEqual(fired, 10)
    XCTAssertEqual(actions.count, 2)
  }
}
extension InputDeadlineTests {
  func testRuntimeDeadlineDrivesGestureWithoutPeriodicTicksAndStopClearsIt() {
    let context = ContextState()
    let layout = LayoutID(rawValue: "US")
    context.update(pid: 42, bundleID: "fixture", focusID: "field", layout: layout, qualified: true)
    let token = context.current()!
    let delivered = expectation(description: "one deadline gesture")
    var count = 0
    let runtime = InputRuntime(context: context, initialLayout: layout, command: { command in
      if case .gesture(.switchLayout, _) = command { count += 1; delivered.fulfill() }
    })
    func shift(_ down: Bool, _ time: UInt64) {
      runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: down ? [.shift] : [],
        timestampNanos: time, layout: layout, context: token, origin: .physical, text: nil, isRepeat: false))
    }
    XCTAssertNil(runtime.nextDeadlineNanos)
    shift(true, 0); shift(false, 1)
    XCTAssertEqual(runtime.nextDeadlineNanos, 300_000_001)
    runtime.advance(to: runtime.nextDeadlineNanos!)
    XCTAssertNil(runtime.nextDeadlineNanos)
    wait(for: [delivered], timeout: 1)
    XCTAssertEqual(count, 1)
    shift(true, 400_000_000); shift(false, 400_000_001)
    XCTAssertNotNil(runtime.nextDeadlineNanos)
    runtime.stop()
    XCTAssertNil(runtime.nextDeadlineNanos)
  }
}
