import SwiftUI

struct BreakOverlayView: View {
    var timerManager: TimerManager

    @State private var animateGlow = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.monoSurface,
                    Color.monoProgressTrack,
                    Color.monoBorder.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            MotionLinesView(animate: true, lineCount: 12, opacity: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                Image(systemName: "eye")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(Color.monoPrimary)
                    .shadow(color: Color.monoPrimary.opacity(animateGlow ? 0.3 : 0.1), radius: animateGlow ? 20 : 8)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            animateGlow = true
                        }
                    }

                VStack(spacing: 12) {
                    Text("Look 20 feet away")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(Color.monoPrimary)

                    Text("Rest your eyes by focusing on something distant")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.monoSecondary)
                        .multilineTextAlignment(.center)
                }

                BreakCountdownRing(
                    remaining: timerManager.breakSecondsRemaining,
                    total: timerManager.breakDurationSeconds,
                    progress: timerManager.breakProgress
                )

                Spacer()

                Button {
                    timerManager.skipBreak()
                } label: {
                    Text("Skip break")
                        .font(.subheadline)
                        .foregroundStyle(Color.monoSecondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.monoCard, in: Capsule())
                        .overlay(Capsule().stroke(Color.monoBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .padding()
        }
    }
}

// MARK: - Break Countdown Ring

private struct BreakCountdownRing: View {
    let remaining: Int
    let total: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.monoProgressTrack, lineWidth: 8)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.monoPrimary,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            Text("\(remaining)")
                .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Color.monoPrimary)
                .contentTransition(.numericText())
                .animation(.default, value: remaining)
        }
    }
}
