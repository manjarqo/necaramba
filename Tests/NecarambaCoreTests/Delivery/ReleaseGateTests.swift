import XCTest
@testable import NecarambaCore
final class ReleaseGateTests:XCTestCase {
 func testMissingFailedAndNAEvidenceNeverPassMandatoryGate() {
  let key="AC-091/x86_64/12/TextEdit/AX"
  XCTAssertFalse(ReleaseGate.isReady(required:[key],results:[:]))
  for status in [AcceptanceStatus.failed,.unrun,.notApplicable] {
   XCTAssertFalse(ReleaseGate.isReady(required:[key],results:[key:.init(status:status,evidencePath:"evidence.json",buildSHA:"abc",architecture:"x86_64",osBuild:"12")]))
  }
 }
 func testDistinctArchitectureRequiredAndEmptyEvidenceRejected() {
  let value=AcceptanceResult(status:.passed,evidencePath:"arm.json",buildSHA:"abc",architecture:"arm64",osBuild:"12")
  XCTAssertFalse(ReleaseGate.isReady(required:["arm64","x86_64"],results:["arm64":value]))
  XCTAssertTrue(ReleaseGate.isReady(required:["arm64"],results:["arm64":value]))
  XCTAssertFalse(ReleaseGate.isReady(required:["arm64"],results:["arm64":.init(status:.passed,evidencePath:"",buildSHA:"abc",architecture:"arm64",osBuild:"12")]))
  XCTAssertFalse(ReleaseGate.isReady(required:[],results:[:]))
 }
}
