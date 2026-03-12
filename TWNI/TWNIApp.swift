import SwiftUI
import SwiftData

@main
struct TWNIApp: App {
    @State private var timerManager = TimerManager()

    #if os(macOS)
    @State private var activityDetector = MacActivityDetector()
    #endif

    #if os(iOS)
    @State private var appBlockingService = AppBlockingService()
    @State private var screenTimeService = iOSScreenTimeService()
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ScreenSession.self, BreakRecord.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(timerManager: timerManager)
                .modelContainer(sharedModelContainer)
                .task {
                    #if os(iOS)
                    timerManager.appBlockingService = appBlockingService
                    timerManager.screenTimeService = screenTimeService

                    appBlockingService.refreshAuthorization()
                    await screenTimeService.refreshAuthorization()

                    SharedDefaults.shared.intervalMinutes = timerManager.effectiveIntervalMinutes
                    SharedDefaults.shared.breakDurationSeconds = timerManager.effectiveBreakDurationSeconds
                    screenTimeService.registerAlwaysOnMonitor()
                    screenTimeService.syncAllSchedules()
                    #endif

                    timerManager.configure(modelContext: sharedModelContainer.mainContext)

                    await timerManager.notificationService.requestAuthorization()
                    timerManager.notificationService.registerActions()

                    #if os(macOS)
                    activityDetector.start(timerManager: timerManager)
                    #endif
                }
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif

        #if os(macOS)
        MenuBarExtra {
            MenuBarView(timerManager: timerManager)
        } label: {
            MenuBarLabel(timerManager: timerManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(timerManager: timerManager)
                .modelContainer(sharedModelContainer)
        }
        #endif
    }
}

// MARK: - Menu Bar Label

#if os(macOS)
private struct MenuBarLabel: View {
    var timerManager: TimerManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if timerManager.state == .active {
                Text(countdownText)
                    .monospacedDigit()
            } else if timerManager.state == .breakActive {
                Text("\(timerManager.breakSecondsRemaining)s")
                    .monospacedDigit()
            }
        }
    }

    private var icon: String {
        switch timerManager.state {
        case .active: "eye"
        case .breakActive: "eye.fill"
        case .disabled: "eye.slash"
        }
    }

    private var countdownText: String {
        let remaining = timerManager.secondsUntilBreak
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
