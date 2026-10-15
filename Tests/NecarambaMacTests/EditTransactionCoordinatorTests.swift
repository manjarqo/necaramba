import XCTest
import NecarambaCore
@testable import NecarambaMac

final class EditTransactionCoordinatorTests: XCTestCase {
  @MainActor func testRejectsConcurrentOperationAndCompletesOnce() async {
    let coordinator = EditTransactionCoordinator()
    let token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    let suspended = expectation(description: "operation suspended")
    let cancelled = expectation(description: "operation received cancellation")
    let completed = expectation(description: "operation completed exactly once")
    var resume: CheckedContinuation<ApplyResult, Never>?
    var results: [ApplyResult] = []
    var posts = 0
    coordinator.start(token: token, operation: {
      posts += 1
      return await withTaskCancellationHandler(operation: {
        await withCheckedContinuation { resume = $0; suspended.fulfill() }
      }, onCancel: { cancelled.fulfill() })
    }, completion: { results.append($0); completed.fulfill() })
    await fulfillment(of: [suspended], timeout: 1)
    guard let resume else { return XCTFail("Operation did not reach suspension") }
    coordinator.start(token: token, operation: { posts += 1; return .committed }, completion: { results.append($0) })
    XCTAssertEqual(results, [.aborted])
    coordinator.cancel()
    await fulfillment(of: [cancelled], timeout: 1)
    // Cancellation must retain exclusivity until an in-flight post returns.
    coordinator.start(token: token, operation: { posts += 1; return .committed }, completion: { results.append($0) })
    resume.resume(returning: .committed)
    await fulfillment(of: [completed], timeout: 1)
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(results, [.aborted, .aborted, .uncertain])
  }

  @MainActor func testPerformCancellationRetainsSlotUntilLateOperationCompletes() async {
    let coordinator = EditTransactionCoordinator()
    let token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    let suspended = expectation(description: "operation suspended")
    let cancelled = expectation(description: "operation received caller cancellation")
    let completed = expectation(description: "perform returned")
    var resume: CheckedContinuation<ApplyResult, Never>?
    var result: ApplyResult?
    let request = Task { @MainActor in
      result = await coordinator.perform(token: token) {
        await withTaskCancellationHandler(operation: {
          await withCheckedContinuation { resume = $0; suspended.fulfill() }
        }, onCancel: { cancelled.fulfill() })
      }
      completed.fulfill()
    }
    await fulfillment(of: [suspended], timeout: 1)
    guard let resume else { request.cancel(); return XCTFail("Operation did not reach suspension") }
    request.cancel()
    await fulfillment(of: [cancelled], timeout: 1)
    let busy = await coordinator.perform(token: token) { XCTFail("Concurrent mutation"); return .committed }
    XCTAssertEqual(busy, .aborted)
    resume.resume(returning: .committed)
    await fulfillment(of: [completed], timeout: 1)
    XCTAssertEqual(result, .uncertain)
    let nextCompleted = expectation(description: "successor completed")
    coordinator.start(token: token, operation: { .committed }, completion: {
      XCTAssertEqual($0, .committed)
      nextCompleted.fulfill()
    })
    await fulfillment(of: [nextCompleted], timeout: 1)
  }
}
