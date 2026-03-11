import Foundation

final class SharedDefaults: @unchecked Sendable {
    static let shared = SharedDefaults()

    let store: UserDefaults

    init() {
        store = UserDefaults(suiteName: TWNIConstants.appGroupID) ?? .standard
    }

    // MARK: - Schedules

    var schedules: [BlockSchedule] {
        get {
            guard let data = store.data(forKey: TWNIConstants.DefaultsKey.schedules),
                  let decoded = try? JSONDecoder().decode([BlockSchedule].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            store.set(data, forKey: TWNIConstants.DefaultsKey.schedules)
        }
    }

    func schedule(for id: UUID) -> BlockSchedule? {
        schedules.first { $0.id == id }
    }

    func updateSchedule(_ schedule: BlockSchedule) {
        var all = schedules
        if let index = all.firstIndex(where: { $0.id == schedule.id }) {
            all[index] = schedule
        } else {
            all.append(schedule)
        }
        schedules = all
    }

    func removeSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
    }

    // MARK: - Block Reason

    var blockReason: BlockReason? {
        get {
            guard let raw = store.string(forKey: TWNIConstants.DefaultsKey.blockReason) else { return nil }
            return BlockReason(rawValue: raw)
        }
        set {
            store.set(newValue?.rawValue, forKey: TWNIConstants.DefaultsKey.blockReason)
        }
    }

    // MARK: - Break State

    var isBreakActive: Bool {
        get { store.bool(forKey: TWNIConstants.DefaultsKey.breakActive) }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.breakActive) }
    }

    var breakEndDate: Date? {
        get { store.object(forKey: TWNIConstants.DefaultsKey.breakEndDate) as? Date }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.breakEndDate) }
    }

    // MARK: - Active Schedule

    var activeScheduleID: UUID? {
        get {
            guard let str = store.string(forKey: TWNIConstants.DefaultsKey.activeScheduleID) else { return nil }
            return UUID(uuidString: str)
        }
        set {
            store.set(newValue?.uuidString, forKey: TWNIConstants.DefaultsKey.activeScheduleID)
        }
    }
}
