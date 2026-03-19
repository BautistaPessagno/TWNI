import Foundation
@preconcurrency import UserNotifications

final class NotificationService: @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    func checkAuthorizationStatus() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    func scheduleBreakNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Time for a break!"
        content.body = "Look at something 20 feet away for 20 seconds."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "BREAK_REMINDER"

        let request = UNNotificationRequest(
            identifier: "break-reminder",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    func scheduleTimerNotification(afterSeconds seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time for a break!"
        content.body = "You've been looking at your screen for 20 minutes. Look 20 feet away for 20 seconds."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "BREAK_REMINDER"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(seconds, 1)),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "timer-background",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func scheduleBreakEndNotification(afterSeconds seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Break complete!"
        content.body = "Your eyes are rested. Back to it!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(seconds, 1)),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "break-end",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancelBreakEndNotification() {
        center.removePendingNotificationRequests(withIdentifiers: ["break-end"])
    }

    func cancelPendingNotifications() {
        center.removePendingNotificationRequests(
            withIdentifiers: ["break-reminder", "timer-background"]
        )
    }

    func registerActions() {
        let startAction = UNNotificationAction(
            identifier: "START_BREAK",
            title: "Start Break",
            options: .foreground
        )

        let skipAction = UNNotificationAction(
            identifier: "SKIP_BREAK",
            title: "Skip",
            options: .destructive
        )

        let category = UNNotificationCategory(
            identifier: "BREAK_REMINDER",
            actions: [startAction, skipAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([category])
    }
}
