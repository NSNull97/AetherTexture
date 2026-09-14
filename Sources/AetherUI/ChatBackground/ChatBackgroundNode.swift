import AsyncDisplayKit
import UIKit

public final class AetherMultiRadialGradientNode: ASDisplayNode {
    private static let imageCache = NSCache<NSString, UIImage>()

    private var gradient: ChatBackgroundSettings.RadialGradient?
    private var configuredInterfaceStyle: UIUserInterfaceStyle?
    private var appliedRenderKey: String?

    public override init() {
        super.init()
        isOpaque = false
        clipsToBounds = true
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    public override func didLoad() {
        super.didLoad()
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
        applyGradientIfNeeded(force: true)
    }

    public override func layout() {
        super.layout()
        applyGradientIfNeeded(force: false)
    }

    public func configure(
        _ gradient: ChatBackgroundSettings.RadialGradient,
        traits: UITraitCollection? = nil
    ) {
        self.gradient = gradient
        configuredInterfaceStyle = traits?.userInterfaceStyle
        appliedRenderKey = nil
        if isNodeLoaded {
            applyGradientIfNeeded(force: true)
        }
    }

    private func applyGradientIfNeeded(force: Bool) {
        guard let gradient, bounds.width > 0, bounds.height > 0 else { return }
        let interfaceStyle = configuredInterfaceStyle ?? (isNodeLoaded
            ? view.traitCollection.userInterfaceStyle
            : UITraitCollection.current.userInterfaceStyle)
        let traits = UITraitCollection(userInterfaceStyle: interfaceStyle)
        let scale = min(2, max(1, view.window?.screen.scale ?? UIScreen.main.scale))
        let renderKey = Self.renderKey(
            gradient: gradient,
            traits: traits,
            size: bounds.size,
            scale: scale
        )
        guard force || appliedRenderKey != renderKey else { return }
        appliedRenderKey = renderKey

        let cacheKey = renderKey as NSString
        let image: UIImage
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            image = cachedImage
        } else {
            image = Self.render(gradient: gradient, traits: traits, size: bounds.size, scale: scale)
            Self.imageCache.setObject(image, forKey: cacheKey)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = image.scale
        layer.contents = image.cgImage
        CATransaction.commit()
    }

    private static func render(
        gradient: ChatBackgroundSettings.RadialGradient,
        traits: UITraitCollection,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = colorComponents(
            gradient.baseColor.resolvedColor(with: traits)
        ).alpha >= 0.999
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let context = output.cgContext
            let baseColor = gradient.baseColor.resolvedColor(with: traits)
            context.setFillColor(baseColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            for field in gradient.fields {
                let color = field.color
                    .resolvedColor(with: traits)
                    .withAlphaComponent(field.opacity)
                guard let radialGradient = CGGradient(
                    colorsSpace: nil,
                    colors: [
                        color.cgColor,
                        color.withAlphaComponent(0).cgColor
                    ] as CFArray,
                    locations: [0, 1]
                ) else { continue }

                let center = CGPoint(
                    x: size.width * field.center.x,
                    y: size.height * field.center.y
                )
                let radiusX = max(1, size.width * max(0.01, field.radius.width))
                let radiusY = max(1, size.height * max(0.01, field.radius.height))
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: radiusX, y: radiusY)
                context.drawRadialGradient(
                    radialGradient,
                    startCenter: .zero,
                    startRadius: 0,
                    endCenter: .zero,
                    endRadius: 1,
                    options: []
                )
                context.restoreGState()
            }
        }
    }

    private static func renderKey(
        gradient: ChatBackgroundSettings.RadialGradient,
        traits: UITraitCollection,
        size: CGSize,
        scale: CGFloat
    ) -> String {
        var components = [
            String(Int((size.width * scale).rounded())),
            String(Int((size.height * scale).rounded())),
            colorKey(gradient.baseColor.resolvedColor(with: traits))
        ]
        components.append(contentsOf: gradient.fields.map { field in
            [
                colorKey(field.color.resolvedColor(with: traits)),
                scalarKey(field.center.x),
                scalarKey(field.center.y),
                scalarKey(field.radius.width),
                scalarKey(field.radius.height),
                scalarKey(field.opacity)
            ].joined(separator: ",")
        })
        return components.joined(separator: "|")
    }

    private static func colorKey(_ color: UIColor) -> String {
        let components = colorComponents(color)
        return [components.red, components.green, components.blue, components.alpha]
            .map(scalarKey)
            .joined(separator: ",")
    }

    private static func colorComponents(
        _ color: UIColor
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }
        var white: CGFloat = 0
        color.getWhite(&white, alpha: &alpha)
        return (white, white, white, alpha)
    }

    private static func scalarKey(_ value: CGFloat) -> String {
        String(Int((value * 10_000).rounded()))
    }
}

private final class ChatBackgroundTraitObserverView: UIView {
    var colorAppearanceDidChange: ((UITraitCollection) -> Void)?

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if let previousTraitCollection,
           !traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            return
        }
        colorAppearanceDidChange?(traitCollection)
    }
}

public final class ChatBackgroundNode: ASDisplayNode {
    public private(set) var settings: ChatBackgroundSettings
    public private(set) var contentStats: ChatBackgroundContentStats
    public var contentStatsUpdated: ((ChatBackgroundContentStats) -> Void)?

    private let visualContainerNode = ASDisplayNode()
    private let linearGradientNode = ChatBackgroundLinearGradientNode()
    private let radialGradientNode = AetherMultiRadialGradientNode()
    private let imageNode = ASImageNode()
    private let tiledImageNode = ChatBackgroundTiledImageNode()
    private let overlayImageNode = ASImageNode()
    private let overlayTiledImageNode = ChatBackgroundTiledImageNode()
    private let overlayGradientMaskNode = ChatBackgroundGradientMaskNode()
    private let patternNode = ChatBackgroundPatternNode()
    private let dimNode = ASDisplayNode()
    private lazy var blurNode = ASDisplayNode(viewBlock: { VisualEffectView() })
    private let traitObserverView = ChatBackgroundTraitObserverView()
    private var appliedInterfaceStyle: UIUserInterfaceStyle?

    public init(settings: ChatBackgroundSettings = .telegramClassic) {
        self.settings = settings
        self.contentStats = settings.estimatedContentStats()
        super.init()
        isOpaque = true
        clipsToBounds = true
        backgroundColor = .systemBackground
        automaticallyManagesSubnodes = false

        addSubnode(visualContainerNode)
        [
            linearGradientNode,
            radialGradientNode,
            imageNode,
            tiledImageNode,
            overlayImageNode,
            overlayTiledImageNode,
            overlayGradientMaskNode,
            blurNode,
            patternNode,
            dimNode
        ].forEach(visualContainerNode.addSubnode)

        imageNode.clipsToBounds = true
        overlayImageNode.clipsToBounds = true
        [linearGradientNode, radialGradientNode, imageNode, tiledImageNode].forEach { $0.isHidden = true }
        [overlayImageNode, overlayTiledImageNode, overlayGradientMaskNode].forEach { $0.isHidden = true }
        patternNode.isHidden = true
        dimNode.isHidden = true
    }

    public override func didLoad() {
        super.didLoad()
        traitObserverView.isUserInteractionEnabled = false
        traitObserverView.backgroundColor = .clear
        view.insertSubview(traitObserverView, at: 0)
        traitObserverView.colorAppearanceDidChange = { [weak self] traits in
            guard let self else { return }
            self.appliedInterfaceStyle = nil
            self.applySettings(force: true, traits: traits)
            self.setNeedsLayout()
        }
        applySettings(force: true, traits: traitObserverView.traitCollection)
    }

    public override func layout() {
        super.layout()
        applySettings(force: false, traits: traitObserverView.traitCollection)
        traitObserverView.frame = bounds
        let amount = resolvedMotionAmount()
        let visualFrame = bounds.insetBy(dx: -amount, dy: -amount)
        visualContainerNode.frame = visualFrame
        let contentBounds = CGRect(origin: .zero, size: visualFrame.size)
        [
            linearGradientNode,
            radialGradientNode,
            imageNode,
            tiledImageNode,
            overlayImageNode,
            overlayTiledImageNode,
            overlayGradientMaskNode,
            blurNode,
            patternNode,
            dimNode
        ].forEach { $0.frame = contentBounds }
    }

    public func setSettings(
        _ settings: ChatBackgroundSettings,
        transition: ContainedViewLayoutTransition = .immediate
    ) {
        self.settings = settings
        appliedInterfaceStyle = nil
        if isNodeLoaded {
            applySettings(force: true, traits: traitObserverView.traitCollection)
        }
        setNeedsLayout()
    }

    private func applySettings(force: Bool, traits: UITraitCollection) {
        let style = traits.userInterfaceStyle
        guard force || appliedInterfaceStyle != style else { return }
        appliedInterfaceStyle = style

        applyContent(traits: traits)
        applyImageOverlay(traits: traits)
        applyBlur()
        applyStats(traits: traits)
        patternNode.configure(pattern: settings.pattern, contentStats: contentStats, traits: traits)
        patternNode.isHidden = settings.pattern == nil
        dimNode.backgroundColor = settings.dimColor?.resolvedColor(with: traits)
        dimNode.isHidden = settings.dimColor == nil
        updateMotionEffects()
    }

    private func applyContent(traits: UITraitCollection) {
        [linearGradientNode, radialGradientNode, imageNode, tiledImageNode].forEach { $0.isHidden = true }
        visualContainerNode.backgroundColor = .clear

        switch settings.content {
        case let .color(color):
            visualContainerNode.backgroundColor = color.resolvedColor(with: traits)
        case let .gradient(gradient):
            linearGradientNode.isHidden = false
            linearGradientNode.configure(gradient, traits: traits)
        case let .radialGradient(gradient):
            radialGradientNode.isHidden = false
            radialGradientNode.configure(gradient, traits: traits)
        case let .image(image, mode):
            if mode == .tile {
                tiledImageNode.isHidden = false
                tiledImageNode.configure(image: image)
            } else {
                imageNode.isHidden = false
                imageNode.image = image
                imageNode.contentMode = Self.contentMode(for: mode)
            }
        }
    }

    private func applyImageOverlay(traits: UITraitCollection) {
        [overlayImageNode, overlayTiledImageNode, overlayGradientMaskNode].forEach { node in
            node.isHidden = true
            node.alpha = 1
        }
        overlayImageNode.image = nil
        overlayTiledImageNode.configure(image: nil)

        guard let overlay = settings.imageOverlay, overlay.alpha > 0 else { return }
        if let gradientTint = overlay.gradientTint, overlay.mode != .tile {
            overlayGradientMaskNode.isHidden = false
            overlayGradientMaskNode.alpha = overlay.alpha
            overlayGradientMaskNode.configure(
                image: overlay.image,
                mode: overlay.mode,
                gradient: gradientTint,
                traits: traits
            )
            return
        }

        if overlay.mode == .tile {
            overlayTiledImageNode.isHidden = false
            overlayTiledImageNode.alpha = overlay.alpha
            overlayTiledImageNode.configure(image: overlay.image)
        } else {
            overlayImageNode.isHidden = false
            overlayImageNode.alpha = overlay.alpha
            overlayImageNode.image = overlay.image
            overlayImageNode.contentMode = Self.contentMode(for: overlay.mode)
        }
    }

    private func applyBlur() {
        let radius = max(0, settings.blurRadius)
        let saturation = max(0, settings.blurSaturation)
        blurNode.alpha = radius > 0 ? 1 : 0
        blurNode.isHidden = radius <= 0
        guard isNodeLoaded else { return }

        let blurNode = self.blurNode
        Task { @MainActor in
            guard let blurView = blurNode.view as? VisualEffectView else { return }
            blurView.style = .customBlur
            blurView.isUserInteractionEnabled = false
            blurView.blurRadius = radius
            blurView.saturation = saturation
        }
    }

    private func applyStats(traits: UITraitCollection) {
        let stats = settings.estimatedContentStats(traitCollection: traits)
        guard stats != contentStats else { return }
        contentStats = stats
        contentStatsUpdated?(stats)
    }

    private func resolvedMotionAmount() -> CGFloat {
        guard settings.motionEnabled, !UIAccessibility.isReduceMotionEnabled else { return 0 }
        return max(0, min(64, settings.motionAmount))
    }

    private func updateMotionEffects() {
        guard visualContainerNode.isNodeLoaded else { return }
        let containerView = visualContainerNode.view
        containerView.motionEffects.forEach(containerView.removeMotionEffect)
        let amount = resolvedMotionAmount()
        guard amount > 0 else { return }

        let horizontal = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        horizontal.minimumRelativeValue = -amount
        horizontal.maximumRelativeValue = amount
        let vertical = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        vertical.minimumRelativeValue = -amount
        vertical.maximumRelativeValue = amount
        let group = UIMotionEffectGroup()
        group.motionEffects = [horizontal, vertical]
        containerView.addMotionEffect(group)
    }

    private static func contentMode(for mode: ChatBackgroundSettings.ImageContentMode) -> UIView.ContentMode {
        switch mode {
        case .aspectFill, .tile:
            return .scaleAspectFill
        case .aspectFit:
            return .scaleAspectFit
        case .fill:
            return .scaleToFill
        }
    }
}

private final class ChatBackgroundLinearGradientNode: ASDisplayNode {
    private let gradientLayer = CAGradientLayer()

    override init() {
        super.init()
        isOpaque = false
        backgroundColor = .clear
    }

    override func didLoad() {
        super.didLoad()
        gradientLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "colors": NSNull(),
            "locations": NSNull(),
            "startPoint": NSNull(),
            "endPoint": NSNull()
        ]
        layer.addSublayer(gradientLayer)
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    func configure(_ gradient: ChatBackgroundSettings.Gradient, traits: UITraitCollection) {
        let colors = gradient.colors.isEmpty ? [UIColor.systemBackground, .secondarySystemBackground] : gradient.colors
        let normalizedColors = colors.count == 1 ? [colors[0], colors[0]] : colors
        let vector = ChatBackgroundSettings.gradientVector(rotation: gradient.rotation)
        gradientLayer.colors = normalizedColors.map { $0.resolvedColor(with: traits).cgColor }
        gradientLayer.locations = gradient.locations
        gradientLayer.startPoint = vector.startPoint
        gradientLayer.endPoint = vector.endPoint
    }
}

private final class ChatBackgroundTiledImageNode: ASDisplayNode {
    func configure(image: UIImage?) {
        backgroundColor = image.map(UIColor.init(patternImage:)) ?? .clear
    }
}

private final class ChatBackgroundPatternNode: ASDisplayNode {
    private var cacheKey: String?

    override init() {
        super.init()
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    func configure(
        pattern: ChatBackgroundSettings.Pattern?,
        contentStats: ChatBackgroundContentStats,
        traits: UITraitCollection
    ) {
        guard let pattern, abs(pattern.clampedIntensity) > 0.001 else {
            cacheKey = nil
            backgroundColor = .clear
            return
        }
        let tint = (
            pattern.tintColor
                ?? (pattern.clampedIntensity < 0 ? UIColor.white : (contentStats.isDark ? .white : .black))
        ).resolvedColor(with: traits)
        let key = [
            String(pattern.image.hash),
            String(Int((pattern.clampedIntensity * 1_000).rounded())),
            String(Int((pattern.clampedScale * 1_000).rounded())),
            Self.colorKey(tint)
        ].joined(separator: "|")
        guard cacheKey != key else { return }
        cacheKey = key
        let tile = Self.tintedTile(
            image: pattern.image,
            color: tint.withAlphaComponent(abs(pattern.clampedIntensity)),
            scale: pattern.clampedScale
        )
        backgroundColor = UIColor(patternImage: tile)
    }

    private static func colorKey(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            color.getWhite(&white, alpha: &alpha)
            red = white
            green = white
            blue = white
        }
        return [red, green, blue, alpha]
            .map { String(Int(($0 * 10_000).rounded())) }
            .joined(separator: ",")
    }

    private static func tintedTile(image: UIImage, color: UIColor, scale: CGFloat) -> UIImage {
        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            color.setFill()
            context.fill(rect)
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }
}

private final class ChatBackgroundGradientMaskNode: ASDisplayNode {
    private let gradientNode = AetherMultiRadialGradientNode()
    private let imageMaskLayer = CALayer()
    private var image: UIImage?
    private var mode: ChatBackgroundSettings.ImageContentMode = .aspectFill

    override init() {
        super.init()
        isOpaque = false
        clipsToBounds = true
        addSubnode(gradientNode)
        imageMaskLayer.magnificationFilter = .linear
        imageMaskLayer.minificationFilter = .linear
    }

    override func didLoad() {
        super.didLoad()
        layer.mask = imageMaskLayer
        updateMask()
    }

    override func layout() {
        super.layout()
        gradientNode.frame = bounds
        updateMask()
    }

    func configure(
        image: UIImage,
        mode: ChatBackgroundSettings.ImageContentMode,
        gradient: ChatBackgroundSettings.RadialGradient,
        traits: UITraitCollection
    ) {
        self.image = image
        self.mode = mode
        gradientNode.configure(gradient, traits: traits)
        if isNodeLoaded {
            updateMask()
        }
    }

    private func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageMaskLayer.frame = bounds
        imageMaskLayer.contents = image?.cgImage
        switch mode {
        case .aspectFill, .tile:
            imageMaskLayer.contentsGravity = .resizeAspectFill
        case .aspectFit:
            imageMaskLayer.contentsGravity = .resizeAspect
        case .fill:
            imageMaskLayer.contentsGravity = .resize
        }
        CATransaction.commit()
    }
}
