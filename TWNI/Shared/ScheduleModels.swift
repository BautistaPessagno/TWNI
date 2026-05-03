import Foundation

enum BlockReason: String, Codable {
    case scheduledBlock
    case eyeBreak
}

enum CategoryPreset: String, Codable, CaseIterable, Identifiable {
    case socialNetworking = "Social Networking"
    case games = "Games"
    case entertainment = "Entertainment"
    case productivity = "Productivity"
    case education = "Education"
    case healthAndFitness = "Health & Fitness"
    case shopping = "Shopping"
    case news = "News"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .socialNetworking: "person.2.fill"
        case .games: "gamecontroller.fill"
        case .entertainment: "tv.fill"
        case .productivity: "briefcase.fill"
        case .education: "book.fill"
        case .healthAndFitness: "heart.fill"
        case .shopping: "cart.fill"
        case .news: "newspaper.fill"
        }
    }
}

struct ScheduleTimeOfDay: Codable, Hashable {
    var hour: Int
    var minute: Int
}

struct BlockSchedule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Schedule"
    var isEnabled: Bool = true
    var weekdays: Set<Int> = Set(1...7)
    var startTime: ScheduleTimeOfDay = ScheduleTimeOfDay(hour: 9, minute: 0)
    var endTime: ScheduleTimeOfDay = ScheduleTimeOfDay(hour: 17, minute: 0)
    var categoryPresets: Set<String> = []
    var customGroupIDs: Set<UUID> = []
    var selectionData: Data?
}

struct CustomAppGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Group"
    var selectionData: Data?
}
