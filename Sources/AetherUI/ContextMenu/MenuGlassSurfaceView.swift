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
    private var isGooeyMaterialSuppressed = false
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
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.isDark = isDark
        if effectsEnabled {
            let surface = GlassBackgroundView(
                style: .regular,
                appearanceStyle: appearanceStyle
            )
            surface.surfaceRole = .popup
            surface.isDarkOverride = isDark
            surface.glassIsInteractive = true
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
            isVisible: !isGooeyMaterialSuppressed,
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
        setGlassInteractionTransform(.identity)
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
        surfaceCornerRadii = resolved
        let radius = resolved.average

        if surfaceView?.usesLiquidGlassAppearance == true, #available(iOS 26.0, *) {
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

    func setGooeyMaterialSuppressed(_ suppressed: Bool) {
        guard isGooeyMaterialSuppressed != suppressed else { return }
        isGooeyMaterialSuppressed = suppressed
        surfaceView?.isHidden = suppressed
        scatteringView.isHidden = suppressed || !supplementalScatteringEnabled
        setNeedsLayout()
    }

    func updateMaterialThickness(_ progress: CGFloat) {
        guard surfaceView?.usesLiquidGlassAppearance == true else {
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

    func setSupplementalScatteringEnabled(_ enabled: Bool) {
        supplementalScatteringEnabled = enabled
        scatteringView.isHidden = !enabled || isGooeyMaterialSuppressed
    }
}
