import SwiftUI
import SwiftData

@main
struct TWNIApp: App {
    @State private var timerManager: TimerManager
    private let modelContainer: ModelContainer

    init() {
        // Set up once, before any window exists, so the timer, notification
        // actions and the macOS overlay work even with no window open.
        let container = Self.makeModelContainer()
        let manager = TimerManager()
        manager.configure(modelContext: container.mainContext)
        modelContainer = container
        _timerManager = State(initialValue: manager)
    }

    var body: some Scene {
        #if os(macOS)
        Window("TWNI", id: "main") {
            ContentView(timerManager: timerManager)
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(timerManager: timerManager)
        } label: {
            MenuBarLabel(timerManager: timerManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(timerManager: timerManager)
        }
        #else
        WindowGroup {
            ContentView(timerManager: timerManager)
        }
        .modelContainer(modelContainer)
        #endif
    }

    /// Uses a new store name: data from the old models wasn't reliable enough
    /// to migrate. Falls back to memory instead of crashing on launch.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([CycleEntry.self])
        do {
            let configuration = ModelConfiguration("TWNI-v2", schema: schema)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("TWNI: couldn't open the store, using memory instead: \(error)")
            let memory = ModelConfiguration("TWNI-v2-memory", schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("TWNI: couldn't create an in-memory store: \(error)")
            }
        }
    }
}
