import DeviceActivity
import FamilyControls
import ManagedSettings
import Foundation

class TWNIDeviceActivityMonitor: DeviceActivityMonitor {
    private let shared = SharedDefaults.shared
    private let scheduleStore = ManagedSettingsStore()
    private let breakStore = ManagedSettingsStore(named: .init("twni.break"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        guard let scheduleID = UUID(uuidString: activity.rawValue),
              let schedule = shared.schedule(for: scheduleID),
              schedule.isEnabled else { return }

        shared.activeScheduleID = scheduleID
        shared.blockReason = .scheduledBlock
        applyShields(from: schedule.selectionData, to: scheduleStore)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
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
        guard let scheduleID = UUID(uuidString: activity.rawValue),
              let schedule = shared.schedule(for: scheduleID) else { return }

        shared.blockReason = .eyeBreak
        shared.isBreakActive = true
        shared.breakEndDate = Date().addingTimeInterval(20)

        applyShields(from: schedule.selectionData, to: breakStore)
    }

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
}
