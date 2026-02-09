import SwiftUI

struct DashboardView: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            StatusCard(timerManager: timerManager)

            ProtectionToggle(timerManager: timerManager)

            ModeIndicator(mode: timerManager.timerMode)

            TodayStats(timerManager: timerManager)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Card

private struct StatusCard: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: timerManager.state == .breakActive)

            Text(title)
                .font(.title2.bold())

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if timerManager.state == .active {
                ProgressView(value: timerManager.progress)
                    .tint(.teal)
                    .padding(.horizontal, 32)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.3), value: timerManager.state)
    }

    private var icon: String {
        switch timerManager.state {
        case .active: "eye"
        case .breakActive: "eye.fill"
        case .disabled: "eye.slash"
        }
    }

    private var iconColor: Color {
        switch timerManager.state {
        case .active: .teal
        case .breakActive: .green
        case .disabled: .secondary
        }
    }

    private var title: String {
        switch timerManager.state {
        case .active:
            let minutes = timerManager.secondsUntilBreak / 60
            let seconds = timerManager.secondsUntilBreak % 60
            if minutes > 0 {
                return "Next break in \(minutes)m \(seconds)s"
            }
            return "Next break in \(seconds)s"
        case .breakActive:
            return "Break in progress"
        case .disabled:
            return "Protection disabled"
        }
    }

    private var subtitle: String {
        switch timerManager.state {
        case .active:
            "Your eyes are being protected"
        case .breakActive:
            "Look at something 20 feet away"
        case .disabled:
            "Enable to start protecting your eyes"
        }
    }
}

// MARK: - Protection Toggle

private struct ProtectionToggle: View {
    var timerManager: TimerManager

    var body: some View {
        Button {
            if timerManager.state == .disabled {
                timerManager.enable()
            } else {
                timerManager.disable()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: timerManager.state == .disabled ? "shield.slash" : "shield.checkered")
                Text(timerManager.state == .disabled ? "Enable Protection" : "Disable Protection")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(timerManager.state == .disabled ? .teal : .red.opacity(0.8))
        .padding(.horizontal, 32)
    }
}

// MARK: - Mode Indicator

private struct ModeIndicator: View {
    let mode: TimerMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode == .auto ? "wand.and.stars" : "slider.horizontal.3")
                .font(.caption)
            Text(mode == .auto ? "Auto (20-20-20)" : "Manual")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Today Stats

private struct TodayStats: View {
    var timerManager: TimerManager

    var body: some View {
        HStack(spacing: 32) {
            StatBadge(
                value: "\(timerManager.totalSessionsToday)",
                label: "Sessions",
                icon: "clock"
            )
            StatBadge(
                value: "\(timerManager.breaksTakenToday)",
                label: "Breaks",
                icon: "eye"
            )
            StatBadge(
                value: "\(timerManager.breaksSkippedToday)",
                label: "Skipped",
                icon: "forward.fill"
            )
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatBadge: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.teal)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
