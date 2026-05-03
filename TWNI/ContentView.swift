import SwiftUI
#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

struct ContentView: View {
    var timerManager: TimerManager

    #if os(iOS)
    var appBlockingService: AppBlockingService?
    var screenTimeService: iOSScreenTimeService?
    @State private var onboardingFinished = false
    #endif

    var body: some View {
        ZStack {
            #if os(iOS)
            if let blockingService = appBlockingService,
               let stService = screenTimeService,
               showOnboarding(blockingService: blockingService) {
                OnboardingView(
                    timerManager: timerManager,
                    blockingService: blockingService,
                    screenTimeService: stService,
                    onFinished: finishOnboarding
                )
            } else {
                mainTabs
            }
            #else
            mainTabs
            #endif

            if timerManager.state == .breakPending || timerManager.state == .breakActive {
                BreakOverlayView(timerManager: timerManager)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: timerManager.state)
    }

    private var mainTabs: some View {
        TabView {
            Tab("Dashboard", systemImage: "eye") {
                DashboardView(timerManager: timerManager)
            }

            Tab("Stats", systemImage: "chart.bar") {
                StatsView()
            }

            #if os(iOS)
            Tab("Schedules", systemImage: "calendar.badge.clock") {
                NavigationStack {
                    SchedulesView(timerManager: timerManager)
                }
            }
            #endif

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView(timerManager: timerManager)
                }
            }
        }
        .tint(Color.monoAccent)
    }

    #if os(iOS)
    private func showOnboarding(blockingService: AppBlockingService) -> Bool {
        if onboardingFinished { return false }

        #if canImport(FamilyControls)
        let status = AuthorizationCenter.shared.authorizationStatus
        if status != .approved { return true }
        #endif

        guard let data = SharedDefaults.shared.breakSelectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        else {
            return true
        }

        return false
    }

    private func finishOnboarding() {
        onboardingFinished = true
        screenTimeService?.registerAlwaysOnMonitor()
        screenTimeService?.syncAllSchedules()
    }
    #endif
}
