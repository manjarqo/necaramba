import Foundation
public enum AcceptanceStatus:String,Codable,Sendable { case passed,failed,unrun,notApplicable }
public struct AcceptanceResult:Codable,Equatable,Sendable {
 public let status:AcceptanceStatus
 public let evidencePath:String
 public let buildSHA:String
 public let architecture:String
 public let osBuild:String
 public init(status:AcceptanceStatus,evidencePath:String,buildSHA:String,architecture:String,osBuild:String) {
  self.status=status; self.evidencePath=evidencePath; self.buildSHA=buildSHA; self.architecture=architecture; self.osBuild=osBuild
 }
}
public enum ReleaseGate {
 /// Keys identify full AC/architecture/OS/host/adapter tuples. Files are checked by CLI.
 public static func isReady(required:Set<String>,results:[String:AcceptanceResult])->Bool {
  !required.isEmpty && required.allSatisfy { key in
   guard let result=results[key] else { return false }
   return result.status == .passed && [result.evidencePath,result.buildSHA,result.architecture,result.osBuild].allSatisfy { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
  }
 }
}
