import ManagedSettings
import ManagedSettingsUI
import UIKit

class TWNIShieldConfigurationProvider: ShieldConfigurationDataSource {
    private let shared = SharedDefaults.shared

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    // MARK: - Configuration Builder

    private func makeConfiguration() -> ShieldConfiguration {
        switch shared.blockReason {
        case .eyeBreak:
            return makeBreakConfiguration()
        case .scheduledBlock, nil:
            return makeScheduleConfiguration()
        }
    }

    private func makeBreakConfiguration() -> ShieldConfiguration {
        let remaining = remainingBreakSeconds()
        let subtitle: String
        if let remaining, remaining > 0 {
            subtitle = "Look at something 20 feet away for \(remaining) seconds."
        } else {
            subtitle = "Look at something 20 feet away for 20 seconds."
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.black.withAlphaComponent(0.85),
            title: ShieldConfiguration.Label(
                text: "Time for an Eye Break",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.7)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open TWNI",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemGray
        )
    }

    private func makeScheduleConfiguration() -> ShieldConfiguration {
        let scheduleName = activeScheduleName()
        let endTime = activeScheduleEndTime()

        var subtitle = "Stay focused and avoid distractions."
        if let endTime {
            subtitle = "Focus time until \(endTime). Stay on track."
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.black.withAlphaComponent(0.85),
            title: ShieldConfiguration.Label(
                text: scheduleName ?? "Focus Time",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.7)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open TWNI",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemGray
        )
    }

    // MARK: - Helpers

    private func remainingBreakSeconds() -> Int? {
        guard let endDate = shared.breakEndDate else { return nil }
        let remaining = Int(endDate.timeIntervalSinceNow)
        return Swift.max(remaining, 0)
    }

    private func activeScheduleName() -> String? {
        guard let id = shared.activeScheduleID else { return nil }
        return shared.schedule(for: id)?.name
    }

    private func activeScheduleEndTime() -> String? {
        guard let id = shared.activeScheduleID,
              let schedule = shared.schedule(for: id) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = schedule.endTime.hour
        components.minute = schedule.endTime.minute
        guard let date = Calendar.current.date(from: components) else { return nil }
        return formatter.string(from: date)
    }
}
