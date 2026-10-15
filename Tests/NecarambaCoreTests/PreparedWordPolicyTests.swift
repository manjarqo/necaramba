import XCTest
@testable import NecarambaCore

final class PreparedWordPolicyTests: XCTestCase {
    func testCanonicalCaseInsensitiveMembershipMatchesExistingNormalization() {
        let excluded: Set<String> = ["HELLO", "Е\u{308}ЛКА", "Straße", "İ"]
        let protected: Set<String> = ["ПРИВЕТ", "CAFÉ"]
        let policy = PreparedWordPolicy(excluded: excluded, protected: protected)
        let legacy = Set(excluded.union(protected).map(TokenGuard.normalized))
        for word in ["hello", "Hello", "ёлка", "Е\u{308}лка", "STRASSE", "i", "İ", "привет", "cafe\u{301}", "other", ""] {
            XCTAssertEqual(policy.contains(word), legacy.contains(TokenGuard.normalized(word)), word)
        }
    }
    func testReplacementPolicyDoesNotMutateCapturedPolicy() {
        var excluded: Set<String> = ["hello"]
        let captured = PreparedWordPolicy(excluded: excluded, protected: [])
        excluded = ["world"]
        let next = PreparedWordPolicy(excluded: excluded, protected: [])
        XCTAssertTrue(captured.contains("HELLO"))
        XCTAssertFalse(captured.contains("world"))
        XCTAssertFalse(next.contains("hello"))
        XCTAssertTrue(next.contains("WORLD"))
    }
    func testOpenPreparedAndConveniencePathsMatchAtEveryCorrectionStage() throws {
        let fixture = OpenCorrectionEngineTests()
        let engine = OpenCorrectionEngine(lexicon: OpenCorrectionEngineTests.Lexicon(), rules: try fixture.rules())
        let context = ContextToken(pid: 1, bundleID: "fixture", focusEpoch: 1, layoutEpoch: 1)
        for (source, ru, en, layout) in [("рудддщ", "рудддщ", "helllo", "RU"), ("Helllo", "рудддщ", "Helllo", "US"), ("ежик", "ежик", "t;br", "RU"), ("ру", "ру", "he", "RU"), ("hello", "привет", "hello", "US")] {
            let word = BufferedWord(text: source, events: [], context: context, layout: .init(rawValue: layout), delimiter: " ")
            for excluded: Set<String> in [[], [source.uppercased()], [en.uppercased()], ["HELLO"], ["ЁЖИК"]] {
                let convenience = engine.decide(word: word, russianCandidate: ru, russianLayout: fixture.ru, englishCandidate: en, englishLayout: fixture.us, preferences: .defaults, excludedWords: excluded, modelVersion: 2)
                let prepared = engine.decide(word: word, russianCandidate: ru, russianLayout: fixture.ru, englishCandidate: en, englishLayout: fixture.us, preferences: .defaults, wordPolicy: PreparedWordPolicy(excluded: excluded, protected: []), modelVersion: 2)
                XCTAssertEqual(prepared, convenience, "\(source): \(excluded)")
            }
        }
    }
    func testLinguisticPreparedPathRetainsIntermediateAndFinalExclusions() {
        let snapshot = RuleSnapshot(modelVersion: 1,
            lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1), .init(word: "hi", language: .english, frequencyBand: 1)],
            typos: [.init(source: "привет", target: "hi", caseSensitive: false)],
            mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["g":"п", "h":"р", "b":"и", "d":"в", "t":"е", "n":"т"])])
        let engine = LinguisticEngine(snapshot: snapshot)
        let word = LinguisticEngineTests().word("ghbdtn")
        for excluded: Set<String> in [[], ["GHBDTN"], ["ПРИВЕТ"], ["HI"]] {
            XCTAssertEqual(engine.decide(word: word, preferences: .defaults, wordPolicy: .init(excluded: excluded, protected: [])),
                engine.decide(word: word, preferences: .defaults, excludedWords: excluded))
            if !excluded.isEmpty {
                XCTAssertEqual(engine.decide(word: word, preferences: .defaults, wordPolicy: .init(excluded: excluded, protected: [])), .unchanged(.excludedWord))
            }
        }
    }
    func testPatternPreparedPathRetainsIntermediateAndFinalExclusions() throws {
        let ru = LayoutID(rawValue: "RU"), en = LayoutID(rawValue: "US")
        let classifier = try PatternClassifier(patterns: [
            .init(text: "привет", features: [.init(languagePair: "ru-en", weight: 2)]),
            .init(text: "ghbdtn", features: [.init(languagePair: "ru-en", weight: 1)])
        ], supportedLanguagePairs: ["ru-en"])
        let engine = PatternCorrectionEngine(classifier: classifier,
            autocorrector: try .init(rules: [.init(pattern: "привет", rewrite: .init(prefixBytes: 0, suffixBytes: 0, insertion: "hi"))]))
        let word = LinguisticEngineTests().word("ghbdtn")
        for excluded: Set<String> in [[], ["GHBDTN"], ["ПРИВЕТ"], ["HI"]] {
            let prepared = engine.decide(word: word, russianCandidate: "привет", russianLayout: ru,
                englishCandidate: "ghbdtn", englishLayout: en, preferences: .defaults,
                wordPolicy: .init(excluded: excluded, protected: []), modelVersion: 1)
            XCTAssertEqual(prepared, engine.decide(word: word, russianCandidate: "привет", russianLayout: ru,
                englishCandidate: "ghbdtn", englishLayout: en, preferences: .defaults, excludedWords: excluded, modelVersion: 1))
            if !excluded.isEmpty { XCTAssertEqual(prepared, .unchanged(.excludedWord)) }
        }
    }

}
