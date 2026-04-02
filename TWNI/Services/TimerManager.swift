import Foundation
import SwiftUI
import SwiftData
import Combine
import AudioToolbox

enum TimerState: String {
    case active
    case breakPending
    case breakActive
    case disabled
}

enum TimerMode: String {
    case auto
    case manual
}

@MainActor @Observable
final class TimerManager {
    // MARK: - Published State

    var state: TimerState = .disabled
    var elapsedSeconds: Int = 0
    var breakSecondsRemaining: Int = 20
    var totalSessionsToday: Int = 0
    var breaksTakenToday: Int = 0
    var breaksSkippedToday: Int = 0

    // MARK: - Settings

    var timerMode: TimerMode = TimerMode(rawValue: UserDefaults.standard.string(forKey: "timerMode") ?? "auto") ?? .auto {
        didSet {
            UserDefaults.standard.set(timerMode.rawValue, forKey: "timerMode")
        }
    }

    var intervalMinutes: Int {
        get { UserDefaults.standard.integer(forKey: "intervalMinutes").clamped(to: 1...120, default: 20) }
        set { UserDefaults.standard.set(newValue, forKey: "intervalMinutes") }
    }

    var breakDurationSeconds: Int {
        get { UserDefaults.standard.integer(forKey: "breakDurationSeconds").clamped(to: 5...120, default: 20) }
        set { UserDefaults.standard.set(newValue, forKey: "breakDurationSeconds") }
    }

    var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEnabled") }
    }

    // MARK: - Computed

    var effectiveIntervalMinutes: Int {
        timerMode == .auto ? 20 : intervalMinutes
    }

    var effectiveBreakDurationSeconds: Int {
        timerMode == .auto ? 20 : breakDurationSeconds
    }

    var intervalSeconds: Int { effectiveIntervalMinutes * 60 }

    var progress: Double {
        guard intervalSeconds > 0 else { return 0 }
        return Swift.min(Double(elapsedSeconds % intervalSeconds) / Double(intervalSeconds), 1.0)
    }

    var breakProgress: Double {
        guard effectiveBreakDurationSeconds > 0 else { return 0 }
        return 1.0 - (Double(breakSecondsRemaining) / Double(effectiveBreakDurationSeconds))
    }

    var secondsUntilBreak: Int {
        Swift.max(nextBreakAtSeconds - elapsedSeconds, 0)
    }

    // MARK: - Internal

    private var timer: AnyCancellable?
    private var trackingStartDate: Date?
    private var breakStartDate: Date?
    private var savedElapsedSeconds: Int = 0
    private var nextBreakAtSeconds: Int = 0
    private var breakTriggerDate: Date?
    private var currentSession: ScreenSession?
    private var modelContext: ModelContext?
    private var idlePaused = false
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []

    // Skip cooldown
    private let maxSkipsPerDay = 3

    var skipsToday: Int {
        get { UserDefaults.standard.integer(forKey: "skipsToday") }
        set { UserDefaults.standard.set(newValue, forKey: "skipsToday") }
    }

    private var lastSkipResetDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastSkipResetDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastSkipResetDate") }
    }

    var canSkip: Bool {
        skipsToday < maxSkipsPerDay
    }

    var remainingSkips: Int {
        Swift.max(maxSkipsPerDay - skipsToday, 0)
    }

    private(set) var notificationService = NotificationService()

    #if os(iOS)
    var appBlockingService: AppBlockingService?
    var screenTimeService: iOSScreenTimeService?
    #endif

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Setup

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        resetSkipsIfNewDay()
        loadTodayStats()
        enable()
        setupAppLifecycleObservers()
    }

    // MARK: - Controls

    func enable() {
        guard state == .disabled else { return }
        elapsedSeconds = 0
        savedElapsedSeconds = 0
        nextBreakAtSeconds = intervalSeconds
        breakTriggerDate = nil
        trackingStartDate = Date()
        startNewSession()
        state = .active
        startTimer()
    }

    func disable() {
        state = .disabled
        elapsedSeconds = 0
        savedElapsedSeconds = 0
        nextBreakAtSeconds = 0
        breakTriggerDate = nil
        idlePaused = false
        stopTimer()
        endCurrentSession()
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        #if os(iOS)
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        SharedDefaults.shared.isBreakPending = false
        #endif
    }

    func claimBreak() {
        guard state == .breakPending else { return }
        state = .breakActive
        breakStartDate = Date()
        breakSecondsRemaining = effectiveBreakDurationSeconds
        startBreakTimer()
        notificationService.scheduleBreakEndNotification(afterSeconds: effectiveBreakDurationSeconds)

        #if os(iOS)
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = true
        SharedDefaults.shared.breakEndDate = Date().addingTimeInterval(
            TimeInterval(effectiveBreakDurationSeconds)
        )
        #endif
    }

    func skipBreak() {
        guard state == .breakActive || state == .breakPending else { return }
        resetSkipsIfNewDay()
        guard canSkip else { return }

        #if os(iOS)
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = false
        #endif
        notificationService.cancelBreakEndNotification()
        recordBreak(completed: false)
        breaksSkippedToday += 1
        skipsToday += 1
        resetAfterBreak()
    }

    private func resetSkipsIfNewDay() {
        if let lastReset = lastSkipResetDate,
           Calendar.current.isDateInToday(lastReset) {
            return
        }
        skipsToday = 0
        lastSkipResetDate = Date()
    }

    func updateTimerMode(_ newMode: TimerMode) {
        timerMode = newMode
        if state == .breakActive || state == .breakPending {
            // Force reset — mode change overrides skip cooldown
            #if os(iOS)
            appBlockingService?.unblockApps()
            screenTimeService?.clearBreakState()
            SharedDefaults.shared.isBreakPending = false
            SharedDefaults.shared.isBreakActive = false
            #endif
            notificationService.cancelBreakEndNotification()
            recordBreak(completed: false)
            breaksSkippedToday += 1
            resetAfterBreak()
        } else if state == .active {
            elapsedSeconds = 0
            savedElapsedSeconds = 0
            nextBreakAtSeconds = effectiveIntervalMinutes * 60
            breakTriggerDate = nil
            trackingStartDate = Date()
            stopTimer()
            startTimer()
        }
        #if os(iOS)
        SharedDefaults.shared.intervalMinutes = effectiveIntervalMinutes
        SharedDefaults.shared.breakDurationSeconds = effectiveBreakDurationSeconds
        screenTimeService?.restartAlwaysOnMonitor()
        #endif
    }

    func handleIntervalChanged() {
        guard state == .active else { return }
        nextBreakAtSeconds = elapsedSeconds + intervalSeconds
    }

    // MARK: - Idle Detection (macOS)

    func handleIdlePause() {
        guard state == .active else { return }
        idlePaused = true
    }

    func handleIdleResume() {
        guard state == .active else { return }
        if idlePaused {
            idlePaused = false
            trackingStartDate = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
        }
    }

    // MARK: - Timer Logic

    private func startTimer() {
        stopTimer()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard state == .active, let start = trackingStartDate else { return }

        if !idlePaused {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }

        #if os(iOS)
        // Pick up breaks triggered by DeviceActivity extension
        if SharedDefaults.shared.isBreakPending {
            stopTimer()
            state = .breakPending
            notificationService.scheduleBreakNotification()
            SharedDefaults.shared.blockReason = .eyeBreak
            appBlockingService?.blockApps()
            return
        }
        #endif
        // Trigger break when cumulative screen time crosses next boundary
        if elapsedSeconds >= nextBreakAtSeconds {
            triggerBreak()
        }
    }

    private func triggerBreak() {
        stopTimer()
        breakTriggerDate = Date()
        state = .breakPending
        notificationService.scheduleBreakNotification()

        #if os(iOS)
        SharedDefaults.shared.isBreakPending = true
        SharedDefaults.shared.blockReason = .eyeBreak
        appBlockingService?.blockApps()
        #endif
    }

    private func startBreakTimer() {
        stopTimer()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.breakTick()
            }
    }

    private func breakTick() {
        guard state == .breakActive else { return }

        breakSecondsRemaining -= 1

        if breakSecondsRemaining <= 0 {
            completeBreak()
        }
    }

    private func completeBreak() {
        #if os(iOS)
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = false
        #endif
        notificationService.cancelBreakEndNotification()
        if soundEnabled { playBreakEndSound() }
        recordBreak(completed: true)
        breaksTakenToday += 1
        resetAfterBreak()
    }

    private func playBreakEndSound() {
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #else
        AudioServicesPlaySystemSound(1007)
        #endif
    }

    private func resetAfterBreak() {
        breakStartDate = nil
        endCurrentSession()

        // Exclude break wall-clock time from cumulative screen time
        if let triggerDate = breakTriggerDate {
            let breakWallClock = Date().timeIntervalSince(triggerDate)
            trackingStartDate = trackingStartDate?.addingTimeInterval(breakWallClock)
        }
        breakTriggerDate = nil

        // Sync elapsedSeconds immediately so it's correct if the app
        // backgrounds between now and the next tick
        if let start = trackingStartDate {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }
        savedElapsedSeconds = elapsedSeconds

        // Advance to next cycle boundary
        nextBreakAtSeconds += intervalSeconds

        idlePaused = false
        startNewSession()
        state = .active
        startTimer()

        #if os(iOS)
        screenTimeService?.restartAlwaysOnMonitor()
        #endif
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Persistence

    private func startNewSession() {
        guard let modelContext else { return }
        let session = ScreenSession(startDate: .now)
        modelContext.insert(session)
        currentSession = session
        totalSessionsToday += 1
        do {
            try modelContext.save()
        } catch {
            print("Failed to save new session: \(error)")
        }
    }

    private func endCurrentSession() {
        guard let session = currentSession else { return }
        session.endDate = .now
        session.durationSeconds = Int(Date().timeIntervalSince(session.startDate))
        do {
            try modelContext?.save()
        } catch {
            print("Failed to save session end: \(error)")
        }
        currentSession = nil
    }

    private func recordBreak(completed: Bool) {
        guard let modelContext, let session = currentSession else { return }
        let record = BreakRecord(
            timestamp: .now,
            completed: completed,
            durationSeconds: completed ? effectiveBreakDurationSeconds : 0,
            session: session
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save break record: \(error)")
        }
    }

    private func loadTodayStats() {
        guard let modelContext else { return }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let descriptor = FetchDescriptor<ScreenSession>(
            predicate: #Predicate { $0.startDate >= startOfDay }
        )

        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        totalSessionsToday = sessions.count
        let allBreaks = sessions.flatMap(\.breaks)
        breaksTakenToday = allBreaks.filter(\.completed).count
        breaksSkippedToday = allBreaks.filter { !$0.completed }.count
    }

    // MARK: - App Lifecycle

    private func setupAppLifecycleObservers() {
        #if os(iOS)
        let resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleiOSBackground()
            }
        }

        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleiOSForeground()
            }
        }

        lifecycleObservers = [resignObserver, activeObserver]
        #elseif os(macOS)
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMacOSBackground()
            }
        }

        let activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMacOSForeground()
            }
        }

        lifecycleObservers = [resignObserver, activeObserver]
        #endif
    }

    // MARK: - iOS Lifecycle (foreground-only: timer pauses when backgrounded)

    #if os(iOS)
    private func handleiOSBackground() {
        savedElapsedSeconds = elapsedSeconds
        stopTimer()

        if state == .breakActive, breakSecondsRemaining > 0 {
            notificationService.scheduleBreakEndNotification(afterSeconds: breakSecondsRemaining)
        }
    }

    private func handleiOSForeground() {
        stopTimer()
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        // Extension triggered break while backgrounded
        if SharedDefaults.shared.isBreakPending, state == .active {
            state = .breakPending
            notificationService.scheduleBreakNotification()
            SharedDefaults.shared.blockReason = .eyeBreak
            appBlockingService?.blockApps()
            return
        }

        // Break was already claimed (e.g. via notification action)
        if SharedDefaults.shared.isBreakActive, state == .breakActive || state == .breakPending {
            if let endDate = SharedDefaults.shared.breakEndDate {
                let remaining = Int(endDate.timeIntervalSinceNow)
                if remaining > 0 {
                    breakSecondsRemaining = remaining
                    state = .breakActive
                    startBreakTimer()
                    return
                } else {
                    completeBreak()
                    return
                }
            }
        }

        if state == .active, let start = trackingStartDate {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
            // Catch up past any fully-missed cycles
            while nextBreakAtSeconds + intervalSeconds <= elapsedSeconds {
                nextBreakAtSeconds += intervalSeconds
            }
            if elapsedSeconds >= nextBreakAtSeconds {
                triggerBreak()
            } else {
                startTimer()
            }
        }
    }
    #endif

    // MARK: - macOS Lifecycle (wall-clock with idle detection)

    #if os(macOS)
    private func handleMacOSBackground() {
        if state == .active, let start = trackingStartDate {
            let actualElapsed = Int(Date().timeIntervalSince(start))
            let remainingSeconds = nextBreakAtSeconds - actualElapsed
            if remainingSeconds > 0 {
                notificationService.scheduleTimerNotification(afterSeconds: remainingSeconds)
            }
        } else if state == .breakActive {
            notificationService.cancelBreakEndNotification()
            if breakSecondsRemaining > 0 {
                notificationService.scheduleBreakEndNotification(afterSeconds: breakSecondsRemaining)
            }
        }
    }

    private func handleMacOSForeground() {
        stopTimer()
        idlePaused = false
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        let now = Date()

        if state == .active, let start = trackingStartDate {
            let totalElapsed = Int(now.timeIntervalSince(start))
            elapsedSeconds = totalElapsed

            // Catch up past any fully-missed cycles
            while nextBreakAtSeconds + intervalSeconds <= elapsedSeconds {
                nextBreakAtSeconds += intervalSeconds
            }

            if totalElapsed >= nextBreakAtSeconds {
                triggerBreak()
            } else {
                startTimer()
            }
        } else if state == .breakPending {
            // Still pending, keep showing overlay
        } else if state == .breakActive, let breakStart = breakStartDate {
            let breakElapsed = Int(now.timeIntervalSince(breakStart))

            if breakElapsed < effectiveBreakDurationSeconds {
                breakSecondsRemaining = effectiveBreakDurationSeconds - breakElapsed
                startBreakTimer()
            } else {
                completeBreak()
            }
        }
    }
    #endif
}

// MARK: - Helpers

private extension Int {
    func clamped(to range: ClosedRange<Int>, default defaultValue: Int) -> Int {
        if self == 0 { return defaultValue }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
