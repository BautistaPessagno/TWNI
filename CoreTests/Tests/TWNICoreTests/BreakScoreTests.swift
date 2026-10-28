import XCTest
@testable import TWNICore

final class BreakScoreTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    let day0 = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400))

    func record(_ outcome: CycleOutcome, minutes: Double, endingAt end: Date) -> CycleRecord {
        CycleRecord(
            startedAt: end.addingTimeInterval(-minutes * 60),
            endedAt: end,
            focusedSeconds: minutes * 60,
            restedSeconds: outcome == .completed ? 20 : 0,
            snoozeCount: 0,
            outcome: outcome
        )
    }

    func summary(_ records: [CycleRecord], live: TimeInterval = 0) -> DaySummary {
        DaySummary(day: day0, records: records, liveFocusSeconds: live)
    }

    // MARK: - Score

    func testNoScreenTimeHasNoScore() {
        XCTAssertNil(BreakScore.score(for: summary([])))
        XCTAssertEqual(BreakScore.label(for: nil), "No screen time yet")
    }

    func testEveryBlockFollowedByBreakIsPerfect() {
        let recs = (1...6).map { record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(Double($0) * 1300)) }
        XCTAssertEqual(BreakScore.score(for: summary(recs)), 100)
    }

    func testSkippingHalfTheBreaksScoresFifty() {
        let recs = [
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(1300)),
            record(.skipped, minutes: 20, endingAt: day0.addingTimeInterval(2600)),
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(3900)),
            record(.missed, minutes: 20, endingAt: day0.addingTimeInterval(5200)),
        ]
        XCTAssertEqual(BreakScore.score(for: summary(recs)), 50)
    }

    func testSteppingAwayOftenCountsAsRest() {
        let recs = (1...6).map { record(.natural, minutes: 10, endingAt: day0.addingTimeInterval(Double($0) * 1000)) }
        XCTAssertEqual(BreakScore.score(for: summary(recs)), 100)
    }

    func testLongStretchWithoutBreaksScoresLow() {
        // Two hours straight (e.g. stopped protection at the end), one break earlier.
        let recs = [
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(1300)),
            record(.stopped, minutes: 120, endingAt: day0.addingTimeInterval(9000)),
        ]
        let s = summary(recs)
        XCTAssertEqual(s.longestStretch, 7200)
        XCTAssertEqual(BreakScore.score(for: s), 14) // 1 rest / 7 blocks
    }

    func testLiveStretchCountsTowardScreenTime() {
        let recs = [record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(1300))]
        let s = summary(recs, live: 25 * 60)
        XCTAssertEqual(s.screenSeconds, 45 * 60)
        XCTAssertEqual(BreakScore.score(for: s), 50)
    }

    func testFirstPartialBlock() {
        XCTAssertEqual(BreakScore.score(for: summary([], live: 10 * 60)), 100)
        let skippedEarly = [record(.skipped, minutes: 5, endingAt: day0.addingTimeInterval(300))]
        XCTAssertEqual(BreakScore.score(for: summary(skippedEarly)), 50)
    }

    // MARK: - Streak

    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: day0))!
    }

    func testStreakCountsConsecutiveMetDays() {
        let statuses: [Date: DayStatus] = [day(0): .met, day(-1): .met, day(-2): .met, day(-3): .notMet, day(-4): .met]
        XCTAssertEqual(Streak.current(statuses: statuses, today: day(0), calendar: calendar), 3)
    }

    func testUnfinishedTodayDoesNotBreakStreak() {
        let statuses: [Date: DayStatus] = [day(0): .notMet, day(-1): .met, day(-2): .met]
        XCTAssertEqual(Streak.current(statuses: statuses, today: day(0).addingTimeInterval(3600), calendar: calendar), 2)
    }

    func testDaysWithoutScreenTimeAreSkipped() {
        // Weekend away from screens keeps the streak alive.
        let statuses: [Date: DayStatus] = [day(0): .met, day(-3): .met, day(-4): .met, day(-5): .notMet]
        XCTAssertEqual(Streak.current(statuses: statuses, today: day(0), calendar: calendar), 3)
    }

    func testMissedYesterdayResetsStreak() {
        let statuses: [Date: DayStatus] = [day(0): .met, day(-1): .notMet, day(-2): .met]
        XCTAssertEqual(Streak.current(statuses: statuses, today: day(0), calendar: calendar), 1)
    }

    func testBestStreak() {
        let statuses: [Date: DayStatus] = [
            day(-10): .met, day(-9): .met, day(-8): .met, day(-7): .met,
            day(-6): .notMet, day(-5): .met, day(-3): .met,
        ]
        XCTAssertEqual(Streak.best(statuses: statuses, calendar: calendar), 4)
    }

    func testStatusUsesGoal() {
        let recs = [
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(1300)),
            record(.skipped, minutes: 20, endingAt: day0.addingTimeInterval(2600)),
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(3900)),
            record(.skipped, minutes: 20, endingAt: day0.addingTimeInterval(5200)),
        ]
        XCTAssertEqual(Streak.status(of: summary(recs)), .notMet)
        XCTAssertEqual(Streak.status(of: summary(recs), goal: 50), .met)
        XCTAssertEqual(Streak.status(of: summary([])), .noData)
    }

    func testLightDaysDontCount() {
        // 40 minutes of screen time, perfect breaks: too little to count for the streak.
        let recs = [
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(1300)),
            record(.completed, minutes: 20, endingAt: day0.addingTimeInterval(2600)),
        ]
        XCTAssertEqual(BreakScore.score(for: summary(recs)), 100)
        XCTAssertEqual(Streak.status(of: summary(recs)), .noData)
    }

    // MARK: - Grouping

    func testGroupingByEndDay() {
        let lateNight = record(.completed, minutes: 20, endingAt: day(1).addingTimeInterval(600))
        let morning = record(.skipped, minutes: 20, endingAt: day(0).addingTimeInterval(36_000))
        let grouped = DayGrouping.summaries(records: [lateNight, morning], calendar: calendar)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[day(1)]?.completed, 1)
        XCTAssertEqual(grouped[day(0)]?.skipped, 1)
    }
}
