#if canImport(ManagedSettings)
import ManagedSettings
@preconcurrency import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // Schedule an immediate notification so the user can tap it to open TWNI.
            // We call the shield's completionHandler only inside the add() completion
            // so the extension process stays alive until iOS has accepted the request.
            let content = UNMutableNotificationContent()
            content.title = "Open TWNI"
            content.body = "Tap here to return to TWNI."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "twni.shield.open",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { _ in
                completionHandler(.close)
            }
        default:
            completionHandler(.close)
        }
    }
}
#endif
