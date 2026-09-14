import UIKit
import AsyncDisplayKit

/// Direct mask used by the Legacy tab-bar chrome material. The progressive
/// field fills the reservation around a rounded cutout for the accessory's own
/// ultra-thin material, while the attached-bar fill stays opaque below it.
/// Non-safe builds group both effect views onto one backdrop identity, so the
/// two requested styles do not recursively sample one another.
private final class NavigationBackgroundAccessoryMaskView: UIView {
    private let progressiveView = UIView()
    private let progressiveLayer = CAGradientLayer()
    private let progressiveCutoutLayer = CAShapeLayer()
    private let attachedBarFillView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false

        let steps = 32
        progressiveLayer.colors = (0...steps).map { index in
            let progress = CGFloat(index) / CGFloat(steps)
            let alpha = 0.5 * (1.0 - cos(.pi * progress))
            return UIColor.white.withAlphaComponent(alpha).cgColor
        }
        progressiveLayer.locations = (0...steps).map { index in
            NSNumber(value: Double(index) / Double(steps))
        }
        progressiveView.isUserInteractionEnabled = false
        progressiveView.backgroundColor = .clear
        progressiveView.layer.addSublayer(progressiveLayer)
        progressiveCutoutLayer.fillColor = UIColor.white.cgColor
        progressiveCutoutLayer.fillRule = .evenOdd
        progressiveView.layer.mask = progressiveCutoutLayer
        addSubview(progressiveView)

        attachedBarFillView.isUserInteractionEnabled = false
        attachedBarFillView.backgroundColor = .white
        addSubview(attachedBarFillView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        size: CGSize,
        tabBarMinY: CGFloat,
        accessoryFrame: CGRect,
        accessoryCornerRadius: CGFloat
    ) {
        frame = CGRect(origin: .zero, size: size)
        let barMinY = max(0.0, min(size.height, tabBarMinY))

        progressiveView.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: size.width,
            height: barMinY
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressiveLayer.frame = progressiveView.bounds
        progressiveCutoutLayer.frame = progressiveView.bounds
        let cutoutPath = UIBezierPath(rect: progressiveView.bounds)
        let accessoryCutout = accessoryFrame.intersection(
            CGRect(origin: .zero, size: progressiveView.bounds.size)
        )
        if !accessoryCutout.isNull, !accessoryCutout.isEmpty {
            cutoutPath.append(
                UIBezierPath(
                    roundedRect: accessoryCutout,
                    cornerRadius: max(
                        0.0,
                        min(
                            accessoryCornerRadius,
                            min(
                                accessoryCutout.width,
                                accessoryCutout.height
                            ) / 2.0
                        )
                    )
                )
            )
        }
        cutoutPath.usesEvenOddFillRule = true
        progressiveCutoutLayer.path = cutoutPath.cgPath
        CATransaction.commit()
        attachedBarFillView.frame = CGRect(
            x: 0.0,
            y: barMinY,
            width: size.width,
            height: max(0.0, size.height - barMinY)
        )
    }

    func updateAttachedChromeAlpha(
        _ alpha: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        transition.updateAlpha(view: progressiveView, alpha: alpha)
        transition.updateAlpha(view: attachedBarFillView, alpha: alpha)
    }

    var attachedChromeAlpha: CGFloat {
        attachedBarFillView.alpha
    }
}

/// A view that provides a background with optional blur effect, matching NavigationBackgroundNode.
public final class NavigationBackgroundView: UIView {
    private struct BottomAccessoryMaskGeometry: Equatable {
        let size: CGSize
        let tabBarMinY: CGFloat
        let accessoryFrame: CGRect
        let accessoryCornerRadius: CGFloat
    }

    private var effectView: UIVisualEffectView?
    private let backgroundColorNode: ASDisplayNode
    private var bottomAccessoryEffectMaskView: NavigationBackgroundAccessoryMaskView?
    private var bottomAccessoryTintMaskView: NavigationBackgroundAccessoryMaskView?
    private var bottomAccessoryMaskGeometry: BottomAccessoryMaskGeometry?
    var backdropGroupingIdentifier: String? {
        didSet {
            guard backdropGroupingIdentifier != oldValue else { return }
            effectView?.aetherApplyBackdropGroupingIdentifier(
                backdropGroupingIdentifier
            )
        }
    }

    public var blurStyle: UIBlurEffect.Style {
        didSet {
            guard blurStyle.rawValue != oldValue.rawValue else { return }
            effectView?.removeFromSuperview()
            effectView = nil
            updateBackgroundBlur()
        }
    }

    public var enableBlur: Bool = true {
        didSet {
            if enableBlur != oldValue {
                updateBackgroundBlur()
            }
        }
    }

    private var _color: UIColor = .white

    /// Preserve theme/local background colour as a light material tint while
    /// keeping the underlying systemChromeMaterial visibly translucent.
    private var blurredColorAlpha: CGFloat {
        blurStyle == .systemChromeMaterial ? 0.12 : 0.8
    }

    public init(
        color: UIColor,
        enableBlur: Bool = true,
        blurStyle: UIBlurEffect.Style = .systemMaterial
    ) {
        self._color = color
        self.enableBlur = enableBlur
        self.blurStyle = blurStyle
        self.backgroundColorNode = ASDisplayNode()

        super.init(frame: .zero)

        self.backgroundColorNode.backgroundColor = color
        addSubview(self.backgroundColorNode.view)

        updateBackgroundBlur()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateColor(color: UIColor, enableBlur: Bool, transition: ContainedViewLayoutTransition) {
        self._color = color
        self.enableBlur = enableBlur
        self.backgroundColorNode.backgroundColor = color

        if !enableBlur || UIAccessibility.isReduceTransparencyEnabled {
            self.backgroundColorNode.alpha = 1.0
        } else {
            self.backgroundColorNode.alpha = blurredColorAlpha
        }
    }

    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, transition: ContainedViewLayoutTransition) {
        let frame = CGRect(origin: .zero, size: size)
        transition.updateFrame(node: self.backgroundColorNode, frame: frame)
        self.effectView?.frame = frame

        if cornerRadius > 0 {
            self.layer.cornerRadius = cornerRadius
            self.clipsToBounds = true
        } else {
            self.layer.cornerRadius = 0
            self.clipsToBounds = false
        }
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(view: self, alpha: alpha)
    }

    /// Extends the tab-bar material around the attached accessory. The rounded
    /// accessory cutout is filled by its own ultra-thin effect view. Masks are
    /// applied directly to effect/tint views because masking their common
    /// ancestor can invalidate UIKit's backdrop hierarchy.
    func updateBottomAccessoryMaterialMask(
        size: CGSize,
        tabBarMinY: CGFloat,
        accessoryFrame: CGRect,
        accessoryCornerRadius: CGFloat,
        attachedChromeAlpha: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        let effectMask = bottomAccessoryEffectMaskView
            ?? NavigationBackgroundAccessoryMaskView()
        let tintMask = bottomAccessoryTintMaskView
            ?? NavigationBackgroundAccessoryMaskView()
        bottomAccessoryEffectMaskView = effectMask
        bottomAccessoryTintMaskView = tintMask

        let geometry = BottomAccessoryMaskGeometry(
            size: size,
            tabBarMinY: tabBarMinY,
            accessoryFrame: accessoryFrame,
            accessoryCornerRadius: accessoryCornerRadius
        )
        let geometryChanged = bottomAccessoryMaskGeometry != geometry
        if geometryChanged {
            bottomAccessoryMaskGeometry = geometry
            effectMask.update(
                size: size,
                tabBarMinY: tabBarMinY,
                accessoryFrame: accessoryFrame,
                accessoryCornerRadius: accessoryCornerRadius
            )
            tintMask.update(
                size: size,
                tabBarMinY: tabBarMinY,
                accessoryFrame: accessoryFrame,
                accessoryCornerRadius: accessoryCornerRadius
            )
        }
        effectMask.updateAttachedChromeAlpha(
            attachedChromeAlpha,
            transition: transition
        )
        tintMask.updateAttachedChromeAlpha(
            attachedChromeAlpha,
            transition: transition
        )

        // UIKit caches visual-effect mask geometry internally. Reattach only
        // after a real resize/reconfiguration (or effect recreation), not on
        // every tab-bar layout pass.
        if geometryChanged || effectView?.mask !== effectMask {
            effectView?.mask = nil
            effectView?.mask = effectMask
        }
        if geometryChanged || backgroundColorNode.view.mask !== tintMask {
            backgroundColorNode.view.mask = nil
            backgroundColorNode.view.mask = tintMask
        }
    }

    func updateBottomAccessoryAttachedChromeAlpha(
        _ alpha: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        bottomAccessoryEffectMaskView?.updateAttachedChromeAlpha(
            alpha,
            transition: transition
        )
        bottomAccessoryTintMaskView?.updateAttachedChromeAlpha(
            alpha,
            transition: transition
        )
    }

    func clearBottomAccessoryMaterialMask() {
        effectView?.mask = nil
        backgroundColorNode.view.mask = nil
        bottomAccessoryEffectMaskView = nil
        bottomAccessoryTintMaskView = nil
        bottomAccessoryMaskGeometry = nil
    }

    func refreshReduceTransparencyStatus() {
        updateBackgroundBlur()
    }

    /// Creates a vibrancy effect paired with the exact public blur effect that
    /// currently renders this background. Callers layer the returned effect on
    /// top of this view and place only the content that should be vibrant in
    /// the effect view's `contentView`.
    ///
    /// Returning `nil` while blur is unavailable (including Reduce
    /// Transparency) keeps those callers on their ordinary semantic-color
    /// fallback instead of installing an orphaned vibrancy renderer.
    func makeVibrancyEffect(
        style: UIVibrancyEffectStyle
    ) -> UIVibrancyEffect? {
        guard enableBlur,
              !UIAccessibility.isReduceTransparencyEnabled,
              let blurEffect = effectView?.effect as? UIBlurEffect else {
            return nil
        }
        return UIVibrancyEffect(
            blurEffect: blurEffect,
            style: style
        )
    }

    private func updateBackgroundBlur() {
        if UIAccessibility.isReduceTransparencyEnabled {
            self.effectView?.removeFromSuperview()
            self.effectView = nil
            self.backgroundColorNode.alpha = 1.0
            return
        }

        if enableBlur {
            if self.effectView == nil {
                let effect = UIBlurEffect(style: blurStyle)
                let effectView = UIVisualEffectView(effect: effect)
                effectView.frame = bounds
                effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                effectView.mask = bottomAccessoryEffectMaskView
                effectView.aetherApplyBackdropGroupingIdentifier(
                    backdropGroupingIdentifier
                )
                insertSubview(effectView, at: 0)
                self.effectView = effectView
            }
            self.backgroundColorNode.alpha = blurredColorAlpha
        } else {
            self.effectView?.removeFromSuperview()
            self.effectView = nil
            self.backgroundColorNode.alpha = 1.0
        }
    }

    internal var backdropGroupingIdentifierForTesting: String? {
        effectView?.aetherBackdropGroupingIdentifier
    }

    #if DEBUG
    internal var usesPublicBlurEffectForTesting: Bool {
        effectView?.effect is UIBlurEffect
    }

    internal var backgroundTintAlphaForTesting: CGFloat {
        backgroundColorNode.alpha
    }

    internal var bottomAccessoryMaterialMaskFrameForTesting: CGRect? {
        effectView?.mask?.frame ?? backgroundColorNode.view.mask?.frame
    }

    internal var bottomAccessoryMaterialCutoutFrameForTesting: CGRect? {
        bottomAccessoryMaskGeometry?.accessoryFrame
    }

    internal var bottomAccessoryAttachedChromeAlphaForTesting: CGFloat? {
        bottomAccessoryEffectMaskView?.attachedChromeAlpha
            ?? bottomAccessoryTintMaskView?.attachedChromeAlpha
    }

    #endif

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.backgroundColorNode.frame = bounds
        self.effectView?.frame = bounds
        self.effectView?.aetherApplyBackdropGroupingIdentifier(
            backdropGroupingIdentifier
        )
    }
}
