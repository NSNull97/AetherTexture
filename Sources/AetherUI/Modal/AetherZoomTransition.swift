import UIKit

/// CallController implements this hook to synchronously prepare Texture
/// content before the source morph starts. AetherUI keeps the transition
/// independent from any app's rendering framework.
public protocol AetherZoomTransitionPreparable: AnyObject {
    func prepareForAetherZoomTransition()
}

/// A reusable source-to-view-controller zoom transition. It mirrors the
/// iOS 18 zoom principles while remaining available on older deployments: a
/// stable source frame, a live destination hierarchy, a continuously rounded
/// mask, and the same reverse geometry on dismissal.
public final class AetherZoomTransition: NSObject, UIViewControllerTransitioningDelegate {
    private let sourceView: UIView?
    private let sourceViewProvider: (() -> UIView?)?
    private let sourceFrameInWindow: CGRect?
    private let sourceSnapshotImage: UIImage?

    public init(
        sourceView: UIView,
        sourceViewProvider: (() -> UIView?)? = nil
    ) {
        self.sourceView = sourceView
        self.sourceViewProvider = sourceViewProvider
        self.sourceFrameInWindow = sourceView.window.map { sourceView.convert(sourceView.bounds, to: $0) }
        self.sourceSnapshotImage = Self.makeSnapshotImage(of: sourceView)
        super.init()
    }

    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        AetherZoomAnimator(
            direction: .presentation,
            sourceView: sourceView,
            sourceViewProvider: sourceViewProvider,
            sourceFrameInWindow: sourceFrameInWindow,
            sourceSnapshotImage: sourceSnapshotImage
        )
    }

    public func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        AetherZoomAnimator(
            direction: .dismissal,
            sourceView: sourceView,
            sourceViewProvider: sourceViewProvider,
            sourceFrameInWindow: sourceFrameInWindow,
            sourceSnapshotImage: sourceSnapshotImage
        )
    }

    public static let presentationDuration = AetherMotion.sourceModal.presentation.duration
    public static let dismissalDuration = AetherMotion.sourceModal.dismissal.duration

    public static func zoomMaskPath(in bounds: CGRect, radii: CGSize) -> CGPath {
        let radiusX = min(max(0, radii.width), bounds.width / 2)
        let radiusY = min(max(0, radii.height), bounds.height / 2)
        let minX = bounds.minX, minY = bounds.minY
        let maxX = bounds.maxX, maxY = bounds.maxY
        let control: CGFloat = 0.552_284_749_830_793_6
        let controlX = radiusX * control, controlY = radiusY * control
        let path = CGMutablePath()
        path.move(to: CGPoint(x: minX + radiusX, y: minY))
        path.addLine(to: CGPoint(x: maxX - radiusX, y: minY))
        path.addCurve(to: CGPoint(x: maxX, y: minY + radiusY),
                      control1: CGPoint(x: maxX - radiusX + controlX, y: minY),
                      control2: CGPoint(x: maxX, y: minY + radiusY - controlY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radiusY))
        path.addCurve(to: CGPoint(x: maxX - radiusX, y: maxY),
                      control1: CGPoint(x: maxX, y: maxY - radiusY + controlY),
                      control2: CGPoint(x: maxX - radiusX + controlX, y: maxY))
        path.addLine(to: CGPoint(x: minX + radiusX, y: maxY))
        path.addCurve(to: CGPoint(x: minX, y: maxY - radiusY),
                      control1: CGPoint(x: minX + radiusX - controlX, y: maxY),
                      control2: CGPoint(x: minX, y: maxY - radiusY + controlY))
        path.addLine(to: CGPoint(x: minX, y: minY + radiusY))
        path.addCurve(to: CGPoint(x: minX + radiusX, y: minY),
                      control1: CGPoint(x: minX, y: minY + radiusY - controlY),
                      control2: CGPoint(x: minX + radiusX - controlX, y: minY))
        path.closeSubpath()
        return path
    }

    private static func makeSnapshotImage(of view: UIView) -> UIImage? {
        guard !view.bounds.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            guard !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) else { return }
            view.layer.render(in: context.cgContext)
        }
    }
}

private final class AetherZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Direction {
        case presentation
        case dismissal
    }

    static let presentationDuration: TimeInterval = AetherMotion.sourceModal.presentation.duration
    static let dismissalDuration: TimeInterval = AetherMotion.sourceModal.dismissal.duration

    private let direction: Direction
    private let sourceView: UIView?
    private let sourceViewProvider: (() -> UIView?)?
    private let sourceFrameInWindow: CGRect?
    private let sourceSnapshotImage: UIImage?

    init(
        direction: Direction,
        sourceView: UIView?,
        sourceViewProvider: (() -> UIView?)? = nil,
        sourceFrameInWindow: CGRect? = nil,
        sourceSnapshotImage: UIImage? = nil
    ) {
        self.direction = direction
        self.sourceView = sourceView
        self.sourceViewProvider = sourceViewProvider
        self.sourceFrameInWindow = sourceFrameInWindow
        self.sourceSnapshotImage = sourceSnapshotImage
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        direction == .presentation ? Self.presentationDuration : Self.dismissalDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if UIAccessibility.isReduceMotionEnabled {
            animateReducedMotion(using: transitionContext)
            return
        }

        switch direction {
        case .presentation:
            animatePresentation(using: transitionContext)
        case .dismissal:
            animateDismissal(using: transitionContext)
        }
    }

    private func animatePresentation(using context: UIViewControllerContextTransitioning) {
        guard let toController = context.viewController(forKey: .to),
              let toView = context.view(forKey: .to) ?? toController.view else {
            context.completeTransition(false)
            return
        }

        let container = context.containerView
        let finalFrame = context.finalFrame(for: toController)
        toView.frame = finalFrame
        container.addSubview(toView)
        UIView.performWithoutAnimation {
            toView.setNeedsLayout()
            toView.layoutIfNeeded()
        }
        (toController as? AetherZoomTransitionPreparable)?.prepareForAetherZoomTransition()

        guard let sourceView = resolvedSourceView,
              let sourceFrame = sourceFrame(
                  for: sourceView,
                  in: container,
                  preferStoredFrame: true
              ) else {
            animateFallbackPresentation(toView: toView, context: context)
            return
        }

        let finalCenter = toView.center
        let originalMask = toView.layer.mask
        let scale = scaleTransform(from: finalFrame.size, to: sourceFrame.size)
        let sourceRadius = resolvedCornerRadius(for: sourceView)
        let mask = makeZoomMask(
            bounds: toView.bounds,
            sourceRadius: sourceRadius,
            sourceSize: sourceFrame.size,
            collapsedScale: scale
        )
        toView.layer.mask = mask.layer
        toView.transform = scale
        toView.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        toView.alpha = 0.38

        let fadeAnimator = UIViewPropertyAnimator(
            duration: 0.28,
            timingParameters: Self.revealTiming
        )
        fadeAnimator.addAnimations {
            toView.alpha = 1
        }
        let geometryAnimator = UIViewPropertyAnimator(
            duration: Self.presentationDuration,
            timingParameters: UISpringTimingParameters(
                dampingRatio: AetherMotion.sourceModal.presentation.dampingRatio,
                initialVelocity: CGVector(
                    dx: AetherMotion.sourceModal.presentation.initialVelocity,
                    dy: AetherMotion.sourceModal.presentation.initialVelocity
                )
            )
        )
        geometryAnimator.addAnimations {
            toView.transform = .identity
            toView.center = finalCenter
        }
        animateMask(
            mask,
            duration: Self.presentationDuration,
            direction: .presentation
        )
        geometryAnimator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            toView.layer.mask = originalMask
            toView.transform = .identity
            toView.center = finalCenter
            toView.alpha = 1
            if !completed {
                toView.removeFromSuperview()
            }
            context.completeTransition(completed)
        }

        fadeAnimator.startAnimation(afterDelay: 0.018)
        geometryAnimator.startAnimation()
    }

    private func animateDismissal(using context: UIViewControllerContextTransitioning) {
        guard let fromController = context.viewController(forKey: .from),
              let fromView = context.view(forKey: .from) ?? fromController.view else {
            context.completeTransition(false)
            return
        }

        let container = context.containerView
        if let toView = context.view(forKey: .to), toView.superview == nil {
            container.insertSubview(toView, belowSubview: fromView)
        }
        fromView.layoutIfNeeded()

        guard let sourceView = resolvedSourceView,
              let sourceFrame = sourceFrame(for: sourceView, in: container) else {
            animateFallbackDismissal(fromView: fromView, context: context)
            return
        }

        // Keep a stable visual endpoint even if the originating Texture row
        // was recycled while the call was active. The real source control is
        // used whenever it is still attached; this image is only an endpoint
        // fallback and is removed after the transition completes.
        let sourceGhost = makeSourceGhost(
            in: container,
            frame: sourceFrame,
            cornerRadius: resolvedCornerRadius(for: sourceView)
        )

        let fullFrame = fromView.frame
        let fullCenter = fromView.center
        let originalMask = fromView.layer.mask
        let scale = scaleTransform(from: fullFrame.size, to: sourceFrame.size)
        let mask = makeZoomMask(
            bounds: fromView.bounds,
            sourceRadius: resolvedCornerRadius(for: sourceView),
            sourceSize: sourceFrame.size,
            collapsedScale: scale,
            startsExpanded: true
        )
        fromView.layer.mask = mask.layer

        let fadeAnimator = UIViewPropertyAnimator(
            duration: 0.26,
            timingParameters: Self.hideTiming
        )
        fadeAnimator.addAnimations {
            fromView.alpha = 0
        }
        let geometryAnimator = UIViewPropertyAnimator(
            duration: Self.dismissalDuration,
            timingParameters: UISpringTimingParameters(
                dampingRatio: AetherMotion.sourceModal.dismissal.dampingRatio,
                initialVelocity: CGVector(
                    dx: AetherMotion.sourceModal.dismissal.initialVelocity,
                    dy: AetherMotion.sourceModal.dismissal.initialVelocity
                )
            )
        )
        geometryAnimator.addAnimations {
            fromView.transform = scale
            fromView.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        }
        animateMask(
            mask,
            duration: Self.dismissalDuration,
            direction: .dismissal
        )
        geometryAnimator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            fromView.layer.mask = originalMask
            fromView.transform = .identity
            fromView.center = fullCenter
            fromView.alpha = 1
            sourceGhost?.removeFromSuperview()
            if completed {
                fromView.removeFromSuperview()
            }
            context.completeTransition(completed)
        }

        // The live call UI remains legible through most of the collapse; the
        // source glyph only takes over once the mask is already near the button.
        fadeAnimator.startAnimation(afterDelay: Self.dismissalDuration * 0.44)
        geometryAnimator.startAnimation()
    }

    private func animateReducedMotion(using context: UIViewControllerContextTransitioning) {
        switch direction {
        case .presentation:
            guard let toController = context.viewController(forKey: .to),
                  let toView = context.view(forKey: .to) ?? toController.view else {
                context.completeTransition(false)
                return
            }
            toView.frame = context.finalFrame(for: toController)
            context.containerView.addSubview(toView)
            animateFallbackPresentation(toView: toView, context: context, duration: 0.20)
        case .dismissal:
            guard let fromView = context.view(forKey: .from) else {
                context.completeTransition(false)
                return
            }
            animateFallbackDismissal(fromView: fromView, context: context, duration: 0.18)
        }
    }

    private func animateFallbackPresentation(
        toView: UIView,
        context: UIViewControllerContextTransitioning,
        duration: TimeInterval = 0.30
    ) {
        toView.alpha = 0
        toView.transform = CGAffineTransform(scaleX: 0.965, y: 0.965)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            toView.alpha = 1
            toView.transform = .identity
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed {
                toView.removeFromSuperview()
            }
            context.completeTransition(completed)
        }
    }

    private func animateFallbackDismissal(
        fromView: UIView,
        context: UIViewControllerContextTransitioning,
        duration: TimeInterval = 0.24
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            fromView.alpha = 0
            fromView.transform = CGAffineTransform(scaleX: 0.975, y: 0.975)
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            fromView.alpha = completed ? 0 : 1
            fromView.transform = .identity
            context.completeTransition(completed)
        }
    }

    private var resolvedSourceView: UIView? {
        sourceViewProvider?() ?? sourceView
    }

    private func sourceFrame(
        for sourceView: UIView,
        in container: UIView,
        preferStoredFrame: Bool = false
    ) -> CGRect? {
        if preferStoredFrame,
           let storedFrame = storedSourceFrame(in: container) {
            return storedFrame
        }
        if sourceView.window != nil,
           !sourceView.isHidden,
           sourceView.bounds.width > 1,
           sourceView.bounds.height > 1 {
            let frame = sourceView.convert(sourceView.bounds, to: container)
            if frame.isFinite, frame.intersects(container.bounds.insetBy(dx: -8, dy: -8)) {
                return frame
            }
        }
        if let storedFrame = storedSourceFrame(in: container) {
            return storedFrame
        }
        return nil
    }

    private func storedSourceFrame(in container: UIView) -> CGRect? {
        guard let sourceFrameInWindow,
              let window = sourceView?.window ?? container.window else {
            return nil
        }
        let frame = container.convert(sourceFrameInWindow, from: window)
        return frame.isFinite && frame.width > 1 && frame.height > 1 ? frame : nil
    }

    private func makeSourceGhost(
        in container: UIView,
        frame: CGRect,
        cornerRadius: CGFloat
    ) -> UIView? {
        guard let sourceSnapshotImage else { return nil }
        let ghostView = AetherZoomSourceGhostView(image: sourceSnapshotImage)
        ghostView.frame = frame
        ghostView.layer.cornerRadius = min(
            cornerRadius,
            min(frame.width, frame.height) / 2
        )
        ghostView.clipsToBounds = true
        ghostView.alpha = 0
        container.addSubview(ghostView)
        UIView.animate(
            withDuration: Self.dismissalDuration * 0.45,
            delay: Self.dismissalDuration * 0.55,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            ghostView.alpha = 1
        }
        return ghostView
    }

    private struct ZoomMask {
        let layer: CAShapeLayer
        let expandedPath: CGPath
        let collapsedPath: CGPath
    }

    private func scaleTransform(from fullSize: CGSize, to sourceSize: CGSize) -> CGAffineTransform {
        let uniformScale = sourceSize.width > 0 && fullSize.width > 0
            ? sourceSize.width / fullSize.width
            : min(
                sourceSize.width / max(fullSize.width, 1),
                sourceSize.height / max(fullSize.height, 1)
            )
        return CGAffineTransform(
            scaleX: uniformScale,
            y: uniformScale
        )
    }

    private func makeZoomMask(
        bounds: CGRect,
        sourceRadius: CGFloat,
        sourceSize: CGSize,
        collapsedScale: CGAffineTransform,
        startsExpanded: Bool = false
    ) -> ZoomMask {
        let scaleX = max(abs(collapsedScale.a), 0.001)
        let scaleY = max(abs(collapsedScale.d), 0.001)
        // Keep the destination hierarchy uniformly scaled. A portrait call
        // screen must never be squeezed into a square source button. The
        // collapsed mask crops the extra height while the source frame grows
        // to the full screen, so every label and circular control preserves
        // its aspect ratio throughout the morph.
        let uniformScale = min(scaleX, scaleY)
        let collapsedWidth = sourceSize.width / max(uniformScale, 0.001)
        let collapsedHeight = sourceSize.height / max(uniformScale, 0.001)
        let collapsedBounds = CGRect(
            x: bounds.midX - collapsedWidth / 2,
            y: bounds.midY - collapsedHeight / 2,
            width: collapsedWidth,
            height: collapsedHeight
        ).intersection(bounds)
        let collapsedRadii = CGSize(
            width: min(collapsedBounds.width / 2, sourceRadius / max(uniformScale, 0.001)),
            height: min(collapsedBounds.height / 2, sourceRadius / max(uniformScale, 0.001))
        )
        let expandedPath = AetherZoomTransition.zoomMaskPath(in: bounds, radii: .zero)
        let collapsedPath = AetherZoomTransition.zoomMaskPath(in: collapsedBounds, radii: collapsedRadii)
        let layer = CAShapeLayer()
        layer.frame = bounds
        layer.path = startsExpanded ? expandedPath : collapsedPath
        layer.fillColor = UIColor.black.cgColor
        return ZoomMask(
            layer: layer,
            expandedPath: expandedPath,
            collapsedPath: collapsedPath
        )
    }

    private func animateMask(
        _ mask: ZoomMask,
        duration: TimeInterval,
        direction: Direction
    ) {
        let bounds = mask.layer.bounds
        let animation = CAKeyframeAnimation(keyPath: "path")
        switch direction {
        case .presentation:
            animation.values = [
                mask.collapsedPath,
                AetherZoomTransition.zoomMaskPath(in: bounds, radii: CGSize(width: 88, height: 118)),
                AetherZoomTransition.zoomMaskPath(in: bounds, radii: CGSize(width: 52, height: 52)),
                AetherZoomTransition.zoomMaskPath(in: bounds, radii: CGSize(width: 24, height: 24)),
                mask.expandedPath
            ]
            animation.keyTimes = [0, 0.20, 0.62, 0.88, 1]
            setPathWithoutImplicitAnimation(mask.expandedPath, on: mask.layer)
        case .dismissal:
            animation.values = [
                mask.expandedPath,
                AetherZoomTransition.zoomMaskPath(in: bounds, radii: CGSize(width: 24, height: 24)),
                AetherZoomTransition.zoomMaskPath(in: bounds, radii: CGSize(width: 52, height: 52)),
                AetherZoomTransition.zoomMaskPath(in: bounds, radii: CGSize(width: 88, height: 118)),
                mask.collapsedPath
            ]
            animation.keyTimes = [0, 0.18, 0.55, 0.82, 1]
            setPathWithoutImplicitAnimation(mask.collapsedPath, on: mask.layer)
        }
        animation.duration = duration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        mask.layer.add(animation, forKey: "callZoom.path")
    }

    private func setPathWithoutImplicitAnimation(_ path: CGPath, on layer: CAShapeLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.path = path
        CATransaction.commit()
    }

    private func resolvedCornerRadius(for view: UIView) -> CGFloat {
        let layer = view.layer.presentation() ?? view.layer
        let maximum = min(view.bounds.width, view.bounds.height) / 2
        return layer.cornerRadius > 0 ? min(layer.cornerRadius, maximum) : maximum
    }
}

private final class AetherZoomSourceGhostView: UIView {
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .scaleAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        image.draw(in: rect)
    }
}

private extension AetherZoomAnimator {
    static let revealTiming = UICubicTimingParameters(
        controlPoint1: CGPoint(x: 0.08, y: 0.72),
        controlPoint2: CGPoint(x: 0.12, y: 1.00)
    )

    static let hideTiming = UICubicTimingParameters(
        controlPoint1: CGPoint(x: 0.30, y: 0.00),
        controlPoint2: CGPoint(x: 0.86, y: 0.24)
    )
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
    }
}
