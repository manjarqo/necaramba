import XCTest
@testable import NecarambaCore

final class PatternRewriteRuleTests: XCTestCase {
  func testRetainsBytePrefixAndSuffixAroundInsertion() {
    XCTAssertEqual(PatternRewriteRule(prefixBytes: 2, suffixBytes: 2, insertion: "Z").apply(to: "abcdef"), "abZef")
  }
  func testCyrillicLengthsAreUTF8Bytes() {
    XCTAssertEqual(PatternRewriteRule(prefixBytes: 2, suffixBytes: 2, insertion: "о").apply(to: "кот"), "кот")
    XCTAssertNil(PatternRewriteRule(prefixBytes: 1, suffixBytes: 0, insertion: "x").apply(to: "кот"))
  }
  func testEmojiAndCombiningScalarsRetainExactBytes() {
    XCTAssertEqual(PatternRewriteRule(prefixBytes: 4, suffixBytes: 3, insertion: "-").apply(to: "🐱abе\u{301}"), nil)
    XCTAssertEqual(PatternRewriteRule(prefixBytes: 4, suffixBytes: 4, insertion: "-").apply(to: "🐱abе\u{301}"), "🐱-е\u{301}")
  }
  func testInvalidCountsAndOversizedInputsFailClosed() {
    for rule in [PatternRewriteRule(prefixBytes: -1, suffixBytes: 0, insertion: ""),
      .init(prefixBytes: Int.max, suffixBytes: Int.max, insertion: ""),
      .init(prefixBytes: 2, suffixBytes: 2, insertion: "")] {
      XCTAssertNil(rule.apply(to: "abc"))
    }
    XCTAssertNil(PatternRewriteRule(prefixBytes: 0, suffixBytes: 0, insertion: String(repeating: "x", count: 513)).apply(to: "a"))
    XCTAssertNil(PatternRewriteRule(prefixBytes: 0, suffixBytes: 0, insertion: "a").apply(to: String(repeating: "x", count: 513)))
  }
}
