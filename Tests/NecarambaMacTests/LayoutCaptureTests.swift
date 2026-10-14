import NecarambaCore
import XCTest

@testable import NecarambaMac

final class LayoutCaptureTests: XCTestCase {
  func testCaptureMainAndBuildBackgroundBeforeInstallCompletion() {
    let done = expectation(description: "installed")
    let captured = expectation(description: "capture")
    let built = expectation(description: "build")
    let controller = NativeInputController(
      layoutCapture: CaptureSpy(onCapture: {
        XCTAssertTrue(Thread.isMainThread)
        captured.fulfill()
      }),
      engineBuilder: BuilderSpy(onBuild: {
        XCTAssertFalse(Thread.isMainThread)
        built.fulfill()
      }))
    controller.install(.init(modelVersion: 17)) { version in
      XCTAssertEqual(version, 17)
      XCTAssertTrue(Thread.isMainThread)
      done.fulfill()
    }
    wait(for: [captured, built, done], timeout: 3)
  }
  func testAliasResolutionAndPhysicalMappingsArePureBackgroundWork() {
    let tables = CapturedLayoutTables(layouts: [
      .init(
        id: .init(rawValue: "actual.en"), entries: [.init(keyCode: 5, modifiers: [], text: "g")]),
      .init(
        id: .init(rawValue: "actual.ru"), entries: [.init(keyCode: 5, modifiers: [], text: "п")]),
    ])
    let snapshot = RuleSnapshot(
      modelVersion: 3,
      mappings: [
        .init(source: .init(rawValue: "US"), target: .init(rawValue: "RU"), pairs: ["g": "п"])
      ])
    let done = expectation(description: "pure resolution")
    DispatchQueue.global().async {
      XCTAssertFalse(Thread.isMainThread)
      let actual = tables.resolve(snapshot)
      XCTAssertEqual(actual.mappings.first?.source.rawValue, "actual.en")
      XCTAssertEqual(actual.mappings.first?.target.rawValue, "actual.ru")
      XCTAssertEqual(tables.physicalMappings(for: actual).first?.entries.first?.text, "п")
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }
  func testRealTISCaptureIsReadOnlyAndRunsOnMain() {
    XCTAssertTrue(Thread.isMainThread)
    let capture = TISLayoutAdapter().captureTables()
    XCTAssertLessThanOrEqual(capture.layouts.count, 32)
  }
}
private final class CaptureSpy: LayoutTableCapturing {
  let onCapture: () -> Void
  init(onCapture: @escaping () -> Void) { self.onCapture = onCapture }
  func captureTables() -> CapturedLayoutTables {
    onCapture()
    return .init(layouts: [])
  }
}
private final class BuilderSpy: RuleEngineBuilding {
  let onBuild: () -> Void
  init(onBuild: @escaping () -> Void) { self.onBuild = onBuild }
  func build(snapshot: RuleSnapshot, physicalMappings: [PhysicalLayoutMapping]) -> LinguisticEngine
  {
    onBuild()
    return .init(snapshot: snapshot, physicalMappings: physicalMappings)
  }
}
