import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class ConservativeAutomaticTests: XCTestCase {
  func testFirstAndNextWordCorrectBothDirectionsInReadableAndProxyFields() async {
    for proxy in [false, true] {
      let fixture = await fixture(proxy: proxy)
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "привет ")
      XCTAssertEqual(fixture.layouts.value.rawValue, "RU")
      feed("руддщ ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "привет hello ")
      XCTAssertEqual(fixture.layouts.value.rawValue, "US")
      XCTAssertEqual(fixture.editor.results, [proxy ? .dispatched : .committed, proxy ? .dispatched : .committed])
      XCTAssertTrue(fixture.controller.automaticReady)
    }
  }
  func testCorrectProtectedDisabledExcludedAndDeniedWordsStayUntouched() async {
    for word in ["hello ", "lf ", "url/ghbdtn ", "foo/ghbdtn ", "foo.ghbdtn ", "foo@ghbdtn ", "a@ghbdtn ", "foo2ghbdtn "] {
      let fixture = await fixture()
      feed(word, fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, word)
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
    for policy in 0..<3 {
      let fixture = await fixture()
      if policy == 0 { fixture.controller.updatePreferences(.init(autoEnabled: false)) }
      if policy == 1 { fixture.controller.updateWordPolicies(["ghbdtn"]) }
      if policy == 2 { fixture.controller.updateAppPolicies(["test": .deny]) }
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "ghbdtn ")
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
  }
  func testEnterAndNewInputAfterSpaceCannotEditEarlierWord() async {
    for suffix in ["\n", "\t", " g"] {
      let fixture = await fixture(proxy: true)
      feed("ghbdtn" + suffix, fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "ghbdtn" + suffix)
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
  }
  func testAutomaticModeIsNotReadyWithoutCapturedLayoutsOrLexicon() async {
    let fixture = await fixture(install: false)
    XCTAssertFalse(fixture.controller.automaticReady)
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "ghbdtn ")
  }
  func testAutomaticProxyResultCanBeReversedByExplicitManualCommand() async {
    let fixture = await fixture(proxy: true)
    var commits = 0
    fixture.controller.onCommitted = { _, _ in commits += 1 }
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
    XCTAssertEqual(commits, 0)
    let asyncResult1 = await fixture.controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult1, .dispatched)
    XCTAssertEqual(fixture.editor.text, "ghbdtn ")
  }
  func testSparkAutomaticNBSPHasExactUndoAndPreservesBoundary() async {
    let fixture = await fixture()
    fixture.context.token = .init(pid: 42, bundleID: "com.readdle.SparkDesktop", focusEpoch: 1, layoutEpoch: 1)
    fixture.editor.normalizesSpace = true
    feed("ghbdtn ", fixture)
    await drain(delay: 0.15)
    XCTAssertEqual(fixture.editor.text, "привет\u{00a0}")
    let asyncResult2 = await fixture.controller.undoLastAsync()
    XCTAssertEqual(asyncResult2, .committed)
    XCTAssertEqual(fixture.editor.text, "ghbdtn\u{00a0}")
    XCTAssertEqual(fixture.layouts.value.rawValue, "US")
  }

  func testSparkAutomaticWithoutPostCommitProofDoesNotCreateUndo() async {
    let fixture = await fixture()
    fixture.context.token = .init(pid: 42, bundleID: "com.readdle.SparkDesktop", focusEpoch: 1, layoutEpoch: 1)
    fixture.editor.hidesSuffix = true
    feed("ghbdtn ", fixture)
    await drain(delay: 0.15)
    XCTAssertEqual(fixture.editor.text, "привет ")
    fixture.editor.hidesSuffix = false
    let asyncResult3 = await fixture.controller.undoLastAsync()
    XCTAssertEqual(asyncResult3, .aborted)
    XCTAssertEqual(fixture.editor.text, "привет ")
  }

  func testSparkPostCommitInputRaceDoesNotCreateUndo() async {
    let fixture = await fixture()
    fixture.context.token = .init(pid: 42, bundleID: "com.readdle.SparkDesktop", focusEpoch: 1, layoutEpoch: 1)
    fixture.editor.onSuffix = { fixture.controller.runtime.invalidateContext(reason: .unknownInput) }
    feed("ghbdtn ", fixture)
    await drain(delay: 0.15)
    fixture.editor.onSuffix = nil
    let asyncResult4 = await fixture.controller.undoLastAsync()
    XCTAssertEqual(asyncResult4, .aborted)
    XCTAssertEqual(fixture.editor.text, "привет ")
  }

  func testReadinessCallbackFollowsLoadedLexiconAndActualLayouts() async {
    let fixture = await fixture(install: false)
    var readiness: [Bool] = []
    fixture.controller.onAutomaticReadinessChanged = { readiness.append($0) }
    let installed = expectation(description: "readiness changed")
    fixture.controller.install(.init(modelVersion: 2, lexicon: [
      .init(word: "привет", language: .russian, frequencyBand: 1)])) { _ in installed.fulfill() }
    await fulfillment(of: [installed], timeout: 2)
    XCTAssertEqual(readiness, [true])
    XCTAssertTrue(fixture.controller.automaticReady)
  }
  func testForeignPasteCannotTurnFollowingURLSuffixIntoStandaloneWord() async {
    let fixture = await fixture(proxy: true)
    feed("url/", fixture)
    fixture.controller.runtime.accept(.init(kind: .down, keyCode: 9, modifiers: [.command],
      timestampNanos: 100, layout: fixture.layouts.value, context: fixture.context.token,
      origin: .foreignSynthetic, text: nil, isRepeat: false))
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn ")
    XCTAssertTrue(fixture.editor.results.isEmpty)
  }
  func testPhysicalTablesCorrectBothDirectionsDespiteStaleTapUnicode() async {
    let fixture = await fixture(proxy: true)
    feed("ghbdtn ", fixture, staleUnicode: true)
    await drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
    feed("руддщ ", fixture, staleUnicode: true)
    await drain()
    XCTAssertEqual(fixture.editor.text, "привет hello ")
  }
  func testNavigationDropsUntrustedPrefixUntilNextSpaceThenAllowsFreshWord() async {
    let fixture = await fixture(proxy: true)
    feed("url/", fixture)
    fixture.controller.runtime.invalidateContext(reason: .mouseNavigation)
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn ")
    XCTAssertEqual(fixture.layouts.value.rawValue, "US")
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn привет ")
  }
  func testAbortedAutomaticReplacementRestoresSourceLayout() async {
    for proxy in [false, true] {
      let fixture = await fixture(proxy: proxy)
      fixture.editor.abortsReplacement = true
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.results, [.aborted])
      XCTAssertEqual(fixture.editor.text, "ghbdtn ")
      XCTAssertEqual(fixture.layouts.value.rawValue, "US", "Unchanged text must keep the typing layout")
      fixture.editor.abortsReplacement = false
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "ghbdtn привет ")
      XCTAssertEqual(fixture.layouts.value.rawValue, "RU")
    }
  }
  func testReadableUntrustedURLSuffixDoesNotChangeLayoutBeforeRejectingWordStart() async {
    let fixture = await fixture(proxy: false)
    feed("url/", fixture)
    fixture.controller.runtime.invalidateContext(reason: .mouseNavigation)
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn ")
    XCTAssertEqual(fixture.layouts.value.rawValue, "US")
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn привет ")
  }
  func testStartupPublishingUnchangedEmptyPoliciesDoesNotDiscardFirstWord() async {
    let fixture = await fixture()
    fixture.controller.updateWordPolicies([])
    fixture.controller.updateAppPolicies([:])
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
  }
  func testManualCorrectionWithoutSpaceDoesNotExposeAppendedSuffixToAutomaticCorrection() async {
    let fixture = await fixture(proxy: true)
    feed("ghbdtn", fixture)
    let asyncResult5 = await fixture.controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult5, .dispatched)
    XCTAssertEqual(fixture.editor.text, "привет")
    feed("руддщ ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "приветруддщ ")
    XCTAssertEqual(fixture.layouts.value.rawValue, "RU")
    XCTAssertTrue(fixture.editor.results.isEmpty)
    feed("руддщ ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "приветруддщ hello ")
  }
  func testFirstWordAfterPlainReturnNeedsNoLeadingSpaceEvenInProxy() async {
    for proxy in [false, true] {
      let fixture = await fixture(proxy: proxy)
      feed("hello\n", fixture)
      await drain()
      XCTAssertTrue(fixture.editor.results.isEmpty)
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "hello\nпривет ")
    }
  }

  func testFirstReadableWordAfterFocusInvalidationNeedsNoLeadingSpace() async {
    let fixture = await fixture()
    fixture.controller.runtime.invalidateContext(reason: .mouseNavigation)
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
  }

  func testFirstOpaqueWordAfterEmptyCaptureResetNeedsNoLeadingSpace() async {
    for reason: InvalidationReason in [.mouseNavigation, .focusChanged, .unknownInput] {
      let fixture = await fixture(proxy: true)
      fixture.controller.runtime.invalidateContext(reason: reason)
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "привет ", reason.rawValue)
      XCTAssertEqual(fixture.editor.results, [.dispatched])
    }
  }

  func testMouseResetCannotForgetForeignPastePrefix() async {
    let fixture = await fixture(proxy: true)
    fixture.controller.runtime.accept(.init(kind: .down, keyCode: 9, modifiers: [.command],
      timestampNanos: 100, layout: fixture.layouts.value, context: fixture.context.token,
      origin: .foreignSynthetic, text: nil, isRepeat: false))
    fixture.editor.text = "url/"
    fixture.controller.runtime.invalidateContext(reason: .mouseNavigation)
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn ")
    XCTAssertTrue(fixture.editor.results.isEmpty)
  }

  func testApplicationShortcutDoesNotBlockFirstWordInNewFocus() async {
    let fixture = await fixture(proxy: true)
    fixture.controller.runtime.accept(.init(kind: .down, keyCode: 48, modifiers: [.command],
      timestampNanos: 100, layout: fixture.layouts.value, context: fixture.context.token,
      origin: .physical, text: "\t", isRepeat: false))
    fixture.controller.runtime.invalidateContext(reason: .focusChanged)
    fixture.context.token = .init(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
    feed("ghbdtn ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
    XCTAssertEqual(fixture.editor.results, [.dispatched])
  }

  func testKnownPrefixInNewFocusIsNotMistakenForFreshCapture() async {
    for manual in [false, true] {
      let fixture = await fixture(proxy: true)
      feed(" ", fixture)
      fixture.controller.runtime.invalidateContext(reason: .focusChanged)
      fixture.context.token = .init(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
      if manual {
        let original = BufferedWord(text: "prefix", events: [], context: fixture.context.token,
          layout: fixture.layouts.value, delimiter: "")
        let candidate = ManualRepeatCandidate(original: original, currentText: "prefix",
          context: fixture.context.token, layout: fixture.layouts.value, delimiter: "", fieldIdentity: UUID())
        XCTAssertTrue(fixture.controller.runtime.retainManualResult(candidate,
          expectedGeneration: fixture.controller.runtime.inputGeneration()))
      } else {
        fixture.controller.runtime.accept(.init(kind: .down, keyCode: 9, modifiers: [.command, .shift],
          timestampNanos: 100, layout: fixture.layouts.value, context: fixture.context.token,
          origin: .physical, text: nil, isRepeat: false))
      }
      fixture.editor.text = "prefix"
      feed("ghbdtn ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, "prefixghbdtn ")
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
  }

  func testLocalModelWithoutFallbackLexiconCorrectsShortWordsAndSurvivesSnapshotInstall() async throws {
    let fixture = await fixture(install: false)
    try await installLocal(fixture)
    XCTAssertTrue(fixture.controller.automaticReady)
    feed("lf ", fixture, staleUnicode: true)
    await drain()
    XCTAssertEqual(fixture.editor.text, "да ")
    let installed = expectation(description: "empty signed snapshot")
    fixture.controller.install(.init(modelVersion: 5)) { _ in installed.fulfill() }
    await fulfillment(of: [installed], timeout: 3)
    XCTAssertTrue(fixture.controller.automaticReady)
    feed("руддщ ", fixture)
    await drain()
    XCTAssertEqual(fixture.editor.text, "да hello ")
  }
  func testLocalModelUsesTypoPreferenceAndStatistics() async throws {
    for enabled in [true, false] {
      let fixture = await fixture()
      try await installLocal(fixture)
      fixture.controller.updatePreferences(.init(typoEnabled: enabled))
      var kinds: [CounterKind] = []
      fixture.controller.onCommitted = { _, kind in kinds.append(kind) }
      feed("teh ", fixture)
      await drain()
      XCTAssertEqual(fixture.editor.text, enabled ? "the " : "teh ")
      XCTAssertEqual(kinds, enabled ? [.typo] : [])
    }
  }
  func testLocalModelStillRespectsSignedProtectedTokens() async throws {
    let fixture = await fixture(install: false)
    try await installLocal(fixture)
    let installed = expectation(description: "protected token policy")
    fixture.controller.install(.init(modelVersion: 9, protectedTokens: ["teh"])) { _ in installed.fulfill() }
    await fulfillment(of: [installed], timeout: 3)
    feed("teh ", fixture); await drain()
    XCTAssertEqual(fixture.editor.text, "teh ")
    XCTAssertTrue(fixture.editor.results.isEmpty)
  }
  func testFailedLocalReloadKeepsWorkingInstalledModel() async throws {
    let fixture = await fixture(install: false)
    try await installLocal(fixture)
    let done = expectation(description: "bad local reload")
    fixture.controller.installLocalModel(url: URL(fileURLWithPath: "/nonexistent-model-" + UUID().uuidString)) { result in
      XCTAssertTrue(Thread.isMainThread)
      if case .success = result { XCTFail("Invalid path must fail") }
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 3)
    XCTAssertTrue(fixture.controller.automaticReady)
    feed("lf ", fixture); await drain()
    XCTAssertEqual(fixture.editor.text, "да ")
  }
  func testLocalPhysicalPunctuationAfterEnglishWords() async throws {
    let fixture = await fixture(install: false)
    try await installLocal(fixture, punctuationFixtures: true)
    feed("ground ", fixture); await drain()
    feed("connector ", fixture); await drain()
    feed("nj;t ", fixture); await drain()
    XCTAssertEqual(fixture.editor.text, "ground connector тоже ")
    _ = fixture.layouts.select(.init(rawValue: "US"))
    fixture.controller.runtime.updateLayout(.init(rawValue: "US"))
    feed("gthtrk.xbkjcm ", fixture); await drain()
    XCTAssertEqual(fixture.editor.text, "ground connector тоже переключилось ")
  }
  private func installLocal(_ fixture: AutoFixture, punctuationFixtures: Bool = false) async throws {
    let words = ["да", "hello", "teh"] + (punctuationFixtures ? ["ground", "connector", "тоже", "переключилось", "nj;t", "gthtrk.xbkjcm"] : [])
    let records = words.enumerated().map { ["key": "\u{2}" + $0.element + "\u{3}", "value": $0.offset] as [String: Any] }
    let index = Dictionary(uniqueKeysWithValues: words.indices.map { (String($0), [["lang": 0, "weight": ["тоже", "переключилось"].contains(words[$0]) ? 0 : (["nj;t", "gthtrk.xbkjcm"].contains(words[$0]) ? -5 : 5), "is_known_word": ["тоже", "переключилось"].contains(words[$0]), "is_case_sensitive": false] as [String: Any]]) })
    let object: [String: Any] = ["version": "synthetic-runtime", "kbm": ["languages": ["0": "ru-en"], "graph_records": records, "index": index],
      "autocorrect": ["graph_records": [["key": "teh", "value": 0]], "rules": [["prefix_len": 0, "suffix_len": 0, "insert_id": 0]], "insert_pool": ["the"]]]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let done = expectation(description: "local model installed")
    fixture.controller.installLocalModel(url: url) { result in
      XCTAssertTrue(Thread.isMainThread)
      switch result {
      case .success(let version): XCTAssertEqual(version, "synthetic-runtime")
      case .failure(let error): XCTFail("Local fixture failed: \(error)")
      }
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 5)
  }
  private func drain(delay: TimeInterval = 0) async {
    let done = expectation(description: "boundary executor")
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { done.fulfill() }
    await fulfillment(of: [done], timeout: 2)
    // The command owns a main-actor task after its dispatch-queue delivery.
    for _ in 0..<10 { await Task.yield() }
  }
  private func fixture(proxy: Bool = false, install: Bool = true) async -> AutoFixture {
    let context = AutoContext()
    let layouts = AutoLayouts(context)
    let editor = AutoEditor(context, proxy: proxy)
    let capture = AutoTables()
    let controller = NativeInputController(layouts: layouts, permissions: AutoPermissions(),
      conservativeAutomaticEnabled: true, editingContext: context, selectionAccess: editor,
      layoutCapture: capture)
    editor.generation = { controller.runtime.inputGeneration() }
    if install {
      let done = expectation(description: "automatic vocabulary installed")
      controller.install(.init(modelVersion: 1, lexicon: [
        .init(word: "привет", language: .russian, frequencyBand: 1),
        .init(word: "hello", language: .english, frequencyBand: 1)
      ])) { _ in done.fulfill() }
      await fulfillment(of: [done], timeout: 2)
    }
    return .init(controller: controller, context: context, layouts: layouts, editor: editor, tables: capture)
  }
  private func feed(_ text: String, _ fixture: AutoFixture, staleUnicode: Bool = false) {
    let layout = fixture.layouts.value
    let entries = fixture.tables.captureTables().layouts.first { $0.id == layout }!.entries
    for (index, character) in text.enumerated() {
      let text = String(character)
      let entry = entries.first { $0.text == text }
      let code: UInt16 = text == " " ? 49 : (text == "\n" ? 36 : (text == "\t" ? 48 : entry?.keyCode ?? 0))
      fixture.editor.text += text
      let opposite = fixture.tables.captureTables().layouts.first { $0.id != layout }
      let raw = staleUnicode && entry != nil ? opposite?.entries.first { $0.keyCode == code }?.text ?? text : text
      fixture.controller.runtime.accept(.init(kind: .down, keyCode: code, modifiers: entry?.modifiers ?? [],
        timestampNanos: UInt64(index + 1), layout: layout, context: fixture.context.token,
        origin: .physical, text: raw, isRepeat: false))
    }
  }
}
private struct AutoFixture {
  let controller: NativeInputController
  let context: AutoContext
  let layouts: AutoLayouts
  let editor: AutoEditor
  let tables: AutoTables
}
private final class AutoContext: ContextRefreshing {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func refresh() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
}
private final class AutoLayouts: LayoutAccess {
  let context: AutoContext
  var value = LayoutID(rawValue: "US")
  init(_ context: AutoContext) { self.context = context }
  func current() -> LayoutID? { value }
  func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool {
    if id != value {
      value = id
      context.token = .init(pid: context.token.pid, bundleID: context.token.bundleID, focusEpoch: context.token.focusEpoch, layoutEpoch: context.token.layoutEpoch + 1)
    }
    return true
  }
}
private final class AutoPermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: true, post: true, ax: true, secureInput: false) }
  func request(_ kind: PermissionKind) { XCTFail("No TCC requests") }
}
private final class AutoEditor: AutomaticBoundaryEligibilityReading, SelectionAccess, AutomaticBoundarySuffixReplacing, ManualRepeatedSuffixReplacing, ManualTrackedSuffixReplacing {
  let context: AutoContext
  let proxy: Bool
  let identity = UUID()
  var text = ""
  var results: [ApplyResult] = []
  var normalizesSpace = false
  var abortsReplacement = false
  var hidesSuffix = false
  var onSuffix: (() -> Void)?
  var generation: () -> UInt64 = { 0 }
  init(_ context: AutoContext, proxy: Bool) { self.context = context; self.proxy = proxy }
  func selected(in context: ContextToken) -> SelectionEvidence? {
    .init(context: context, text: "", location: proxy ? 0 : text.utf16.count, length: 0, identity: identity)
  }
  func suffix(_ suffix: String, in token: ContextToken) -> SelectionEvidence? {
    guard !proxy, !hidesSuffix, token == context.token, text.hasSuffix(suffix) else { return nil }
    let evidence = SelectionEvidence(context: token, text: suffix,
      location: text.utf16.count - suffix.utf16.count, length: suffix.utf16.count,
      identity: identity, inputGeneration: generation(), mode: .suffix)
    onSuffix?()
    return evidence
  }
  func replace(_ evidence: SelectionEvidence, with replacement: String) -> ApplyResult {
    guard evidence.context == context.token, evidence.identity == identity,
      evidence.inputGeneration == generation(), text.hasSuffix(evidence.text) else { return .aborted }
    text.removeLast(evidence.text.count)
    text += replacement
    return .committed
  }
  func replaceTrackedSuffix(_ word: BufferedWord, with replacement: String) -> ApplyResult {
    guard word.context == context.token, text.hasSuffix(word.text + word.delimiter) else { return .aborted }
    text.removeLast(word.text.count + word.delimiter.count)
    text += replacement
    return .dispatched
  }
  func replaceRepeatedSuffix(_ candidate: ManualRepeatCandidate, with replacement: String) -> ApplyResult {
    guard candidate.context == context.token, candidate.fieldIdentity == identity,
      text.hasSuffix(candidate.currentText + candidate.delimiter) else { return .aborted }
    text.removeLast(candidate.currentText.count + candidate.delimiter.count)
    text += replacement
    return .dispatched
  }
  func canReplaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with replacement: String) -> Bool {
    automaticEligible(candidate)
  }
  private func automaticEligible(_ candidate: AutomaticBoundaryCandidate) -> Bool {
    guard candidate.inputGeneration == generation(), candidate.word.context == context.token,
      candidate.boundary.keyCode == 49, candidate.boundary.text == " ",
      text.hasSuffix(candidate.word.text + " ") else { return false }
    if candidate.requiresWordStartProof && (!proxy || !candidate.allowsOpaqueWordStart) {
      guard !proxy else { return false }
      let prefix = text.dropLast(candidate.word.text.count + 1)
      guard prefix.isEmpty || prefix.last?.isWhitespace == true else { return false }
    }
    return true
  }
  func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with replacement: String) -> ApplyResult {
    guard automaticEligible(candidate) else { return .aborted }
    // Models a rejection after layout preparation that posts no key.
    guard !abortsReplacement else { results.append(.aborted); return .aborted }
    text.removeLast(candidate.word.text.count + 1)
    text += normalizesSpace ? String(replacement.dropLast()) + "\u{00a0}" : replacement
    let result: ApplyResult = proxy ? .dispatched : .committed
    results.append(result)
    return result
  }
}
private final class AutoTables: LayoutTableCapturing {
  func captureTables() -> CapturedLayoutTables {
    let codes: [UInt16] = [12,13,14,15,17,16,32,34,31,35,33,30,0,1,2,3,5,4,38,40,37,41,39,6,7,8,9,11,45,46,43,47,44]
    let source = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,./")
    let target = Array("йцукенгшщзхъфывапролджэячсмитьбю.")
    return .init(layouts: [
      .init(id: .init(rawValue: "US"), entries: zip(codes, source).map { .init(keyCode: $0.0, modifiers: [], text: String($0.1)) }),
      .init(id: .init(rawValue: "RU"), entries: zip(codes, target).map { .init(keyCode: $0.0, modifiers: [], text: String($0.1)) })
    ])
  }
}
