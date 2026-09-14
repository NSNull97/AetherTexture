import UIKit

// MARK: - LensEffectView

/// AetherUI port of Telegram's `LensTransitionContainerEffectViewImpl`
/// (`ContextControllerActionsStackNode.swift`, lines 1448–1631). Provides the
/// lazily-created `UIVisualEffectView` whose `UIGlassEffect` corner radius /
/// size is animated along the keyframe arrays produced by
/// `LensTransitionContainer`'s SDF keyframe baker.
///
/// On iOS 26+ the effect uses native `UIGlassEffect` and `cornerConfiguration`
/// (also driving the `UICornerRadius` morph during `animateIn`). On older
/// systems the view degrades silently. Legacy never installs this renderer:
/// its content remains a normal child view and all lens-only effects are
/// disabled.
public final class LensEffectView: UIView, LensTransitionContainerEffectView, AetherAppearanceConsumer, LensTransitionAppearanceManagedEffectView {
    /// Compatibility accessor for clients that need the underlying effect
    /// view. Normal transition code deliberately avoids this accessor in
    /// Legacy so merely constructing a lens cannot allocate a hidden effect
    /// host. Direct access in Legacy returns an inert, detached effect view.
    public var glassView: UIVisualEffectView {
        if appliedAppearanceStyle.usesLiquidGlass {
            return installGlassRendererIfNeeded()
        }
        if let glassViewStorage {
            return glassViewStorage
        }
        let glassView = UIVisualEffectView()
        glassViewStorage = glassView
        return glassView
    }

    public let contentView: UIView?

    /// `nil` follows the application runtime. A non-`nil` value pins the
    /// source lens, except that an owning Legacy transition is always a hard
    /// safety gate and therefore wins over a Liquid source pin.
    public let appearanceStyle: AetherAppearanceStyle?

    private var isDarkAppearance: Bool = false
    private var glassViewStorage: UIVisualEffectView?
    private var owningAppearanceStyle: AetherAppearanceStyle?
    private var appliedAppearanceStyle: AetherAppearanceStyle

    // MARK: - Init

    public init(
        contentView: UIView?,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.contentView = contentView
        self.appearanceStyle = appearanceStyle
        self.appliedAppearanceStyle = appearanceStyle
            ?? AetherAppearance.runtimeCurrent.style

        super.init(frame: CGRect())

        if let contentView {
            addSubview(contentView)
        }
        AetherAppearanceConsumerRegistry.register(self)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Theme

    /// Equivalent of Telegram's `update(theme:)` — flips the `UIGlassEffect`
    /// style between regular/dark to match the surface beneath.
    public func updateAppearance(isDark: Bool) {
        self.isDarkAppearance = isDark
        guard appliedAppearanceStyle.usesLiquidGlass else {
            return
        }

        // Resolve the owner/local style before asking the effect factory for
        // a renderer. This is the important Legacy hard gate: the factory is
        // never reached while the resolved appearance is Legacy.
        installGlassRendererIfNeeded().effect = SystemGlassEffect.make(
            isDark: isDark,
            appearanceStyle: appliedAppearanceStyle
        )
    }

    // MARK: - Sized updates (transition-driven)

    public func updateSize(size: CGSize, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        guard appliedAppearanceStyle.usesLiquidGlass else { return }
        let glassView = installGlassRendererIfNeeded()
        transition.animateView {
            glassView.bounds.size = size
            glassView.center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            if #available(iOS 26.0, *) {
                glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: cornerRadius))
            }
        }
    }

    public func updateSize(size: CGSize, transition: ContainedViewLayoutTransition) {
        transition.setBounds(view: self, bounds: CGRect(origin: .zero, size: size))
        guard appliedAppearanceStyle.usesLiquidGlass else { return }
        let glassView = installGlassRendererIfNeeded()
        transition.setBounds(view: glassView, bounds: CGRect(origin: .zero, size: size))
        transition.setPosition(view: glassView, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
    }

    public func updatePosition(position: CGPoint, transition: ContainedViewLayoutTransition) {
        transition.setPosition(view: self, position: position)
    }

    // MARK: - Keyframed updates (drive the lens morph)

    public func updateSize(duration: Double, keyframes: [CGSize]) {
        let glassView = appliedAppearanceStyle.usesLiquidGlass
            ? installGlassRendererIfNeeded()
            : nil
        guard keyframes.count >= 2 else {
            if let last = keyframes.last {
                self.bounds.size = last
                glassView?.bounds.size = last
                glassView?.center = CGPoint(x: last.width * 0.5, y: last.height * 0.5)
            }
            return
        }
        // Start value
        self.bounds.size = keyframes[0]
        glassView?.bounds.size = keyframes[0]
        glassView?.center = CGPoint(x: keyframes[0].width * 0.5, y: keyframes[0].height * 0.5)

        let segmentCount = keyframes.count - 1
        let relativeStep = 1.0 / Double(segmentCount)

        var options: UIView.KeyframeAnimationOptions = [.calculationModeLinear]
        options.insert(UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveLinear.rawValue))
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0.0,
            options: options,
            animations: {
                for i in 0 ..< segmentCount {
                    let nextSize = keyframes[i + 1]
                    let relativeStartTime = Double(i) * relativeStep
                    let relativeDuration = (i == segmentCount - 1) ? (1.0 - relativeStartTime) : relativeStep
                    UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                        self.bounds.size = nextSize
                        glassView?.bounds.size = nextSize
                        glassView?.center = CGPoint(x: nextSize.width * 0.5, y: nextSize.height * 0.5)
                    }
                }
            },
            completion: nil
        )
    }

    public func updatePosition(duration: Double, keyframes: [CGPoint]) {
        guard keyframes.count >= 2 else {
            if let last = keyframes.last {
                self.center = last
            }
            return
        }
        self.center = keyframes[0]

        let segmentCount = keyframes.count - 1
        let relativeStep = 1.0 / Double(segmentCount)

        var options: UIView.KeyframeAnimationOptions = [.calculationModeLinear]
        options.insert(UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveLinear.rawValue))
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0.0,
            options: options,
            animations: {
                for i in 0 ..< segmentCount {
                    let nextPosition = keyframes[i + 1]
                    let relativeStartTime = Double(i) * relativeStep
                    let relativeDuration = (i == segmentCount - 1) ? (1.0 - relativeStartTime) : relativeStep
                    UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                        self.center = nextPosition
                    }
                }
            },
            completion: nil
        )
    }

    public func updateCornerRadius(duration: Double, keyframes: [CGFloat]) {
        guard #available(iOS 26.0, *) else { return }
        guard appliedAppearanceStyle.usesLiquidGlass else { return }
        let glassView = installGlassRendererIfNeeded()

        guard keyframes.count >= 2 else {
            if let last = keyframes.last {
                glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: last))
            }
            return
        }
        // Start value
        glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: keyframes[0]))

        let segmentCount = keyframes.count - 1
        let relativeStep = 1.0 / Double(segmentCount)

        var options: UIView.KeyframeAnimationOptions = [.calculationModeLinear]
        options.insert(UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveLinear.rawValue))
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0.0,
            options: options,
            animations: {
                for i in 0 ..< segmentCount {
                    let nextValue = keyframes[i + 1]
                    let relativeStartTime = Double(i) * relativeStep
                    let relativeDuration = (i == segmentCount - 1) ? (1.0 - relativeStartTime) : relativeStep
                    UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                        glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: nextValue))
                    }
                }
            },
            completion: nil
        )
    }

    public func setTransitionFraction(value: CGFloat, duration: Double) {
        guard appliedAppearanceStyle.usesLiquidGlass else {
            tearDownGlassRenderer()
            contentView?.alpha = 1.0
            return
        }

        let glassView = installGlassRendererIfNeeded()
        let fraction = max(0.0, min(1.0, value))
        let transition: ContainedViewLayoutTransition =
            duration == 0.0 ? .immediate : .animated(duration: duration, curve: .easeInOut)
        transition.setBlur(layer: glassView.contentView.layer, radius: (1.0 - fraction) * 4.0)
        transition.updateAlpha(view: glassView.contentView, alpha: fraction)
    }

    // MARK: - Appearance ownership

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        applyResolvedAppearance(runtimeStyle: appearance.style)
    }

    func aetherApplyOwningAppearanceStyle(_ style: AetherAppearanceStyle) {
        owningAppearanceStyle = style
        applyResolvedAppearance(runtimeStyle: AetherAppearance.runtimeCurrent.style)
    }

    private func applyResolvedAppearance(runtimeStyle: AetherAppearanceStyle) {
        let resolvedStyle = resolvedAppearanceStyle(runtimeStyle: runtimeStyle)
        let didChange = resolvedStyle != appliedAppearanceStyle
        appliedAppearanceStyle = resolvedStyle

        guard resolvedStyle.usesLiquidGlass else {
            tearDownGlassRenderer()
            return
        }

        // Stay lazy until the source lens is actually used. If a renderer
        // already exists, replace its effect so live Liquid generation/theme
        // changes cannot retain stale UIKit effect state.
        if didChange, glassViewStorage != nil {
            installGlassRendererIfNeeded().effect = SystemGlassEffect.make(
                isDark: isDarkAppearance,
                appearanceStyle: resolvedStyle
            )
        }
    }

    private func resolvedAppearanceStyle(runtimeStyle: AetherAppearanceStyle) -> AetherAppearanceStyle {
        // A Legacy pin at either level is restrictive: a Legacy container
        // must not be able to retain a Liquid source, and an explicitly
        // Legacy source must not be promoted by a Liquid owner.
        if appearanceStyle == .legacy || owningAppearanceStyle == .legacy {
            return .legacy
        }
        return appearanceStyle ?? owningAppearanceStyle ?? runtimeStyle
    }

    private func installGlassRendererIfNeeded() -> UIVisualEffectView {
        precondition(appliedAppearanceStyle.usesLiquidGlass)

        let glassView: UIVisualEffectView
        if let glassViewStorage {
            glassView = glassViewStorage
        } else {
            glassView = UIVisualEffectView()
            glassViewStorage = glassView
        }

        if glassView.superview !== self {
            glassView.frame = bounds
            glassView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            insertSubview(glassView, at: 0)
            if let contentView, contentView.superview === self {
                glassView.contentView.addSubview(contentView)
            }
        }
        if glassView.effect == nil {
            glassView.effect = SystemGlassEffect.make(
                isDark: isDarkAppearance,
                appearanceStyle: appliedAppearanceStyle
            )
        }
        return glassView
    }

    /// Fully releases renderer state. Clearing the effect and filters before
    /// detaching also makes externally-retained references inert after a
    /// live Liquid -> Legacy switch.
    private func tearDownGlassRenderer() {
        guard let glassView = glassViewStorage else { return }

        glassView.layer.removeAllAnimations()
        glassView.contentView.layer.removeAllAnimations()
        glassView.contentView.layer.filters = nil
        glassView.layer.filters = nil
        glassView.contentView.alpha = 1.0
        glassView.effect = nil

        if let contentView, contentView.superview === glassView.contentView {
            contentView.removeFromSuperview()
            addSubview(contentView)
        }
        glassView.removeFromSuperview()
        glassViewStorage = nil
    }

    // MARK: - Test hooks

    internal var appliedAppearanceStyleForTesting: AetherAppearanceStyle {
        appliedAppearanceStyle
    }

    internal var hasAllocatedGlassViewForTesting: Bool {
        glassViewStorage != nil
    }

    internal var glassViewForTesting: UIVisualEffectView? {
        glassViewStorage
    }

    internal var hasVisualEffectForTesting: Bool {
        glassViewStorage?.effect != nil
    }

    internal var hasRendererFiltersForTesting: Bool {
        guard let glassViewStorage else { return false }
        return glassViewStorage.layer.filters != nil
            || glassViewStorage.contentView.layer.filters != nil
    }
}
