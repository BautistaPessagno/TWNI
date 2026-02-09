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
        get { UserDefaults.standard.bool(forKey: "appBlockingEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "appBlockingEnabled") }
    }

    #if canImport(FamilyControls)
    var activitySelection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }

    private let store = ManagedSettingsStore()
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

    func blockApps() {
        #if canImport(FamilyControls)
        guard isAuthorized, isBlockingEnabled else { return }
        store.shield.applications = activitySelection.applicationTokens.isEmpty ? nil : activitySelection.applicationTokens
        store.shield.applicationCategories = activitySelection.categoryTokens.isEmpty
            ? nil
            : .specific(activitySelection.categoryTokens)
        #endif
    }

    func unblockApps() {
        #if canImport(FamilyControls)
        store.clearAllSettings()
        #endif
    }

    // MARK: - Persistence

    #if canImport(FamilyControls)
    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(activitySelection) else { return }
        UserDefaults.standard.set(data, forKey: "blockedAppsSelection")
    }

    private func loadSelection() {
        guard let data = UserDefaults.standard.data(forKey: "blockedAppsSelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        activitySelection = selection
    }
    #endif
}
#endif
