import Foundation
@preconcurrency import UserNotifications

enum NotificationPermission: Sendable {
    case unknown
    case notAsked
    case allowed
    case denied
}

/// Local notifications for iOS screen sessions, and the delegate that routes
/// taps and action buttons back to `TimerManager`. macOS doesn't need
/// reminders: it shows a full-screen break instead.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    /// Set by `TimerManager`; always called on the main actor.
    @MainActor var onAction: (@MainActor (NotificationAction) -> Void)?

    private enum ID {
        static let category = "BREAK_REMINDER"
        /// Strict mode: no Skip or Snooze on the notification either.
        static let strictCategory = "BREAK_REMINDER_STRICT"
        static let noSnoozeCategory = "BREAK_REMINDER_NO_SNOOZE"
        static let start = NotificationAction.Identifier.start
        static let snooze = NotificationAction.Identifier.snooze
        static let skip = NotificationAction.Identifier.skip
        static let restDone = NotificationAction.Identifier.restDone
        static func reminder(_ index: Int) -> String { "reminder-\(index)" }
    }

    /// Must run before the app finishes launching so actions on a notification
    /// that launched the app are delivered.
    func activate() {
        center.delegate = self
        let start = UNNotificationAction(identifier: ID.start, title: "Rest my eyes", options: .foreground)
        let snooze = UNNotificationAction(identifier: ID.snooze, title: "In 5 minutes", options: [])
        let skip = UNNotificationAction(identifier: ID.skip, title: "Skip", options: .destructive)
        let category = UNNotificationCategory(
            identifier: ID.category,
            actions: [start, snooze, skip],
            intentIdentifiers: []
        )
        let strict = UNNotificationCategory(
            identifier: ID.strictCategory,
            actions: [start],
            intentIdentifiers: []
        )
        let noSnooze = UNNotificationCategory(
            identifier: ID.noSnoozeCategory,
            actions: [start, skip],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category, strict, noSnooze])
    }

    // MARK: - Permission

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .authorized, .provisional: return .allowed
        #if os(iOS)
        case .ephemeral: return .allowed  // App Clips only; unavailable on macOS
        #endif
        @unknown default: return .unknown
        }
    }

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Scheduling

    /// Replaces every pending reminder with one per date.
    func scheduleReminders(
        at dates: [Date],
        breakSeconds: Int,
        sound: Bool,
        allowsSkip: Bool,
        allowsSnooze: Bool,
        now: Date = Date()
    ) {
        cancelReminders()
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time for an eye break"
            content.body = "Look at something 6 m (20 ft) away for \(breakSeconds) seconds."
            content.sound = sound ? .default : nil
            content.interruptionLevel = .active
            content.categoryIdentifier = !allowsSkip ? ID.strictCategory : (allowsSnooze ? ID.category : ID.noSnoozeCategory)
            content.threadIdentifier = "eye-breaks"
            add(content, id: ID.reminder(index), at: date, now: now)
        }
    }

    /// Tells the user a break they started has finished while the app was closed.
    func scheduleRestDone(at date: Date, sound: Bool, now: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = "Eye break done"
        content.body = "Nice. Your next one is in a while."
        content.sound = sound ? .default : nil
        content.interruptionLevel = .passive
        content.threadIdentifier = "eye-breaks"
        add(content, id: ID.restDone, at: date, now: now)
    }

    /// Removes pending and delivered TWNI notifications.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func cancelReminders() {
        let ids = (0..<64).map(ID.reminder) + [ID.restDone]
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func add(_ content: UNNotificationContent, id: String, at date: Date, now: Date) {
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSince(now), 1),
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // While the app is open it shows its own break screen.
        []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = NotificationAction(
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier
        )
        await MainActor.run {
            self.onAction?(action)
        }
    }
}
