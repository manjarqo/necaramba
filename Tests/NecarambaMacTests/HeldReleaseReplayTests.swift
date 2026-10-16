import CoreGraphics
import XCTest
@testable import NecarambaMac

/// The physical Space release usually arrives while the replacement owns input.
/// Replaying a held key release cannot change text and must keep the edit generation.
final class HeldReleaseReplayTests: XCTestCase {
  func testOnlyHeldKeyReleasesDoNotInvalidateInput() throws {
    let spaceUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false))
    let letterUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false))
    let letterDown = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
    XCTAssertFalse(EventTapAdapter.replayInvalidatesInput([spaceUp]))
    XCTAssertFalse(EventTapAdapter.replayInvalidatesInput([spaceUp, letterUp]))
    XCTAssertTrue(EventTapAdapter.replayInvalidatesInput([spaceUp, letterDown]))
    XCTAssertFalse(EventTapAdapter.replayInvalidatesInput([]))
  }
}
