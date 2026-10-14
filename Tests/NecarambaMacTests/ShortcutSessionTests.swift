import CoreGraphics
import NecarambaCore
import XCTest

@testable import NecarambaMac

final class ShortcutSessionTests: XCTestCase {
  let token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  func testExpiredPreparationCannotReacquireAfterFallback() {
    let session = ShortcutSession()
    let lease = ShortcutLease(context: token, generation: 1, startedNanos: 0)
    XCTAssertTrue(session.begin(lease))
    session.cancel()
    XCTAssertFalse(session.admits(lease, generation: 2, context: token, now: 101_000_000))
    let newer = ShortcutLease(context: token, generation: 2, startedNanos: 102_000_000)
    XCTAssertTrue(session.begin(newer))
    XCTAssertFalse(session.admits(lease, generation: 2, context: token, now: 102_000_001))
  }
  func testOverflowCancellationCannotBorrowNewGeneration() {
    let session = ShortcutSession()
    let lease = ShortcutLease(context: token, generation: 1, startedNanos: 0)
    XCTAssertTrue(session.begin(lease))
    session.cancel()
    XCTAssertFalse(session.admits(lease, generation: 5, context: token, now: 20))
  }
  func testChangedFocusRejectsOriginalLeaseEvenAtSameGeneration() {
    let session = ShortcutSession()
    let lease = ShortcutLease(context: token, generation: 1, startedNanos: 0)
    XCTAssertTrue(session.begin(lease))
    let other = ContextToken(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
    XCTAssertFalse(session.admits(lease, generation: 1, context: other, now: 20))
  }
  func testOnlyOriginalVPressIsConsumed() {
    let down = key(true)
    let up = key(false)
    let ordinaryDown = key(true)
    let ordinaryUp = key(false)
    down.flags = [.maskCommand, .maskShift]
    let flags = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false)!
    flags.type = .flagsChanged
    let filtered = ShortcutSession.consumeTrigger([down, up, flags, ordinaryDown, ordinaryUp])
    XCTAssertEqual(filtered.events.count, 3)
    XCTAssertTrue(filtered.events[0] === flags)
    XCTAssertTrue(filtered.events[1] === ordinaryDown)
    XCTAssertTrue(filtered.events[2] === ordinaryUp)
    XCTAssertFalse(filtered.awaitingRelease)
  }
  private func key(_ down: Bool) -> CGEvent {
    CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)!
  }
}
