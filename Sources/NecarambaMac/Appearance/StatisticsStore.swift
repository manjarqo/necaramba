import Foundation
public enum CounterKind: String, Codable, CaseIterable, Sendable { case layout, typo, doubleCaps, yo, manual, undo
 public var estimatedSeconds: Int { switch self { case .layout,.manual: return 1; case .typo,.doubleCaps,.yo: return 2; case .undo:return 0 } }
}
public enum StatisticsError: Error { case invalidDay, corruptStore, overflow }
/// Aggregate-only persistence. Producer guarantees no duplicate delivery beyond the 1024-ID window.
public final class StatisticsStore {
 public static let weightsVersion = 1
 private struct State: Codable { var version = 1; var counters:[String:[String:Int]] = [:] }
 private let queue = DispatchQueue(label:"org.necaramba.statistics")
 private let url: URL
 private var state: State
 private var recent: [UUID] = []
 private var ids: Set<UUID> = []
 public init(directory: URL) throws {
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  url = directory.appendingPathComponent("aggregate-counters.json")
  if FileManager.default.fileExists(atPath:url.path) {
   state = try JSONDecoder().decode(State.self,from:Data(contentsOf:url))
   guard state.version == 1, state.counters.allSatisfy({ Self.validDay($0.key) && $0.value.allSatisfy({ CounterKind(rawValue:$0.key) != nil && $0.value >= 0 }) }) else { throw StatisticsError.corruptStore }
  } else { state = State() }
 }
 private static func validDay(_ day:String) -> Bool {
  guard day.utf8.count == 10 else { return false }
  let formatter=DateFormatter(); formatter.locale=Locale(identifier:"en_US_POSIX"); formatter.timeZone=TimeZone(secondsFromGMT:0); formatter.dateFormat="yyyy-MM-dd"; formatter.isLenient=false
  return formatter.date(from:day).map { formatter.string(from:$0)==day } ?? false
 }
 public func recordCommitted(id:UUID,kind:CounterKind,day:String) throws {
  try queue.sync {
   guard Self.validDay(day) else { throw StatisticsError.invalidDay }
   guard !ids.contains(id) else { return }
   var next=state; let old=next.counters[day]?[kind.rawValue] ?? 0
   guard old < Int.max else { throw StatisticsError.overflow }
   next.counters[day,default:[:]][kind.rawValue]=old+1
   try JSONEncoder().encode(next).write(to:url,options:.atomic)
   state=next; ids.insert(id); recent.append(id)
   if recent.count > 1024 { ids.remove(recent.removeFirst()) }
  }
 }
 public func count(kind:CounterKind,day:String) throws -> Int { try queue.sync { guard Self.validDay(day) else { throw StatisticsError.invalidDay }; return state.counters[day]?[kind.rawValue] ?? 0 } }
 public var totals: [CounterKind:Int] { queue.sync { Dictionary(uniqueKeysWithValues:CounterKind.allCases.map { kind in (kind,state.counters.values.reduce(0) { result,row in let (sum,overflow)=result.addingReportingOverflow(row[kind.rawValue] ?? 0); return overflow ? Int.max : sum }) }) } }
 public var estimatedSeconds: Int { totals.reduce(0) { result,pair in let (weighted,o1)=pair.value.multipliedReportingOverflow(by:pair.key.estimatedSeconds); let (sum,o2)=result.addingReportingOverflow(weighted); return o1 || o2 ? Int.max : sum } }
 public func reset() throws { try queue.sync { let next=State(); try JSONEncoder().encode(next).write(to:url,options:.atomic); state=next; recent=[]; ids=[] } }
}
