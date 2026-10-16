import XCTest
import NecarambaCore
@testable import NecarambaMac

@MainActor final class OpaqueControllerIntegrationTests: XCTestCase {
  func testOpaqueManualConversionRetainsIdentityForRepeatWithoutCommitCounterOrUndoJournal() async {
    await assertRepeatUsesDispatchedIdentity(changeIdentityBeforeDispatch: false)
  }
  func testRepeatRetainsActualDispatchIdentityWhenPreliminaryFocusWasDifferent() async {
    await assertRepeatUsesDispatchedIdentity(changeIdentityBeforeDispatch: true)
  }
  private func assertRepeatUsesDispatchedIdentity(changeIdentityBeforeDispatch: Bool) async {
    let context = OpaqueControllerContext()
    let reader = OpaqueControllerReader()
    reader.changeIdentityBeforeDispatch = changeIdentityBeforeDispatch
    let adapter = AXSelectionAdapter(context: context, qualifies: { _, _ in true }, reader: reader,
      allowMissingMarkedTextRange: { true })
    let layouts = OpaqueControllerLayouts(context: context)
    let controller = NativeInputController(layouts: layouts, permissions: OpaqueControllerPermissions(),
      editingContext: context, selectionAccess: adapter)
    adapter.inputGeneration = { controller.runtime.inputGeneration() }
    var posted: [String] = []
    adapter.executePhysicalAsync = { _, text, valid in
      guard valid() else { return .aborted }
      XCTAssertEqual(layouts.current()?.rawValue, text == "привет" ? "RU" : "US")
      posted.append(text); return .committed
    }
    let installed = expectation(description: "mapping installed")
    controller.install(.init(modelVersion: 1, mappings: [
      .init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"),
        pairs: ["g": "п", "h": "р", "b": "и", "d": "в", "t": "е", "n": "т"]),
      .init(source: .init(rawValue: "RU"), target: .init(rawValue: "US"),
        pairs: ["п": "g", "р": "h", "и": "b", "в": "d", "е": "t", "т": "n"])
    ])) { _ in installed.fulfill() }
    await fulfillment(of: [installed], timeout: 2)
    for (index, pair) in zip([5, 4, 11, 2, 17, 45], Array("ghbdtn")).enumerated() {
      controller.runtime.accept(.init(kind: .down, keyCode: UInt16(pair.0), modifiers: [],
        timestampNanos: UInt64(index), layout: .init(rawValue: "US"), context: context.token,
        origin: .physical, text: String(pair.1), isRepeat: false))
    }
    var commits = 0
    controller.onCommitted = { _, _ in commits += 1 }
    let first = await controller.manualCorrectionAsync()
    XCTAssertEqual(first, .dispatched)
    XCTAssertEqual(controller.runtime.manualRepeatCandidate()?.fieldIdentity, reader.identity)
    let repeated = await controller.manualCorrectionAsync()
    XCTAssertEqual(repeated, .dispatched)
    XCTAssertEqual(posted, ["привет", "ghbdtn"])
    XCTAssertEqual(commits, 0)
    let undo = await controller.undoLastAsync()
    XCTAssertEqual(undo, .aborted)
    XCTAssertEqual(posted.count, 2)
  }
}
private final class OpaqueControllerContext: ContextRefreshing {
  var token = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
  func current() -> ContextToken? { token }
  func refresh() -> ContextToken? { token }
  func isSafe(_ token: ContextToken) -> Bool { token == self.token }
}
private final class OpaqueControllerReader: AXSelectionReading {
  var identity = UUID()
  var changeIdentityBeforeDispatch = false
  private var reads = 0
  func read(in token: ContextToken) -> AXTextSnapshot? {
    reads += 1
    // The first selected/suffix queries precede the dispatch adapter's preflight.
    if changeIdentityBeforeDispatch && reads == 3 { identity = UUID() }
    return nil
  }
  func observe(in token: ContextToken, deadline: TimeInterval) -> AXSelectionObservation {
    .opaque(.init(context: token, identity: identity, selection: .unavailable))
  }
}
private final class OpaqueControllerLayouts: LayoutAccess {
  let context: OpaqueControllerContext
  init(context: OpaqueControllerContext) { self.context = context }
  var value = LayoutID(rawValue: "US")
  func current() -> LayoutID? { value }
  func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
  func select(_ id: LayoutID) -> Bool {
    value = id
    context.token = .init(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: context.token.layoutEpoch + 1)
    return true
  }
}
private final class OpaqueControllerPermissions: PermissionReading {
  func current() -> PermissionState { .init(listen: true, post: true, ax: true, secureInput: false) }
  func request(_ kind: PermissionKind) { XCTFail("Tests cannot request real permissions") }
}
