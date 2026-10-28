import Foundation
import ManagedSettings

/// Handles the shield's buttons.
/// Primary: first tap starts the look-away; a tap after the break length
/// unlocks the apps. Secondary: sends a notification that opens TWNI's guided
/// break (an extension can't open the app itself).
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            let now = Date()
            let breakSeconds = Double(ScreenTimeShared.breakSeconds)
            guard let started = ScreenTimeShared.restStartedAt else {
                ScreenTimeShared.restStartedAt = now
                ScreenTimeShared.notifyRestDone(after: ScreenTimeShared.breakSeconds)
                // Redraw the shield with "Keep looking away".
                return .defer
            }
            let rested = now.timeIntervalSince(started)
            // Too early: redraw with the seconds left.
            guard rested >= breakSeconds else { return .defer }
            ScreenTimeShared.finishBreak(outcome: "completed", restedSeconds: breakSeconds, now: now)
            return .defer
        case .secondaryButtonPressed:
            ScreenTimeShared.notifyOpenApp()
            return .none
        default:
            return .none
        }
    }
}
