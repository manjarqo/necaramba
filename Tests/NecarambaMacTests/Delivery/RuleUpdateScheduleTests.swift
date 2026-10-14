import XCTest
@testable import NecarambaMac
final class RuleUpdateScheduleTests: XCTestCase {
    func testLaunchDailyJitterAndManualThrottle() {
        var now = Date(timeIntervalSince1970: 100)
        let schedule = RuleUpdateSchedule(now: { now }, jitter: { 99999 })
        XCTAssertTrue(schedule.takeScheduledCheck()); XCTAssertFalse(schedule.takeScheduledCheck())
        XCTAssertTrue(schedule.takeManualCheck()); XCTAssertFalse(schedule.takeManualCheck())
        now = now.addingTimeInterval(30); XCTAssertTrue(schedule.takeManualCheck())
        now = Date(timeIntervalSince1970: 100 + 86400 + 7200); XCTAssertTrue(schedule.takeScheduledCheck())
    }
}
