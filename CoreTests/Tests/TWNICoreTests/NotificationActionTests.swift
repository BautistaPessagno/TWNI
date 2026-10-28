import XCTest
@testable import TWNICore

final class NotificationActionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testExhaustedNotificationSnoozeDoesNotStartOrCompleteRest() {
        var settings = EyeTimerSettings.classic
        settings.gapPolicy = .focus
        var engine = EyeTimerEngine(settings: settings)
        engine.start(at: t0)
        _ = engine.respond(to: .snooze, at: t0.addingTimeInterval(1200), presence: .present, allowsSkip: true)
        _ = engine.respond(to: .snooze, at: t0.addingTimeInterval(1500), presence: .present, allowsSkip: true)
        XCTAssertEqual(engine.snoozeCount, 2)

        let rejected = engine.respond(to: .snooze, at: t0.addingTimeInterval(1800), presence: .present, allowsSkip: true)
        XCTAssertFalse(rejected.contains(.breakStarted))
        XCTAssertFalse(engine.isResting)
        let later = engine.respond(to: .restDone, at: t0.addingTimeInterval(1830), presence: .present, allowsSkip: true)
        XCTAssertFalse(later.contains { if case .cycleEnded(let record) = $0 { return record.outcome == .completed }; return false })
    }

    func testOpeningRestDoneDoesNotStartAnotherBreak() {
        var settings = EyeTimerSettings.classic
        settings.gapPolicy = .focus
        var engine = EyeTimerEngine(settings: settings)
        engine.start(at: t0)
        _ = engine.startBreak(at: t0)
        let action = NotificationAction(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", requestIdentifier: "rest-done")
        XCTAssertEqual(action, .restDone)
        let events = engine.respond(to: action, at: t0.addingTimeInterval(20), presence: .present, allowsSkip: true)
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertFalse(events.contains(.breakStarted))
    }

    func testBackgroundTicksDoNotStartAnUnattendedRest() {
        var settings = EyeTimerSettings.classic
        settings.gapPolicy = .focus
        var engine = EyeTimerEngine(settings: settings)
        engine.start(at: t0)
        for second in 1...1260 {
            let events = engine.update(at: t0.addingTimeInterval(TimeInterval(second)), presence: .present, allowsStartingBreak: false)
            XCTAssertTrue(events.isEmpty)
        }
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.update(at: t0.addingTimeInterval(1261), presence: .present), [.breakStarted])
    }

    func testAcceptedRestAndSkipActionsStillWorkFromBackground() {
        for action in [NotificationAction.startBreak, .skip] {
            var settings = EyeTimerSettings.classic
            settings.gapPolicy = .focus
            var engine = EyeTimerEngine(settings: settings)
            engine.start(at: t0)
            let events = engine.respond(to: action, at: t0.addingTimeInterval(1200), presence: .present, allowsSkip: true)
            if action == .startBreak {
                XCTAssertTrue(engine.isResting)
                XCTAssertEqual(events, [.breakStarted])
            } else {
                XCTAssertEqual(engine.phase, .focusing)
                let outcomes = events.compactMap { event -> CycleOutcome? in
                    if case .cycleEnded(let record) = event { return record.outcome }
                    return nil
                }
                XCTAssertEqual(outcomes, [.skipped])
            }
        }
    }

    func testStrictModeRejectsStaleSnoozeAndSkipActions() {
        for action in [NotificationAction.snooze, .skip] {
            var settings = EyeTimerSettings.classic
            settings.gapPolicy = .focus
            settings.maxSnoozesPerCycle = 0
            var engine = EyeTimerEngine(settings: settings)
            engine.start(at: t0)
            XCTAssertTrue(engine.respond(to: action, at: t0.addingTimeInterval(1200), presence: .present, allowsSkip: false).isEmpty)
            XCTAssertEqual(engine.phase, .focusing)
        }
    }

    func testLateSkipDoesNotDiscardTheNextFocusCycle() {
        var settings = EyeTimerSettings.classic
        settings.gapPolicy = .focus
        var engine = EyeTimerEngine(settings: settings)
        engine.start(at: t0)
        let now = t0.addingTimeInterval(32 * 60)
        let events = engine.respond(to: .skip, at: now, presence: .present, allowsSkip: true)
        let outcomes = events.compactMap { event -> CycleOutcome? in
            if case .cycleEnded(let record) = event { return record.outcome }
            return nil
        }
        XCTAssertEqual(outcomes, [.missed])
        XCTAssertEqual(engine.focusedSeconds, 12 * 60)
        XCTAssertEqual(engine.nextBreakDate(from: now), t0.addingTimeInterval(40 * 60))
    }
}
