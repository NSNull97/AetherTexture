import UIKit

/// Tab bar item configuration.
public final class AetherTabBarItem {
    public let title: String
    public let image: UIImage?
    public let selectedImage: UIImage?
    public var badgeValue: String?
    public var isEnabled: Bool

    public init(title: String, image: UIImage?, selectedImage: UIImage? = nil, badgeValue: String? = nil, isEnabled: Bool = true) {
        self.title = title
        self.image = image
        self.selectedImage = selectedImage ?? image
        self.badgeValue = badgeValue
        self.isEnabled = isEnabled
    }
}

/// A search tab whose placement is independent of the app's glass appearance.
public final class SearchTabItem: UITabBarItem {
    public enum Style: String {
        /// A separate button that transforms into a bottom search field.
        case separate
        /// A regular tab with search below its navigation bar. Its button
        /// separates from the tab bar when the bar is minimized.
        case inside
    }

    public var style: Style {
        didSet {
            guard style != oldValue else { return }
            styleDidChange?()
        }
    }

    internal var styleDidChange: (() -> Void)?
    public var action: (() -> Void)?

    public init(
        style: Style = .separate,
        image: UIImage? = UIImage(systemName: "magnifyingglass"),
        selectedImage: UIImage? = nil,
        action: (() -> Void)? = nil
    ) {
        self.style = style
        self.action = action
        super.init()
        self.image = image
        self.selectedImage = selectedImage ?? image
    }

    public required init?(coder: NSCoder) {
        let rawStyle = coder.decodeObject(of: NSString.self, forKey: "aether.search.style") as String?
        self.style = rawStyle.flatMap(Style.init(rawValue:)) ?? .separate
        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(style.rawValue, forKey: "aether.search.style")
    }
}
