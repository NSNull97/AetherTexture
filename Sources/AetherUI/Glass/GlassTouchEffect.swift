import UIKit

// MARK: - TouchEffect
// Direct port of Display framework `TouchEffect` from


final class TouchEffect {
    struct SpringParameters {
        var duration: TimeInterval
        var dampingRatio: CGFloat
        var initialVelocity: CGFloat
    }

    struct Parameters {
        var liftOn: SpringParameters
        var liftOff: SpringParameters
        var pressedSizeIncrease: CGFloat
        var maximumTranslation: CGFloat
        var movementHysteresis: CGFloat
        var cancellationInset: CGFloat
        var highlightAlpha: Float
        var highlightDiameter: CGFloat
        var highlightInDuration: TimeInterval
        var highlightOutDuration: TimeInterval

        init(profile: AetherMotion.Press = AetherMotion.standaloneButtonPress) {
            liftOn = SpringParameters(
                duration: profile.press.duration,
                dampingRatio: profile.press.dampingRatio,
                initialVelocity: profile.press.initialVelocity
            )
            liftOff = SpringParameters(
                duration: profile.release.duration,
                dampingRatio: profile.release.dampingRatio,
                initialVelocity: profile.release.initialVelocity
            )
            pressedSizeIncrease = profile.pressedSizeIncrease
            maximumTranslation = profile.maximumTranslation
            movementHysteresis = profile.movementHysteresis
            cancellationInset = profile.cancellationInset
            highlightAlpha = profile.highlightAlpha
            highlightDiameter = profile.highlightDiameter
            highlightInDuration = profile.highlightInDuration
            highlightOutDuration = profile.highlightOutDuration
        }
    }

    private struct State: Equatable {
        var isTracking: Bool
        var stretchVector: CGPoint
        var touchLocation: CGPoint?
    }

    private weak var view: UIView?
    private weak var highlightContainerView: UIView?
    private let reducesMotion: Bool
    static let transformAnimationKey = "aether.touchEffect.sublayerTransform"
    private static let highlightAnimationKey = "aether.touchEffect.highlightOpacity"

    private let radialHighlightLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .radial

        let baseGradientAlpha: CGFloat = 0.5
        let numSteps = 8
        let firstStep = 1
        let firstLocation = 0.5
        let colors = (0..<numSteps).map { i -> UIColor in
            if i < firstStep {
                return UIColor(white: 1.0, alpha: 1.0)
            } else {
                let step = CGFloat(i - firstStep) / CGFloat(numSteps - firstStep - 1)
                let value = 1.0 - bezierPoint(0.42, 0.0, 0.58, 1.0, step)
                return UIColor(white: 1.0, alpha: baseGradientAlpha * value)
            }
        }
        let locations = (0..<numSteps).map { i -> CGFloat in
            if i < firstStep {
                return 0.0
            } else {
                let step = CGFloat(i - firstStep) / CGFloat(numSteps - firstStep - 1)
                return firstLocation + (1.0 - firstLocation) * step
            }
        }

        layer.colors = colors.map(\.cgColor)
        layer.locations = locations.map { $0 as NSNumber }
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer.opacity = 0.0
        layer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
        ]
        return layer
    }()

    private var state = State(isTracking: false, stretchVector: .zero, touchLocation: nil)
    private var appliedState: State?

    var parameters = Parameters()

    init(view: UIView, highlightContainerView: UIView?, reducesMotion: Bool) {
        self.view = view
        self.highlightContainerView = highlightContainerView
        self.reducesMotion = reducesMotion

        if let highlightContainerView {
            highlightContainerView.layer.addSublayer(self.radialHighlightLayer)
        }
    }

    deinit {
        radialHighlightLayer.removeFromSuperlayer()
    }

    private func currentTransform(for state: State, view: UIView) -> CATransform3D {
        guard !reducesMotion else {
            return CATransform3DIdentity
        }
        let reference = highlightContainerView ?? view
        let w = max(1.0, reference.bounds.width)
        let h = max(1.0, reference.bounds.height)
        let aspect = w / h

        let baseScale = state.isTracking
            ? 1.0 + parameters.pressedSizeIncrease / min(w, h)
            : 1.0
        let baseScaleX = baseScale
        let baseScaleY = baseScale

        guard state.isTracking else {
            return CATransform3DScale(CATransform3DIdentity, baseScaleX, baseScaleY, 1.0)
        }

        let stretch = state.stretchVector
        let adjustedX = stretch.x / aspect
        let length = sqrt(pow(adjustedX, 2) + pow(stretch.y, 2))

        guard length != 0.0 else {
            return CATransform3DScale(CATransform3DIdentity, baseScaleX, baseScaleY, 1.0)
        }

        let normal = CGPoint(x: adjustedX / length, y: stretch.y / length)
        let k: CGFloat = -1.0 / ((length / h) / (5.0 * aspect) + 1.0) + 1.0
        let additionalMaxScale = (h + parameters.maximumTranslation * 0.67 / aspect) / h - 1.0
        let t = additionalMaxScale * k * aspect
        let maxOffset = parameters.maximumTranslation

        if abs(normal.x) > abs(normal.y) {
            let diff = abs(normal.x) - abs(normal.y)
            var transform = CATransform3DIdentity
            transform.m11 = baseScaleX * (1.0 + t * diff)
            transform.m22 = baseScaleY * (1.0 / (1.0 + t * diff))
            transform.m41 = normal.x * maxOffset * k
            transform.m42 = normal.y * maxOffset * k
            return transform
        } else {
            let diff = abs(normal.y) - abs(normal.x)
            var transform = CATransform3DIdentity
            transform.m11 = baseScaleX * (1.0 / (1.0 + t * diff))
            transform.m22 = baseScaleY * (1.0 + t * diff)
            transform.m41 = normal.x * maxOffset * k
            transform.m42 = normal.y * maxOffset * k
            return transform
        }
    }

    private func currentSpringParameters(from previous: State?, to state: State) -> SpringParameters {
        guard let previous, previous != state else {
            return state.isTracking ? parameters.liftOn : parameters.liftOff
        }
        if !previous.isTracking, state.isTracking {
            return parameters.liftOn
        } else {
            return parameters.liftOff
        }
    }

    private func updateRadialHighlight(animated: Bool) {
        guard highlightContainerView != nil else { return }

        let baseAlpha = parameters.highlightAlpha
        let targetOpacity: Float = state.isTracking ? baseAlpha : 0.0
        let size = CGSize(width: parameters.highlightDiameter, height: parameters.highlightDiameter)

        if let touch = state.touchLocation {
            radialHighlightLayer.bounds = CGRect(origin: .zero, size: size)
            radialHighlightLayer.position = touch
        }

        if animated, !reducesMotion {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = radialHighlightLayer.presentation()?.opacity ?? radialHighlightLayer.opacity
            radialHighlightLayer.opacity = targetOpacity
            animation.toValue = targetOpacity
            animation.duration = state.isTracking ? parameters.highlightInDuration : parameters.highlightOutDuration
            animation.timingFunction = CAMediaTimingFunction(name: state.isTracking ? .easeOut : .easeInEaseOut)
            animation.isRemovedOnCompletion = true
            radialHighlightLayer.add(animation, forKey: Self.highlightAnimationKey)
        } else {
            radialHighlightLayer.removeAnimation(forKey: Self.highlightAnimationKey)
            radialHighlightLayer.opacity = targetOpacity
        }
    }

    func applyCurrentTransform(animated: Bool = true) {
        guard let view else { return }
        let targetTransform = currentTransform(for: state, view: view)

        if !animated {
            view.layer.removeAnimation(forKey: Self.transformAnimationKey)
            view.layer.sublayerTransform = targetTransform
            updateRadialHighlight(animated: false)
            appliedState = state
            return
        }

        let spring = currentSpringParameters(from: appliedState, to: state)
        let animation = CASpringAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: view.layer.presentation()?.sublayerTransform ?? view.layer.sublayerTransform)
        animation.toValue = NSValue(caTransform3D: targetTransform)
        let dampingRatio = max(0.01, min(1.0, spring.dampingRatio))
        let angularFrequency = 4.0 / max(0.01, dampingRatio * spring.duration)
        animation.mass = 1.0
        animation.stiffness = angularFrequency * angularFrequency
        animation.damping = 2.0 * dampingRatio * angularFrequency
        animation.initialVelocity = spring.initialVelocity
        animation.duration = reducesMotion ? 0.0 : spring.duration
        animation.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.sublayerTransform = targetTransform
        CATransaction.commit()
        if animation.duration > 0.0 {
            view.layer.add(animation, forKey: Self.transformAnimationKey)
        } else {
            view.layer.removeAnimation(forKey: Self.transformAnimationKey)
        }
        updateRadialHighlight(animated: true)
        appliedState = state
    }

    func setParameters(_ parameters: Parameters, animated: Bool = false) {
        self.parameters = parameters
        applyCurrentTransform(animated: animated)
    }

    func setIsTracking(_ value: Bool, animated: Bool = true) {
        let next = State(
            isTracking: value,
            stretchVector: value ? state.stretchVector : .zero,
            touchLocation: state.touchLocation
        )
        guard state != next else { return }
        state = next
        applyCurrentTransform(animated: animated)
    }

    func setTouchLocation(_ location: CGPoint, animated: Bool = false) {
        let next = State(isTracking: state.isTracking, stretchVector: state.stretchVector, touchLocation: location)
        guard state != next else { return }
        state = next
        // Touch location only drives the radial highlight position —
        // the sublayer transform doesn't depend on it. Skipping the
        // full `applyCurrentTransform` path prevents every touchesMoved
        // event from removing the in-progress lift-on spring and
        // snapping the layer to its target transform in one frame.
        updateRadialHighlight(animated: animated)
        appliedState = state
    }

    func setStretchVector(_ vector: CGPoint, animated: Bool = false) {
        let next = State(isTracking: state.isTracking, stretchVector: vector, touchLocation: state.touchLocation)
        guard state != next else { return }
        state = next
        applyCurrentTransform(animated: animated)
    }

    /// Immediately returns the owned layer to an exact, animation-free rest
    /// state. Transition owners use this before they begin moving the same
    /// surface so a press-release spring cannot become an additional geometry
    /// animation on the first expansion frame.
    func forceRest() {
        state = State(
            isTracking: false,
            stretchVector: .zero,
            touchLocation: nil
        )
        applyCurrentTransform(animated: false)
    }
}

// MARK: - GlassHighlightGestureRecognizer
// Direct port of `GlassHighlightGestureRecognizer`.

public final class GlassHighlightGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var highlightContainerView: UIView?

    private var touchEffect: TouchEffect?
    private var releasingEffects: [TouchEffect] = []
    private var trackedTouch: UITouch?
    private var initialTouchLocation: CGPoint?
    private var isTouchInside = false
    weak var touchEffectView: UIView?

    public var motionProfile: AetherMotion.Press = AetherMotion.standaloneButtonPress {
        didSet {
            parameters = TouchEffect.Parameters(profile: motionProfile)
        }
    }

    var parameters = TouchEffect.Parameters() {
        didSet {
            touchEffect?.setParameters(parameters, animated: false)
        }
    }

    public override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        self.delegate = self
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
        self.requiresExclusiveTouchType = false
    }

    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public override func reset() {
        finishCurrentEffect()
        trackedTouch = nil
        initialTouchLocation = nil
        isTouchInside = false
        super.reset()
    }

    /// Cancels both the active press and any retained release springs without
    /// leaving a presentation/model transform behind. Normal touch endings
    /// still use the animated `finishCurrentEffect()` path; this seam is for a
    /// host that is about to hand the surface to a different transition.
    func resetVisualState() {
        touchEffect?.forceRest()
        for effect in releasingEffects {
            effect.forceRest()
        }
        touchEffect = nil
        releasingEffects.removeAll()
        trackedTouch = nil
        initialTouchLocation = nil
        isTouchInside = false
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil,
              let view = touchEffectView ?? self.view,
              let touch = touches.first else {
            if trackedTouch == nil {
                state = .failed
            }
            return
        }
        let location = touch.location(in: view)
        let effect = TouchEffect(
            view: view,
            highlightContainerView: highlightContainerView,
            reducesMotion: UIAccessibility.isReduceMotionEnabled
        )
        effect.setParameters(parameters, animated: false)
        if let highlightContainerView {
            effect.setTouchLocation(touch.location(in: highlightContainerView), animated: false)
        }
        effect.setStretchVector(.zero, animated: false)
        self.touchEffect = effect
        self.trackedTouch = touch
        self.initialTouchLocation = location
        self.isTouchInside = true
        effect.setIsTracking(true)
        state = .began
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        finishCurrentEffect()
        self.trackedTouch = nil
        state = .ended
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        finishCurrentEffect()
        self.trackedTouch = nil
        state = .cancelled
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touchEffect,
              let view = touchEffectView ?? self.view,
              let trackedTouch,
              touches.contains(trackedTouch),
              let initial = initialTouchLocation
        else { return }
        let location = trackedTouch.location(in: view)
        if let highlightContainerView {
            touchEffect.setTouchLocation(trackedTouch.location(in: highlightContainerView), animated: false)
        }

        let trackingBounds = view.bounds.insetBy(
            dx: -parameters.cancellationInset,
            dy: -parameters.cancellationInset
        )
        let nextIsInside = trackingBounds.contains(location)
        isTouchInside = nextIsInside

        // Visual stretch follows the finger until the touch actually ends,
        // even after it leaves the control's action hit region. UIControl
        // keeps responsibility for deciding touchUpInside vs touchUpOutside;
        // collapsing the material here made the elastic connection disappear
        // exactly when the finger pulled far enough to make it visible.
        let delta = CGPoint(x: location.x - initial.x, y: location.y - initial.y)
        let hysteresisSquared = parameters.movementHysteresis * parameters.movementHysteresis
        if delta.x * delta.x + delta.y * delta.y < hysteresisSquared { return }
        touchEffect.setStretchVector(delta, animated: false)
        if state == .began || state == .changed {
            state = .changed
        }
    }

    private func finishCurrentEffect() {
        guard let effect = touchEffect else { return }
        effect.setIsTracking(false)
        touchEffect = nil

        // Retain the effect until both the spring and the radial highlight
        // have reached rest. Deallocating it here removes the highlight layer
        // immediately and was the reason release feedback used to snap off.
        releasingEffects.append(effect)
        let releaseDuration = max(parameters.liftOff.duration, parameters.highlightOutDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDuration + 0.05) { [weak self] in
            self?.releasingEffects.removeAll { $0 === effect }
        }
    }
}
