import SwiftUI

/// Onboarding on first run, then the main tabs. On iOS the break screen
/// covers the app; on macOS it's shown in its own full-screen panels.
struct ContentView: View {
    var timerManager: TimerManager

    var body: some View {
        Group {
            if timerManager.hasCompletedOnboarding {
                MainTabs(timerManager: timerManager)
            } else {
                OnboardingView(timerManager: timerManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: timerManager.hasCompletedOnboarding)
        #if os(iOS)
        .overlay {
            if timerManager.isShowingBreak {
                BreakOverlayView(timerManager: timerManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: timerManager.isShowingBreak)
        #else
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }
}

private struct MainTabs: View {
    var timerManager: TimerManager

    var body: some View {
        TabView {
            Tab("Today", systemImage: "eye") {
                DashboardView(timerManager: timerManager)
            }
            Tab("Progress", systemImage: "chart.bar") {
                StatsView(timerManager: timerManager)
            }
            #if os(iOS)
            // macOS has its own Settings window (⌘,).
            Tab("Settings", systemImage: "gear") {
                SettingsView(timerManager: timerManager)
            }
            #endif
        }
        .tint(Color.monoAccent)
    }
}
