import AppKit
import ApplicationServices
import XCTest
@testable import NecarambaMac

final class FocusedElementResolverTests: XCTestCase {
  func testSystemFocusResolvesOverlayOwnerWithoutFrontmostApplication() {
    let overlay = AXUIElementCreateApplication(4321)
    let resolver = AXFocusedElementResolver(
      focusedElement: { _ in (.success, overlay) },
      processID: { _ in 4321 }, bundleID: { $0 == 4321 ? "test.search.overlay" : nil })
    let result = resolver.resolve(deadline: ProcessInfo.processInfo.systemUptime + 1)
    XCTAssertEqual(result.focus?.pid, 4321)
    XCTAssertEqual(result.focus?.bundleID, "test.search.overlay")
    XCTAssertTrue(result.focus.map { CFEqual($0.element, overlay) } ?? false)
  }

  func testUnderlyingApplicationCannotReadOverlayAsItsOwnFocus() {
    let overlay = AXUIElementCreateApplication(4321)
    let resolver = AXFocusedElementResolver(
      focusedElement: { _ in (.success, overlay) },
      processID: { _ in 4321 }, bundleID: { _ in "test.search.overlay" })
    XCTAssertNil(resolver.resolve(expectedPID: 1234, deadline: ProcessInfo.processInfo.systemUptime + 1).focus)
    XCTAssertNotNil(resolver.resolve(expectedPID: 4321, deadline: ProcessInfo.processInfo.systemUptime + 1).focus)
  }

  func testMissingFocusOrUnidentifiedOwnerCannotFallBackToUnderlyingApp() {
    let element = AXUIElementCreateApplication(4321)
    for status in [AXError.noValue, .cannotComplete] {
      let resolver = AXFocusedElementResolver(
        focusedElement: { _ in (status, nil) }, processID: { _ in 4321 }, bundleID: { _ in "test.app" })
      let result = resolver.resolve(deadline: ProcessInfo.processInfo.systemUptime + 1)
      XCTAssertNil(result.focus)
      XCTAssertEqual(result.status, status)
    }
    let unidentified = AXFocusedElementResolver(
      focusedElement: { _ in (.success, element) }, processID: { _ in nil }, bundleID: { _ in "test.app" })
    XCTAssertNil(unidentified.resolve(deadline: ProcessInfo.processInfo.systemUptime + 1).focus)
  }
}
