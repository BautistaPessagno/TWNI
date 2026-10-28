import XCTest
@testable import TWNICore

final class EyeTimerEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Ticks the engine once per second for `seconds`, collecting events.
    @discardableResult
    func run(
        _ engine: inout EyeTimerEngine,
        from start: Date,
        seconds: Int,
        presence: (Int) -> Presence = { _ in .present }
    ) -> (events: [EyeTimerEvent], end: Date) {
        var events: [EyeTimerEvent] = []
        var now = start
        for i in 0..<seconds {
            now = start.addingTimeInterval(TimeInterval(i + 1))
            events += engine.update(at: now, presence: presence(i))
        }
        return (events, now)
    }

    func records(_ events: [EyeTimerEvent]) -> [CycleRecord] {
        events.compactMap { if case .cycleEnded(let r) = $0 { return r } else { return nil } }
    }

    // MARK: - Basic cycle

    func testBreakStartsAfterTwentyMinutesOfScreenTime() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let first = run(&engine, from: t0, seconds: 20 * 60 - 1)
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.secondsUntilBreak, 1, accuracy: 0.001)

        let second = run(&engine, from: first.end, seconds: 1)
        XCTAssertEqual(second.events, [.breakStarted])
        XCTAssertTrue(engine.isResting)
    }

    func testCompletedBreakRecordsCycleAndStartsOver() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 20 * 60)
        let rest = run(&engine, from: focus.end, seconds: 20)
        let recs = records(rest.events)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.outcome, .completed)
        XCTAssertEqual(recs.first?.focusedSeconds ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(recs.first?.restedSeconds ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(recs.first?.startedAt, t0)
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.focusedSeconds, 0)
    }

    func testSkipRecordsSkippedAndRestartsInterval() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 20 * 60)
        let events = engine.skipBreak(at: focus.end.addingTimeInterval(1))
        XCTAssertEqual(records(events).map(\.outcome), [.skipped])
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.secondsUntilBreak, 20 * 60, accuracy: 0.001)
    }

    func testSnoozeBringsBreakBackAndIsLimited() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        var end = run(&engine, from: t0, seconds: 20 * 60).end

        XCTAssertTrue(engine.canSnooze)
        XCTAssertEqual(engine.snooze(at: end), [.snoozed(until: end.addingTimeInterval(300))])
        let afterSnooze = run(&engine, from: end, seconds: 300)
        XCTAssertEqual(afterSnooze.events, [.breakStarted])
        end = afterSnooze.end

        engine.snooze(at: end)
        end = run(&engine, from: end, seconds: 300).end
        XCTAssertTrue(engine.isResting)
        XCTAssertFalse(engine.canSnooze, "only two snoozes per cycle")

        let done = run(&engine, from: end, seconds: 20)
        XCTAssertEqual(records(done.events).first?.snoozeCount, 2)
        XCTAssertEqual(records(done.events).first?.outcome, .completed)
    }

    func testStartBreakEarlyCountsAsCompleted() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 10 * 60)
        XCTAssertEqual(engine.startBreak(at: focus.end), [.breakStarted])
        let rest = run(&engine, from: focus.end, seconds: 20)
        XCTAssertEqual(records(rest.events).map(\.outcome), [.completed])
    }

    func testStopRecordsPartialCycleOnlyIfMeaningful() {
        var a = EyeTimerEngine()
        a.start(at: t0)
        run(&a, from: t0, seconds: 30)
        XCTAssertTrue(a.stop(at: t0.addingTimeInterval(31)).isEmpty, "30 s is too short to record")
        XCTAssertEqual(a.phase, .off)

        var b = EyeTimerEngine()
        b.start(at: t0)
        run(&b, from: t0, seconds: 300)
        XCTAssertEqual(records(b.stop(at: t0.addingTimeInterval(301))).map(\.outcome), [.stopped])
    }

    // MARK: - Idle and away (macOS)

    func testShortIdleStillCountsAsScreenTime() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        // Reading: no input for 45 s at a time.
        run(&engine, from: t0, seconds: 600) { i in Presence(idleSeconds: TimeInterval(i % 45)) }
        XCTAssertEqual(engine.focusedSeconds, 600, accuracy: 0.001)
    }

    func testIdlePausesCountingWithoutResetting() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 600)
        // Two minutes without input: paused, not reset.
        run(&engine, from: focus.end, seconds: 120) { i in Presence(idleSeconds: TimeInterval(60 + i)) }
        XCTAssertEqual(engine.focusedSeconds, 600, accuracy: 1.001)
        XCTAssertTrue(engine.isFocusPaused)
    }

    func testVideoKeepsCountingWhileIdle() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        run(&engine, from: t0, seconds: 900) { i in
            Presence(idleSeconds: TimeInterval(i), isWatchingMedia: true)
        }
        XCTAssertEqual(engine.focusedSeconds, 900, accuracy: 0.001)
    }

    func testSteppingAwayFiveMinutesCountsAsNaturalRest() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 15 * 60)
        let away = run(&engine, from: focus.end, seconds: 301) { i in Presence(idleSeconds: TimeInterval(i)) }
        let recs = records(away.events)
        XCTAssertEqual(recs.map(\.outcome), [.natural])
        XCTAssertEqual(recs.first?.endedAt, focus.end.addingTimeInterval(1), "dated from when the user left")
        XCTAssertEqual(recs.first?.focusedSeconds ?? 0, 900, accuracy: 60.001)
        XCTAssertEqual(engine.focusedSeconds, 0)
        // Staying away doesn't create more records.
        let more = run(&engine, from: away.end, seconds: 600) { i in Presence(idleSeconds: TimeInterval(301 + i)) }
        XCTAssertTrue(more.events.isEmpty)
    }

    func testLockedScreenForAMinuteCountsAsRest() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 19 * 60)
        let locked = run(&engine, from: focus.end, seconds: 60) { _ in .screenOff }
        XCTAssertEqual(records(locked.events).map(\.outcome), [.natural])
        let back = run(&engine, from: locked.end, seconds: 120)
        XCTAssertTrue(back.events.isEmpty, "no break right after coming back")
        XCTAssertEqual(engine.focusedSeconds, 120, accuracy: 0.001)
    }

    func testBriefScreenOffDoesNotReset() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 600)
        let off = run(&engine, from: focus.end, seconds: 30) { _ in .screenOff }
        XCTAssertTrue(off.events.isEmpty)
        XCTAssertEqual(engine.focusedSeconds, 600, accuracy: 0.001)
    }

    func testSleepGapCountsAsRestNotScreenTime() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 10 * 60)
        // Lid closed for an hour: next tick arrives an hour later.
        let wake = focus.end.addingTimeInterval(3600)
        let events = engine.update(at: wake, presence: .present)
        XCTAssertEqual(records(events).map(\.outcome), [.natural])
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.focusedSeconds, 0)
    }

    func testShortStallIsIgnored() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 600)
        let events = engine.update(at: focus.end.addingTimeInterval(30), presence: .present)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.focusedSeconds, 600, accuracy: 0.001, "unobserved time isn't counted")
    }

    func testClockGoingBackwardsAddsNothing() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 100)
        XCTAssertTrue(engine.update(at: focus.end.addingTimeInterval(-3600), presence: .present).isEmpty)
        XCTAssertEqual(engine.focusedSeconds, 100, accuracy: 0.001)
    }

    // MARK: - Calls

    func testBreakWaitsForCallToEnd() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 1100)
        // Call from 18:20 to 25:00, no typing.
        let call = run(&engine, from: focus.end, seconds: 400) { i in
            Presence(idleSeconds: TimeInterval(i), isInCall: true)
        }
        XCTAssertTrue(call.events.isEmpty, "no break during the call")
        XCTAssertTrue(engine.isBreakDeferred)
        XCTAssertEqual(engine.focusedSeconds, 1500, accuracy: 0.001, "calls count as screen time")
        let after = run(&engine, from: call.end, seconds: 1)
        XCTAssertEqual(after.events, [.breakStarted])
        XCTAssertFalse(engine.isBreakDeferred)
    }

    func testLongSilentCallIsNotANaturalRest() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 60)
        let call = run(&engine, from: focus.end, seconds: 600) { i in
            Presence(idleSeconds: TimeInterval(i), isInCall: true)
        }
        XCTAssertTrue(records(call.events).isEmpty)
        XCTAssertEqual(engine.focusedSeconds, 660, accuracy: 0.001)
    }

    // MARK: - Rest verification

    func testRestOnlyCountsWhileHandsAreOffWhenRequired() {
        var settings = EyeTimerSettings.classic
        settings.restRequiresStillness = true
        var engine = EyeTimerEngine(settings: settings)
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 1200)
        // Keeps typing for 10 s, then stops.
        let typing = run(&engine, from: focus.end, seconds: 10) { _ in Presence(idleSeconds: 0.1) }
        XCTAssertTrue(engine.isRestPausedByInput)
        XCTAssertEqual(engine.restedSeconds, 0)
        let still = run(&engine, from: typing.end, seconds: 20) { i in Presence(idleSeconds: TimeInterval(i + 1)) }
        XCTAssertEqual(records(still.events).map(\.outcome), [.completed])
    }

    func testSleepingDuringBreakCompletesIt() {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 1200)
        let events = engine.update(at: focus.end.addingTimeInterval(120), presence: .present)
        XCTAssertEqual(records(events).map(\.outcome), [.completed])
        XCTAssertEqual(records(events).first?.restedSeconds, 20)
    }

    // MARK: - iOS screen sessions (gap counts as focus)

    func focusSettings() -> EyeTimerSettings {
        var s = EyeTimerSettings.classic
        s.gapPolicy = .focus
        return s
    }

    func testBackgroundShorterThanIntervalJustAccrues() {
        var engine = EyeTimerEngine(settings: focusSettings())
        engine.start(at: t0)
        let events = engine.update(at: t0.addingTimeInterval(600), presence: .present)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.focusedSeconds, 600, accuracy: 0.001)
    }

    func testOpeningAppRightAfterReminderStartsBreak() {
        var engine = EyeTimerEngine(settings: focusSettings())
        engine.start(at: t0)
        // Reminder fired at 20:00, user opens the app at 21:00.
        let events = engine.update(at: t0.addingTimeInterval(1260), presence: .present)
        XCTAssertEqual(events, [.breakStarted])
        XCTAssertTrue(engine.isResting)
    }

    func testIgnoredRemindersCountAsMissedWithCorrectTimes() {
        var engine = EyeTimerEngine(settings: focusSettings())
        engine.start(at: t0)
        // Away 50 min: reminders at 20:00 (missed) and 40:00 (missed, >5 min ago).
        let now = t0.addingTimeInterval(50 * 60)
        let events = engine.update(at: now, presence: .present)
        let recs = records(events)
        XCTAssertEqual(recs.map(\.outcome), [.missed, .missed])
        XCTAssertEqual(recs.map(\.endedAt), [t0.addingTimeInterval(1200), t0.addingTimeInterval(2400)])
        XCTAssertEqual(recs.map(\.startedAt), [t0, t0.addingTimeInterval(1200)])
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.focusedSeconds, 600, accuracy: 0.001)
    }

    func testBreakFinishingInBackgroundHandsTimeBackToFocus() {
        var engine = EyeTimerEngine(settings: focusSettings())
        engine.start(at: t0)
        engine.startBreak(at: t0)
        // Phone locked during the break; back 21 min later: break done at 0:20,
        // next reminder was due at 20:20 (40 s ago, within grace).
        let events = engine.update(at: t0.addingTimeInterval(20 + 1200 + 40), presence: .present)
        let recs = records(events)
        XCTAssertEqual(recs.map(\.outcome), [.completed])
        XCTAssertEqual(recs.first?.endedAt, t0.addingTimeInterval(20))
        XCTAssertEqual(events.last, .breakStarted)
    }

    func testVeryLongGapIsBounded() {
        var engine = EyeTimerEngine(settings: focusSettings())
        engine.start(at: t0)
        let events = engine.update(at: t0.addingTimeInterval(30 * 24 * 3600), presence: .present)
        XCTAssertLessThanOrEqual(records(events).count, 500)
        XCTAssertEqual(engine.phase, .focusing)
    }

    // MARK: - Persistence

    func testEngineRoundTripsThroughCodable() throws {
        var engine = EyeTimerEngine()
        engine.start(at: t0)
        let focus = run(&engine, from: t0, seconds: 1200)
        engine.snooze(at: focus.end)
        let data = try JSONEncoder().encode(engine)
        let decoded = try JSONDecoder().decode(EyeTimerEngine.self, from: data)
        XCTAssertEqual(decoded, engine)
    }
}
