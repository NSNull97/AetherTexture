import UIKit

public final class LegacyGlassBackdropView: UIView {
    public enum Style: Equatable { case normal, clear }

    private let visualEffectView: VisualEffectView?
    let experimentalView: ExperimentalGlassView?
    private var cornerRadius: CGFloat = 0
    private(set) var experimentalInteractionEnabled = false
    var hasBackdropLayer: Bool { false }

    public override init(frame: CGRect) {
        switch AetherGlassConfig.current.legacyBlurBackend {
        case .experimentalGlass:
            let glass = ExperimentalGlassView(.regular)
            experimentalView = glass
            visualEffectView = glass == nil ? VisualEffectView() : nil
            glass?.edgeRefractionBoost = 1.65
        case let .visualEffectView(blurRadius, tintColor, tintColorAlpha, saturation):
            experimentalView = nil
            let view = VisualEffectView()
            view.style = .customBlur
            view.colorTint = tintColor
            view.colorTintAlpha = tintColorAlpha
            view.blurRadius = blurRadius
            view.saturation = saturation
            view.scale = 1
            visualEffectView = view
        }
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerCurve = .continuous
        if let view = (experimentalView as UIView?) ?? visualEffectView {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(size: CGSize, cornerRadius: CGFloat, style: Style,
                transition: ContainedViewLayoutTransition) {
        self.cornerRadius = cornerRadius
        transition.updateCornerRadius(layer: layer, cornerRadius: cornerRadius)
        if let glass = experimentalView {
            transition.updateFrame(view: glass, frame: CGRect(origin: .zero, size: size))
            transition.updateCornerRadius(layer: glass.layer, cornerRadius: cornerRadius)
        }
    }

    func updateMaterial(owner: GlassBackgroundView, style: GlassBackgroundView.Style,
                        tint: GlassBackgroundView.TintColor, isDark: Bool, isInteractive: Bool,
                        transition: ContainedViewLayoutTransition = .immediate) {
        guard let glass = experimentalView else { return }
        glass.backgroundOwner = owner
        glass.overrideUserInterfaceStyle = isDark ? .dark : .light
        var material = ExperimentalGlassMaterial.regular
        let color: UIColor
        var clear = style == .clear
        switch tint.kind {
        case .panel:
            color = isDark ? UIColor(white: 0.05, alpha: style == .prominent ? 0.7 : 0.55)
                : UIColor(white: 1, alpha: style == .prominent ? 0.55 : 0.35)
        case .clear:
            clear = true
            color = .clear
        case let .custom(customStyle, customColor):
            clear = customStyle == .clear
            color = customColor
        }
        material.tintColor = color
        material.backgroundTextureBlurRadius = clear ? 0 : (style == .prominent ? 0.5 : 0.3)
        glass.setMaterial(material, transition: transition)
        experimentalInteractionEnabled = isInteractive
        if !isInteractive { updateInteraction(active: false) }
        glass.edgeRefractionBoost = 1.65
        glass.isHidden = UIAccessibility.isReduceTransparencyEnabled
        backgroundColor = UIAccessibility.isReduceTransparencyEnabled
            ? (isDark ? .black : .white) : .clear
    }

    private func updateInteraction(active: Bool) {
        guard let glass = experimentalView else { return }
        let active = active && experimentalInteractionEnabled
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.18
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            glass.transform = active ? CGAffineTransform(scaleX: 1.025, y: 1.025) : .identity
        }
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        updateInteraction(active: true)
    }
    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        updateInteraction(active: false)
    }
    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        updateInteraction(active: false)
    }

    func updateInteractiveGeometry(size: CGSize, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(origin: .zero, size: size)
        layer.cornerRadius = cornerRadius
        visualEffectView?.frame = bounds
        experimentalView?.frame = bounds
        experimentalView?.layer.cornerRadius = cornerRadius
        CATransaction.commit()
    }
}
