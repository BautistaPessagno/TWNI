import DeviceActivity
import FamilyControls
import ManagedSettings
import Foundation
import UserNotifications

class TWNIDeviceActivityMonitor: DeviceActivityMonitor {
    private let shared = SharedDefaults.shared
    private let scheduleStore = ManagedSettingsStore()
    private let breakStore = ManagedSettingsStore(named: .init("twni.break"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        if activity.rawValue == TWNIConstants.alwaysOnActivityName { return }

        guard let scheduleID = UUID(uuidString: activity.rawValue),
              let schedule = shared.schedule(for: scheduleID),
              schedule.isEnabled else { return }

        shared.activeScheduleID = scheduleID
        shared.blockReason = .scheduledBlock
        applyShields(from: schedule.selectionData, to: scheduleStore)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        if activity.rawValue == TWNIConstants.alwaysOnActivityName { return }

        scheduleStore.clearAllSettings()
        if shared.blockReason == .scheduledBlock {
            shared.blockReason = nil
        }
        shared.activeScheduleID = nil
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        shared.isBreakPending = true
        shared.blockReason = .eyeBreak
        scheduleBreakNotification()

        if shared.isBlockingEnabled {
            if activity.rawValue == TWNIConstants.alwaysOnActivityName {
                applyShields(from: shared.breakSelectionData, to: breakStore)
            } else if let scheduleID = UUID(uuidString: activity.rawValue),
                      let schedule = shared.schedule(for: scheduleID) {
                applyShields(from: schedule.selectionData, to: breakStore)
            }
        }
    }

    // MARK: - Shields

    private func applyShields(from selectionData: Data?, to settingsStore: ManagedSettingsStore) {
        guard let data = selectionData,
              let selection = try? JSONDecoder().decode(
                FamilyActivitySelection.self, from: data
              ) else { return }

        settingsStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        settingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
    }

    // MARK: - Notifications

    private func scheduleBreakNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Time for a break!"
        content.body = "You've been looking at your screen. Open TWNI to start your eye break."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "BREAK_REMINDER"

        let request = UNNotificationRequest(
            identifier: "extension-break-reminder",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
