import ManagedSettings
import UserNotifications

class TWNIShieldActionDelegate: ShieldActionDelegate {
    private let shared = SharedDefaults.shared

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action, completionHandler: completionHandler)
    }

    private func handleShieldAction(
        _ action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            scheduleOpenTWNINotification()
            completionHandler(.none)
        case .secondaryButtonPressed,
             .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            completionHandler(.none)
        @unknown default:
            completionHandler(.none)
        }
    }

    private func scheduleOpenTWNINotification() {
        let content = UNMutableNotificationContent()
        content.title = "Open TWNI"
        content.body = notificationBody
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "twni.shield.open-twni",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private var notificationBody: String {
        switch shared.blockReason {
        case .eyeBreak:
            "Tap to start your eye break."
        case .scheduledBlock:
            "Tap to manage your focus schedule."
        case nil:
            "Tap to return to TWNI."
        }
    }
}
