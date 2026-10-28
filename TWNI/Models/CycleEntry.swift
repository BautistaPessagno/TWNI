import Foundation
import SwiftData

/// One stretch of screen time and how it ended (stored form of `CycleRecord`).
/// Every property has a default so future schema changes migrate cleanly.
@Model
final class CycleEntry {
    var startedAt: Date = Date.distantPast
    var endedAt: Date = Date.distantPast
    var focusedSeconds: Double = 0
    var restedSeconds: Double = 0
    var snoozeCount: Int = 0
    var outcomeRaw: String = CycleOutcome.stopped.rawValue
    /// "mac" or "ios", for when history is merged across devices later.
    var device: String = ""

    init(record: CycleRecord, device: String) {
        self.startedAt = record.startedAt
        self.endedAt = record.endedAt
        self.focusedSeconds = record.focusedSeconds
        self.restedSeconds = record.restedSeconds
        self.snoozeCount = record.snoozeCount
        self.outcomeRaw = record.outcome.rawValue
        self.device = device
    }

    var record: CycleRecord {
        CycleRecord(
            startedAt: startedAt,
            endedAt: endedAt,
            focusedSeconds: focusedSeconds,
            restedSeconds: restedSeconds,
            snoozeCount: snoozeCount,
            outcome: CycleOutcome(rawValue: outcomeRaw) ?? .stopped
        )
    }
}
