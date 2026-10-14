import XCTest
import NecarambaCore
@testable import NecarambaMac
final class SelectionTests:XCTestCase {
 func testSelectionReplacesOnlyProvenRange() {
  let access=MemorySelection(); let adapter=SelectionAdapter(selection:access)
  XCTAssertEqual(adapter.convert(in:access.token,transform:{$0.uppercased()}),.committed)
  XCTAssertEqual(access.text,"A WORD Z")
 }
 func testUnknownSelectionDoesNotWrite() {
  let access=MemorySelection(); access.available=false
  XCTAssertEqual(SelectionAdapter(selection:access).convert(in:access.token,transform:{$0.uppercased()}),.aborted)
  XCTAssertEqual(access.text,"A word Z")
 }
 func testCapabilityRequiresRecordedPass() {
  XCTAssertFalse(CapabilityProfiles().qualifies(bundleID:"com.apple.TextEdit",role:"AXTextArea"))
 }
}
private final class MemorySelection:SelectionAccess {
 let token=ContextToken(pid:42,bundleID:"test",focusEpoch:1,layoutEpoch:1)
 var text="A word Z"; var available=true
 func selected(in context:ContextToken)->SelectionEvidence? { available && context==token ? .init(context:token,text:"word",location:2,length:4):nil }
 func suffix(_ text:String,in context:ContextToken)->SelectionEvidence? { nil }
 func replace(_ evidence:SelectionEvidence,with value:String)->ApplyResult { guard evidence==selected(in:token) else { return .aborted }; text=(text as NSString).replacingCharacters(in:NSRange(location:evidence.location,length:evidence.length),with:value); return .committed }
}
