import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The block screen's look. The system renders it in its own font; only the
/// words (`CurfewCopy`) and colours (`CurfewShieldPalette`, pinned to DesignKit
/// by a unit test) are ours. One configuration for every kind of shield so an
/// app, a category, and a website all say the same thing. No green anywhere.
final class CurfewShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    Self.curfewConfiguration()
  }

  override func configuration(
    shielding application: Application,
    in category: ActivityCategory
  ) -> ShieldConfiguration {
    Self.curfewConfiguration()
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    Self.curfewConfiguration()
  }

  override func configuration(
    shielding webDomain: WebDomain,
    in category: ActivityCategory
  ) -> ShieldConfiguration {
    Self.curfewConfiguration()
  }

  private static func curfewConfiguration() -> ShieldConfiguration {
    ShieldConfiguration(
      backgroundBlurStyle: .systemUltraThinMaterialDark,
      backgroundColor: UIColor(curfewHex: CurfewShieldPalette.background),
      icon: UIImage(systemName: "moon.zzz"),
      title: ShieldConfiguration.Label(
        text: CurfewCopy.shieldTitle,
        color: UIColor(curfewHex: CurfewShieldPalette.textPrimary)
      ),
      subtitle: ShieldConfiguration.Label(
        text: CurfewCopy.shieldSubtitle,
        color: UIColor(curfewHex: CurfewShieldPalette.textSecondary)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: CurfewCopy.shieldPrimaryButton,
        color: UIColor(curfewHex: CurfewShieldPalette.onAccent)
      ),
      primaryButtonBackgroundColor: UIColor(curfewHex: CurfewShieldPalette.accent),
      secondaryButtonLabel: ShieldConfiguration.Label(
        text: CurfewCopy.shieldSecondaryButton,
        color: UIColor(curfewHex: CurfewShieldPalette.textSecondary)
      )
    )
  }
}

extension UIColor {
  /// `0xRRGGBB` from `CurfewShieldPalette`, fully opaque.
  convenience init(curfewHex hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
