import UIKit
import CoreImage
import AsyncDisplayKit
import ObjectiveC.runtime

/// Transparent content rendered at a finite set of blur radii before animation.
/// Blur changes only select a prepared image; display-link callbacks never
/// capture a view or run a Core Image filter.
final class AetherMaterializationImageView: UIView {
    let imageSize: CGSize
    let maximumBlurRadius: CGFloat
    private let imageView = UIImageView()
    private let images: [UIImage]
    private let radii: [CGFloat]
    private let imagePadding: CGFloat
    private(set) var blurRadius: CGFloat = 0
    private var displayedIndex = -1

    init(image: UIImage, maximumBlurRadius: CGFloat) {
        let original = AetherContentMaterialization.normalizedImage(image)
        imageSize = original.size
        let maximumBlur = maximumBlurRadius.isFinite ? max(0, maximumBlurRadius) : 0
        self.maximumBlurRadius = maximumBlur
        // Preserve the outward Gaussian halo without changing the logical
        // content size or its alignment with the source view.
        let padding = ceil(maximumBlur * 3 * original.scale) / original.scale
        imagePadding = padding
        let padded = AetherContentMaterialization.paddedImage(original, inset: padding)
        let sampleCount = maximumBlur > 0 ? 17 : 1
        let preparedRadii: [CGFloat] = (0 ..< sampleCount).map { index in
            guard sampleCount > 1 else { return 0 }
            let t = CGFloat(index) / CGFloat(sampleCount - 1)
            // Fine spacing near sharp content makes the final settle gradual.
            return maximumBlur * t * t
        }
        radii = preparedRadii
        images = preparedRadii.map { radius in
            AetherContentMaterialization.blurredImage(padded, radius: radius)
        }
        super.init(frame: CGRect(origin: .zero, size: original.size))
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        imageView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        updateImageFrame()
        setBlurRadius(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateImageFrame()
    }

    private func updateImageFrame() {
        let scaleX = imageSize.width > 0 ? bounds.width / imageSize.width : 1
        let scaleY = imageSize.height > 0 ? bounds.height / imageSize.height : 1
        imageView.frame = bounds.insetBy(dx: -imagePadding * scaleX, dy: -imagePadding * scaleY)
    }

    func setBlurRadius(_ radius: CGFloat) {
        let resolved = radius.isFinite ? min(maximumBlurRadius, max(0, radius)) : 0
        blurRadius = resolved
        let index = radii.indices.min { abs(radii[$0] - resolved) < abs(radii[$1] - resolved) } ?? 0
        guard index != displayedIndex else { return }
        displayedIndex = index
        imageView.image = images[index]
    }

    var displayedImageForTesting: UIImage? { imageView.image }
    var sharpImageForTesting: UIImage? { images.first }
    var preparedImageCountForTesting: Int { images.count }
    var imageFrameForTesting: CGRect { imageView.frame }
    var imagePaddingForTesting: CGFloat { imagePadding }
}

private final class AetherMaterializationBlurCacheKey: NSObject {
    let image: CGImage
    let scale: CGFloat
    let radius: CGFloat

    init(image: CGImage, scale: CGFloat, radius: CGFloat) {
        self.image = image
        self.scale = scale
        self.radius = radius
        super.init()
    }

    override var hash: Int {
        var value = Hasher()
        value.combine(ObjectIdentifier(image))
        value.combine(scale)
        value.combine(radius)
        return value.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AetherMaterializationBlurCacheKey else { return false }
        return image === other.image && scale == other.scale && radius == other.radius
    }
}

private var aetherContentMaterializationAnimationKey: UInt8 = 0

/// Content-only materialization that works without private CAFilter APIs.
enum AetherContentMaterialization {
    private final class SnapshotView: UIView {}

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let blurCache: NSCache<AetherMaterializationBlurCacheKey, UIImage> = {
        let cache = NSCache<AetherMaterializationBlurCacheKey, UIImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        cache.countLimit = 128
        return cache
    }()

    static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up || image.cgImage == nil else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func paddedImage(_ image: UIImage, inset: CGFloat) -> UIImage {
        guard inset > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let size = CGSize(width: image.size.width + 2 * inset, height: image.size.height + 2 * inset)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: CGPoint(x: inset, y: inset), size: image.size))
        }
    }

    /// Radius is measured in points; Core Image receives the matching pixels.
    static func blurredImage(_ image: UIImage, radius: CGFloat) -> UIImage {
        guard radius.isFinite, radius > 0, let cgImage = image.cgImage else { return image }
        let key = AetherMaterializationBlurCacheKey(image: cgImage, scale: image.scale, radius: radius)
        if let cached = blurCache.object(forKey: key) { return cached }
        let input = CIImage(cgImage: cgImage)
        // Gaussian blur samples transparent pixels outside the image. Clamping
        // the input here would smear an edge glyph into an opaque dark border.
        let output = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * image.scale])
        guard let rendered = context.createCGImage(output, from: input.extent) else { return image }
        let result = UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
        blurCache.setObject(result, forKey: key, cost: rendered.bytesPerRow * rendered.height)
        return result
    }

    static func captureContent(of view: UIView, preservingRootOpacity: Bool = false) -> UIImage? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              view.bounds.width.isFinite, view.bounds.height.isFinite else { return nil }
        UIView.performWithoutAnimation {
            // UIKit wrappers may only assign their nested Texture frames in
            // layoutSubviews. Displaying nodes before that pass permanently
            // captures their old/empty bounds in every prepared blur frame.
            layoutContentForCapture(in: view)
            ensureTextureContentIsDisplayed(in: view)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? view.contentScaleFactor
        format.opaque = false
        let layer = view.layer
        let originalOpacity = layer.opacity
        let originalHidden = layer.isHidden
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Navigation materialization supplies its own opacity clock. A menu
        // lease instead must capture exactly the caption currently on screen,
        // including a disabled/custom-alpha source, before hiding its owner.
        layer.opacity = preservingRootOpacity ? originalOpacity : 1
        layer.isHidden = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            context.cgContext.translateBy(x: -view.bounds.minX, y: -view.bounds.minY)
            layer.render(in: context.cgContext)
        }
        layer.opacity = originalOpacity
        layer.isHidden = originalHidden
        CATransaction.commit()
        return image
    }

    private static func layoutContentForCapture(in view: UIView) {
        view.layoutIfNeeded()
        ASViewToDisplayNode(view)?.layoutIfNeeded()
        for subview in view.subviews {
            layoutContentForCapture(in: subview)
        }
    }

    private static func ensureTextureContentIsDisplayed(in view: UIView) {
        if let node = ASViewToDisplayNode(view) {
            node.recursivelyEnsureDisplaySynchronously(true)
        }
        for subview in view.subviews {
            ensureTextureContentIsDisplayed(in: subview)
        }
    }

    @discardableResult
    static func animate(
        view: UIView,
        samples: [AetherMotion.NavigationChromeMaterializationSample],
        duration: TimeInterval,
        targetAlpha: CGFloat,
        completion: (() -> Void)? = nil
    ) -> Animation? {
        cancel(view: view)
        let finalAlpha = targetAlpha.isFinite ? min(1, max(0, targetAlpha)) : 1
        guard duration.isFinite, duration > 0, !samples.isEmpty,
              let superview = view.superview, let image = captureContent(of: view) else {
            view.alpha = finalAlpha
            completion?()
            return nil
        }
        let animation = Animation(
            view: view,
            superview: superview,
            image: image,
            samples: samples,
            duration: duration,
            targetAlpha: finalAlpha,
            completion: completion
        )
        objc_setAssociatedObject(view, &aetherContentMaterializationAnimationKey, animation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        animation.start()
        return animation
    }

    static func cancel(view: UIView) {
        (objc_getAssociatedObject(view, &aetherContentMaterializationAnimationKey) as? Animation)?.cancel()
    }

    static func isAnimating(view: UIView) -> Bool {
        (objc_getAssociatedObject(view, &aetherContentMaterializationAnimationKey) as? Animation)?.isActive == true
    }

    /// Host layout must leave this disposable sibling with its animation owner.
    static func isSnapshotView(_ view: UIView) -> Bool {
        view is SnapshotView
    }

    /// The image actually prepared for this animation, without recapturing a
    /// hierarchy that may already have completed additional layout passes.
    static func capturedImageForTesting(of view: UIView) -> UIImage? {
        (objc_getAssociatedObject(view, &aetherContentMaterializationAnimationKey) as? Animation)?.capturedImageForTesting
    }

    final class Animation {
        // A retained, cancelled handle can deallocate after its replacement
        // starts. Per-animation keys keep that teardown from revealing the
        // source underneath the replacement's snapshot.
        private let suppressionKey = "aether.contentMaterialization.suppression.\(UUID().uuidString)"
        private weak var view: UIView?
        private weak var originalSuperview: UIView?
        private let snapshot: UIView
        private let content: AetherMaterializationImageView
        private let samples: [AetherMotion.NavigationChromeMaterializationSample]
        private let duration: TimeInterval
        private let targetAlpha: CGFloat
        private let opacityScale: CGFloat
        private var completion: (() -> Void)?
        private var displayLink: CADisplayLink?
        private var startTime: CFTimeInterval = 0
        private(set) var isActive = false

        fileprivate init(
            view: UIView,
            superview: UIView,
            image: UIImage,
            samples: [AetherMotion.NavigationChromeMaterializationSample],
            duration: TimeInterval,
            targetAlpha: CGFloat,
            completion: (() -> Void)?
        ) {
            self.view = view
            originalSuperview = superview
            self.samples = samples
            self.duration = duration
            self.targetAlpha = targetAlpha
            opacityScale = targetAlpha > 0 ? targetAlpha : view.alpha
            self.completion = completion
            snapshot = SnapshotView()
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            content = AetherMaterializationImageView(
                image: image,
                maximumBlurRadius: samples.map(\.blurRadius).max() ?? 0
            )
            snapshot.addSubview(content)
        }

        fileprivate func start() {
            guard let view, let originalSuperview else { return }
            isActive = true
            view.alpha = targetAlpha
            originalSuperview.insertSubview(snapshot, aboveSubview: view)
            // Keep the requested alpha in the model layer. Only our own
            // presentation animation hides the original under its proxy.
            let suppression = CABasicAnimation(keyPath: "opacity")
            suppression.fromValue = 0
            suppression.toValue = 0
            suppression.duration = duration
            suppression.fillMode = .both
            suppression.isRemovedOnCompletion = false
            view.layer.add(suppression, forKey: suppressionKey)
            startTime = CACurrentMediaTime()
            update(progress: 0)
            let link = CADisplayLink(target: DisplayLinkTarget(animation: self), selector: #selector(DisplayLinkTarget.tick(_:)))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        fileprivate func tick(_ link: CADisplayLink) {
            guard isActive else { return }
            guard let view, let originalSuperview,
                  view.superview === originalSuperview,
                  snapshot.superview === originalSuperview else {
                cancel()
                return
            }
            let elapsed = max(0, link.timestamp - startTime)
            update(progress: CGFloat(min(1, elapsed / duration)))
            if elapsed >= duration { finish(completed: true) }
        }

        private func update(progress: CGFloat) {
            guard let view else { return }
            let fractionalIndex = max(0, min(1, progress)) * CGFloat(samples.count - 1)
            let lowerIndex = Int(floor(fractionalIndex))
            let upperIndex = min(samples.count - 1, lowerIndex + 1)
            let t = fractionalIndex - CGFloat(lowerIndex)
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            let opacity = lower.opacity + (upper.opacity - lower.opacity) * t
            let blur = lower.blurRadius + (upper.blurRadius - lower.blurRadius) * t
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let sourceLayer = view.layer.presentation() ?? view.layer
            snapshot.layer.anchorPoint = sourceLayer.anchorPoint
            snapshot.bounds = sourceLayer.bounds
            snapshot.layer.position = sourceLayer.position
            snapshot.layer.transform = sourceLayer.transform
            snapshot.layer.zPosition = view.layer.zPosition
            content.frame = snapshot.bounds
            snapshot.alpha = max(0, min(1, opacity)) * opacityScale
            content.setBlurRadius(blur)
            CATransaction.commit()
        }

        func cancel() { finish(completed: false) }

        private func finish(completed: Bool) {
            guard isActive else { return }
            isActive = false
            displayLink?.invalidate()
            displayLink = nil
            snapshot.removeFromSuperview()
            if let view {
                view.alpha = targetAlpha
                view.layer.removeAnimation(forKey: suppressionKey)
                if objc_getAssociatedObject(view, &aetherContentMaterializationAnimationKey) as? Animation === self {
                    objc_setAssociatedObject(view, &aetherContentMaterializationAnimationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            }
            let completion = self.completion
            self.completion = nil
            if completed { completion?() }
        }

        deinit {
            displayLink?.invalidate()
            snapshot.removeFromSuperview()
            view?.layer.removeAnimation(forKey: suppressionKey)
        }

        var snapshotForTesting: UIView { snapshot }
        fileprivate var capturedImageForTesting: UIImage? { content.sharpImageForTesting }

        private final class DisplayLinkTarget: NSObject {
            weak var animation: Animation?
            init(animation: Animation) {
                self.animation = animation
                super.init()
            }
            @objc func tick(_ link: CADisplayLink) { animation?.tick(link) }
        }
    }
}
