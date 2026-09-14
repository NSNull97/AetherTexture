import UIKit
import AsyncDisplayKit

/// Appearance-aware circular button.
/// UIKit interaction shell with Texture-backed passive content.
public final class GlassButtonView: UIControl {
    // MARK: - Subviews

    private let blurView: GlassBackgroundView
    private let iconNode: ASImageNode
    private let labelNode: ASTextNode?
    private let labelText: String?

    private var regularImage: UIImage?
    private var highlightedImage: UIImage?
    private var filledImage: UIImage?

    // MARK: - Properties

    public var buttonSize: CGSize

    /// `nil` follows the application appearance runtime. Passing a value to
    /// the initializer seeds the backing surface before renderer allocation.
    public var appearanceStyleOverride: AetherAppearanceStyle? {
        get { blurView.appearanceStyleOverride }
        set { blurView.appearanceStyleOverride = newValue }
    }

    override public var isSelected: Bool {
        didSet {
            updateState()
        }
    }

    override public var isHighlighted: Bool {
        didSet {
            updateState()
        }
    }

    // MARK: - Init

    public init(
        icon: UIImage,
        label: String? = nil,
        size: CGSize = CGSize(width: 60, height: 60),
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.buttonSize = size

        let blurView = GlassBackgroundView(
            style: .regular,
            appearanceStyle: appearanceStyle
        )
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        blurView.surfaceRole = .button
        blurView.glassIsInteractive = false
        self.blurView = blurView

        self.iconNode = ASImageNode()
        self.iconNode.contentMode = .center

        if let label = label {
            let labelNode = ASTextNode()
            labelNode.maximumNumberOfLines = 1
            labelNode.truncationMode = .byTruncatingTail
            labelNode.attributedText = Self.attributedLabel(label, size: size)
            self.labelNode = labelNode
            self.labelText = label
        } else {
            self.labelNode = nil
            self.labelText = nil
        }

        // Generate button images
        self.regularImage = GlassButtonView.generateButtonImage(icon: icon, fillColor: .clear, size: size)
        self.highlightedImage = GlassButtonView.generateButtonImage(icon: icon, fillColor: UIColor(white: 1.0, alpha: 0.3), size: size)
        self.filledImage = GlassButtonView.generateButtonImage(icon: icon, fillColor: UIColor(white: 1.0, alpha: 1.0), knockout: true, size: size)

        super.init(frame: CGRect(origin: .zero, size: size))

        addSubview(blurView)
        iconNode.image = regularImage
        iconNode.view.isUserInteractionEnabled = false
        addSubview(iconNode.view)

        if let labelNode {
            labelNode.view.isUserInteractionEnabled = false
            addSubview(labelNode.view)
        }
    }

    internal var backingUsesLiquidGlassAppearanceForTesting: Bool {
        blurView.usesLiquidGlassAppearance
    }

    internal var backingUsesAnyGlassRendererForTesting: Bool {
        blurView.usesAnyGlassRendererForTesting
    }

    internal var backingLegacyBlurStyleForTesting: UIBlurEffect.Style? {
        blurView.legacyBlurStyleForTesting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        iconNode.view.removeFromSuperview()
        labelNode?.view.removeFromSuperview()
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        blurView.frame = bounds
        blurView.layer.cornerRadius = bounds.width / 2.0
        blurView.update(
            size: bounds.size,
            cornerRadius: bounds.width / 2.0,
            transition: .immediate
        )

        iconNode.frame = bounds

        if let labelNode, let labelText {
            let labelSize = Self.labelSize(labelText, size: buttonSize)
            let offset: CGFloat = bounds.width < 70 ? 65.0 : 81.0
            labelNode.frame = CGRect(
                x: (bounds.width - labelSize.width) / 2.0,
                y: offset,
                width: labelSize.width,
                height: labelSize.height
            )
        }
    }

    override public var intrinsicContentSize: CGSize {
        return buttonSize
    }

    // MARK: - State

    private func updateState() {
        let targetImage: UIImage?
        if isSelected {
            targetImage = filledImage
        } else if isHighlighted {
            targetImage = highlightedImage
        } else {
            targetImage = regularImage
        }

        if iconNode.image !== targetImage {
            let previousContents = iconNode.view.layer.contents
            iconNode.image = targetImage

            if let previousContents = previousContents, let targetImage = targetImage {
                let duration: Double = isSelected ? 0.25 : 0.15
                let animation = CABasicAnimation(keyPath: "contents")
                animation.fromValue = previousContents
                animation.toValue = targetImage.cgImage
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                iconNode.view.layer.add(animation, forKey: "contents")
            }
        }
    }

    // MARK: - Image Generation

    private static func generateButtonImage(icon: UIImage, fillColor: UIColor, knockout: Bool = false, size: CGSize) -> UIImage? {
        guard let iconImage = resolvedCGImage(for: icon) else { return nil }
        return generateImage(size, contextGenerator: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            context.setBlendMode(.copy)
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: size))

            let imageSize = icon.size
            let imageRect = CGRect(
                x: (size.width - imageSize.width) / 2.0,
                y: (size.height - imageSize.height) / 2.0,
                width: imageSize.width,
                height: imageSize.height
            )

            if knockout {
                context.setBlendMode(.copy)
                context.clip(to: imageRect, mask: iconImage)
                context.setFillColor(UIColor.clear.cgColor)
                context.fill(imageRect)
            } else {
                context.setBlendMode(.normal)
                context.draw(iconImage, in: imageRect)
            }
        })
    }

    /// SF Symbols and CI-backed UIImages do not necessarily expose a
    /// `cgImage`; rasterize those representations instead of force-unwrapping.
    private static func resolvedCGImage(for image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }
        guard image.size.width > 0.0, image.size.height > 0.0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    private static func attributedLabel(_ label: String, size: CGSize) -> NSAttributedString {
        NSAttributedString(
            string: label,
            attributes: [
                .font: labelFont(size: size),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centeredParagraphStyle
            ]
        )
    }

    private static func labelSize(_ label: String, size: CGSize) -> CGSize {
        let raw = (label as NSString).size(withAttributes: [.font: labelFont(size: size)])
        return CGSize(width: ceil(raw.width), height: ceil(raw.height))
    }

    private static func labelFont(size: CGSize) -> UIFont {
        UIFont.aetherScaledSystemFont(ofSize: size.width < 70 ? 11.5 : 14.5)
    }

    private static let centeredParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
}
