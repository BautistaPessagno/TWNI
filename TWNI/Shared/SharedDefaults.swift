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

    var isBreakPending: Bool {
        get { store.bool(forKey: TWNIConstants.DefaultsKey.breakPending) }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.breakPending) }
    }

    var breakEndDate: Date? {
        get { store.object(forKey: TWNIConstants.DefaultsKey.breakEndDate) as? Date }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.breakEndDate) }
    }

    var isBlockingEnabled: Bool {
        get { store.bool(forKey: TWNIConstants.DefaultsKey.appBlockingEnabled) }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.appBlockingEnabled) }
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

    // MARK: - Break App Selection (shared with extension)

    var breakSelectionData: Data? {
        get { store.data(forKey: TWNIConstants.DefaultsKey.breakSelectionData) }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.breakSelectionData) }
    }

    // MARK: - Timer Configuration (shared with extension)

    var intervalMinutes: Int {
        get {
            let val = store.integer(forKey: TWNIConstants.DefaultsKey.intervalMinutes)
            return val > 0 ? val : 20
        }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.intervalMinutes) }
    }

    var breakDurationSeconds: Int {
        get {
            let val = store.integer(forKey: TWNIConstants.DefaultsKey.breakDurationSeconds)
            return val > 0 ? val : 20
        }
        set { store.set(newValue, forKey: TWNIConstants.DefaultsKey.breakDurationSeconds) }
    }

    // MARK: - Custom App Groups

    var customAppGroups: [CustomAppGroup] {
        get {
            guard let data = store.data(forKey: TWNIConstants.DefaultsKey.customAppGroups),
                  let decoded = try? JSONDecoder().decode([CustomAppGroup].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            store.set(data, forKey: TWNIConstants.DefaultsKey.customAppGroups)
        }
    }

    func customAppGroup(for id: UUID) -> CustomAppGroup? {
        customAppGroups.first { $0.id == id }
    }

    func updateCustomAppGroup(_ group: CustomAppGroup) {
        var all = customAppGroups
        if let index = all.firstIndex(where: { $0.id == group.id }) {
            all[index] = group
        } else {
            all.append(group)
        }
        customAppGroups = all
    }

    func removeCustomAppGroup(id: UUID) {
        customAppGroups.removeAll { $0.id == id }
    }
}
