import SwiftUI
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    var timerManager: TimerManager

    @AppStorage("intervalMinutes") private var intervalMinutes: Int = 20
    @AppStorage("breakDurationSeconds") private var breakDurationSeconds: Int = 20
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true

    @State private var pendingMode: TimerMode?
    @State private var showModeChangeAlert = false

    #if os(macOS)
    @State private var launchAtLogin = false
    #endif

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Protection Mode", selection: Binding(
                    get: { timerManager.timerMode },
                    set: { newMode in
                        guard newMode != timerManager.timerMode else { return }
                        if timerManager.state != .disabled {
                            pendingMode = newMode
                            showModeChangeAlert = true
                        } else {
                            timerManager.updateTimerMode(newMode)
                        }
                    }
                )) {
                    Text("Auto (20-20-20)").tag(TimerMode.auto)
                    Text("Manual").tag(TimerMode.manual)
                }
                .pickerStyle(.segmented)

                if timerManager.timerMode == .auto {
                    Text("Every 20 minutes, look at something 20 feet away for 20 seconds.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.monoTertiary)
                } else {
                    Stepper(
                        "Interval: \(intervalMinutes) min",
                        value: $intervalMinutes,
                        in: 1...120
                    )
                    .onChange(of: intervalMinutes) {
                        timerManager.intervalMinutes = intervalMinutes
                        timerManager.handleIntervalChanged()
                        SharedDefaults.shared.intervalMinutes = intervalMinutes
                        #if os(iOS)
                        timerManager.screenTimeService?.restartAlwaysOnMonitor()
                        #endif
                    }

                    Stepper(
                        "Break duration: \(breakDurationSeconds) sec",
                        value: $breakDurationSeconds,
                        in: 5...120,
                        step: 5
                    )
                    .onChange(of: breakDurationSeconds) {
                        timerManager.breakDurationSeconds = breakDurationSeconds
                        SharedDefaults.shared.breakDurationSeconds = breakDurationSeconds
                    }
                }
            }

            Section("Behavior") {
                Toggle("Sound effects", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) {
                        timerManager.soundEnabled = soundEnabled
                    }
            }

            #if os(iOS)
            AppBlockingSection(timerManager: timerManager)
            #endif

            #if os(macOS)
            Section("macOS") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        toggleLaunchAtLogin(launchAtLogin)
                    }
                    .onAppear {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            #endif

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Rule", value: "20-20-20")

                VStack(alignment: .leading, spacing: 8) {
                    Text("The 20-20-20 Rule")
                        .font(.subheadline.weight(.heavy))
                    Text("Every 20 minutes, look at something 20 feet away for 20 seconds. This helps reduce eye strain from prolonged screen use.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.monoTertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.monoSurface)
        .alert("Change Mode?", isPresented: $showModeChangeAlert) {
            Button("Change & Reset", role: .destructive) {
                if let mode = pendingMode {
                    timerManager.updateTimerMode(mode)
                }
                pendingMode = nil
            }
            Button("Cancel", role: .cancel) {
                pendingMode = nil
            }
        } message: {
            Text("This will reset the current timer and start a new interval.")
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    #if os(macOS)
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
    #endif
}

// MARK: - App Blocking Section (iOS)

#if os(iOS)
private struct AppBlockingSection: View {
    var timerManager: TimerManager

    var body: some View {
        if let blockingService = timerManager.appBlockingService, blockingService.isAvailable {
            Section("App Blocking During Breaks") {
                if blockingService.isAuthorized {
                    Toggle("Block apps during breaks", isOn: Binding(
                        get: { blockingService.isBlockingEnabled },
                        set: { blockingService.isBlockingEnabled = $0 }
                    ))

                    #if canImport(FamilyControls)
                    if blockingService.isBlockingEnabled {
                        NavigationLink {
                            BreakAppSelectionView(blockingService: blockingService)
                        } label: {
                            LabeledContent("Apps to block", value: appsSelectedLabel)
                        }
                    }
                    #endif
                } else {
                    Button("Authorize App Blocking") {
                        Task {
                            await blockingService.requestAuthorization()
                        }
                    }

                    Text("Requires Screen Time authorization to block apps during breaks.")
                        .font(.caption)
                        .foregroundStyle(Color.monoTertiary)
                }
            }
        }
    }

    private var appsSelectedLabel: String {
        #if canImport(FamilyControls)
        let count = blockingService.activitySelection.applicationTokens.count
            + blockingService.activitySelection.categoryTokens.count
        return count > 0 ? "\(count) selected" : "None"
        #else
        return "N/A"
        #endif
    }

    private var blockingService: AppBlockingService {
        timerManager.appBlockingService!
    }
}
#endif

// MARK: - Break App Selection (iOS)

#if os(iOS) && canImport(FamilyControls)
import FamilyControls

private struct BreakAppSelectionView: View {
    var blockingService: AppBlockingService

    var body: some View {
        FamilyActivityPicker(selection: Binding(
            get: { blockingService.activitySelection },
            set: { blockingService.activitySelection = $0 }
        ))
        .navigationTitle("Break App Selection")
    }
}
#endif

