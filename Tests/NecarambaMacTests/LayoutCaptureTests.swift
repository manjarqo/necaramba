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
  func testPhysicalVersionTranslationPreservesDigitsInBothDirections() throws {
    let ru = LayoutID(rawValue: "RU"), en = LayoutID(rawValue: "US")
    let entries: [(UInt16, String, String)] = [(18, "1", "1"), (20, "3", "3"), (22, "6", "6"), (47, "ю", ".")]
    let tables = CapturedLayoutTables(layouts: [
      .init(id: ru, entries: entries.map { .init(keyCode: $0.0, modifiers: [], text: $0.1) }),
      .init(id: en, entries: entries.map { .init(keyCode: $0.0, modifiers: [], text: $0.2) })
    ])
    let context = ContextToken(pid: 42, bundleID: "test", focusEpoch: 1, layoutEpoch: 1)
    for (source, target, expected) in [(ru, en, "1.3.166"), (en, ru, "1ю3ю166")] {
      let events = [18,47,20,47,18,22,22].map { code in
        InputEvent(kind: .down, keyCode: UInt16(code), modifiers: [], timestampNanos: 1,
          layout: source, context: context, origin: .physical, text: "stale", isRepeat: false)
      }
      let word = BufferedWord(text: "stale", events: events, context: context, layout: source, delimiter: " ")
      let conversion = try XCTUnwrap(tables.manualConversion(word, target: target))
      XCTAssertEqual(conversion.replacement, expected)
      XCTAssertEqual(conversion.word.delimiter, " ")
    }
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
extension LayoutCaptureTests {
  func testManualPhysicalMappingPreservesCaseAndLeavesAmbiguousCharactersAlone() throws {
    let us = LayoutID(rawValue: "US")
    let ru = LayoutID(rawValue: "RU")
    let tables = CapturedLayoutTables(layouts: [
      .init(id: us, entries: [
        .init(keyCode: 5, modifiers: [], text: "g"),
        .init(keyCode: 5, modifiers: [.shift], text: "G"),
        .init(keyCode: 1, modifiers: [], text: "x"),
        .init(keyCode: 2, modifiers: [], text: "x")]),
      .init(id: ru, entries: [
        .init(keyCode: 5, modifiers: [], text: "п"),
        .init(keyCode: 5, modifiers: [.shift], text: "П"),
        .init(keyCode: 1, modifiers: [], text: "а"),
        .init(keyCode: 2, modifiers: [], text: "б")])
    ])
    let mapping = try XCTUnwrap(tables.manualMapping(source: us, target: ru))
    XCTAssertEqual(LayoutConverter.convert("gGx", mapping: mapping), "пПx")
    XCTAssertNil(tables.manualMapping(source: us, target: .init(rawValue: "missing")))
  }
}
extension LayoutCaptureTests {
  func testAvailableSourceChangeInvalidatesSharedCaptureAndRecaptures() {
    var captures = 0
    let controller = NativeInputController(layoutCapture: CaptureSpy(onCapture: { captures += 1 }))
    let first = expectation(description: "first install")
    controller.install(.init(modelVersion: 17)) { _ in first.fulfill() }
    wait(for: [first], timeout: 3)
    let second = expectation(description: "shared capture install")
    controller.install(.init(modelVersion: 18)) { _ in second.fulfill() }
    wait(for: [second], timeout: 3)
    XCTAssertEqual(captures, 1)
    let generation = controller.runtime.inputGeneration()
    let refreshed = expectation(description: "recaptured source list")
    controller.onAutomaticReadinessChanged = { _ in refreshed.fulfill() }
    controller.context.onAvailableLayoutsChanged?()
    wait(for: [refreshed], timeout: 3)
    XCTAssertEqual(captures, 2)
    XCTAssertGreaterThan(controller.runtime.inputGeneration(), generation)
    XCTAssertEqual(controller.runtime.installedModelVersion, 18)
  }
}
extension LayoutCaptureTests {
  func testSourceListChangeCannotPublishInFlightOldCapture() {
    let entered = expectation(description: "old capture compiling")
    let released = expectation(description: "superseded callback completed")
    let installed = expectation(description: "new capture installed")
    let gate = DispatchSemaphore(value: 0)
    var builds = 0
    var captures = 0
    let controller = NativeInputController(
      layoutCapture: CaptureSpy(onCapture: { captures += 1 }),
      engineBuilder: BuilderSpy(onBuild: {
        builds += 1
        if builds == 1 { entered.fulfill(); _ = gate.wait(timeout: .now() + 3) }
      }))
    controller.install(.init(modelVersion: 23)) { version in
      XCTAssertEqual(version, 0, "Superseded completion reports actual currently installed version")
      released.fulfill()
    }
    wait(for: [entered], timeout: 3)
    var publications = 0
    controller.onAutomaticReadinessChanged = { _ in publications += 1; installed.fulfill() }
    controller.context.onAvailableLayoutsChanged?()
    gate.signal()
    wait(for: [released, installed], timeout: 3)
    XCTAssertEqual(publications, 1)
    XCTAssertEqual(captures, 2)
    XCTAssertEqual(controller.runtime.installedModelVersion, 23)
  }
}
