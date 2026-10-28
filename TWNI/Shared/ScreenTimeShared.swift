#if os(iOS)
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
@preconcurrency import UserNotifications

// Shared by the TWNI app and its three Screen Time extensions (device activity
// monitor, shield configuration, shield action), through the App Group.
//
// The mechanism is the one Opal-style apps use:
// 1. DeviceActivity counts only the time the user spends in the monitored apps
//    (all apps, or the ones they picked), whether TWNI is open or not.
// 2. When that time reaches the interval, the monitor extension shields the apps.
// 3. The shield asks for an eye break. The user can do it on the shield itself
//    (start, look away, tap Done) or in TWNI's guided break (notification).
// 4. Finishing or skipping the break removes the shield, logs the cycle for the
//    app to import, and starts counting again from zero.

enum ScreenTimeShared {
    static let appGroup = "group.com.twni.app"
    static let activity = DeviceActivityName("twni.screen")
    static let store = ManagedSettingsStore.Name("twni.break")
    static let notificationCategory = "SCREEN_TIME_BREAK"

    enum Mode: String, Codable, Sendable {
        case off
        case allApps
        case selectedApps
    }

    /// One finished cycle, written by an extension or the app, imported by the app.
    struct LoggedCycle: Codable, Sendable {
        var id = UUID()
        var startedAt: Date
        var endedAt: Date
        var focusedSeconds: Double
        var restedSeconds: Double
        /// `CycleOutcome` raw value ("completed", "skipped").
        var outcome: String
    }

    private enum Key {
        static let mode = "st.mode"
        static let selection = "st.selection"
        static let intervalMinutes = "st.intervalMinutes"
        static let breakSeconds = "st.breakSeconds"
        static let generation = "st.generation"
        static let armedAt = "st.armedAt"
        static let shieldedAt = "st.shieldedAt"
        static let restStartedAt = "st.restStartedAt"
        static let log = "st.log"
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    // MARK: - Settings

    static var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Key.selection),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.selection) }
    }

    static var intervalMinutes: Int {
        get { defaults.integer(forKey: Key.intervalMinutes).nonZero(or: 20) }
        set { defaults.set(newValue, forKey: Key.intervalMinutes) }
    }

    static var breakSeconds: Int {
        get { defaults.integer(forKey: Key.breakSeconds).nonZero(or: 20) }
        set { defaults.set(newValue, forKey: Key.breakSeconds) }
    }

    // MARK: - State

    /// Bumped every time counting restarts, so stale callbacks can be ignored.
    static var generation: Int {
        get { defaults.integer(forKey: Key.generation) }
        set { defaults.set(newValue, forKey: Key.generation) }
    }

    /// When counting toward the current break started.
    static var armedAt: Date? {
        get { defaults.object(forKey: Key.armedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.armedAt) }
    }

    /// When the apps were locked for the current break (nil: not locked).
    static var shieldedAt: Date? {
        get { defaults.object(forKey: Key.shieldedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.shieldedAt) }
    }

    /// When the user started looking away on the shield.
    static var restStartedAt: Date? {
        get { defaults.object(forKey: Key.restStartedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.restStartedAt) }
    }

    static var isShieldActive: Bool { shieldedAt != nil }

    static func eventName(for generation: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("twni.due.\(generation)")
    }

    // MARK: - Counting

    /// Starts counting app use toward the next break, from zero.
    /// `thresholdMinutes` overrides the interval (used to re-arm after an early callback).
    static func arm(now: Date = Date(), thresholdMinutes: Int? = nil, resetStart: Bool = true) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        guard mode != .off else { return }

        generation += 1
        if resetStart || armedAt == nil { armedAt = now }

        // A repeating day-long window; the threshold counts from the moment we
        // start monitoring (includesPastActivity: false), and from midnight
        // after the day rolls over. Start and end use the same components.
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let threshold = DateComponents(minute: max(thresholdMinutes ?? intervalMinutes, 1))
        let event: DeviceActivityEvent
        switch mode {
        case .selectedApps:
            let picked = selection
            event = DeviceActivityEvent(
                applications: picked.applicationTokens,
                categories: picked.categoryTokens,
                webDomains: picked.webDomainTokens,
                threshold: threshold,
                includesPastActivity: false
            )
        case .allApps, .off:
            // No apps listed: the event counts all device use.
            event = DeviceActivityEvent(
                applications: [],
                categories: [],
                webDomains: [],
                threshold: threshold,
                includesPastActivity: false
            )
        }
        try center.startMonitoring(activity, during: schedule, events: [eventName(for: generation): event])
    }

    static func stopCounting() {
        DeviceActivityCenter().stopMonitoring([activity])
        clearShield()
        armedAt = nil
    }

    // MARK: - Shield

    /// Locks the monitored apps until the eye break is done.
    static func applyShield(now: Date = Date()) {
        let settings = ManagedSettingsStore(named: store)
        switch mode {
        case .allApps:
            settings.shield.applicationCategories = .all()
            settings.shield.webDomainCategories = .all()
        case .selectedApps:
            let picked = selection
            settings.shield.applications = picked.applicationTokens.isEmpty ? nil : picked.applicationTokens
            settings.shield.applicationCategories = picked.categoryTokens.isEmpty ? nil : .specific(picked.categoryTokens)
            settings.shield.webDomains = picked.webDomainTokens.isEmpty ? nil : picked.webDomainTokens
        case .off:
            return
        }
        shieldedAt = now
        restStartedAt = nil
    }

    static func clearShield() {
        ManagedSettingsStore(named: store).clearAllSettings()
        shieldedAt = nil
        restStartedAt = nil
    }

    /// Ends the current break: logs it, unlocks the apps and starts counting again.
    static func finishBreak(outcome: String, restedSeconds: Double, now: Date = Date()) {
        let focused = Double(intervalMinutes * 60)
        let start = armedAt ?? now.addingTimeInterval(-focused)
        appendLog(LoggedCycle(
            startedAt: start,
            endedAt: now,
            focusedSeconds: focused,
            restedSeconds: restedSeconds,
            outcome: outcome
        ))
        clearShield()
        try? arm(now: now)
    }

    // MARK: - Log

    static func appendLog(_ cycle: LoggedCycle) {
        var log = readLog()
        log.append(cycle)
        defaults.set(try? JSONEncoder().encode(Array(log.suffix(500))), forKey: Key.log)
    }

    /// Returns and removes the cycles waiting to be imported by the app.
    static func drainLog() -> [LoggedCycle] {
        let log = readLog()
        if !log.isEmpty { defaults.removeObject(forKey: Key.log) }
        return log
    }

    private static func readLog() -> [LoggedCycle] {
        guard let data = defaults.data(forKey: Key.log),
              let log = try? JSONDecoder().decode([LoggedCycle].self, from: data) else { return [] }
        return log
    }

    // MARK: - Notifications (sent from the extensions)

    /// "Time for an eye break": tapping it opens TWNI's guided break.
    static func notifyBreakDue() {
        notify(
            id: "screen-time-due",
            title: "Time for an eye break",
            body: "You've used your apps for \(intervalMinutes) minutes. Tap for a guided \(breakSeconds)-second break.",
            after: 1
        )
    }

    /// Sent when the user asks for the guided break from the shield.
    static func notifyOpenApp() {
        notify(id: "screen-time-open", title: "Your eye break is ready", body: "Tap to open TWNI and start it.", after: 1)
    }

    /// Lets the user know they can tap Done on the shield.
    static func notifyRestDone(after seconds: Int) {
        notify(id: "screen-time-rest-done", title: "\(breakSeconds) seconds done", body: "Tap Done to unlock your apps.", after: seconds)
    }

    private static func notify(id: String, title: String, body: String, after seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.categoryIdentifier = notificationCategory
        content.threadIdentifier = "eye-breaks"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(seconds, 1)), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self > 0 ? self : fallback }
}
#endif
