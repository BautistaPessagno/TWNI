import SwiftUI

struct ContentView: View {
    var timerManager: TimerManager

    var body: some View {
        ZStack {
            TabView {
                Tab("Dashboard", systemImage: "eye") {
                    DashboardView(timerManager: timerManager)
                }

                Tab("Stats", systemImage: "chart.bar") {
                    StatsView()
                }

                Tab("Settings", systemImage: "gear") {
                    NavigationStack {
                        SettingsView(timerManager: timerManager)
                    }
                }
            }
            .tint(Color.monoAccent)

            if timerManager.state == .breakActive {
                BreakOverlayView(timerManager: timerManager)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: timerManager.state)
    }
}
