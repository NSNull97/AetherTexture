import UIKit

public extension UIFont {
    /// A system font that follows the current Dynamic Type category while
    /// preserving the component's original visual size as the base size.
    static func aetherScaledSystemFont(
        ofSize size: CGFloat,
        weight: UIFont.Weight = .regular,
        maximumPointSize: CGFloat? = nil,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: .body)
        if let maximumPointSize {
            return metrics.scaledFont(
                for: baseFont,
                maximumPointSize: maximumPointSize,
                compatibleWith: traitCollection
            )
        }
        return metrics.scaledFont(for: baseFont, compatibleWith: traitCollection)
    }
}
