import Foundation

extension Int {
    /// "12 min", "45 s": countdowns that don't need second precision.
    var countdownText: String {
        if self >= 60 {
            let minutes = Int((Double(self) / 60).rounded(.up))
            return "\(minutes) min"
        }
        return "\(Swift.max(self, 0)) s"
    }

    /// "4:05": a precise countdown.
    var clockText: String {
        let value = Swift.max(self, 0)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

extension TimeInterval {
    /// "2 h 10 min", "45 min", "0 min".
    var durationText: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        return "\(minutes) min"
    }
}
