import SwiftUI

#if os(macOS)
struct MenuBarView: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(Color.monoPrimary)
                Text("TWNI")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.monoPrimary)
                Spacer()
                StateIndicator(state: timerManager.state)
            }

            Divider()

            // Status display
            MenuBarStatusDisplay(timerManager: timerManager)

            Divider()

            // Enable/Disable toggle
            Group {
                if timerManager.state == .disabled {
                    menuBarToggleButton.buttonStyle(MonochromePrimaryButtonStyle())
                } else {
                    menuBarToggleButton.buttonStyle(MonochromeSecondaryButtonStyle())
                }
            }

            if timerManager.state == .breakPending {
                Button("Start Break") {
                    timerManager.claimBreak()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.monoAccent)
                .frame(maxWidth: .infinity)

                Button("Skip") {
                    timerManager.skipBreak()
                }
                .buttonStyle(.bordered)
                .tint(Color.monoAccent)
                .frame(maxWidth: .infinity)
            }

            if timerManager.state == .breakActive {
                Button("Skip Break") {
                    timerManager.skipBreak()
                }
                .buttonStyle(.bordered)
                .tint(Color.monoAccent)
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Stats
            HStack {
                Label("\(timerManager.breaksTakenToday) breaks", systemImage: "eye")
                Spacer()
                Label("\(timerManager.totalSessionsToday) sessions", systemImage: "clock")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.monoSecondary)

            Divider()

            // Quit
            Button("Quit TWNI") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.monoTertiary)
            .font(.caption)
        }
        .padding()
        .frame(width: 260)
    }

    private var menuBarToggleButton: some View {
        Button {
            if timerManager.state == .disabled {
                timerManager.enable()
            } else {
                timerManager.disable()
            }
        } label: {
            Label(
                timerManager.state == .disabled ? "Enable Protection" : "Disable Protection",
                systemImage: timerManager.state == .disabled ? "shield.checkered" : "shield.slash"
            )
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - State Indicator

private struct StateIndicator: View {
    let state: TimerState

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state == .disabled ? Color.clear : Color.monoPrimary)
                .overlay(
                    Circle()
                        .stroke(Color.monoTertiary, lineWidth: state == .disabled ? 1.5 : 0)
                )
                .opacity(state == .disabled ? 0.4 : 1.0)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .animation(
                    state == .breakActive
                        ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear { pulse = state == .breakActive || state == .breakPending }
                .onChange(of: state) { pulse = state == .breakActive || state == .breakPending }

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.monoSecondary)
        }
    }

    private var label: String {
        switch state {
        case .active: "Active"
        case .breakPending: "Break Pending"
        case .breakActive: "Break"
        case .disabled: "Disabled"
        }
    }
}

// MARK: - Status Display

private struct MenuBarStatusDisplay: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 8) {
            if timerManager.state == .breakPending {
                Text("Time for an eye break")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.monoPrimary)
                Text("Tap Start Break")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.monoSecondary)
            } else if timerManager.state == .breakActive {
                Text("Look away...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.monoPrimary)
                Text("\(timerManager.breakSecondsRemaining)s")
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.monoPrimary)

                ProgressView(value: timerManager.breakProgress)
                    .tint(Color.monoProgressFill)
            } else if timerManager.state == .active {
                let minutes = timerManager.secondsUntilBreak / 60
                let seconds = timerManager.secondsUntilBreak % 60
                Text("Next break in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.monoSecondary)
                Text(String(format: "%02d:%02d", minutes, seconds))
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.monoPrimary)

                ProgressView(value: timerManager.progress)
                    .tint(Color.monoProgressFill)
            } else {
                Text("Protection disabled")
                    .font(.subheadline)
                    .foregroundStyle(Color.monoTertiary)
            }
        }
    }
}
#endif
