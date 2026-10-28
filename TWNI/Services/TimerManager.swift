import Foundation
import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
import AudioToolbox
#endif

/// Coarse state for compact UI (menu bar icon, status lines).
enum TimerState: String {
    case active
    case breakActive
    case disabled
}

enum TimerMode: String, CaseIterable, Identifiable {
    /// The classic 20-20-20 rule.
    case auto
    /// User-chosen interval and break length.
    case manual

    var id: String { rawValue }
}

/// How firmly a break holds the screen.
enum BreakStyle: String, CaseIterable, Identifiable {
    case gentle
    case standard
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .strict: "Strict"
        }
    }

    var summary: String {
        switch self {
        case .gentle: "Skip any break with one tap."
        case .standard: "Hold to skip. Snooze up to twice."
        case .strict: "No skipping or snoozing. It only takes a few seconds."
        }
    }

    var snoozesPerCycle: Int {
        switch self {
        case .gentle: 3
        case .standard: 2
        case .strict: 0
        }
    }

    var allowsSkip: Bool { self != .strict }
    var skipNeedsHold: Bool { self == .standard }
}

/// Owns the eye-break engine and connects it to the clock, storage,
/// notifications and (on macOS) presence detection and the break overlay.
/// Created once in `TWNIApp.init` and passed down to views.
@MainActor @Observable
final class TimerManager {
    // MARK: - Live state

    private(set) var engine = EyeTimerEngine()
    /// Refreshed every second so time-based views update.
    private(set) var now = Date()
    private(set) var todayRecords: [CycleRecord] = []
    /// Summaries for days before today (today is computed live).
    private(set) var pastSummaries: [Date: DaySummary] = [:]
    private(set) var lifetimeCompleted = 0
    private(set) var currentExercise: EyeExercise = EyeExerciseLibrary.all[0]
    /// The break that just finished, for the short "done" screen.
    private(set) var justCompleted: CycleRecord?
    /// macOS: protection is paused until this time.
    private(set) var pausedUntil: Date?
    /// iOS: the current screen session ends at this time.
    private(set) var sessionEndsAt: Date?
    private(set) var notificationPermission: NotificationPermission = .unknown

    // MARK: - Settings (stored so SwiftUI tracks them; persisted to UserDefaults)

    var timerMode: TimerMode {
        didSet { defaults.set(timerMode.rawValue, forKey: Keys.timerMode); applyEngineSettings() }
    }
    var intervalMinutes: Int {
        didSet { defaults.set(intervalMinutes, forKey: Keys.intervalMinutes); applyEngineSettings() }
    }
    var breakDurationSeconds: Int {
        didSet { defaults.set(breakDurationSeconds, forKey: Keys.breakDurationSeconds); applyEngineSettings() }
    }
    var breakStyle: BreakStyle {
        didSet { defaults.set(breakStyle.rawValue, forKey: Keys.breakStyle); applyEngineSettings() }
    }
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }
    /// Daily Break Score needed to extend the streak.
    var dailyGoal: Int {
        didSet { defaults.set(dailyGoal, forKey: Keys.dailyGoal) }
    }
    /// macOS: don't start a break while the microphone is in use.
    var holdBreaksDuringCalls: Bool {
        didSet { defaults.set(holdBreaksDuringCalls, forKey: Keys.holdBreaksDuringCalls) }
    }
    /// macOS: keep counting screen time while a video keeps the display awake.
    var countVideoAsScreenTime: Bool {
        didSet { defaults.set(countVideoAsScreenTime, forKey: Keys.countVideoAsScreenTime) }
    }
    /// From onboarding; used for the personal numbers on the plan screen.
    var dailyScreenHours: Int {
        didSet { defaults.set(dailyScreenHours, forKey: Keys.dailyScreenHours) }
    }
    private(set) var hasCompletedOnboarding: Bool
    /// macOS: the user turned protection on (it starts with the app).
    private(set) var isProtectionEnabled: Bool

    // MARK: - Internals

    private let defaults: UserDefaults
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var ticker: AnyCancellable?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var recordsByDay: [Date: [CycleRecord]] = [:]
    @ObservationIgnored private var currentDay: Date
    @ObservationIgnored private var lastSnapshotSave = Date.distantPast
    @ObservationIgnored private var isConfigured = false
    let notifications = NotificationService()

    #if os(macOS)
    private let presenceMonitor: MacPresenceMonitor
    @ObservationIgnored private var overlay: BreakOverlayController?
    #endif

    private enum Keys {
        static let timerMode = "timerMode"
        static let intervalMinutes = "intervalMinutes"
        static let breakDurationSeconds = "breakDurationSeconds"
        static let soundEnabled = "soundEnabled"
        static let breakStyle = "breakStyle"
        static let dailyGoal = "dailyGoal"
        static let holdBreaksDuringCalls = "holdBreaksDuringCalls"
        static let countVideoAsScreenTime = "countVideoAsScreenTime"
        static let dailyScreenHours = "dailyScreenHours"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let isProtectionEnabled = "isProtectionEnabled"
        static let pausedUntil = "pausedUntil"
        static let sessionEndsAt = "sessionEndsAt"
        static let engine = "engineSnapshot.v2"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timerMode = TimerMode(rawValue: defaults.string(forKey: Keys.timerMode) ?? "") ?? .auto
        intervalMinutes = Self.storedInt(defaults, Keys.intervalMinutes, default: 20, range: 5...90)
        breakDurationSeconds = Self.storedInt(defaults, Keys.breakDurationSeconds, default: 20, range: 10...120)
        breakStyle = BreakStyle(rawValue: defaults.string(forKey: Keys.breakStyle) ?? "") ?? .standard
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        dailyGoal = Self.storedInt(defaults, Keys.dailyGoal, default: Streak.defaultGoal, range: 10...100)
        holdBreaksDuringCalls = defaults.object(forKey: Keys.holdBreaksDuringCalls) as? Bool ?? true
        countVideoAsScreenTime = defaults.object(forKey: Keys.countVideoAsScreenTime) as? Bool ?? true
        dailyScreenHours = Self.storedInt(defaults, Keys.dailyScreenHours, default: 8, range: 1...16)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        isProtectionEnabled = defaults.object(forKey: Keys.isProtectionEnabled) as? Bool ?? true
        currentDay = Calendar.current.startOfDay(for: Date())
        #if os(macOS)
        presenceMonitor = MacPresenceMonitor()
        #endif
    }

    /// One-time setup. Safe to call more than once.
    func configure(modelContext: ModelContext) {
        guard !isConfigured else { return }
        isConfigured = true
        self.modelContext = modelContext

        notifications.onAction = { [weak self] action in
            self?.handleNotificationAction(action)
        }
        notifications.activate()

        #if os(macOS)
        presenceMonitor.start()
        overlay = BreakOverlayController(timerManager: self)
        #endif

        reloadHistory()
        restoreState()
        observeLifecycle()
        startTicker()
        if hasCompletedOnboarding { startProtectionIfNeeded() }
        Task { await refreshNotificationPermission() }
    }

    // MARK: - Derived values

    var state: TimerState {
        switch engine.phase {
        case .off: .disabled
        case .resting: .breakActive
        case .focusing, .snoozed: .active
        }
    }

    var effectiveIntervalMinutes: Int { timerMode == .auto ? 20 : intervalMinutes }
    var effectiveBreakDurationSeconds: Int { timerMode == .auto ? 20 : breakDurationSeconds }

    var secondsUntilBreak: Int { Int(engine.secondsUntilBreak.rounded(.up)) }
    var breakSecondsRemaining: Int { Int(engine.restRemaining.rounded(.up)) }
    var focusProgress: Double { engine.focusProgress }
    var breakProgress: Double { engine.restProgress }

    var isSnoozed: Bool {
        if case .snoozed = engine.phase { return true }
        return false
    }

    /// True while the break screen should be up (including a short "done" moment).
    var isShowingBreak: Bool {
        if engine.isResting { return true }
        if let done = justCompleted { return now.timeIntervalSince(done.endedAt) < 2.5 }
        return false
    }

    var currentPrompt: EyeExercise {
        EyeExerciseLibrary.prompt(
            for: currentExercise,
            restRemaining: engine.restRemaining,
            breakDuration: engine.settings.breakDuration
        )
    }

    var canSnooze: Bool { engine.canSnooze }
    var canSkip: Bool { breakStyle.allowsSkip }

    var today: DaySummary {
        DaySummary(day: currentDay, records: todayRecords, liveFocusSeconds: engine.focusedSeconds)
    }

    var todayScore: Int? {
        BreakScore.score(for: today, focusInterval: engine.settings.focusInterval)
    }

    /// Breaks taken today, counting the one in progress.
    var breakNumberToday: Int { today.completed + 1 }

    func summary(for day: Date) -> DaySummary {
        let start = Calendar.current.startOfDay(for: day)
        if start == currentDay { return today }
        return pastSummaries[start] ?? DaySummary(day: start)
    }

    /// The last seven days, oldest first, ending today.
    var lastSevenDays: [DaySummary] {
        (0..<7).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: currentDay).map(summary(for:))
        }
    }

    func score(for day: DaySummary) -> Int? {
        BreakScore.score(for: day, focusInterval: engine.settings.focusInterval)
    }

    func status(of day: DaySummary) -> DayStatus {
        Streak.status(of: day, goal: dailyGoal, focusInterval: engine.settings.focusInterval)
    }

    private var dayStatuses: [Date: DayStatus] {
        var statuses = pastSummaries.mapValues(status(of:))
        statuses[currentDay] = status(of: today)
        return statuses
    }

    var currentStreak: Int { Streak.current(statuses: dayStatuses, today: now) }
    var bestStreak: Int { max(Streak.best(statuses: dayStatuses), currentStreak) }

    /// One line describing what the timer is doing right now.
    var statusLine: String {
        switch engine.phase {
        case .off:
            #if os(macOS)
            if let pausedUntil {
                return "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
            }
            return "Eye breaks are off"
            #else
            return "No screen session running"
            #endif
        case .resting:
            return "Eye break in progress"
        case .snoozed(let until):
            return "Snoozed until \(until.formatted(date: .omitted, time: .shortened))"
        case .focusing:
            if engine.isBreakDeferred { return "Break waits until your call ends" }
            if engine.isFocusPaused { return "Paused while you're away" }
            return "Next eye break in \(secondsUntilBreak.countdownText)"
        }
    }

    // MARK: - Break commands

    func startBreakNow() {
        let date = Date()
        handle(engine.startBreak(at: date), at: date)
    }

    func skipBreak() {
        guard canSkip else { return }
        let date = Date()
        handle(engine.skipBreak(at: date), at: date)
    }

    func snoozeBreak() {
        let date = Date()
        handle(engine.snooze(at: date), at: date)
    }

    // MARK: - Protection (macOS) and sessions (iOS)

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.hasCompletedOnboarding)
        startProtectionIfNeeded()
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        defaults.set(false, forKey: Keys.hasCompletedOnboarding)
    }

    /// Turn eye breaks on (macOS) and clear any pause.
    func enable() {
        setProtectionEnabled(true)
        setPausedUntil(nil)
        startProtectionIfNeeded()
    }

    /// Turn eye breaks off until the user turns them back on.
    func disable() {
        setProtectionEnabled(false)
        setPausedUntil(nil)
        stopEngine()
    }

    /// Pause eye breaks for a while; they come back on their own.
    func pause(for duration: TimeInterval) {
        setPausedUntil(Date().addingTimeInterval(duration))
        stopEngine()
    }

    func pauseUntilTomorrow() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        setPausedUntil(tomorrow)
        stopEngine()
    }

    func resume() {
        setPausedUntil(nil)
        setProtectionEnabled(true)
        startProtectionIfNeeded()
    }

    /// iOS: the user is about to spend time on screens; remind them until `minutes` from now.
    func startSession(minutes: Int) {
        let date = Date()
        setSessionEnd(date.addingTimeInterval(TimeInterval(minutes * 60)))
        if !engine.isRunning { engine.start(at: date) }
        saveSnapshot()
    }

    func endSession() {
        finishSession(at: Date())
    }

    // MARK: - Notifications

    func requestNotificationPermission() async {
        await notifications.requestPermission()
        await refreshNotificationPermission()
    }

    func refreshNotificationPermission() async {
        notificationPermission = await notifications.permission()
    }

    private func handleNotificationAction(_ action: NotificationAction) {
        let date = Date()
        tick(at: date)
        switch action {
        case .open, .startBreak:
            // Tapping a reminder means "I'm resting now", even a late one.
            if engine.isRunning, !engine.isResting { startBreakNow() }
        case .snooze:
            if engine.isRunning, !engine.isResting { _ = engine.startBreak(at: date) }
            snoozeBreak()
        case .skip:
            if engine.isResting || isSnoozed {
                let events = engine.skipBreak(at: date)
                handle(events, at: date)
            }
        }
        #if os(iOS)
        if UIApplication.shared.applicationState != .active { scheduleBackgroundNotifications() }
        #endif
    }

    // MARK: - Clock

    private func startTicker() {
        ticker = Timer.publish(every: 1, tolerance: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick(at: date)
            }
    }

    private func tick(at date: Date) {
        now = date
        rollOverDayIfNeeded(date)

        #if os(macOS)
        if let pausedUntil, date >= pausedUntil { resume() }
        #else
        if let end = sessionEndsAt, date >= end {
            handle(engine.update(at: end, presence: .present), at: end, quiet: true)
            finishSession(at: end)
            return
        }
        #endif

        handle(engine.update(at: date, presence: currentPresence()), at: date)
        syncOverlay()
        if date.timeIntervalSince(lastSnapshotSave) > 15 { saveSnapshot() }
    }

    private func currentPresence() -> Presence {
        #if os(macOS)
        return presenceMonitor.snapshot(
            detectCalls: holdBreaksDuringCalls,
            detectVideo: countVideoAsScreenTime
        )
        #else
        // The timer only ticks while the app is on screen.
        return .present
        #endif
    }

    private func handle(_ events: [EyeTimerEvent], at date: Date, quiet: Bool = false) {
        guard !events.isEmpty else { return }
        for event in events {
            switch event {
            case .breakStarted:
                currentExercise = EyeExerciseLibrary.exercise(forBreakNumber: today.completed)
                justCompleted = nil
            case .snoozed:
                break
            case .cycleEnded(let record):
                store(record)
                if record.outcome == .completed, !quiet {
                    justCompleted = record
                    celebrateCompletedBreak()
                }
            }
        }
        saveSnapshot()
        syncOverlay()
    }

    private func applyEngineSettings() {
        var settings = EyeTimerSettings.classic
        settings.focusInterval = TimeInterval(effectiveIntervalMinutes * 60)
        settings.breakDuration = TimeInterval(effectiveBreakDurationSeconds)
        settings.maxSnoozesPerCycle = breakStyle.snoozesPerCycle
        #if os(macOS)
        settings.gapPolicy = .away
        // Hands off the keyboard and mouse while the break counts down.
        settings.restRequiresStillness = breakStyle != .gentle
        #else
        settings.gapPolicy = .focus
        settings.missedGrace = 10 * 60
        #endif
        engine.apply(settings)
    }

    private func startProtectionIfNeeded() {
        #if os(macOS)
        guard hasCompletedOnboarding, isProtectionEnabled, pausedUntil == nil, !engine.isRunning else { return }
        engine.start(at: Date())
        saveSnapshot()
        #endif
    }

    private func stopEngine() {
        let date = Date()
        handle(engine.stop(at: date), at: date)
        justCompleted = nil
        saveSnapshot()
        syncOverlay()
    }

    private func finishSession(at date: Date) {
        setSessionEnd(nil)
        handle(engine.stop(at: date), at: date, quiet: true)
        notifications.cancelAll()
        saveSnapshot()
    }

    private func syncOverlay() {
        #if os(macOS)
        // Wait for the first tick: during launch (App.init) it's too early for windows.
        guard ticker != nil else { return }
        overlay?.setVisible(isShowingBreak)
        #endif
    }

    private func celebrateCompletedBreak() {
        guard soundEnabled else { return }
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #else
        AudioServicesPlaySystemSound(1007)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - History

    private func store(_ record: CycleRecord) {
        let day = Calendar.current.startOfDay(for: record.endedAt)
        recordsByDay[day, default: []].append(record)
        if day == currentDay {
            todayRecords = recordsByDay[day] ?? []
        } else {
            pastSummaries[day] = DaySummary(day: day, records: recordsByDay[day] ?? [])
        }
        if record.outcome == .completed { lifetimeCompleted += 1 }

        guard let modelContext else { return }
        modelContext.insert(CycleEntry(record: record, device: Self.deviceName))
        do {
            try modelContext.save()
        } catch {
            print("TWNI: failed to save cycle: \(error)")
        }
    }

    private func reloadHistory() {
        guard let modelContext else { return }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -400, to: currentDay) ?? .distantPast
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate { $0.endedAt >= cutoff },
            sortBy: [SortDescriptor(\.endedAt)]
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []

        var byDay: [Date: [CycleRecord]] = [:]
        for entry in entries {
            byDay[calendar.startOfDay(for: entry.endedAt), default: []].append(entry.record)
        }
        recordsByDay = byDay
        todayRecords = byDay[currentDay] ?? []
        var past: [Date: DaySummary] = [:]
        for (day, records) in byDay where day != currentDay {
            past[day] = DaySummary(day: day, records: records)
        }
        pastSummaries = past

        let completed = CycleOutcome.completed.rawValue
        let countDescriptor = FetchDescriptor<CycleEntry>(predicate: #Predicate { $0.outcomeRaw == completed })
        lifetimeCompleted = (try? modelContext.fetchCount(countDescriptor)) ?? 0
    }

    private func rollOverDayIfNeeded(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != currentDay else { return }
        currentDay = day
        reloadHistory()
    }

    // MARK: - Persistence

    private func restoreState() {
        if let data = defaults.data(forKey: Keys.engine),
           let saved = try? JSONDecoder().decode(EyeTimerEngine.self, from: data) {
            engine = saved
        }
        pausedUntil = defaults.object(forKey: Keys.pausedUntil) as? Date
        sessionEndsAt = defaults.object(forKey: Keys.sessionEndsAt) as? Date
        applyEngineSettings()

        // Catch up on the time the app wasn't running, without celebrating it.
        let date = Date()
        #if os(iOS)
        if let end = sessionEndsAt, end <= date {
            handle(engine.update(at: end, presence: .present), at: end, quiet: true)
            finishSession(at: end)
        }
        #endif
        handle(engine.update(at: date, presence: currentPresence()), at: date, quiet: true)
    }

    private func saveSnapshot() {
        lastSnapshotSave = Date()
        if let data = try? JSONEncoder().encode(engine) {
            defaults.set(data, forKey: Keys.engine)
        }
    }

    private func setPausedUntil(_ date: Date?) {
        pausedUntil = date
        defaults.set(date, forKey: Keys.pausedUntil)
    }

    private func setSessionEnd(_ date: Date?) {
        sessionEndsAt = date
        defaults.set(date, forKey: Keys.sessionEndsAt)
    }

    private func setProtectionEnabled(_ enabled: Bool) {
        isProtectionEnabled = enabled
        defaults.set(enabled, forKey: Keys.isProtectionEnabled)
    }

    private static func storedInt(_ defaults: UserDefaults, _ key: String, default value: Int, range: ClosedRange<Int>) -> Int {
        guard defaults.object(forKey: key) != nil else { return value }
        return Swift.min(Swift.max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }

    private static var deviceName: String {
        #if os(macOS)
        return "mac"
        #else
        return "ios"
        #endif
    }

    // MARK: - App lifecycle

    private func observeLifecycle() {
        let center = NotificationCenter.default
        #if os(iOS)
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleBackground() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleForeground() }
        })
        #elseif os(macOS)
        lifecycleObservers.append(center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSnapshot() }
        })
        #endif
    }

    #if os(iOS)
    private func handleBackground() {
        tick(at: Date())
        saveSnapshot()
        scheduleBackgroundNotifications()
    }

    private func handleForeground() {
        notifications.cancelAll()
        tick(at: Date())
        Task { await refreshNotificationPermission() }
    }

    /// iOS can't run the timer in the background, so hand the next reminders
    /// to the system. They match how the engine catches up on return.
    private func scheduleBackgroundNotifications() {
        guard engine.isRunning else {
            notifications.cancelAll()
            return
        }
        let date = Date()
        let dates = ReminderPlanner.reminderDates(for: engine, now: date, until: sessionEndsAt)
        notifications.scheduleReminders(at: dates, breakSeconds: effectiveBreakDurationSeconds, sound: soundEnabled, now: date)
        if engine.isResting {
            notifications.scheduleRestDone(at: date.addingTimeInterval(engine.restRemaining), sound: soundEnabled, now: date)
        }
    }
    #endif
}
