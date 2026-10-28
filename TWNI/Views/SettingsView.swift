import SwiftUI
#if os(macOS)
import ServiceManagement
#else
import UIKit
#endif

struct SettingsView: View {
    @Bindable var timerManager: TimerManager

    var body: some View {
        NavigationStack {
            Form {
                ruleSection
                breaksSection
                #if os(macOS)
                smartPauseSection
                #endif
                streakSection
                #if os(iOS)
                RemindersSection(timerManager: timerManager)
                #else
                LaunchAtLoginSection()
                #endif
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.monoSurface)
            .navigationTitle("Settings")
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    // MARK: - Sections

    private var ruleSection: some View {
        Section {
            Picker("Rule", selection: $timerManager.timerMode) {
                Text("20-20-20").tag(TimerMode.auto)
                Text("Custom").tag(TimerMode.manual)
            }
            .pickerStyle(.segmented)

            if timerManager.timerMode == .manual {
                Stepper(
                    "Break every \(timerManager.intervalMinutes) min",
                    value: $timerManager.intervalMinutes,
                    in: 5...90,
                    step: 5
                )
                Stepper(
                    "Look away for \(timerManager.breakDurationSeconds) s",
                    value: $timerManager.breakDurationSeconds,
                    in: 10...120,
                    step: 5
                )
            }
        } header: {
            Text("Your rule")
        } footer: {
            Text(timerManager.timerMode == .auto
                 ? "Every 20 minutes of screen time, look at something 6 m (20 ft) away for 20 seconds."
                 : "Every \(timerManager.intervalMinutes) minutes of screen time, look far away for \(timerManager.breakDurationSeconds) seconds.")
        }
    }

    private var breaksSection: some View {
        Section {
            Picker("Break style", selection: $timerManager.breakStyle) {
                ForEach(BreakStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            Toggle("Sound when a break ends", isOn: $timerManager.soundEnabled)
        } header: {
            Text("Breaks")
        } footer: {
            Text(timerManager.breakStyle.summary)
        }
    }

    #if os(macOS)
    private var smartPauseSection: some View {
        Section {
            Toggle("Hold breaks during calls", isOn: $timerManager.holdBreaksDuringCalls)
            Toggle("Count videos as screen time", isOn: $timerManager.countVideoAsScreenTime)
        } header: {
            Text("Smart pause")
        } footer: {
            Text("TWNI checks whether the microphone is in use and whether a video is keeping the display awake. It never listens or records.")
        }
    }
    #endif

    private var streakSection: some View {
        Section {
            Picker("Daily goal", selection: $timerManager.dailyGoal) {
                ForEach([50, 60, 70, 80, 90], id: \.self) { goal in
                    Text("Break Score \(goal)").tag(goal)
                }
            }
        } header: {
            Text("Streak")
        } footer: {
            Text("Your streak grows on days your Break Score reaches this goal. Light days, with less than about an hour of screen time, don't count either way.")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink("The science behind TWNI") {
                ScienceView()
            }
            LabeledContent(
                "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
            Button("Replay the introduction") {
                timerManager.resetOnboarding()
            }
        } header: {
            Text("About")
        } footer: {
            Text("TWNI is a wellness tool, not a medical device. If you have eye pain, sudden changes in vision or symptoms that don't go away, see an eye doctor.")
        }
    }
}

// MARK: - iOS reminders

#if os(iOS)
private struct RemindersSection: View {
    var timerManager: TimerManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            switch timerManager.notificationPermission {
            case .allowed:
                Label("Reminders are on", systemImage: "checkmark.circle")
            case .denied:
                Button("Turn on in Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            case .notAsked, .unknown:
                Button("Allow reminders") {
                    Task { await timerManager.requestNotificationPermission() }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("During a screen session, TWNI sends a reminder when it's time to look away, even while you're in other apps.")
        }
    }
}
#endif

// MARK: - macOS launch at login

#if os(macOS)
private struct LaunchAtLoginSection: View {
    @State private var status = SMAppService.mainApp.status

    var body: some View {
        Section {
            Toggle("Open TWNI when you log in", isOn: Binding(
                get: { status == .enabled },
                set: { setEnabled($0) }
            ))
            if status == .requiresApproval {
                Button("Approve in System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } header: {
            Text("Mac")
        } footer: {
            Text("Eye breaks only work while TWNI is running.")
        }
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("TWNI: launch at login failed: \(error)")
        }
        status = SMAppService.mainApp.status
    }
}
#endif
