import XCTest
import NecarambaCore
@testable import NecarambaMac

final class LayoutAdapterTests: XCTestCase {
    func testSwitchRequiresReadbackAndBoundedRetries() {
        let fake = LayoutStub()
        let switcher = VerifiedLayoutSwitcher(access: fake, maxAttempts: 3, sleeper: { _ in })
        XCTAssertFalse(switcher.select(LayoutID(rawValue: "RU")))
        XCTAssertEqual(fake.attempts, 3)
        fake.reallySelect = true
        XCTAssertTrue(switcher.select(LayoutID(rawValue: "RU")))
        XCTAssertEqual(fake.attempts, 4)
    }
    func testAlreadySelectedDoesNotPostSelection() {
        let fake = LayoutStub()
        XCTAssertTrue(VerifiedLayoutSwitcher(access: fake).select(LayoutID(rawValue: "US")))
        XCTAssertEqual(fake.attempts, 0)
    }
    func testUnknownLayoutNeverSelects() {
        let fake = LayoutStub()
        XCTAssertFalse(VerifiedLayoutSwitcher(access: fake).select(LayoutID(rawValue: "IME")))
        XCTAssertEqual(fake.attempts, 0)
    }
    func testFocusAndLayoutChangesInvalidateTokens() {
        let state = ContextState()
        state.update(pid: 42, bundleID: "test.editor", focusID: "first", layout: LayoutID(rawValue:"US"), qualified: true)
        let first = state.current()!
        state.update(pid: 42, bundleID: "test.editor", focusID: "second", layout: LayoutID(rawValue:"US"), qualified: true)
        XCTAssertFalse(state.isSafe(first))
        let second = state.current()!
        state.update(pid: 42, bundleID: "test.editor", focusID: "second", layout: LayoutID(rawValue:"RU"), qualified: true)
        XCTAssertFalse(state.isSafe(second))
        state.invalidate(.secureInput)
        XCTAssertNil(state.current())
    }
}
private final class LayoutStub: LayoutAccess {
    var value = LayoutID(rawValue: "US")
    var attempts = 0
    var reallySelect = false
    func current() -> LayoutID? { value }
    func supported() -> [LayoutID] { [.init(rawValue: "US"), .init(rawValue: "RU")] }
    func select(_ id: LayoutID) -> Bool { attempts += 1; if reallySelect { value = id }; return true }
}

extension LayoutAdapterTests {
  @MainActor func testAsyncLateReadbackAndCancellationNeverRetries() async {
    let fake = LayoutStub()
    let target = LayoutID(rawValue: "RU")
    var waits = 0
    let switcher = VerifiedLayoutSwitcher(access: fake, scheduler: { delay in
      XCTAssertEqual(delay, 0.02)
      waits += 1
      fake.value = target
    })
    let result = await switcher.selectAsync(target)
    XCTAssertTrue(result)
    XCTAssertEqual(fake.attempts, 1)
    XCTAssertEqual(waits, 1)
    fake.value = .init(rawValue: "US")
    var valid = true
    let cancelled = VerifiedLayoutSwitcher(access: fake, scheduler: { _ in valid = false })
    let cancelledResult = await cancelled.selectAsync(target, authorized: { valid })
    XCTAssertFalse(cancelledResult)
    XCTAssertEqual(fake.attempts, 2)
  }
}

extension LayoutAdapterTests {
  @MainActor func testAsyncAlreadySelectedUnsupportedAndExhaustedReadback() async {
    let access = LayoutStub()
    var waits = 0
    let switcher = VerifiedLayoutSwitcher(access: access, scheduler: { _ in waits += 1 })
    let already = await switcher.selectAsync(.init(rawValue: "US"))
    let unsupported = await switcher.selectAsync(.init(rawValue: "IME"))
    XCTAssertTrue(already)
    XCTAssertFalse(unsupported)
    XCTAssertEqual(access.attempts, 0)
    let failed = await switcher.selectAsync(.init(rawValue: "RU"))
    XCTAssertFalse(failed)
    XCTAssertEqual(access.attempts, 3)
    XCTAssertEqual(waits, 2)
  }
}
