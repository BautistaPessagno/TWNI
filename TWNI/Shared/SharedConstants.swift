import Foundation

enum TWNIConstants {
    static let appGroupID = "group.com.twni.app"
    static let alwaysOnActivityName = "twni.always-on"

    enum DefaultsKey {
        static let schedules = "twni_schedules"
        static let blockReason = "twni_blockReason"
        static let breakActive = "twni_breakActive"
        static let breakPending = "twni_breakPending"
        static let breakEndDate = "twni_breakEndDate"
        static let activeScheduleID = "twni_activeScheduleID"
        static let breakSelectionData = "twni_breakSelectionData"
        static let intervalMinutes = "twni_intervalMinutes"
        static let breakDurationSeconds = "twni_breakDurationSeconds"
        static let customAppGroups = "twni_customAppGroups"
        static let appBlockingEnabled = "appBlockingEnabled"
    }
}
