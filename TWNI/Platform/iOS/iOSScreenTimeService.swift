#if os(iOS)
import Foundation
import SwiftUI

#if canImport(DeviceActivity)
import DeviceActivity
import FamilyControls
#endif

@MainActor @Observable
final class iOSScreenTimeService {
    var isAuthorized = false

    #if canImport(DeviceActivity)
    private let center = DeviceActivityCenter()
    #endif

    private let shared = SharedDefaults.shared

    func refreshAuthorization() async {
        #if canImport(FamilyControls)
        let status = AuthorizationCenter.shared.authorizationStatus
        isAuthorized = (status == .approved)
        #endif
    }

    func requestAuthorization() async {
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            print("FamilyControls authorization failed: \(error)")
            isAuthorized = false
        }
        #endif
    }

    // MARK: - Schedule Monitoring

    func startMonitoring(schedule: BlockSchedule) {
        #if canImport(DeviceActivity)
        guard isAuthorized, schedule.isEnabled else { return }

        let activityName = DeviceActivityName(schedule.id.uuidString)

        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: DateComponents(
                hour: schedule.startTime.hour,
                minute: schedule.startTime.minute
            ),
            intervalEnd: DateComponents(
                hour: schedule.endTime.hour,
                minute: schedule.endTime.minute
            ),
            repeats: true
        )

        let usageThreshold = DateComponents(minute: 20)

        let eventName = DeviceActivityEvent.Name(schedule.id.uuidString + ".break")
        let event: DeviceActivityEvent
        if let selectionData = schedule.selectionData,
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
                during: deviceSchedule,
                events: [eventName: event]
            )
        } catch {
            print("Failed to start monitoring schedule \(schedule.name): \(error)")
        }
        #endif
    }

    func stopMonitoring(schedule: BlockSchedule) {
        #if canImport(DeviceActivity)
        let activityName = DeviceActivityName(schedule.id.uuidString)
        center.stopMonitoring([activityName])
        #endif
    }

    func stopAllMonitoring() {
        #if canImport(DeviceActivity)
        center.stopMonitoring()
        #endif
    }

    func syncAllSchedules() {
        #if canImport(DeviceActivity)
        stopAllMonitoring()
        for schedule in shared.schedules where schedule.isEnabled {
            startMonitoring(schedule: schedule)
        }
        #endif
    }

    // MARK: - Break Lifecycle

    func clearBreakState() {
        shared.isBreakActive = false
        shared.breakEndDate = nil
        if shared.blockReason == .eyeBreak {
            shared.blockReason = nil
        }
    }
}
#endif
