#if os(iOS)
import Foundation
import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

@MainActor @Observable
final class AppBlockingService {
    var isAuthorized = false
    var isBlockingEnabled: Bool {
        get { SharedDefaults.shared.store.bool(forKey: "appBlockingEnabled") }
        set { SharedDefaults.shared.store.set(newValue, forKey: "appBlockingEnabled") }
    }

    #if canImport(FamilyControls)
    var activitySelection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }

    private let scheduleStore = ManagedSettingsStore()
    private let breakStore = ManagedSettingsStore(named: .init("twni.break"))
    #endif

    var isAvailable: Bool {
        #if canImport(FamilyControls)
        return true
        #else
        return false
        #endif
    }

    init() {
        #if canImport(FamilyControls)
        loadSelection()
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

    func refreshAuthorization() {
        #if canImport(FamilyControls)
        let status = AuthorizationCenter.shared.authorizationStatus
        isAuthorized = (status == .approved)
        #endif
    }

    // MARK: - Break Blocking

    func blockAppsForBreak() {
        #if canImport(FamilyControls)
        guard isAuthorized, isBlockingEnabled else { return }
        breakStore.shield.applications = activitySelection.applicationTokens.isEmpty
            ? nil : activitySelection.applicationTokens
        breakStore.shield.applicationCategories = activitySelection.categoryTokens.isEmpty
            ? nil : .specific(activitySelection.categoryTokens)
        SharedDefaults.shared.blockReason = .eyeBreak
        #endif
    }

    func unblockAppsAfterBreak() {
        #if canImport(FamilyControls)
        breakStore.clearAllSettings()
        if SharedDefaults.shared.blockReason == .eyeBreak {
            SharedDefaults.shared.blockReason = nil
        }
        #endif
    }

    // MARK: - Schedule Blocking

    func blockAppsForSchedule(selectionData: Data?) {
        #if canImport(FamilyControls)
        guard isAuthorized else { return }
        guard let data = selectionData,
              let selection = try? JSONDecoder().decode(
                  FamilyActivitySelection.self, from: data
              ) else { return }

        scheduleStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        scheduleStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        SharedDefaults.shared.blockReason = .scheduledBlock
        #endif
    }

    func unblockAppsForSchedule() {
        #if canImport(FamilyControls)
        scheduleStore.clearAllSettings()
        if SharedDefaults.shared.blockReason == .scheduledBlock {
            SharedDefaults.shared.blockReason = nil
        }
        #endif
    }

    // MARK: - Legacy single-selection blocking (for break overlay)

    func blockApps() {
        blockAppsForBreak()
    }

    func unblockApps() {
        unblockAppsAfterBreak()
    }

    // MARK: - Persistence

    #if canImport(FamilyControls)
    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(activitySelection) else { return }
        SharedDefaults.shared.store.set(data, forKey: "blockedAppsSelection")
    }

    private func loadSelection() {
        guard let data = SharedDefaults.shared.store.data(forKey: "blockedAppsSelection"),
              let selection = try? JSONDecoder().decode(
                  FamilyActivitySelection.self, from: data
              ) else { return }
        activitySelection = selection
    }
    #endif
}
#endif
