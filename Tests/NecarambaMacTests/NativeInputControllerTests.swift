import NecarambaCore
import CryptoKit
import XCTest

@testable import NecarambaMac

@MainActor final class NativeInputControllerTests: XCTestCase {
  func testInstallCompletionFollowsActualRuntimeVersion() async {
    let controller = NativeInputController(profiles: CapabilityProfiles())
    let done = expectation(description: "installed")
    controller.install(.init(modelVersion: 42)) { version in
      XCTAssertEqual(version, 42)
      XCTAssertEqual(controller.runtime.installedModelVersion, 42)
      XCTAssertTrue(Thread.isMainThread)
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 2)
  }
  func testUnsupportedControllerManualActionAborts() async {
    let controller = NativeInputController(profiles: CapabilityProfiles())
    let asyncResult1 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult1, .aborted)
  }
}

private final class FacadeContext: ContextRefreshing {
  var onRefresh: (() -> Void)?
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
  func refresh() -> ContextToken? { onRefresh?(); return token }
}
private final class FacadePermissions: PermissionReading {
  var secure = false
  var post = true
  func current() -> PermissionState {
    .init(listen: true, post: post, ax: true, secureInput: secure)
  }
  func request(_ kind: PermissionKind) { XCTFail("No permission request allowed") }
}
private final class FacadeSelection: SelectionAccess {
  var reads = 0
  func selected(in token: ContextToken) -> SelectionEvidence? {
    reads += 1
    return nil
  }
  func suffix(_ text: String, in token: ContextToken) -> SelectionEvidence? { nil }
  func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult {
    XCTFail("Unexpected mutation")
    return .uncertain
  }
}
private final class FacadeClipboard: ClipboardAccess {
  var reads = 0
  var changeCount: Int { 0 }
  func snapshot(maxBytes: Int) throws -> PasteboardSnapshot {
    reads += 1
    return .init(items: [], changeCount: 0)
  }
  func write(_ items: [PasteboardItem]) throws -> Int {
    XCTFail("Unexpected clipboard write")
    return 0
  }
}
extension NativeInputControllerTests {
  func testPlainPasteUsesCapturedFocusInsteadOfCurrentFocus() async {
    let context = FacadeContext()
    let selection = FacadeSelection()
    let clipboard = FacadeClipboard()
    let controller = NativeInputController(
      permissions: FacadePermissions(), editingContext: context, selectionAccess: selection)
    let original = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    let asyncResult2 = await controller.plainPasteAsync(in: original, clipboard: clipboard)
    XCTAssertEqual(asyncResult2, .aborted)
    XCTAssertEqual(selection.reads, 0)
    XCTAssertEqual(clipboard.reads, 0)
  }
}

private final class ManualLayouts: LayoutAccess {
  var onSelect: ((LayoutID) -> Void)?
  var value = LayoutID(rawValue: "US")
  func current() -> LayoutID? { value }
  func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool { value = id; onSelect?(id); return true }
}
private final class ManualEditor: ManualCaretWordReading, SelectionAccess, ManualTrackedSuffixReplacing, ManualRepeatedSuffixReplacing {
  let context: FacadeContext
  var text = "ghbdtn"
  var authoritativeCaretWord = false
  func wordBeforeCaret(in token: ContextToken) -> ManualCaretWord {
    guard authoritativeCaretWord else { return .notRequired }
    return suffix(text, in: token).map(ManualCaretWord.word) ?? .unavailable
  }
  var selectionLength = 0
  var emptyProxy = false
  var fallbackCalls = 0
  var replacementResult = ApplyResult.committed
  var onReplace: (() -> Void)?
  init(_ context: FacadeContext) { self.context = context }
  func selected(in token: ContextToken) -> SelectionEvidence? {
    guard token == context.token else { return nil }
    return .init(context: token, text: selectionLength == 0 ? "" : text,
                 location: selectionLength == 0 ? text.utf16.count : 0, length: selectionLength)
  }
  func suffix(_ suffix: String, in token: ContextToken) -> SelectionEvidence? {
    guard !emptyProxy, token == context.token, text.hasSuffix(suffix) else { return nil }
    return .init(context: token, text: suffix, location: text.utf16.count - suffix.utf16.count,
                 length: suffix.utf16.count)
  }
  func replace(_ evidence: SelectionEvidence, with replacement: String) -> ApplyResult {
    guard evidence.context == context.token else { return .aborted }
    guard replacementResult == .committed else { return replacementResult }
    text = (text as NSString).replacingCharacters(
      in: NSRange(location: evidence.location, length: evidence.length), with: replacement)
    onReplace?()
    return .committed
  }
  func replaceRepeatedSuffix(_ candidate: ManualRepeatCandidate, with replacement: String) -> ApplyResult {
    guard emptyProxy, candidate.context == context.token,
      text == candidate.currentText + candidate.delimiter else { return .aborted }
    text = replacement
    return .dispatched
  }
  func replaceTrackedSuffix(_ word: BufferedWord, with replacement: String) -> ApplyResult {
    fallbackCalls += 1
    guard emptyProxy, word.context == context.token, word.text + word.delimiter == text,
      word.events.compactMap(\.text).joined() == word.text else { return .aborted }
    text = replacement
    return .dispatched
  }
}
extension NativeInputControllerTests {
  private func installedController(corpus: Bool = false) async -> (NativeInputController, FacadeContext, ManualEditor) {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    let controller = NativeInputController(
      layouts: ManualLayouts(), permissions: FacadePermissions(), corpusQualified: corpus,
      editingContext: context, selectionAccess: editor)
    let installed = expectation(description: "manual mapping installed")
    controller.install(.init(modelVersion: 1,
      lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)],
      mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"),
        pairs: ["g": "п", "h": "р", "b": "и", "d": "в", "t": "е", "n": "т"]),
        .init(source: .init(rawValue: "RU"), target: .init(rawValue: "US"),
          pairs: ["п": "g", "р": "h", "и": "b", "в": "d", "е": "t", "т": "n"])])) { _ in installed.fulfill() }
    await fulfillment(of: [installed], timeout: 2)
    return (controller, context, editor)
  }
  private func typeWord(_ controller: NativeInputController, context: FacadeContext) {
    for (n, pair) in zip([5, 4, 11, 2, 17, 45], Array("ghbdtn")).enumerated() {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(pair.0), modifiers: [],
        timestampNanos: UInt64(n), layout: .init(rawValue: "US"), context: context.token,
        origin: .physical, text: String(pair.1), isRepeat: false))
    }
  }
  func testEmptyProfilesStillAllowExplicitDoubleShiftForProvenTypedWord() async {
    let (controller, context, editor) = await installedController()
    let committed = expectation(description: "manual correction")
    controller.onResult = { result in XCTAssertEqual(result, .committed); committed.fulfill() }
    typeWord(controller, context: context)
    for (index, down) in [true, false, true, false].enumerated() {
      controller.runtime.accept(.init(kind: down ? .down : .up, keyCode: 56,
        modifiers: down ? [.shift] : [], timestampNanos: UInt64(index + 1) * 40_000_000,
        layout: .init(rawValue: "US"), context: context.token, origin: .physical,
        text: nil, isRepeat: false))
    }
    await fulfillment(of: [committed], timeout: 1)
    XCTAssertEqual(editor.text, "привет")
  }
  func testSpotlightUsesFullVisibleWordWhenOnlyLastTwoKeysWereCaptured() async {
    let (controller, context, editor) = await installedController()
    editor.authoritativeCaretWord = true
    for (index, character) in Array("tn").enumerated() {
      controller.runtime.accept(.init(kind: .down, keyCode: index == 0 ? 17 : 45,
        modifiers: [], timestampNanos: UInt64(index), layout: .init(rawValue: "US"),
        context: context.token, origin: .physical, text: String(character), isRepeat: false))
    }
    XCTAssertEqual(controller.runtime.manualWord()?.text, "tn")
    let asyncResult3 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult3, .committed)
    XCTAssertEqual(editor.text, "привет")
  }

  func testSpotlightNeverUsesPartialCaptureWhenWholeWordCannotBeProven() async {
    let (controller, context, editor) = await installedController()
    editor.authoritativeCaretWord = true
    editor.emptyProxy = true
    typeWord(controller, context: context)
    let asyncResult4 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult4, .aborted)
    XCTAssertEqual(editor.text, "ghbdtn")
    XCTAssertEqual(editor.fallbackCalls, 0)
  }

  func testSpotlightUsesVisibleWordWhenCaptureWasEntirelyLost() async {
    let (controller, _, editor) = await installedController()
    editor.authoritativeCaretWord = true
    let asyncResult5 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult5, .committed)
    XCTAssertEqual(editor.text, "привет")
  }

  func testManualVersionConversionAndRepeatedReversalPreserveDigits() async {
    for delimiter in ["", " "] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      let layouts = ManualLayouts()
      layouts.value = .init(rawValue: "RU")
      let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor)
      let installed = expectation(description: "version mappings")
      controller.install(.init(modelVersion: 1, mappings: [
        .init(source: .init(rawValue: "RU"), target: .init(rawValue: "US"), pairs: ["ю": "."]),
        .init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: [".": "ю"])
      ])) { _ in installed.fulfill() }
      await fulfillment(of: [installed], timeout: 2)
      editor.text = "1ю3ю166" + delimiter
      for (index, char) in editor.text.enumerated() {
        controller.runtime.accept(.init(kind: .down, keyCode: char == " " ? 49 : 0, modifiers: [],
          timestampNanos: UInt64(index), layout: .init(rawValue: "RU"), context: context.token,
          origin: .physical, text: String(char), isRepeat: false))
      }
      for expected in ["1.3.166", "1ю3ю166", "1.3.166", "1ю3ю166"] {
        let asyncResult6 = await controller.manualCorrectionAsync()
        XCTAssertEqual(asyncResult6, .committed)
        XCTAssertEqual(editor.text, expected + delimiter)
      }
    }
  }
  func testSparkManualReversalAfterAutomaticNBSPCorrectionRemainsRepeatable() async {
    let (controller, context, editor) = await installedController()
    context.token = ContextToken(pid: 42, bundleID: "com.readdle.SparkDesktop", focusEpoch: 2, layoutEpoch: 1)
    editor.authoritativeCaretWord = true
    editor.text = "привет\u{00A0}"
    let original = BufferedWord(text: "ghbdtn", events: [], context: context.token,
      layout: .init(rawValue: "US"), delimiter: " ")
    XCTAssertTrue(controller.runtime.retainManualResult(.init(original: original,
      currentText: "привет", context: context.token, layout: .init(rawValue: "RU"),
      delimiter: " ", fieldIdentity: nil), expectedGeneration: controller.runtime.inputGeneration()))
    for expected in ["ghbdtn\u{00A0}", "привет\u{00A0}", "ghbdtn\u{00A0}", "привет\u{00A0}"] {
      let asyncResult7 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult7, .committed)
      XCTAssertEqual(editor.text, expected)
    }
  }

  func testEmptyProfilesAllowExplicitSelectionConversion() async {
    let (controller, _, editor) = await installedController()
    editor.selectionLength = 6
    let asyncResult8 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult8, .committed)
    XCTAssertEqual(editor.text, "привет")
  }
  func testCorpusQualificationDoesNotBypassMissingAutomaticProfile() async {
    let (controller, context, editor) = await installedController(corpus: true)
    typeWord(controller, context: context)
    let drained = expectation(description: "commands drained")
    DispatchQueue.main.async { drained.fulfill() }
    await fulfillment(of: [drained], timeout: 1)
    XCTAssertEqual(editor.text, "ghbdtn")
  }
}

extension NativeInputControllerTests {
  func testManualRoleQualificationDoesNotDependOnApplicationProfile() async {
    XCTAssertTrue(ContextMonitor.supportsManualRole("AXTextField"))
    XCTAssertTrue(ContextMonitor.supportsManualRole("AXTextArea"))
    XCTAssertTrue(ContextMonitor.supportsManualRole("AXComboBox"))
    XCTAssertFalse(ContextMonitor.supportsManualRole("AXPopUpButton"))
    XCTAssertFalse(ContextMonitor.supportsManualRole("AXWebArea"))
    XCTAssertFalse(ContextMonitor.supportsManualRole("AXButton"))
    XCTAssertFalse(ContextMonitor.supportsManualRole(""))
  }
  func testManualSelectionCannotBypassSecureInputOrPostPermission() async {
    for secure in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.selectionLength = 6
      let permissions = FacadePermissions()
      permissions.secure = secure
      permissions.post = secure
      let controller = NativeInputController(layouts: ManualLayouts(), permissions: permissions,
        editingContext: context, selectionAccess: editor)
      let asyncResult9 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult9, .aborted)
      XCTAssertEqual(editor.text, "ghbdtn")
    }
  }
}

extension NativeInputControllerTests {
  func testExplicitTrackedWordUsesEmptyProxyFallbackWithoutClaimingCommitOrUndo() async {
    let (controller, context, editor) = await installedController()
    editor.emptyProxy = true
    typeWord(controller, context: context)
    controller.onCommitted = { _, _ in XCTFail("Unverified dispatch must not record a correction") }
    let asyncResult10 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult10, .dispatched)
    XCTAssertEqual(editor.text, "привет")
    XCTAssertEqual(editor.fallbackCalls, 1)
    XCTAssertNil(controller.runtime.manualWord())
    let asyncResult11 = await controller.undoLastAsync()
    XCTAssertEqual(asyncResult11, .aborted)
  }
  func testFailedProvenReplacementNeverRetriesViaTrackedFallback() async {
    let (controller, context, editor) = await installedController()
    typeWord(controller, context: context)
    editor.replacementResult = .uncertain
    let asyncResult12 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult12, .uncertain)
    XCTAssertEqual(editor.fallbackCalls, 0)
    XCTAssertEqual(editor.text, "ghbdtn")
  }
}

private final class ManualCapture: LayoutTableCapturing {
  var onCapture: () -> Void = {}
  func captureTables() -> CapturedLayoutTables {
    onCapture()
    let codes: [UInt16] = [5, 4, 11, 2, 17, 45, 50, 15, 3, 37, 40]
    return .init(layouts: [
      .init(id: .init(rawValue: "US"), entries: zip(codes, Array("ghbdtn`rflk")).map {
        .init(keyCode: $0.0, modifiers: [], text: String($0.1))
      }),
      .init(id: .init(rawValue: "RU"), entries: zip(codes, Array("привет>кадл")).map {
        .init(keyCode: $0.0, modifiers: [], text: String($0.1))
      })
    ])
  }
}
extension NativeInputControllerTests {
  func testManualConversionUsesActualTablesDespiteRejectedShippedMapping() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    let capture = ManualCapture()
    let snapshot = RuleSnapshot(modelVersion: 1, mappings: [
      .init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"),
        pairs: ["g": "п", "h": "р", "b": "и", "d": "в", "t": "е", "n": "т", "`": "ё"])
    ])
    XCTAssertTrue(capture.captureTables().resolve(snapshot).mappings.isEmpty)
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: capture)
    let installed = expectation(description: "rejected automatic mapping installed")
    controller.install(snapshot) { _ in installed.fulfill() }
    await fulfillment(of: [installed], timeout: 2)
    typeWord(controller, context: context)
    let asyncResult13 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult13, .committed)
    XCTAssertEqual(editor.text, "привет")
  }
  func testManualSelectionNeedsNoRulePackageOrDictionary() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.selectionLength = 6
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    let asyncResult14 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult14, .committed)
    XCTAssertEqual(editor.text, "привет")
  }
}

extension NativeInputControllerTests {
  func testTypingDuringManualTableCaptureCancelsAction() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.selectionLength = 6
    let capture = ManualCapture()
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: capture)
    capture.onCapture = { self.typeWord(controller, context: context) }
    let asyncResult15 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult15, .aborted)
    XCTAssertEqual(editor.text, "ghbdtn")
  }
}

extension NativeInputControllerTests {
  func testSuccessiveManualWordsUsePhysicalLayoutWhenTapUnicodeIsStale() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.emptyProxy = true
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    let asyncResult16 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult16, .dispatched)
    XCTAssertEqual(editor.text, "привет")
    editor.text = "как"
    for code in [15, 3, 15] {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(code), modifiers: [],
        timestampNanos: 500, layout: .init(rawValue: "RU"), context: context.token,
        origin: .physical, text: code == 15 ? "r" : "f", isRepeat: false))
    }
    let asyncResult17 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult17, .dispatched)
    XCTAssertEqual(editor.text, "rfr")
    editor.text = "ltkf"
    for (code, stale) in zip([37, 17, 40, 3], Array("дела")) {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(code), modifiers: [],
        timestampNanos: 1000, layout: .init(rawValue: "US"), context: context.token,
        origin: .physical, text: String(stale), isRepeat: false))
    }
    let asyncResult18 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult18, .dispatched)
    XCTAssertEqual(editor.text, "дела")
  }
}
extension NativeInputControllerTests {
  func testPhysicalSourceReconstructionStillRequiresExactEditorSuffix() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    let layouts = ManualLayouts()
    layouts.value = .init(rawValue: "RU")
    let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    for code in [15, 3, 15] {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(code), modifiers: [],
        timestampNanos: 500, layout: .init(rawValue: "RU"), context: context.token,
        origin: .physical, text: code == 15 ? "r" : "f", isRepeat: false))
    }
    editor.text = "unrelated"
    let asyncResult19 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult19, .aborted)
    XCTAssertEqual(editor.text, "unrelated")
    editor.text = "как"
    let asyncResult20 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult20, .committed)
    XCTAssertEqual(editor.text, "rfr")
  }
}
extension NativeInputControllerTests {
  func testRepeatedDoubleShiftTogglesLastWordAtLeastFourTimesInReadableAndProxyFields() async {
    for proxy in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.emptyProxy = proxy
      let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
      typeWord(controller, context: context)
      for (turn, expected) in ["привет", "ghbdtn", "привет", "ghbdtn"].enumerated() {
        let converted = expectation(description: "double Shift conversion")
        controller.onResult = { result in
          XCTAssertEqual(result, proxy ? .dispatched : .committed)
          converted.fulfill()
        }
        let layout = controller.runtime.cachedInputContext()!.1
        // Duplicate asynchronous TIS notification must not erase the last result.
        controller.runtime.updateLayout(layout)
        for (index, down) in [true, false, true, false].enumerated() {
          controller.runtime.accept(.init(kind: down ? .down : .up, keyCode: 56,
            modifiers: down ? [.shift] : [],
            timestampNanos: UInt64(turn + 1) * 1_000_000_000 + UInt64(index) * 40_000_000,
            layout: layout, context: context.token, origin: .physical, text: nil, isRepeat: false))
        }
        await fulfillment(of: [converted], timeout: 1)
        XCTAssertEqual(editor.text, expected)
      }
    }
  }
  func testSelectedTextUsesItsAlphabetRatherThanActiveInputLayout() async {
    for (selected, active, expected) in [("привет", "US", "ghbdtn"), ("ghbdtn", "RU", "привет")] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.text = selected
      editor.selectionLength = selected.utf16.count
      let layouts = ManualLayouts()
      layouts.value = .init(rawValue: active)
      let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
      let asyncResult21 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult21, .committed)
      XCTAssertEqual(editor.text, expected)
      editor.selectionLength = 0
      let asyncResult22 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult22, .committed)
      XCTAssertEqual(editor.text, selected)
    }
  }
  func testRepeatedConversionSurvivesSingleShiftBetweenPairsAndInitialSelection() async {
    for initiallySelected in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.selectionLength = initiallySelected ? 6 : 0
      let layouts = ManualLayouts()
      let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
      if !initiallySelected { typeWord(controller, context: context) }
      let asyncResult23 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult23, .committed)
      editor.selectionLength = 0
      for turn in 0..<12 {
        if turn % 3 == 2 {
          let stamp = UInt64(turn + 1) * 1_000_000_000
          for (index, modifiers): (Int, Set<Modifier>) in [Set<Modifier>([.shift]), []].enumerated() {
            controller.runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: modifiers,
              timestampNanos: stamp + UInt64(index), layout: controller.runtime.cachedInputContext()!.1,
              context: context.token, origin: .physical, text: nil, isRepeat: false))
          }
          let delivered = expectation(description: "single Shift verified")
          layouts.onSelect = { _ in delivered.fulfill() }
          controller.runtime.advance(to: stamp + 400_000_000)
          await fulfillment(of: [delivered], timeout: 1)
          layouts.onSelect = nil
        }
        let asyncResult24 = await controller.manualCorrectionAsync()
        XCTAssertEqual(asyncResult24, .committed, "turn \(turn), selected \(initiallySelected)")
        XCTAssertEqual(editor.text, turn % 2 == 0 ? "ghbdtn" : "привет")
      }
    }
  }
  func testTwentyConversionsRetainWordWhenShiftArrivesDuringReplacement() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    editor.onReplace = {
      controller.runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: [],
        timestampNanos: 100, layout: controller.runtime.cachedInputContext()!.1,
        context: context.token, origin: .physical, text: nil, isRepeat: false))
    }
    for turn in 0..<20 {
      let asyncResult25 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult25, .committed)
      XCTAssertEqual(editor.text, turn % 2 == 0 ? "привет" : "ghbdtn")
      XCTAssertNotNil(controller.runtime.manualRepeatCandidate())
    }
    editor.onReplace = nil
  }
  func testNavigationAndFocusChangeInvalidateRepeatedManualConversion() async {
    for changeFocus in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.emptyProxy = true
      let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
      typeWord(controller, context: context)
      let asyncResult26 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult26, .dispatched)
      if changeFocus {
        context.token = .init(pid: 42, bundleID: "test", focusEpoch: 3, layoutEpoch: 1)
      } else {
        controller.runtime.accept(.init(kind: .down, keyCode: 123, modifiers: [], timestampNanos: 900,
          layout: .init(rawValue: "RU"), context: context.token, origin: .physical,
          text: nil, isRepeat: false))
      }
      let asyncResult27 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult27, .aborted)
      XCTAssertEqual(editor.text, "привет")
    }
  }
}

extension NativeInputControllerTests {
  func testRepeatedManualPreservesTrailingSpaceAndDirectPasteDiscardsCandidate() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.text = "ghbdtn "
    editor.emptyProxy = true
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    controller.runtime.accept(.init(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 100,
      layout: .init(rawValue: "US"), context: context.token, origin: .physical, text: " ", isRepeat: false))
    for expected in ["привет ", "ghbdtn ", "привет "] {
      let asyncResult28 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult28, .dispatched)
      XCTAssertEqual(editor.text, expected)
    }
    _ = await controller.plainPasteAsync(clipboard: FacadeClipboard())
    let asyncResult29 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult29, .aborted)
    XCTAssertEqual(editor.text, "привет ")
  }
}
extension NativeInputControllerTests {
  func testDirectPasteDiscardsPrePasteAutomaticBufferBeforeNextSpace() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.emptyProxy = true
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    _ = await controller.plainPasteAsync(clipboard: FacadeClipboard())
    controller.runtime.accept(.init(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 100,
      layout: .init(rawValue: "US"), context: context.token, origin: .physical, text: " ", isRepeat: false))
    XCTAssertNil(controller.runtime.manualWord())
    let asyncResult30 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult30, .aborted)
  }
  func testPermissionDeniedDoubleShiftDiscardsRepeatBeforePermissionsReturn() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.emptyProxy = true
    let permissions = FacadePermissions()
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: permissions,
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    let asyncResult31 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult31, .dispatched)
    permissions.secure = true
    for (index, down) in [true, false, true, false].enumerated() {
      controller.runtime.accept(.init(kind: down ? .down : .up, keyCode: 56,
        modifiers: down ? [.shift] : [], timestampNanos: 1_000_000_000 + UInt64(index) * 40_000_000,
        layout: .init(rawValue: "RU"), context: context.token, origin: .physical, text: nil, isRepeat: false))
    }
    let drained = expectation(description: "permission-denied gesture dispatched")
    DispatchQueue.main.async { drained.fulfill() }
    await fulfillment(of: [drained], timeout: 1)
    permissions.secure = false
    XCTAssertNil(controller.runtime.manualRepeatCandidate())
    let asyncResult32 = await controller.manualCorrectionAsync()
    XCTAssertEqual(asyncResult32, .aborted)
    XCTAssertEqual(editor.text, "привет")
  }
}

private final class OpenFacadeCapture: LayoutTableCapturing {
  func captureTables() -> CapturedLayoutTables {
    let codes: [UInt16] = [12,13,14,15,17,16,32,34,31,35,33,30,0,1,2,3,5,4,38,40,37,41,39,6,7,8,9,11,45,46,43,47,44]
    return .init(layouts: zip(["US", "RU"], ["qwertyuiop[]asdfghjkl;'zxcvbnm,./", "йцукенгшщзхъфывапролджэячсмитьбю."]).map { id, chars in
      .init(id: .init(rawValue: id), entries: zip(codes, chars).map { .init(keyCode: $0.0, modifiers: [], text: String($0.1)) })
    })
  }
}
extension ManualEditor: AutomaticBoundarySuffixReplacing {
  func replaceAutomaticBoundary(_ candidate: AutomaticBoundaryCandidate, with replacement: String) -> ApplyResult {
    guard let evidence = suffix(candidate.word.text + candidate.word.delimiter, in: candidate.word.context) else { return .aborted }
    return replace(evidence, with: replacement)
  }
}
extension NativeInputControllerTests {
  private func openBundle() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let rules = Data(#"{"schemaVersion":1,"version":"fixture-1","typos":[],"yo":[],"protectedWords":[]}"#.utf8)
    let files = ["en.words": Data("ground\nhello\n".utf8), "ru.words": Data("да\nпривет\nтоже\n".utf8), "corrections.json": rules]
    var entries: [String: Any] = [:]
    for (name, data) in files {
      try data.write(to: directory.appendingPathComponent(name))
      entries[name] = ["bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
    }
    try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "version": "fixture-1", "files": entries]).write(to: directory.appendingPathComponent("manifest.json"))
    return directory
  }
  func testOpenModelReadinessShortPunctuationAndManualReverse() async throws {
    let directory = try openBundle(); defer { try? FileManager.default.removeItem(at: directory) }
    for (typed, expected) in [("lf ", "да "), ("nj;t ", "тоже ")] {
      let context = FacadeContext(), layouts = ManualLayouts(), capture = OpenFacadeCapture()
      let editor = ManualEditor(context); editor.text = ""
      let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(), conservativeAutomaticEnabled: true,
        editingContext: context, selectionAccess: editor, layoutCapture: capture)
      XCTAssertFalse(controller.automaticReady)
      let installed = expectation(description: "open model installed")
      controller.installOpenModel(directory: directory) { result in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(try? result.get(), "fixture-1")
        installed.fulfill()
      }
      await fulfillment(of: [installed], timeout: 3)
      XCTAssertTrue(controller.automaticReady)
      let refreshed = expectation(description: "signed snapshot refresh preserves open model")
      controller.install(.init(modelVersion: 2)) { _ in refreshed.fulfill() }
      await fulfillment(of: [refreshed], timeout: 2)
      XCTAssertTrue(controller.automaticReady)
      let corrected = expectation(description: "automatic correction completed")
      controller.onResult = { result in
        XCTAssertEqual(result, .committed)
        corrected.fulfill()
      }
      let entries = capture.captureTables().layouts[0].entries
      for (index, character) in typed.enumerated() {
        editor.text.append(character)
        controller.runtime.accept(.init(kind: .down, keyCode: character == " " ? 49 : entries.first { $0.text == String(character) }!.keyCode,
          modifiers: [], timestampNanos: UInt64(index + 1), layout: layouts.value, context: context.token,
          origin: .physical, text: String(character), isRepeat: false))
      }
      await fulfillment(of: [corrected], timeout: 2)
      controller.onResult = { _ in }
      XCTAssertEqual(editor.text, expected)
      let asyncResult33 = await controller.manualCorrectionAsync()
      XCTAssertEqual(asyncResult33, .committed)
      XCTAssertEqual(editor.text, typed)
    }
  }
  func testOpenModelFailureDoesNotEnableAutomaticAndRequiresFullLayouts() async throws {
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(), conservativeAutomaticEnabled: true,
      editingContext: FacadeContext(), layoutCapture: ManualCapture())
    let failed = expectation(description: "invalid open bundle rejected")
    controller.installOpenModel(directory: URL(fileURLWithPath: "/missing-" + UUID().uuidString)) { result in
      if case .success = result { XCTFail("Expected failure") }; failed.fulfill()
    }
    await fulfillment(of: [failed], timeout: 2); XCTAssertFalse(controller.automaticReady)
    let directory = try openBundle(); defer { try? FileManager.default.removeItem(at: directory) }
    let loaded = expectation(description: "valid bundle unsupported layouts")
    controller.installOpenModel(directory: directory) { result in XCTAssertEqual(try? result.get(), "fixture-1"); loaded.fulfill() }
    await fulfillment(of: [loaded], timeout: 2); XCTAssertFalse(controller.automaticReady)
  }
}

extension NativeInputControllerTests {
  func testOwnLayoutNotificationDoesNotInvalidateSelectedConversionOrRepeat() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.selectionLength = editor.text.utf16.count
    let layouts = ManualLayouts()
    let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    layouts.onSelect = { target in
      context.token = .init(pid: context.token.pid, bundleID: context.token.bundleID,
        focusEpoch: context.token.focusEpoch, layoutEpoch: context.token.layoutEpoch + 1)
      controller.context.onLayoutChanged?(target)
    }
    let result = await controller.manualCorrectionAsync()
    XCTAssertEqual(result, .committed)
    XCTAssertEqual(editor.text, "привет")
    XCTAssertNotNil(controller.runtime.manualRepeatCandidate())
  }
}

extension NativeInputControllerTests {
  func testFocusChangeOnFinalLayoutRefreshCannotCommitSelectedConversion() async {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.selectionLength = 6
    let layouts = ManualLayouts()
    let controller = NativeInputController(layouts: layouts, permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    var commits = 0
    controller.onCommitted = { _, _ in commits += 1 }
    context.onRefresh = {
      if layouts.value.rawValue == "RU" {
        context.token = .init(pid: 99, bundleID: "other", focusEpoch: 100, layoutEpoch: 1)
      }
    }
    let result = await controller.manualCorrectionAsync()
    XCTAssertEqual(result, .uncertain)
    XCTAssertEqual(commits, 0)
    XCTAssertNil(controller.runtime.manualRepeatCandidate())
  }
}
