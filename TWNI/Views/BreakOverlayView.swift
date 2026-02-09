import SwiftUI

struct BreakOverlayView: View {
    var timerManager: TimerManager

    @State private var animateGlow = false

    var body: some View {
        ZStack {
            // Calming gradient background
            LinearGradient(
                colors: [
                    Color.teal.opacity(0.8),
                    Color.blue.opacity(0.6),
                    Color.indigo.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Eye icon with glow
                Image(systemName: "eye")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(animateGlow ? 0.8 : 0.2), radius: animateGlow ? 30 : 10)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            animateGlow = true
                        }
                    }

                // Instruction
                VStack(spacing: 12) {
                    Text("Look 20 feet away")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Rest your eyes by focusing on something distant")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                // Countdown ring
                BreakCountdownRing(
                    remaining: timerManager.breakSecondsRemaining,
                    total: timerManager.breakDurationSeconds,
                    progress: timerManager.breakProgress
                )

                Spacer()

                // Skip button
                Button {
                    timerManager.skipBreak()
                } label: {
                    Text("Skip break")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.15), in: Capsule())
                }
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
                .stroke(Color.white.opacity(0.2), lineWidth: 8)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            Text("\(remaining)")
                .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.default, value: remaining)
        }
    }
}
