import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Home: today's Break Score and streak, what the timer is doing, and the week.
struct DashboardView: View {
    var timerManager: TimerManager

    @State private var showingScoreInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                ScoreCard(timerManager: timerManager, showingInfo: $showingScoreInfo)
                #if os(iOS)
                if timerManager.notificationPermission == .denied {
                    NotificationsOffBanner()
                }
                AutomaticBreaksCard(timerManager: timerManager)
                if !timerManager.isAutomaticMode {
                    // Without Screen Time access: reminders on a timer.
                    SessionCard(timerManager: timerManager)
                }
                #else
                ProtectionCard(timerManager: timerManager)
                #endif
                WeekStrip(timerManager: timerManager)
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.monoSurface)
        .sheet(isPresented: $showingScoreInfo) {
            ScoreInfoSheet(timerManager: timerManager)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.monoPrimary)
                Text(timerManager.now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundStyle(Color.monoSecondary)
            }
            Spacer()
            StreakBadge(days: timerManager.currentStreak)
        }
        .padding(.top, 8)
    }
}

// MARK: - Score

private struct ScoreCard: View {
    var timerManager: TimerManager
    @Binding var showingInfo: Bool

    private var today: DaySummary { timerManager.today }
    private var score: Int? { timerManager.todayScore }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                ScoreRing(score: score)
                    .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 6) {
                    Text(BreakScore.label(for: score))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.monoPrimary)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(Color.monoSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("How it works") { showingInfo = true }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.monoPrimary)
                        .underline()
                }
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var chips: some View {
        InfoChip(text: today.rests == 1 ? "1 rest" : "\(today.rests) rests", systemImage: "eye")
        InfoChip(text: "\(today.screenSeconds.durationText) on screen", systemImage: screenIcon)
        if today.longestStretch >= 60 {
            InfoChip(text: "Longest \(today.longestStretch.durationText)", systemImage: "arrow.left.and.right")
        }
    }

    private var screenIcon: String {
        #if os(macOS)
        return "laptopcomputer"
        #else
        return "iphone"
        #endif
    }

    private var explanation: String {
        let interval = timerManager.effectiveIntervalMinutes
        let blocks = Int(today.screenSeconds / Double(interval * 60))
        if !today.hasScreenTime {
            return "Your score starts with your first \(interval) minutes of screen time."
        }
        if blocks == 0 {
            return "Your first \(interval)-minute block is still running."
        }
        let rested = min(today.rests, blocks)
        return "\(rested) of \(blocks) blocks of \(interval) min ended with a rest."
    }
}

// MARK: - macOS status

#if os(macOS)
private struct ProtectionCard: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(timerManager.statusLine)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.monoPrimary)
                .contentTransition(.numericText())

            if timerManager.state == .active, !timerManager.isSnoozed {
                ProgressView(value: timerManager.focusProgress)
                    .tint(Color.monoProgressFill)
                    .accessibilityLabel("Time until the next eye break")
            }

            HStack(spacing: 12) {
                if timerManager.engine.isRunning {
                    Button("Rest now") { timerManager.startBreakNow() }
                        .buttonStyle(MonochromePrimaryButtonStyle())
                    Menu {
                        Button("For 30 minutes") { timerManager.pause(for: 30 * 60) }
                        Button("For 1 hour") { timerManager.pause(for: 60 * 60) }
                        Button("Until tomorrow") { timerManager.pauseUntilTomorrow() }
                        Divider()
                        Button("Turn off eye breaks") { timerManager.disable() }
                    } label: {
                        Text("Pause")
                            .frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .buttonStyle(MonochromeSecondaryButtonStyle())
                } else if timerManager.pausedUntil != nil {
                    Button("Resume now") { timerManager.resume() }
                        .buttonStyle(MonochromePrimaryButtonStyle())
                } else {
                    Button("Turn on eye breaks") { timerManager.enable() }
                        .buttonStyle(MonochromePrimaryButtonStyle())
                }
            }
            .font(.headline)

            Text("TWNI counts screen time only while you use your Mac. It pauses when you step away and holds breaks during calls.")
                .font(.footnote)
                .foregroundStyle(Color.monoSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(cornerRadius: 20)
    }
}
#endif

// MARK: - iOS sessions

#if os(iOS)
private struct SessionCard: View {
    var timerManager: TimerManager

    private let durations: [(label: String, minutes: Int)] = [
        ("30 min", 30), ("1 h", 60), ("2 h", 120), ("4 h", 240),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let end = timerManager.sessionEndsAt {
                activeSession(endsAt: end)
            } else {
                startSession
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var startSession: some View {
        Text("Start a screen session")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.monoPrimary)
        Text("Settling in to scroll, study or game? Tell TWNI how long, and you'll get an eye-break reminder every \(timerManager.effectiveIntervalMinutes) minutes, even in other apps.")
            .font(.subheadline)
            .foregroundStyle(Color.monoSecondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            ForEach(durations, id: \.minutes) { option in
                Button(option.label) { timerManager.startSession(minutes: option.minutes) }
                    .buttonStyle(MonochromeSecondaryButtonStyle())
                    .font(.headline)
            }
        }

        if timerManager.notificationPermission == .notAsked {
            Button("Allow reminders") {
                Task { await timerManager.requestNotificationPermission() }
            }
            .buttonStyle(MonochromePrimaryButtonStyle())
            .font(.headline)
        }
    }

    @ViewBuilder
    private func activeSession(endsAt end: Date) -> some View {
        Text(timerManager.statusLine)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.monoPrimary)
        if timerManager.state == .active, !timerManager.isSnoozed {
            ProgressView(value: timerManager.focusProgress)
                .tint(Color.monoProgressFill)
                .accessibilityLabel("Time until the next eye break")
        }
        Text("Session ends at \(end.formatted(date: .omitted, time: .shortened))")
            .font(.subheadline)
            .foregroundStyle(Color.monoSecondary)
        HStack(spacing: 12) {
            Button("Rest now") { timerManager.startBreakNow() }
                .buttonStyle(MonochromePrimaryButtonStyle())
            Button("End session") { timerManager.endSession() }
                .buttonStyle(MonochromeSecondaryButtonStyle())
        }
        .font(.headline)
    }
}

private struct NotificationsOffBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Reminders are turned off")
                    .font(.headline)
                Text("Without notifications, TWNI can't remind you while you're in other apps.")
                    .font(.subheadline)
                    .foregroundStyle(Color.monoSecondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(Color.monoPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard()
    }
}
#endif

// MARK: - Week

private struct WeekStrip: View {
    var timerManager: TimerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.headline)
                .foregroundStyle(Color.monoPrimary)
            HStack(spacing: 0) {
                ForEach(timerManager.lastSevenDays, id: \.day) { day in
                    DayDot(day: day, score: timerManager.score(for: day), status: timerManager.status(of: day))
                        .frame(maxWidth: .infinity)
                }
            }
            Text("A check means the day reached your goal of \(timerManager.dailyGoal).")
                .font(.footnote)
                .foregroundStyle(Color.monoSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(cornerRadius: 20)
    }
}

private struct DayDot: View {
    let day: DaySummary
    let score: Int?
    let status: DayStatus

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ScoreRing(score: score, lineWidth: 4, showsLabel: false)
                if status == .met {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.monoPrimary)
                }
            }
            .frame(width: 30, height: 30)
            Text(day.day.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.monoSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let score else { return "No screen time" }
        return status == .met ? "Score \(score), goal reached" : "Score \(score)"
    }
}

// MARK: - Score explanation

private struct ScoreInfoSheet: View {
    var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let interval = timerManager.effectiveIntervalMinutes
                    Text("Every \(interval) minutes of screen time is one block. A block counts when it ends with a rest: a finished eye break, or stepping away from the screen for a while.")
                    Text("Your Break Score is the share of today's blocks that got a rest, from 0 to 100. Skipped or missed breaks don't count, and long stretches without a break add blocks with no rest.")
                    Text("Your streak grows on days your score reaches \(timerManager.dailyGoal). Days with less than about an hour of screen time are light days: they don't add to the streak or break it.")
                    Text("TWNI measures your breaks, not your eyes. It is a wellness tool, not a medical device.")
                        .foregroundStyle(Color.monoSecondary)
                }
                .font(.body)
                .foregroundStyle(Color.monoPrimary)
                .padding()
            }
            .navigationTitle("How the Break Score works")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
