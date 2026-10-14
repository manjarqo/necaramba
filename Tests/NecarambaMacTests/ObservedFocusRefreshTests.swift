import XCTest
import NecarambaCore
@testable import NecarambaMac

final class ObservedFocusRefreshTests: XCTestCase {
  func testAppFocusLayoutChangeSynchronizesRuntimeBeforeTyping() throws {
    let state = ContextState()
    let source = LayoutID(rawValue: "US")
    let target = LayoutID(rawValue: "RU")
    state.update(pid: 1, bundleID: "first", focusID: "first", layout: source, qualified: true)
    let runtime = InputRuntime(context: state, initialLayout: source)
    ObservedFocusRefresh.perform(state: state, refresh: {
      state.update(pid: 2, bundleID: "second", focusID: "second", layout: target, qualified: true)
      return state.publishedCurrent()
    }, synchronizeLayout: {
      XCTAssertNotNil(state.current())
      runtime.updateLayout(target)
    })
    XCTAssertEqual(runtime.cachedInputContext()?.1, target)
  }
  func testRepeatedSameLayoutObservationPreservesInputGenerationAndVisibleContext() throws {
    let state = ContextState()
    let layout = LayoutID(rawValue: "US")
    state.update(pid: 1, bundleID: "test", focusID: "field", layout: layout, qualified: true)
    let runtime = InputRuntime(context: state, initialLayout: layout)
    let before = try XCTUnwrap(state.current())
    let generation = runtime.inputGeneration()
    var synchronized = 0
    for _ in 0..<3 {
      ObservedFocusRefresh.perform(state: state, refresh: {
        state.update(pid: 1, bundleID: "test", focusID: "field", layout: layout, qualified: true)
        return state.publishedCurrent()
      }, synchronizeLayout: {
        XCTAssertEqual(runtime.cachedInputContext()?.0, before)
        runtime.updateLayout(layout)
        synchronized += 1
      })
    }
    XCTAssertEqual(synchronized, 3)
    XCTAssertEqual(runtime.inputGeneration(), generation)
    XCTAssertEqual(state.current(), before)
  }
}
