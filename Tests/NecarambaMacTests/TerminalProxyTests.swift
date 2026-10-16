import XCTest
import ApplicationServices
import NecarambaCore
@testable import NecarambaMac

final class TerminalProxyMetadataTests: XCTestCase {
  func testExactClassArrayIdentifiesOnlyKnownTerminalEditableProxy() {
    XCTAssertTrue(AXTerminalProxyMetadata.matches(bundleID: "org.tabby", role: "AXTextField",
      status: .success, classes: ["other", "xterm-helper-textarea"] as CFArray))
    XCTAssertTrue(AXTerminalProxyMetadata.matches(bundleID: "org.tabby", role: "AXTextArea",
      status: .success, classes: ["xterm-helper-textarea"] as CFArray))
    for bundle in ["com.vscodium", "test", "org.tabby.other"] {
      XCTAssertFalse(AXTerminalProxyMetadata.matches(bundleID: bundle, role: "AXTextField",
        status: .success, classes: ["xterm-helper-textarea"] as CFArray))
    }
    XCTAssertFalse(AXTerminalProxyMetadata.matches(bundleID: "org.tabby", role: "AXButton",
      status: .success, classes: ["xterm-helper-textarea"] as CFArray))
  }
  func testOrcaTerminalHelperQualifiesOnlyForExactBundle() {
    XCTAssertTrue(AXTerminalProxyMetadata.isHost("com.stablyai.orca"))
    XCTAssertTrue(AXTerminalProxyMetadata.matches(bundleID: "com.stablyai.orca", role: "AXTextField",
      status: .success, classes: ["xterm-helper-textarea"] as CFArray))
    XCTAssertFalse(AXTerminalProxyMetadata.matches(bundleID: "com.stablyai.orca", role: "AXTextField",
      status: .success, classes: ["min-w-0", "flex-1", "bg-transparent"] as CFArray),
      "Orca's ordinary text inputs are not terminal proxies")
    for bundle in ["com.stablyai.orca.helper", "other.com.stablyai.orca", "com.vscodium"] {
      XCTAssertFalse(AXTerminalProxyMetadata.isHost(bundle))
      XCTAssertFalse(AXTerminalProxyMetadata.matches(bundleID: bundle, role: "AXTextField",
        status: .success, classes: ["xterm-helper-textarea"] as CFArray))
    }
  }
  func testMissingMalformedMixedAndSubstringClassMetadataDoesNotQualify() {
    let values: [CFTypeRef?] = [nil, "xterm-helper-textarea" as CFString,
      ["not-xterm-helper-textarea"] as CFArray, [] as CFArray,
      ["xterm-helper-textarea", 42] as CFArray]
    for value in values {
      XCTAssertFalse(AXTerminalProxyMetadata.matches(bundleID: "org.tabby", role: "AXTextField",
        status: .success, classes: value))
    }
    for status: AXError in [.cannotComplete, .failure, .noValue, .attributeUnsupported] {
      XCTAssertFalse(AXTerminalProxyMetadata.matches(bundleID: "org.tabby", role: "AXTextField",
        status: status, classes: ["xterm-helper-textarea"] as CFArray))
    }
  }
  func testOnlyCollapsedBoundedRangeWithAuthorizedDirectLayoutQualifies() {
    XCTAssertTrue(AXTerminalProxyMetadata.permits(rangeStatus: .success,
      range: CFRange(location: 9, length: 0), directLayout: true, authorized: true))
    for range in [CFRange(location: 0, length: 1), CFRange(location: -1, length: 0),
      CFRange(location: 0, length: -1), CFRange(location: 1_048_577, length: 0)] {
      XCTAssertFalse(AXTerminalProxyMetadata.permits(rangeStatus: .success,
        range: range, directLayout: true, authorized: true))
    }
    XCTAssertFalse(AXTerminalProxyMetadata.permits(rangeStatus: .noValue,
      range: nil, directLayout: true, authorized: true))
    XCTAssertFalse(AXTerminalProxyMetadata.permits(rangeStatus: .success,
      range: CFRange(location: 0, length: 0), directLayout: false, authorized: true))
    XCTAssertFalse(AXTerminalProxyMetadata.permits(rangeStatus: .success,
      range: CFRange(location: 0, length: 0), directLayout: true, authorized: false))
  }
}

@MainActor final class TerminalProxyDispatchTests: XCTestCase {
  func testEmptyThenNonemptyProxyResidueKeepsPhysicalAutoDispatchUnverified() async {
    let state = ContextState()
    let layout = LayoutID(rawValue: "US")
    state.update(pid: 42, bundleID: "org.tabby", focusID: "terminal", layout: layout, qualified: true)
    let token = state.current()!
    let reader = TerminalProxyReader()
    let adapter = AXSelectionAdapter(context: state, qualifies: { _, _ in true }, reader: reader,
      allowAutomaticBoundary: { true })
    adapter.inputGeneration = { 1 }
    let events = "word".map { InputEvent(kind: .down, keyCode: 0, modifiers: [], timestampNanos: 1,
      layout: layout, context: token, origin: .physical, text: String($0), isRepeat: false) }
    let word = BufferedWord(text: "word", events: events, context: token, layout: layout, delimiter: " ")
    let boundary = InputEvent(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 2,
      layout: layout, context: token, origin: .physical, text: " ", isRepeat: false)
    let candidate = AutomaticBoundaryCandidate(word: word, boundary: boundary, inputGeneration: 1)
    XCTAssertTrue(adapter.canReplaceAutomaticBoundary(candidate, with: "WORD "))
    reader.value = "d "
    reader.range = CFRange(location: 2, length: 0)
    var posts = 0
    adapter.executePhysicalAsync = { mutation, _, valid in
      XCTAssertTrue(valid())
      XCTAssertEqual(mutation.deleteCount, 5)
      reader.value = "residue"
      reader.range = CFRange(location: 7, length: 0)
      XCTAssertTrue(valid())
      posts += 1
      return .committed
    }
    let result = await adapter.replaceAutomaticBoundaryAsync(candidate, with: "WORD ")
    XCTAssertEqual(result, .dispatched)
    XCTAssertEqual(posts, 1)
    XCTAssertNil(adapter.selected(in: token))
    reader.range = CFRange(location: 0, length: 3)
    XCTAssertFalse(adapter.canReplaceAutomaticBoundary(candidate, with: "WORD "))
    XCTAssertNil(adapter.selected(in: token), "Helper selection is not terminal text selection")
  }
}

private final class TerminalProxyReader: AXSelectionReading {
  let identity = UUID()
  var value = ""
  var range = CFRange(location: 0, length: 0)
  func read(in token: ContextToken) -> AXTextSnapshot? {
    guard case .snapshot(let snapshot) = observe(in: token, deadline: .greatestFiniteMagnitude)
    else { return nil }
    return snapshot
  }
  func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    guard AXTerminalProxyMetadata.matches(bundleID: token.bundleID, role: "AXTextField",
      status: .success, classes: ["xterm-helper-textarea"] as CFArray),
      AXTerminalProxyMetadata.permits(rangeStatus: .success, range: range,
        directLayout: true, authorized: true) else { return .rejected }
    return .opaque(.init(context: token, identity: identity, selection: .collapsed))
  }
}
