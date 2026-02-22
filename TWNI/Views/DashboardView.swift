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
        .background(Color.monoSurface)
    }
}

// MARK: - Status Card

private struct StatusCard: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: iconWeight))
                .foregroundStyle(Color.monoPrimary.opacity(iconOpacity))
                .symbolEffect(.pulse, isActive: timerManager.state == .breakActive)

            Text(title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color.monoPrimary)

            Text(subtitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.monoSecondary)
                .multilineTextAlignment(.center)

            if timerManager.state == .active {
                ProgressView(value: timerManager.progress)
                    .tint(Color.monoProgressFill)
                    .padding(.horizontal, 32)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .monochromeCard(cornerRadius: 20)
        .animation(.easeInOut(duration: 0.3), value: timerManager.state)
    }

    private var icon: String {
        switch timerManager.state {
        case .active: "eye"
        case .breakActive: "eye.fill"
        case .disabled: "eye.slash"
        }
    }

    private var iconWeight: Font.Weight {
        switch timerManager.state {
        case .active: .regular
        case .breakActive: .bold
        case .disabled: .light
        }
    }

    private var iconOpacity: Double {
        switch timerManager.state {
        case .active: 1.0
        case .breakActive: 1.0
        case .disabled: 0.4
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

    private var isDisabled: Bool { timerManager.state == .disabled }

    var body: some View {
        Group {
            if isDisabled {
                toggleButton.buttonStyle(MonochromePrimaryButtonStyle())
            } else {
                toggleButton.buttonStyle(MonochromeSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 32)
    }

    private var toggleButton: some View {
        Button {
            if isDisabled {
                timerManager.enable()
            } else {
                timerManager.disable()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isDisabled ? "shield.checkered" : "shield.slash")
                    .fontWeight(isDisabled ? .bold : .light)
                Text(isDisabled ? "Enable Protection" : "Disable Protection")
                    .font(.headline.weight(.heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Mode Indicator

private struct ModeIndicator: View {
    let mode: TimerMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode == .auto ? "wand.and.stars" : "slider.horizontal.3")
                .font(.caption.weight(.semibold))
            Text(mode == .auto ? "Auto (20-20-20)" : "Manual")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.monoTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.monoElevated, in: Capsule())
        .overlay(Capsule().stroke(Color.monoBorder, lineWidth: 0.5))
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
                icon: "clock",
                iconWeight: .bold
            )
            StatBadge(
                value: "\(timerManager.breaksTakenToday)",
                label: "Breaks",
                icon: "eye",
                iconWeight: .medium
            )
            StatBadge(
                value: "\(timerManager.breaksSkippedToday)",
                label: "Skipped",
                icon: "forward.fill",
                iconWeight: .light
            )
        }
        .padding()
        .monochromeCard()
    }
}

private struct StatBadge: View {
    let value: String
    let label: String
    let icon: String
    var iconWeight: Font.Weight = .regular

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .fontWeight(iconWeight)
                .foregroundStyle(Color.monoSecondary)
            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color.monoPrimary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.monoTertiary)
        }
    }
}
