import Foundation

/// Platform-independent routing for local notification responses.
enum NotificationAction: Equatable, Sendable {
    case open
    case startBreak
    case snooze
    case skip
    case restDone

    enum Identifier {
        static let start = "START_BREAK"
        static let snooze = "SNOOZE"
        static let skip = "SKIP"
        static let restDone = "rest-done"
    }

    init(actionIdentifier: String, requestIdentifier: String) {
        if requestIdentifier == Identifier.restDone {
            self = .restDone
            return
        }
        switch actionIdentifier {
        case Identifier.start: self = .startBreak
        case Identifier.snooze: self = .snooze
        case Identifier.skip: self = .skip
        default: self = .open
        }
    }
}
