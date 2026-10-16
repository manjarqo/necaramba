import XCTest
import CryptoKit
import NecarambaCore
@testable import NecarambaMac

final class OpenModelLoaderTests: XCTestCase {
  private func fixture(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let files: [String: Data] = ["en.words": Data("ground\nhello\n".utf8),
      "ru.words": Data("привет\nтоже\n".utf8),
      "corrections.json": Data(#"{"schemaVersion":1,"version":"open-2","typos":[],"yo":[],"protectedWords":[]}"#.utf8)]
    var entries: [String: Any] = [:]
    for (name, data) in files {
      try data.write(to: dir.appendingPathComponent(name))
      entries[name] = ["sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "bytes": data.count]
    }
    try JSONSerialization.data(withJSONObject: ["schemaVersion":1,"version":"open-2","files":entries])
      .write(to: dir.appendingPathComponent("manifest.json"))
    try body(dir)
  }
  func testLoadsVerifiedOpenBundle() throws {
    try fixture { dir in
      let model = try OpenModelLoader.load(directory: dir)
      XCTAssertEqual(model.version, "open-2")
    }
  }
  func testShippedOpenModelConvertsPhysicalYoKeyAndContractions() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let model = try OpenModelLoader.load(directory: root.appendingPathComponent("Resources/OpenModel", isDirectory: true))
    let context = ContextToken(pid: 1, bundleID: "fixture", focusEpoch: 1, layoutEpoch: 1)
    let us = LayoutID(rawValue: "US"), ru = LayoutID(rawValue: "RU")
    func decide(_ text: String, _ layout: LayoutID, russian: String, english: String,
                _ preferences: PreferencesSnapshot) -> String {
      let events = text.map { InputEvent(kind: .down, keyCode: 0, modifiers: $0.isUppercase ? [.shift] : [],
        timestampNanos: 1, layout: layout, context: context, origin: .physical, text: String($0), isRepeat: false) }
      let decision = model.engine.decide(word: .init(text: text, events: events, context: context, layout: layout, delimiter: " "),
        russianCandidate: russian, russianLayout: ru, englishCandidate: english, englishLayout: us,
        preferences: preferences, excludedWords: [], modelVersion: 3, physicalCandidatesVerified: true)
      if case .replace(let correction) = decision { return correction.replacement }
      return "unchanged:\(decision)"
    }
    for preferences in [PreferencesSnapshot.defaults, .init(typoEnabled: true, yoEnabled: true)] {
      XCTAssertEqual(decide("dc\\", us, russian: "всё", english: "dc\\", preferences), "всё")
      XCTAssertEqual(decide("dct", us, russian: "все", english: "dct", preferences), "все")
      XCTAssertEqual(decide("to\\", us, russian: "ещё", english: "to\\", preferences), "ещё")
      XCTAssertEqual(decide("вщтэе", ru, russian: "вщтэе", english: "don't", preferences), "don't")
    }
  }
  func testRejectsTamperedMissingOrLinkedData() throws {
    for variant in 0..<3 {
      try fixture { dir in
        let file = dir.appendingPathComponent("en.words")
        if variant == 0 { try Data("changed\n".utf8).write(to: file) }
        else {
          try FileManager.default.removeItem(at: file)
          if variant == 2 { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: dir.appendingPathComponent("ru.words")) }
        }
        XCTAssertThrowsError(try OpenModelLoader.load(directory: dir))
      }
    }
  }
  func testRejectsAggregateBudgetBeforeOpeningPayloads() throws {
    try fixture { dir in
      let url = dir.appendingPathComponent("manifest.json")
      var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
      var files = manifest["files"] as! [String: [String: Any]]
      files["en.words"]!["bytes"] = 63 * 1024 * 1024
      files["ru.words"]!["bytes"] = 63 * 1024 * 1024
      manifest["files"] = files
      try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("manifest.json"))
      do { _ = try OpenModelLoader.load(directory: dir); XCTFail("Expected aggregate budget rejection") }
      catch OpenModelLoader.LoadingError.resourceLimit { }
      catch { XCTFail("Must reject before reading payload: \(error)") }
    }
  }
  func testRejectsUnexpectedManifestFilesAndVersion() throws {
    try fixture { dir in
      let url = dir.appendingPathComponent("manifest.json")
      var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
      manifest["version"] = "different"
      try JSONSerialization.data(withJSONObject: manifest).write(to: url)
      XCTAssertThrowsError(try OpenModelLoader.load(directory: dir))
    }
  }
}
