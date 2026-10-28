import SwiftUI

/// The eye break: a guided 20-second look-away, then a short "done" moment.
/// On macOS it fills every display (see BreakOverlayController); on iOS it
/// covers the app.
struct BreakOverlayView: View {
    var timerManager: TimerManager
    /// False on secondary displays: they only dim and show the countdown.
    var showsControls = true

    var body: some View {
        ZStack {
            background
            if timerManager.engine.isResting {
                if showsControls {
                    restingContent
                } else {
                    secondaryScreenContent
                }
            } else if let done = timerManager.justCompleted {
                completedContent(done)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: timerManager.engine.isResting)
        .animation(.easeInOut(duration: 0.3), value: timerManager.currentPrompt.id)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color.monoSurface, Color.monoProgressTrack],
                startPoint: .top,
                endPoint: .bottom
            )
            MotionLinesView(lineCount: 12, opacity: 0.06)
        }
        .ignoresSafeArea()
    }

    // MARK: - Resting

    private var restingContent: some View {
        let prompt = timerManager.currentPrompt
        return VStack(spacing: 28) {
            Spacer(minLength: 24)

            Image(systemName: prompt.systemImage)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.monoPrimary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(prompt.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.monoPrimary)
                Text(prompt.instruction)
                    .font(.title3)
                    .foregroundStyle(Color.monoSecondary)
                    .frame(maxWidth: 520)
            }
            .multilineTextAlignment(.center)
            .id(prompt.id)
            .transition(.opacity)

            CountdownRing(
                remaining: timerManager.breakSecondsRemaining,
                progress: timerManager.breakProgress
            )

            hint

            Spacer(minLength: 24)

            controls
        }
        .padding(32)
    }

    @ViewBuilder
    private var hint: some View {
        #if os(macOS)
        if timerManager.engine.isRestPausedByInput {
            Label("Hands off the keyboard and mouse. The timer waits for you.", systemImage: "hand.raised")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.monoPrimary)
        } else {
            Text("Eye break \(timerManager.breakNumberToday) today")
                .font(.callout)
                .foregroundStyle(Color.monoSecondary)
        }
        #else
        Text("You can lock your phone. We'll tell you when it's done.")
            .font(.callout)
            .foregroundStyle(Color.monoSecondary)
            .multilineTextAlignment(.center)
        #endif
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            if timerManager.canSnooze {
                Button {
                    timerManager.snoozeBreak()
                } label: {
                    Label("5 more minutes", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(CapsuleButtonStyle())
            }
            if timerManager.canSkip {
                if timerManager.breakStyle.skipNeedsHold {
                    HoldToSkipButton { timerManager.skipBreak() }
                } else {
                    Button("Skip") { timerManager.skipBreak() }
                        .buttonStyle(CapsuleButtonStyle())
                }
            }
        }
        .padding(.bottom, 16)
    }

    private var secondaryScreenContent: some View {
        VStack(spacing: 16) {
            Text("Look away from the screen")
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.monoPrimary)
            CountdownRing(
                remaining: timerManager.breakSecondsRemaining,
                progress: timerManager.breakProgress,
                size: 110
            )
        }
    }

    // MARK: - Done

    private func completedContent(_ record: CycleRecord) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.monoPrimary)
                .symbolEffect(.bounce, value: record.endedAt)
                .accessibilityHidden(true)
            Text("Eyes rested")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.monoPrimary)
            if showsControls {
                Text(completionDetail)
                    .font(.title3)
                    .foregroundStyle(Color.monoSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private var completionDetail: String {
        var parts: [String] = []
        if let score = timerManager.todayScore { parts.append("Break Score \(score)") }
        let streak = timerManager.currentStreak
        if streak > 0 { parts.append(streak == 1 ? "1-day streak" : "\(streak)-day streak") }
        return parts.isEmpty ? "See you in \(timerManager.effectiveIntervalMinutes) minutes." : parts.joined(separator: " · ")
    }
}

// MARK: - Countdown Ring

private struct CountdownRing: View {
    let remaining: Int
    let progress: Double
    var size: CGFloat = 160

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.monoProgressTrack, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.monoPrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Text("\(remaining)")
                .font(.system(size: size * 0.35, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.monoPrimary)
                .contentTransition(.numericText())
                .animation(.default, value: remaining)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eye break")
        .accessibilityValue(remaining == 1 ? "1 second left" : "\(remaining) seconds left")
    }
}
