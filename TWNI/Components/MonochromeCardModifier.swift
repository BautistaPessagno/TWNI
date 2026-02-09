import SwiftUI

struct MonochromeCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(Color.monoCard, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.monoBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

extension View {
    func monochromeCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(MonochromeCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Button Styles

struct MonochromePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color.monoAccent.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 12)
            )
    }
}

struct MonochromeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.monoAccent)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color.monoCard.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.monoBorder, lineWidth: 1.5)
            )
    }
}
