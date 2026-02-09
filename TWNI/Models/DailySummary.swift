import Foundation

struct DailySummary: Identifiable {
    let id: Date
    let date: Date
    let totalScreenTimeSeconds: Int
    let sessionsCount: Int
    let breaksTaken: Int
    let breaksSkipped: Int

    var completionRate: Double {
        let total = breaksTaken + breaksSkipped
        guard total > 0 else { return 0 }
        return Double(breaksTaken) / Double(total)
    }

    var totalScreenTimeFormatted: String {
        let hours = totalScreenTimeSeconds / 3600
        let minutes = (totalScreenTimeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
