import SwiftUI

#if os(macOS)
struct MenuBarView: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(.teal)
                Text("TWNI")
                    .font(.headline)
                Spacer()
                StateIndicator(state: timerManager.state)
            }

            Divider()

            // Status display
            MenuBarStatusDisplay(timerManager: timerManager)

            Divider()

            // Enable/Disable toggle
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
            .buttonStyle(.borderedProminent)
            .tint(timerManager.state == .disabled ? .teal : .red.opacity(0.8))

            if timerManager.state == .breakActive {
                Button("Skip Break") {
                    timerManager.skipBreak()
                }
                .buttonStyle(.bordered)
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
            .foregroundStyle(.secondary)

            Divider()

            // Quit
            Button("Quit TWNI") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding()
        .frame(width: 260)
    }
}

// MARK: - State Indicator

private struct StateIndicator: View {
    let state: TimerState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch state {
        case .active: "Active"
        case .breakActive: "Break"
        case .disabled: "Disabled"
        }
    }

    private var color: Color {
        switch state {
        case .active: .green
        case .breakActive: .teal
        case .disabled: .gray
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
                    .foregroundStyle(.teal)
                Text("\(timerManager.breakSecondsRemaining)s")
                    .font(.system(size: 36, weight: .light, design: .monospaced))

                ProgressView(value: timerManager.breakProgress)
                    .tint(.teal)
            } else if timerManager.state == .active {
                let minutes = timerManager.secondsUntilBreak / 60
                let seconds = timerManager.secondsUntilBreak % 60
                Text("Next break in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d:%02d", minutes, seconds))
                    .font(.system(size: 36, weight: .light, design: .monospaced))

                ProgressView(value: timerManager.progress)
                    .tint(.blue)
            } else {
                Text("Protection disabled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
