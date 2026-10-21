import UIKit

/// Selection surface for the pre-iOS-26 LiquidLensView path. The owning lens
/// supplies geometry, masks, lift/collapse state and transition timing.
final class ExperimentalGlassLensSurface: UIView {
    let glass: ExperimentalGlassView
    private let appearanceStyle: AetherAppearanceStyle
    private let resting = UIView()

    init?(appearanceStyle: AetherAppearanceStyle = .liquidGlassV1,
          material: ExperimentalGlassMaterial = .lens) {
        guard let glass = ExperimentalGlassView(material) else { return nil }
        self.glass = glass
        self.appearanceStyle = appearanceStyle
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(resting)
        addSubview(glass)
        glass.backgroundOwner = self
        glass.alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(isDark: Bool, lifted: Bool, collapsed: Bool,
                transition: ContainedViewLayoutTransition) {
        overrideUserInterfaceStyle = isDark ? .dark : .light
        resting.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.16)
            : UIColor.white.withAlphaComponent(0.3)
        var material = ExperimentalGlassMaterial.lens
        // Liquid Glass v2 keeps the lens tint supplied below, but softens the
        // captured backdrop with a small, colour-neutral blur. This only
        // changes the sampled texture; it does not paint over the lens tint.
        material.backgroundTextureBlurRadius = appearanceStyle == .liquidGlassV2 ? 4.0 : 0.0
        material.tintColor = isDark ? UIColor.black.withAlphaComponent(0.08) : .clear
        glass.setMaterial(material, transition: transition)
        let showGlass = lifted && !UIAccessibility.isReduceTransparencyEnabled
        transition.updateAlpha(view: resting, alpha: showGlass ? 0 : 1)
        transition.updateAlpha(view: glass, alpha: showGlass ? 1 : 0)
        transition.updateAlpha(view: self, alpha: collapsed ? 0 : 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resting.frame = bounds
        glass.frame = bounds
        let radius = min(bounds.width, bounds.height) / 2
        resting.layer.cornerRadius = radius
        glass.layer.cornerRadius = radius
    }
}
