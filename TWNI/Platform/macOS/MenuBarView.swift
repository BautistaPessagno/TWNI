import SwiftUI

#if os(macOS)
import AppKit

/// The menu bar popover: today's score and streak, what the timer is doing,
/// and quick controls.
struct MenuBarView: View {
    var timerManager: TimerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            status
            controls
            if !timerManager.hasCompletedOnboarding {
                Button("Finish setting up TWNI") { openMainWindow() }
                    .buttonStyle(MonochromePrimaryButtonStyle())
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                ScoreRing(score: timerManager.todayScore, lineWidth: 4, showsLabel: false)
                Text(timerManager.todayScore.map(String.init) ?? "–")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Break Score")
                    .font(.headline)
                Text(BreakScore.label(for: timerManager.todayScore))
                    .font(.caption)
                    .foregroundStyle(Color.monoSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Break Score")
            .accessibilityValue(timerManager.todayScore.map { "\($0) out of 100" } ?? "No screen time yet")

            Spacer()
            StreakBadge(days: timerManager.currentStreak)
        }
        .foregroundStyle(Color.monoPrimary)
    }

    @ViewBuilder
    private var status: some View {
        Text(timerManager.statusLine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.monoPrimary)
        if timerManager.state == .active, !timerManager.isSnoozed {
            ProgressView(value: timerManager.focusProgress)
                .tint(Color.monoProgressFill)
                .accessibilityLabel("Time until the next eye break")
        }
    }

    @ViewBuilder
    private var controls: some View {
        if timerManager.engine.isRunning {
            HStack(spacing: 8) {
                Button("Rest now") { timerManager.startBreakNow() }
                    .buttonStyle(MonochromePrimaryButtonStyle())
                Menu {
                    Button("For 30 minutes") { timerManager.pause(for: 30 * 60) }
                    Button("For 1 hour") { timerManager.pause(for: 60 * 60) }
                    Button("Until tomorrow") { timerManager.pauseUntilTomorrow() }
                    Divider()
                    Button("Turn off eye breaks") { timerManager.disable() }
                } label: {
                    Text("Pause").frame(maxWidth: .infinity)
                }
                .menuStyle(.button)
                .buttonStyle(MonochromeSecondaryButtonStyle())
            }
        } else if timerManager.pausedUntil != nil {
            Button("Resume now") { timerManager.resume() }
                .buttonStyle(MonochromePrimaryButtonStyle())
        } else if timerManager.hasCompletedOnboarding {
            Button("Turn on eye breaks") { timerManager.enable() }
                .buttonStyle(MonochromePrimaryButtonStyle())
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Open TWNI") { openMainWindow() }
            SettingsLink { Text("Settings…") }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(Color.monoSecondary)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }
}

/// Menu bar item: an eye plus a short countdown.
struct MenuBarLabel: View {
    var timerManager: TimerManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if let text {
                Text(text)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TWNI")
        .accessibilityValue(timerManager.statusLine)
    }

    private var icon: String {
        switch timerManager.state {
        case .active: "eye"
        case .breakActive: "eye.fill"
        case .disabled: "eye.slash"
        }
    }

    /// Minutes are enough most of the time; seconds near the break.
    private var text: String? {
        switch timerManager.state {
        case .breakActive:
            return "\(timerManager.breakSecondsRemaining)s"
        case .active:
            if timerManager.isSnoozed || timerManager.engine.isFocusPaused { return nil }
            let seconds = timerManager.secondsUntilBreak
            return seconds >= 60 ? "\(Int((Double(seconds) / 60).rounded(.up)))m" : "\(seconds)s"
        case .disabled:
            return nil
        }
    }
}
#endif
