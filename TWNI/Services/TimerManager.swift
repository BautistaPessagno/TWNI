import Foundation
import SwiftUI
import SwiftData
import Combine
import AudioToolbox

enum TimerState: String {
    case active
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

    var timerMode: TimerMode {
        get {
            TimerMode(rawValue: UserDefaults.standard.string(forKey: "timerMode") ?? "auto") ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "timerMode")
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
        return Swift.min(Double(elapsedSeconds) / Double(intervalSeconds), 1.0)
    }

    var breakProgress: Double {
        guard effectiveBreakDurationSeconds > 0 else { return 0 }
        return 1.0 - (Double(breakSecondsRemaining) / Double(effectiveBreakDurationSeconds))
    }

    var secondsUntilBreak: Int {
        Swift.max(intervalSeconds - elapsedSeconds, 0)
    }

    // MARK: - Internal

    private var timer: AnyCancellable?
    private var trackingStartDate: Date?
    private var breakStartDate: Date?
    private var currentSession: ScreenSession?
    private var modelContext: ModelContext?
    private var idlePaused = false
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []

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
        loadTodayStats()
        enable()
        setupAppLifecycleObservers()
    }

    // MARK: - Controls

    func enable() {
        guard state == .disabled else { return }
        elapsedSeconds = 0
        trackingStartDate = Date()
        startNewSession()
        state = .active
        startTimer()
    }

    func disable() {
        state = .disabled
        elapsedSeconds = 0
        idlePaused = false
        stopTimer()
        endCurrentSession()
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        #if os(iOS)
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        #endif
    }

    func startBreak() {
        state = .breakActive
        breakStartDate = Date()
        breakSecondsRemaining = effectiveBreakDurationSeconds
        startBreakTimer()
        notificationService.scheduleBreakNotification()
        notificationService.scheduleBreakEndNotification(afterSeconds: effectiveBreakDurationSeconds)

        #if os(iOS)
        appBlockingService?.blockApps()
        SharedDefaults.shared.isBreakActive = true
        SharedDefaults.shared.breakEndDate = Date().addingTimeInterval(
            TimeInterval(effectiveBreakDurationSeconds)
        )
        SharedDefaults.shared.blockReason = .eyeBreak
        #endif
    }

    func skipBreak() {
        if state == .breakActive {
            #if os(iOS)
            appBlockingService?.unblockApps()
            screenTimeService?.clearBreakState()
            #endif
        }
        notificationService.cancelBreakEndNotification()
        recordBreak(completed: false)
        breaksSkippedToday += 1
        resetAfterBreak()
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

        if elapsedSeconds >= intervalSeconds {
            triggerBreak()
        }
    }

    private func triggerBreak() {
        stopTimer()
        startBreak()
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
        elapsedSeconds = 0
        idlePaused = false
        trackingStartDate = Date()
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

    // MARK: - iOS Lifecycle (wall-clock: background time counts toward interval)

    #if os(iOS)
    private func handleiOSBackground() {
        stopTimer()

        if state == .active {
            let remainingSeconds = intervalSeconds - elapsedSeconds
            if remainingSeconds > 0 {
                notificationService.scheduleTimerNotification(afterSeconds: remainingSeconds)
                notificationService.scheduleBreakEndNotification(
                    afterSeconds: remainingSeconds + effectiveBreakDurationSeconds
                )
            }
        } else if state == .breakActive {
            notificationService.cancelBreakEndNotification()
            if breakSecondsRemaining > 0 {
                notificationService.scheduleBreakEndNotification(afterSeconds: breakSecondsRemaining)
            }
        }
    }

    private func handleiOSForeground() {
        stopTimer()
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        let now = Date()

        while true {
            if state == .active, let start = trackingStartDate {
                let totalElapsed = Int(now.timeIntervalSince(start))

                if totalElapsed < intervalSeconds {
                    elapsedSeconds = totalElapsed
                    startTimer()
                    return
                } else {
                    state = .breakActive
                    breakStartDate = start.addingTimeInterval(TimeInterval(intervalSeconds))
                    breakSecondsRemaining = effectiveBreakDurationSeconds
                    appBlockingService?.blockApps()
                    SharedDefaults.shared.isBreakActive = true
                    SharedDefaults.shared.breakEndDate = breakStartDate?.addingTimeInterval(
                        TimeInterval(effectiveBreakDurationSeconds)
                    )
                    SharedDefaults.shared.blockReason = .eyeBreak
                }
            } else if state == .breakActive, let breakStart = breakStartDate {
                let breakElapsed = Int(now.timeIntervalSince(breakStart))

                if breakElapsed < effectiveBreakDurationSeconds {
                    breakSecondsRemaining = effectiveBreakDurationSeconds - breakElapsed
                    startBreakTimer()
                    return
                } else {
                    appBlockingService?.unblockApps()
                    screenTimeService?.clearBreakState()
                    recordBreak(completed: true)
                    breaksTakenToday += 1

                    let breakEndTime = breakStart.addingTimeInterval(
                        TimeInterval(effectiveBreakDurationSeconds)
                    )
                    breakStartDate = nil
                    endCurrentSession()
                    elapsedSeconds = 0
                    trackingStartDate = breakEndTime
                    startNewSession()
                    state = .active
                }
            } else {
                return
            }
        }
    }
    #endif

    // MARK: - macOS Lifecycle (wall-clock with idle detection, unchanged)

    #if os(macOS)
    private func handleMacOSBackground() {
        if state == .active {
            let remainingSeconds = intervalSeconds - elapsedSeconds
            if remainingSeconds > 0 {
                notificationService.scheduleTimerNotification(afterSeconds: remainingSeconds)
                notificationService.scheduleBreakEndNotification(
                    afterSeconds: remainingSeconds + effectiveBreakDurationSeconds
                )
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
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        let now = Date()

        while true {
            if state == .active, let start = trackingStartDate {
                let totalElapsed = Int(now.timeIntervalSince(start))

                if totalElapsed < intervalSeconds {
                    elapsedSeconds = totalElapsed
                    startTimer()
                    return
                } else {
                    state = .breakActive
                    breakStartDate = start.addingTimeInterval(TimeInterval(intervalSeconds))
                    breakSecondsRemaining = effectiveBreakDurationSeconds
                }
            } else if state == .breakActive, let breakStart = breakStartDate {
                let breakElapsed = Int(now.timeIntervalSince(breakStart))

                if breakElapsed < effectiveBreakDurationSeconds {
                    breakSecondsRemaining = effectiveBreakDurationSeconds - breakElapsed
                    startBreakTimer()
                    return
                } else {
                    recordBreak(completed: true)
                    breaksTakenToday += 1

                    let breakEndTime = breakStart.addingTimeInterval(
                        TimeInterval(effectiveBreakDurationSeconds)
                    )
                    breakStartDate = nil
                    endCurrentSession()
                    elapsedSeconds = 0
                    idlePaused = false
                    trackingStartDate = breakEndTime
                    startNewSession()
                    state = .active
                }
            } else {
                return
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
