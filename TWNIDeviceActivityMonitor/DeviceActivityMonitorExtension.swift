import DeviceActivity
import FamilyControls
import ManagedSettings
import Foundation
import UserNotifications

class TWNIDeviceActivityMonitor: DeviceActivityMonitor {
    private let shared = SharedDefaults.shared
    private let scheduleStore = ManagedSettingsStore()
    private let breakStore = ManagedSettingsStore(named: .init("twni.break"))

    private var isAlwaysOn: Bool {
        false // helper; actual check done per-method via activity name
    }

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
        let breakDuration = shared.breakDurationSeconds

        if activity.rawValue == TWNIConstants.alwaysOnActivityName {
            shared.blockReason = .eyeBreak
            shared.isBreakActive = true
            shared.breakEndDate = Date().addingTimeInterval(TimeInterval(breakDuration))
            applyShields(from: shared.breakSelectionData, to: breakStore)
            scheduleBreakNotification()
            restartAlwaysOnMonitor()
            return
        }

        guard let scheduleID = UUID(uuidString: activity.rawValue),
              let schedule = shared.schedule(for: scheduleID) else { return }

        shared.blockReason = .eyeBreak
        shared.isBreakActive = true
        shared.breakEndDate = Date().addingTimeInterval(TimeInterval(breakDuration))

        applyShields(from: schedule.selectionData, to: breakStore)
        scheduleBreakNotification()
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
        content.body = "You've been looking at your screen. Look 20 feet away for 20 seconds."
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

    // MARK: - Re-register Always-On Monitor

    private func restartAlwaysOnMonitor() {
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName(TWNIConstants.alwaysOnActivityName)
        center.stopMonitoring([activityName])

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let thresholdMinutes = shared.intervalMinutes
        let usageThreshold = DateComponents(minute: thresholdMinutes)

        let eventName = DeviceActivityEvent.Name(TWNIConstants.alwaysOnActivityName + ".break")
        let event: DeviceActivityEvent
        if let selectionData = shared.breakSelectionData,
           let selection = try? JSONDecoder().decode(
               FamilyActivitySelection.self, from: selectionData
           ) {
            event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: usageThreshold
            )
        } else {
            event = DeviceActivityEvent(threshold: usageThreshold)
        }

        do {
            try center.startMonitoring(
                activityName,
                during: schedule,
                events: [eventName: event]
            )
        } catch {
            print("Extension failed to restart always-on monitor: \(error)")
        }
    }
}
