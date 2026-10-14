import Foundation
public struct EditPlan: Equatable, Sendable {
 public let id:UUID
 public let expected:ContextToken
 public let original:String
 public let replacement:String
 public let sourceLayout:LayoutID
 public let targetLayout:LayoutID
 public let delimiter:String
 public init(id:UUID = UUID(),expected:ContextToken,original:String,replacement:String,sourceLayout:LayoutID,targetLayout:LayoutID,delimiter:String) { self.id=id; self.expected=expected; self.original=original; self.replacement=replacement; self.sourceLayout=sourceLayout; self.targetLayout=targetLayout; self.delimiter=delimiter }
}
public enum ApplyResult: Equatable, Sendable { case committed, aborted, uncertain }
public protocol KeySending:AnyObject { func replaceVerifiedSuffix(_ plan:EditPlan)->ApplyResult }
public protocol RuleSnapshotConsumer:AnyObject { func install(_ snapshot:RuleSnapshot) }
/// Evidence is immutable and tied to a focus token and exact UTF16 range.
public struct SelectionEvidence:Equatable, Sendable {
 public let context:ContextToken
 public let text:String
 public let location:Int
 public let length:Int
 public init(context:ContextToken,text:String,location:Int,length:Int) { self.context=context; self.text=text; self.location=location; self.length=length }
}
public protocol SelectionAccess:AnyObject {
 func selected(in context:ContextToken)->SelectionEvidence?
 func suffix(_ text:String,in context:ContextToken)->SelectionEvidence?
 func replace(_ evidence:SelectionEvidence,with text:String)->ApplyResult
}
