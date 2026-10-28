#if os(iOS)
import FamilyControls
import SwiftUI

/// Dashboard card for automatic eye breaks (Screen Time).
struct AutomaticBreaksCard: View {
    var timerManager: TimerManager
    @State private var showingSetup = false

    private var screenTime: ScreenTimeService { timerManager.screenTime }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if screenTime.isActive {
                activeContent
            } else {
                setupContent
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(cornerRadius: 20)
        .sheet(isPresented: $showingSetup) {
            ScreenTimeSetupView(timerManager: timerManager)
        }
    }

    @ViewBuilder
    private var setupContent: some View {
        Label("Automatic eye breaks", systemImage: "hourglass")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.monoPrimary)
        Text("With Screen Time access, TWNI counts only the time you actually spend in your apps, even when TWNI is closed. After \(timerManager.effectiveIntervalMinutes) minutes, those apps lock until you rest your eyes.")
            .font(.subheadline)
            .foregroundStyle(Color.monoSecondary)
            .fixedSize(horizontal: false, vertical: true)
        Button("Set up automatic breaks") { showingSetup = true }
            .buttonStyle(MonochromePrimaryButtonStyle())
            .font(.headline)
    }

    @ViewBuilder
    private var activeContent: some View {
        if screenTime.isShieldActive {
            Label("Your apps are locked", systemImage: "lock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.monoPrimary)
            Text("Take a \(timerManager.effectiveBreakDurationSeconds)-second eye break to unlock them.")
                .font(.subheadline)
                .foregroundStyle(Color.monoSecondary)
        } else {
            Label("Automatic eye breaks are on", systemImage: "checkmark.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.monoPrimary)
            Text(countingText)
                .font(.subheadline)
                .foregroundStyle(Color.monoSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button("Change apps or turn off") { showingSetup = true }
            .buttonStyle(MonochromeSecondaryButtonStyle())
            .font(.headline)
        if let error = screenTime.lastError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(Color.monoSecondary)
        }
    }

    private var countingText: String {
        let apps = screenTime.mode == .allApps
            ? "all your apps"
            : (screenTime.selectedCount == 1 ? "1 selected item" : "\(screenTime.selectedCount) selected items")
        return "TWNI counts the time you spend in \(apps). After \(timerManager.effectiveIntervalMinutes) minutes of use, they lock until you rest your eyes."
    }
}

/// Settings row that opens the automatic breaks setup.
struct AutomaticBreaksSection: View {
    var timerManager: TimerManager
    @State private var showingSetup = false

    var body: some View {
        Section {
            Button {
                showingSetup = true
            } label: {
                LabeledContent("Automatic breaks", value: timerManager.screenTime.isActive ? "On" : "Off")
            }
        } header: {
            Text("Screen Time")
        } footer: {
            Text("Counts only the time you spend in your apps and locks them when it's time for a break.")
        }
        .sheet(isPresented: $showingSetup) {
            ScreenTimeSetupView(timerManager: timerManager)
        }
    }
}

/// Turns automatic breaks on or off and chooses which apps count.
struct ScreenTimeSetupView: View {
    var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss
    @State private var choice: ScreenTimeShared.Mode = .allApps
    @State private var selection = FamilyActivitySelection()
    @State private var showingPicker = false

    private var screenTime: ScreenTimeService { timerManager.screenTime }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("TWNI counts the time you spend in your apps, even when TWNI is closed. When it reaches \(timerManager.effectiveIntervalMinutes) minutes, those apps lock. Rest your eyes for \(timerManager.effectiveBreakDurationSeconds) seconds, on the lock screen or in TWNI, to unlock them.")
                    Text("Screen Time data stays on your iPhone. TWNI can't see which apps you use or for how long.")
                        .foregroundStyle(Color.monoSecondary)
                }

                if !screenTime.isAuthorized {
                    Section {
                        Button("Allow Screen Time access") {
                            Task { await screenTime.requestAuthorization() }
                        }
                    } footer: {
                        Text("iOS asks for your passcode or Face ID. You can turn it off later in Settings > Screen Time.")
                    }
                } else {
                    Section("Which apps count") {
                        Picker("Apps", selection: $choice) {
                            Text("All apps").tag(ScreenTimeShared.Mode.allApps)
                            Text("Selected apps").tag(ScreenTimeShared.Mode.selectedApps)
                        }
                        .pickerStyle(.segmented)
                        if choice == .selectedApps {
                            Button(selectionLabel) { showingPicker = true }
                        }
                    }

                    Section {
                        Button(screenTime.isActive ? "Save" : "Turn on automatic breaks") { save() }
                            .disabled(choice == .selectedApps && isSelectionEmpty)
                        if screenTime.isActive {
                            Button("Turn off", role: .destructive) {
                                screenTime.setMode(.off)
                                dismiss()
                            }
                        }
                    }
                }

                if let error = screenTime.lastError {
                    Section { Text(error).foregroundStyle(Color.monoSecondary) }
                }
            }
            .navigationTitle("Automatic breaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
            .onAppear {
                choice = screenTime.mode == .off ? .allApps : screenTime.mode
                selection = screenTime.selection
            }
        }
    }

    private var isSelectionEmpty: Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    private var selectionLabel: String {
        let count = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        return count == 0 ? "Choose apps" : "Change apps (\(count) selected)"
    }

    private func save() {
        screenTime.setSelection(selection)
        screenTime.setMode(choice)
        if timerManager.sessionEndsAt != nil { timerManager.endSession() }
        dismiss()
    }
}
#endif
