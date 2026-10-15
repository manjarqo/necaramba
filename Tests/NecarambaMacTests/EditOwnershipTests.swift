import NecarambaCore
import XCTest

@testable import NecarambaMac

final class EditOwnershipTests: XCTestCase {
  func testOneHundredThousandEventsAcrossCommitOverflowFocusAndPartialFailure() {
    var input: [Int] = []
    var output: [Int] = []
    var mutations = 0
    for group in 0..<5000 {
      let owner = EditOwnership<Int>(capacity: 16)
      XCTAssertTrue(owner.begin(now: 0))
      var editor = "ghbdtn"
      let mode = group % 4
      for offset in 0..<20 {
        let event = group * 20 + offset
        input.append(event)
        switch owner.intercept(event, now: 1) {
        case .pass:
          output.append(event)
          editor += "a"
        case .held: break
        case .replay(let held):
          output += held
          editor += String(repeating: "a", count: held.count)
        }
        if offset == 3 && mode != 1 {
          let result = owner.commit(
            expectedGeneration: 0, currentGeneration: { mode == 2 ? 1 : 0 }, now: 2
          ) {
            mutations += 1
            if mode == 3 {
              editor.removeLast()
              return .uncertain
            }
            editor = "привет"
            return .committed
          }
          output += result.replay
          editor += String(repeating: "a", count: result.replay.count)
          XCTAssertEqual(
            result.result, mode == 2 ? .aborted : (mode == 3 ? .uncertain : .committed))
        }
      }
      XCTAssertEqual(
        editor,
        (mode == 0 ? "привет" : (mode == 3 ? "ghbdt" : "ghbdtn"))
          + String(repeating: "a", count: 20))
    }
    XCTAssertEqual(input, output)
    XCTAssertEqual(output.count, 100000)
    XCTAssertEqual(mutations, 2500)
  }
  func testStalePreparationNeverMutates() {
    let owner = EditOwnership<Int>()
    var mutated = false
    XCTAssertEqual(
      owner.commit(
        expectedGeneration: 0, currentGeneration: { 1 }, now: 0,
        mutation: {
          mutated = true
          return .committed
        }
      ).result, .aborted)
    XCTAssertFalse(mutated)
  }
  func testOverflowBeforeMutationReplaysExactlyOnceInOrder() {
    let owner = EditOwnership<Int>(capacity: 16)
    XCTAssertTrue(owner.begin(now: 0))
    for n in 0..<16 { XCTAssertEqual(owner.intercept(n, now: 1), .held) }
    XCTAssertEqual(owner.intercept(16, now: 1), .replay(Array(0...16)))
    XCTAssertEqual(owner.intercept(17, now: 1), .pass)
  }
  func testPartialFailureStopsWithoutRetryAndReleasesHeldInput() {
    let owner = EditOwnership<Int>()
    XCTAssertTrue(owner.begin(now: 0))
    _ = owner.intercept(7, now: 1)
    var writes = 0
    let result = owner.commit(
      expectedGeneration: 2, currentGeneration: { 2 }, now: 2,
      mutation: {
        writes += 1
        return .uncertain
      })
    XCTAssertEqual(result.result, .uncertain)
    XCTAssertEqual(result.replay, [7])
    XCTAssertEqual(writes, 1)
  }
  func testTimeoutAbortsBeforeMutation() {
    let owner = EditOwnership<Int>(deadlineNanos: 100)
    XCTAssertTrue(owner.begin(now: 0))
    _ = owner.intercept(4, now: 1)
    var writes = 0
    let result = owner.commit(
      expectedGeneration: 0, currentGeneration: { 0 }, now: 101,
      mutation: {
        writes += 1
        return .committed
      })
    XCTAssertEqual(result.result, .aborted)
    XCTAssertEqual(result.replay, [4])
    XCTAssertEqual(writes, 0)
  }
}

extension EditOwnershipTests {
  func testDeadlineClearsOnCancelAndCommit() {
    let owner = EditOwnership<Int>()
    XCTAssertNil(owner.nextDeadlineNanos)
    XCTAssertTrue(owner.begin(now: 10))
    XCTAssertEqual(owner.nextDeadlineNanos, 100_000_010)
    _ = owner.cancel()
    XCTAssertNil(owner.nextDeadlineNanos)
    XCTAssertTrue(owner.begin(now: 20))
    _ = owner.commit(expectedGeneration: 1, currentGeneration: { 1 }, now: 30) { .committed }
    XCTAssertNil(owner.nextDeadlineNanos)
  }
}
