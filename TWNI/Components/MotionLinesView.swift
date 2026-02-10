import SwiftUI

struct MotionLinesView: View {
    var animate: Bool = true
    var lineCount: Int = 12
    var opacity: Double = 0.12

    @State private var phase: CGFloat = 0

    private struct LineConfig: Identifiable {
        let id: Int
        let yFraction: CGFloat
        let width: CGFloat
        let thickness: CGFloat
    }

    private var lines: [LineConfig] {
        (0..<lineCount).map { i in
            let seed = Double(i)
            let yFraction = (seed + 0.5) / Double(lineCount)
            let width: CGFloat = CGFloat(100 + Int(seed * 37) % 200)
            let thickness: CGFloat = CGFloat(1 + Int(seed * 13) % 3)
            return LineConfig(id: i, yFraction: yFraction, width: width, thickness: thickness)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(lines) { line in
                let xOffset = animate ? animatedOffset(for: line, containerWidth: geometry.size.width) : staticOffset(for: line, containerWidth: geometry.size.width)

                RoundedRectangle(cornerRadius: line.thickness / 2)
                    .fill(Color.monoPrimary.opacity(opacity))
                    .frame(width: line.width, height: line.thickness)
                    .position(
                        x: xOffset,
                        y: geometry.size.height * line.yFraction
                    )
            }
        }
        .onAppear {
            guard animate else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
    }

    private func animatedOffset(for line: LineConfig, containerWidth: CGFloat) -> CGFloat {
        let totalTravel = containerWidth + line.width
        let startX = containerWidth + line.width / 2
        let seedOffset = CGFloat(line.id) / CGFloat(lineCount)
        let adjustedPhase = (phase + seedOffset).truncatingRemainder(dividingBy: 1.0)
        return startX - totalTravel * adjustedPhase
    }

    private func staticOffset(for line: LineConfig, containerWidth: CGFloat) -> CGFloat {
        let seed = CGFloat(line.id * 47 % lineCount)
        return (seed / CGFloat(lineCount)) * containerWidth
    }
}
