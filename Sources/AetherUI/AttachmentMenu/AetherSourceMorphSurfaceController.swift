import UIKit

public protocol AetherSourceMorphSurfaceControllerDelegate: AnyObject {
    func sourceMorphSurfaceControllerDidLayout(_ controller: AetherSourceMorphSurfaceController)
    func sourceMorphSurfaceControllerWillDismiss(_ controller: AetherSourceMorphSurfaceController)
    func sourceMorphSurfaceControllerDidDismiss(_ controller: AetherSourceMorphSurfaceController)
    func sourceMorphSurfaceController(
        _ controller: AetherSourceMorphSurfaceController,
        didChangeState state: AetherSourceMorphSurfaceController.State
    )
    func sourceMorphSurfaceController(
        _ controller: AetherSourceMorphSurfaceController,
        didUpdateDismissProgress progress: CGFloat
    )
}

public extension AetherSourceMorphSurfaceControllerDelegate {
    func sourceMorphSurfaceControllerDidLayout(_ controller: AetherSourceMorphSurfaceController) {}
    func sourceMorphSurfaceControllerWillDismiss(_ controller: AetherSourceMorphSurfaceController) {}
    func sourceMorphSurfaceControllerDidDismiss(_ controller: AetherSourceMorphSurfaceController) {}
    func sourceMorphSurfaceController(
        _ controller: AetherSourceMorphSurfaceController,
        didChangeState state: AetherSourceMorphSurfaceController.State
    ) {}
    func sourceMorphSurfaceController(
        _ controller: AetherSourceMorphSurfaceController,
        didUpdateDismissProgress progress: CGFloat
    ) {}
}

public final class AetherSourceMorphSurfaceController: AetherAppearanceConsumer {
    public struct State: Hashable, RawRepresentable {
        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public struct Geometry {
        public let bounds: CGRect
        public let safeBounds: CGRect
        public let sourceFrame: CGRect
    }

    public struct StateConfiguration {
        public let cornerRadius: CGFloat
        public let frame: (Geometry) -> CGRect

        public init(cornerRadius: CGFloat, frame: @escaping (Geometry) -> CGRect) {
            self.cornerRadius = cornerRadius
            self.frame = frame
        }
    }

    public struct Configuration {
        public var glassTintColor: GlassBackgroundView.TintColor
        public var presentationDuration: TimeInterval
        public var dismissalDuration: TimeInterval
        public var stateChangeDuration: TimeInterval
        public var presentationDamping: CGFloat
        public var dismissalDamping: CGFloat
        public var stateChangeDamping: CGFloat
        public var initialSpringVelocity: CGFloat
        public var dismissDragDistance: CGFloat
        public var detentVelocityThreshold: CGFloat

        public init(
            glassTintColor: GlassBackgroundView.TintColor = .init(kind: .panel),
            presentationDuration: TimeInterval = AetherMotion.sourceModal.presentation.duration,
            dismissalDuration: TimeInterval = AetherMotion.sourceModal.dismissal.duration,
            stateChangeDuration: TimeInterval = AetherMotion.navigation.duration,
            presentationDamping: CGFloat = AetherMotion.sourceModal.presentation.dampingRatio,
            dismissalDamping: CGFloat = AetherMotion.sourceModal.dismissal.dampingRatio,
            stateChangeDamping: CGFloat = AetherMotion.navigation.dampingRatio,
            initialSpringVelocity: CGFloat = AetherMotion.sourceModal.presentation.initialVelocity,
            dismissDragDistance: CGFloat = 92.0,
            detentVelocityThreshold: CGFloat = 720.0
        ) {
            self.glassTintColor = glassTintColor
            self.presentationDuration = presentationDuration
            self.dismissalDuration = dismissalDuration
            self.stateChangeDuration = stateChangeDuration
            self.presentationDamping = presentationDamping
            self.dismissalDamping = dismissalDamping
            self.stateChangeDamping = stateChangeDamping
            self.initialSpringVelocity = initialSpringVelocity
            self.dismissDragDistance = dismissDragDistance
            self.detentVelocityThreshold = detentVelocityThreshold
        }
    }

    public weak var delegate: AetherSourceMorphSurfaceControllerDelegate?
    public weak var primaryScrollView: UIScrollView?
    public var interactiveStates: Set<State> = []
    public var shouldBeginInteractiveResize: (() -> Bool)?

    public let contentView = UIView()
    /// A non-`nil` style is pinned locally. `nil` follows the application
    /// appearance and participates in live renderer replacement.
    public let appearanceStyle: AetherAppearanceStyle?

    private let sourceFrame: CGRect
    private weak var sourceView: UIView?
    private let stateConfigurations: [State: StateConfiguration]
    private let configuration: Configuration
    private let surfaceView = UIView()
    private var glassView: GlassBackgroundView?
    private var legacyBlurView: UIVisualEffectView?
    private weak var hostView: UIView?
    private var currentState: State
    private var isPresented = false
    private var sourceOriginalAlpha: CGFloat?
    private var sourceOriginalInteractionEnabled: Bool?
    private var inheritedAppearance: AetherAppearance
    private var appliedAppearanceStyle: AetherAppearanceStyle
    private var presentedAppearanceStyle: AetherAppearanceStyle?
    private var animationGeneration: UInt = 0

    public init(
        sourceFrame: CGRect,
        sourceView: UIView?,
        initialState: State,
        stateConfigurations: [State: StateConfiguration],
        configuration: Configuration = Configuration(),
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        let inheritedAppearance = AetherAppearance.runtimeCurrent
        let resolvedAppearanceStyle = appearanceStyle ?? inheritedAppearance.style

        self.sourceFrame = sourceFrame
        self.sourceView = sourceView
        self.currentState = initialState
        self.stateConfigurations = stateConfigurations
        self.configuration = configuration
        self.appearanceStyle = appearanceStyle
        self.inheritedAppearance = inheritedAppearance
        self.appliedAppearanceStyle = resolvedAppearanceStyle

        surfaceView.backgroundColor = .clear
        surfaceView.clipsToBounds = false
        surfaceView.layer.masksToBounds = false
        surfaceView.alpha = 0

        contentView.backgroundColor = .clear
        rebuildRenderer(for: resolvedAppearanceStyle)
        AetherAppearanceConsumerRegistry.register(self)
    }

    public func install(in hostView: UIView) {
        self.hostView = hostView
        if surfaceView.superview !== hostView {
            hostView.addSubview(surfaceView)
        }
        layout()
    }

    public func layout() {
        guard let hostView else { return }
        let targetFrame = frame(for: currentState, in: hostView)
        apply(frame: targetFrame, cornerRadius: cornerRadius(for: currentState), transition: .immediate)
        delegate?.sourceMorphSurfaceControllerDidLayout(self)
    }

    public func present(animated: Bool, alongside: (() -> Void)? = nil) {
        guard !isPresented, let hostView else { return }
        let resolvedAppearanceStyle = appearanceStyle ?? inheritedAppearance.style
        if appliedAppearanceStyle != resolvedAppearanceStyle {
            rebuildRenderer(for: resolvedAppearanceStyle)
        }
        presentedAppearanceStyle = resolvedAppearanceStyle
        isPresented = true
        if surfaceView.superview !== hostView {
            hostView.addSubview(surfaceView)
        }
        let targetFrame = frame(for: currentState, in: hostView)
        hostView.bringSubviewToFront(surfaceView)

        let animations: () -> Void
        if resolvedAppearanceStyle.usesLiquidGlass {
            let initialFrame = resolvedSourceFrame(in: hostView)
            surfaceView.transform = .identity
            surfaceView.alpha = 1
            apply(
                frame: initialFrame,
                cornerRadius: min(initialFrame.width, initialFrame.height) / 2,
                transition: .immediate
            )

            if let sourceView {
                sourceOriginalAlpha = sourceView.alpha
                sourceOriginalInteractionEnabled = sourceView.isUserInteractionEnabled
                sourceView.alpha = 0.0
                sourceView.isUserInteractionEnabled = false
            }

            animations = {
                self.surfaceView.alpha = 1
                self.apply(
                    frame: targetFrame,
                    cornerRadius: self.cornerRadius(for: self.currentState),
                    transition: .immediate
                )
                alongside?()
            }
        } else {
            // Classic popups appear at their final geometry. They do not
            // lease, snapshot, hide or geometrically morph from the source.
            apply(
                frame: targetFrame,
                cornerRadius: cornerRadius(for: currentState),
                transition: .immediate
            )
            surfaceView.alpha = 0
            surfaceView.transform = Self.legacyClosedTransform
            animations = {
                self.surfaceView.alpha = 1
                self.surfaceView.transform = .identity
                alongside?()
            }
        }
        animate(
            animated: animated,
            duration: configuration.presentationDuration,
            damping: configuration.presentationDamping,
            initialVelocity: configuration.initialSpringVelocity,
            animations: animations
        )
    }

    public func dismiss(
        animated: Bool,
        alongside: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard isPresented || presentedAppearanceStyle != nil else {
            completion?()
            return
        }
        guard let hostView else {
            isPresented = false
            restoreSourceOwnership()
            presentedAppearanceStyle = nil
            completion?()
            return
        }
        delegate?.sourceMorphSurfaceControllerWillDismiss(self)
        let dismissalStyle = presentedAppearanceStyle ?? appliedAppearanceStyle
        let animations: () -> Void
        if dismissalStyle.usesLiquidGlass {
            let targetFrame = resolvedSourceFrame(in: hostView)
            animations = {
                self.surfaceView.alpha = 1
                self.apply(
                    frame: targetFrame,
                    cornerRadius: min(targetFrame.width, targetFrame.height) / 2,
                    transition: .immediate
                )
                alongside?()
            }
        } else {
            animations = {
                self.surfaceView.alpha = 0
                self.surfaceView.transform = Self.legacyClosedTransform
                alongside?()
            }
        }
        animate(
            animated: animated,
            duration: configuration.dismissalDuration,
            damping: configuration.dismissalDamping,
            initialVelocity: configuration.initialSpringVelocity,
            animations: animations,
            completion: { [weak self] in
                guard let self else { return }
                self.isPresented = false
                self.restoreSourceOwnership()
                let cleanupGeneration = self.animationGeneration
                let cleanup = { [weak self] in
                    guard let self,
                          self.animationGeneration == cleanupGeneration else { return }
                    self.surfaceView.removeFromSuperview()
                    self.surfaceView.alpha = 0
                    self.surfaceView.transform = .identity
                    self.presentedAppearanceStyle = nil
                    self.delegate?.sourceMorphSurfaceControllerDidDismiss(self)
                    completion?()
                }

                if dismissalStyle == .legacy {
                    cleanup()
                } else {
                    DispatchQueue.main.async(execute: cleanup)
                }
            }
        )
    }

    public func setState(
        _ state: State,
        animated: Bool,
        initialVelocity: CGFloat = 0,
        alongside: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let hostView else {
            currentState = state
            completion?()
            return
        }
        currentState = state
        let targetFrame = frame(for: state, in: hostView)
        let animations = {
            self.apply(
                frame: targetFrame,
                cornerRadius: self.cornerRadius(for: state),
                transition: .immediate
            )
            alongside?()
        }
        animate(
            animated: animated,
            duration: configuration.stateChangeDuration,
            damping: configuration.stateChangeDamping,
            initialVelocity: initialVelocity,
            animations: animations,
            completion: { [weak self] in
                guard let self else { return }
                self.delegate?.sourceMorphSurfaceController(self, didChangeState: state)
                completion?()
            }
        )
    }

    public func handleScrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isPresented, interactiveStates.contains(currentState) else { return }
        delegate?.sourceMorphSurfaceController(self, didUpdateDismissProgress: 0)
    }

    private func frame(for state: State, in hostView: UIView) -> CGRect {
        let sourceFrame = resolvedSourceFrame(in: hostView)
        let geometry = Geometry(
            bounds: hostView.bounds,
            safeBounds: hostView.bounds.inset(by: hostView.safeAreaInsets),
            sourceFrame: sourceFrame
        )
        return stateConfigurations[state]?.frame(geometry) ?? sourceFrame
    }

    private func cornerRadius(for state: State) -> CGFloat {
        stateConfigurations[state]?.cornerRadius ?? 0
    }

    private func resolvedSourceFrame(in hostView: UIView) -> CGRect {
        if let sourceView, sourceView.window != nil {
            return sourceView.convert(sourceView.bounds, to: hostView)
        }
        return sourceFrame
    }

    private func apply(frame: CGRect, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        surfaceView.frame = frame
        contentView.frame = surfaceView.bounds

        if let glassView {
            glassView.frame = surfaceView.bounds
            glassView.update(
                size: glassView.bounds.size,
                cornerRadius: cornerRadius,
                isDark: surfaceView.traitCollection.userInterfaceStyle == .dark,
                tintColor: configuration.glassTintColor,
                isInteractive: true,
                transition: transition
            )
        } else if let legacyBlurView {
            legacyBlurView.frame = surfaceView.bounds
            legacyBlurView.layer.cornerRadius = cornerRadius
            surfaceView.layer.shadowPath = UIBezierPath(
                roundedRect: surfaceView.bounds,
                cornerRadius: cornerRadius
            ).cgPath
        }
    }

    private func rebuildRenderer(for style: AetherAppearanceStyle) {
        contentView.removeFromSuperview()
        glassView?.removeFromSuperview()
        legacyBlurView?.removeFromSuperview()
        glassView = nil
        legacyBlurView = nil

        if style.usesLiquidGlass {
            let glassView = GlassBackgroundView(
                style: .regular,
                appearanceStyle: style
            )
            glassView.surfaceRole = .floatingSurface
            glassView.clipsToBounds = true
            glassView.layer.cornerCurve = .continuous
            surfaceView.layer.shadowOpacity = 0
            surfaceView.addSubview(glassView)
            glassView.contentView.addSubview(contentView)
            self.glassView = glassView
        } else {
            let blurView = UIVisualEffectView(
                effect: UIBlurEffect(style: .systemChromeMaterial)
            )
            blurView.clipsToBounds = true
            blurView.layer.cornerCurve = .continuous
            surfaceView.layer.shadowColor = UIColor.black.cgColor
            surfaceView.layer.shadowOpacity = 0.16
            surfaceView.layer.shadowRadius = 18
            surfaceView.layer.shadowOffset = CGSize(width: 0, height: 7)
            surfaceView.addSubview(blurView)
            blurView.contentView.addSubview(contentView)
            self.legacyBlurView = blurView
        }
        appliedAppearanceStyle = style
    }

    private func animate(
        animated: Bool,
        duration: TimeInterval,
        damping: CGFloat,
        initialVelocity: CGFloat,
        animations: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        animationGeneration &+= 1
        let generation = animationGeneration
        guard animated, duration > 0, !UIAccessibility.isReduceMotionEnabled else {
            animations()
            completion?()
            return
        }
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: animations,
            completion: { [weak self] _ in
                guard let self, self.animationGeneration == generation else { return }
                completion?()
            }
        )
    }

    private func cancelActiveAnimations() {
        animationGeneration &+= 1
        surfaceView.layer.removeAllAnimations()
        glassView?.layer.removeAllAnimations()
        legacyBlurView?.layer.removeAllAnimations()
    }

    private func cancelPresentationForAppearanceChange() {
        guard presentedAppearanceStyle != nil else { return }
        delegate?.sourceMorphSurfaceControllerWillDismiss(self)
        cancelActiveAnimations()
        isPresented = false
        restoreSourceOwnership()
        surfaceView.removeFromSuperview()
        surfaceView.alpha = 0
        surfaceView.transform = .identity
        presentedAppearanceStyle = nil
        delegate?.sourceMorphSurfaceControllerDidDismiss(self)
    }

    private func restoreSourceOwnership() {
        if let sourceView {
            sourceView.alpha = sourceOriginalAlpha ?? 1.0
            sourceView.isUserInteractionEnabled = sourceOriginalInteractionEnabled ?? true
        }
        sourceOriginalAlpha = nil
        sourceOriginalInteractionEnabled = nil
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated _: Bool) {
        inheritedAppearance = appearance
        let nextStyle = appearanceStyle ?? appearance.style
        if appearanceStyle == nil,
           let presentedAppearanceStyle,
           presentedAppearanceStyle != nextStyle {
            cancelPresentationForAppearanceChange()
        }
        guard appliedAppearanceStyle != nextStyle else { return }
        rebuildRenderer(for: nextStyle)
        if surfaceView.superview != nil, let hostView {
            let targetFrame = frame(for: currentState, in: hostView)
            apply(
                frame: targetFrame,
                cornerRadius: cornerRadius(for: currentState),
                transition: .immediate
            )
        }
    }

    private static let legacyClosedTransform = CGAffineTransform(
        translationX: 0,
        y: 8
    ).scaledBy(x: 0.96, y: 0.96)

    internal var resolvedAppearanceStyleForTesting: AetherAppearanceStyle {
        presentedAppearanceStyle ?? appearanceStyle ?? inheritedAppearance.style
    }

    internal var isPresentedForTesting: Bool {
        isPresented
    }

    internal var hasLiquidSurfaceForTesting: Bool {
        glassView != nil
    }

    internal var legacyBlurStyleForTesting: UIBlurEffect.Style? {
        legacyBlurView == nil ? nil : .systemChromeMaterial
    }

    internal var hasInstalledSurfaceForTesting: Bool {
        surfaceView.superview != nil
    }
}
