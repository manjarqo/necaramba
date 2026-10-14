import Foundation
public final class RuleUpdateSchedule {
    private let now: () -> Date
    private let jitter: () -> TimeInterval
    private var next: Date?
    private var lastManual: Date?
    public init(now: @escaping () -> Date = Date.init, jitter: @escaping () -> TimeInterval = { Double.random(in: -7200...7200) }) { self.now = now; self.jitter = jitter }
    public func takeScheduledCheck() -> Bool {
        let time = now(); guard next.map({ time >= $0 }) ?? true else { return false }
        let value = jitter(); let bounded = value.isFinite ? min(7200, max(-7200, value)) : 0
        next = time.addingTimeInterval(86400 + bounded); return true
    }
    public func takeManualCheck() -> Bool {
        let time = now(); guard lastManual.map({ time.timeIntervalSince($0) >= 30 }) ?? true else { return false }
        lastManual = time; return true
    }
    public var nextScheduledDate: Date? { next }
}
