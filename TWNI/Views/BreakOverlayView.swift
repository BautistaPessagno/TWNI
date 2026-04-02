import SwiftUI

struct BreakOverlayView: View {
    var timerManager: TimerManager

    @State private var animateGlow = false
    @State private var skipButtonVisible = false

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

            pendingContent
        }
    }

    // MARK: - Break Pending

    private var pendingContent: some View {
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
                Text("Time for an Eye Break")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Color.monoPrimary)

                Text("Take a moment to rest your eyes")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.monoSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    timerManager.claimBreak()
                } label: {
                    Text("Claim Break")
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(MonochromePrimaryButtonStyle())
                .padding(.horizontal, 32)

                if timerManager.canSkip && skipButtonVisible {
                    Button {
                        timerManager.skipBreak()
                    } label: {
                        Text("Skip (\(timerManager.remainingSkips) left)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.monoSecondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.monoCard, in: Capsule())
                            .overlay(Capsule().stroke(Color.monoBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.bottom, 40)
        }
        .padding()
        .task {
            skipButtonVisible = false
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.easeInOut(duration: 0.3)) {
                skipButtonVisible = true
            }
        }
    }

    // MARK: - Break Active (countdown)
}
