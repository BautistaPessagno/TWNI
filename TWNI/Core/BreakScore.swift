import Foundation

/// Totals for one calendar day, built from the cycles that ended that day.
struct DaySummary: Equatable, Sendable {
    var day: Date
    var screenSeconds: TimeInterval = 0
    var completed = 0
    var skipped = 0
    var missed = 0
    var natural = 0
    var longestStretch: TimeInterval = 0
    var restSeconds: TimeInterval = 0

    /// Eye breaks that were due and not taken.
    var breaksMissed: Int { skipped + missed }
    /// Times the eyes got a real rest: a guided break, or stepping away.
    var rests: Int { completed + natural }
    var hasScreenTime: Bool { screenSeconds >= 60 }

    init(day: Date) {
        self.day = day
    }

    init(day: Date, records: [CycleRecord], liveFocusSeconds: TimeInterval = 0) {
        self.day = day
        for record in records {
            screenSeconds += record.focusedSeconds
            restSeconds += record.restedSeconds
            longestStretch = max(longestStretch, record.focusedSeconds)
            switch record.outcome {
            case .completed: completed += 1
            case .skipped: skipped += 1
            case .missed: missed += 1
            case .natural: natural += 1
            case .stopped: break
            }
        }
        screenSeconds += liveFocusSeconds
        longestStretch = max(longestStretch, liveFocusSeconds)
    }
}

/// The daily Break Score: of the 20-minute blocks of screen time today, how many
/// were followed by a rest for the eyes? 100 means every block was.
enum BreakScore {
    static func score(for day: DaySummary, focusInterval: TimeInterval = 20 * 60) -> Int? {
        guard day.hasScreenTime, focusInterval > 0 else { return nil }
        let required = Int(day.screenSeconds / focusInterval)
        if required == 0 {
            // Not a full block yet: perfect unless a break was already dodged.
            return day.breaksMissed == 0 ? 100 : 50
        }
        let ratio = min(Double(day.rests) / Double(required), 1)
        return Int((ratio * 100).rounded())
    }

    /// A short label for a score, for headers and widgets.
    static func label(for score: Int?) -> String {
        guard let score else { return "No screen time yet" }
        switch score {
        case 90...: return "Excellent"
        case 70..<90: return "Good"
        case 40..<70: return "Room to improve"
        default: return "Time for more breaks"
        }
    }
}

enum DayStatus: Equatable, Sendable {
    /// Score reached the goal.
    case met
    /// Had screen time but the score stayed under the goal.
    case notMet
    /// No tracked screen time: neither extends nor breaks the streak.
    case noData
}

enum Streak {
    static let defaultGoal = 70
    /// Days with less screen time than this many intervals are light days:
    /// they neither extend nor break the streak.
    static let minimumBlocks = 3

    static func status(of day: DaySummary, goal: Int = defaultGoal, focusInterval: TimeInterval = 20 * 60) -> DayStatus {
        guard day.screenSeconds >= focusInterval * Double(minimumBlocks),
              let score = BreakScore.score(for: day, focusInterval: focusInterval) else { return .noData }
        return score >= goal ? .met : .notMet
    }

    /// Consecutive days meeting the goal, counting back from today. Today only
    /// counts once it is met, so an unfinished day never breaks the streak.
    /// Days without screen time are skipped.
    static func current(
        statuses: [Date: DayStatus],
        today: Date,
        calendar: Calendar = .current,
        maxLookback: Int = 400
    ) -> Int {
        var count = 0
        let start = calendar.startOfDay(for: today)
        for offset in 0..<maxLookback {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { break }
            let status = statuses[day] ?? .noData
            switch status {
            case .met:
                count += 1
            case .notMet:
                if offset == 0 { continue }
                return count
            case .noData:
                continue
            }
        }
        return count
    }

    /// The longest run of met days in the history, skipping days without data.
    static func best(statuses: [Date: DayStatus], calendar: Calendar = .current) -> Int {
        let days = statuses.keys.sorted()
        guard let first = days.first, let last = days.last else { return 0 }
        var best = 0
        var run = 0
        var day = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        while day <= end {
            switch statuses[day] ?? .noData {
            case .met:
                run += 1
                best = max(best, run)
            case .notMet:
                run = 0
            case .noData:
                break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best
    }
}

/// Groups cycle records into per-day summaries (by the day each cycle ended).
enum DayGrouping {
    static func summaries(
        records: [CycleRecord],
        calendar: Calendar = .current
    ) -> [Date: DaySummary] {
        var grouped: [Date: [CycleRecord]] = [:]
        for record in records {
            grouped[calendar.startOfDay(for: record.endedAt), default: []].append(record)
        }
        return grouped.reduce(into: [:]) { result, entry in
            result[entry.key] = DaySummary(day: entry.key, records: entry.value)
        }
    }
}
