#if canImport(ManagedSettings) && canImport(ManagedSettingsUI)
import ManagedSettings
import ManagedSettingsUI
import UIKit

class TWNIShieldConfigurationProvider: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.110, green: 0.106, blue: 0.094, alpha: 1.0),
            icon: UIImage(systemName: "eye"),
            title: ShieldConfiguration.Label(
                text: "En descanso",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Mirá algo a 6 metros por 20 segundos.",
                color: UIColor.white.withAlphaComponent(0.7)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Abrir TWNI para desbloquear",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.white.withAlphaComponent(0.15),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Entendido",
                color: UIColor.white.withAlphaComponent(0.5)
            )
        )
    }
}
#endif
