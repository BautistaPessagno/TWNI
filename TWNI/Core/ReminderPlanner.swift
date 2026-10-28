import Foundation

/// Works out when to fire break reminders while the app can't run (iOS in the
/// background). Matches `EyeTimerEngine`'s `.focus` gap model: an ignored
/// reminder starts the next interval at the moment it fired.
enum ReminderPlanner {
    /// iOS keeps at most 64 pending notifications per app; leave room for others.
    static let maxReminders = 48

    static func reminderDates(
        for engine: EyeTimerEngine,
        now: Date,
        until end: Date?,
        limit: Int = maxReminders
    ) -> [Date] {
        guard limit > 0, engine.settings.focusInterval > 0,
              var next = engine.nextBreakDate(from: now) else { return [] }
        // A due-now break would fire immediately; nudge it a few seconds out.
        next = max(next, now.addingTimeInterval(5))
        var dates: [Date] = []
        while dates.count < limit {
            if let end, next > end { break }
            dates.append(next)
            next = next.addingTimeInterval(engine.settings.focusInterval)
        }
        return dates
    }
}
