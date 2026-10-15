import NecarambaCore
import XCTest

@testable import NecarambaMac

final class KeyBatchPostingTests: XCTestCase {
  func testGuardedInstantBatchCompletesWithoutConsumingDeadline() {
    let owner = EditOwnership<Int>()
    XCTAssertTrue(owner.begin(now: 0))
    var posted: [Int] = []
    let report = KeyBatchPosting.postGuardedPairs([0, 1], now: { 0 },
      ownershipValid: { owner.isActive && !owner.expired(at: $0) },
      generationValid: { true }, contextValid: { true }, secureInput: { false },
      post: { posted.append($0) })
    XCTAssertEqual(report.result, .committed)
    XCTAssertEqual(report.reason, .completed)
    XCTAssertEqual(report.elapsedNanos, 0)
    XCTAssertEqual(posted, [0, 1])
  }
  func testGuardedSevenCharacterBatchFitsExistingOwnershipBudget() {
    var time: UInt64 = 0
    let owner = EditOwnership<Int>()
    XCTAssertTrue(owner.begin(now: time))
    var posted: [Int] = []
    let result = KeyBatchPosting.postGuardedPairs(Array(0..<16), now: { time },
      ownershipValid: { owner.isActive && !owner.expired(at: $0) },
      generationValid: { true }, contextValid: { true }, secureInput: { false }) {
        posted.append($0); time += 1_000_000
      }
    XCTAssertEqual(result.result, .committed)
    XCTAssertEqual(result.reason, .completed)
    XCTAssertEqual(result.postedPairs, 8)
    XCTAssertEqual(result.elapsedNanos, 16_000_000)
    XCTAssertEqual(posted, Array(0..<16))
  }
  func testGuardedBatchCannotRenewAlmostExpiredOwnership() {
    for start: UInt64 in [90_000_000, 100_000_000] {
      let owner = EditOwnership<Int>()
      XCTAssertTrue(owner.begin(now: 0))
      var time = start
      var posted: [Int] = []
      let report = KeyBatchPosting.postGuardedPairs(Array(0..<16), now: { time },
        ownershipValid: { owner.isActive && !owner.expired(at: $0) },
        generationValid: { true }, contextValid: { true }, secureInput: { false }) {
          posted.append($0); time += 1_000_000
        }
      XCTAssertEqual(report.result, start == 100_000_000 ? .aborted : .uncertain)
      XCTAssertEqual(report.reason, .ownershipExpired)
      XCTAssertEqual(posted, start == 100_000_000 ? [] : Array(0..<10))
    }
  }
  func testGuardedBatchStopsOnSafetyChangesButAlwaysReleasesDown() {
    for expected in [KeyBatchPosting.StopReason.generationChanged, .contextChanged, .secureInput] {
      for unsafeAtEntry in [false, true] {
        var safe = !unsafeAtEntry
        var posted: [Int] = []
        let report = KeyBatchPosting.postGuardedPairs([0, 1, 2, 3], now: { 0 },
          ownershipValid: { _ in true },
          generationValid: { expected != .generationChanged || safe },
          contextValid: { expected != .contextChanged || safe },
          secureInput: { expected == .secureInput && !safe }) {
            posted.append($0); safe = false
          }
        XCTAssertEqual(report.result, unsafeAtEntry ? .aborted : .uncertain)
        XCTAssertEqual(report.reason, expected)
        XCTAssertEqual(posted, unsafeAtEntry ? [] : [0, 1])
      }
    }
  }
  func testTenMillisecondWindowCanStopSevenCharacterReplacementBeforeInsertion() {
    // Seven deletions followed by one text insertion. Each synthetic posting
    // costs 1ms; no context/security/generation change occurs.
    var now: UInt64 = 0
    var posted: [Int] = []
    let result = KeyBatchPosting.postPairs(Array(0..<16), isSafe: { now < 10_000_000 }) {
      posted.append($0)
      now += 1_000_000
    }
    XCTAssertEqual(result, .uncertain)
    XCTAssertEqual(posted, Array(0..<10))
    XCTAssertFalse(posted.contains(14), "Insertion was never dispatched")
  }
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
