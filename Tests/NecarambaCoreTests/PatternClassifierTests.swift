import XCTest
@testable import NecarambaCore

final class PatternClassifierTests: XCTestCase {
  private func feature(_ weight: Int32, pair: String = "a-b", sensitive: Bool = false,
    known: Bool = false) -> PatternFeature {
    .init(languagePair: pair, weight: weight, caseSensitive: sensitive, knownWord: known)
  }
  private func classifier(_ patterns: [ClassifierPattern]) throws -> PatternClassifier {
    try .init(patterns: patterns, supportedLanguagePairs: ["a-b", "c-d"])
  }

  func testOverlappingMatchesAndRepeatedOccurrencesContributeEveryWeight() throws {
    let engine = try classifier([
      .init(text: "a", features: [feature(1)]),
      .init(text: "aa", features: [feature(-2)])
    ])
    XCTAssertEqual(engine.classify("aaa", languagePair: "a-b"), .init(status: .scored, score: -1))
  }

  func testStartEndAnchorsAndLanguageFiltering() throws {
    let engine = try classifier([
      .init(text: "\u{2}ab\u{3}", features: [feature(7), feature(100, pair: "c-d")]),
      .init(text: "ab", features: [feature(1)])
    ])
    XCTAssertEqual(engine.classify("ab", languagePair: "a-b").score, 8)
    XCTAssertEqual(engine.classify("cab", languagePair: "a-b").score, 1)
    XCTAssertEqual(engine.classify("abc", languagePair: "a-b").score, 1)
    XCTAssertEqual(engine.classify("ab", languagePair: "c-d").score, 100)
    XCTAssertEqual(engine.classify("ab", languagePair: "missing").status, .unsupported)
  }

  func testLowercasePassAndOriginalCasePassDoNotDoubleCount() throws {
    let engine = try classifier([
      .init(text: "a", features: [feature(2)]),
      .init(text: "A", features: [feature(3, sensitive: true)])
    ])
    XCTAssertEqual(engine.classify("A", languagePair: "a-b").score, 5)
    XCTAssertEqual(engine.classify("a", languagePair: "a-b").score, 2)
  }

  func testZeroWeightAssertionsUnknownWinsAndWeightsRemainSeparate() throws {
    let engine = try classifier([
      .init(text: "x", features: [feature(0, known: true), feature(4)]),
      .init(text: "y", features: [feature(0)])
    ])
    XCTAssertEqual(engine.classify("x", languagePair: "a-b"), .init(status: .known, score: 4))
    XCTAssertEqual(engine.classify("xy", languagePair: "a-b"), .init(status: .rejected, score: 4))
    XCTAssertEqual(engine.classify("z", languagePair: "a-b"), .init(status: .scored, score: 0))
  }

  func testNonzeroKnownFlagIsNotAnAssertion() throws {
    let engine = try classifier([.init(text: "x", features: [feature(2, known: true)])])
    XCTAssertEqual(engine.classify("x", languagePair: "a-b").status, .scored)
  }

  func testUnicodeMatchesUseUTF8AndLowercaseWithoutCanonicalNormalization() throws {
    let engine = try classifier([
      .init(text: "ёж", features: [feature(3)]),
      .init(text: "é", features: [feature(4)])
    ])
    XCTAssertEqual(engine.classify("ЁЖёж", languagePair: "a-b").score, 6)
    XCTAssertEqual(engine.classify("e\u{301}", languagePair: "a-b").score, 0)
  }

  func testMalformedPatternsAndUndefinedFeatureLanguagesAreRejectedAtCompilation() {
    for text in ["", "a\u{2}", "\u{3}a", "a\u{0}b", String(repeating: "x", count: 513)] {
      XCTAssertThrowsError(try classifier([.init(text: text, features: [feature(1)])]))
    }
    XCTAssertThrowsError(try classifier([.init(text: "a", features: [feature(1, pair: "unknown")])]))
  }

  func testIncompleteFramingDoesNotMatchEndAnchoredPattern() throws {
    let engine = try classifier([.init(text: "\u{2}x\u{3}", features: [feature(4)])])
    XCTAssertEqual(engine.classify("x", languagePair: "a-b", framing: .incomplete).score, 0)
    XCTAssertEqual(engine.classify("x", languagePair: "a-b", framing: .complete).score, 4)
    XCTAssertEqual(engine.classify("", languagePair: "a-b"), .init(status: .scored, score: 0))
    XCTAssertEqual(engine.classify(" x ", languagePair: "a-b").score, 0)
  }

  func testDuplicateDeclarationsContributeIndependently() throws {
    let pattern = ClassifierPattern(text: "x", features: [feature(3)])
    let engine = try classifier([pattern, pattern])
    XCTAssertEqual(engine.classify("xx", languagePair: "a-b").score, 12)
  }

  func testEvaluationBudgetAndCompileFeatureBudgetFailClosed() throws {
    let engine = try classifier([.init(text: "x", features: Array(repeating: feature(1), count: 100_001))])
    XCTAssertEqual(engine.classify("x", languagePair: "a-b"), .init(status: .unsupported, score: 0))
    XCTAssertThrowsError(try classifier([
      .init(text: "x", features: Array(repeating: feature(1), count: 1_000_001))
    ]))
  }

  func testLowercaseExpansionIsCheckedAgainstInputLimit() throws {
    let engine = try classifier([])
    // Latin capital I with dot expands to three UTF-8 bytes when lowercased.
    XCTAssertEqual(engine.classify(String(repeating: "İ", count: 200), languagePair: "a-b").status, .unsupported)
  }

  func testTokenFramingUsesOriginalDelimiterNotTrimmedWhitespace() throws {
    let engine = try classifier([.init(text: "\u{2}x\u{3}", features: [feature(7)])])
    XCTAssertEqual(engine.classifyToken("x ", languagePair: "a-b").score, 7)
    XCTAssertEqual(engine.classifyToken("x\t", languagePair: "a-b").score, 7)
    XCTAssertEqual(engine.classifyToken("x\u{a0}", languagePair: "a-b").score, 0)
    XCTAssertEqual(engine.classifyToken("x\u{a0}", languagePair: "a-b", forceComplete: true).score, 7)
  }

  func testTokenTrimsExactUnicodeWhitespaceAndPreservesHyphenInPrimary() throws {
    let engine = try classifier([
      .init(text: "\u{2}x-\u{3}", features: [feature(5)]),
      .init(text: "\u{2}x\u{3}", features: [feature(9)])
    ])
    XCTAssertEqual(engine.classifyToken("\u{2003}x-", languagePair: "a-b").score, 5)
    XCTAssertEqual(engine.classifyToken("\u{85}x\u{3000}", languagePair: "a-b", forceComplete: true).score, 9)
    XCTAssertEqual(engine.classifyToken("\u{200b}x", languagePair: "a-b", forceComplete: true).score, 0)
  }

  func testTokenFallbackUsesModeSpecificPunctuationAndLeadingStripping() throws {
    let engine = try classifier([
      .init(text: "\u{2}x", features: [feature(2)]),
      .init(text: "\u{2}x\u{3}", features: [feature(3)])
    ])
    XCTAssertEqual(engine.classifyToken("(-x_", languagePair: "a-b").score, 2)
    XCTAssertEqual(engine.classifyToken("(-x?", languagePair: "a-b", forceComplete: true).score, 5)
    XCTAssertEqual(engine.classifyToken("(-x_", languagePair: "a-b", forceComplete: true).score, 2)
  }

  func testExistingZeroUnknownFeaturePreventsTokenFallback() throws {
    let engine = try classifier([
      .init(text: "!", features: [feature(0)]),
      .init(text: "\u{2}x\u{3}", features: [feature(9)])
    ])
    XCTAssertEqual(engine.classifyToken("x!", languagePair: "a-b", forceComplete: true),
      .init(status: .rejected, score: 0))
  }

  func testForeignLanguageAndCaseFilteredFeaturesDoNotSuppressFallback() throws {
    let engine = try classifier([
      .init(text: "!", features: [feature(0, pair: "c-d")]),
      .init(text: "X!", features: [feature(0, sensitive: true)]),
      .init(text: "\u{2}x\u{3}", features: [feature(8)])
    ])
    XCTAssertEqual(engine.classifyToken("x!", languagePair: "a-b", forceComplete: true).score, 8)
    XCTAssertEqual(engine.classifyToken("X!", languagePair: "a-b", forceComplete: true).status, .rejected)
  }

  func testTokenFallbackPunctuationIsModeSpecificAndCleanupIsNotIterative() throws {
    let engine = try classifier([
      .init(text: "\u{2}x\u{3}", features: [feature(1)]),
      .init(text: "\u{2}x", features: [feature(2)])
    ])
    for suffix in ["!", "$", "&", "(", ")", "*", "+", "-", "/", "?", "@", "^"] {
      XCTAssertEqual(engine.classifyToken("(-x" + suffix, languagePair: "a-b", forceComplete: true).score, 3)
    }
    for suffix in ["!", "(", ")", "+", "=", "_"] {
      XCTAssertEqual(engine.classifyToken("(-x" + suffix, languagePair: "a-b").score, 2)
    }
    // Final whitespace trim does not restart leading punctuation stripping.
    XCTAssertEqual(engine.classifyToken("( -x!", languagePair: "a-b", forceComplete: true).score, 0)
  }

  func testTokenControlsAndBoundsFailClosed() throws {
    let engine = try classifier([])
    for input in ["x\u{2}", "x\u{0}", "x\tx", String(repeating: " ", count: 513)] {
      XCTAssertEqual(engine.classifyToken(input, languagePair: "a-b").status, .unsupported)
    }
    XCTAssertEqual(engine.classifyToken(" ", languagePair: "missing").status, .unsupported)
    XCTAssertEqual(engine.classifyToken(" ", languagePair: "a-b"), .init(status: .scored, score: 0))
  }

  func testInputBoundsAndOverflowFailClosed() throws {
    let engine = try classifier([.init(text: "x", features: [feature(Int32.max)])])
    for input in ["x\u{2}", String(repeating: "x", count: 513), "xx"] {
      XCTAssertEqual(engine.classify(input, languagePair: "a-b"), .init(status: .unsupported, score: 0))
    }
  }
}
