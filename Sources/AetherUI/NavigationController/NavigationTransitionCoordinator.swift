import UIKit
import AsyncDisplayKit

// Direct port of Display framework `NavigationTransitionCoordinator` from
// submodules/Display/Source/NavigationTransitionCoordinator.swift
// adapted to pure UIKit.
//
// Motion follows `UINavigationController` on iOS 26/27 (see
// `AetherMotion.navigationStack`):
// - push/pop run as one spring on the render server, so a busy main thread
//   (the incoming screen laying out its first frames) cannot drop or bunch
//   frames, and the first visible frame starts from the resting position;
// - an interactive pop moves the page through a spring that follows the
//   finger, and on release the same page state (position and velocity) is
//   handed to a render-server spring toward the resolved edge.

enum NavigationTransitionDirection {
    case push
    case pop
}

private let navigationShadowWidth: CGFloat = 16.0
private let navigationStationaryPopVelocityTolerance: CGFloat = 140.0
/// Residual motion below this many points is invisible; the transition
/// completes there instead of waiting for the spring's numeric tail.
private let navigationSettleTolerance: CGFloat = 0.25

private func navigationTransitionPosition(_ value: CGFloat) -> CGFloat {
    return value
}

/// Exact damped-spring evolution of a displacement `u` (current − target)
/// and velocity `v` over `t` seconds.
struct NavigationSpringStep {
    let spring: AetherMotion.PhysicalSpring

    func advance(displacement u0: CGFloat, velocity v0: CGFloat, by t: CGFloat) -> (displacement: CGFloat, velocity: CGFloat) {
        guard t > 0.0 else {
            return (u0, v0)
        }
        let omega = 2.0 * .pi / CGFloat(max(0.001, spring.response))
        let zeta = spring.dampingRatio
        if abs(zeta - 1.0) < 1e-4 {
            let decay = exp(-omega * t)
            let c = v0 + omega * u0
            let u = (u0 + c * t) * decay
            let v = (c - omega * (u0 + c * t)) * decay
            return (u, v)
        } else if zeta < 1.0 {
            let omegaD = omega * sqrt(1.0 - zeta * zeta)
            let decay = exp(-zeta * omega * t)
            let a = u0
            let b = (v0 + zeta * omega * u0) / omegaD
            let cosT = cos(omegaD * t)
            let sinT = sin(omegaD * t)
            let u = decay * (a * cosT + b * sinT)
            let v = decay * ((b * omegaD - zeta * omega * a) * cosT - (a * omegaD + zeta * omega * b) * sinT)
            return (u, v)
        } else {
            let root = omega * sqrt(zeta * zeta - 1.0)
            let r1 = -zeta * omega + root
            let r2 = -zeta * omega - root
            let c2 = (v0 - r1 * u0) / (r2 - r1)
            let c1 = u0 - c2
            let e1 = exp(r1 * t)
            let e2 = exp(r2 * t)
            return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
        }
    }

    /// Time after which the motion stays within `tolerance` points.
    func settleDuration(distance: CGFloat, velocity: CGFloat, tolerance: CGFloat = navigationSettleTolerance) -> Double {
        guard abs(distance) > tolerance || abs(velocity) > 1.0 else {
            return 0.0
        }
        let step: CGFloat = 1.0 / 240.0
        var t: CGFloat = 0.0
        var lastOutside: CGFloat = 0.0
        while t < 2.0 {
            t += step
            let state = advance(displacement: distance, velocity: velocity, by: t)
            if abs(state.displacement) > tolerance {
                lastOutside = t
            }
        }
        return Double(lastOutside + step)
    }
}

private final class NavigationProgressDisplayLinkTarget: NSObject {
    var tick: ((CADisplayLink) -> Void)?

    @objc func handleDisplayLink(_ link: CADisplayLink) {
        tick?(link)
    }
}

private let navigationShadowImage: UIImage? = generateImage(CGSize(width: 16.0, height: 1.0), rotatedContext: { size, context in
    context.clear(CGRect(origin: .zero, size: size))
    context.setFillColor(UIColor.black.cgColor)
    context.setShadow(offset: .zero, blur: 16.0, color: UIColor(white: 0.0, alpha: 0.5).cgColor)
    context.fill(CGRect(origin: CGPoint(x: size.width, y: 0.0), size: CGSize(width: 16.0, height: 1.0)))
})

final class NavigationTransitionCoordinator {
    // MARK: - Public state

    /// 0 = start of transition, 1 = complete. For push, visually "1" means the
    /// new screen fully on-screen; for pop, "1" means the popped screen fully
    /// off-screen to the right. While a render-server spring is running this
    /// is its destination.
    private(set) var progress: CGFloat = 0.0

    let isInteractive: Bool
    let isFlat: Bool

    private(set) var animatingCompletion: Bool = false

    // MARK: - Internal

    private let container: UIView
    private let direction: NavigationTransitionDirection
    private let topView: UIView
    private let bottomView: UIView
    private let topBar: NavigationBarView?
    private let bottomBar: NavigationBarView?
    private let progressUpdated: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    private let motion = AetherMotion.navigationStack

    private let dimView: UIView
    private let shadowNode: ASImageNode

    private var restoreTopViewCornerState: (() -> Void)?
    private var requestedTopCornerRadius: CGFloat = 0
    private var requestedBottomCornerRadius: CGFloat?
    private let transitionCornerMask = CAShapeLayer()

    private var currentCompletion: (() -> Void)?

    // Interactive tracking: page progress and velocity (progress units/s)
    // following `trackingTarget` through `motion.tracking`.
    private var trackingTarget: CGFloat = 0.0
    private var trackingVelocity: CGFloat = 0.0
    private var trackingDisplayLink: CADisplayLink?
    private var trackingDisplayLinkTarget: NavigationProgressDisplayLinkTarget?
    private var trackingLastTimestamp: CFTimeInterval?

    // Render-server spring in flight.
    private var springGeneration: Int = 0
    private var springCompletion: (() -> Void)?

    private static let animationKey = "aether.navigation.stack"

    var completionTransition: ContainedViewLayoutTransition {
        return makeReleaseTransition(target: 1.0, velocity: 0.0)
    }

    static func nonInteractiveCompletionTransition(direction _: NavigationTransitionDirection) -> ContainedViewLayoutTransition {
        let spring = AetherMotion.navigationStack.transition
        let width = UIScreen.main.bounds.width
        return .animated(
            duration: NavigationSpringStep(spring: spring).settleDuration(distance: width, velocity: 0.0),
            curve: .customSpring(damping: spring.dampingRatio, initialVelocity: 0.0)
        )
    }

    func completionTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        guard isInteractive else {
            return Self.nonInteractiveCompletionTransition(direction: direction)
        }
        return makeReleaseTransition(target: 1.0, velocity: releaseVelocity(gestureVelocity: velocity))
    }

    var cancelTransition: ContainedViewLayoutTransition {
        return cancelTransition(velocity: 0.0)
    }

    func cancelTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        return makeReleaseTransition(target: 0.0, velocity: releaseVelocity(gestureVelocity: velocity))
    }

    /// UIKit's resolution of a released back swipe: a leftward motion
    /// cancels, a throw completes, otherwise the finger position decides.
    func shouldCompleteInteractivePop(progress proposedProgress: CGFloat? = nil, velocity: CGFloat) -> Bool {
        guard isInteractive, direction == .pop else {
            return progress >= 1.0
        }
        if velocity < -navigationStationaryPopVelocityTolerance {
            return false
        }
        if velocity >= motion.completionVelocity {
            return true
        }
        let effectiveProgress = proposedProgress ?? progress
        return effectiveProgress >= motion.completionProgress
    }

    // MARK: - Init

    /// - parameters:
    ///   - direction: `.push` or `.pop`.
    ///   - topView: the incoming controller's view on push, or the outgoing
    ///     (being dismissed) one on pop — i.e. the view that moves.
    ///   - bottomView: the stationary-ish view behind `topView` (it gets a
    ///     parallax translation unless `isFlat`).
    ///   - isInteractive: whether this was initiated by a pan gesture.
    ///   - isFlat: when true, no parallax — `bottomView` simply slides in sync.
    ///   - screenCornerRadius: supplied by the containing surface. The
    ///     controller's original corner state is restored at settlement.
    init(
        container: UIView,
        direction: NavigationTransitionDirection,
        topView: UIView,
        bottomView: UIView,
        topBar: NavigationBarView?,
        bottomBar: NavigationBarView?,
        isInteractive: Bool,
        isFlat: Bool = false,
        screenCornerRadius: CGFloat = 0.0,
        bottomCornerRadius: CGFloat? = nil,
        progressUpdated: ((CGFloat, ContainedViewLayoutTransition) -> Void)? = nil
    ) {
        self.container = container
        self.direction = direction
        self.topView = topView
        self.bottomView = bottomView
        self.topBar = topBar
        self.bottomBar = bottomBar
        self.isInteractive = isInteractive
        self.isFlat = isFlat
        self.progressUpdated = progressUpdated

        self.dimView = UIView()
        self.dimView.backgroundColor = .black
        self.dimView.alpha = 0.0
        self.dimView.isUserInteractionEnabled = false

        self.shadowNode = ASImageNode()
        self.shadowNode.image = navigationShadowImage
        self.shadowNode.contentMode = .scaleToFill
        self.shadowNode.view.alpha = 0.0

        // Z-order: bottomView is added first by the caller; we add dim + shadow
        // just below topView so the shadow falls on bottomView.
        if topView.superview == nil {
            container.addSubview(topView)
        }

        if !isFlat {
            container.insertSubview(dimView, belowSubview: topView)
            container.insertSubview(shadowNode.view, belowSubview: dimView)

            updateCornerRadii(top: screenCornerRadius, bottom: bottomCornerRadius)
        }

        dimView.frame = container.bounds
        setProgress(0.0, transition: .immediate, completion: {})
    }

    deinit {
        invalidateTrackingDisplayLink()
    }

    // MARK: - Corners

    func updateCornerRadii(top: CGFloat, bottom: CGFloat?) {
        requestedTopCornerRadius = top
        requestedBottomCornerRadius = bottom
        guard !isFlat else { return }
        let limit = max(0, min(container.bounds.width, container.bounds.height) / 2)
        let topRadius = max(0, min(top, limit))
        let bottomRadius = max(0, min(bottom ?? top, limit))
        guard topRadius > 0 || bottomRadius > 0 else {
            restoreTopViewCorners()
            return
        }
        if restoreTopViewCornerState == nil {
            let clipsToBounds = topView.clipsToBounds
            let radius = topView.layer.cornerRadius
            let maskedCorners = topView.layer.maskedCorners
            let curve = topView.layer.cornerCurve
            let mask = topView.layer.mask
            var restoreNativeConfiguration: (() -> Void)?
            if #available(iOS 26.0, *) {
                let configuration = topView.cornerConfiguration
                restoreNativeConfiguration = { [weak topView] in
                    topView?.cornerConfiguration = configuration
                }
            }
            restoreTopViewCornerState = { [weak topView] in
                guard let topView else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                restoreNativeConfiguration?()
                topView.layer.cornerCurve = curve
                topView.layer.maskedCorners = maskedCorners
                topView.layer.cornerRadius = radius
                topView.layer.mask = mask
                topView.clipsToBounds = clipsToBounds
                CATransaction.commit()
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topView.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner
        ]
        topView.layer.cornerCurve = .continuous
        topView.clipsToBounds = true
        if #available(iOS 26.0, *) {
            topView.cornerConfiguration = .uniformEdges(
                topRadius: .fixed(topRadius), bottomRadius: .fixed(bottomRadius)
            )
            topView.layer.cornerRadius = 0
            topView.layer.mask = nil
        } else if topRadius == bottomRadius {
            topView.layer.cornerRadius = topRadius
            topView.layer.mask = nil
        } else {
            topView.layer.cornerRadius = 0
            let size = container.bounds.size
            let path = CGMutablePath()
            path.move(to: CGPoint(x: topRadius, y: 0))
            path.addLine(to: CGPoint(x: size.width - topRadius, y: 0))
            path.addArc(center: CGPoint(x: size.width - topRadius, y: topRadius), radius: topRadius,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: size.width, y: size.height - bottomRadius))
            path.addArc(center: CGPoint(x: size.width - bottomRadius, y: size.height - bottomRadius), radius: bottomRadius,
                        startAngle: 0, endAngle: .pi / 2, clockwise: false)
            path.addLine(to: CGPoint(x: bottomRadius, y: size.height))
            path.addArc(center: CGPoint(x: bottomRadius, y: size.height - bottomRadius), radius: bottomRadius,
                        startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: topRadius))
            path.addArc(center: CGPoint(x: topRadius, y: topRadius), radius: topRadius,
                        startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
            path.closeSubpath()
            transitionCornerMask.frame = CGRect(origin: .zero, size: size)
            transitionCornerMask.path = path
            topView.layer.mask = transitionCornerMask
        }
        CATransaction.commit()
    }

    // MARK: - Progress

    /// Reapply the current motion to a resized surface without restarting its
    /// clock or changing gesture progress. A running render-server spring is
    /// additive, so it keeps its offset on top of the resized endpoint.
    func updateLayout() {
        updateCornerRadii(top: requestedTopCornerRadius, bottom: requestedBottomCornerRadius)
        updateContentProgress(progress, transition: .immediate, completion: {})
        progressUpdated?(progress, .immediate)
    }

    /// Places the pages at `progress` right away (or with `transition`).
    func updateProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        trackingVelocity = 0.0
        trackingTarget = progress
        setProgress(progress, transition: transition, completion: completion)
    }

    /// Interactive pop: the page follows `progress` (the finger) through the
    /// tracking spring on the display clock.
    func trackInteractiveProgress(_ progress: CGFloat) {
        guard !animatingCompletion else { return }
        trackingTarget = progress
        guard motion.tracking.response > 0.0 else {
            trackingVelocity = 0.0
            setProgress(progress, transition: .immediate, completion: {})
            return
        }
        startTrackingDisplayLinkIfNeeded()
    }

    private func setProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        self.progress = progress
        var framesWereApplied = false
        var completedSynchronously = false
        updateContentProgress(progress, transition: transition) {
            if framesWereApplied {
                completion()
            } else {
                completedSynchronously = true
            }
        }
        progressUpdated?(progress, transition)
        framesWereApplied = true
        if completedSynchronously {
            completion()
        }
    }

    private struct ContentFrames {
        let top: CGRect
        let bottom: CGRect
        let shadow: CGRect
        let shadowAlpha: CGFloat
        let dimAlpha: CGFloat
    }

    /// Maps `progress` (0 → 1) to the on-screen position of the transition:
    /// `position = 1 - progress` for `.push`, `position = progress` for `.pop`.
    private func contentFrames(for progress: CGFloat) -> ContentFrames {
        let position: CGFloat
        switch direction {
        case .push:
            position = 1.0 - progress
        case .pop:
            position = progress
        }

        let size = container.bounds.size
        let topFrame = CGRect(origin: CGPoint(x: navigationTransitionPosition(position * size.width), y: 0.0), size: size)
        let bottomFrame: CGRect
        if isFlat {
            bottomFrame = CGRect(origin: CGPoint(x: -navigationTransitionPosition((1.0 - position) * size.width), y: 0.0), size: size)
        } else {
            bottomFrame = CGRect(origin: CGPoint(x: (position - 1.0) * size.width * motion.parallax, y: 0.0), size: size)
        }
        let shadowFrame = CGRect(
            x: topFrame.minX - navigationShadowWidth,
            y: 0.0,
            width: navigationShadowWidth,
            height: size.height
        )
        let coverage = 1.0 - position
        return ContentFrames(
            top: topFrame,
            bottom: bottomFrame,
            shadow: shadowFrame,
            shadowAlpha: coverage * 0.9,
            dimAlpha: max(0.0, min(1.0, coverage)) * motion.dimming
        )
    }

    private func updateContentProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        let frames = contentFrames(for: progress)

        var canInvokeCompletion = false
        var hadEarlyCompletion = false
        transition.updateFrame(view: topView, frame: frames.top, completion: { _ in
            if canInvokeCompletion {
                completion()
            } else {
                hadEarlyCompletion = true
            }
        })
        canInvokeCompletion = true

        transition.updateFrame(view: bottomView, frame: frames.bottom)
        transition.updateFrame(view: shadowNode.view, frame: frames.shadow)
        transition.updateAlpha(view: shadowNode.view, alpha: frames.shadowAlpha)
        transition.updateFrame(view: dimView, frame: CGRect(origin: .zero, size: container.bounds.size))
        transition.updateAlpha(view: dimView, alpha: frames.dimAlpha)

        if hadEarlyCompletion {
            completion()
        }
    }

    // MARK: - Animation entry points

    /// Finish the transition. A non-interactive push/pop runs the transition
    /// spring from rest; a released swipe continues from the page's current
    /// position and velocity with the release spring.
    func animateCompletion(velocity: CGFloat = 0.0, completion: @escaping () -> Void) {
        animatingCompletion = true
        currentCompletion = completion
        let spring = isInteractive ? motion.release : motion.transition
        let initialVelocity = isInteractive ? releaseVelocity(gestureVelocity: velocity) : 0.0
        runSpring(to: 1.0, spring: spring, velocity: initialVelocity) { [weak self] in
            self?.finish()
        }
    }

    /// Abort the transition (e.g. interactive pan released without enough
    /// velocity/distance). Animates back to `progress = 0` and tears down.
    func animateCancel(velocity: CGFloat = 0.0, _ completion: @escaping () -> Void) {
        animatingCompletion = true
        currentCompletion = completion
        let spring = isInteractive ? motion.release : motion.transition
        let initialVelocity = isInteractive ? releaseVelocity(gestureVelocity: velocity) : 0.0
        runSpring(to: 0.0, spring: spring, velocity: initialVelocity) { [weak self] in
            guard let self else { return }
            // Remove the incoming view entirely — same controller just came
            // back to its original position.
            switch self.direction {
            case .push:
                self.topView.removeFromSuperview()
            case .pop:
                self.bottomView.removeFromSuperview()
            }
            self.cleanupOverlays()
            self.restoreTopViewCorners()
            let hook = self.currentCompletion
            self.currentCompletion = nil
            hook?()
        }
    }

    /// Instantly complete the transition without animation (used when the
    /// transition is being replaced mid-flight by a deeper one).
    func performCompletion(completion: @escaping () -> Void) {
        invalidateTrackingDisplayLink()
        cancelSpring()
        updateProgress(1.0, transition: .immediate, completion: { [weak self] in
            self?.finish()
            completion()
        })
    }

    /// Synchronously mark the transition as complete and tear down overlays.
    /// Used when the caller has already applied `progress = 1.0`.
    func complete() {
        invalidateTrackingDisplayLink()
        cancelSpring()
        animatingCompletion = true
        progress = 1.0
        finish()
    }

    // MARK: - Interactive tracking

    /// Page velocity handed to the release spring, in points per second.
    /// While tracking, the page's own spring velocity keeps the hand-off
    /// continuous; a throw faster than the page is carried over too.
    private func releaseVelocity(gestureVelocity: CGFloat) -> CGFloat {
        let width = max(1.0, container.bounds.width)
        let pageVelocity = trackingVelocity * width
        let signedGesture: CGFloat
        switch direction {
        case .pop:
            signedGesture = gestureVelocity
        case .push:
            signedGesture = -gestureVelocity
        }
        if signedGesture > 0.0 {
            return max(pageVelocity, signedGesture)
        } else if signedGesture < 0.0 {
            return min(pageVelocity, signedGesture)
        }
        return pageVelocity
    }

    private func makeReleaseTransition(target: CGFloat, velocity: CGFloat) -> ContainedViewLayoutTransition {
        let spring = isInteractive ? motion.release : motion.transition
        let width = max(1.0, container.bounds.width)
        let distance = (progress - target) * width
        let duration = NavigationSpringStep(spring: spring).settleDuration(distance: distance, velocity: velocity)
        let normalizedVelocity = abs(distance) > .ulpOfOne ? velocity / -distance : 0.0
        return .animated(
            duration: max(0.01, duration),
            curve: .customSpring(damping: spring.dampingRatio, initialVelocity: normalizedVelocity)
        )
    }

    private func startTrackingDisplayLinkIfNeeded() {
        guard trackingDisplayLink == nil else { return }
        let target = NavigationProgressDisplayLinkTarget()
        target.tick = { [weak self] link in
            self?.handleTrackingDisplayLink(link)
        }
        let link = CADisplayLink(target: target, selector: #selector(NavigationProgressDisplayLinkTarget.handleDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            let preferred = Float(preferredFramesPerSecond())
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: preferred, preferred: preferred)
        }
        trackingLastTimestamp = nil
        trackingDisplayLinkTarget = target
        trackingDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func handleTrackingDisplayLink(_ link: CADisplayLink) {
        // Advance to the time this frame is presented; the first frame of
        // the gesture moves by one frame of spring time.
        let frameTime = link.targetTimestamp
        let previous = trackingLastTimestamp ?? link.timestamp
        trackingLastTimestamp = frameTime
        let dt = CGFloat(max(0.0, min(0.1, frameTime - previous)))
        let state = NavigationSpringStep(spring: motion.tracking).advance(
            displacement: progress - trackingTarget,
            velocity: trackingVelocity,
            by: dt
        )
        trackingVelocity = state.velocity
        let next = trackingTarget + state.displacement
        setProgress(next, transition: .immediate, completion: {})
    }

    private func invalidateTrackingDisplayLink() {
        trackingDisplayLink?.invalidate()
        trackingDisplayLink = nil
        trackingDisplayLinkTarget = nil
        trackingLastTimestamp = nil
    }

    private func preferredFramesPerSecond() -> Int {
        let screenMaximum = container.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        return min(120, max(60, screenMaximum))
    }

    // MARK: - Render-server spring

    /// Moves every transition layer to `target` with one physical spring on
    /// the render server. Model values jump to the destination; additive
    /// animations carry the remaining offset, so layout changes during the
    /// settle land on the right endpoint.
    private func runSpring(to target: CGFloat, spring: AetherMotion.PhysicalSpring, velocity: CGFloat, completion: @escaping () -> Void) {
        invalidateTrackingDisplayLink()
        cancelSpring()

        let width = max(1.0, container.bounds.width)
        let from = contentFrames(for: progress)
        let to = contentFrames(for: target)
        let distance = (progress - target) * width
        let duration = NavigationSpringStep(spring: spring).settleDuration(distance: distance, velocity: velocity)
        // CASpringAnimation velocity is in units of the animated distance.
        let normalizedVelocity = abs(distance) > .ulpOfOne ? velocity / -distance : 0.0

        springGeneration += 1
        let generation = springGeneration
        springCompletion = completion

        var didSettle = false
        let settle: () -> Void = { [weak self] in
            guard !didSettle else { return }
            didSettle = true
            guard let self, self.springGeneration == generation, let completion = self.springCompletion else { return }
            self.springCompletion = nil
            completion()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Fires once the render server has played the spring. The animation
        // begins at the commit that carries it, so main-thread work done
        // before that commit (the incoming screen's first layout) delays
        // the start instead of skipping its first frames.
        CATransaction.setCompletionBlock(settle)

        progress = target
        trackingTarget = target
        trackingVelocity = 0.0
        updateContentProgress(target, transition: .immediate, completion: {})
        progressUpdated?(target, .immediate)

        var addedAnimation = false
        if duration > 0.0 {
            let add: (CALayer, String, CGFloat) -> Void = { layer, keyPath, delta in
                guard abs(delta) > 0.001 else { return }
                let animation = CASpringAnimation(keyPath: keyPath)
                animation.mass = 1.0
                animation.stiffness = spring.stiffness
                animation.damping = spring.damping
                animation.initialVelocity = normalizedVelocity
                animation.fromValue = NSNumber(value: Double(delta))
                animation.toValue = NSNumber(value: 0.0)
                animation.isAdditive = true
                animation.duration = duration
                animation.isRemovedOnCompletion = true
                animation.aetherPreferHighFrameRate()
                layer.add(animation, forKey: Self.animationKey + "." + keyPath)
                addedAnimation = true
            }
            add(topView.layer, "position.x", from.top.minX - to.top.minX)
            add(bottomView.layer, "position.x", from.bottom.minX - to.bottom.minX)
            if !isFlat {
                add(shadowNode.layer, "position.x", from.shadow.minX - to.shadow.minX)
                add(shadowNode.layer, "opacity", from.shadowAlpha - to.shadowAlpha)
                add(dimView.layer, "opacity", from.dimAlpha - to.dimAlpha)
            }
        }
        CATransaction.commit()

        if !addedAnimation {
            // Already at rest: still resolve on the next turn, like a running
            // spring, so callers finish handling the gesture event first.
            DispatchQueue.main.async(execute: settle)
        } else {
            // Layers outside a rendering window never report completion.
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25, execute: settle)
        }
    }

    private func cancelSpring() {
        springGeneration += 1
        springCompletion = nil
        for layer in [topView.layer, bottomView.layer, shadowNode.layer, dimView.layer] {
            layer.removeAnimation(forKey: Self.animationKey + ".position.x")
            layer.removeAnimation(forKey: Self.animationKey + ".opacity")
        }
    }

    // MARK: - Teardown

    private func finish() {
        invalidateTrackingDisplayLink()
        cleanupOverlays()
        restoreTopViewCorners()
        let hook = currentCompletion
        currentCompletion = nil
        hook?()
    }

    private func cleanupOverlays() {
        dimView.removeFromSuperview()
        shadowNode.view.removeFromSuperview()
    }

    private func restoreTopViewCorners() {
        restoreTopViewCornerState?()
        restoreTopViewCornerState = nil
    }
}
