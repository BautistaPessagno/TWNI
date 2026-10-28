import SwiftUI

/// Slow horizontal lines drifting across the break screen, a hint of distance.
/// Freezes when Reduce Motion is on.
struct MotionLinesView: View {
    var lineCount: Int = 12
    var opacity: Double = 0.08

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                for index in 0..<lineCount {
                    let seed = Double(index)
                    let width = 100 + Double((index * 37) % 200)
                    let thickness = 1 + Double((index * 13) % 3)
                    let speed = 12 + Double((index * 17) % 24)
                    let travel = Double(size.width) + width
                    let offset = (time * speed + seed * 97).truncatingRemainder(dividingBy: travel)
                    let rect = CGRect(
                        x: offset - width,
                        y: Double(size.height) * (seed + 0.5) / Double(lineCount),
                        width: width,
                        height: thickness
                    )
                    graphics.fill(
                        Path(roundedRect: rect, cornerRadius: thickness / 2),
                        with: .color(Color.monoPrimary.opacity(opacity))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
