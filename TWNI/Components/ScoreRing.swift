import SwiftUI

/// A ring that fills with a 0-100 Break Score.
struct ScoreRing: View {
    let score: Int?
    var lineWidth: CGFloat = 12
    var showsLabel = true

    private var fraction: CGFloat { CGFloat(score ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.monoProgressTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.monoProgressFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            if showsLabel {
                VStack(spacing: 0) {
                    Text(score.map(String.init) ?? "–")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                    Text("Break Score")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.monoSecondary)
                }
                .foregroundStyle(Color.monoPrimary)
                .padding(lineWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Break Score")
        .accessibilityValue(score.map { "\($0) out of 100" } ?? "No screen time yet")
    }
}

/// "🔥 4" pill for the current streak.
struct StreakBadge: View {
    let days: Int

    var body: some View {
        Label("\(days)", systemImage: "flame.fill")
            .font(.headline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(days > 0 ? Color.monoPrimary : Color.monoTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.monoElevated, in: Capsule())
            .overlay(Capsule().stroke(Color.monoBorder, lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(days == 1 ? "1-day streak" : "\(days)-day streak")
    }
}

/// Small rounded label used for score details.
struct InfoChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.monoSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.monoElevated, in: Capsule())
    }
}
