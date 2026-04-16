import Foundation
import SwiftUI
import SwiftData
import Combine
import AudioToolbox

enum TimerState: String {
    case disabled
    case monitoring
    case breakPending
    case breakActive
}

@MainActor @Observable
final class TimerManager {
    // MARK: - Published State

    var state: TimerState = .disabled
    var breakSecondsRemaining: Int = 0
    var totalSessionsToday: Int = 0
    var breaksTakenToday: Int = 0
    var breaksSkippedToday: Int = 0

    // MARK: - Settings

    var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEnabled") }
    }

    // MARK: - Constants

    let intervalSeconds: Int = 1200 // 20 minutes

    // MARK: - macOS-only timer state

    #if os(macOS)
    var elapsedSeconds: Int = 0

    var progress: Double {
        guard intervalSeconds > 0 else { return 0 }
        return Swift.min(Double(elapsedSeconds % intervalSeconds) / Double(intervalSeconds), 1.0)
    }

    var secondsUntilBreak: Int {
        let cycleElapsed = elapsedSeconds % intervalSeconds
        return Swift.max(intervalSeconds - cycleElapsed, 0)
    }

    private var trackingStartDate: Date?
    private var savedElapsedSeconds: Int = 0
    private var nextBreakAtSeconds: Int = 0
    private var breakTriggerDate: Date?
    private var idlePaused = false
    #endif

    // MARK: - Internal

    private var timer: AnyCancellable?
    private var currentSession: ScreenSession?
    private var modelContext: ModelContext?
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    #if os(iOS)
    nonisolated(unsafe) private var darwinObserverRegistered = false
    #endif

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
        #if os(iOS)
        if darwinObserverRegistered {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(TWNIConstants.darwinBreakPendingNotification as CFString),
                nil
            )
        }
        #endif
    }

    // MARK: - Setup

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        resetSkipsIfNewDay()
        #if os(iOS)
        resetCycleCountIfNewDay()
        #endif
        loadTodayStats()
        enable()
        setupAppLifecycleObservers()
    }

    // MARK: - Controls

    func enable() {
        guard state == .disabled else { return }

        #if os(iOS)
        SharedDefaults.shared.breakCycleCount = 0
        SharedDefaults.shared.cycleStartDate = Date()
        screenTimeService?.registerAlwaysOnMonitor()
        startNewSession()
        state = .monitoring
        #elseif os(macOS)
        elapsedSeconds = 0
        savedElapsedSeconds = 0
        nextBreakAtSeconds = intervalSeconds
        breakTriggerDate = nil
        trackingStartDate = Date()
        startNewSession()
        state = .monitoring
        startTimer()
        #endif
    }

    func disable() {
        if state == .breakActive {
            stopTimer()
            recordBreak(completed: false)
            breaksSkippedToday += 1
        } else if state == .breakPending {
            recordBreak(completed: false)
            breaksSkippedToday += 1
        }

        state = .disabled
        stopTimer()
        endCurrentSession()
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        #if os(iOS)
        SharedDefaults.shared.cycleStartDate = nil
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = false
        SharedDefaults.shared.isBreakCountdownActive = false
        #elseif os(macOS)
        elapsedSeconds = 0
        savedElapsedSeconds = 0
        nextBreakAtSeconds = 0
        breakTriggerDate = nil
        idlePaused = false
        #endif
    }

    func claimBreak() {
        guard state == .breakPending else { return }

        state = .breakActive
        breakSecondsRemaining = 20
        notificationService.cancelPendingNotifications()

        #if os(iOS)
        SharedDefaults.shared.breakEndDate = Date().addingTimeInterval(20)
        SharedDefaults.shared.isBreakCountdownActive = true
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = true
        notificationService.scheduleBreakEndNotification(afterSeconds: 20)
        #endif

        startBreakCountdown()
    }

    func skipBreak() {
        guard state == .breakPending else { return }
        resetSkipsIfNewDay()
        guard canSkip else { return }

        #if os(iOS)
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = false
        SharedDefaults.shared.isBreakCountdownActive = false
        #endif
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()
        recordBreak(completed: false)
        breaksSkippedToday += 1
        skipsToday += 1

        #if os(iOS)
        resetCycleCountIfNewDay()
        SharedDefaults.shared.breakCycleCount += 1
        SharedDefaults.shared.cycleStartDate = Date()
        screenTimeService?.registerAlwaysOnMonitor()
        startNewSession()
        state = .monitoring
        #elseif os(macOS)
        resetAfterBreakMacOS()
        #endif
    }

    private func resetSkipsIfNewDay() {
        if let lastReset = lastSkipResetDate,
           Calendar.current.isDateInToday(lastReset) {
            return
        }
        skipsToday = 0
        lastSkipResetDate = Date()
    }

    // MARK: - Break Countdown (both platforms)

    private func startBreakCountdown() {
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
        stopTimer()
        if soundEnabled { playBreakEndFeedback() }
        notificationService.cancelBreakEndNotification()
        recordBreak(completed: true)
        breaksTakenToday += 1

        #if os(iOS)
        appBlockingService?.unblockApps()
        screenTimeService?.clearBreakState()
        SharedDefaults.shared.isBreakPending = false
        SharedDefaults.shared.isBreakActive = false
        SharedDefaults.shared.isBreakCountdownActive = false
        SharedDefaults.shared.breakEndDate = nil
        resetCycleCountIfNewDay()
        SharedDefaults.shared.breakCycleCount += 1
        SharedDefaults.shared.cycleStartDate = Date()
        screenTimeService?.registerAlwaysOnMonitor()
        endCurrentSession()
        startNewSession()
        state = .monitoring
        #elseif os(macOS)
        resetAfterBreakMacOS()
        #endif
    }

    // MARK: - iOS: Break Trigger (from DeviceActivity via SharedDefaults)

    #if os(iOS)
    private func triggerBreak() {
        state = .breakPending
        SharedDefaults.shared.blockReason = .eyeBreak
    }

    func handleExtensionBreakTrigger() {
        guard SharedDefaults.shared.isBreakPending, state == .monitoring else { return }
        triggerBreak()
    }
    #endif

    // MARK: - Sound & Vibration

    private func playBreakEndFeedback() {
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #else
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1007)
        #endif
    }

    // MARK: - macOS Timer Logic

    #if os(macOS)
    private func startTimer() {
        stopTimer()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard state == .monitoring, let start = trackingStartDate else { return }

        if !idlePaused {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }

        if elapsedSeconds >= nextBreakAtSeconds {
            triggerBreakMacOS()
        }
    }

    private func triggerBreakMacOS() {
        stopTimer()
        breakTriggerDate = Date()
        state = .breakPending
        notificationService.scheduleBreakNotification()
    }

    private func resetAfterBreakMacOS() {
        endCurrentSession()

        if let triggerDate = breakTriggerDate {
            let breakWallClock = Date().timeIntervalSince(triggerDate)
            trackingStartDate = trackingStartDate?.addingTimeInterval(breakWallClock)
        }
        breakTriggerDate = nil

        if trackingStartDate == nil {
            trackingStartDate = Date()
        }

        if let start = trackingStartDate {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }
        savedElapsedSeconds = elapsedSeconds
        nextBreakAtSeconds += intervalSeconds

        idlePaused = false
        startNewSession()
        state = .monitoring
        startTimer()
    }

    func handleIdlePause() {
        guard state == .monitoring else { return }
        idlePaused = true
    }

    func handleIdleResume() {
        guard state == .monitoring else { return }
        if idlePaused {
            idlePaused = false
            trackingStartDate = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
        }
    }
    #endif

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
            durationSeconds: completed ? 20 : 0,
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

        registerDarwinBreakObserver()
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

    // MARK: - iOS Darwin notification bridge

    #if os(iOS)
    private func registerDarwinBreakObserver() {
        guard !darwinObserverRegistered else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let manager = Unmanaged<TimerManager>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in manager.handleExtensionBreakTrigger() }
            },
            TWNIConstants.darwinBreakPendingNotification as CFString,
            nil,
            .deliverImmediately
        )
        darwinObserverRegistered = true
    }

    private func resetCycleCountIfNewDay() {
        let now = Date()
        guard let start = SharedDefaults.shared.cycleStartDate else {
            SharedDefaults.shared.cycleStartDate = now
            return
        }
        if !Calendar.current.isDateInToday(start) {
            SharedDefaults.shared.breakCycleCount = 0
            SharedDefaults.shared.cycleStartDate = now
        }
    }
    #endif

    // MARK: - iOS Lifecycle

    #if os(iOS)
    private func handleiOSBackground() {
        if state == .breakActive {
            stopTimer()
        }
    }

    private func handleiOSForeground() {
        notificationService.cancelPendingNotifications()
        resetCycleCountIfNewDay()

        if state == .breakActive {
            if let endDate = SharedDefaults.shared.breakEndDate {
                if Date() >= endDate {
                    completeBreak()
                } else {
                    breakSecondsRemaining = Swift.max(Int(endDate.timeIntervalSinceNow), 1)
                    startBreakCountdown()
                }
            }
            return
        }

        if SharedDefaults.shared.isBreakPending, state == .monitoring {
            triggerBreak()
        }
    }
    #endif

    // MARK: - macOS Lifecycle (wall-clock with idle detection)

    #if os(macOS)
    private func handleMacOSBackground() {
        if state == .monitoring, let start = trackingStartDate {
            let actualElapsed = Int(Date().timeIntervalSince(start))
            let remainingSeconds = nextBreakAtSeconds - actualElapsed
            if remainingSeconds > 0 {
                notificationService.scheduleTimerNotification(afterSeconds: remainingSeconds)
            }
        }
    }

    private func handleMacOSForeground() {
        stopTimer()
        idlePaused = false
        notificationService.cancelPendingNotifications()
        notificationService.cancelBreakEndNotification()

        let now = Date()

        if state == .monitoring, let start = trackingStartDate {
            let totalElapsed = Int(now.timeIntervalSince(start))
            elapsedSeconds = totalElapsed

            while nextBreakAtSeconds + intervalSeconds <= elapsedSeconds {
                nextBreakAtSeconds += intervalSeconds
            }

            if totalElapsed >= nextBreakAtSeconds {
                triggerBreakMacOS()
            } else {
                startTimer()
            }
        } else if state == .breakPending {
            // Still pending, keep showing overlay
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
