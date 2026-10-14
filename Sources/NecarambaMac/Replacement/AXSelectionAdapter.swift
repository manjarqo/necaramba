import AppKit
import ApplicationServices
import NecarambaCore
/// The only supported native edit strategy is a qualified, settable AX value/range.
public final class AXSelectionAdapter:SelectionAccess {
 private let context:ContextAccess
 private let qualifies:(String,String)->Bool
 public init(context:ContextAccess,qualifies:@escaping(String,String)->Bool) { self.context=context; self.qualifies=qualifies }
 private struct State { let element:AXUIElement; let value:String; let range:NSRange }
 private func state(_ token:ContextToken)->State? {
  precondition(Thread.isMainThread)
  guard context.isSafe(token),NSWorkspace.shared.frontmostApplication?.processIdentifier==token.pid else { return nil }
  let app=AXUIElementCreateApplication(token.pid); AXUIElementSetMessagingTimeout(app,0.1)
  var focused:CFTypeRef?
  guard AXUIElementCopyAttributeValue(app,kAXFocusedUIElementAttribute as CFString,&focused) == .success,let focused,CFGetTypeID(focused)==AXUIElementGetTypeID() else { return nil }
  let element=unsafeBitCast(focused,to:AXUIElement.self)
  func value(_ name:String)->CFTypeRef? { var result:CFTypeRef?; guard AXUIElementCopyAttributeValue(element,name as CFString,&result) == .success else { return nil }; return result }
  guard let role=value(kAXRoleAttribute) as? String,qualifies(token.bundleID,role),value(kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,let text=value(kAXValueAttribute) as? String,let raw=value(kAXSelectedTextRangeAttribute),CFGetTypeID(raw)==AXValueGetTypeID() else { return nil }
  var range=CFRange(); guard AXValueGetValue(unsafeBitCast(raw,to:AXValue.self),.cfRange,&range),range.location>=0,range.length>=0,range.location<=text.utf16.count,range.length<=text.utf16.count-range.location else { return nil }
  var writable:DarwinBoolean=false
  guard AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&writable) == .success,writable.boolValue,AXUIElementIsAttributeSettable(element,kAXSelectedTextRangeAttribute as CFString,&writable) == .success,writable.boolValue else { return nil }
  return State(element:element,value:text,range:NSRange(location:range.location,length:range.length))
 }
 public func selected(in token:ContextToken)->SelectionEvidence? { guard let current=state(token) else { return nil }; return .init(context:token,text:(current.value as NSString).substring(with:current.range),location:current.range.location,length:current.range.length) }
 public func suffix(_ text:String,in token:ContextToken)->SelectionEvidence? {
  guard let current=state(token),current.range.length==0,current.range.location>=text.utf16.count else { return nil }
  let range=NSRange(location:current.range.location-text.utf16.count,length:text.utf16.count)
  guard (current.value as NSString).substring(with:range)==text else { return nil }
  return .init(context:token,text:text,location:range.location,length:range.length)
 }
 public func replace(_ evidence:SelectionEvidence,with text:String)->ApplyResult {
  guard let before=state(evidence.context),evidence.location>=0,evidence.length>=0,evidence.location<=before.value.utf16.count,evidence.length<=before.value.utf16.count-evidence.location else { return .aborted }
  let range=NSRange(location:evidence.location,length:evidence.length)
  guard (before.value as NSString).substring(with:range)==evidence.text,
   before.range==range || (before.range.length==0 && before.range.location==range.location+range.length),context.isSafe(evidence.context) else { return .aborted }
  let result=(before.value as NSString).replacingCharacters(in:range,with:text)
  guard AXUIElementSetAttributeValue(before.element,kAXValueAttribute as CFString,result as CFString) == .success else { return .uncertain }
  var caret=CFRange(location:range.location+text.utf16.count,length:0)
  guard let value=AXValueCreate(.cfRange,&caret),context.isSafe(evidence.context),AXUIElementSetAttributeValue(before.element,kAXSelectedTextRangeAttribute as CFString,value) == .success,let after=state(evidence.context),CFEqual(after.element,before.element),after.value==result,after.range==NSRange(location:caret.location,length:0) else { return .uncertain }
  return .committed
 }
}
