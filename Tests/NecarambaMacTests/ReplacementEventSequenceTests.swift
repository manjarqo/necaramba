import Foundation
import XCTest
@testable import NecarambaMac

final class ReplacementEventSequenceTests: XCTestCase {
  func testTemporarySpaceOnlyForExactBrowserSuffixes() {
    for id in ["com.apple.Safari", "com.google.Chrome", "com.google.Chrome.beta",
      "com.google.Chrome.dev", "com.google.Chrome.canary", "com.brave.Browser",
      "com.brave.Browser.beta", "com.brave.Browser.nightly"] {
      XCTAssertTrue(ReplacementEventSequence.usesTemporarySpace(bundleID: id, selected: false))
      XCTAssertEqual(ReplacementEventSequence.deletionCount(originalCount: 3, bundleID: id, selected: false), 4)
      XCTAssertFalse(ReplacementEventSequence.usesTemporarySpace(bundleID: id, selected: true))
      XCTAssertEqual(ReplacementEventSequence.deletionCount(originalCount: 3, bundleID: id, selected: true), 0)
    }
    for id in ["test.editor", "com.google.Chrome.fake", "prefix.com.apple.Safari", "com.apple.SafariTechnologyPreview"] {
      XCTAssertFalse(ReplacementEventSequence.usesTemporarySpace(bundleID: id, selected: false))
      XCTAssertEqual(ReplacementEventSequence.deletionCount(originalCount: 3, bundleID: id, selected: false), 3)
    }
  }

  func testBrowserProgressIncludesTemporarySpaceAndItsDeletion() throws {
    let progress = try fixture()
    XCTAssertEqual(progress.valueProgress("Pab Z", minimum: 0), 0)
    XCTAssertEqual(progress.valueProgress("Pab  Z", minimum: 0), 1)
    XCTAssertEqual(progress.rangeProgress(NSRange(location: 5, length: 0), minimum: 0), 1)
    XCTAssertEqual(progress.valueProgress("Pab Z", minimum: 1), 2)
    XCTAssertEqual(progress.valueProgress("PabZ", minimum: 2), 3)
    XCTAssertEqual(progress.valueProgress("PaZ", minimum: 3), 4)
    XCTAssertEqual(progress.valueProgress("PZ", minimum: 4), 5)
    XCTAssertNotNil(progress.valueProgress("PяZ", minimum: 5))
    XCTAssertNil(progress.valueProgress("Pab  Z", minimum: 2))
    XCTAssertNil(progress.valueProgress("QяZ", minimum: 0))
    XCTAssertNil(progress.valueProgress("PяQ", minimum: 0))
    XCTAssertNil(progress.valueProgress("PwrongZ", minimum: 0))
    XCTAssertNil(progress.rangeProgress(NSRange(location: 99, length: 0), minimum: 0))
  }

  func testSelectedReplacementHasNoTemporarySpaceOrDeletionStates() throws {
    let progress = try fixture(selected: true)
    XCTAssertNil(progress.valueProgress("Pab  Z", minimum: 0))
    XCTAssertNil(progress.valueProgress("PabZ", minimum: 0))
    XCTAssertNotNil(progress.valueProgress("PяZ", minimum: 0))
  }

  func testGraphemeDeletionsAndScalarInsertionPreserveUTF16Offsets() throws {
    let progress = try XCTUnwrap(ReplacementObservationProgress(beforeValue: "😀e\u{301}👩‍💻Z",
      beforeSelection: NSRange(location: 9, length: 0), replacementRange: NSRange(location: 2, length: 7),
      original: "e\u{301}👩‍💻", replacement: "🦊я", bundleID: "test.editor", selected: false))
    XCTAssertEqual(progress.valueProgress("😀e\u{301}Z", minimum: 0), 1)
    XCTAssertEqual(progress.rangeProgress(NSRange(location: 4, length: 0), minimum: 0), 1)
    XCTAssertNil(progress.valueProgress("😀eZ", minimum: 0))
    XCTAssertNotNil(progress.valueProgress("😀🦊Z", minimum: 2))
    XCTAssertNotNil(progress.rangeProgress(NSRange(location: 4, length: 0), minimum: 2))
  }

  func testInvalidOrUnboundedEvidenceRejected() {
    for original in ["wrong", String(repeating: "a", count: 129)] {
      XCTAssertNil(ReplacementObservationProgress(beforeValue: "abc", beforeSelection: NSRange(location: 3, length: 0),
        replacementRange: NSRange(location: 0, length: 3), original: original,
        replacement: "x", bundleID: "test.editor", selected: false))
    }
  }

  func testSelectedInsertionAllowsEmptyOriginalAndLongPlainPaste() throws {
    let replacement = String(repeating: "x", count: 600)
    let progress = try XCTUnwrap(ReplacementObservationProgress(beforeValue: "AZ",
      beforeSelection: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 1, length: 0),
      original: "", replacement: replacement, bundleID: "com.apple.Safari", selected: true))
    XCTAssertNotNil(progress.valueProgress("A" + replacement + "Z", minimum: 0))
    XCTAssertNotNil(progress.rangeProgress(NSRange(location: 601, length: 0), minimum: 0))
    XCTAssertNil(progress.valueProgress("A Z", minimum: 0))
  }

  private func fixture(selected: Bool = false) throws -> ReplacementObservationProgress {
    try XCTUnwrap(ReplacementObservationProgress(beforeValue: "Pab Z",
      beforeSelection: selected ? NSRange(location: 1, length: 3) : NSRange(location: 4, length: 0),
      replacementRange: NSRange(location: 1, length: 3), original: "ab ", replacement: "я",
      bundleID: "com.apple.Safari", selected: selected))
  }
}
