import Foundation
import SwiftData

enum SessionSource: String, Codable {
    case `internal`
    case screenTimeAPI
}

@Model
final class ScreenSession {
    var startDate: Date
    var endDate: Date?
    var durationSeconds: Int
    var source: SessionSource

    @Relationship(deleteRule: .cascade, inverse: \BreakRecord.session)
    var breaks: [BreakRecord]

    init(
        startDate: Date = .now,
        endDate: Date? = nil,
        durationSeconds: Int = 0,
        source: SessionSource = .internal,
        breaks: [BreakRecord] = []
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.source = source
        self.breaks = breaks
    }
}
