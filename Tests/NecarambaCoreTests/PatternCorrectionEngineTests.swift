import XCTest
@testable import NecarambaCore
final class PatternCorrectionEngineTests: XCTestCase {
  private let ru = LayoutID(rawValue: "RU"), en = LayoutID(rawValue: "US")
  private func make(_ ruWeight: Int32 = 2, _ enWeight: Int32 = 1,
    ruKnown: Bool = false, enKnown: Bool = false, reject: Bool = false,
    rules: [PatternAutocorrectRule] = []) throws -> PatternCorrectionEngine {
    let classifier = try PatternClassifier(patterns: [
      .init(text: "привет", features: [.init(languagePair: "ru-en", weight: ruWeight, knownWord: ruKnown)]),
      .init(text: "ghbdtn", features: [.init(languagePair: "ru-en", weight: enWeight, knownWord: enKnown)])
    ] + (reject ? [.init(text: "ghbdtn", features: [.init(languagePair: "ru-en", weight: 0)])] : []),
      supportedLanguagePairs: ["ru-en"])
    return .init(classifier: classifier, autocorrector: try .init(rules: rules))
  }
  private func decide(_ engine: PatternCorrectionEngine, sourceRU: Bool = false,
    preferences: PreferencesSnapshot = .defaults, excluded: Set<String> = []) -> LinguisticDecision {
    let layout = sourceRU ? ru : en
    let word = BufferedWord(text: sourceRU ? "привет" : "ghbdtn", events: [],
      context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: layout, delimiter: " ")
    return engine.decide(word: word, russianCandidate: "привет", russianLayout: ru,
      englishCandidate: "ghbdtn", englishLayout: en, preferences: preferences, excludedWords: excluded, modelVersion: 17)
  }
  private func correction(_ value: LinguisticDecision) -> Correction? {
    guard case .replace(let result) = value else { return nil }; return result
  }
  func testVerifiedPhysicalPunctuationRequiresKnownRussianAndNegativeEnglish() throws {
    for (source, target) in [("nj;t", "тоже"), ("gthtrk.xbkjcm", "переключилось")] {
      for verified in [false, true] {
        let result = try punctuationDecision(source, target, verified: verified)
        if verified { XCTAssertEqual(correction(result)?.replacement, target) }
        else { XCTAssertEqual(result, .unchanged(.protectedToken)) }
      }
      XCTAssertEqual(try punctuationDecision(source, target, verified: true, score: 0), .unchanged(.protectedToken))
      XCTAssertEqual(try punctuationDecision(source, target, verified: true, known: false), .unchanged(.protectedToken))
    }
  }
  func testPhysicalPunctuationDoesNotAdmitURLsPathsOrCommands() throws {
    for source in ["1ю3ю166", "1.3.166", "foo.com", "example.org", "a.b.c", "foo/bar", "foo\\bar", "a@b", "a2;b", "curl:foo", "a&&b", "$(cmd)", ";", "a\t;b"] {
      XCTAssertEqual(try punctuationDecision(source, "тоже", verified: true), .unchanged(.protectedToken), source)
    }
    XCTAssertEqual(try punctuationDecision("foo.bar", "тоже", verified: true, known: false), .unchanged(.protectedToken))
    XCTAssertEqual(try punctuationDecision("nj;t", "тоже", verified: true, excluded: ["тоже"]), .unchanged(.excludedWord))
  }
  private func punctuationDecision(_ source: String, _ target: String, verified: Bool,
    score: Int32 = -5, known: Bool = true, excluded: Set<String> = []) throws -> LinguisticDecision {
    let classifier = try PatternClassifier(patterns: [
      .init(text: "\u{2}" + target + "\u{3}", features: [.init(languagePair: "ru-en", weight: known ? 0 : 5, knownWord: known)]),
      .init(text: "\u{2}" + source.replacingOccurrences(of: "\t", with: "") + "\u{3}", features: [.init(languagePair: "ru-en", weight: score)])
    ], supportedLanguagePairs: ["ru-en"])
    let engine = PatternCorrectionEngine(classifier: classifier, autocorrector: try .init(rules: []))
    let word = BufferedWord(text: source, events: [], context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: en, delimiter: " ")
    return engine.decide(word: word, russianCandidate: target, russianLayout: ru,
      englishCandidate: source, englishLayout: en, preferences: .defaults, excludedWords: excluded,
      modelVersion: 1, physicalCandidatesVerified: verified)
  }
  func testSelectsHighestSignedScoreAndPreservesVersion() throws {
    let result = correction(decide(try make(-1, -2)))
    XCTAssertEqual(result?.replacement, "привет"); XCTAssertEqual(result?.targetLayout, ru)
    XCTAssertEqual(result?.kind, .layout); XCTAssertEqual(result?.modelVersion, 17)
  }
  func testTiePrefersRUAndAllZeroAbstains() throws {
    XCTAssertEqual(correction(decide(try make(2, 2)))?.targetLayout, ru)
    // A zero-weight feature is an assertion, so use a model with no matching features for scored zero.
    let empty = PatternCorrectionEngine(classifier: try .init(patterns: [], supportedLanguagePairs: ["ru-en"]),
      autocorrector: try .init(rules: []))
    XCTAssertEqual(decide(empty), .unchanged(.ambiguous))
  }
  func testSecondKnownWinsAndRejectedAlwaysBlocks() throws {
    XCTAssertEqual(correction(decide(try make(0, 0, ruKnown: true, enKnown: true), sourceRU: true))?.targetLayout, en)
    XCTAssertEqual(decide(try make(0, 5, ruKnown: true, reject: true)), .unchanged(.ambiguous))
  }
  func testExclusionsDisabledAndCorrectSource() throws {
    let engine = try make()
    XCTAssertEqual(decide(engine, excluded: ["GHBDTN"]), .unchanged(.excludedWord))
    XCTAssertEqual(decide(engine, excluded: ["Привет"]), .unchanged(.excludedWord))
    XCTAssertEqual(decide(engine, preferences: .init(autoEnabled: false)), .unchanged(.disabled))
    XCTAssertEqual(decide(engine, sourceRU: true), .unchanged(.correct))
  }
  func testSelectedCandidateAutocorrectAndKind() throws {
    let rule = PatternAutocorrectRule(pattern: "привет", rewrite: .init(prefixBytes: 0, suffixBytes: 0, insertion: "ответ"))
    let engine = try make(rules: [rule])
    XCTAssertEqual(correction(decide(engine))?.replacement, "ответ")
    XCTAssertEqual(correction(decide(engine))?.kind, .combined)
    XCTAssertEqual(correction(decide(engine, sourceRU: true))?.kind, .typo)
    XCTAssertEqual(decide(engine, excluded: ["Ответ"]), .unchanged(.excludedWord))
    XCTAssertEqual(correction(decide(engine, preferences: .init(typoEnabled: false, yoEnabled: false)))?.replacement, "привет")
  }
  func testYoKindAndToggleAreBasedOnAcceptedRuleCategory() throws {
    let rule = PatternAutocorrectRule(pattern: "привет", rewrite: .init(prefixBytes: 0, suffixBytes: 0, insertion: "ёлка"), isYofikator: true)
    let engine = try make(rules: [rule])
    XCTAssertEqual(correction(decide(engine, sourceRU: true))?.kind, .yo)
    XCTAssertEqual(decide(engine, sourceRU: true, preferences: .init(yoEnabled: false)), .unchanged(.correct))
  }
  func testProtectedSourceAndMismatchedCandidateCannotReachReplacement() throws {
    let engine = try make()
    for source in ["abc.com", "ghbdtn"] {
      let word = BufferedWord(text: source, events: [], context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: en, delimiter: " ")
      let result = engine.decide(word: word, russianCandidate: "привет", russianLayout: ru,
        englishCandidate: "different", englishLayout: en, preferences: .defaults, excludedWords: [], modelVersion: 1)
      XCTAssertEqual(result, .unchanged(source == "abc.com" ? .protectedToken : .unsupportedLayout))
    }
  }
  func testNativeWordSafetyRejectsWhitespaceOutput() throws {
    let rule = PatternAutocorrectRule(pattern: "привет", rewrite: .init(prefixBytes: 0, suffixBytes: 0, insertion: "а\tб"))
    XCTAssertEqual(decide(try make(rules: [rule])), .unchanged(.protectedToken))
  }
  func testRussianCandidateAllowsPunctuationInUnselectedPhysicalAlternative() throws {
    for (source, alternate, output) in [("еж", "t;", "ёж"), ("жизнь", ";bpym", "жизнь")] {
      let classifier = try PatternClassifier(patterns: [
        .init(text: source, features: [.init(languagePair: "ru-en", weight: 0, knownWord: true)])
      ], supportedLanguagePairs: ["ru-en"])
      let autocorrector = try PatternAutocorrector(rules: [
        .init(pattern: "еж", rewrite: .init(prefixBytes: 0, suffixBytes: 0, insertion: "ёж"), isYofikator: true)
      ])
      let engine = PatternCorrectionEngine(classifier: classifier, autocorrector: autocorrector)
      let word = BufferedWord(text: source, events: [], context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: ru, delimiter: " ")
      let result = engine.decide(word: word, russianCandidate: source, russianLayout: ru,
        englishCandidate: alternate, englishLayout: en, preferences: .defaults, excludedWords: [], modelVersion: 1)
      if output == source { XCTAssertEqual(result, .unchanged(.correct)) }
      else { XCTAssertEqual(correction(result)?.replacement, output) }
    }
  }
  func testUnsafeSelectedAlternativeStillCannotBecomeReplacement() throws {
    let classifier = try PatternClassifier(patterns: [
      .init(text: "t;", features: [.init(languagePair: "ru-en", weight: 0, knownWord: true)])
    ], supportedLanguagePairs: ["ru-en"])
    let engine = PatternCorrectionEngine(classifier: classifier, autocorrector: try .init(rules: []))
    let word = BufferedWord(text: "еж", events: [], context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: ru, delimiter: " ")
    for alternate in ["t;", "t\t", "t "] {
      XCTAssertEqual(engine.decide(word: word, russianCandidate: "еж", russianLayout: ru,
        englishCandidate: alternate, englishLayout: en, preferences: .defaults, excludedWords: [], modelVersion: 1), .unchanged(.protectedToken))
    }
  }

  func testSourceTypoRunsWhenLayoutClassifierAbstains() throws {
    let classifier = try PatternClassifier(patterns: [], supportedLanguagePairs: ["ru-en"])
    let autocorrector = try PatternAutocorrector(rules: [
      .init(pattern: "\u{2}првиет\u{3}", rewrite: .init(prefixBytes: 0, suffixBytes: 0, insertion: "привет"))
    ])
    let engine = PatternCorrectionEngine(classifier: classifier, autocorrector: autocorrector)
    for enabled in [true, false] {
      let word = BufferedWord(text: "првиет", events: [], context: .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1), layout: ru, delimiter: " ")
      let result = engine.decide(word: word, russianCandidate: "првиет", russianLayout: ru,
        englishCandidate: "ghdbtn", englishLayout: en, preferences: .init(typoEnabled: enabled), excludedWords: [], modelVersion: 1)
      if enabled {
        XCTAssertEqual(correction(result)?.replacement, "привет")
        XCTAssertEqual(correction(result)?.targetLayout, ru)
        XCTAssertEqual(correction(result)?.kind, .typo)
      } else { XCTAssertEqual(result, .unchanged(.ambiguous)) }
    }
  }

}
