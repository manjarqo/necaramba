import XCTest
import NecarambaCore
@testable import NecarambaMac

final class LocalPatternModelLoaderTests: XCTestCase {
  private func fixture() -> [String: Any] {
    ["version": "synthetic-1", "kbm": [
      "languages": ["0": "ru-en"],
      "graph_records": [["key": "\u{02}hello\u{03}", "value": 0]],
      "index": ["0": [["lang": 0, "weight": 0, "is_known_word": true, "is_case_sensitive": false]]]
    ], "autocorrect": [
      "graph_records": [["key": "\u{02}teh\u{03}", "value": 0]],
      "rules": [["prefix_len": 0, "suffix_len": 0, "insert_id": 0]],
      "insert_pool": ["the"]
    ]]
  }
  private func withFile(_ object: [String: Any], body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("model.json")
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    try body(url)
  }
  func testLoadsIndependentSyntheticClassifierAndAutocorrector() throws {
    try withFile(fixture()) { url in
      let model = try LocalPatternModelLoader.load(url: url)
      XCTAssertEqual(model.version, "synthetic-1")
      XCTAssertEqual(model.classifier.classify("hello", languagePair: "ru-en").status, .known)
      XCTAssertEqual(model.autocorrector.correct("teh", forceComplete: true).replacement, "the")
    }
  }
  func testRejectsMissingReferencesAndMalformedLanguageIDs() throws {
    for variant in 0..<7 {
      var object = fixture()
      var kbm = object["kbm"] as! [String: Any]
      var auto = object["autocorrect"] as! [String: Any]
      switch variant {
      case 0: kbm["index"] = [:] as [String: Any]
      case 1: kbm["languages"] = ["1": "ru-en"]
      case 2: kbm["languages"] = ["0": "ru-ru"]
      case 3: kbm["languages"] = ["00": "ru-en"]
      case 4: auto["graph_records"] = [["key": "teh", "value": 5]]
      case 5: auto["insert_pool"] = [] as [String]
      default: auto["rules"] = [["prefix_len": -1, "suffix_len": 0, "insert_id": 0]]
      }
      object["kbm"] = kbm; object["autocorrect"] = auto
      try withFile(object) { XCTAssertThrowsError(try LocalPatternModelLoader.load(url: $0), "variant \(variant)") }
    }
  }
  func testRejectsDuplicateGraphKeysInEitherTable() throws {
    for table in ["kbm", "autocorrect"] {
      var object = fixture()
      var section = object[table] as! [String: Any]
      let records = section["graph_records"] as! [[String: Any]]
      section["graph_records"] = records + records
      object[table] = section
      try withFile(object) { XCTAssertThrowsError(try LocalPatternModelLoader.load(url: $0)) }
    }
  }
  func testRejectsMalformedMissingAndNonregularFiles() throws {
    try withFile(fixture()) { url in
      try Data("{".utf8).write(to: url)
      XCTAssertThrowsError(try LocalPatternModelLoader.load(url: url))
      XCTAssertThrowsError(try LocalPatternModelLoader.load(url: url.deletingLastPathComponent()))
      let link = url.appendingPathExtension("link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
      XCTAssertThrowsError(try LocalPatternModelLoader.load(url: link))
      XCTAssertThrowsError(try LocalPatternModelLoader.load(url: url.appendingPathExtension("missing")))
    }
  }
  func testExplicitLocalModelCompilation() throws {
    guard let path = ProcessInfo.processInfo.environment["NECARAMBA_TEST_LOCAL_MODEL"] else {
      throw XCTSkip("Only runs with an explicitly supplied local model; fixtures remain synthetic")
    }
    let model = try LocalPatternModelLoader.load(url: URL(fileURLWithPath: path))
    XCTAssertFalse(model.version.isEmpty)
    XCTAssertNotEqual(model.classifier.classify("hello", languagePair: "ru-en").status, .unsupported)
    XCTAssertNotEqual(model.autocorrector.correct("hello").status, .unsupported)
  }

  func testRejectsOversizeFileBeforeDecoding() throws {
    try withFile(fixture()) { url in
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
      XCTAssertThrowsError(try LocalPatternModelLoader.load(url: url))
    }
  }
}
