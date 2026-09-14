import UIKit
import AsyncDisplayKit

// MARK: - Configuration

/// Drop-in analogue of `UIContentUnavailableConfiguration`.
///
/// Build a configuration via `.empty()`, `.loading()`, or `.error()` and
/// override individual fields:
///
///     var config = AetherContentUnavailableConfiguration.empty()
///     config.image = UIImage(systemName: "tray")
///     config.text = "Здесь пока пусто"
///     config.secondaryText = "Добавьте первую запись"
///     config.button.title = "Добавить"
///     config.button.primaryAction = { [weak self] in self?.add() }
///     stateView.configuration = config
///
/// Setting `configuration` to `nil` hides the view and lets touches pass
/// through to underlying content.
public struct AetherContentUnavailableConfiguration {
    public var image: UIImage?
    public var imageProperties: ImageProperties
    public var text: String?
    public var textProperties: TextProperties
    public var secondaryText: String?
    public var secondaryTextProperties: TextProperties
    public var button: ButtonProperties
    public var loadingIndicator: LoadingIndicatorProperties?
    public var background: BackgroundProperties
    public var directionalLayoutMargins: NSDirectionalEdgeInsets
    public var imageToTextPadding: CGFloat
    public var textToSecondaryTextPadding: CGFloat
    public var textToButtonPadding: CGFloat

    public init(
        image: UIImage? = nil,
        imageProperties: ImageProperties = .init(),
        text: String? = nil,
        textProperties: TextProperties = .title,
        secondaryText: String? = nil,
        secondaryTextProperties: TextProperties = .secondary,
        button: ButtonProperties = .init(),
        loadingIndicator: LoadingIndicatorProperties? = nil,
        background: BackgroundProperties = .init(),
        directionalLayoutMargins: NSDirectionalEdgeInsets = .init(top: 24, leading: 32, bottom: 24, trailing: 32),
        imageToTextPadding: CGFloat = 14,
        textToSecondaryTextPadding: CGFloat = 6,
        textToButtonPadding: CGFloat = 20
    ) {
        self.image = image
        self.imageProperties = imageProperties
        self.text = text
        self.textProperties = textProperties
        self.secondaryText = secondaryText
        self.secondaryTextProperties = secondaryTextProperties
        self.button = button
        self.loadingIndicator = loadingIndicator
        self.background = background
        self.directionalLayoutMargins = directionalLayoutMargins
        self.imageToTextPadding = imageToTextPadding
        self.textToSecondaryTextPadding = textToSecondaryTextPadding
        self.textToButtonPadding = textToButtonPadding
    }

    // MARK: Factories

    /// Blank empty-state preset. Caller fills in image/text/button.
    public static func empty() -> Self {
        Self()
    }

    /// Loading-state preset with a centered activity indicator.
    /// Set `secondaryText` to add a caption beneath the spinner.
    public static func loading() -> Self {
        var config = Self()
        config.loadingIndicator = LoadingIndicatorProperties()
        return config
    }

    /// Error-state preset. Caller fills in text/secondaryText/button.
    public static func error() -> Self {
        Self()
    }

    // MARK: Image

    public struct ImageProperties {
        public var tintColor: UIColor?
        public var preferredSymbolConfiguration: UIImage.SymbolConfiguration?
        /// Maximum rendered size. Use `.zero` for unbounded (intrinsic) size.
        public var maximumSize: CGSize

        public init(
            tintColor: UIColor? = UIColor(white: 0.5, alpha: 1.0),
            preferredSymbolConfiguration: UIImage.SymbolConfiguration? = nil,
            maximumSize: CGSize = CGSize(width: 56, height: 56)
        ) {
            self.tintColor = tintColor
            self.preferredSymbolConfiguration = preferredSymbolConfiguration
            self.maximumSize = maximumSize
        }
    }

    // MARK: Text

    public struct TextProperties {
        public var font: UIFont
        public var color: UIColor
        public var alignment: NSTextAlignment
        public var numberOfLines: Int

        public init(
            font: UIFont = .aetherScaledSystemFont(ofSize: 17, weight: .semibold),
            color: UIColor = UIColor(white: 0.15, alpha: 1.0),
            alignment: NSTextAlignment = .center,
            numberOfLines: Int = 0
        ) {
            self.font = font
            self.color = color
            self.alignment = alignment
            self.numberOfLines = numberOfLines
        }

        public static let title = TextProperties()

        public static let secondary = TextProperties(
            font: .aetherScaledSystemFont(ofSize: 14),
            color: UIColor(white: 0.4, alpha: 1.0)
        )
    }

    // MARK: Button

    public struct ButtonProperties {
        public var title: String?
        public var image: UIImage?
        public var titleFont: UIFont
        public var tintColor: UIColor
        public var contentInsets: NSDirectionalEdgeInsets
        public var primaryAction: (() -> Void)?

        public init(
            title: String? = nil,
            image: UIImage? = nil,
            titleFont: UIFont = .aetherScaledSystemFont(ofSize: 15, weight: .medium),
            tintColor: UIColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
            contentInsets: NSDirectionalEdgeInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 16),
            primaryAction: (() -> Void)? = nil
        ) {
            self.title = title
            self.image = image
            self.titleFont = titleFont
            self.tintColor = tintColor
            self.contentInsets = contentInsets
            self.primaryAction = primaryAction
        }
    }

    // MARK: Loading indicator

    public struct LoadingIndicatorProperties {
        public var color: UIColor?
        public var style: UIActivityIndicatorView.Style

        public init(
            color: UIColor? = UIColor(white: 0.5, alpha: 1.0),
            style: UIActivityIndicatorView.Style = .large
        ) {
            self.color = color
            self.style = style
        }
    }

    // MARK: Background

    public struct BackgroundProperties {
        public var backgroundColor: UIColor?

        public init(backgroundColor: UIColor? = .clear) {
            self.backgroundColor = backgroundColor
        }
    }
}

// MARK: - View

/// View that renders a `AetherContentUnavailableConfiguration`.
/// Set `configuration = nil` to hide and let touches pass through.
public final class AetherContentUnavailableView: UIView {
    public var configuration: AetherContentUnavailableConfiguration? {
        get { contentNode.configuration }
        set {
            contentNode.configuration = newValue
            isHidden = newValue == nil
            setNeedsLayout()
        }
    }

    /// Cross-fade duration for `setConfiguration(_:animated:)`. Defaults to 0.18s.
    public var transitionDuration: TimeInterval {
        get { contentNode.transitionDuration }
        set { contentNode.transitionDuration = newValue }
    }

    public let contentNode: AetherContentUnavailableNode

    public init(configuration: AetherContentUnavailableConfiguration? = nil) {
        self.contentNode = AetherContentUnavailableNode(configuration: configuration)
        super.init(frame: .zero)
        addSubview(contentNode.view)
        isHidden = configuration == nil
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setConfiguration(_ configuration: AetherContentUnavailableConfiguration?, animated: Bool) {
        if configuration != nil {
            isHidden = false
        }
        contentNode.setConfiguration(configuration, animated: animated)
        if configuration == nil, animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) { [weak self] in
                guard self?.configuration == nil else { return }
                self?.isHidden = true
            }
        } else if configuration == nil {
            isHidden = true
        }
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        contentNode.frame = bounds
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if configuration == nil { return nil }
        return super.hitTest(point, with: event)
    }
}
