import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class ClipboardSelectionControllerTests: XCTestCase {
  private func controller(bundleID: String = "test", terminalProxy: Bool = false,
                          outcome: ClipboardSelectionOutcome)
    -> (NativeInputController, ClipContext, ClipLayouts, ClipConverter) {
    let context = ClipContext(bundleID: bundleID)
    let layouts = ClipLayouts(context)
    let converter = ClipConverter(outcome: outcome)
    let controller = NativeInputController(layouts: layouts, permissions: ClipPermissions(),
      conservativeAutomaticEnabled: true, editingContext: context,
      selectionAccess: OpaqueClipEditor(context, terminalProxy: terminalProxy),
      layoutCapture: ClipCapture(), clipboardSelection: converter)
    return (controller, context, layouts, converter)
  }

  func testOpaqueFieldWithoutTypedWordConvertsSelectionThroughClipboard() async {
    let (controller, _, layouts, converter) = controller(outcome: .dispatched)
    let result = await controller.manualCorrectionAsync()
    XCTAssertEqual(converter.calls, 1)
    XCTAssertEqual(converter.prepared?.text, "привет")
    XCTAssertEqual(converter.prepared?.context.layoutEpoch, 2, "Paste targets the refreshed layout context")
    XCTAssertEqual(result, .dispatched)
    XCTAssertEqual(layouts.value.rawValue, "RU")
  }

  func testTerminalsNeverUseClipboardSelection() async {
    for (bundle, proxy) in [("test", true), ("com.apple.Terminal", false), ("com.googlecode.iterm2", false)] {
      let (controller, _, _, converter) = controller(bundleID: bundle, terminalProxy: proxy, outcome: .dispatched)
      let result = await controller.manualCorrectionAsync()
      XCTAssertEqual(converter.calls, 0, bundle)
      XCTAssertEqual(result, .aborted)
    }
  }

  func testNoSelectionOrAbortKeepsTheTypingLayout() async {
    for outcome in [ClipboardSelectionOutcome.noSelection, .aborted] {
      let (controller, _, layouts, converter) = controller(outcome: outcome)
      let result = await controller.manualCorrectionAsync()
      XCTAssertEqual(converter.calls, 1)
      XCTAssertEqual(result, .aborted)
      XCTAssertEqual(layouts.value.rawValue, "US", "\(outcome)")
    }
  }
}

@MainActor private final class ClipConverter: ClipboardSelectionConverting {
  let outcome: ClipboardSelectionOutcome
  private(set) var calls = 0
  private(set) var prepared: (text: String, context: ContextToken)?
  init(outcome: ClipboardSelectionOutcome) { self.outcome = outcome }
  func convert(in token: ContextToken, generation: UInt64, valid: @escaping () -> Bool,
               prepare: (String) async -> (text: String, context: ContextToken)?) async -> ClipboardSelectionOutcome {
    calls += 1
    guard outcome != .noSelection, valid() else { return outcome }
    prepared = await prepare("ghbdtn")
    XCTAssertTrue(valid(), "Our own layout switch must not invalidate the operation")
    return outcome
  }
}
private final class ClipContext: ContextRefreshing {
  var token: ContextToken
  init(bundleID: String) { token = .init(pid: 42, bundleID: bundleID, focusEpoch: 1, layoutEpoch: 1) }
  func current() -> ContextToken? { token }
  func refresh() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
}
private final class ClipLayouts: LayoutAccess {
  let context: ClipContext
  var value = LayoutID(rawValue: "US")
  init(_ context: ClipContext) { self.context = context }
  func current() -> LayoutID? { value }
  func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool {
    if id != value {
      value = id
      let old = context.token
      context.token = .init(pid: old.pid, bundleID: old.bundleID, focusEpoch: old.focusEpoch, layoutEpoch: old.layoutEpoch + 1)
    }
    return true
  }
}
private final class ClipPermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: true, post: true, ax: true, secureInput: false) }
  func request(_ kind: PermissionKind) { XCTFail("No TCC requests") }
}
private final class OpaqueClipEditor: SelectionAccess, OpaqueFocusReading {
  let context: ClipContext
  let terminalProxy: Bool
  let identity = UUID()
  init(_ context: ClipContext, terminalProxy: Bool) { self.context = context; self.terminalProxy = terminalProxy }
  func selected(in context: ContextToken) -> SelectionEvidence? { nil }
  func suffix(_ text: String, in context: ContextToken) -> SelectionEvidence? { nil }
  func replace(_ evidence: SelectionEvidence, with text: String) -> ApplyResult { .aborted }
  func replaceAsync(_ evidence: SelectionEvidence, with text: String) async -> ApplyResult { .aborted }
  func opaqueFocus(in token: ContextToken) -> OpaqueFocusProof? {
    guard token == context.token else { return nil }
    return .init(context: token, identity: identity, selection: .unavailable, terminalProxy: terminalProxy)
  }
}
private final class ClipCapture: LayoutTableCapturing {
  func captureTables() -> CapturedLayoutTables {
    let codes: [UInt16] = [12,13,14,15,17,16,32,34,31,35,33,30,0,1,2,3,5,4,38,40,37,41,39,6,7,8,9,11,45,46,43,47,44]
    return .init(layouts: zip(["US", "RU"], ["qwertyuiop[]asdfghjkl;'zxcvbnm,./", "йцукенгшщзхъфывапролджэячсмитьбю."]).map { id, chars in
      .init(id: .init(rawValue: id), entries: zip(codes, chars).map { .init(keyCode: $0.0, modifiers: [], text: String($0.1)) })
    })
  }
}
