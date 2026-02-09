import Foundation
import SwiftData

@Model
final class BreakRecord {
    var timestamp: Date
    var completed: Bool
    var durationSeconds: Int
    var session: ScreenSession?

    init(
        timestamp: Date = .now,
        completed: Bool = true,
        durationSeconds: Int = 20,
        session: ScreenSession? = nil
    ) {
        self.timestamp = timestamp
        self.completed = completed
        self.durationSeconds = durationSeconds
        self.session = session
    }
}
