import UIKit

/// Appearance-aware menu surface with a stable content host.
///
/// Liquid appearances are rendered by `GlassBackgroundView`; Legacy uses
/// that host's ordinary color/border/shadow renderer. No backdrop view,
/// visual effect, private filter or glass interaction recognizer is allocated
/// for Legacy.
public final class MenuGlassSurfaceView: UIView {
    public let contentView = UIView()

    private let surfaceView: GlassBackgroundView?
    private let scatteringView = UIView()
    private let isDark: Bool
    private var surfaceCornerRadii = ContextMenuBloomCornerRadii.uniform(0)
    private var forcesRoundedBoundsClip = false
    private var appliedCornerRadii: ContextMenuBloomCornerRadii?
    private var appliedCornerUsesLiquidGlass = false
    private var appliedCornerForcesRoundedBoundsClip = false
    private weak var appliedCornerContentHost: UIView?
    private var supplementalScatteringEnabled = true
    var routesTouchesToGlassSurface = false

    /// `appearanceStyle` is resolved by the owning presentation before this
    /// surface is allocated. Passing it through the initializer is important:
    /// applying an override after `GlassBackgroundView` has been constructed
    /// would briefly allocate/register the wrong Liquid renderer for a local
    /// Legacy menu.
    public init(
        isDark: Bool,
        effectsEnabled: Bool = true,
        appearanceStyle: AetherAppearanceStyle? = nil,
        surfaceRole: AetherSurfaceRole = .popup,
        legacySurfaceColorOverride: UIColor? = nil
    ) {
        self.isDark = isDark
        if effectsEnabled {
            let surface = GlassBackgroundView(
                style: .regular,
                appearanceStyle: appearanceStyle
            )
            surface.surfaceRole = surfaceRole
            surface.isDarkOverride = isDark
            surface.glassIsInteractive = true
            surface.legacySurfaceColorOverride = legacySurfaceColorOverride
            self.surfaceView = surface
        } else {
            self.surfaceView = nil
        }

        super.init(frame: .zero)

        clipsToBounds = false
        if let surfaceView {
            surfaceView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(surfaceView)

            scatteringView.isUserInteractionEnabled = false
            scatteringView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            surfaceView.contentView.addSubview(scatteringView)

            contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.backgroundColor = .clear
            surfaceView.contentView.addSubview(contentView)
        } else {
            contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.backgroundColor = .clear
            addSubview(contentView)
        }
        updateMaterialThickness(0)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func tearDownGlassEffect() {
        surfaceView?.tearDownLiquidRenderer()
    }

    internal var usesLiquidSurfaceRendererForTesting: Bool {
        surfaceView?.usesAnyGlassRendererForTesting == true
    }

    internal var usesLegacySurfaceRendererForTesting: Bool {
        surfaceView?.usesLegacySurfaceRendererForTesting == true
    }

    internal var legacyBlurStyleForTesting: UIBlurEffect.Style? {
        surfaceView?.legacyBlurStyleForTesting
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        surfaceView?.frame = bounds
        scatteringView.frame = bounds
        contentView.frame = bounds

        let storedRadius = surfaceCornerRadii.average
        let radius = storedRadius > 0 ? storedRadius : layer.cornerRadius
        surfaceView?.update(
            size: bounds.size,
            cornerRadius: radius,
            isDark: isDark,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled,
              self.point(inside: point, with: event) else {
            return nil
        }
        if !routesTouchesToGlassSurface {
            let contentPoint = convert(point, to: contentView)
            if let hit = contentView.hitTest(contentPoint, with: event), hit !== contentView {
                return hit
            }
        }
        if let surfaceView {
            return surfaceView.hitTest(convert(point, to: surfaceView), with: event) ?? self
        }
        return self
    }

    func setGlassInteractionTransform(_ transform: CGAffineTransform) {
        self.transform = transform
        guard surfaceView?.usesLiquidGlassAppearance == true else {
            contentView.transform = .identity
            return
        }
        let scaleX = max(0.001, hypot(transform.a, transform.c))
        let scaleY = max(0.001, hypot(transform.b, transform.d))
        contentView.transform = transform.isIdentity
            ? .identity
            : CGAffineTransform(scaleX: 1 / scaleX, y: 1 / scaleY)
    }

    func resetGlassInteractionTransform() {
        elasticStretchIsActive = false
        setGlassInteractionTransform(.identity)
    }

    private var elasticStretchIsActive = false

    /// iOS 27 menus lean toward a held finger: a slight swell while it rests
    /// on the platter, and a rubber-band pull of the nearest edge once it
    /// leaves. `point` is in this view's untransformed coordinates.
    func updateElasticStretch(toward point: CGPoint) {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        func band(_ overflow: CGFloat, _ dimension: CGFloat) -> CGFloat {
            guard overflow != 0 else { return 0 }
            let limit = dimension * 0.22
            let pull = limit * (1 - 1 / (abs(overflow) * 0.55 / limit + 1))
            return overflow < 0 ? -pull : pull
        }
        let extendX = band(point.x < 0 ? point.x : max(0, point.x - size.width), size.width)
        let extendY = band(point.y < 0 ? point.y : max(0, point.y - size.height), size.height)
        let swell: CGFloat = 0.015
        // Scaling about the centre and shifting by half the extension keeps
        // the far edge in place while the near edge follows the finger.
        let transform = CGAffineTransform(translationX: extendX / 2, y: extendY / 2)
            .scaledBy(x: 1 + swell + abs(extendX) / size.width, y: 1 + swell + abs(extendY) / size.height)
        elasticStretchIsActive = true
        UIView.animate(withDuration: 0.14, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            self.setGlassInteractionTransform(transform)
        }
    }

    /// Springs back with a visible overshoot, as the platter does on lift-off.
    func releaseElasticStretch() {
        guard elasticStretchIsActive else { return }
        elasticStretchIsActive = false
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.52, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.setGlassInteractionTransform(.identity)
        }
    }

    func setSurfaceCornerRadius(_ radius: CGFloat) {
        setSurfaceCornerRadii(.uniform(radius))
    }

    func setSurfaceCornerRadii(_ radii: ContextMenuBloomCornerRadii) {
        let resolved = ContextMenuBloomCornerRadii(
            topLeft: max(0, radii.topLeft),
            topRight: max(0, radii.topRight),
            bottomLeft: max(0, radii.bottomLeft),
            bottomRight: max(0, radii.bottomRight)
        )
        let usesLiquidGlass = surfaceView?.usesLiquidGlassAppearance == true
        let contentHost = surfaceView?.contentView.superview
        // Identical corner writes invalidate native glass layout even when
        // the source lobe is hidden or the shape has already settled. A new
        // renderer reparents the stable content view, so it must receive the
        // configuration again; clipping changes must also bypass this guard.
        guard appliedCornerRadii != resolved
            || appliedCornerUsesLiquidGlass != usesLiquidGlass
            || appliedCornerForcesRoundedBoundsClip != forcesRoundedBoundsClip
            || appliedCornerContentHost !== contentHost else { return }
        appliedCornerRadii = resolved
        appliedCornerUsesLiquidGlass = usesLiquidGlass
        appliedCornerForcesRoundedBoundsClip = forcesRoundedBoundsClip
        appliedCornerContentHost = contentHost
        surfaceCornerRadii = resolved
        let radius = resolved.average

        if usesLiquidGlass, #available(iOS 26.0, *) {
            let configuration = UICornerConfiguration.corners(
                topLeftRadius: .fixed(resolved.topLeft),
                topRightRadius: .fixed(resolved.topRight),
                bottomLeftRadius: .fixed(resolved.bottomLeft),
                bottomRightRadius: .fixed(resolved.bottomRight)
            )
            surfaceView?.setNativeCornerConfiguration(configuration)
            cornerConfiguration = configuration
            layer.cornerRadius = forcesRoundedBoundsClip ? radius : 0
            layer.masksToBounds = forcesRoundedBoundsClip
            contentView.cornerConfiguration = configuration
            contentView.layer.cornerRadius = 0
        } else {
            if #available(iOS 26.0, *) {
                cornerConfiguration = .uniformCorners(radius: .fixed(radius))
            }
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            contentView.layer.cornerRadius = radius
            contentView.layer.cornerCurve = .continuous
            contentView.layer.masksToBounds = true
        }
        surfaceView?.glassCornerRadius = radius
        setNeedsLayout()
    }

    func setForcesRoundedBoundsClip(_ enabled: Bool) {
        guard forcesRoundedBoundsClip != enabled else { return }
        forcesRoundedBoundsClip = enabled
        setSurfaceCornerRadii(surfaceCornerRadii)
    }

    /// Confined to the transition host; ordinary popup/legacy surfaces retain
    /// their own material and shadow behavior.
    func configureTransitionOptics(contentLensing: Bool, excludesShadow: Bool) {
        surfaceView?.nativeDescriptorOptions = .init(contentLensing: contentLensing, excludesShadow: excludesShadow)
        setNeedsLayout()
        layoutIfNeeded()
    }

    var usesNativeContentLensing: Bool { surfaceView?.nativeContentLensingApplied == true }

    func updateMaterialThickness(_ progress: CGFloat) {
        guard surfaceView?.usesLiquidGlassAppearance == true else {
            scatteringView.backgroundColor = .clear
            return
        }
        // Native glass already scatters the backdrop and provides key/fill
        // highlights. A white overlay hides that moving refraction during
        // the transition, particularly on a dark or detailed background.
        if usesNativeContentLensing {
            scatteringView.backgroundColor = .clear
            return
        }
        let t = max(0, min(1, progress))
        let baseAlpha: CGFloat = isDark ? 0.015 : 0.025
        let peakAlpha: CGFloat = isDark ? 0.085 : 0.115
        scatteringView.backgroundColor = UIColor.white.withAlphaComponent(
            baseAlpha + (peakAlpha - baseAlpha) * t
        )
    }

    /// Opacity of the glass material alone; hosted content is unaffected.
    /// Unlike view alpha, the native renderer honours this per frame.
    func setTransitionMaterialAlpha(_ alpha: CGFloat) {
        guard let surfaceView, abs(surfaceView.transitionMaterialAlpha - alpha) > 0.001 else { return }
        surfaceView.transitionMaterialAlpha = alpha
        scatteringView.alpha = alpha
    }

    func setSupplementalScatteringEnabled(_ enabled: Bool) {
        supplementalScatteringEnabled = enabled
        scatteringView.isHidden = !enabled
    }
}
