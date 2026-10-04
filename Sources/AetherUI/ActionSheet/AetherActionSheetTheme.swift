import UIKit

public enum AetherActionSheetBackgroundType: Equatable {
    case light
    case dark
}

public struct AetherActionSheetTheme: Equatable {
    public let dimColor: UIColor
    public let backgroundType: AetherActionSheetBackgroundType
    public let itemBackgroundColor: UIColor
    public let itemHighlightedBackgroundColor: UIColor
    public let standardActionTextColor: UIColor
    public let destructiveActionTextColor: UIColor
    public let disabledActionTextColor: UIColor
    public let primaryTextColor: UIColor
    public let secondaryTextColor: UIColor
    public let controlAccentColor: UIColor
    public let controlColor: UIColor
    public let separatorColor: UIColor
    public let baseFontSize: CGFloat
    /// Tint of the single floating surface behind all action groups.
    public let cardBackgroundColor: UIColor

    public init(
        dimColor: UIColor,
        backgroundType: AetherActionSheetBackgroundType,
        itemBackgroundColor: UIColor,
        itemHighlightedBackgroundColor: UIColor,
        standardActionTextColor: UIColor,
        destructiveActionTextColor: UIColor,
        disabledActionTextColor: UIColor,
        primaryTextColor: UIColor,
        secondaryTextColor: UIColor,
        controlAccentColor: UIColor,
        controlColor: UIColor,
        separatorColor: UIColor,
        baseFontSize: CGFloat = 17.0,
        cardBackgroundColor: UIColor? = nil
    ) {
        self.dimColor = dimColor
        self.backgroundType = backgroundType
        self.itemBackgroundColor = itemBackgroundColor
        self.itemHighlightedBackgroundColor = itemHighlightedBackgroundColor
        self.standardActionTextColor = standardActionTextColor
        self.destructiveActionTextColor = destructiveActionTextColor
        self.disabledActionTextColor = disabledActionTextColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.controlAccentColor = controlAccentColor
        self.controlColor = controlColor
        self.separatorColor = separatorColor
        self.baseFontSize = min(26.0, baseFontSize)
        self.cardBackgroundColor = cardBackgroundColor ?? (backgroundType == .dark
            ? UIColor(white: 0.15, alpha: 0.92)
            : UIColor.white.withAlphaComponent(0.92))
    }

    public static let light = AetherActionSheetTheme(
        dimColor: UIColor(white: 0.0, alpha: 0.08),
        backgroundType: .light,
        itemBackgroundColor: AetherAlertTheme.light.pillFillColor,
        itemHighlightedBackgroundColor: AetherAlertTheme.light.highlightedItemColor,
        standardActionTextColor: .black,
        destructiveActionTextColor: UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),
        disabledActionTextColor: UIColor(white: 0.6, alpha: 1.0),
        primaryTextColor: .black,
        secondaryTextColor: UIColor(white: 0.4, alpha: 1.0),
        controlAccentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        controlColor: UIColor(white: 0.7, alpha: 1.0),
        separatorColor: UIColor(white: 0.0, alpha: 0.1),
        cardBackgroundColor: AetherAlertTheme.light.backgroundColor
    )

    public static let dark = AetherActionSheetTheme(
        dimColor: UIColor(white: 0.0, alpha: 0.24),
        backgroundType: .dark,
        itemBackgroundColor: AetherAlertTheme.dark.pillFillColor,
        itemHighlightedBackgroundColor: AetherAlertTheme.dark.highlightedItemColor,
        standardActionTextColor: .white,
        destructiveActionTextColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0),
        disabledActionTextColor: UIColor(white: 0.5, alpha: 1.0),
        primaryTextColor: .white,
        secondaryTextColor: UIColor(white: 0.7, alpha: 1.0),
        controlAccentColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        controlColor: UIColor(white: 0.3, alpha: 1.0),
        separatorColor: UIColor(white: 1.0, alpha: 0.1),
        cardBackgroundColor: AetherAlertTheme.dark.backgroundColor
    )
}
