import Foundation

// Pure timing logic for the 20-20-20 rule. No UI or platform frameworks, so it
// can be unit-tested anywhere (see CoreTests/). The platform layer feeds it a
// clock and a `Presence` snapshot once per second and reacts to the events it
// returns.

/// What the platform knows about the user at a given moment.
struct Presence: Equatable, Codable, Sendable {
    /// Seconds since the last keyboard, mouse or touch input.
    var idleSeconds: TimeInterval
    /// Something is keeping the display awake (video, call, presentation),
    /// so the user is probably still looking at the screen without typing.
    var isWatchingMedia: Bool
    /// False while the screen is locked, asleep or off.
    var isScreenOn: Bool
    /// A call or meeting is using the microphone: hold breaks until it ends.
    var isInCall: Bool

    init(idleSeconds: TimeInterval = 0, isWatchingMedia: Bool = false, isScreenOn: Bool = true, isInCall: Bool = false) {
        self.idleSeconds = idleSeconds
        self.isWatchingMedia = isWatchingMedia
        self.isScreenOn = isScreenOn
        self.isInCall = isInCall
    }

    static let present = Presence()
    static let screenOff = Presence(isScreenOn: false)
}

/// How to treat time the engine did not observe (computer asleep, app suspended).
enum GapPolicy: String, Codable, Sendable {
    /// The user was away from this screen (macOS: sleep, lid closed).
    case away
    /// The user said they'd be on screens (iOS screen session), so assume they
    /// kept looking at one. Reminders that fired in the meantime count as missed.
    case focus
}

struct EyeTimerSettings: Equatable, Codable, Sendable {
    /// Screen time before an eye break is due.
    var focusInterval: TimeInterval = 20 * 60
    /// Length of the eye break.
    var breakDuration: TimeInterval = 20
    /// Without input for this long (and no video playing), stop counting screen time.
    var idlePauseAfter: TimeInterval = 60
    /// Without input for this long (and no video playing), the user stepped away:
    /// that counts as a rest and the interval starts over.
    var naturalRestAfter: TimeInterval = 5 * 60
    /// Screen locked or asleep for this long counts as a rest.
    var screenOffRestAfter: TimeInterval = 60
    var snoozeDuration: TimeInterval = 5 * 60
    var maxSnoozesPerCycle: Int = 2
    /// macOS: the break only counts down while hands are off the keyboard and mouse.
    var restRequiresStillness: Bool = false
    var gapPolicy: GapPolicy = .away
    /// With `.focus`, a reminder older than this when the user comes back counts as missed.
    var missedGrace: TimeInterval = 5 * 60
    /// Cycles with less screen time than this are not worth recording.
    var minimumRecordedFocus: TimeInterval = 60
    /// Ticks further apart than this mean the engine wasn't running in between.
    var maxTickGap: TimeInterval = 15

    static let classic = EyeTimerSettings()
}

enum EyePhase: Equatable, Codable, Sendable {
    case off
    /// Counting screen time toward the next break.
    case focusing
    /// The eye break is running.
    case resting(startedAt: Date)
    /// The user postponed the break; it comes back at `until`.
    case snoozed(until: Date)
}

enum CycleOutcome: String, Codable, CaseIterable, Sendable {
    /// Finished the guided eye break.
    case completed
    /// Dismissed the break.
    case skipped
    /// Stepped away from the screen long enough on their own.
    case natural
    /// A reminder went unanswered during a screen session (iOS).
    case missed
    /// Protection was turned off mid-cycle.
    case stopped
}

/// One stretch of screen time and how it ended.
struct CycleRecord: Equatable, Codable, Sendable {
    var startedAt: Date
    var endedAt: Date
    var focusedSeconds: TimeInterval
    var restedSeconds: TimeInterval
    var snoozeCount: Int
    var outcome: CycleOutcome
}

enum EyeTimerEvent: Equatable, Sendable {
    case breakStarted
    case snoozed(until: Date)
    case cycleEnded(CycleRecord)
}

struct EyeTimerEngine: Equatable, Codable, Sendable {
    var settings: EyeTimerSettings

    private(set) var phase: EyePhase = .off
    /// Screen time counted in the current cycle.
    private(set) var focusedSeconds: TimeInterval = 0
    /// Rest counted in the current break.
    private(set) var restedSeconds: TimeInterval = 0
    /// Continuous time with the screen off while focusing.
    private(set) var screenOffSeconds: TimeInterval = 0
    private(set) var cycleStart: Date?
    private(set) var snoozeCount = 0
    private(set) var lastUpdate: Date?
    /// True while a break is paused because the user is still typing or moving the mouse.
    private(set) var isRestPausedByInput = false
    /// True while screen time is not being counted (idle, screen off).
    private(set) var isFocusPaused = false
    /// True while a due break waits for a call to end.
    private(set) var isBreakDeferred = false

    init(settings: EyeTimerSettings = .classic) {
        self.settings = settings
    }

    // MARK: - Derived values

    var isRunning: Bool { phase != .off }

    var isResting: Bool {
        if case .resting = phase { return true }
        return false
    }

    var secondsUntilBreak: TimeInterval {
        if case .snoozed(let until) = phase, let lastUpdate {
            return max(until.timeIntervalSince(lastUpdate), 0)
        }
        return max(settings.focusInterval - focusedSeconds, 0)
    }

    var restRemaining: TimeInterval {
        max(settings.breakDuration - restedSeconds, 0)
    }

    var focusProgress: Double {
        guard settings.focusInterval > 0 else { return 0 }
        return min(max(focusedSeconds / settings.focusInterval, 0), 1)
    }

    var restProgress: Double {
        guard settings.breakDuration > 0 else { return 0 }
        return min(max(restedSeconds / settings.breakDuration, 0), 1)
    }

    var canSnooze: Bool {
        isResting && snoozeCount < settings.maxSnoozesPerCycle
    }

    /// When the next break is due if the user keeps looking at the screen
    /// (after the current break, if one is running).
    func nextBreakDate(from now: Date) -> Date? {
        switch phase {
        case .off: return nil
        case .focusing: return now.addingTimeInterval(secondsUntilBreak)
        case .resting: return now.addingTimeInterval(restRemaining + settings.focusInterval)
        case .snoozed(let until): return until
        }
    }

    // MARK: - Commands

    mutating func start(at now: Date) {
        guard phase == .off else { return }
        resetCycle()
        phase = .focusing
        lastUpdate = now
    }

    @discardableResult
    mutating func stop(at now: Date) -> [EyeTimerEvent] {
        guard phase != .off else { return [] }
        var events: [EyeTimerEvent] = []
        if let record = makeRecord(outcome: .stopped, endedAt: now) {
            events.append(.cycleEnded(record))
        }
        resetCycle()
        phase = .off
        lastUpdate = now
        return events
    }

    /// Start the eye break now (user tapped "Rest now", or opened a reminder).
    @discardableResult
    mutating func startBreak(at now: Date) -> [EyeTimerEvent] {
        switch phase {
        case .focusing, .snoozed:
            beginRest(at: now)
            lastUpdate = now
            return [.breakStarted]
        case .off, .resting:
            return []
        }
    }

    @discardableResult
    mutating func skipBreak(at now: Date) -> [EyeTimerEvent] {
        switch phase {
        case .resting, .snoozed:
            let record = makeRecord(outcome: .skipped, endedAt: now, force: true)
            resetCycle()
            phase = .focusing
            lastUpdate = now
            return record.map { [.cycleEnded($0)] } ?? []
        case .off, .focusing:
            return []
        }
    }

    @discardableResult
    mutating func snooze(at now: Date) -> [EyeTimerEvent] {
        guard canSnooze else { return [] }
        snoozeCount += 1
        restedSeconds = 0
        isRestPausedByInput = false
        let until = now.addingTimeInterval(settings.snoozeDuration)
        phase = .snoozed(until: until)
        lastUpdate = now
        return [.snoozed(until: until)]
    }

    /// Apply new settings. Takes effect from the next tick.
    mutating func apply(_ newSettings: EyeTimerSettings) {
        settings = newSettings
    }

    // MARK: - Clock

    /// Advance the engine to `now`. Call about once per second.
    mutating func update(at now: Date, presence: Presence) -> [EyeTimerEvent] {
        guard phase != .off else {
            lastUpdate = now
            return []
        }
        let previous = lastUpdate ?? now
        lastUpdate = now
        // A clock that moved backwards (time zone or manual change) adds nothing.
        let delta = max(now.timeIntervalSince(previous), 0)

        if delta > settings.maxTickGap {
            return handleGap(delta, endingAt: now, presence: presence)
        }
        return advance(by: delta, at: now, presence: presence)
    }

    // MARK: - Internals

    private mutating func advance(by delta: TimeInterval, at now: Date, presence: Presence) -> [EyeTimerEvent] {
        switch phase {
        case .off:
            return []

        case .focusing, .snoozed:
            if let natural = naturalRestIfAway(delta: delta, at: now, presence: presence) {
                return natural
            }
            // Calls count as screen time even without typing.
            if countsAsScreenTime(presence) || (presence.isScreenOn && presence.isInCall) {
                isFocusPaused = false
                if cycleStart == nil { cycleStart = now.addingTimeInterval(-delta) }
                focusedSeconds += delta
            } else {
                isFocusPaused = true
            }
            return breakIfDue(at: now, presence: presence)

        case .resting:
            let still = !settings.restRequiresStillness
                || !presence.isScreenOn
                || presence.idleSeconds >= 0.75
            isRestPausedByInput = !still
            if still { restedSeconds += delta }
            return finishRestIfDone(at: now)
        }
    }

    private func countsAsScreenTime(_ presence: Presence) -> Bool {
        guard presence.isScreenOn else { return false }
        return presence.idleSeconds < settings.idlePauseAfter || presence.isWatchingMedia
    }

    /// While focusing or snoozed: if the user has been away long enough, credit a rest.
    private mutating func naturalRestIfAway(delta: TimeInterval, at now: Date, presence: Presence) -> [EyeTimerEvent]? {
        if presence.isScreenOn {
            screenOffSeconds = 0
        } else {
            screenOffSeconds += delta
        }
        let awayByScreen = screenOffSeconds >= settings.screenOffRestAfter
        let awayByInput = presence.isScreenOn
            && !presence.isWatchingMedia
            && !presence.isInCall
            && presence.idleSeconds >= settings.naturalRestAfter
        guard awayByScreen || awayByInput else { return nil }
        // Date the rest from when the user left, not from when we noticed.
        let awayFor = awayByScreen ? screenOffSeconds : presence.idleSeconds
        return endCycleNaturally(at: now, leftAt: now.addingTimeInterval(-awayFor))
    }

    private mutating func endCycleNaturally(at now: Date, leftAt: Date) -> [EyeTimerEvent] {
        var events: [EyeTimerEvent] = []
        let endedAt = max(leftAt, cycleStart ?? leftAt)
        if let record = makeRecord(outcome: .natural, endedAt: endedAt) {
            events.append(.cycleEnded(record))
        }
        let offSeconds = screenOffSeconds
        resetCycle()
        screenOffSeconds = offSeconds
        phase = .focusing
        isFocusPaused = true
        return events
    }

    private mutating func breakIfDue(at now: Date, presence: Presence) -> [EyeTimerEvent] {
        let due: Bool
        switch phase {
        case .focusing: due = focusedSeconds >= settings.focusInterval
        case .snoozed(let until): due = now >= until
        case .off, .resting: due = false
        }
        guard due else {
            isBreakDeferred = false
            return []
        }
        // Don't interrupt a call: the break starts as soon as it ends.
        if presence.isInCall {
            isBreakDeferred = true
            return []
        }
        isBreakDeferred = false
        // Nobody at the screen: wait. Either they come back (the break starts
        // then) or they stay away long enough for a natural rest.
        guard countsAsScreenTime(presence) else { return [] }
        beginRest(at: now)
        return [.breakStarted]
    }

    private mutating func finishRestIfDone(at now: Date) -> [EyeTimerEvent] {
        guard restedSeconds >= settings.breakDuration else { return [] }
        return finishRest(endedAt: now)
    }

    private mutating func finishRest(endedAt: Date) -> [EyeTimerEvent] {
        let record = makeRecord(outcome: .completed, endedAt: endedAt, force: true)
        resetCycle()
        phase = .focusing
        return record.map { [.cycleEnded($0)] } ?? []
    }

    private mutating func handleGap(_ gap: TimeInterval, endingAt now: Date, presence: Presence) -> [EyeTimerEvent] {
        let gapStart = now.addingTimeInterval(-gap)
        switch phase {
        case .off:
            return []

        case .resting:
            // Away from the screen during a break is exactly what a break is.
            isRestPausedByInput = false
            var credit = gap
            if settings.restRequiresStillness, presence.isScreenOn, gap < settings.screenOffRestAfter {
                // A short stall we didn't watch (not sleep): only the hands-off
                // part at the end of it can count.
                credit = min(gap, presence.idleSeconds)
            }
            let needed = max(settings.breakDuration - restedSeconds, 0)
            guard credit >= needed else {
                restedSeconds += credit
                return []
            }
            restedSeconds = settings.breakDuration
            let restEnd = now.addingTimeInterval(needed - credit)
            var events = finishRest(endedAt: restEnd)
            if settings.gapPolicy == .focus, now > restEnd {
                events += reconcileFocusedGap(from: restEnd, to: now)
            }
            return events

        case .focusing, .snoozed:
            switch settings.gapPolicy {
            case .away:
                // Asleep or suspended: not screen time. Long enough, and it's a rest.
                if gap >= settings.screenOffRestAfter {
                    return endCycleNaturally(at: now, leftAt: gapStart)
                }
                return []
            case .focus:
                return reconcileFocusedGap(from: gapStart, to: now)
            }
        }
    }

    /// iOS screen sessions: assume the user stayed on screens while the app was
    /// in the background. Every reminder that fired more than `missedGrace` ago
    /// counts as missed; a recent one starts the break now.
    private mutating func reconcileFocusedGap(from start: Date, to now: Date) -> [EyeTimerEvent] {
        var events: [EyeTimerEvent] = []
        var cursor = start
        if cycleStart == nil { cycleStart = start }

        // Bounded: each pass consumes at least one full interval of the gap.
        let maxCycles = 500
        for _ in 0..<maxCycles {
            let dueAt: Date
            if case .snoozed(let until) = phase {
                dueAt = max(until, cursor)
            } else {
                dueAt = cursor.addingTimeInterval(max(settings.focusInterval - focusedSeconds, 0))
            }

            if dueAt > now {
                focusedSeconds += now.timeIntervalSince(cursor)
                return events
            }
            focusedSeconds += dueAt.timeIntervalSince(cursor)

            if now.timeIntervalSince(dueAt) <= settings.missedGrace {
                // They kept using screens until they came back to rest.
                focusedSeconds += now.timeIntervalSince(dueAt)
                beginRest(at: now)
                events.append(.breakStarted)
                return events
            }

            if let record = makeRecord(outcome: .missed, endedAt: dueAt, force: true) {
                events.append(.cycleEnded(record))
            }
            resetCycle()
            phase = .focusing
            cycleStart = dueAt
            cursor = dueAt
        }
        // Absurdly long gap: start fresh instead of looping forever.
        resetCycle()
        phase = .focusing
        cycleStart = now
        return events
    }

    private mutating func beginRest(at now: Date) {
        phase = .resting(startedAt: now)
        restedSeconds = 0
        isRestPausedByInput = false
        isFocusPaused = false
        isBreakDeferred = false
    }

    private mutating func resetCycle() {
        focusedSeconds = 0
        restedSeconds = 0
        screenOffSeconds = 0
        cycleStart = nil
        snoozeCount = 0
        isRestPausedByInput = false
        isFocusPaused = false
        isBreakDeferred = false
    }

    private func makeRecord(outcome: CycleOutcome, endedAt: Date, force: Bool = false) -> CycleRecord? {
        guard force || focusedSeconds >= settings.minimumRecordedFocus else { return nil }
        return CycleRecord(
            startedAt: cycleStart ?? endedAt.addingTimeInterval(-focusedSeconds),
            endedAt: endedAt,
            focusedSeconds: focusedSeconds,
            restedSeconds: min(restedSeconds, settings.breakDuration),
            snoozeCount: snoozeCount,
            outcome: outcome
        )
    }
}
