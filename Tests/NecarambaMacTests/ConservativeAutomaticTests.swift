import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ConservativeAutomaticTests: XCTestCase {
  func testFirstAndNextWordCorrectBothDirectionsInReadableAndProxyFields() {
    for proxy in [false, true] {
      let fixture = fixture(proxy: proxy)
      feed("ghbdtn ", fixture)
      drain()
      XCTAssertEqual(fixture.editor.text, "привет ")
      XCTAssertEqual(fixture.layouts.value.rawValue, "RU")
      feed("руддщ ", fixture)
      drain()
      XCTAssertEqual(fixture.editor.text, "привет hello ")
      XCTAssertEqual(fixture.layouts.value.rawValue, "US")
      XCTAssertEqual(fixture.editor.results, [proxy ? .dispatched : .committed, proxy ? .dispatched : .committed])
      XCTAssertTrue(fixture.controller.automaticReady)
    }
  }
  func testCorrectProtectedDisabledExcludedAndDeniedWordsStayUntouched() {
    for word in ["hello ", "lf ", "url/ghbdtn ", "foo/ghbdtn ", "foo.ghbdtn ", "foo@ghbdtn ", "a@ghbdtn ", "foo2ghbdtn "] {
      let fixture = fixture()
      feed(word, fixture)
      drain()
      XCTAssertEqual(fixture.editor.text, word)
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
    for policy in 0..<3 {
      let fixture = fixture()
      if policy == 0 { fixture.controller.updatePreferences(.init(autoEnabled: false)) }
      if policy == 1 { fixture.controller.updateWordPolicies(["ghbdtn"]) }
      if policy == 2 { fixture.controller.updateAppPolicies(["test": .deny]) }
      feed("ghbdtn ", fixture)
      drain()
      XCTAssertEqual(fixture.editor.text, "ghbdtn ")
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
  }
  func testEnterAndNewInputAfterSpaceCannotEditEarlierWord() {
    for suffix in ["\n", "\t", " g"] {
      let fixture = fixture(proxy: true)
      feed("ghbdtn" + suffix, fixture)
      drain()
      XCTAssertEqual(fixture.editor.text, "ghbdtn" + suffix)
      XCTAssertTrue(fixture.editor.results.isEmpty)
    }
  }
  func testAutomaticModeIsNotReadyWithoutCapturedLayoutsOrLexicon() {
    let fixture = fixture(install: false)
    XCTAssertFalse(fixture.controller.automaticReady)
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "ghbdtn ")
  }
  func testAutomaticProxyResultCanBeReversedByExplicitManualCommand() {
    let fixture = fixture(proxy: true)
    var commits = 0
    fixture.controller.onCommitted = { _, _ in commits += 1 }
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
    XCTAssertEqual(commits, 0)
    XCTAssertEqual(fixture.controller.manualCorrection(), .dispatched)
    XCTAssertEqual(fixture.editor.text, "ghbdtn ")
  }
  func testReadinessCallbackFollowsLoadedLexiconAndActualLayouts() {
    let fixture = fixture(install: false)
    var readiness: [Bool] = []
    fixture.controller.onAutomaticReadinessChanged = { readiness.append($0) }
    let installed = expectation(description: "readiness changed")
    fixture.controller.install(.init(modelVersion: 2, lexicon: [
      .init(word: "привет", language: .russian, frequencyBand: 1)])) { _ in installed.fulfill() }
    wait(for: [installed], timeout: 2)
    XCTAssertEqual(readiness, [true])
    XCTAssertTrue(fixture.controller.automaticReady)
  }
  func testForeignPasteCannotTurnFollowingURLSuffixIntoStandaloneWord() {
    let fixture = fixture(proxy: true)
    feed("url/", fixture)
    fixture.controller.runtime.accept(.init(kind: .down, keyCode: 9, modifiers: [.command],
      timestampNanos: 100, layout: fixture.layouts.value, context: fixture.context.token,
      origin: .foreignSynthetic, text: nil, isRepeat: false))
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn ")
    XCTAssertTrue(fixture.editor.results.isEmpty)
  }
  func testPhysicalTablesCorrectBothDirectionsDespiteStaleTapUnicode() {
    let fixture = fixture(proxy: true)
    feed("ghbdtn ", fixture, staleUnicode: true)
    drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
    feed("руддщ ", fixture, staleUnicode: true)
    drain()
    XCTAssertEqual(fixture.editor.text, "привет hello ")
  }
  func testNavigationDropsUntrustedPrefixUntilNextSpaceThenAllowsFreshWord() {
    let fixture = fixture(proxy: true)
    feed("url/", fixture)
    fixture.controller.runtime.invalidateContext(reason: .mouseNavigation)
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn ")
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "url/ghbdtn привет ")
  }
  func testStartupPublishingUnchangedEmptyPoliciesDoesNotDiscardFirstWord() {
    let fixture = fixture()
    fixture.controller.updateWordPolicies([])
    fixture.controller.updateAppPolicies([:])
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
  }
  func testManualCorrectionWithoutSpaceDoesNotExposeAppendedSuffixToAutomaticCorrection() {
    let fixture = fixture(proxy: true)
    feed("ghbdtn", fixture)
    XCTAssertEqual(fixture.controller.manualCorrection(), .dispatched)
    XCTAssertEqual(fixture.editor.text, "привет")
    feed("руддщ ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "приветруддщ ")
    XCTAssertTrue(fixture.editor.results.isEmpty)
    feed("руддщ ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "приветруддщ hello ")
  }
  func testFirstWordAfterPlainReturnNeedsNoLeadingSpaceEvenInProxy() {
    for proxy in [false, true] {
      let fixture = fixture(proxy: proxy)
      feed("hello\n", fixture)
      drain()
      XCTAssertTrue(fixture.editor.results.isEmpty)
      feed("ghbdtn ", fixture)
      drain()
      XCTAssertEqual(fixture.editor.text, "hello\nпривет ")
    }
  }

  func testFirstReadableWordAfterFocusInvalidationNeedsNoLeadingSpace() {
    let fixture = fixture()
    fixture.controller.runtime.invalidateContext(reason: .mouseNavigation)
    feed("ghbdtn ", fixture)
    drain()
    XCTAssertEqual(fixture.editor.text, "привет ")
  }

  private func drain() {
    let done = expectation(description: "boundary executor")
    DispatchQueue.main.async { done.fulfill() }
    wait(for: [done], timeout: 2)
  }
  private func fixture(proxy: Bool = false, install: Bool = true) -> AutoFixture {
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
      wait(for: [done], timeout: 2)
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
      context.token = .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: context.token.layoutEpoch + 1)
    }
    return true
  }
}
private final class AutoPermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: true, post: true, ax: true, secureInput: false) }
  func request(_ kind: PermissionKind) { XCTFail("No TCC requests") }
}
private final class AutoEditor: SelectionAccess, AutomaticBoundarySuffixReplacing, ManualRepeatedSuffixReplacing, ManualTrackedSuffixReplacing {
  let context: AutoContext
  let proxy: Bool
  let identity = UUID()
  var text = ""
  var results: [ApplyResult] = []
  var generation: () -> UInt64 = { 0 }
  init(_ context: AutoContext, proxy: Bool) { self.context = context; self.proxy = proxy }
  func selected(in context: ContextToken) -> SelectionEvidence? {
    .init(context: context, text: "", location: proxy ? 0 : text.utf16.count, length: 0, identity: identity)
  }
  func suffix(_ suffix: String, in context: ContextToken) -> SelectionEvidence? { nil }
  func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult { XCTFail("Use captured auto lease"); return .aborted }
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
  func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with replacement: String) -> ApplyResult {
    guard candidate.inputGeneration == generation(), candidate.word.context == context.token,
      candidate.boundary.keyCode == 49, candidate.boundary.text == " ",
      text.hasSuffix(candidate.word.text + " ") else { return .aborted }
    if candidate.requiresWordStartProof {
      guard !proxy else { return .aborted }
      let prefix = text.dropLast(candidate.word.text.count + 1)
      guard prefix.isEmpty || prefix.last?.isWhitespace == true else { return .aborted }
    }
    text.removeLast(candidate.word.text.count + 1)
    text += replacement
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
