import NecarambaCore
import XCTest

@testable import NecarambaMac

final class NativeInputControllerTests: XCTestCase {
  func testInstallCompletionFollowsActualRuntimeVersion() {
    let controller = NativeInputController(profiles: CapabilityProfiles())
    let done = expectation(description: "installed")
    controller.install(.init(modelVersion: 42)) { version in
      XCTAssertEqual(version, 42)
      XCTAssertEqual(controller.runtime.installedModelVersion, 42)
      XCTAssertTrue(Thread.isMainThread)
      done.fulfill()
    }
    wait(for: [done], timeout: 2)
  }
  func testUnsupportedControllerManualActionAborts() {
    let controller = NativeInputController(profiles: CapabilityProfiles())
    XCTAssertEqual(controller.manualCorrection(), .aborted)
  }
}

private final class FacadeContext: ContextRefreshing {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 2, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
  func refresh() -> ContextToken? { token }
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
  func testPlainPasteUsesCapturedFocusInsteadOfCurrentFocus() {
    let context = FacadeContext()
    let selection = FacadeSelection()
    let clipboard = FacadeClipboard()
    let controller = NativeInputController(
      permissions: FacadePermissions(), editingContext: context, selectionAccess: selection)
    let original = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    XCTAssertEqual(controller.plainPaste(in: original, clipboard: clipboard), .aborted)
    XCTAssertEqual(selection.reads, 0)
    XCTAssertEqual(clipboard.reads, 0)
  }
}

private final class ManualLayouts: LayoutAccess {
  var value = LayoutID(rawValue: "US")
  func current() -> LayoutID? { value }
  func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool { value = id; return true }
}
private final class ManualEditor: SelectionAccess, ManualTrackedSuffixReplacing, ManualRepeatedSuffixReplacing {
  let context: FacadeContext
  var text = "ghbdtn"
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
  private func installedController(corpus: Bool = false) -> (NativeInputController, FacadeContext, ManualEditor) {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    let controller = NativeInputController(
      layouts: ManualLayouts(), permissions: FacadePermissions(), corpusQualified: corpus,
      editingContext: context, selectionAccess: editor)
    let installed = expectation(description: "manual mapping installed")
    controller.install(.init(modelVersion: 1,
      lexicon: [.init(word: "привет", language: .russian, frequencyBand: 1)],
      mappings: [.init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"),
        pairs: ["g": "п", "h": "р", "b": "и", "d": "в", "t": "е", "n": "т"])])) { _ in installed.fulfill() }
    wait(for: [installed], timeout: 2)
    return (controller, context, editor)
  }
  private func typeWord(_ controller: NativeInputController, context: FacadeContext) {
    for (n, pair) in zip([5, 4, 11, 2, 17, 45], Array("ghbdtn")).enumerated() {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(pair.0), modifiers: [],
        timestampNanos: UInt64(n), layout: .init(rawValue: "US"), context: context.token,
        origin: .physical, text: String(pair.1), isRepeat: false))
    }
  }
  func testEmptyProfilesStillAllowExplicitDoubleShiftForProvenTypedWord() {
    let (controller, context, editor) = installedController()
    let committed = expectation(description: "manual correction")
    controller.onResult = { result in XCTAssertEqual(result, .committed); committed.fulfill() }
    typeWord(controller, context: context)
    for (index, down) in [true, false, true, false].enumerated() {
      controller.runtime.accept(.init(kind: down ? .down : .up, keyCode: 56,
        modifiers: down ? [.shift] : [], timestampNanos: UInt64(index + 1) * 40_000_000,
        layout: .init(rawValue: "US"), context: context.token, origin: .physical,
        text: nil, isRepeat: false))
    }
    wait(for: [committed], timeout: 1)
    XCTAssertEqual(editor.text, "привет")
  }
  func testEmptyProfilesAllowExplicitSelectionConversion() {
    let (controller, _, editor) = installedController()
    editor.selectionLength = 6
    XCTAssertEqual(controller.manualCorrection(), .committed)
    XCTAssertEqual(editor.text, "привет")
  }
  func testCorpusQualificationDoesNotBypassMissingAutomaticProfile() {
    let (controller, context, editor) = installedController(corpus: true)
    typeWord(controller, context: context)
    let drained = expectation(description: "commands drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 1)
    XCTAssertEqual(editor.text, "ghbdtn")
  }
}

extension NativeInputControllerTests {
  func testManualRoleQualificationDoesNotDependOnApplicationProfile() {
    XCTAssertTrue(ContextMonitor.supportsManualRole("AXTextField"))
    XCTAssertTrue(ContextMonitor.supportsManualRole("AXTextArea"))
    XCTAssertFalse(ContextMonitor.supportsManualRole("AXWebArea"))
    XCTAssertFalse(ContextMonitor.supportsManualRole("AXButton"))
    XCTAssertFalse(ContextMonitor.supportsManualRole(""))
  }
  func testManualSelectionCannotBypassSecureInputOrPostPermission() {
    for secure in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.selectionLength = 6
      let permissions = FacadePermissions()
      permissions.secure = secure
      permissions.post = secure
      let controller = NativeInputController(layouts: ManualLayouts(), permissions: permissions,
        editingContext: context, selectionAccess: editor)
      XCTAssertEqual(controller.manualCorrection(), .aborted)
      XCTAssertEqual(editor.text, "ghbdtn")
    }
  }
}

extension NativeInputControllerTests {
  func testExplicitTrackedWordUsesEmptyProxyFallbackWithoutClaimingCommitOrUndo() {
    let (controller, context, editor) = installedController()
    editor.emptyProxy = true
    typeWord(controller, context: context)
    controller.onCommitted = { _, _ in XCTFail("Unverified dispatch must not record a correction") }
    XCTAssertEqual(controller.manualCorrection(), .dispatched)
    XCTAssertEqual(editor.text, "привет")
    XCTAssertEqual(editor.fallbackCalls, 1)
    XCTAssertNil(controller.runtime.manualWord())
    XCTAssertEqual(controller.undoLast(), .aborted)
  }
  func testFailedProvenReplacementNeverRetriesViaTrackedFallback() {
    let (controller, context, editor) = installedController()
    typeWord(controller, context: context)
    editor.replacementResult = .uncertain
    XCTAssertEqual(controller.manualCorrection(), .uncertain)
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
  func testManualConversionUsesActualTablesDespiteRejectedShippedMapping() {
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
    wait(for: [installed], timeout: 2)
    typeWord(controller, context: context)
    XCTAssertEqual(controller.manualCorrection(), .committed)
    XCTAssertEqual(editor.text, "привет")
  }
  func testManualSelectionNeedsNoRulePackageOrDictionary() {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.selectionLength = 6
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    XCTAssertEqual(controller.manualCorrection(), .committed)
    XCTAssertEqual(editor.text, "привет")
  }
}

extension NativeInputControllerTests {
  func testTypingDuringManualTableCaptureCancelsAction() {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.selectionLength = 6
    let capture = ManualCapture()
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: capture)
    capture.onCapture = { self.typeWord(controller, context: context) }
    XCTAssertEqual(controller.manualCorrection(), .aborted)
    XCTAssertEqual(editor.text, "ghbdtn")
  }
}

extension NativeInputControllerTests {
  func testSuccessiveManualWordsUsePhysicalLayoutWhenTapUnicodeIsStale() {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.emptyProxy = true
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    XCTAssertEqual(controller.manualCorrection(), .dispatched)
    XCTAssertEqual(editor.text, "привет")
    editor.text = "как"
    for code in [15, 3, 15] {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(code), modifiers: [],
        timestampNanos: 500, layout: .init(rawValue: "RU"), context: context.token,
        origin: .physical, text: code == 15 ? "r" : "f", isRepeat: false))
    }
    XCTAssertEqual(controller.manualCorrection(), .dispatched)
    XCTAssertEqual(editor.text, "rfr")
    editor.text = "ltkf"
    for (code, stale) in zip([37, 17, 40, 3], Array("дела")) {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(code), modifiers: [],
        timestampNanos: 1000, layout: .init(rawValue: "US"), context: context.token,
        origin: .physical, text: String(stale), isRepeat: false))
    }
    XCTAssertEqual(controller.manualCorrection(), .dispatched)
    XCTAssertEqual(editor.text, "дела")
  }
}
extension NativeInputControllerTests {
  func testPhysicalSourceReconstructionStillRequiresExactEditorSuffix() {
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
    XCTAssertEqual(controller.manualCorrection(), .aborted)
    XCTAssertEqual(editor.text, "unrelated")
    editor.text = "как"
    XCTAssertEqual(controller.manualCorrection(), .committed)
    XCTAssertEqual(editor.text, "rfr")
  }
}
extension NativeInputControllerTests {
  func testRepeatedDoubleShiftTogglesLastWordAtLeastFourTimesInReadableAndProxyFields() {
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
        wait(for: [converted], timeout: 1)
        XCTAssertEqual(editor.text, expected)
      }
    }
  }
  func testRepeatedConversionSurvivesSingleShiftBetweenPairsAndInitialSelection() {
    for initiallySelected in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.selectionLength = initiallySelected ? 6 : 0
      let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
      if !initiallySelected { typeWord(controller, context: context) }
      XCTAssertEqual(controller.manualCorrection(), .committed)
      editor.selectionLength = 0
      for turn in 0..<12 {
        if turn % 3 == 2 {
          let stamp = UInt64(turn + 1) * 1_000_000_000
          for (index, modifiers): (Int, Set<Modifier>) in [Set<Modifier>([.shift]), []].enumerated() {
            controller.runtime.accept(.init(kind: .flagsChanged, keyCode: 56, modifiers: modifiers,
              timestampNanos: stamp + UInt64(index), layout: controller.runtime.cachedInputContext()!.1,
              context: context.token, origin: .physical, text: nil, isRepeat: false))
          }
          controller.runtime.advance(to: stamp + 400_000_000)
          let delivered = expectation(description: "single Shift delivered")
          DispatchQueue.main.async { delivered.fulfill() }
          wait(for: [delivered], timeout: 1)
        }
        XCTAssertEqual(controller.manualCorrection(), .committed, "turn \(turn), selected \(initiallySelected)")
        XCTAssertEqual(editor.text, turn % 2 == 0 ? "ghbdtn" : "привет")
      }
    }
  }
  func testTwentyConversionsRetainWordWhenShiftArrivesDuringReplacement() {
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
      XCTAssertEqual(controller.manualCorrection(), .committed)
      XCTAssertEqual(editor.text, turn % 2 == 0 ? "привет" : "ghbdtn")
      XCTAssertNotNil(controller.runtime.manualRepeatCandidate())
    }
    editor.onReplace = nil
  }
  func testNavigationAndFocusChangeInvalidateRepeatedManualConversion() {
    for changeFocus in [false, true] {
      let context = FacadeContext()
      let editor = ManualEditor(context)
      editor.emptyProxy = true
      let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
        editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
      typeWord(controller, context: context)
      XCTAssertEqual(controller.manualCorrection(), .dispatched)
      if changeFocus {
        context.token = .init(pid: 42, bundleID: "test", focusEpoch: 3, layoutEpoch: 1)
      } else {
        controller.runtime.accept(.init(kind: .down, keyCode: 123, modifiers: [], timestampNanos: 900,
          layout: .init(rawValue: "RU"), context: context.token, origin: .physical,
          text: nil, isRepeat: false))
      }
      XCTAssertEqual(controller.manualCorrection(), .aborted)
      XCTAssertEqual(editor.text, "привет")
    }
  }
}

extension NativeInputControllerTests {
  func testRepeatedManualPreservesTrailingSpaceAndDirectPasteDiscardsCandidate() {
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
      XCTAssertEqual(controller.manualCorrection(), .dispatched)
      XCTAssertEqual(editor.text, expected)
    }
    _ = controller.plainPaste(clipboard: FacadeClipboard())
    XCTAssertEqual(controller.manualCorrection(), .aborted)
    XCTAssertEqual(editor.text, "привет ")
  }
}
extension NativeInputControllerTests {
  func testDirectPasteDiscardsPrePasteAutomaticBufferBeforeNextSpace() {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.emptyProxy = true
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: FacadePermissions(),
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    _ = controller.plainPaste(clipboard: FacadeClipboard())
    controller.runtime.accept(.init(kind: .down, keyCode: 49, modifiers: [], timestampNanos: 100,
      layout: .init(rawValue: "US"), context: context.token, origin: .physical, text: " ", isRepeat: false))
    XCTAssertNil(controller.runtime.manualWord())
    XCTAssertEqual(controller.manualCorrection(), .aborted)
  }
  func testPermissionDeniedDoubleShiftDiscardsRepeatBeforePermissionsReturn() {
    let context = FacadeContext()
    let editor = ManualEditor(context)
    editor.emptyProxy = true
    let permissions = FacadePermissions()
    let controller = NativeInputController(layouts: ManualLayouts(), permissions: permissions,
      editingContext: context, selectionAccess: editor, layoutCapture: ManualCapture())
    typeWord(controller, context: context)
    XCTAssertEqual(controller.manualCorrection(), .dispatched)
    permissions.secure = true
    for (index, down) in [true, false, true, false].enumerated() {
      controller.runtime.accept(.init(kind: down ? .down : .up, keyCode: 56,
        modifiers: down ? [.shift] : [], timestampNanos: 1_000_000_000 + UInt64(index) * 40_000_000,
        layout: .init(rawValue: "RU"), context: context.token, origin: .physical, text: nil, isRepeat: false))
    }
    let drained = expectation(description: "permission-denied gesture dispatched")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 1)
    permissions.secure = false
    XCTAssertNil(controller.runtime.manualRepeatCandidate())
    XCTAssertEqual(controller.manualCorrection(), .aborted)
    XCTAssertEqual(editor.text, "привет")
  }
}
