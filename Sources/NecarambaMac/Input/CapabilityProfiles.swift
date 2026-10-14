import Foundation
public struct CapabilityEvidence:Sendable {
 public let bundleID:String
 public let role:String
 public let osMajor:Int
 public let revision:String
 public let passed:Bool
 public init(bundleID:String,role:String,osMajor:Int,revision:String,passed:Bool) { self.bundleID=bundleID; self.role=role; self.osMajor=osMajor; self.revision=revision; self.passed=passed }
}
public struct CapabilityProfiles:Sendable {
 private let evidence:[CapabilityEvidence]
 private let osMajor:Int
 public init(evidence:[CapabilityEvidence] = [],osMajor:Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) { self.evidence=evidence; self.osMajor=osMajor }
 public func qualifies(bundleID:String,role:String)->Bool { evidence.contains { $0.bundleID==bundleID && $0.role==role && $0.osMajor==osMajor && !$0.revision.isEmpty && $0.passed } }
}
