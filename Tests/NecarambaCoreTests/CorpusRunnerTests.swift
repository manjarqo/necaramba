import XCTest
import CryptoKit
@testable import NecarambaCore
final class CorpusRunnerTests: XCTestCase {
    func testExactCorrectionsAndUndefinedDenominators() throws {
        let rows = (0..<199).map { CorpusCase(id: "p\($0)", input: "wrong\($0)", layout: LayoutID(rawValue: "US"), expected: "right\($0)", shouldChange: true, split: .holdout, sourceLicense: "CC0-1.0", category: "layout", family: "p\($0)") }
        let negative = CorpusCase(id: "negative", input: "correct", layout: LayoutID(rawValue: "US"), expected: "correct", shouldChange: false, split: .holdout, sourceLicense: "CC0-1.0", category: "plain", family: "negative")
        let missed = CorpusCase(id: "miss", input: "wrong", layout: LayoutID(rawValue: "US"), expected: "right", shouldChange: true, split: .holdout, sourceLicense: "CC0-1.0", category: "layout", family: "miss")
        let report = QualityEvaluator.evaluate(rows + [negative, missed]) { row in row.id == "negative" ? "changed" : row.id == "miss" ? row.input : row.expected }
        XCTAssertEqual(report.truePositive, 199)
        XCTAssertEqual(report.falsePositive, 1)
        XCTAssertEqual(report.falseNegative, 1)
        XCTAssertEqual(report.precision!, 0.995, accuracy: 0.00001)
        XCTAssertEqual(report.recall!, 0.995, accuracy: 0.00001)
        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.perCategory["doubleCaps"]?.total, 0)
        XCTAssertNil(QualityEvaluator.evaluate([negative]) { $0.input }.precision)
    }
    func testWrongReplacementIsFalsePositiveAndFalseNegative() {
        let row = CorpusCase(id: "x", input: "bad", layout: LayoutID(rawValue: "US"), expected: "good", shouldChange: true, split: .holdout, sourceLicense: "CC0-1.0", category: "layout", family: "x")
        let result = QualityEvaluator.evaluate([row]) { _ in "other" }
        XCTAssertEqual(result.falsePositive, 1); XCTAssertEqual(result.falseNegative, 1)
        XCTAssertEqual(result.mismatches.count, 1)
    }
    func testDeclaredFamilyCannotHideDuplicateNormalizedExpectedTokens() throws {
        let a = CorpusCase(id: "a", input: "HELLO", layout: LayoutID(rawValue: "US"), expected: "HELLO", shouldChange: false, split: .train, sourceLicense: "CC0-1.0", category: "plain", family: "a")
        let b = CorpusCase(id: "b", input: "hello", layout: LayoutID(rawValue: "US"), expected: "hello", shouldChange: false, split: .holdout, sourceLicense: "CC0-1.0", category: "plain", family: "b")
        XCTAssertThrowsError(try CorpusValidator.validate([a, b]))
    }
    func testManifestRejectsTraversalAndUnsupportedSchema() throws {
        XCTAssertThrowsError(try CorpusManifest.validateRelativePath("../escape"))
        XCTAssertThrowsError(try CorpusManifest.validateRelativePath("/absolute"))
        XCTAssertNoThrow(try CorpusManifest.validateRelativePath("Corpora/holdout.jsonl"))
        let json = Data("{\"schemaVersion\":99}".utf8)
        XCTAssertThrowsError(try CorpusManifest.decode(json))
    }
    func testManifestRejectsUnknownNestedFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Corpora/manifest.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rules = try XCTUnwrap(object["rules"] as? [String: Any]); rules["ignored"] = "bad"
        object["rules"] = rules
        XCTAssertThrowsError(try CorpusManifest.decode(JSONSerialization.data(withJSONObject: object)))
    }
    func testFrozenManifestVerifiesDigestsAndRegisteredLicenses() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Corpora/manifest.json"))
        let manifest = try CorpusManifest.decode(data)
        func read(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(path)) }
        func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        let rows = try manifest.validate(read: read, digest: digest)
        XCTAssertEqual(rows.count, 18010)
        XCTAssertEqual(rows.filter { $0.split == .holdout && !$0.shouldChange }.count, 3602)
        XCTAssertThrowsError(try manifest.validate(read: { path in path == manifest.rules.path ? Data("tampered".utf8) : try read(path) }, digest: digest))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var files = try XCTUnwrap(object["files"] as? [[String: Any]])
        let path = try XCTUnwrap(files[0]["path"] as? String)
        var lines = String(decoding: try read(path), as: UTF8.self).components(separatedBy: "\n")
        var first = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        first["sourceLicense"] = "unregistered"
        lines[0] = String(decoding: try JSONSerialization.data(withJSONObject: first), as: UTF8.self)
        let changed = Data(lines.joined(separator: "\n").utf8)
        files[0]["sha256"] = digest(changed); object["files"] = files
        let altered = try CorpusManifest.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try altered.validate(read: { requested in requested == path ? changed : try read(requested) }, digest: digest))
    }
    func testContradictoryLabelsForSameInputAndLayoutAreRejected() throws {
        let a = CorpusCase(id: "a", input: ",jhp", layout: LayoutID(rawValue: "US"), expected: "борз", shouldChange: true, split: .holdout, sourceLicense: "CC0-1.0", category: "layout", family: "борз")
        let b = CorpusCase(id: "b", input: ",jhp", layout: LayoutID(rawValue: "US"), expected: "Борз", shouldChange: true, split: .holdout, sourceLicense: "CC0-1.0", category: "layout", family: "борз")
        XCTAssertThrowsError(try CorpusValidator.validate([a, b]))
    }
    func testStrictJSONLAndFamilyLeakage() throws {
        let row = CorpusCase(id: "x", input: "café", layout: LayoutID(rawValue: "US"), expected: "café", shouldChange: false, split: .train, sourceLicense: "CC0-1.0", category: "plain", family: "CAFÉ")
        let second = CorpusCase(id: "y", input: "other", layout: LayoutID(rawValue: "US"), expected: "other", shouldChange: false, split: .holdout, sourceLicense: "CC0-1.0", category: "plain", family: "cafe\u{301}")
        XCTAssertThrowsError(try CorpusValidator.validate([row, second]))
        XCTAssertThrowsError(try CorpusValidator.validate([row, row]))
        XCTAssertThrowsError(try CorpusValidator.decodeJSONL(Data("{}\n".utf8)))
        XCTAssertThrowsError(try CorpusValidator.decodeJSONL(Data("\n".utf8)))
    }
}
