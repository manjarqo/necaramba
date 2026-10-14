import NecarambaCore
import XCTest

@testable import NecarambaMac

final class KeyBatchPostingTests: XCTestCase {
  func testAlwaysFinishesUpAfterDownEvenWhenSafetyExpires() {
    var events: [Int] = []
    var safe = true
    let result = KeyBatchPosting.postPairs(
      [0, 1, 2, 3], isSafe: { safe },
      post: { event in
        events.append(event)
        safe = false
      })
    XCTAssertEqual(events, [0, 1])
    XCTAssertEqual(result, .uncertain)
  }
  func testNoSafeEntryMeansNoDeletion() {
    var events: [Int] = []
    XCTAssertEqual(
      KeyBatchPosting.postPairs([0, 1], isSafe: { false }, post: { events.append($0) }), .aborted)
    XCTAssertTrue(events.isEmpty)
  }
}
