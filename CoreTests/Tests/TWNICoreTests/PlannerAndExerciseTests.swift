import XCTest
@testable import TWNICore

final class ReminderPlannerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func focusEngine() -> EyeTimerEngine {
        var s = EyeTimerSettings.classic
        s.gapPolicy = .focus
        return EyeTimerEngine(settings: s)
    }

    func testRemindersEveryIntervalUntilSessionEnd() {
        var engine = focusEngine()
        engine.start(at: t0)
        _ = engine.update(at: t0.addingTimeInterval(300), presence: .present)
        let now = t0.addingTimeInterval(300)
        let dates = ReminderPlanner.reminderDates(for: engine, now: now, until: t0.addingTimeInterval(3600))
        XCTAssertEqual(dates, [1200, 2400, 3600].map { t0.addingTimeInterval($0) })
    }

    func testPlannerMatchesEngineReconciliation() {
        var engine = focusEngine()
        engine.start(at: t0)
        let dates = ReminderPlanner.reminderDates(for: engine, now: t0, until: nil, limit: 3)
        // Ignore all three reminders, come back 10 min after the third.
        let events = engine.update(at: dates[2].addingTimeInterval(600), presence: .present)
        let missedEnds = events.compactMap { event -> Date? in
            if case .cycleEnded(let r) = event, r.outcome == .missed { return r.endedAt }
            return nil
        }
        XCTAssertEqual(missedEnds, dates)
    }

    func testNoRemindersWhileOff() {
        let engine = focusEngine()
        XCTAssertTrue(ReminderPlanner.reminderDates(for: engine, now: t0, until: nil).isEmpty)
    }

    func testRemindersDuringBreakStartAfterIt() {
        var engine = focusEngine()
        engine.start(at: t0)
        engine.startBreak(at: t0)
        let dates = ReminderPlanner.reminderDates(for: engine, now: t0, until: nil, limit: 2)
        XCTAssertEqual(dates, [t0.addingTimeInterval(1220), t0.addingTimeInterval(2420)])
    }

    func testRespectsLimitAndSnooze() {
        var engine = focusEngine()
        engine.start(at: t0)
        XCTAssertEqual(ReminderPlanner.reminderDates(for: engine, now: t0, until: nil).count, ReminderPlanner.maxReminders)
        engine.startBreak(at: t0)
        engine.snooze(at: t0)
        let dates = ReminderPlanner.reminderDates(for: engine, now: t0, until: nil, limit: 2)
        XCTAssertEqual(dates, [t0.addingTimeInterval(300), t0.addingTimeInterval(1500)])
    }
}

final class EyeExerciseTests: XCTestCase {
    func testRotationWraps() {
        let count = EyeExerciseLibrary.all.count
        XCTAssertEqual(EyeExerciseLibrary.exercise(forBreakNumber: 0), EyeExerciseLibrary.all[0])
        XCTAssertEqual(EyeExerciseLibrary.exercise(forBreakNumber: count), EyeExerciseLibrary.all[0])
        XCTAssertEqual(EyeExerciseLibrary.exercise(forBreakNumber: -1), EyeExerciseLibrary.all[count - 1])
    }

    func testBlinkCueInLastSeconds() {
        let first = EyeExerciseLibrary.all[0]
        XCTAssertEqual(EyeExerciseLibrary.prompt(for: first, restRemaining: 12, breakDuration: 20), first)
        XCTAssertEqual(EyeExerciseLibrary.prompt(for: first, restRemaining: 4, breakDuration: 20), EyeExerciseLibrary.blinkCue)
        XCTAssertEqual(EyeExerciseLibrary.prompt(for: first, restRemaining: 4, breakDuration: 10), first)
    }

    func testIDsAreUnique() {
        let ids = (EyeExerciseLibrary.all + [EyeExerciseLibrary.blinkCue]).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
