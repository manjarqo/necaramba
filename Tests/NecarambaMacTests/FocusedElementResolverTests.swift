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
  func testVirtualSuggestionResolvesToProvenKeyboardOwner() throws {
    let suggestion = AXUIElementCreateApplication(123)
    let owner = AXUIElementCreateApplication(124)
    let resolver = AXFocusedElementResolver(focusedElement: { _ in (.success, suggestion) },
      processID: { _ in 4321 }, bundleID: { _ in "com.vscodium" },
      keyboardOwner: { _, _ in owner })
    let resolved = try XCTUnwrap(resolver.resolve(expectedPID: 4321, deadline: 1).focus)
    XCTAssertTrue(CFEqual(resolved.element, owner))
  }
  func testVirtualOwnerCannotCrossProcessBoundary() {
    let suggestion = AXUIElementCreateApplication(123)
    let owner = AXUIElementCreateApplication(124)
    let resolver = AXFocusedElementResolver(focusedElement: { _ in (.success, suggestion) },
      processID: { CFEqual($0, suggestion) ? 4321 : 9999 }, bundleID: { _ in "com.vscodium" },
      keyboardOwner: { _, _ in owner })
    XCTAssertNil(resolver.resolve(expectedPID: 4321, deadline: 1).focus)
  }
  func testVirtualOwnerCannotOutliveChangedOrUnavailableSystemFocus() {
    let suggestion = AXUIElementCreateApplication(123)
    let owner = AXUIElementCreateApplication(124)
    for status in [AXError.success, .cannotComplete] {
      var reads = 0
      let resolver = AXFocusedElementResolver(focusedElement: { _ in
        reads += 1
        return reads == 1 ? (.success, suggestion) : (status, owner)
      }, processID: { _ in 4321 }, bundleID: { _ in "com.vscodium" }, keyboardOwner: { _, _ in owner })
      XCTAssertNil(resolver.resolve(deadline: 1).focus)
    }
  }

  func testOwnerRelationshipMustRemainStableAfterSystemFocusConfirmation() {
    let raw = AXUIElementCreateApplication(123)
    let owner = AXUIElementCreateApplication(124)
    var reads = 0
    let resolver = AXFocusedElementResolver(focusedElement: { _ in (.success, raw) },
      processID: { _ in 4321 }, bundleID: { _ in "com.vscodium" },
      keyboardOwner: { _, _ in reads += 1; return reads == 1 ? owner : raw })
    XCTAssertNil(resolver.resolve(deadline: 1).focus)
  }

}
