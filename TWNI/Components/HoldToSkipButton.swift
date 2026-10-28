import SwiftUI

/// A skip button that has to be held down: enough friction to make skipping
/// a choice, not a reflex. VoiceOver users can activate it directly.
struct HoldToSkipButton: View {
    var title = "Hold to skip"
    var duration: Double = 1.5
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.monoSecondary)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .background {
                GeometryReader { proxy in
                    Color.monoCard
                    Color.monoBorder
                        .frame(width: proxy.size.width * progress)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.monoBorder, lineWidth: 1))
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                progress = 0
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: duration) : .easeOut(duration: 0.2)) {
                    progress = pressing ? 1 : 0
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Skip break")
            .accessibilityHint("Touch and hold to skip this break.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Capsule button used on the break screen.
struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.monoSecondary)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .background(Color.monoCard.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(Color.monoBorder, lineWidth: 1))
            .contentShape(Capsule())
    }
}
