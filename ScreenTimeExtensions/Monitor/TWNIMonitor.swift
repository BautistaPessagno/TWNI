import DeviceActivity
import Foundation

/// Runs without TWNI open. iOS calls it when the user has spent the interval
/// in the monitored apps; it locks those apps and asks for an eye break.
final class TWNIMonitor: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == ScreenTimeShared.activity,
              event == ScreenTimeShared.eventName(for: ScreenTimeShared.generation),
              ScreenTimeShared.mode != .off,
              !ScreenTimeShared.isShieldActive else { return }

        // iOS 26 sometimes reports thresholds early. App use can't outrun the
        // clock, so a callback sooner than the interval after we started
        // counting is wrong: keep counting for at least the time left.
        let now = Date()
        let interval = TimeInterval(ScreenTimeShared.intervalMinutes * 60)
        if let armedAt = ScreenTimeShared.armedAt {
            let elapsed = now.timeIntervalSince(armedAt)
            if elapsed < interval - 30 {
                let remainingMinutes = Int(((interval - elapsed) / 60).rounded(.up))
                try? ScreenTimeShared.arm(now: now, thresholdMinutes: remainingMinutes, resetStart: false)
                return
            }
        }

        ScreenTimeShared.applyShield(now: now)
        ScreenTimeShared.notifyBreakDue()
    }
}
