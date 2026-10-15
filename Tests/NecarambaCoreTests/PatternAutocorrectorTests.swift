import XCTest
@testable import NecarambaCore

final class PatternAutocorrectorTests: XCTestCase {
  private func rule(_ pattern: String, _ insertion: String, prefix: Int = 0, suffix: Int = 0,
    sensitive: Bool = false, yo: Bool = false) -> PatternAutocorrectRule {
    .init(pattern: pattern, rewrite: .init(prefixBytes: prefix, suffixBytes: suffix, insertion: insertion),
      caseSensitive: sensitive, isYofikator: yo)
  }
  func testUnicodeByteSpliceAndOriginalWhitespacePreservation() throws {
    let engine = try PatternAutocorrector(rules: [rule("\u{2}ёж\u{3}", "и", prefix: 2)])
    XCTAssertEqual(engine.correct(" ёж ").replacement, " ёи ")
  }
  func testCaseSensitiveReplacesAllNonoverlappingOccurrences() throws {
    let engine = try PatternAutocorrector(rules: [rule("aa", "x", sensitive: true)])
    XCTAssertEqual(engine.correct("aaaaa").replacement, "xxa")
    XCTAssertEqual(engine.correct("AA").status, .unchanged)
  }
  func testMatchesAreOrderedAndNotRecomputedAfterRewrite() throws {
    let engine = try PatternAutocorrector(rules: [rule("a", "b"), rule("b", "c")])
    XCTAssertEqual(engine.correct("a").replacement, "b")
    XCTAssertEqual(engine.correct("ab").replacement, "cc")
  }
  func testShortPrefixMatchPrecedesLongMatch() throws {
    let engine = try PatternAutocorrector(rules: [rule("ab", "z"), rule("a", "x")])
    XCTAssertEqual(engine.correct("ab").replacement, "xb")
  }
  func testCaseProjectionUsesStrictMajorityAndPositionalUppercase() throws {
    let engine = try PatternAutocorrector(rules: [rule("hello", "worldwide")])
    XCTAssertEqual(engine.correct("HEllo").replacement, "WOrldwide")
    XCTAssertEqual(engine.correct("HELlo").replacement, "WORLDWIDE")
    let tie = try PatternAutocorrector(rules: [rule("ab", "xyz")])
    XCTAssertEqual(tie.correct("Ab").replacement, "Xyz")
  }
  func testReplacementCaseIsPreservedAndUnicodeExpansionIsPerScalar() throws {
    let engine = try PatternAutocorrector(rules: [rule("ab", "XyZ"), rule("c", "ß")])
    XCTAssertEqual(engine.correct("ab").replacement, "XyZ")
    XCTAssertEqual(engine.correct("C").replacement, "SS")
    let scalars = try PatternAutocorrector(rules: [rule("ss", "x")])
    XCTAssertEqual(scalars.correct("ß").status, .unchanged)
  }
  func testExplicitYoFlagAndOrdinaryToggle() throws {
    let engine = try PatternAutocorrector(rules: [rule("a", "b", yo: true)])
    XCTAssertEqual(engine.correct("a", typoEnabled: false, yoEnabled: true).replacement, "b")
    XCTAssertEqual(engine.correct("a", typoEnabled: true, yoEnabled: false).status, .unchanged)
  }
  func testDynamicYoUsesFullCurrentTextSetAndOccurrenceCount() throws {
    let single = try PatternAutocorrector(rules: [rule("е", "ё")])
    XCTAssertEqual(single.correct("е", typoEnabled: false).replacement, "ё")
    XCTAssertEqual(single.correct("её", typoEnabled: false).status, .unchanged)
    let repeated = try PatternAutocorrector(rules: [rule("е", "ёё")])
    XCTAssertEqual(repeated.correct("е", typoEnabled: false).status, .unchanged)
    let extra = try PatternAutocorrector(rules: [rule("е", "ёж")])
    XCTAssertEqual(extra.correct("е", typoEnabled: false).status, .unchanged)
  }
  func testShorterReplacementAndScalarBoundaries() throws {
    let engine = try PatternAutocorrector(rules: [rule("abcd", "xy"), rule("é", "a")])
    XCTAssertEqual(engine.correct("ABcd").replacement, "XY")
    XCTAssertEqual(engine.correct("e\u{301}").status, .unchanged)
  }
  func testOriginalOccurrencesRetainedButLowercaseAdditionsDeduplicated() throws {
    let engine = try PatternAutocorrector(rules: [rule("x", "xx")])
    XCTAssertEqual(engine.correct("xx").replacement, "xxxxxxxx")
    XCTAssertEqual(engine.correct("XX").replacement, "XXXX")
  }
  func testCompleteFallbackRetainsOutputPunctuationAndUsesAutocorrectMask() throws {
    let engine = try PatternAutocorrector(rules: [rule("\u{2}teh\u{3}", "the")])
    XCTAssertEqual(engine.correct("-(teh.), ").replacement, "-(the.), ")
    XCTAssertEqual(engine.correct("(teh!").status, .unchanged)
    XCTAssertEqual(engine.correct("(teh?", forceComplete: true).status, .unchanged)
    XCTAssertEqual(engine.correct("teh\u{a0}").status, .unchanged)
    XCTAssertEqual(engine.correct("teh\u{a0}", forceComplete: true).replacement, "the\u{a0}")
  }
  func testAnyPrimaryMatchPreventsFallbackEvenWhenToggleDisablesIt() throws {
    let engine = try PatternAutocorrector(rules: [rule("!", "?"), rule("\u{2}е\u{3}", "ё")])
    XCTAssertEqual(engine.correct("е! ", typoEnabled: false, yoEnabled: true).status, .unchanged)
  }
  func testOutputAndCompileBudgetsFailClosed() throws {
    let engine = try PatternAutocorrector(rules: [rule("x", String(repeating: "a", count: 300))])
    let result = engine.correct("xx")
    XCTAssertEqual(result.status, .unsupported)
    XCTAssertNil(result.replacement)
    XCTAssertThrowsError(try PatternAutocorrector(rules: Array(repeating: rule("x", "a"), count: 100_001)))
  }
  func testTabInsertionIsLiteralTextWithoutDispatchAuthorization() throws {
    let engine = try PatternAutocorrector(rules: [rule("ab", "a\tb")])
    XCTAssertEqual(engine.correct("ab").replacement, "a\tb")
    for control in ["\u{0}", "\u{1b}", "\n", "\r"] {
      XCTAssertThrowsError(try PatternAutocorrector(rules: [rule("ab", control)]))
    }
  }
  func testMalformedRulesAndInputAreRejected() throws {
    for pattern in ["", "a\u{2}", "\u{3}a"] {
      XCTAssertThrowsError(try PatternAutocorrector(rules: [rule(pattern, "x")]))
    }
    XCTAssertThrowsError(try PatternAutocorrector(rules: [rule("я", "x", prefix: 1)]))
    let engine = try PatternAutocorrector(rules: [])
    XCTAssertEqual(engine.correct("x\u{2}").status, .unsupported)
    XCTAssertEqual(engine.correct(String(repeating: "x", count: 513)).status, .unsupported)
  }
}
