import XCTest
@testable import NecarambaMac
import NecarambaCore

final class PhasedKeyPostingTests: XCTestCase {
  func testPhysicalCapacityReservesDeletionAndBrowserWorkaroundBeforeChoosingTransport() {
    XCTAssertTrue(ReplacementEventSequence.canReplayPhysical(keyCount: 256, deleteCount: 0, temporarySpace: false))
    XCTAssertFalse(ReplacementEventSequence.canReplayPhysical(keyCount: 257, deleteCount: 0, temporarySpace: false))
    XCTAssertTrue(ReplacementEventSequence.canReplayPhysical(keyCount: 128, deleteCount: 128, temporarySpace: false))
    XCTAssertFalse(ReplacementEventSequence.canReplayPhysical(keyCount: 128, deleteCount: 128, temporarySpace: true))
    XCTAssertFalse(ReplacementEventSequence.canReplayPhysical(keyCount: 0, deleteCount: 1, temporarySpace: false))
  }
  func testWaitsBeforeDeleteAndBeforeRetype() {
    var scheduled: [(Double, () -> Void)] = []
    var posted: [Int] = []
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [1, 2], insertion: [3, 4],
      schedule: { scheduled.append(($0, $1)) }, authorized: { true },
      post: { events in posted += events; return .committed }, finish: { result = $0 })
    XCTAssertTrue(posted.isEmpty)
    XCTAssertEqual(scheduled[0].0, 0.025)
    scheduled.removeFirst().1()
    XCTAssertEqual(posted, [1, 2])
    XCTAssertNil(result)
    XCTAssertEqual(scheduled[0].0, 0.025)
    scheduled.removeFirst().1()
    XCTAssertEqual(posted, [1, 2, 3, 4])
    XCTAssertEqual(result, .committed)
  }
  func testLostAuthorizationBeforeDeleteAbortsWithoutPosting() {
    var scheduled: [() -> Void] = []
    var safe = true
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [1, 2], insertion: [3, 4],
      schedule: { _, action in scheduled.append(action) }, authorized: { safe },
      post: { _ in XCTFail("No events allowed"); return .committed }, finish: { result = $0 })
    safe = false
    scheduled.removeFirst()()
    XCTAssertEqual(result, .aborted)
  }
  func testLostAuthorizationAfterDeleteIsUncertainAndNeverRetries() {
    var scheduled: [() -> Void] = []
    var safe = true
    var posted: [Int] = []
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [1, 2], insertion: [3, 4],
      schedule: { _, action in scheduled.append(action) }, authorized: { safe },
      post: { posted += $0; return .committed }, finish: { result = $0 })
    scheduled.removeFirst()()
    safe = false
    scheduled.removeFirst()()
    XCTAssertEqual(posted, [1, 2])
    XCTAssertEqual(result, .uncertain)
    XCTAssertTrue(scheduled.isEmpty)
  }
  func testPartialDeletionDoesNotScheduleRetype() {
    var scheduled: [() -> Void] = []
    var calls = 0
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [1, 2], insertion: [3, 4],
      schedule: { _, action in scheduled.append(action) }, authorized: { true },
      post: { _ in calls += 1; return .uncertain }, finish: { result = $0 })
    scheduled.removeFirst()()
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(result, .uncertain)
    XCTAssertTrue(scheduled.isEmpty)
  }
  func testInsertionAbortAfterDeletionIsUncertain() {
    var scheduled: [() -> Void] = []
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [1, 2], insertion: [3, 4],
      schedule: { _, action in scheduled.append(action) }, authorized: { true },
      post: { $0 == [1, 2] ? .committed : .aborted }, finish: { result = $0 })
    scheduled.removeFirst()()
    scheduled.removeFirst()()
    XCTAssertEqual(result, .uncertain)
  }
  func testSelectedReplacementCancellationBeforeFirstPostAborts() {
    var scheduled: [() -> Void] = []
    var safe = true
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [Int](), insertion: [3, 4],
      schedule: { _, action in scheduled.append(action) }, authorized: { safe },
      post: { _ in XCTFail("No events allowed"); return .committed }, finish: { result = $0 })
    scheduled.removeFirst()()
    safe = false
    scheduled.removeFirst()()
    XCTAssertEqual(result, .aborted)
  }
  func testReplacedOwnershipDoesNotAuthorizeOldPhase() {
    let owner = EditOwnership<Int>()
    XCTAssertTrue(owner.begin(now: 0))
    let revision = owner.revision
    var scheduled: [() -> Void] = []
    var result: ApplyResult?
    PhasedKeyPosting.run(deletion: [1, 2], insertion: [3, 4],
      schedule: { _, action in scheduled.append(action) },
      authorized: { owner.isActive && owner.revision == revision },
      post: { _ in .committed }, finish: { result = $0 })
    scheduled.removeFirst()()
    _ = owner.cancel()
    XCTAssertTrue(owner.begin(now: 10))
    scheduled.removeFirst()()
    XCTAssertEqual(result, .uncertain)
    XCTAssertTrue(owner.isActive)
  }

}
