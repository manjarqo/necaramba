import ApplicationServices
import XCTest
@testable import NecarambaMac

final class KeyboardFocusOwnerTests: XCTestCase {
  func testVirtualRowUsesOnlyFocusedEditableOwner() {
    let row = AXUIElementCreateApplication(123)
    let editor = AXUIElementCreateApplication(124)
    for focused in [true, false] {
      let resolver = AXKeyboardFocusOwner { node, key, _ in
        switch key {
        case kAXRoleAttribute: return (CFEqual(node, row) ? "AXRow" : "AXTextArea") as CFString
        case kAXFocusedUIElementAttribute: return editor
        case kAXFocusedAttribute: return focused ? kCFBooleanTrue : kCFBooleanFalse
        default: return nil
        }
      }
      XCTAssertTrue(CFEqual(resolver.resolve(row, deadline: 1), focused ? editor : row))
    }
  }
  func testMissingOwnerOrNoneditableOwnerDoesNotAuthorizeContainer() {
    let row = AXUIElementCreateApplication(123)
    let other = AXUIElementCreateApplication(124)
    for role in ["AXButton", "AXGroup", "AXWebArea"] {
      let resolver = AXKeyboardFocusOwner { node, key, _ in
        switch key {
        case kAXRoleAttribute: return (CFEqual(node, row) ? "AXRow" : role) as CFString
        case kAXFocusedUIElementAttribute: return other
        case kAXFocusedAttribute: return kCFBooleanTrue
        default: return nil
        }
      }
      XCTAssertTrue(CFEqual(resolver.resolve(row, deadline: 1), row))
    }
    XCTAssertTrue(CFEqual(AXKeyboardFocusOwner(attribute: { _, _, _ in nil }).resolve(row, deadline: 1), row))
  }
  func testEditableRawFocusIsNeverRedirectedAndMalformedFocusIsRejected() {
    let raw = AXUIElementCreateApplication(123)
    let owner = AXUIElementCreateApplication(124)
    let direct = AXKeyboardFocusOwner { _, key, _ in
      XCTAssertEqual(key, kAXRoleAttribute)
      return "AXTextArea" as CFString
    }
    XCTAssertTrue(CFEqual(direct.resolve(raw, deadline: 1), raw))
    for malformedRelation in [true, false] {
      let resolver = AXKeyboardFocusOwner { node, key, _ in
        switch key {
        case kAXRoleAttribute: return (CFEqual(node, raw) ? "AXRow" : "AXTextArea") as CFString
        case kAXFocusedUIElementAttribute: return malformedRelation ? "invalid" as CFString : owner
        case kAXFocusedAttribute: return "true" as CFString
        default: return nil
        }
      }
      XCTAssertTrue(CFEqual(resolver.resolve(raw, deadline: 1), raw))
    }
  }
  func testEditableAncestorResolvesWithoutPretendingAncestorHasAXFocus() {
    let raw = AXUIElementCreateApplication(123)
    let editor = AXUIElementCreateApplication(124)
    var ancestorReads = 0
    let resolver = AXKeyboardFocusOwner { node, key, _ in
      switch key {
      case kAXRoleAttribute: return (CFEqual(node, raw) ? "AXStaticText" : "AXTextArea") as CFString
      case "AXEditableAncestor": ancestorReads += 1; return editor
      case kAXFocusedUIElementAttribute: return raw
      case kAXFocusedAttribute: return kCFBooleanFalse
      default: return nil
      }
    }
    XCTAssertTrue(CFEqual(resolver.resolve(raw, deadline: 1), editor))
    XCTAssertEqual(ancestorReads, 2)
  }
  func testEditableAncestorRejectsMalformedNoneditableAndChangingRelationships() {
    let raw = AXUIElementCreateApplication(123)
    let editor = AXUIElementCreateApplication(124)
    for mode in 0..<3 {
      var reads = 0
      let resolver = AXKeyboardFocusOwner { node, key, _ in
        switch key {
        case kAXRoleAttribute:
          return (CFEqual(node, raw) ? "AXStaticText" : (mode == 1 ? "AXGroup" : "AXTextArea")) as CFString
        case "AXEditableAncestor":
          reads += 1
          if mode == 0 { return "invalid" as CFString }
          return reads == 1 ? editor : raw
        default: return nil
        }
      }
      XCTAssertTrue(CFEqual(resolver.resolve(raw, deadline: 1), raw))
    }
  }

  func testEditableAncestorRejectsSecureOrMalformedSubroleOnEitherElement() {
    let raw = AXUIElementCreateApplication(123)
    let editor = AXUIElementCreateApplication(124)
    for secureRaw in [true, false] {
      for malformed in [true, false] {
        let resolver = AXKeyboardFocusOwner { node, key, _ in
          switch key {
          case kAXRoleAttribute: return (CFEqual(node, raw) ? "AXStaticText" : "AXTextArea") as CFString
          case "AXEditableAncestor": return editor
          case kAXSubroleAttribute:
            guard CFEqual(node, raw) == secureRaw else { return nil }
            return malformed ? kCFBooleanTrue : kAXSecureTextFieldSubrole as CFString
          default: return nil
          }
        }
        XCTAssertTrue(CFEqual(resolver.resolve(raw, deadline: 1), raw))
      }
    }
  }

}
