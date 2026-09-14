import UIKit
import AsyncDisplayKit

public enum ContainedViewLayoutTransitionCurve {
    case linear
    case easeInOut
    case spring
    case customSpring(damping: CGFloat, initialVelocity: CGFloat)
    case custom(Float, Float, Float, Float)

    public static var slide: ContainedViewLayoutTransitionCurve {
        return .custom(0.33, 0.52, 0.25, 0.99)
    }

    public static var navigationEaseOut: ContainedViewLayoutTransitionCurve {
        return .custom(0.18, 0.82, 0.22, 1.0)
    }

    /// Softer geometry response for liquid navbar morphs. It keeps the fast
    /// iOS-style settle, but removes the initial kick of `navigationEaseOut`.
    public static var navigationFluidMorph: ContainedViewLayoutTransitionCurve {
        return .custom(0.20, 0.60, 0.24, 1.0)
    }

    public var viewAnimationOptions: UIView.AnimationOptions {
        switch self {
        case .linear:
            return .curveLinear
        case .easeInOut:
            return .curveEaseInOut
        case .spring, .customSpring:
            return .curveLinear
        case .custom:
            return .curveLinear
        }
    }

    public func mediaTimingFunction() -> CAMediaTimingFunction {
        switch self {
        case .linear:
            return CAMediaTimingFunction(name: .linear)
        case .easeInOut:
            return CAMediaTimingFunction(name: .easeInEaseOut)
        case .spring, .customSpring:
            return CAMediaTimingFunction(name: .linear)
        case let .custom(p1, p2, p3, p4):
            return CAMediaTimingFunction(controlPoints: p1, p2, p3, p4)
        }
    }

    /// Evaluates the visual progress of the curve. This is used by sampled
    /// material animations that must stay edge-locked to UIKit frame motion.
    internal func value(at progress: CGFloat) -> CGFloat {
        let progress = max(0.0, min(1.0, progress))
        switch self {
        case .linear:
            return progress
        case .easeInOut:
            return Self.cubicValue(
                at: progress,
                controlPoint1: CGPoint(x: 0.42, y: 0.0),
                controlPoint2: CGPoint(x: 0.58, y: 1.0)
            )
        case .spring, .customSpring:
            // UIKit does not expose the normalized value of its duration-
            // fitted spring. The navigation response is the closest stable
            // monotonic proxy for edge compensation; the visible elasticity
            // still comes from the independent material pulse.
            return Self.cubicValue(
                at: progress,
                controlPoint1: CGPoint(x: 0.18, y: 0.82),
                controlPoint2: CGPoint(x: 0.22, y: 1.0)
            )
        case let .custom(p1, p2, p3, p4):
            return Self.cubicValue(
                at: progress,
                controlPoint1: CGPoint(x: CGFloat(p1), y: CGFloat(p2)),
                controlPoint2: CGPoint(x: CGFloat(p3), y: CGFloat(p4))
            )
        }
    }

    private static func cubicValue(
        at input: CGFloat,
        controlPoint1: CGPoint,
        controlPoint2: CGPoint
    ) -> CGFloat {
        var lower: CGFloat = 0.0
        var upper: CGFloat = 1.0
        var parameter = input
        for _ in 0 ..< 10 {
            let estimatedX = cubicCoordinate(
                parameter,
                first: controlPoint1.x,
                second: controlPoint2.x
            )
            if estimatedX < input {
                lower = parameter
            } else {
                upper = parameter
            }
            parameter = (lower + upper) * 0.5
        }
        return cubicCoordinate(
            parameter,
            first: controlPoint1.y,
            second: controlPoint2.y
        )
    }

    private static func cubicCoordinate(_ t: CGFloat, first: CGFloat, second: CGFloat) -> CGFloat {
        let inverse = 1.0 - t
        return 3.0 * inverse * inverse * t * first
            + 3.0 * inverse * t * t * second
            + t * t * t
    }
}

public enum ContainedViewLayoutTransition {
    case immediate
    case animated(duration: Double, curve: ContainedViewLayoutTransitionCurve)

    public var isAnimated: Bool {
        switch self {
        case .immediate:
            return false
        case .animated:
            return true
        }
    }

    public var duration: Double {
        switch self {
        case .immediate:
            return 0.0
        case let .animated(duration, _):
            return duration
        }
    }

    public func updateFrame(view: UIView, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.frame = frame
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.frame = frame
            }, completion: completion)
        }
    }

    public func updateFrame(node: ASDisplayNode, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateFrame(view: node.view, frame: frame, completion: completion)
    }

    public func updateFrame(layer: CALayer, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.frame = frame
            completion?(true)
        case let .animated(duration, curve):
            let previousFrame = layer.frame
            layer.frame = frame
            layer.animateFrame(from: previousFrame, to: frame, duration: duration, timingFunction: curve.mediaTimingFunction(), completion: { finished in
                completion?(finished)
            })
        }
    }

    public func updateAlpha(view: UIView, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.alpha = alpha
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.alpha = alpha
            }, completion: completion)
        }
    }

    public func updateAlpha(node: ASDisplayNode, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateAlpha(view: node.view, alpha: alpha, completion: completion)
    }

    public func updateAlpha(layer: CALayer, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.opacity = Float(alpha)
            completion?(true)
        case let .animated(duration, _):
            let previousAlpha = layer.opacity
            layer.opacity = Float(alpha)
            layer.animate(from: NSNumber(value: previousAlpha), to: NSNumber(value: Float(alpha)), keyPath: "opacity", duration: duration, completion: { finished in
                completion?(finished)
            })
        }
    }

    public func updateTransform(view: UIView, transform: CGAffineTransform, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.transform = transform
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.transform = transform
            }, completion: completion)
        }
    }

    public func updateTransform(node: ASDisplayNode, transform: CGAffineTransform, completion: ((Bool) -> Void)? = nil) {
        updateTransform(view: node.view, transform: transform, completion: completion)
    }

    public func updateBounds(view: UIView, bounds: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.bounds = bounds
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.bounds = bounds
            }, completion: completion)
        }
    }

    public func updateBounds(node: ASDisplayNode, bounds: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateBounds(view: node.view, bounds: bounds, completion: completion)
    }

    public func updatePosition(view: UIView, position: CGPoint, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.center = position
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.center = position
            }, completion: completion)
        }
    }

    public func updatePosition(node: ASDisplayNode, position: CGPoint, completion: ((Bool) -> Void)? = nil) {
        updatePosition(view: node.view, position: position, completion: completion)
    }

    public func updateCornerRadius(layer: CALayer, cornerRadius: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.cornerRadius = cornerRadius
            completion?(true)
        case let .animated(duration, curve):
            // Keep shape changes on the exact same timing curve as the frame
            // transition. Reading the presentation value also preserves visual
            // continuity when a running morph is replaced by its settle phase.
            let previousCornerRadius = layer.presentation()?.cornerRadius
                ?? layer.cornerRadius
            layer.cornerRadius = cornerRadius
            layer.animate(
                from: NSNumber(value: Double(previousCornerRadius)),
                to: NSNumber(value: Double(cornerRadius)),
                keyPath: "cornerRadius",
                duration: duration,
                timingFunction: curve.mediaTimingFunction(),
                completion: { finished in
                    completion?(finished)
                }
            )
        }
    }

    // MARK: - Scroll inset updates
    //
    // UIKit doesn't animate `safeAreaInsets` propagation, and a scroll
    // view's `adjustedContentInset` is recomputed synchronously when its
    // safe area changes — meaning a scroll view configured with
    // `contentInsetAdjustmentBehavior = .automatic` will *snap* to the
    // new inset even if the chrome that caused it (nav bar growing,
    // search opening, tab-bar accessory appearing) is animating its
    // frame smoothly.
    //
    // The fix matches how Telegram-iOS handles this: opt the scroll out
    // of automatic adjustment (`contentInsetAdjustmentBehavior = .never`,
    // `automaticallyAdjustsScrollIndicatorInsets = false`) and animate
    // `contentInset` / `verticalScrollIndicatorInsets` directly inside
    // the same transition block as the chrome's frame change. Both are
    // honoured by `UIView.animate`, so the scroll content slides in
    // sync with the bar.
    //
    // Typical usage from a `ViewController` subclass:
    //
    //     override func containerLayoutUpdated(_ layout: ContainerViewLayout,
    //                                          transition: ContainedViewLayoutTransition) {
    //         super.containerLayoutUpdated(layout, transition: transition)
    //         let top = cleanNavigationHeight
    //         let bottom = max(layout.safeInsets.bottom, layout.additionalInsets.bottom)
    //         let insets = UIEdgeInsets(top: top,
    //                                   left: layout.safeInsets.left,
    //                                   bottom: bottom,
    //                                   right: layout.safeInsets.right)
    //         transition.updateContentInset(scrollView: tableView, insets: insets)
    //         transition.updateScrollIndicatorInsets(scrollView: tableView, insets: insets)
    //     }

    /// Animate `scrollView.contentInset` to `insets` along with the
    /// transition. Pair with `contentInsetAdjustmentBehavior = .never`
    /// so UIKit does not fight you over the value.
    ///
    /// Also compensates `contentOffset` to preserve the content's
    /// visible position — without this the scroll view would *appear*
    /// to jump when only the inset changed, since the on-screen pixel
    /// position of any item depends on `contentOffset.y + inset.top`.
    /// With `.automatic` UIKit performed this compensation internally;
    /// once you opt out, you have to do it yourself, otherwise:
    ///   • content stuck to the top (offset.y == -oldInset.top) stays
    ///     at the OLD top after the inset shrinks, leaving a visible
    ///     gap above it — the "scroll doesn't follow the chrome" bug.
    ///   • content scrolled to position N appears to jump by deltaTop
    ///     when the user wasn't even scrolling.
    /// Compensation is skipped while the user is actively touching the
    /// scroll view (`isTracking`/`isDragging`) so we don't yank content
    /// out from under their finger. It's also skipped when the scroll
    /// view has a non-zero scrollable area but content isn't otherwise
    /// being moved — `setContentOffset` inside an animation block lets
    /// UIKit interpolate it together with `contentInset`.
    public func updateContentInset(scrollView: UIScrollView, insets: UIEdgeInsets, completion: ((Bool) -> Void)? = nil) {
        let oldInsets = scrollView.contentInset
        if oldInsets == insets {
            completion?(true)
            return
        }

        let deltaTop = insets.top - oldInsets.top
        let shouldCompensate = !scrollView.isTracking && !scrollView.isDragging && deltaTop != 0
        let oldOffset = scrollView.contentOffset
        let newOffset = CGPoint(x: oldOffset.x, y: oldOffset.y - deltaTop)

        switch self {
        case .immediate:
            scrollView.contentInset = insets
            if shouldCompensate {
                scrollView.contentOffset = newOffset
            }
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                scrollView.contentInset = insets
                if shouldCompensate {
                    scrollView.contentOffset = newOffset
                }
            }, completion: completion)
        }
    }

    /// Animate the scroll-indicator insets (vertical + horizontal on
    /// iOS 13+, falling back to the legacy `scrollIndicatorInsets` on
    /// older systems) along with the transition. Pair with
    /// `automaticallyAdjustsScrollIndicatorInsets = false` so UIKit does
    /// not stomp the value.
    public func updateScrollIndicatorInsets(scrollView: UIScrollView, insets: UIEdgeInsets, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            if #available(iOS 11.1, *) {
                if scrollView.verticalScrollIndicatorInsets != insets {
                    scrollView.verticalScrollIndicatorInsets = insets
                }
                if scrollView.horizontalScrollIndicatorInsets != insets {
                    scrollView.horizontalScrollIndicatorInsets = insets
                }
            } else {
                if scrollView.scrollIndicatorInsets != insets {
                    scrollView.scrollIndicatorInsets = insets
                }
            }
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                if #available(iOS 11.1, *) {
                    scrollView.verticalScrollIndicatorInsets = insets
                    scrollView.horizontalScrollIndicatorInsets = insets
                } else {
                    scrollView.scrollIndicatorInsets = insets
                }
            }, completion: completion)
        }
    }

    /// Update a scroll view's raw `contentInset`, indicator insets, and
    /// optional `contentOffset` in one transition. This intentionally does not
    /// apply the top-inset compensation from `updateContentInset`; callers that
    /// manage list anchoring can provide the exact offset they want.
    public func updateScrollViewInsetsAndOffset(
        scrollView: UIScrollView,
        contentInset: UIEdgeInsets,
        scrollIndicatorInsets: UIEdgeInsets,
        contentOffset: CGPoint?,
        completion: ((Bool) -> Void)? = nil
    ) {
        let applyUpdates = {
            if scrollView.contentInset != contentInset {
                scrollView.contentInset = contentInset
            }
            if #available(iOS 11.1, *) {
                if scrollView.verticalScrollIndicatorInsets != scrollIndicatorInsets {
                    scrollView.verticalScrollIndicatorInsets = scrollIndicatorInsets
                }
                if scrollView.horizontalScrollIndicatorInsets != scrollIndicatorInsets {
                    scrollView.horizontalScrollIndicatorInsets = scrollIndicatorInsets
                }
            } else if scrollView.scrollIndicatorInsets != scrollIndicatorInsets {
                scrollView.scrollIndicatorInsets = scrollIndicatorInsets
            }
            if let contentOffset, scrollView.contentOffset != contentOffset {
                scrollView.contentOffset = contentOffset
            }
        }

        switch self {
        case .immediate:
            applyUpdates()
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: applyUpdates, completion: completion)
        }
    }

    private func animate(duration: Double, curve: ContainedViewLayoutTransitionCurve, animations: @escaping () -> Void, completion: ((Bool) -> Void)?) {
        let baseOptions: UIView.AnimationOptions = [.layoutSubviews, .beginFromCurrentState, .allowUserInteraction]
        switch curve {
        case .spring:
            UIView.animate(
                withDuration: duration,
                delay: 0.0,
                usingSpringWithDamping: AetherMotion.navigation.dampingRatio,
                initialSpringVelocity: AetherMotion.navigation.initialVelocity,
                options: baseOptions,
                animations: animations,
                completion: completion
            )
        case let .customSpring(damping, initialVelocity):
            UIView.animate(withDuration: duration, delay: 0.0, usingSpringWithDamping: damping, initialSpringVelocity: initialVelocity, options: baseOptions, animations: animations, completion: completion)
        case let .custom(p1, p2, p3, p4):
            let parameters = UICubicTimingParameters(
                controlPoint1: CGPoint(x: CGFloat(p1), y: CGFloat(p2)),
                controlPoint2: CGPoint(x: CGFloat(p3), y: CGFloat(p4))
            )
            let animator = UIViewPropertyAnimator(duration: duration, timingParameters: parameters)
            animator.addAnimations(animations)
            animator.addCompletion { position in
                completion?(position == .end)
            }
            UIViewPropertyAnimatorRetainer.start(animator)
        default:
            UIView.animate(withDuration: duration, delay: 0.0, options: [curve.viewAnimationOptions, baseOptions], animations: animations, completion: completion)
        }
    }

    // MARK: - Aliases that mirror ComponentTransition API surface.

    public func setFrame(view: UIView, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateFrame(view: view, frame: frame, completion: completion)
    }

    public func setFrame(node: ASDisplayNode, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateFrame(node: node, frame: frame, completion: completion)
    }

    public func setFrame(layer: CALayer, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateFrame(layer: layer, frame: frame, completion: completion)
    }

    public func setAlpha(view: UIView, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateAlpha(view: view, alpha: alpha, completion: completion)
    }

    public func setAlpha(node: ASDisplayNode, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateAlpha(node: node, alpha: alpha, completion: completion)
    }

    public func setAlpha(layer: CALayer, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateAlpha(layer: layer, alpha: alpha, completion: completion)
    }

    public func setBounds(view: UIView, bounds: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateBounds(view: view, bounds: bounds, completion: completion)
    }

    public func setBounds(node: ASDisplayNode, bounds: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateBounds(node: node, bounds: bounds, completion: completion)
    }

    public func setPosition(view: UIView, position: CGPoint, completion: ((Bool) -> Void)? = nil) {
        updatePosition(view: view, position: position, completion: completion)
    }

    public func setPosition(node: ASDisplayNode, position: CGPoint, completion: ((Bool) -> Void)? = nil) {
        updatePosition(node: node, position: position, completion: completion)
    }

    public func setCornerRadius(layer: CALayer, cornerRadius: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateCornerRadius(layer: layer, cornerRadius: cornerRadius, completion: completion)
    }

    public func setScale(view: UIView, scale: CGFloat, completion: ((Bool) -> Void)? = nil) {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        updateTransform(view: view, transform: transform, completion: completion)
    }

    public func setScale(node: ASDisplayNode, scale: CGFloat, completion: ((Bool) -> Void)? = nil) {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        updateTransform(node: node, transform: transform, completion: completion)
    }

    public func animateView(_ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            animations()
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: animations, completion: completion)
        }
    }

    public func animateAlpha(view: UIView, from: CGFloat, to: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.alpha = to
            completion?(true)
        case let .animated(duration, _):
            view.alpha = from
            self.animate(duration: duration, curve: .easeInOut, animations: {
                view.alpha = to
            }, completion: completion)
        }
    }

    public func animateAlpha(node: ASDisplayNode, from: CGFloat, to: CGFloat, completion: ((Bool) -> Void)? = nil) {
        animateAlpha(view: node.view, from: from, to: to, completion: completion)
    }

    public func animateScale(view: UIView, from: CGFloat, to: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.transform = CGAffineTransform(scaleX: to, y: to)
            completion?(true)
        case let .animated(duration, curve):
            view.transform = CGAffineTransform(scaleX: from, y: from)
            self.animate(duration: duration, curve: curve, animations: {
                view.transform = CGAffineTransform(scaleX: to, y: to)
            }, completion: completion)
        }
    }

    public func animateScale(node: ASDisplayNode, from: CGFloat, to: CGFloat, completion: ((Bool) -> Void)? = nil) {
        animateScale(view: node.view, from: from, to: to, completion: completion)
    }

    public func withAnimation(_ other: ContainedViewLayoutTransition) -> ContainedViewLayoutTransition {
        return other
    }

    public static var none: ContainedViewLayoutTransition { .immediate }

    // MARK: - setBlur (private CAFilter "gaussianBlur")
    //
    // Port of `ComponentTransition.setBlur`. Telegram's lens transition uses
    // this to fade between sharp and blurred contents for the source effect
    // view. Backed by the same private `CAFilter("gaussianBlur")` runtime API
    // already used elsewhere in AetherUI's glass pipeline.

    public func setBlur(layer: CALayer, radius: CGFloat, completion: ((Bool) -> Void)? = nil) {
        #if APPSTORE_SAFE
        // A CALayer has no public variable-blur filter. Safe builds keep the
        // transition contract and let the owning UIVisualEffectView provide
        // its system material instead of mutating private layer filters.
        completion?(true)
        #else
        var currentRadius: CGFloat = 0.0
        if let currentFilters = layer.filters {
            for filter in currentFilters {
                if let f = filter as? NSObject, f.description.contains(ObfuscatedSymbols.gaussianBlur) {
                    currentRadius = f.value(forKey: ObfuscatedSymbols.filterRadiusKey) as? CGFloat ?? 0.0
                }
            }
        }

        if currentRadius == radius {
            completion?(true)
            return
        }

        guard let blurFilter = CALayer.blur() else {
            completion?(true)
            return
        }
        blurFilter.setValue(radius as NSNumber, forKey: ObfuscatedSymbols.filterRadiusKey)
        layer.filters = [blurFilter]

        switch self {
        case .immediate:
            if radius <= 0.0 { layer.filters = nil }
            completion?(true)
        case let .animated(duration, _):
            let from = NSNumber(value: Float(currentRadius))
            let to = NSNumber(value: Float(radius))
            layer.animate(
                from: from, to: to,
                keyPath: ObfuscatedSymbols.keypath(
                    ObfuscatedSymbols.filters,
                    ObfuscatedSymbols.gaussianBlur,
                    ObfuscatedSymbols.filterRadiusKey
                ),
                duration: duration,
                completion: { [weak layer] flag in
                    if let layer, radius <= 0.0 { layer.filters = nil }
                    completion?(flag)
                }
            )
        }
        #endif
    }

    // MARK: - Additive animations (`animatePositionAdditive` /
    // `animateOffsetAdditive`). These add a CABasicAnimation with
    // `isAdditive = true` on top of the already-set model layer value, so
    // the layer animates FROM `position + offset` TO `position` without us
    // having to twiddle the model value first.

    public func animatePositionAdditive(layer: CALayer, offset: CGPoint, removeOnCompletion: Bool = true, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            completion?(true)
        case let .animated(duration, curve):
            let animation = CABasicAnimation(keyPath: "position")
            animation.isAdditive = true
            animation.fromValue = NSValue(cgPoint: offset)
            animation.toValue = NSValue(cgPoint: .zero)
            animation.duration = duration
            animation.timingFunction = curve.mediaTimingFunction()
            animation.fillMode = .both
            animation.isRemovedOnCompletion = removeOnCompletion
            if let completion {
                animation.delegate = NavTransitionAnimationDelegate(completion: completion)
            }
            animation.aetherPreferHighFrameRate()
            switch curve {
            case .spring, .customSpring:
                let spring = CASpringAnimation(keyPath: "position")
                spring.isAdditive = true
                spring.fromValue = NSValue(cgPoint: offset)
                spring.toValue = NSValue(cgPoint: .zero)
                spring.mass = 1.0
                spring.stiffness = 320.0
                spring.damping = 30.0
                spring.duration = spring.settlingDuration
                spring.fillMode = .both
                spring.isRemovedOnCompletion = removeOnCompletion
                if let completion {
                    spring.delegate = NavTransitionAnimationDelegate(completion: completion)
                }
                spring.aetherPreferHighFrameRate()
                layer.add(spring, forKey: "position-additive")
            default:
                layer.add(animation, forKey: "position-additive")
            }
        }
    }

    public func animateOffsetAdditive(layer: CALayer, offset: CGFloat, removeOnCompletion: Bool = true, completion: ((Bool) -> Void)? = nil) {
        animatePositionAdditive(layer: layer, offset: CGPoint(x: 0.0, y: offset), removeOnCompletion: removeOnCompletion, completion: completion)
    }
}

private enum UIViewPropertyAnimatorRetainer {
    private static var activeAnimators: [UIViewPropertyAnimator] = []

    static func start(_ animator: UIViewPropertyAnimator) {
        activeAnimators.append(animator)
        animator.addCompletion { [weak animator] _ in
            guard let animator else { return }
            activeAnimators.removeAll { $0 === animator }
        }
        animator.startAnimation()
    }
}

private final class NavTransitionAnimationDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion(flag)
    }
}
