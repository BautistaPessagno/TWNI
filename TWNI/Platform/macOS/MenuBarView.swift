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
                    .font(.headline.bold())
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
            .font(.caption)
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
                .onAppear { pulse = state == .breakActive }
                .onChange(of: state) { pulse = state == .breakActive }

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.monoSecondary)
        }
    }

    private var label: String {
        switch state {
        case .active: "Active"
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
            if timerManager.state == .breakActive {
                Text("Look away...")
                    .font(.subheadline)
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
                    .font(.caption)
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
