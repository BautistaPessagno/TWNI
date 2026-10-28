import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// What a locked app shows during an eye break. Apple only allows an icon,
/// a title, a subtitle and two buttons here; the text changes with the break
/// state because the shield is redrawn after each button tap.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let breakSeconds = ScreenTimeShared.breakSeconds
        let title: String
        let subtitle: String
        let primary: String

        if let started = ScreenTimeShared.restStartedAt {
            let left = Int((Double(breakSeconds) - Date().timeIntervalSince(started)).rounded(.up))
            if left > 0 {
                title = "Keep looking away"
                subtitle = "Look at something 6 m (20 ft) away. About \(left) s left, then tap Done."
            } else {
                title = "Eyes rested"
                subtitle = "Nice. Tap Done to unlock your apps."
            }
            primary = "Done"
        } else {
            title = "Time for an eye break"
            subtitle = "You've used your apps for \(ScreenTimeShared.intervalMinutes) minutes. Look at something 6 m (20 ft) away for \(breakSeconds) seconds."
            primary = "Start \(breakSeconds)-second break"
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: nil,
            icon: UIImage(systemName: "eye"),
            title: ShieldConfiguration.Label(text: title, color: .label),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: primary, color: .systemBackground),
            primaryButtonBackgroundColor: .label,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Guided break in TWNI", color: .label)
        )
    }
}
