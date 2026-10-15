import XCTest
@testable import NecarambaCore

final class OpenCorrectionEngineTests: XCTestCase {
    struct Lexicon: OpenWordLookup {
        let en: Set<String> = ["ground", "connector", "hello", "he"]
        let ru: Set<String> = ["женский", "бывало", "елка", "ёлка", "ежик", "не", "тоже", "переключилось", "периодически", "ёжик", "привет"]
        func contains(_ word: String, language: Language) -> Bool {
            (language == .english ? en : ru).contains(word.lowercased())
        }
    }
    let us = LayoutID(rawValue: "US"), ru = LayoutID(rawValue: "RU")
    func rules(_ value: String = "") throws -> OpenCorrectionRules {
        try OpenCorrectionRules(data: Data((value.isEmpty ? #"{"schemaVersion":1,"version":"open-2","typos":[{"source":"helllo","target":"hello"}],"yo":[{"source":"ежик","target":"ёжик"}],"protectedWords":["ру"]}"# : value).utf8))
    }
    func decide(_ source: String, russian: String, english: String, layout: String = "US", verified: Bool = true, physical: Bool = true, preferences: PreferencesSnapshot = .defaults, excluded: Set<String> = [], customRules: OpenCorrectionRules? = nil) throws -> LinguisticDecision {
        let context = ContextToken(pid: 1, bundleID: "fixture", focusEpoch: 1, layoutEpoch: 1)
        let id = LayoutID(rawValue: layout)
        let events = source.map { InputEvent(kind: .down, keyCode: 0, modifiers: $0.isUppercase || ":<>{}\"~".contains($0) ? [.shift] : [], timestampNanos: 1, layout: id, context: context, origin: physical ? .physical : .foreignSynthetic, text: String($0), isRepeat: false) }
        return OpenCorrectionEngine(lexicon: Lexicon(), rules: try customRules ?? rules()).decide(word: .init(text: source, events: events, context: context, layout: id, delimiter: " "), russianCandidate: russian, russianLayout: ru, englishCandidate: english, englishLayout: us, preferences: preferences, excludedWords: excluded, modelVersion: 2, physicalCandidatesVerified: verified)
    }
    func output(_ decision: LinguisticDecision, source: String) -> String {
        if case .replace(let correction) = decision { return correction.replacement }; return source
    }
    func testUserRegressionsAndKnownSourceRetention() throws {
        for (wrong, correct) in [("пкщгтв", "ground"), ("сщттусещк", "connector")] {
            XCTAssertEqual(output(try decide(wrong, russian: wrong, english: correct, layout: "RU"), source: wrong), correct)
            XCTAssertEqual(output(try decide(correct, russian: wrong, english: correct), source: correct), correct)
        }
        for (wrong, correct) in [("yt", "не"), ("nj;t", "тоже"), ("gthtrk.xbkjcm", "переключилось"), ("gthbjlbxtcrb", "периодически")] {
            XCTAssertEqual(output(try decide(wrong, russian: correct, english: wrong), source: wrong), correct)
            XCTAssertEqual(output(try decide(correct, russian: correct, english: wrong, layout: "RU"), source: correct), correct)
        }
    }
    func testPunctuationRequiresPhysicalProvenanceAndSafeSource() throws {
        for source in ["1ю3ю166", "1.3.166", "foo.com", "foo.bar.baz", "foo/bar", "foo(bar)", "foo@bar", "API", "nJ;t", "abЖ"] {
            XCTAssertEqual(output(try decide(source, russian: "тоже", english: source), source: source), source)
        }
        for proof in [(false, true), (true, false)] {
            XCTAssertEqual(output(try decide("nj;t", russian: "тоже", english: "nj;t", verified: proof.0, physical: proof.1), source: "nj;t"), "nj;t")
        }
    }
    func testAmbiguityPreferencesAndExclusions() throws {
        XCTAssertEqual(output(try decide("ру", russian: "ру", english: "he", layout: "RU"), source: "ру"), "ру")
        XCTAssertEqual(output(try decide("hello", russian: "привет", english: "hello"), source: "hello"), "hello")
        XCTAssertEqual(output(try decide("unknown", russian: "неизвестно", english: "unknown"), source: "unknown"), "unknown")
        XCTAssertEqual(try decide("nj;t", russian: "тоже", english: "nj;t", excluded: ["тоже"]), .unchanged(.excludedWord))
        XCTAssertEqual(try decide("nj;t", russian: "тоже", english: "nj;t", preferences: .init(autoEnabled: false)), .unchanged(.disabled))
    }
    func testExactTypoYoAndCase() throws {
        XCTAssertEqual(output(try decide("Helllo", russian: "рудддщ", english: "Helllo"), source: "Helllo"), "Hello")
        XCTAssertEqual(output(try decide("Helllo", russian: "рудддщ", english: "Helllo", preferences: .init(typoEnabled: false)), source: "Helllo"), "Helllo")
        XCTAssertEqual(output(try decide("ежик", russian: "ежик", english: "t;br", layout: "RU", preferences: .init(yoEnabled: true)), source: "ежик"), "ёжик")
        XCTAssertEqual(output(try decide("ежик", russian: "ежик", english: "t;br", layout: "RU", preferences: .init(yoEnabled: false)), source: "ежик"), "ежик")
        XCTAssertEqual(output(try decide("HEllo", russian: "руддщ", english: "HEllo"), source: "HEllo"), "Hello")
    }
    func testLeadingShiftedPunctuationAndEmbeddedColonGuard() throws {
        for (source, target) in [(":tycrbq", "Женский"), ("<sdfkj", "Бывало")] {
            XCTAssertEqual(output(try decide(source, russian: target, english: source), source: source), target)
        }
        for source in ["foo:bar", "a<b", "::tycrbq", ":TYCRBQ", ":a.b"] {
            XCTAssertEqual(output(try decide(source, russian: "Женский", english: source), source: source), source)
        }
    }
    func testExactAlternativeRepairAndAmbiguity() throws {
        let decision = try decide("рудддщ", russian: "рудддщ", english: "helllo", layout: "RU")
        XCTAssertEqual(output(decision, source: "рудддщ"), "hello")
        if case .replace(let correction) = decision { XCTAssertEqual(correction.kind, .combined) } else { XCTFail("Expected combined correction") }
        XCTAssertEqual(try decide("рудддщ", russian: "рудддщ", english: "helllo", layout: "RU", excluded: ["helllo"]), .unchanged(.excludedWord))
        let competing = try rules(#"{"schemaVersion":1,"version":"x","typos":[{"source":"helllo","target":"hello"},{"source":"рудддщ","target":"привет"}],"yo":[],"protectedWords":[]}"#)
        XCTAssertEqual(output(try decide("рудддщ", russian: "рудддщ", english: "helllo", layout: "RU", customRules: competing), source: "рудддщ"), "рудддщ")
    }
    func testIntermediateTypoYoExclusionAndProtection() throws {
        let payload = #"{"schemaVersion":1,"version":"x","typos":[{"source":"еллка","target":"елка"}],"yo":[{"source":"елка","target":"ёлка"}],"protectedWords":[]}"#
        XCTAssertEqual(try decide("еллка", russian: "еллка", english: "tkkuf", layout: "RU", preferences: .init(yoEnabled: true), excluded: ["елка"], customRules: try rules(payload)), .unchanged(.excludedWord))
        let protected = payload.replacingOccurrences(of: #""protectedWords":[]"#, with: #""protectedWords":["елка"]"#)
        XCTAssertEqual(try decide("еллка", russian: "еллка", english: "tkkuf", layout: "RU", preferences: .init(yoEnabled: true), customRules: try rules(protected)), .unchanged(.protectedToken))
    }
    func testRulesRejectDuplicatesConflictsAndUnknownSchema() throws {
        for payload in [
            #"{"schemaVersion":9,"version":"x","typos":[],"yo":[],"protectedWords":[]}"#,
            #"{"schemaVersion":1,"version":"x","typos":[{"source":"helllo","target":"hello"},{"source":"helllo","target":"hello"}],"yo":[],"protectedWords":[]}"#,
            #"{"schemaVersion":1,"version":"x","typos":[],"yo":[{"source":"ежик","target":"привет"}],"protectedWords":[]}"#
        ] { XCTAssertThrowsError(try rules(payload)) }
    }
}
