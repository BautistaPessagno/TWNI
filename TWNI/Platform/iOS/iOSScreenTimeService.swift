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

    // MARK: - Always-On Eye Break Monitor

    func registerAlwaysOnMonitor() {
        #if canImport(DeviceActivity)
        guard isAuthorized else { return }

        if let previous = shared.store.string(forKey: TWNIConstants.DefaultsKey.currentAlwaysOnActivity) {
            center.stopMonitoring([DeviceActivityName(previous)])
        }

        let cycleID = Int(Date().timeIntervalSince1970)
        let activityRaw = "\(TWNIConstants.alwaysOnActivityName).\(cycleID)"
        let activityName = DeviceActivityName(activityRaw)

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let eventName = DeviceActivityEvent.Name(activityRaw + ".break")
        let event = DeviceActivityEvent(
            applications: [],
            categories: [],
            threshold: DateComponents(minute: 20),
            includesPastActivity: false
        )

        do {
            try center.startMonitoring(
                activityName,
                during: schedule,
                events: [eventName: event]
            )
            shared.store.set(activityRaw, forKey: TWNIConstants.DefaultsKey.currentAlwaysOnActivity)
        } catch {
            print("Failed to register always-on monitor: \(error)")
        }
        #endif
    }

    func restartAlwaysOnMonitor() {
        #if canImport(DeviceActivity)
        registerAlwaysOnMonitor()
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

        let eventName = DeviceActivityEvent.Name(schedule.id.uuidString + ".break")
        let event = DeviceActivityEvent(
            applications: [],
            categories: [],
            threshold: DateComponents(minute: 20),
            includesPastActivity: false
        )

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

    func stopAllScheduleMonitoring() {
        #if canImport(DeviceActivity)
        for schedule in shared.schedules {
            stopMonitoring(schedule: schedule)
        }
        #endif
    }

    func syncAllSchedules() {
        #if canImport(DeviceActivity)
        stopAllScheduleMonitoring()
        for schedule in shared.schedules where schedule.isEnabled {
            startMonitoring(schedule: schedule)
        }
        #endif
    }

    // MARK: - Break Lifecycle

    func clearBreakState() {
        shared.isBreakActive = false
        shared.isBreakPending = false
        shared.isBreakCountdownActive = false
        shared.breakEndDate = nil
        if shared.blockReason == .eyeBreak {
            shared.blockReason = nil
        }
    }
}
#endif
