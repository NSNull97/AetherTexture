import UIKit
import AsyncDisplayKit

public final class AetherContentUnavailableNode: AetherDisplayNode {

    public var configuration: AetherContentUnavailableConfiguration? {
        didSet { applyConfiguration() }
    }

    public var transitionDuration: TimeInterval = 0.18

    private let imageNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let secondaryTextNode = ASTextNode()
    private let loadingNode = AetherLoadingIndicatorNode()
    private let buttonNode = AetherContentUnavailableButtonNode()

    public init(configuration: AetherContentUnavailableConfiguration? = nil) {
        self.configuration = configuration
        super.init()
        addSubnode(imageNode)
        addSubnode(loadingNode)
        addSubnode(titleNode)
        addSubnode(secondaryTextNode)
        addSubnode(buttonNode)
        buttonNode.action = { [weak self] in
            self?.configuration?.button.primaryAction?()
        }
        applyConfiguration()
    }

    public override func layout() {
        super.layout()
        guard let config = configuration else {
            imageNode.frame = .zero
            loadingNode.frame = .zero
            titleNode.frame = .zero
            secondaryTextNode.frame = .zero
            buttonNode.frame = .zero
            return
        }

        let margins = config.directionalLayoutMargins
        let safeInsets = isNodeLoaded ? view.safeAreaInsets : .zero
        let safeBounds = bounds.inset(by: safeInsets)
        let availableWidth = max(0.0, safeBounds.width - margins.leading - margins.trailing)

        var imageFrame = CGRect.zero
        var loadingFrame = CGRect.zero
        var titleFrame = CGRect.zero
        var secondaryFrame = CGRect.zero
        var buttonFrame = CGRect.zero
        var contentHeight: CGFloat = 0.0

        if !imageNode.isHidden, let image = imageNode.image {
            imageFrame.size = Self.sizeForImage(image, max: config.imageProperties.maximumSize)
            contentHeight += imageFrame.height
        }
        if !loadingNode.isHidden {
            loadingFrame.size = loadingNode.preferredSize
            if imageFrame.size != .zero { contentHeight += config.imageToTextPadding }
            contentHeight += loadingFrame.height
        }
        if !titleNode.isHidden {
            let size = titleNode.layoutThatFits(
                ASSizeRange(min: .zero, max: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            ).size
            titleFrame.size = size
            if imageFrame.size != .zero || loadingFrame.size != .zero { contentHeight += config.imageToTextPadding }
            contentHeight += size.height
        }
        if !secondaryTextNode.isHidden {
            let size = secondaryTextNode.layoutThatFits(
                ASSizeRange(min: .zero, max: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            ).size
            secondaryFrame.size = size
            if titleFrame.size != .zero {
                contentHeight += config.textToSecondaryTextPadding
            } else if imageFrame.size != .zero || loadingFrame.size != .zero {
                contentHeight += config.imageToTextPadding
            }
            contentHeight += size.height
        }
        if !buttonNode.isHidden {
            buttonFrame.size = buttonNode.measuredSize(maxWidth: availableWidth)
            if titleFrame.size != .zero || secondaryFrame.size != .zero {
                contentHeight += config.textToButtonPadding
            }
            contentHeight += buttonFrame.height
        }

        let availableHeight = max(0.0, safeBounds.height - margins.top - margins.bottom)
        let centerX = safeBounds.midX
        var y = safeBounds.minY + margins.top + max(0.0, floor((availableHeight - contentHeight) / 2.0))

        if imageFrame.size != .zero {
            imageFrame.origin = CGPoint(x: floor(centerX - imageFrame.width / 2.0), y: y)
            y += imageFrame.height
        }
        if loadingFrame.size != .zero {
            if imageFrame.size != .zero { y += config.imageToTextPadding }
            loadingFrame.origin = CGPoint(x: floor(centerX - loadingFrame.width / 2.0), y: y)
            y += loadingFrame.height
        }
        if titleFrame.size != .zero {
            if imageFrame.size != .zero || loadingFrame.size != .zero { y += config.imageToTextPadding }
            titleFrame.origin = CGPoint(x: floor(centerX - titleFrame.width / 2.0), y: y)
            y += titleFrame.height
        }
        if secondaryFrame.size != .zero {
            if titleFrame.size != .zero {
                y += config.textToSecondaryTextPadding
            } else if imageFrame.size != .zero || loadingFrame.size != .zero {
                y += config.imageToTextPadding
            }
            secondaryFrame.origin = CGPoint(x: floor(centerX - secondaryFrame.width / 2.0), y: y)
            y += secondaryFrame.height
        }
        if buttonFrame.size != .zero {
            if titleFrame.size != .zero || secondaryFrame.size != .zero { y += config.textToButtonPadding }
            buttonFrame.origin = CGPoint(x: floor(centerX - buttonFrame.width / 2.0), y: y)
        }

        imageNode.frame = imageFrame
        loadingNode.frame = loadingFrame
        titleNode.frame = titleFrame
        secondaryTextNode.frame = secondaryFrame
        buttonNode.frame = buttonFrame
    }

    public func setConfiguration(_ configuration: AetherContentUnavailableConfiguration?, animated: Bool) {
        guard animated, isNodeLoaded else {
            self.configuration = configuration
            return
        }
        UIView.transition(
            with: view,
            duration: transitionDuration,
            options: [.transitionCrossDissolve, .beginFromCurrentState],
            animations: {
                self.configuration = configuration
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
            }
        )
    }

    private func applyConfiguration() {
        guard let config = configuration else {
            isHidden = true
            loadingNode.isAnimating = false
            setNeedsLayout()
            return
        }

        isHidden = false
        backgroundColor = config.background.backgroundColor

        if let image = config.image {
            imageNode.isHidden = false
            let configuredImage = config.imageProperties.preferredSymbolConfiguration.map {
                image.withConfiguration($0)
            } ?? image
            imageNode.image = Self.renderedImage(configuredImage, tintColor: config.imageProperties.tintColor)
            imageNode.tintColor = config.imageProperties.tintColor
        } else {
            imageNode.isHidden = true
            imageNode.image = nil
        }

        if let text = config.text, !text.isEmpty {
            titleNode.isHidden = false
            titleNode.maximumNumberOfLines = UInt(config.textProperties.numberOfLines)
            titleNode.attributedText = Self.attributedText(text, properties: config.textProperties)
        } else {
            titleNode.isHidden = true
            titleNode.attributedText = nil
        }

        if let secondaryText = config.secondaryText, !secondaryText.isEmpty {
            secondaryTextNode.isHidden = false
            secondaryTextNode.maximumNumberOfLines = UInt(config.secondaryTextProperties.numberOfLines)
            secondaryTextNode.attributedText = Self.attributedText(secondaryText, properties: config.secondaryTextProperties)
        } else {
            secondaryTextNode.isHidden = true
            secondaryTextNode.attributedText = nil
        }

        if let loading = config.loadingIndicator {
            loadingNode.isHidden = false
            loadingNode.color = loading.color ?? .secondaryLabel
            loadingNode.indicatorStyle = loading.style
            loadingNode.isAnimating = true
        } else {
            loadingNode.isHidden = true
            loadingNode.isAnimating = false
        }

        if config.button.title?.isEmpty == false || config.button.image != nil {
            buttonNode.isHidden = false
            buttonNode.configure(properties: config.button)
        } else {
            buttonNode.isHidden = true
            buttonNode.configure(properties: .init())
        }

        setNeedsLayout()
    }

    private static func attributedText(
        _ string: String,
        properties: AetherContentUnavailableConfiguration.TextProperties
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = properties.alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: string,
            attributes: [
                .font: properties.font,
                .foregroundColor: properties.color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private static func sizeForImage(_ image: UIImage, max: CGSize) -> CGSize {
        var width = image.size.width
        var height = image.size.height
        if width <= 0.0 || height <= 0.0 {
            return max == .zero ? CGSize(width: 56.0, height: 56.0) : max
        }
        if max.width > 0.0, width > max.width {
            let scale = max.width / width
            width *= scale
            height *= scale
        }
        if max.height > 0.0, height > max.height {
            let scale = max.height / height
            width *= scale
            height *= scale
        }
        return CGSize(width: width, height: height)
    }

    private static func renderedImage(_ image: UIImage, tintColor: UIColor?) -> UIImage {
        guard let tintColor else { return image }
        let template = image.withRenderingMode(.alwaysTemplate)
        UIGraphicsBeginImageContextWithOptions(template.size, false, template.scale)
        tintColor.setFill()
        let rect = CGRect(origin: .zero, size: template.size)
        template.draw(in: rect)
        UIRectFillUsingBlendMode(rect, .sourceAtop)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? template
    }
}

private final class AetherLoadingIndicatorNode: ASDisplayNode {
    var color: UIColor = .secondaryLabel {
        didSet { shapeLayer.strokeColor = color.cgColor }
    }

    var indicatorStyle: UIActivityIndicatorView.Style = .large {
        didSet { setNeedsLayout() }
    }

    var isAnimating: Bool = false {
        didSet { updateAnimation() }
    }

    private let shapeLayer = CAShapeLayer()

    var preferredSize: CGSize {
        switch indicatorStyle {
        case .medium:
            return CGSize(width: 20.0, height: 20.0)
        default:
            return CGSize(width: 37.0, height: 37.0)
        }
    }

    override init() {
        super.init()
        isLayerBacked = true
    }

    override func didLoad() {
        super.didLoad()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineCap = .round
        layer.addSublayer(shapeLayer)
        updateAnimation()
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        let lineWidth = max(2.0, min(bounds.width, bounds.height) * 0.08)
        shapeLayer.lineWidth = lineWidth
        let radius = max(0.0, min(bounds.width, bounds.height) / 2.0 - lineWidth)
        shapeLayer.path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: radius,
            startAngle: -.pi / 2.0,
            endAngle: .pi * 1.2,
            clockwise: true
        ).cgPath
    }

    private func updateAnimation() {
        guard isNodeLoaded else { return }
        if isAnimating {
            if shapeLayer.animation(forKey: "aether.rotation") == nil {
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.fromValue = 0.0
                animation.toValue = CGFloat.pi * 2.0
                animation.duration = 0.85
                animation.repeatCount = .infinity
                shapeLayer.add(animation, forKey: "aether.rotation")
            }
        } else {
            shapeLayer.removeAnimation(forKey: "aether.rotation")
        }
    }
}

private final class AetherContentUnavailableButtonNode: ASControlNode {
    var action: (() -> Void)?

    private let titleNode = ASTextNode()
    private let imageNode = ASImageNode()
    private var properties = AetherContentUnavailableConfiguration.ButtonProperties()

    override init() {
        super.init()
        addSubnode(imageNode)
        addSubnode(titleNode)
        addTarget(self, action: #selector(pressed), forControlEvents: .touchUpInside)
        titleNode.maximumNumberOfLines = 1
        imageNode.contentMode = .scaleAspectFit
    }

    func configure(properties: AetherContentUnavailableConfiguration.ButtonProperties) {
        self.properties = properties
        if let title = properties.title, !title.isEmpty {
            titleNode.isHidden = false
            titleNode.attributedText = NSAttributedString(
                string: title,
                attributes: [
                    .font: properties.titleFont,
                    .foregroundColor: properties.tintColor
                ]
            )
        } else {
            titleNode.isHidden = true
            titleNode.attributedText = nil
        }
        if let image = properties.image {
            imageNode.isHidden = false
            imageNode.image = image.withRenderingMode(.alwaysTemplate)
            imageNode.tintColor = properties.tintColor
        } else {
            imageNode.isHidden = true
            imageNode.image = nil
        }
        setNeedsLayout()
    }

    func measuredSize(maxWidth: CGFloat) -> CGSize {
        let insets = properties.contentInsets
        let maxContentWidth = max(0.0, maxWidth - insets.leading - insets.trailing)
        let titleSize = titleNode.isHidden
            ? .zero
            : titleNode.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: maxContentWidth, height: .greatestFiniteMagnitude))).size
        let imageSize = fittedImageSize()
        let spacing: CGFloat = titleSize != .zero && imageSize != .zero ? 8.0 : 0.0
        let contentWidth = titleSize.width + imageSize.width + spacing
        let contentHeight = max(titleSize.height, imageSize.height)
        return CGSize(
            width: min(maxWidth, max(140.0, ceil(contentWidth + insets.leading + insets.trailing))),
            height: max(40.0, ceil(contentHeight + insets.top + insets.bottom))
        )
    }

    override func layout() {
        super.layout()
        let insets = properties.contentInsets
        let contentRect = bounds.inset(by: UIEdgeInsets(
            top: insets.top,
            left: insets.leading,
            bottom: insets.bottom,
            right: insets.trailing
        ))
        let maxTitleWidth = max(0.0, contentRect.width)
        let titleSize = titleNode.isHidden
            ? .zero
            : titleNode.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: maxTitleWidth, height: contentRect.height))).size
        let imageSize = fittedImageSize()
        let spacing: CGFloat = titleSize != .zero && imageSize != .zero ? 8.0 : 0.0
        let contentWidth = imageSize.width + spacing + titleSize.width
        var x = floor(contentRect.midX - contentWidth / 2.0)

        if imageSize != .zero {
            imageNode.frame = CGRect(
                x: x,
                y: floor(contentRect.midY - imageSize.height / 2.0),
                width: imageSize.width,
                height: imageSize.height
            )
            x += imageSize.width + spacing
        } else {
            imageNode.frame = .zero
        }

        if titleSize != .zero {
            titleNode.frame = CGRect(
                x: x,
                y: floor(contentRect.midY - titleSize.height / 2.0),
                width: titleSize.width,
                height: titleSize.height
            )
        } else {
            titleNode.frame = .zero
        }
    }

    private func fittedImageSize() -> CGSize {
        guard !imageNode.isHidden, let image = imageNode.image else { return .zero }
        let maxSide: CGFloat = 22.0
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxSide else { return image.size }
        let scale = maxSide / largestSide
        return CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
    }

    @objc private func pressed() {
        action?()
    }
}

open class AetherSkeletonNode: AetherDisplayNode {
    public var theme: AetherSkeletonTheme {
        didSet {
            applyTheme()
            restartShimmerIfNeeded(force: true)
        }
    }

    public var isAnimating: Bool {
        didSet {
            if oldValue != isAnimating {
                restartShimmerIfNeeded(force: true)
            }
        }
    }

    private let gradientLayer = CAGradientLayer()
    private var currentSweepAnimation: CABasicAnimation?
    private var lastSweepWidth: CGFloat = 0.0
    private var lifecycleObservers: [NSObjectProtocol] = []

    public init(theme: AetherSkeletonTheme = .light, isAnimating: Bool = true, cornerRadius: CGFloat = 0.0) {
        self.theme = theme
        self.isAnimating = isAnimating
        super.init()
        self.cornerRadius = cornerRadius
        backgroundColor = theme.baseColor
        setupLifecycleObservers()
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public override func didLoad() {
        super.didLoad()
        layer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        layer.addSublayer(gradientLayer)
        applyTheme()
        restartShimmerIfNeeded(force: true)
    }

    public override func layout() {
        super.layout()
        layer.cornerRadius = resolvedCornerRadius(for: bounds.size)

        let sweepWidth = bounds.width * 2.0
        let newFrame = CGRect(x: -bounds.width, y: 0.0, width: sweepWidth, height: bounds.height)
        if gradientLayer.frame != newFrame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.frame = newFrame
            CATransaction.commit()
        }
        restartShimmerIfNeeded(force: false)
    }

    open func resolvedCornerRadius(for size: CGSize) -> CGFloat {
        cornerRadius
    }

    public func refreshThemeForCurrentTraits() {
        applyTheme()
    }

    private func setupLifecycleObservers() {
        let restart: () -> Void = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.restartShimmerIfNeeded(force: true)
            }
        }
        let willForeground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in restart() }
        let didActivate = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in restart() }
        lifecycleObservers = [willForeground, didActivate]
    }

    private func applyTheme() {
        backgroundColor = theme.baseColor
        guard isNodeLoaded else { return }
        let traitCollection = view.traitCollection
        let resolvedBase = theme.baseColor.resolvedColor(with: traitCollection)
        let resolvedHighlight = theme.highlightColor.resolvedColor(with: traitCollection)
        gradientLayer.colors = [
            resolvedBase.cgColor,
            resolvedHighlight.cgColor,
            resolvedBase.cgColor
        ]
        let fraction = max(0.1, min(0.9, theme.shimmerWidthFraction))
        gradientLayer.locations = [
            NSNumber(value: 0.5 - Double(fraction) / 2.0),
            NSNumber(value: 0.5),
            NSNumber(value: 0.5 + Double(fraction) / 2.0)
        ]
    }

    private func restartShimmerIfNeeded(force: Bool) {
        guard isNodeLoaded else { return }
        let currentWidth = bounds.width
        let animationAttached = gradientLayer.animation(forKey: "sweep") != nil

        if !force,
           isAnimating,
           animationAttached,
           abs(lastSweepWidth - currentWidth) < 0.5 {
            return
        }

        gradientLayer.removeAnimation(forKey: "sweep")
        currentSweepAnimation = nil

        guard isAnimating, currentWidth > 0.0 else {
            lastSweepWidth = 0.0
            return
        }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -currentWidth
        animation.toValue = currentWidth * 2.0
        animation.duration = theme.shimmerDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.beginTime = gradientLayer.convertTime(0.0, from: nil)
        gradientLayer.add(animation, forKey: "sweep")
        currentSweepAnimation = animation
        lastSweepWidth = currentWidth
    }
}

public final class AetherSkeletonLineNode: AetherSkeletonNode {
    public var lineHeight: CGFloat = 12.0 {
        didSet { setNeedsLayout() }
    }

    public override init(theme: AetherSkeletonTheme = .light, isAnimating: Bool = true, cornerRadius: CGFloat = 0.0) {
        super.init(theme: theme, isAnimating: isAnimating, cornerRadius: cornerRadius)
    }

    public override func resolvedCornerRadius(for size: CGSize) -> CGFloat {
        min(size.height / 2.0, size.width / 2.0)
    }
}

public final class AetherSkeletonBlockNode: AetherSkeletonNode {
    public override init(theme: AetherSkeletonTheme = .light, isAnimating: Bool = true, cornerRadius: CGFloat = 10.0) {
        super.init(theme: theme, isAnimating: isAnimating, cornerRadius: cornerRadius)
    }
}

public final class AetherSkeletonCircleNode: AetherSkeletonNode {
    public override init(theme: AetherSkeletonTheme = .light, isAnimating: Bool = true, cornerRadius: CGFloat = 0.0) {
        super.init(theme: theme, isAnimating: isAnimating, cornerRadius: cornerRadius)
    }

    public override func resolvedCornerRadius(for size: CGSize) -> CGFloat {
        min(size.width, size.height) / 2.0
    }
}
