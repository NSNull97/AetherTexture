import UIKit
import AsyncDisplayKit

// MARK: - Internal content container

private final class GlassContentContainer: UIView {
    private let maskContentView: UIView
    var passesUnclaimedTouchesThrough = false

    init(maskContentView: UIView) {
        self.maskContentView = maskContentView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else {
            return nil
        }
        if passesUnclaimedTouchesThrough,
           !hasExplicitInteraction(from: result) {
            return nil
        }
        if result === self {
            if let recognizers = self.gestureRecognizers, !recognizers.isEmpty {
                return result
            }
            return nil
        }
        return result
    }

    private func hasExplicitInteraction(from hitView: UIView) -> Bool {
        var candidate: UIView? = hitView
        while let view = candidate, view !== self {
            if view is UIControl || view is UIScrollView {
                return true
            }
            if let recognizers = view.gestureRecognizers,
               !recognizers.isEmpty {
                return true
            }
            candidate = view.superview
        }
        return false
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        if let subview = subview as? GlassBackgroundView.ContentView {
            maskContentView.addSubview(subview.tintMask)
        }
    }

    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        if let subview = subview as? GlassBackgroundView.ContentView {
            subview.tintMask.removeFromSuperview()
        }
    }
}

/// A compositor-owned geometry/material track for the native liquid-glass
/// hierarchy.  The tab-bar accessory builds this from the same samples and
/// host-time origin as its outer surface track, so the material cannot trail
/// the card when the main thread misses a display-link callback.
@MainActor
struct GlassBackgroundCompositorSettleTrack {
    /// Identifies the coordinator that installed this track. A wrapper can be
    /// reused synchronously from a dismiss completion, so lifecycle cleanup
    /// must never let the retired coordinator remove its successor's native
    /// material animations.
    let owner: ObjectIdentifier?
    let duration: TimeInterval
    let keyTimes: [NSNumber]
    let sizes: [CGSize]
    let cornerRadii: [CGFloat]
    let materialAlphaValues: [CGFloat]
    let mediaBeginTime: CFTimeInterval
    let preferredFrameRateRange: CAFrameRateRange

    init(
        owner: ObjectIdentifier? = nil,
        duration: TimeInterval,
        keyTimes: [NSNumber],
        sizes: [CGSize],
        cornerRadii: [CGFloat],
        materialAlphaValues: [CGFloat],
        mediaBeginTime: CFTimeInterval,
        preferredFrameRateRange: CAFrameRateRange
    ) {
        self.owner = owner
        self.duration = duration
        self.keyTimes = keyTimes
        self.sizes = sizes
        self.cornerRadii = cornerRadii
        self.materialAlphaValues = materialAlphaValues
        self.mediaBeginTime = mediaBeginTime
        self.preferredFrameRateRange = preferredFrameRateRange
    }

    var isValid: Bool {
        let count = keyTimes.count
        guard duration.isFinite,
              duration > 0,
              mediaBeginTime.isFinite,
              count >= 2,
              sizes.count == count,
              cornerRadii.count == count,
              materialAlphaValues.count == count else {
            return false
        }
        return sizes.allSatisfy {
            $0.width.isFinite && $0.height.isFinite
                && $0.width >= 0 && $0.height >= 0
        } && cornerRadii.allSatisfy { $0.isFinite && $0 >= 0 }
            && materialAlphaValues.allSatisfy { $0.isFinite }
    }
}

// MARK: - GlassBackgroundView

/// Glass background effect view — the core glass morphism component.
/// Port of Display framework `GlassBackgroundComponent.GlassBackgroundView` targeting
/// the native `UIGlassEffect` pipeline on iOS 26+ with a legacy CABackdropLayer
/// fallback for earlier systems.
public class GlassBackgroundView: UIView, AetherAppearanceConsumer {
    /// The same key is used on every native child layer. Each layer owns its
    /// own group, but all groups use a shared host-time origin and key lattice.
    internal static let transitionCompositorSettleAnimationKey =
        "aether.glass.transition.compositorSettle"

    internal struct LegacyShadowOverride: Equatable {
        let opacity: Float
        let radius: CGFloat
        let offset: CGSize
    }

    // MARK: Content view protocol

    public protocol ContentView: UIView {
        var tintMask: UIView { get }
    }

    public final class ContentColorView: UIView, ContentView {
        public let tintMask = UIView()

        public override init(frame: CGRect) {
            super.init(frame: frame)
            tintMask.backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override var backgroundColor: UIColor? {
            didSet {
                tintMask.backgroundColor = backgroundColor?.withAlphaComponent(1.0) ?? .black
            }
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            tintMask.frame = bounds
            tintMask.layer.cornerRadius = layer.cornerRadius
        }
    }

    public final class ContentImageView: UIView, ContentView {
        private let imageNode = ASImageNode()
        private let tintImageNode = ASImageNode()

        public var image: UIImage? {
            didSet { updateImages() }
        }

        public var highlightedImage: UIImage? {
            didSet { updateImages() }
        }

        public var isHighlighted: Bool = false {
            didSet { updateImages() }
        }

        public var tintMask: UIView {
            tintImageNode.view
        }

        public override var contentMode: UIView.ContentMode {
            didSet {
                imageNode.contentMode = contentMode
                tintImageNode.contentMode = contentMode
            }
        }

        public override var tintColor: UIColor! {
            didSet {
                imageNode.view.setMonochromaticEffect(tintColor: tintColor)
            }
        }

        public override init(frame: CGRect) {
            super.init(frame: frame)
            setupNodes()
        }

        public init(image: UIImage?) {
            self.image = image
            super.init(frame: .zero)
            setupNodes()
            updateImages()
        }

        public init(image: UIImage?, highlightedImage: UIImage?) {
            self.image = image
            self.highlightedImage = highlightedImage
            super.init(frame: .zero)
            setupNodes()
            updateImages()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            imageNode.view.removeFromSuperview()
            tintImageNode.view.removeFromSuperview()
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            imageNode.frame = bounds
            tintImageNode.frame = bounds
        }

        private func setupNodes() {
            imageNode.contentMode = contentMode
            imageNode.view.isUserInteractionEnabled = false
            addSubview(imageNode.view)

            tintImageNode.contentMode = contentMode
            tintImageNode.tintColor = .black
            tintImageNode.view.isUserInteractionEnabled = false
            updateImages()
        }

        private func updateImages() {
            let activeImage = isHighlighted ? (highlightedImage ?? image) : image
            imageNode.image = activeImage
            tintImageNode.image = activeImage?.withRenderingMode(.alwaysTemplate)
        }
    }

    // MARK: Public types (preserve existing API surface)

    public enum Style: Equatable {
        case regular
        case clear
        case prominent
    }

    public struct TintColor: Equatable {
        public enum CustomStyle: Equatable {
            case `default`
            case clear
        }

        public enum Kind: Equatable {
            case panel
            case clear
            case custom(style: CustomStyle, color: UIColor)
        }

        public let kind: Kind
        public let innerColor: UIColor?
        public let innerInset: CGFloat

        public init(kind: Kind, innerColor: UIColor? = nil, innerInset: CGFloat = 3.0) {
            self.kind = kind
            self.innerColor = innerColor
            self.innerInset = innerInset
        }
    }

    public enum Shape: Equatable {
        case roundedRect(cornerRadius: CGFloat)
    }

    private enum CornerRadiusSource: Equatable {
        case fixed(CGFloat)
        case capsule

        func resolved(for size: CGSize) -> CGFloat {
            switch self {
            case let .fixed(radius):
                return radius
            case .capsule:
                return size.height / 2.0
            }
        }
    }

    public struct GlassParams: Equatable {
        public let cornerRadius: CGFloat
        public let keepRoundedCorners: Bool

        public init(cornerRadius: CGFloat = 10.0, keepRoundedCorners: Bool = true) {
            self.cornerRadius = cornerRadius
            self.keepRoundedCorners = keepRoundedCorners
        }
    }

    public struct Params: Equatable {
        public let shape: Shape
        public let isDark: Bool
        public let tintColor: TintColor
        public let isInteractive: Bool
        public let isVisible: Bool
    }

    /// When `true`, always use the legacy CABackdropLayer renderer even on iOS 26+.
    /// Matches `useCustomGlassImpl` debug switch.
    public static var useCustomGlassImpl: Bool = !GlassCompatibility.isLiquidDesignAvailable

    private static let legacyShadowInset: CGFloat = 32.0

    // MARK: Internal state

    private var style: Style

    // Native (iOS 26+) path.
    private var nativeView: UIVisualEffectView? = nil
    private var nativeViewShape: Shape?
    private var nativeParamsView: EffectSettingsContainerView? = nil
    private let syntheticStrokeLayer = CAShapeLayer()

    // Legacy path.
    private var legacyView: LegacyGlassBackdropView? = nil
    private var legacyHighlightContainerView: UIView? = nil
    private var foregroundNode: ASImageNode? = nil
    /// Top-edge specular highlight on the legacy path. Vertical white→
    /// clear gradient sitting above `foregroundView` so even when the
    /// backdrop sample is uniformly white (e.g. plain `systemBackground`
    /// behind the glass) the surface still reads as glass — the
    /// bright top kerb suggests light catching the curved edge of a
    /// material, not a flat opaque pill. Placed in `GlassBackgroundView`
    /// rather than `LegacyGlassBackdropView` because the foreground
    /// image (rendered shadow + border + fill) sits above the backdrop
    /// view; the highlight has to be above THAT to actually be visible.
    private var shadowNode: ASImageNode? = nil

    // Classic, non-Liquid-Glass path used by `AetherAppearanceStyle.legacy`.
    // This is a public UIKit blur material and never owns UIGlassEffect,
    // CABackdrop/CAFilter lensing or a display-link renderer.
    private var plainSurfaceView: UIView? = nil
    private var legacyMaterialView: UIVisualEffectView? = nil
    private var legacyBlurStyle: UIBlurEffect.Style? = nil
    private var appliedAppearanceStyle: AetherAppearanceStyle

    /// Optional per-component style. `nil` follows the application runtime.
    public var appearanceStyleOverride: AetherAppearanceStyle? = nil {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    /// Semantic role used to resolve Legacy colors, border and shadow.
    public var surfaceRole: AetherSurfaceRole = .floatingSurface {
        didSet {
            guard surfaceRole != oldValue else { return }
            if appliedAppearanceStyle == .legacy {
                setNeedsLayout()
            }
        }
    }

    /// Optional classic-surface color for components that already expose a
    /// theme-level background color. It is ignored by both Liquid Glass
    /// generations and therefore cannot accidentally paint over refraction.
    public var legacySurfaceColorOverride: UIColor? {
        didSet {
            guard legacySurfaceColorOverride !== oldValue else { return }
            if appliedAppearanceStyle == .legacy {
                _ = reapplyLastUpdate()
            }
        }
    }

    /// Whether the classic renderer should place a public UIKit blur material
    /// behind its semantic surface color. Attached bars keep this enabled;
    /// filled controls such as the iOS 18 search field opt out and render the
    /// role's ordinary semantic fill instead.
    internal var legacyUsesBlurMaterial: Bool = true {
        didSet {
            guard legacyUsesBlurMaterial != oldValue,
                  appliedAppearanceStyle == .legacy else {
                return
            }
            installRenderer(for: .legacy)
            if !reapplyLastUpdate() {
                setNeedsLayout()
            }
        }
    }

    /// Component-local public material recipe. The Legacy bottom accessory
    /// uses an ultra-thin effect at full renderer alpha instead of simulating
    /// density with a translucent color wash.
    internal var legacyBlurStyleOverride: UIBlurEffect.Style? {
        didSet {
            guard legacyBlurStyleOverride?.rawValue
                    != oldValue?.rawValue,
                  appliedAppearanceStyle == .legacy else {
                return
            }
            installRenderer(for: .legacy)
            if !reapplyLastUpdate() {
                setNeedsLayout()
            }
        }
    }

    /// Stable private backdrop group shared with the attached tab bar in
    /// non-App-Store-safe builds. Public safe builds leave UIKit's groups
    /// untouched while retaining the requested public blur style.
    internal var legacyBackdropGroupingIdentifier: String? {
        didSet {
            guard legacyBackdropGroupingIdentifier != oldValue else { return }
            legacyMaterialView?.aetherApplyBackdropGroupingIdentifier(
                legacyBackdropGroupingIdentifier
            )
        }
    }

    /// The component is sitting above a shared external Legacy material.
    /// Its local renderer stays effect-free and contributes only its shape,
    /// optional surface color and shadow.
    internal var legacyUsesExternalBlurMaterial: Bool = false {
        didSet {
            guard legacyUsesExternalBlurMaterial != oldValue,
                  appliedAppearanceStyle == .legacy else {
                return
            }
            _ = reapplyLastUpdate()
        }
    }

    /// Optional component-local border width. Used by attached mini players,
    /// whose classic surface has shadow but no perimeter hairline.
    internal var legacyBorderWidthOverride: CGFloat? {
        didSet {
            guard legacyBorderWidthOverride != oldValue,
                  appliedAppearanceStyle == .legacy else {
                return
            }
            _ = reapplyLastUpdate()
        }
    }

    /// Optional component-local classic shadow recipe. The attached mini
    /// player uses a darker but tighter shadow than generic floating cards.
    internal var legacyShadowOverride: LegacyShadowOverride? {
        didSet {
            guard legacyShadowOverride != oldValue,
                  appliedAppearanceStyle == .legacy else {
                return
            }
            _ = reapplyLastUpdate()
        }
    }

    #if DEBUG
    internal private(set) var reduceTransparencyRefreshCountForTesting = 0
    #endif

    // Mask for content-driven vibrancy (used by both paths).
    private let maskContainerView: UIView
    public let maskContentView: UIView
    private let publicContentContainer: GlassContentContainer
    private let contentContainer: GlassContentContainer
    private var innerBackgroundView: UIView?

    public var contentView: UIView {
        publicContentContainer
    }

    /// Plain content plane above the material renderer. The tab-bar player
    /// uses this only for its expanded endpoint so the one glass material can
    /// fade independently without fading Full Player content. Compact content
    /// remains a direct child of `contentView` and retains native vibrancy.
    internal var transitionContentView: UIView {
        contentContainer
    }

    /// Keeps native liquid-glass deformation alive when endpoint content is
    /// hosted above the material. Controls, scroll views and explicit gesture
    /// surfaces still own their touches; otherwise the hit falls through to
    /// the single native material view below. The legacy renderer deliberately
    /// keeps the old content hit target because it has no interactive material
    /// view to receive a forwarded touch.
    internal var transitionContentPassesUnclaimedTouchesToMaterial: Bool {
        get { contentContainer.passesUnclaimedTouchesThrough }
        set {
            contentContainer.passesUnclaimedTouchesThrough = newValue
                && nativeView != nil
        }
    }

    /// Whether an otherwise-unclaimed transition touch may enter the native
    /// material hierarchy. The bottom-bar accessory disables this outside its
    /// stable compact endpoint: a fullscreen pan received by the same
    /// interactive UIGlassEffect would otherwise leave a large elastic state
    /// behind when that surface docks back into the 48pt Mini.
    ///
    /// Returning the wrapper itself while quarantined keeps framework-owned
    /// ancestor gestures alive without putting the native effect in the hit
    /// view's responder ancestry. This changes touch ownership only; the glass
    /// renderer/effect object remains untouched.
    internal var transitionMaterialInteractionEnabled = true

    internal var transitionMaterialHitTargetForTesting: UIView? {
        nativeView
    }

    /// Counts actual assignments to `UIVisualEffectView.effect`. The getter
    /// returns a copy on current SDKs, so pointer identity cannot prove that a
    /// transition retained one live native renderer.
    internal private(set) var nativeGlassEffectAssignmentCountForTesting = 0
    var nativeDescriptorOptions = NativeGlassDescriptorOptions() {
        didSet {
            guard nativeDescriptorOptions != oldValue else { return }
            params = nil
            setNeedsLayout()
        }
    }
    private var requestedNativeEffectStyle = 0
    private var appliedNativeEffectStyle: Int?
    private var appliedNativeDescriptorOptions: NativeGlassDescriptorOptions?
    internal private(set) var nativeContentLensingApplied = false


    /// Opacity of the optical material only. Endpoint content hosted in
    /// `transitionContentView` is deliberately unaffected.
    internal var transitionMaterialAlpha: CGFloat {
        get { _transitionMaterialAlpha }
        set {
            _transitionMaterialAlpha = min(max(newValue, 0), 1)
            applyTransitionMaterialAlpha()
        }
    }

    internal var transitionMaterialPresentationAlphaForTesting: CGFloat {
        if let nativeParamsView {
            return nativeParamsView.alpha
        }
        return legacyView?.alpha ?? plainSurfaceView?.alpha ?? 0
    }

    public func updateStyle(_ style: Style) {
        guard self.style != style else {
            return
        }
        self.style = style
        if !reapplyLastUpdate() {
            setNeedsLayout()
        }
    }

    internal var styleForTesting: Style {
        style
    }

    public private(set) var params: Params?

    /// When `true` (default) the glass automatically re-applies its last
    /// `update(...)` with an `isDark` value derived from
    /// `traitCollection.userInterfaceStyle` whenever the trait collection
    /// changes. This fixes mixed-tint glass on screens where only some
    /// call sites go through the short-form `update`, and keeps all
    /// GlassBackgroundView instances visually consistent as the system
    /// toggles light/dark. Set to `false` if you want the explicit
    /// `isDark` you passed to update(...) to stay pinned regardless of
    /// trait changes (e.g. a forced-dark glass on a blue custom background).
    public var tracksTraitCollection: Bool = true

    /// Explicit override for the resolved `isDark` value. When non-`nil`
    /// it wins over the trait-collection auto-derivation on every path
    /// that computes dark/light implicitly — the short-form `update(...)`,
    /// `layoutSubviews`-driven auto-update, and `traitCollectionDidChange`.
    /// Leave at `nil` to let the glass follow the system theme.
    ///
    /// Typical use: a glass surface sitting on top of a custom dark
    /// artwork/image, where the system is in light mode but the glass
    /// still needs to render with dark-mode tinting so it reads against
    /// the background. Set once and forget — unlike the `isDark:`
    /// parameter on the full-form `update(...)`, this survives trait
    /// changes.
    public var isDarkOverride: Bool? {
        didSet {
            if isDarkOverride == oldValue { return }
            if !reapplyLastUpdate() {
                setNeedsLayout()
            }
        }
    }

    /// `isDarkOverride` if set, otherwise the trait-collection derivation.
    /// Single source of truth for every implicit dark/light computation.
    private var resolvedIsDark: Bool {
        isDarkOverride ?? (traitCollection.userInterfaceStyle == .dark)
    }

    /// Corner radius used by `layoutSubviews`-driven auto-update. `nil`
    /// means "pill" (`bounds.height / 2`). Set via property or via
    /// `update(...)`; the latter also writes this through so subsequent
    /// layout passes respect the explicit value.
    public var glassCornerRadius: CGFloat? {
        didSet {
            guard glassCornerRadius != oldValue else { return }
            invalidateLayoutConfiguration()
        }
    }

    /// Tint color used by `layoutSubviews`-driven auto-update.
    public var glassTintColor: TintColor = .init(kind: .panel) {
        didSet {
            guard glassTintColor != oldValue else { return }
            invalidateLayoutConfiguration()
        }
    }

    /// Interactive glass flag used by `layoutSubviews`-driven auto-update.
    /// When true, `UIGlassEffect.isInteractive` is set on iOS 26+ so the
    /// glass shows native elastic deformation on touch. Defaults to `true`
    /// — every `GlassBackgroundView` is interactive by default. Pass
    /// `glassIsInteractive = false` after init to opt a specific surface
    /// out of the deformation.
    public var glassIsInteractive: Bool = true {
        didSet {
            guard glassIsInteractive != oldValue else { return }
            invalidateLayoutConfiguration()
        }
    }

    /// Optional stroke override for the glass outline.
    /// `nil` keeps the automatic fallback: Aether's Liquid Glass v2 appearance gets a
    /// synthetic hairline only on OS versions before iOS 27, because iOS 27+
    /// provides the native glass outline itself.
    public var strokeAppearance: AetherGlassStrokeAppearance? {
        didSet {
            setNeedsLayout()
        }
    }

    internal var isSyntheticStrokeVisible: Bool {
        !syntheticStrokeLayer.isHidden
    }

    internal var isSyntheticStrokeHostedByNativeEffectView: Bool {
        guard let nativeView else {
            return false
        }
        return syntheticStrokeLayer.superlayer === nativeView.layer
    }

    internal var syntheticStrokeAnimationKeys: [String] {
        syntheticStrokeLayer.animationKeys() ?? []
    }

    internal var isNativeGlassLayerMaskedForTesting: Bool? {
        nativeView?.layer.masksToBounds
    }

    internal var hasNativeCornerConfigurationForTesting: Bool {
        hasCustomNativeCornerConfiguration
    }

    internal var usesNativeGlassRendererForTesting: Bool {
        nativeView != nil && nativeParamsView != nil
    }

    internal var usesAnyGlassRendererForTesting: Bool {
        nativeView != nil || legacyView != nil
    }

    internal var usesLegacySurfaceRendererForTesting: Bool {
        plainSurfaceView != nil && nativeView == nil && legacyView == nil
    }

    internal var legacyBlurStyleForTesting: UIBlurEffect.Style? {
        legacyBlurStyle
    }

    internal var legacyPlainSurfaceBackgroundColorForTesting: UIColor? {
        plainSurfaceView?.backgroundColor
    }

    internal var legacyMaterialContentBackgroundColorForTesting: UIColor? {
        legacyMaterialView?.contentView.backgroundColor
    }

    internal var legacySurfaceCornerRadiusForTesting: CGFloat? {
        plainSurfaceView?.layer.cornerRadius
    }

    internal var legacySurfaceShadowOpacityForTesting: Float? {
        plainSurfaceView?.layer.shadowOpacity
    }

    internal var legacySurfaceShadowRadiusForTesting: CGFloat? {
        plainSurfaceView?.layer.shadowRadius
    }

    internal var legacySurfaceShadowOffsetForTesting: CGSize? {
        plainSurfaceView?.layer.shadowOffset
    }

    internal var legacySurfaceBorderWidthForTesting: CGFloat? {
        plainSurfaceView?.layer.borderWidth
    }

    internal var legacyUsesExternalBlurMaterialForTesting: Bool {
        legacyUsesExternalBlurMaterial && legacyMaterialView == nil
    }

    internal var legacyBackdropGroupingIdentifierForTesting: String? {
        legacyMaterialView?.aetherBackdropGroupingIdentifier
    }

    internal var usesLiquidGlassAppearance: Bool {
        appliedAppearanceStyle.usesLiquidGlass
    }

    internal func tearDownLiquidRenderer() {
        nativeView?.effect = nil
        legacyMaterialView?.effect = nil
        nativeView?.layer.removeAllAnimations()
        legacyView?.layer.removeAllAnimations()
    }

    internal var isTransitionCompositorSettleActive: Bool {
        hasTransitionCompositorSettleTrack
    }

    internal var hasPendingTransitionCompositorPresentation: Bool {
        !pendingTransitionCompositorGeometry.isEmpty
    }

    internal var transitionNativeParamsAnimationForTesting: CAAnimation? {
        nativeParamsView?.layer.animation(
            forKey: Self.transitionCompositorSettleAnimationKey
        )
    }

    internal var transitionNativeEffectAnimationForTesting: CAAnimation? {
        nativeView?.layer.animation(
            forKey: Self.transitionCompositorSettleAnimationKey
        )
    }

    internal var transitionContentContainerAnimationForTesting: CAAnimation? {
        contentContainer.layer.animation(
            forKey: Self.transitionCompositorSettleAnimationKey
        )
    }

    internal var transitionMaskContainerAnimationForTesting: CAAnimation? {
        maskContainerView.layer.animation(
            forKey: Self.transitionCompositorSettleAnimationKey
        )
    }

    internal var transitionMaskContentAnimationForTesting: CAAnimation? {
        maskContentView.layer.animation(
            forKey: Self.transitionCompositorSettleAnimationKey
        )
    }

    internal var transitionSyntheticStrokeAnimationForTesting: CAAnimation? {
        syntheticStrokeLayer.animation(
            forKey: Self.transitionCompositorSettleAnimationKey
        )
    }

    /// Install a per-corner shape on the native `UIVisualEffectView` host of
    /// `UIGlassEffect`. Use this instead of a CAShapeLayer mask when the
    /// outline needs different top/bottom radii — the layer mask clips the
    /// interactive elastic deformation so the glass feels stiff, while
    /// `cornerConfiguration` participates in the native shape pipeline and
    /// leaves the effect free to "float" inside its rounded outline.
    /// No-op on iOS < 26 (no native glass).
    /// True when a caller has installed a custom `cornerConfiguration` on
    /// the native glass view. Tracked separately from `nativeView.cornerConfiguration`
    /// because the latter is `nonnull` (always returns a default), so we
    /// can't tell "shape configured" from "default" without a flag.
    private var hasCustomNativeCornerConfiguration: Bool = false

    @available(iOS 26.0, *)
    public func setNativeCornerConfiguration(_ configuration: UICornerConfiguration) {
        guard let nativeView else { return }
        nativeView.cornerConfiguration = configuration
        hasCustomNativeCornerConfiguration = true
        // Drop any prior cornerRadius/masksToBounds — `cornerConfiguration`
        // is the source of truth from now on, and a leftover `masksToBounds`
        // would re-introduce the deformation clipping we're trying to avoid.
        nativeView.layer.masksToBounds = false
        nativeView.layer.cornerRadius = 0.0
        nativeViewShape = nil
    }

    @available(iOS 26.0, *)
    public func setNativeUniformCornerRadius(_ radius: CGFloat) {
        setNativeCornerConfiguration(.uniformCorners(radius: .fixed(radius)))
    }

    /// Remembers the last `cornerRadius`, `tintColor`, `isInteractive`,
    /// `isVisible` the caller passed to `update(...)`. Referenced by
    /// `traitCollectionDidChange` and `layoutSubviews` to rebuild params.
    private struct UpdateMemo {
        let size: CGSize
        let cornerRadiusSource: CornerRadiusSource
        let tintColor: TintColor
        let isInteractive: Bool
        let isVisible: Bool
        let layoutConfigurationRevision: Int

        var cornerRadius: CGFloat {
            cornerRadiusSource.resolved(for: size)
        }
    }
    private var lastUpdateMemo: UpdateMemo?
    private var layoutConfigurationRevision: Int = 0
    /// While a gesture/property animator owns the surface, layout must not
    /// route every bounds sample through `applyUpdate`: the legacy branch of
    /// that method regenerates stretchable artwork when the radius changes.
    /// This override keeps the material instance stable and updates only
    /// lightweight geometry until the coordinator commits an endpoint.
    private var interactiveGeometryOverride: (size: CGSize, cornerRadius: CGFloat)?
    private var _transitionMaterialAlpha: CGFloat = 1

    /// Native settle animations are compositor-owned. While this is true,
    /// `layoutSubviews` and the display-link delegate must not rewrite child
    /// frames/corners: doing so wakes `UIVisualEffectView` layout at 120 Hz and
    /// defeats the outer surface's otherwise smooth Core Animation track.
    private var hasTransitionCompositorSettleTrack = false
    private var transitionCompositorSettleOwner: ObjectIdentifier?
    private var pendingTransitionCompositorOwner: ObjectIdentifier?
    internal private(set) var transitionCompositorSettleTrackForTesting:
        GlassBackgroundCompositorSettleTrack?
    internal private(set) var transitionDirectGeometryUpdateCountForTesting = 0
    internal private(set) var transitionCompositorCaptureCountForTesting = 0
    internal private(set) var transitionCompositorTrackedLayerCountForTesting = 0
    private var pendingTransitionCompositorGeometry: [
        ObjectIdentifier: TransitionLayerGeometry
    ] = [:]
    private var pendingTransitionCompositorMaterialAlpha: CGFloat?

    private struct TransitionLayerGeometry {
        var position: CGPoint
        var bounds: CGRect
        var cornerRadius: CGFloat

        init(layer: CALayer) {
            position = layer.position
            bounds = layer.bounds
            cornerRadius = layer.cornerRadius
        }

        init(frame: CGRect, cornerRadius: CGFloat) {
            position = CGPoint(x: frame.midX, y: frame.midY)
            bounds = CGRect(origin: .zero, size: frame.size)
            self.cornerRadius = cornerRadius
        }

        func corrected(
            from desiredOrigin: TransitionLayerGeometry,
            capturedOrigin: TransitionLayerGeometry,
            weight: CGFloat
        ) -> TransitionLayerGeometry {
            let weight = min(max(weight, 0), 1)
            return TransitionLayerGeometry(
                position: CGPoint(
                    x: position.x
                        + (capturedOrigin.position.x - desiredOrigin.position.x) * weight,
                    y: position.y
                        + (capturedOrigin.position.y - desiredOrigin.position.y) * weight
                ),
                bounds: CGRect(
                    x: bounds.origin.x
                        + (capturedOrigin.bounds.origin.x - desiredOrigin.bounds.origin.x) * weight,
                    y: bounds.origin.y
                        + (capturedOrigin.bounds.origin.y - desiredOrigin.bounds.origin.y) * weight,
                    width: bounds.width
                        + (capturedOrigin.bounds.width - desiredOrigin.bounds.width) * weight,
                    height: bounds.height
                        + (capturedOrigin.bounds.height - desiredOrigin.bounds.height) * weight
                ),
                cornerRadius: cornerRadius
                    + (capturedOrigin.cornerRadius - desiredOrigin.cornerRadius) * weight
            )
        }

        private init(
            position: CGPoint,
            bounds: CGRect,
            cornerRadius: CGFloat
        ) {
            self.position = position
            self.bounds = bounds
            self.cornerRadius = cornerRadius
        }
    }

    /// Synthetic-stroke paths are geometry-only. Keeping their resolved input
    /// prevents duplicate layout/display-link samples from rebuilding the same
    /// CGPath, while changed interactive geometry still updates immediately.
    private struct SyntheticStrokePathGeometry: Equatable {
        let bounds: CGRect
        let cornerRadius: CGFloat
        let lineWidth: CGFloat
    }
    private var syntheticStrokePathGeometry: SyntheticStrokePathGeometry?
    internal private(set) var syntheticStrokePathUpdateCount: Int = 0

    private struct LayoutConfiguration {
        let cornerRadiusSource: CornerRadiusSource
        let tintColor: TintColor
        let isInteractive: Bool
        let isVisible: Bool
    }

    // Legacy back-compat: expose GlassParams for callers that read it.
    public var glassParams: GlassParams? {
        guard let params else { return nil }
        switch params.shape {
        case let .roundedRect(cornerRadius):
            return GlassParams(cornerRadius: cornerRadius, keepRoundedCorners: true)
        }
    }

    private var allowsBackgroundHitTesting: Bool {
        params.map { $0.isInteractive && $0.isVisible } ?? glassIsInteractive
    }

    private func invalidateLayoutConfiguration() {
        layoutConfigurationRevision += 1
        setNeedsLayout()
    }

    @discardableResult
    private func reapplyLastUpdate(transition: ContainedViewLayoutTransition = .immediate) -> Bool {
        guard let memo = lastUpdateMemo else {
            return false
        }
        applyUpdate(
            size: memo.size,
            cornerRadiusSource: memo.cornerRadiusSource,
            isDark: resolvedIsDark,
            tintColor: memo.tintColor,
            isInteractive: memo.isInteractive,
            isVisible: memo.isVisible,
            transition: transition
        )
        return true
    }

    private func layoutConfiguration(for size: CGSize) -> LayoutConfiguration {
        if let memo = lastUpdateMemo, memo.layoutConfigurationRevision == layoutConfigurationRevision {
            return LayoutConfiguration(
                cornerRadiusSource: memo.cornerRadiusSource,
                tintColor: memo.tintColor,
                isInteractive: memo.isInteractive,
                isVisible: memo.isVisible
            )
        }

        return LayoutConfiguration(
            cornerRadiusSource: glassCornerRadius.map(CornerRadiusSource.fixed) ?? .capsule,
            tintColor: glassTintColor,
            isInteractive: glassIsInteractive,
            isVisible: lastUpdateMemo?.isVisible ?? true
        )
    }

    // MARK: Init

    public init(
        style: Style = .regular,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.style = style
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style

        self.maskContainerView = UIView()
        self.maskContainerView.backgroundColor = .white
        self.maskContainerView.clipsToBounds = true

        self.maskContentView = UIView()
        self.maskContainerView.addSubview(self.maskContentView)

        self.publicContentContainer = GlassContentContainer(maskContentView: self.maskContentView)
        // The glass renderer owns the material shape. UIKit's native glass
        // can temporarily inscribe its content region down to zero height for
        // a short capsule; clipping this public host would then cut off both
        // the Mini controls and their hit area even though their model frame
        // remains correct.
        self.publicContentContainer.clipsToBounds = false
        self.publicContentContainer.layer.cornerCurve = .continuous
        self.contentContainer = GlassContentContainer(maskContentView: self.maskContentView)
        self.contentContainer.clipsToBounds = true
        self.contentContainer.layer.cornerCurve = .continuous

        super.init(frame: .zero)

        clipsToBounds = false
        // NOTE: interaction MUST stay enabled so buttons / controls nested
        // inside `contentView` can receive taps. `hitTest` below explicitly
        // filters out the background itself — the glass surface only reports
        // an interactive hit when a child (a real button) claims the touch.
        isUserInteractionEnabled = true
        addSubview(publicContentContainer)
        addSubview(contentContainer)
        syntheticStrokeLayer.fillColor = UIColor.clear.cgColor
        syntheticStrokeLayer.isHidden = true
        installRenderer(for: appliedAppearanceStyle)
        AetherAppearanceConsumerRegistry.register(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceTransparencyStatusDidChange),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func reduceTransparencyStatusDidChange() {
        guard appliedAppearanceStyle == .legacy else { return }
        #if DEBUG
        reduceTransparencyRefreshCountForTesting += 1
        #endif
        if !reapplyLastUpdate() {
            setNeedsLayout()
        }
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let resolvedStyle = appearanceStyleOverride ?? appearance.style
        guard appliedAppearanceStyle != resolvedStyle else {
            if resolvedStyle == .legacy {
                setNeedsLayout()
            }
            return
        }

        appliedAppearanceStyle = resolvedStyle
        installRenderer(for: resolvedStyle)
        if !reapplyLastUpdate() {
            setNeedsLayout()
        }

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        let rendererView = nativeParamsView ?? legacyView ?? plainSurfaceView
        let targetMaterialAlpha = (params?.isVisible ?? true)
            ? _transitionMaterialAlpha
            : 0.0
        guard targetMaterialAlpha > 0.001 else {
            rendererView?.alpha = 0.0
            return
        }
        rendererView?.alpha = 0
        UIView.animate(
            withDuration: AetherLegacySurfaceTokens
                .resolve(role: surfaceRole, traitCollection: traitCollection)
                .animationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            rendererView?.alpha = targetMaterialAlpha
        }
    }

    private func installRenderer(for appearanceStyle: AetherAppearanceStyle) {
        _ = cancelTransitionCompositorSettleTrack(capturingPresentation: false)
        pendingTransitionCompositorGeometry.removeAll(keepingCapacity: false)
        pendingTransitionCompositorMaterialAlpha = nil
        pendingTransitionCompositorOwner = nil
        interactiveGeometryOverride = nil
        hasTransitionCompositorSettleTrack = false
        transitionCompositorSettleOwner = nil
        transitionCompositorSettleTrackForTesting = nil
        transitionCompositorTrackedLayerCountForTesting = 0
        nativeView?.effect = nil
        legacyMaterialView?.effect = nil

        layer.removeAllAnimations()
        nativeParamsView?.layer.removeAllAnimations()
        nativeView?.layer.removeAllAnimations()
        legacyView?.layer.removeAllAnimations()
        legacyHighlightContainerView?.layer.removeAllAnimations()
        foregroundNode?.layer.removeAllAnimations()
        shadowNode?.layer.removeAllAnimations()
        syntheticStrokeLayer.removeAllAnimations()
        syntheticStrokeLayer.removeFromSuperlayer()

        innerBackgroundView?.removeFromSuperview()
        innerBackgroundView = nil
        nativeParamsView?.removeFromSuperview()
        nativeView?.removeFromSuperview()
        legacyView?.removeFromSuperview()
        legacyHighlightContainerView?.removeFromSuperview()
        foregroundNode?.view.removeFromSuperview()
        shadowNode?.view.removeFromSuperview()
        legacyMaterialView?.removeFromSuperview()
        plainSurfaceView?.removeFromSuperview()
        publicContentContainer.removeFromSuperview()

        nativeView = nil
        nativeParamsView = nil
        nativeViewShape = nil
        legacyView = nil
        legacyHighlightContainerView = nil
        foregroundNode = nil
        shadowNode = nil
        legacyMaterialView = nil
        legacyBlurStyle = nil
        plainSurfaceView = nil
        params = nil
        hasCustomNativeCornerConfiguration = false
        transitionMaterialInteractionEnabled = appearanceStyle.usesLiquidGlass
        contentContainer.passesUnclaimedTouchesThrough = false
        maskContainerView.layer.filters = nil

        if appearanceStyle == .legacy {
            let tokens = AetherLegacySurfaceTokens.resolve(
                role: surfaceRole,
                traitCollection: traitCollection
            )
            let plain = UIView()
            plain.isUserInteractionEnabled = false
            plain.layer.cornerCurve = .continuous
            plainSurfaceView = plain
            if legacyUsesBlurMaterial {
                let blurStyle = legacyBlurStyleOverride
                    ?? tokens.blurStyle
                    ?? .systemChromeMaterial
                let material = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
                material.isUserInteractionEnabled = false
                material.clipsToBounds = true
                material.aetherApplyBackdropGroupingIdentifier(
                    legacyBackdropGroupingIdentifier
                )
                plain.addSubview(material)
                legacyMaterialView = material
                legacyBlurStyle = blurStyle
            }
            insertSubview(plain, belowSubview: contentContainer)
            insertSubview(publicContentContainer, belowSubview: contentContainer)
            layer.addSublayer(syntheticStrokeLayer)
            syntheticStrokeLayer.isHidden = true
            return
        }

        let useNative = !GlassBackgroundView.useCustomGlassImpl
            && GlassCompatibility.isLiquidDesignAvailable
        if useNative, #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = glassIsInteractive
            let native = UIVisualEffectView(effect: effect)
            native.contentView.clipsToBounds = false
            nativeView = native

            let paramsView = EffectSettingsContainerView(frame: .zero)
            nativeParamsView = paramsView
            paramsView.addSubview(native)
            insertSubview(paramsView, belowSubview: contentContainer)
            native.contentView.addSubview(publicContentContainer)
            native.layer.addSublayer(syntheticStrokeLayer)
        } else {
            if let filter = CALayer.aetherAlphaMaskFilter() {
                maskContainerView.layer.filters = [filter]
            }
            let backdrop = LegacyGlassBackdropView(frame: .zero)
            legacyView = backdrop

            let highlight = UIView()
            highlight.isUserInteractionEnabled = false
            highlight.clipsToBounds = true
            legacyHighlightContainerView = highlight

            let foreground = ASImageNode()
            foreground.contentMode = .scaleToFill
            foreground.view.isUserInteractionEnabled = false
            foregroundNode = foreground

            let shadow = ASImageNode()
            shadow.contentMode = .scaleToFill
            shadow.view.isUserInteractionEnabled = false
            shadowNode = shadow

            insertSubview(shadow.view, belowSubview: contentContainer)
            insertSubview(backdrop, belowSubview: contentContainer)
            insertSubview(foreground.view, belowSubview: contentContainer)
            foreground.view.mask = maskContainerView
            addSubview(highlight)
            insertSubview(publicContentContainer, belowSubview: contentContainer)
            bringSubviewToFront(contentContainer)
            layer.addSublayer(syntheticStrokeLayer)
        }
        syntheticStrokeLayer.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        foregroundNode?.view.removeFromSuperview()
        shadowNode?.view.removeFromSuperview()
    }

    // MARK: Auto-layout
    //
    // GlassBackgroundView can be used two ways:
    //
    //   1. **Explicit** — caller drives everything via `update(...)`. The
    //      memo stored there is what `layoutSubviews` re-applies when
    //      bounds change.
    //
    //   2. **Property-based** — caller sets `glassCornerRadius` /
    //      `glassTintColor` / `glassIsInteractive` on the view (or leaves
    //      them at defaults) and lets the normal UIView layout cycle do
    //      the rest. `layoutSubviews` picks up the current bounds and
    //      re-renders. No explicit `update(...)` call required.
    //
    // Both work side-by-side; an explicit `update(...)` wins over the
    // property defaults (it writes its values into the memo which
    // `layoutSubviews` consults first).

    // MARK: Trait tracking

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if appliedAppearanceStyle == .legacy {
            _ = reapplyLastUpdate()
            return
        }
        guard tracksTraitCollection, lastUpdateMemo != nil else { return }
        // Skip when `isDarkOverride` is pinned — trait changes don't matter
        // then, the override is the source of truth.
        if isDarkOverride != nil { return }
        // Only re-apply if the resolved dark/light style actually changed —
        // avoids unnecessary redraws on e.g. content size category changes.
        let previousStyle = previousTraitCollection?.userInterfaceStyle
        if previousStyle == traitCollection.userInterfaceStyle { return }
        reapplyLastUpdate()
    }

    // MARK: Hit testing

    /// UIKit normally routes touches through a property animator's
    /// presentation geometry. This custom `hitTest` performs a second manual
    /// descent into the glass hierarchy, so its incoming model-local point has
    /// to be remapped into the moving layer's presentation-local coordinates.
    /// Without that remap a collapsing surface cannot be caught where it is
    /// visibly drawn, while an expanding surface can expose an invisible
    /// full-size hit region from its already-committed model layer.
    private func presentationHitTestPoint(_ point: CGPoint) -> CGPoint {
        guard layer.animationKeys()?.isEmpty == false,
              let presentation = layer.presentation(),
              let modelSuperlayer = layer.superlayer,
              let presentationSuperlayer = presentation.superlayer else {
            return point
        }

        let pointInSuperlayer = layer.convert(point, to: modelSuperlayer)
        return presentation.convert(
            pointInSuperlayer,
            from: presentationSuperlayer
        )
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }
        let point = presentationHitTestPoint(point)
        if let result = contentContainer.hitTest(
            self.convert(point, to: contentContainer),
            with: event
        ) {
            return result
        }
        if let result = publicContentContainer.hitTest(
            self.convert(point, to: publicContentContainer),
            with: event
        ) {
            return result
        }
        // `point` has already been remapped into presentation-local
        // coordinates above. During a settle the model bounds are committed to
        // the endpoint before the compositor finishes drawing the moving
        // surface, so testing `UIView.point(inside:)` here can reject a catch
        // touch that is visibly inside the presentation layer but outside the
        // compact model bounds. Keep that touch on the wrapper instead of
        // letting it arm the reused native material mid-transition.
        let interactionBounds = layer.presentation()?.bounds ?? layer.bounds
        if !transitionMaterialInteractionEnabled,
           interactionBounds.contains(point) {
            return self
        }
        if let nativeView {
            // Liquid Glass lays out `_UIVisualEffectContentView` as the
            // capsule's inscribed safe-content rect. For a short pill that
            // rect can legitimately have zero height even though direct
            // children draw beyond it with clipping disabled. UIKit's normal
            // descent then rejects those visible controls at `point(inside:)`.
            // Descend into the public content view's direct children first so
            // real glass content keeps its full visual hit region while
            // remaining an actual child of `contentView`.
            for contentSubview in nativeView.contentView.subviews.reversed() {
                if let result = contentSubview.hitTest(
                    self.convert(point, to: contentSubview),
                    with: event
                ) {
                    return result
                }
            }
            if let result = nativeView.hitTest(self.convert(point, to: nativeView), with: event) {
                return result
            }
            // When the surface is marked interactive, route in-bounds
            // "background" touches (i.e. touches that didn't land on a
            // `contentView` child) to the `UIVisualEffectView` itself.
            // iOS 26's `UIGlassEffect.isInteractive` deformation needs
            // the visual-effect view to receive the touch in order to
            // track finger position and play the liquid warp; the
            // default `UIVisualEffectView.hitTest` returns nil for
            // background touches, so without this the glass never sees
            // them and stays static. Parent gesture recognizers (a
            // search-bar tap, a segment-control scrub) still fire as
            // expected — recognizers walk the ancestor chain regardless
            // of which descendant the hit-test returned.
            if allowsBackgroundHitTesting, self.point(inside: point, with: event) {
                return nativeView
            }
            return nil
        }
        return nil
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        // The model hierarchy is already at the settle endpoint and the
        // presentation hierarchy is moving on a synchronized CA track. A
        // UIKit layout pass here would rewrite every child layer mid-flight.
        if hasTransitionCompositorSettleTrack {
            return
        }

        if let geometry = interactiveGeometryOverride {
            applyInteractiveGeometry(
                size: geometry.size,
                cornerRadius: geometry.cornerRadius
            )
            return
        }

        // Auto-apply on layout if the caller hasn't driven it explicitly via
        // `update(...)` yet, OR the bounds changed since the last update.
        // Lets clients use GlassBackgroundView as a plain auto-layout view
        // without having to manually call `update(size:cornerRadius:...)`
        // on each layout pass.
        let size = bounds.size
        if size.width > 0, size.height > 0 {
            let configuration = layoutConfiguration(for: size)
            applyUpdate(
                size: size,
                cornerRadiusSource: configuration.cornerRadiusSource,
                isDark: resolvedIsDark,
                tintColor: configuration.tintColor,
                isInteractive: configuration.isInteractive,
                isVisible: configuration.isVisible,
                transition: .immediate
            )
        }

        if let params {
            switch params.shape {
            case let .roundedRect(cornerRadius):
                innerBackgroundView?.layer.cornerRadius = max(0.0, cornerRadius - params.tintColor.innerInset)
            }
        }
    }

    // MARK: Interactive geometry

    /// Starts a geometry-only update session. The glass effect, tint, filter
    /// hierarchy, and generated legacy assets remain alive for the duration.
    /// `AetherTabBarController` uses this for its interruptible accessory
    /// morph; regular clients should continue to call `update(...)`.
    internal func beginInteractiveGeometryUpdates() {
        captureTransitionCompositorPresentation()
        if interactiveGeometryOverride == nil {
            let radius = lastUpdateMemo?.cornerRadius
                ?? glassCornerRadius
                ?? bounds.height / 2.0
            interactiveGeometryOverride = (bounds.size, radius)
        }
    }

    /// Applies one display-link sample without creating implicit animations or
    /// rebuilding the material hierarchy.
    internal func updateInteractiveGeometry(
        size: CGSize,
        cornerRadius: CGFloat
    ) {
        guard !hasTransitionCompositorSettleTrack else { return }
        pendingTransitionCompositorGeometry.removeAll(keepingCapacity: true)
        pendingTransitionCompositorMaterialAlpha = nil
        pendingTransitionCompositorOwner = nil
        transitionDirectGeometryUpdateCountForTesting += 1
        let geometry = (
            size: CGSize(width: max(0, size.width), height: max(0, size.height)),
            cornerRadius: max(0, cornerRadius)
        )
        interactiveGeometryOverride = geometry
        applyInteractiveGeometry(
            size: geometry.size,
            cornerRadius: geometry.cornerRadius
        )
    }

    /// Commits the final geometry through the normal update path once. This
    /// refreshes endpoint-specific stretchable assets without paying that cost
    /// on every interactive frame.
    internal func endInteractiveGeometryUpdates(
        size: CGSize,
        cornerRadius: CGFloat
    ) {
        cancelTransitionCompositorSettleTrack(capturingPresentation: false)
        pendingTransitionCompositorGeometry.removeAll(keepingCapacity: true)
        pendingTransitionCompositorMaterialAlpha = nil
        pendingTransitionCompositorOwner = nil
        interactiveGeometryOverride = nil
        let configuration = layoutConfiguration(for: size)
        applyUpdate(
            size: size,
            cornerRadiusSource: .fixed(max(0, cornerRadius)),
            isDark: resolvedIsDark,
            tintColor: configuration.tintColor,
            isInteractive: configuration.isInteractive,
            isVisible: configuration.isVisible,
            transition: .immediate
        )

    }

    /// Captures every native child from its presentation layer before a
    /// retarget removes the old groups. The next track therefore starts from
    /// the exact visible material, not from the previously committed endpoint.
    @discardableResult
    internal func captureTransitionCompositorPresentation(
        owner: ObjectIdentifier? = nil
    ) -> Bool {
        cancelTransitionCompositorSettleTrack(
            capturingPresentation: true,
            owner: owner
        )
    }

    /// A captured settle may be retargeted into Reduce Motion, which has no
    /// native child compositor track by design. Let its display-link/direct
    /// handoff take ownership immediately instead of preserving a pending
    /// compositor origin that will never be consumed.
    @discardableResult
    internal func discardPendingTransitionCompositorPresentation(
        owner: ObjectIdentifier? = nil
    ) -> Bool {
        if let owner {
            guard owner == pendingTransitionCompositorOwner else {
                return false
            }
        }
        let hadPendingPresentation = pendingTransitionCompositorOwner != nil
            || !pendingTransitionCompositorGeometry.isEmpty
            || pendingTransitionCompositorMaterialAlpha != nil
        pendingTransitionCompositorGeometry.removeAll(keepingCapacity: true)
        pendingTransitionCompositorMaterialAlpha = nil
        pendingTransitionCompositorOwner = nil
        return hadPendingPresentation
    }

    /// Releases compositor ownership after the shared clock reaches its
    /// endpoint. Model layers were committed before installation, so cleanup
    /// removes only animation metadata/groups and performs no extra layout.
    @discardableResult
    internal func completeTransitionCompositorSettleTrack(
        owner: ObjectIdentifier? = nil
    ) -> Bool {
        let completed = cancelTransitionCompositorSettleTrack(
            capturingPresentation: false,
            owner: owner
        )
        let discarded = discardPendingTransitionCompositorPresentation(
            owner: owner
        )
        return completed || discarded
    }

    /// Installs the native material hierarchy on the exact same compositor
    /// clock as the accessory surface. Interactive/legacy paths intentionally
    /// never enter this method and continue to use direct geometry updates.
    internal func installTransitionCompositorSettleTrack(
        _ track: GlassBackgroundCompositorSettleTrack
    ) {
        guard track.isValid,
              let nativeParamsView,
              let nativeView else {
            cancelTransitionCompositorSettleTrack(capturingPresentation: true)
            pendingTransitionCompositorGeometry.removeAll(keepingCapacity: true)
            pendingTransitionCompositorMaterialAlpha = nil
            pendingTransitionCompositorOwner = nil
            return
        }

        if hasTransitionCompositorSettleTrack {
            captureTransitionCompositorPresentation()
        }
        // Installing a new track is an explicit ownership transfer. Preserve
        // any presentation geometry captured from the previous generation,
        // but bind that handoff to the new coordinator before it is consumed.
        pendingTransitionCompositorOwner = track.owner

        let localFrames = track.sizes.map {
            CGRect(origin: .zero, size: $0)
        }
        let surfaceSamples = zip(localFrames, track.cornerRadii).map {
            TransitionLayerGeometry(frame: $0.0, cornerRadius: $0.1)
        }
        let frameOnlySamples = localFrames.map {
            TransitionLayerGeometry(frame: $0, cornerRadius: 0)
        }
        let materialIsVisible = params?.isVisible ?? true
        let materialValues = track.materialAlphaValues.map {
            materialIsVisible ? min(max($0, 0), 1) : 0
        }

        var installedLayerCount = 0
        if installTransitionCompositorLayerTrack(
            on: nativeParamsView.layer,
            samples: frameOnlySamples,
            opacityValues: materialValues,
            includesCornerRadius: false,
            track: track
        ) {
            installedLayerCount += 1
        }
        if installTransitionCompositorLayerTrack(
            on: nativeView.layer,
            samples: surfaceSamples,
            includesCornerRadius: !hasCustomNativeCornerConfiguration,
            track: track
        ) {
            installedLayerCount += 1
        }
        if installTransitionCompositorLayerTrack(
            on: contentContainer.layer,
            samples: surfaceSamples,
            includesCornerRadius: true,
            track: track
        ) {
            installedLayerCount += 1
        }

        // The mask hierarchy is normally active only on the legacy renderer,
        // but custom native appearances may attach it. Track it only when it
        // participates in the render tree; detached mask layers need no clock.
        let maskIsActive = maskContainerView.layer.superlayer != nil
            || foregroundNode?.view.mask === maskContainerView
        if maskIsActive {
            let shadowInset = Self.legacyShadowInset
            let maskContainerSamples = track.sizes.map {
                TransitionLayerGeometry(
                    frame: CGRect(
                        origin: .zero,
                        size: CGSize(
                            width: $0.width + shadowInset * 2,
                            height: $0.height + shadowInset * 2
                        )
                    ),
                    cornerRadius: 0
                )
            }
            let maskContentSamples = track.sizes.map {
                TransitionLayerGeometry(
                    frame: CGRect(
                        x: shadowInset,
                        y: shadowInset,
                        width: $0.width,
                        height: $0.height
                    ),
                    cornerRadius: 0
                )
            }
            if installTransitionCompositorLayerTrack(
                on: maskContainerView.layer,
                samples: maskContainerSamples,
                includesCornerRadius: false,
                track: track
            ) {
                installedLayerCount += 1
            }
            if installTransitionCompositorLayerTrack(
                on: maskContentView.layer,
                samples: maskContentSamples,
                includesCornerRadius: false,
                track: track
            ) {
                installedLayerCount += 1
            }
        }

        if let innerBackgroundView, let params {
            let inset = params.tintColor.innerInset
            let innerSamples = track.sizes.map { size in
                let frame = CGRect(origin: .zero, size: size)
                    .insetBy(dx: inset, dy: inset)
                return TransitionLayerGeometry(
                    frame: frame,
                    cornerRadius: max(0, min(frame.width, frame.height) / 2)
                )
            }
            if installTransitionCompositorLayerTrack(
                on: innerBackgroundView.layer,
                samples: innerSamples,
                includesCornerRadius: true,
                track: track
            ) {
                installedLayerCount += 1
            }
        }

        // iOS 26 may use Aether's synthetic outline under the native effect.
        // Its path is geometry-dependent, so leaving it at the release size
        // while the native hosts resize produces a stationary outline and an
        // endpoint pop. iOS 27 normally hides it and pays no extra work.
        if !syntheticStrokeLayer.isHidden,
           installTransitionCompositorStrokeTrack(
                track,
                on: syntheticStrokeLayer
           ) {
            installedLayerCount += 1
        }

        guard installedLayerCount >= 3 else {
            cancelTransitionCompositorSettleTrack(capturingPresentation: true)
            return
        }
        _transitionMaterialAlpha = min(
            max(track.materialAlphaValues.last ?? 1, 0),
            1
        )
        nativeViewShape = .roundedRect(
            cornerRadius: track.cornerRadii.last ?? 0
        )
        if let size = track.sizes.last,
           let cornerRadius = track.cornerRadii.last {
            interactiveGeometryOverride = (size, cornerRadius)
        }
        transitionCompositorSettleTrackForTesting = track
        transitionCompositorTrackedLayerCountForTesting = installedLayerCount
        transitionCompositorSettleOwner = track.owner
        hasTransitionCompositorSettleTrack = true
        pendingTransitionCompositorGeometry.removeAll(keepingCapacity: true)
        pendingTransitionCompositorMaterialAlpha = nil
        pendingTransitionCompositorOwner = nil
    }

    @discardableResult
    private func installTransitionCompositorLayerTrack(
        on layer: CALayer,
        samples desiredSamples: [TransitionLayerGeometry],
        opacityValues desiredOpacityValues: [CGFloat]? = nil,
        includesCornerRadius: Bool,
        track: GlassBackgroundCompositorSettleTrack
    ) -> Bool {
        guard desiredSamples.count == track.keyTimes.count,
              desiredOpacityValues == nil
                || desiredOpacityValues?.count == track.keyTimes.count,
              let desiredOrigin = desiredSamples.first,
              let desiredTarget = desiredSamples.last else {
            return false
        }

        let capturedOrigin = pendingTransitionCompositorGeometry[
            ObjectIdentifier(layer)
        ] ?? TransitionLayerGeometry(layer: layer.presentation() ?? layer)
        let capturedOpacity: CGFloat
        if layer === nativeParamsView?.layer,
           let pendingTransitionCompositorMaterialAlpha {
            capturedOpacity = pendingTransitionCompositorMaterialAlpha
        } else {
            capturedOpacity = CGFloat(
                layer.presentation()?.opacity ?? layer.opacity
            )
        }
        let handoffDuration = min(
            0.06,
            max(1.0 / 120.0, track.duration * 0.18)
        )
        var resolvedSamples: [TransitionLayerGeometry] = []
        resolvedSamples.reserveCapacity(desiredSamples.count)
        var resolvedOpacityValues: [NSNumber]? = desiredOpacityValues.map { _ in [] }
        resolvedOpacityValues?.reserveCapacity(desiredSamples.count)

        for index in desiredSamples.indices {
            let normalizedTime = CGFloat(truncating: track.keyTimes[index])
            let elapsed = TimeInterval(normalizedTime) * track.duration
            let correctionWeight = 1 - Self.transitionSmootherstep(
                CGFloat(elapsed / max(0.000_1, handoffDuration))
            )
            resolvedSamples.append(
                desiredSamples[index].corrected(
                    from: desiredOrigin,
                    capturedOrigin: capturedOrigin,
                    weight: correctionWeight
                )
            )
            if let desiredOpacityValues {
                let desiredOriginOpacity = desiredOpacityValues[0]
                let correctedOpacity = desiredOpacityValues[index]
                    + (capturedOpacity - desiredOriginOpacity) * correctionWeight
                resolvedOpacityValues?.append(
                    NSNumber(value: min(max(correctedOpacity, 0), 1))
                )
            }
        }

        let position = Self.transitionKeyframeAnimation(
            keyPath: "position",
            values: resolvedSamples.map { NSValue(cgPoint: $0.position) },
            track: track
        )
        let bounds = Self.transitionKeyframeAnimation(
            keyPath: "bounds",
            values: resolvedSamples.map { NSValue(cgRect: $0.bounds) },
            track: track
        )
        var animations: [CAAnimation] = [position, bounds]
        if includesCornerRadius {
            animations.append(
                Self.transitionKeyframeAnimation(
                    keyPath: "cornerRadius",
                    values: resolvedSamples.map {
                        NSNumber(value: $0.cornerRadius)
                    },
                    track: track
                )
            )
        }
        if let resolvedOpacityValues {
            animations.append(
                Self.transitionKeyframeAnimation(
                    keyPath: "opacity",
                    values: resolvedOpacityValues,
                    track: track
                )
            )
        }

        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = track.duration
        group.beginTime = layer.convertTime(track.mediaBeginTime, from: nil)
        group.isRemovedOnCompletion = true
        group.preferredFrameRateRange = track.preferredFrameRateRange

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = desiredTarget.position
        layer.bounds = desiredTarget.bounds
        if includesCornerRadius {
            layer.cornerRadius = desiredTarget.cornerRadius
        }
        if let desiredOpacityValues {
            layer.opacity = Float(
                min(max(desiredOpacityValues.last ?? 1, 0), 1)
            )
        }
        CATransaction.commit()
        layer.add(
            group,
            forKey: Self.transitionCompositorSettleAnimationKey
        )
        return true
    }

    @discardableResult
    private func installTransitionCompositorStrokeTrack(
        _ track: GlassBackgroundCompositorSettleTrack,
        on layer: CAShapeLayer
    ) -> Bool {
        guard track.sizes.count == track.keyTimes.count,
              track.cornerRadii.count == track.keyTimes.count,
              let desiredOriginSize = track.sizes.first,
              let desiredTargetSize = track.sizes.last,
              let desiredTargetCornerRadius = track.cornerRadii.last else {
            return false
        }

        let desiredOrigin = TransitionLayerGeometry(
            frame: CGRect(origin: .zero, size: desiredOriginSize),
            cornerRadius: 0
        )
        let capturedOrigin = pendingTransitionCompositorGeometry[
            ObjectIdentifier(layer)
        ] ?? TransitionLayerGeometry(layer: layer.presentation() ?? layer)
        let capturedNativeGeometry: TransitionLayerGeometry?
        if let nativeView {
            capturedNativeGeometry = pendingTransitionCompositorGeometry[
                ObjectIdentifier(nativeView.layer)
            ]
        } else {
            capturedNativeGeometry = nil
        }
        let capturedCornerRadius = capturedNativeGeometry?.cornerRadius
            ?? track.cornerRadii[0]
        let handoffDuration = min(
            0.06,
            max(1.0 / 120.0, track.duration * 0.18)
        )
        let lineWidth = max(0, layer.lineWidth)
        var resolvedSamples: [TransitionLayerGeometry] = []
        var resolvedPaths: [CGPath] = []
        resolvedSamples.reserveCapacity(track.keyTimes.count)
        resolvedPaths.reserveCapacity(track.keyTimes.count)

        for index in track.keyTimes.indices {
            let normalizedTime = CGFloat(truncating: track.keyTimes[index])
            let elapsed = TimeInterval(normalizedTime) * track.duration
            let correctionWeight = 1 - Self.transitionSmootherstep(
                CGFloat(elapsed / max(0.000_1, handoffDuration))
            )
            let desired = TransitionLayerGeometry(
                frame: CGRect(origin: .zero, size: track.sizes[index]),
                cornerRadius: 0
            )
            let resolved = desired.corrected(
                from: desiredOrigin,
                capturedOrigin: capturedOrigin,
                weight: correctionWeight
            )
            let resolvedCornerRadius = track.cornerRadii[index]
                + (capturedCornerRadius - track.cornerRadii[0])
                    * correctionWeight
            let rect = CGRect(origin: .zero, size: resolved.bounds.size)
                .insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
            let pathRadius = min(
                max(0, resolvedCornerRadius - lineWidth * 0.5),
                max(0, min(rect.width, rect.height) * 0.5)
            )
            resolvedSamples.append(resolved)
            resolvedPaths.append(
                CGPath(
                    roundedRect: rect,
                    cornerWidth: pathRadius,
                    cornerHeight: pathRadius,
                    transform: nil
                )
            )
        }

        let position = Self.transitionKeyframeAnimation(
            keyPath: "position",
            values: resolvedSamples.map { NSValue(cgPoint: $0.position) },
            track: track
        )
        let bounds = Self.transitionKeyframeAnimation(
            keyPath: "bounds",
            values: resolvedSamples.map { NSValue(cgRect: $0.bounds) },
            track: track
        )
        let path = Self.transitionKeyframeAnimation(
            keyPath: "path",
            values: resolvedPaths.map { $0 as Any },
            track: track
        )
        let group = CAAnimationGroup()
        group.animations = [position, bounds, path]
        group.duration = track.duration
        group.beginTime = layer.convertTime(track.mediaBeginTime, from: nil)
        group.isRemovedOnCompletion = true
        group.preferredFrameRateRange = track.preferredFrameRateRange

        let targetFrame = CGRect(origin: .zero, size: desiredTargetSize)
        let targetRect = targetFrame.insetBy(
            dx: lineWidth * 0.5,
            dy: lineWidth * 0.5
        )
        let targetRadius = min(
            max(0, desiredTargetCornerRadius - lineWidth * 0.5),
            max(0, min(targetRect.width, targetRect.height) * 0.5)
        )
        let targetPath = CGPath(
            roundedRect: targetRect,
            cornerWidth: targetRadius,
            cornerHeight: targetRadius,
            transform: nil
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        layer.bounds = CGRect(origin: .zero, size: targetFrame.size)
        layer.path = targetPath
        syntheticStrokePathGeometry = SyntheticStrokePathGeometry(
            bounds: targetFrame,
            cornerRadius: targetRadius,
            lineWidth: lineWidth
        )
        CATransaction.commit()
        layer.add(
            group,
            forKey: Self.transitionCompositorSettleAnimationKey
        )
        return true
    }

    private static func transitionKeyframeAnimation(
        keyPath: String,
        values: [Any],
        track: GlassBackgroundCompositorSettleTrack
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = track.keyTimes
        animation.duration = track.duration
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = true
        animation.preferredFrameRateRange = track.preferredFrameRateRange
        return animation
    }

    private static func transitionSmootherstep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    @discardableResult
    private func cancelTransitionCompositorSettleTrack(
        capturingPresentation: Bool,
        owner requestedOwner: ObjectIdentifier? = nil
    ) -> Bool {
        guard hasTransitionCompositorSettleTrack else { return false }
        if let requestedOwner,
           requestedOwner != transitionCompositorSettleOwner {
            return false
        }
        let capturedOwner = transitionCompositorSettleOwner

        if capturingPresentation {
            pendingTransitionCompositorGeometry.removeAll(keepingCapacity: true)
            pendingTransitionCompositorMaterialAlpha = nil
            pendingTransitionCompositorOwner = capturedOwner
        }

        let layers = [
            nativeParamsView?.layer,
            nativeView?.layer,
            contentContainer.layer,
            maskContainerView.layer,
            maskContentView.layer,
            innerBackgroundView?.layer,
            syntheticStrokeLayer
        ].compactMap { $0 }
        var capturedSurfaceSize: CGSize?
        var capturedCornerRadius: CGFloat?
        var capturedMaterialAlpha: CGFloat?

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers {
            let presentation = capturingPresentation ? layer.presentation() : nil
            let sampledLayer = capturingPresentation
                ? (presentation ?? layer)
                : nil
            let geometry = sampledLayer.map(TransitionLayerGeometry.init(layer:))
            let opacity = sampledLayer?.opacity
            let shapePath = (sampledLayer as? CAShapeLayer)?.path
            layer.removeAnimation(
                forKey: Self.transitionCompositorSettleAnimationKey
            )
            if let geometry {
                pendingTransitionCompositorGeometry[
                    ObjectIdentifier(layer)
                ] = geometry
                layer.position = geometry.position
                layer.bounds = geometry.bounds
                layer.cornerRadius = geometry.cornerRadius
                layer.opacity = opacity ?? layer.opacity
                if let shapeLayer = layer as? CAShapeLayer,
                   let shapePath {
                    shapeLayer.path = shapePath
                }
                if layer === nativeParamsView?.layer {
                    capturedSurfaceSize = geometry.bounds.size
                    capturedMaterialAlpha = CGFloat(opacity ?? layer.opacity)
                    pendingTransitionCompositorMaterialAlpha =
                        CGFloat(opacity ?? layer.opacity)
                } else if layer === nativeView?.layer {
                    capturedCornerRadius = geometry.cornerRadius
                }
            }
        }
        CATransaction.commit()

        if capturingPresentation {
            transitionCompositorCaptureCountForTesting += 1
            if let capturedMaterialAlpha, capturedMaterialAlpha.isFinite {
                _transitionMaterialAlpha = min(max(capturedMaterialAlpha, 0), 1)
            }
            if let capturedSurfaceSize,
               let capturedCornerRadius,
               capturedSurfaceSize.width.isFinite,
               capturedSurfaceSize.height.isFinite,
               capturedCornerRadius.isFinite {
                interactiveGeometryOverride = (
                    capturedSurfaceSize,
                    max(0, capturedCornerRadius)
                )
                nativeViewShape = .roundedRect(
                    cornerRadius: max(0, capturedCornerRadius)
                )
            }
        }
        transitionCompositorSettleTrackForTesting = nil
        transitionCompositorTrackedLayerCountForTesting = 0
        transitionCompositorSettleOwner = nil
        hasTransitionCompositorSettleTrack = false
        return true
    }

    private func applyInteractiveGeometry(
        size: CGSize,
        cornerRadius: CGFloat
    ) {
        let localFrame = CGRect(origin: .zero, size: size)
        let shadowInset = Self.legacyShadowInset

        if appliedAppearanceStyle == .legacy {
            applyLegacySurface(
                size: size,
                cornerRadius: cornerRadius,
                tintColor: params?.tintColor ?? glassTintColor,
                isDark: params?.isDark ?? resolvedIsDark,
                isVisible: params?.isVisible ?? true,
                transition: .immediate
            )
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let nativeView {
            nativeViewShape = .roundedRect(cornerRadius: cornerRadius)
            nativeParamsView?.frame = localFrame
            nativeView.frame = localFrame
            if !hasCustomNativeCornerConfiguration {
                nativeView.layer.cornerRadius = cornerRadius
                nativeView.layer.masksToBounds = true
            }
        }

        legacyView?.updateInteractiveGeometry(
            size: size,
            cornerRadius: cornerRadius
        )
        legacyHighlightContainerView?.frame = localFrame
        legacyHighlightContainerView?.layer.cornerRadius = cornerRadius

        contentContainer.frame = localFrame
        contentContainer.layer.cornerRadius = cornerRadius
        publicContentContainer.frame = localFrame
        publicContentContainer.layer.cornerRadius = cornerRadius

        maskContainerView.frame = CGRect(
            origin: .zero,
            size: CGSize(
                width: size.width + shadowInset * 2.0,
                height: size.height + shadowInset * 2.0
            )
        )
        maskContentView.frame = CGRect(
            x: shadowInset,
            y: shadowInset,
            width: size.width,
            height: size.height
        )
        nativeParamsView?.frame = localFrame
        foregroundNode?.frame = localFrame.insetBy(
            dx: -shadowInset,
            dy: -shadowInset
        )
        shadowNode?.frame = localFrame.insetBy(
            dx: -shadowInset,
            dy: -shadowInset
        )

        if let params, let innerBackgroundView {
            let inset = params.tintColor.innerInset
            let innerFrame = localFrame.insetBy(dx: inset, dy: inset)
            innerBackgroundView.frame = innerFrame
            innerBackgroundView.layer.cornerRadius = max(
                0,
                min(innerFrame.width, innerFrame.height) / 2.0
            )
        }

        CATransaction.commit()
        updateSyntheticStroke(
            size: size,
            cornerRadius: cornerRadius,
            isVisible: params?.isVisible ?? true,
            transition: .immediate
        )
    }

    // MARK: Update

    /// Convenience wrapper. `isDark` is auto-derived — `isDarkOverride` wins
    /// when set, otherwise we fall back to `traitCollection.userInterfaceStyle`.
    /// Callers that share one `GlassBackgroundView(style: .regular)` config
    /// across multiple places get visually consistent glass this way; the
    /// previous `isDark: false` hard-code produced inconsistent tints when
    /// some call sites passed explicit `true` and others went through this
    /// short form.
    public func update(size: CGSize, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        // Honour `glassIsInteractive` here — callers set the property up
        // front and then drive the size/corner via this short form, so
        // hard-coding `false` would silently override their intent on every
        // layout pass.
        applyUpdate(
            size: size,
            cornerRadiusSource: .fixed(cornerRadius),
            isDark: resolvedIsDark,
            tintColor: .init(kind: .panel),
            isInteractive: glassIsInteractive,
            isVisible: true,
            transition: transition
        )
    }

    public func update(
        size: CGSize,
        cornerRadius: CGFloat,
        isDark: Bool,
        tintColor: TintColor,
        isInteractive: Bool = false,
        isVisible: Bool = true,
        transition: ContainedViewLayoutTransition
    ) {
        applyUpdate(
            size: size,
            cornerRadiusSource: .fixed(cornerRadius),
            isDark: isDark,
            tintColor: tintColor,
            isInteractive: isInteractive,
            isVisible: isVisible,
            transition: transition
        )
    }

    private func applyUpdate(
        size: CGSize,
        cornerRadiusSource: CornerRadiusSource,
        isDark: Bool,
        tintColor: TintColor,
        isInteractive: Bool,
        isVisible: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let cornerRadius = cornerRadiusSource.resolved(for: size)
        // Remember everything except `isDark` so `traitCollectionDidChange`
        // can rebuild the params with a fresh trait-derived isDark.
        self.lastUpdateMemo = UpdateMemo(
            size: size,
            cornerRadiusSource: cornerRadiusSource,
            tintColor: tintColor,
            isInteractive: isInteractive,
            isVisible: isVisible,
            layoutConfigurationRevision: layoutConfigurationRevision
        )
        let shape: Shape = .roundedRect(cornerRadius: cornerRadius)

        if appliedAppearanceStyle == .legacy {
            self.params = Params(
                shape: shape,
                isDark: isDark,
                tintColor: tintColor,
                isInteractive: isInteractive,
                isVisible: isVisible
            )
            applyLegacySurface(
                size: size,
                cornerRadius: cornerRadius,
                tintColor: tintColor,
                isDark: isDark,
                isVisible: isVisible,
                transition: transition
            )
            return
        }

        // Native UIGlassEffect pipeline
        if let nativeView, #available(iOS 26.0, *) {
            if nativeView.bounds.size != size || nativeViewShape != shape {
                nativeViewShape = shape
                // When the caller has installed a `cornerConfiguration` on
                // the native view (the modern way to round a glass surface),
                // we leave its shape alone — `masksToBounds=true` clips the
                // interactive elastic deformation inside a hard rounded rect
                // and visibly muffles the "floating" feel of the effect.
                if !hasCustomNativeCornerConfiguration {
                    transition.setCornerRadius(layer: nativeView.layer, cornerRadius: cornerRadius)
                    nativeView.layer.masksToBounds = true
                }
                if transition.isAnimated {
                    transition.animateView({ nativeView.frame = CGRect(origin: .zero, size: size) })
                } else {
                    nativeView.frame = CGRect(origin: .zero, size: size)
                }
            }
            // Apply the dark/light override only when it actually changes.
            // Setting it on every update made the glass briefly flicker
            // between styles during rapid layout passes (tab switches in
            // dark mode looked like a black\u2194white flash).
            let targetStyle: UIUserInterfaceStyle = isDark ? .dark : .light
            if nativeView.overrideUserInterfaceStyle != targetStyle {
                nativeView.overrideUserInterfaceStyle = targetStyle
            }
        }

        // Legacy backdrop-blur pipeline
        if let legacyView {
            let legacyStyle: LegacyGlassBackdropView.Style
            switch tintColor.kind {
            case .panel:
                legacyStyle = .normal
            case .clear:
                legacyStyle = .clear
            case let .custom(style, _):
                legacyStyle = style == .clear ? .clear : .normal
            }
            legacyView.update(size: size, cornerRadius: cornerRadius, style: legacyStyle, transition: transition)
            transition.setFrame(view: legacyView, frame: CGRect(origin: .zero, size: size))
            transition.setAlpha(view: legacyView, alpha: isVisible ? 1.0 : 0.0)

            transition.setPosition(view: contentView, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
            transition.setBounds(view: contentView, bounds: CGRect(origin: .zero, size: size))
        }

        if let legacyHighlightContainerView {
            transition.setFrame(view: legacyHighlightContainerView, frame: CGRect(origin: .zero, size: size))
            transition.setCornerRadius(layer: legacyHighlightContainerView.layer, cornerRadius: cornerRadius)
        }

        let shadowInset = Self.legacyShadowInset

        // Inner fill overlay
        if let innerColor = tintColor.innerColor {
            let innerFrame = CGRect(origin: .zero, size: size).insetBy(dx: tintColor.innerInset, dy: tintColor.innerInset)
            let innerRadius = min(innerFrame.width, innerFrame.height) * 0.5

            let innerView: UIView
            var innerTransition = transition
            var animateIn = false
            if let current = innerBackgroundView {
                innerView = current
            } else {
                innerView = UIView()
                innerBackgroundView = innerView
                innerTransition = .immediate
                contentView.insertSubview(innerView, at: 0)

                innerView.frame = innerFrame
                innerView.layer.cornerRadius = innerRadius
                animateIn = true
            }

            innerView.backgroundColor = innerColor
            innerTransition.setFrame(view: innerView, frame: innerFrame)
            innerTransition.setCornerRadius(layer: innerView.layer, cornerRadius: innerRadius)

            if animateIn, transition.isAnimated {
                transition.animateAlpha(view: innerView, from: 0.0, to: 1.0)
                transition.animateScale(view: innerView, from: 0.001, to: 1.0)
            }
        } else if let innerView = innerBackgroundView {
            self.innerBackgroundView = nil
            if transition.isAnimated {
                transition.setAlpha(view: innerView, alpha: 0.0, completion: { [weak innerView] _ in
                    innerView?.removeFromSuperview()
                })
                transition.setScale(view: innerView, scale: 0.001)
            } else {
                innerView.removeFromSuperview()
            }
        }

        let params = Params(shape: shape, isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, isVisible: isVisible)
        if self.params != params {
            self.params = params

            let outerCornerRadius: CGFloat
            switch shape {
            case let .roundedRect(cornerRadius):
                outerCornerRadius = cornerRadius
            }

            // Legacy foreground (shadow + border gradient).
            if let shadowNode {
                let shadowInnerInset: CGFloat = 0.5
                shadowNode.image = generateImage(
                    CGSize(width: shadowInset * 2.0 + outerCornerRadius * 2.0,
                           height: shadowInset * 2.0 + outerCornerRadius * 2.0),
                    rotatedContext: { size, context in
                        context.clear(CGRect(origin: .zero, size: size))

                        context.setFillColor(UIColor.black.cgColor)
                        context.setShadow(offset: CGSize(width: 0.0, height: 1.0), blur: 40.0, color: UIColor(white: 0.0, alpha: 0.04).cgColor)
                        context.fillEllipse(in: CGRect(
                            x: shadowInset + shadowInnerInset,
                            y: shadowInset + shadowInnerInset,
                            width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0,
                            height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0
                        ))

                        context.setFillColor(UIColor.clear.cgColor)
                        context.setBlendMode(.copy)
                        context.fillEllipse(in: CGRect(
                            x: shadowInset + shadowInnerInset,
                            y: shadowInset + shadowInnerInset,
                            width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0,
                            height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0
                        ))
                    }
                )?.stretchableImage(withLeftCapWidth: Int(shadowInset + outerCornerRadius), topCapHeight: Int(shadowInset + outerCornerRadius))
                transition.setAlpha(view: shadowNode.view, alpha: isVisible ? 1.0 : 0.0)
            }

            if let foregroundNode {
                let fillColor: UIColor
                let borderWidthFactor: CGFloat
                switch tintColor.kind {
                case .panel:
                    borderWidthFactor = 1.0
                    // Tightened tint alpha so the glass on iOS<26 reads
                    // as actual glass (you see backdrop blur through it),
                    // not a near-opaque white pill on top of the blur.
                    // The original 0.7/0.85 values dialed the foreground
                    // ellipse so high that nothing under the surface was
                    // visible. 0.35 / 0.55 keeps enough whiteness for
                    // contrast against backdrop content but lets the
                    // material breathe.
                    if isDark {
                        fillColor = UIColor(white: 1.0, alpha: 1.0)
                            .mixedWith(.black, alpha: 1.0 - 0.11)
                            .withAlphaComponent(style == .prominent ? 0.68 : 0.55)
                    } else {
                        fillColor = UIColor(white: 1.0, alpha: style == .prominent ? 0.48 : 0.35)
                    }
                case .clear:
                    borderWidthFactor = 2.0
                    fillColor = UIColor(white: 1.0, alpha: 0.0)
                case let .custom(style, color):
                    fillColor = color
                    borderWidthFactor = style == .clear ? 2.0 : 1.0
                }
                foregroundNode.image = Self.generateLegacyGlassImage(
                    size: CGSize(width: outerCornerRadius * 2.0, height: outerCornerRadius * 2.0),
                    inset: shadowInset,
                    borderWidthFactor: borderWidthFactor,
                    isDark: isDark,
                    fillColor: fillColor
                )
                transition.setAlpha(view: foregroundNode.view, alpha: isVisible ? 1.0 : 0.0)
            } else if let nativeParamsView, let nativeView, #available(iOS 26.0, *) {
                // Native iOS 26 liquid-glass path: set up a proper UIGlassEffect
                // with tint / interactive flag. `nativeView` is only allocated
                // on this path (legacy takes over when liquid design is off),
                // so no inner OS-gate is needed below.
                let glassEffect = makeNativeGlassEffect(
                    isDark: isDark,
                    tintColor: tintColor,
                    isInteractive: params.isInteractive,
                    isVisible: isVisible
                )
                applyNativeGlassEffect(glassEffect, to: nativeView, transition: transition)
                applyNativeLuma(isDark: isDark, to: nativeParamsView)
            }
        }

        if let nativeParamsView {
            transition.setFrame(view: nativeParamsView, frame: CGRect(origin: .zero, size: size))
        }
        updateSyntheticStroke(size: size, cornerRadius: cornerRadius, isVisible: isVisible, transition: transition)
        transition.setFrame(view: maskContainerView, frame: CGRect(
            origin: .zero,
            size: CGSize(width: size.width + shadowInset * 2.0, height: size.height + shadowInset * 2.0)
        ))
        transition.setFrame(view: maskContentView, frame: CGRect(x: shadowInset, y: shadowInset, width: size.width, height: size.height))
        if let foregroundNode {
            transition.setFrame(view: foregroundNode.view, frame: CGRect(origin: .zero, size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        if let shadowNode {
            transition.setFrame(view: shadowNode.view, frame: CGRect(origin: .zero, size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }

        transition.setFrame(view: contentContainer, frame: CGRect(origin: .zero, size: size))
        transition.setCornerRadius(layer: contentContainer.layer, cornerRadius: cornerRadius)
        transition.setFrame(view: publicContentContainer, frame: CGRect(origin: .zero, size: size))
        transition.setCornerRadius(layer: publicContentContainer.layer, cornerRadius: cornerRadius)
        if _transitionMaterialAlpha < 0.999 {
            applyTransitionMaterialAlpha()
        }
    }

    /// Applies no animation and never mutates/recreates the glass effect.
    /// The coordinator samples this alongside surface geometry, so keeping
    /// the existing renderer alive avoids both a white fullscreen material
    /// veil and effect-allocation churn during interruption or reversal.
    private func applyTransitionMaterialAlpha() {
        let materialIsVisible = params?.isVisible ?? true
        let alpha = materialIsVisible ? _transitionMaterialAlpha : 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nativeParamsView?.alpha = alpha
        legacyView?.alpha = alpha
        legacyHighlightContainerView?.alpha = alpha
        foregroundNode?.view.alpha = alpha
        shadowNode?.view.alpha = alpha
        plainSurfaceView?.alpha = alpha
        if nativeView == nil {
            innerBackgroundView?.alpha = alpha
            syntheticStrokeLayer.opacity = Float(alpha)
        }
        CATransaction.commit()
    }

    private func applyLegacySurface(
        size: CGSize,
        cornerRadius: CGFloat,
        tintColor _: TintColor,
        isDark: Bool,
        isVisible: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        guard let plainSurfaceView else { return }
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: surfaceRole,
            traitCollection: traitCollection
        )
        // Glass tint is renderer-specific input. Carrying it into Legacy
        // paints a colour wash over `systemChromeMaterial`, which makes an
        // attached bar look opaque even though a blur view is installed.
        // Only the explicit classic-surface override may tint the material.
        let backgroundColor = legacySurfaceColorOverride ?? tokens.surfaceColor

        plainSurfaceView.overrideUserInterfaceStyle = isDark ? .dark : .light
        if legacyUsesExternalBlurMaterial {
            legacyMaterialView?.contentView.backgroundColor = .clear
            plainSurfaceView.backgroundColor = UIAccessibility
                .isReduceTransparencyEnabled
                ? backgroundColor
                : backgroundColor.withAlphaComponent(
                    min(backgroundColor.cgColor.alpha, 0.22)
                )
        } else if !legacyUsesBlurMaterial {
            plainSurfaceView.backgroundColor = backgroundColor
        } else if UIAccessibility.isReduceTransparencyEnabled {
            plainSurfaceView.backgroundColor = .clear
            legacyMaterialView?.contentView.backgroundColor = backgroundColor
        } else if legacySurfaceColorOverride != nil {
            plainSurfaceView.backgroundColor = .clear
            legacyMaterialView?.contentView.backgroundColor = backgroundColor.withAlphaComponent(
                min(backgroundColor.cgColor.alpha, 0.22)
            )
        } else {
            plainSurfaceView.backgroundColor = .clear
            legacyMaterialView?.contentView.backgroundColor = .clear
        }
        plainSurfaceView.layer.cornerCurve = tokens.cornerCurve
        plainSurfaceView.layer.borderColor = tokens.borderColor.cgColor
        plainSurfaceView.layer.borderWidth = legacyBorderWidthOverride
            ?? tokens.borderWidth
        plainSurfaceView.layer.shadowColor = tokens.shadowColor.cgColor
        plainSurfaceView.layer.shadowOpacity = legacyShadowOverride?.opacity
            ?? tokens.shadowOpacity
        plainSurfaceView.layer.shadowRadius = legacyShadowOverride?.radius
            ?? tokens.shadowRadius
        plainSurfaceView.layer.shadowOffset = legacyShadowOverride?.offset
            ?? tokens.shadowOffset
        plainSurfaceView.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadius: cornerRadius
        ).cgPath

        transition.setFrame(view: plainSurfaceView, frame: CGRect(origin: .zero, size: size))
        transition.setCornerRadius(layer: plainSurfaceView.layer, cornerRadius: cornerRadius)
        transition.setAlpha(view: plainSurfaceView, alpha: isVisible ? _transitionMaterialAlpha : 0)
        if let legacyMaterialView {
            transition.setFrame(view: legacyMaterialView, frame: CGRect(origin: .zero, size: size))
            transition.setCornerRadius(layer: legacyMaterialView.layer, cornerRadius: cornerRadius)
            legacyMaterialView.aetherApplyBackdropGroupingIdentifier(
                legacyBackdropGroupingIdentifier
            )
        }
        transition.setFrame(view: contentContainer, frame: CGRect(origin: .zero, size: size))
        transition.setCornerRadius(layer: contentContainer.layer, cornerRadius: cornerRadius)
        transition.setFrame(view: publicContentContainer, frame: CGRect(origin: .zero, size: size))
        transition.setCornerRadius(layer: publicContentContainer.layer, cornerRadius: cornerRadius)
        syntheticStrokeLayer.isHidden = true
    }

    @available(iOS 26.0, *)
    private func makeNativeGlassEffect(
        isDark: Bool,
        tintColor: TintColor,
        isInteractive: Bool,
        isVisible: Bool
    ) -> UIGlassEffect? {
        guard isVisible else {
            return nil
        }

        let effect: UIGlassEffect
        requestedNativeEffectStyle = 0
        switch tintColor.kind {
        case .panel:
            effect = UIGlassEffect(style: .regular)
            // Slightly weaker tint so UIGlassEffect's own material specular
            // stays dominant and the surface does not look painted on.
            effect.tintColor = isDark
                ? UIColor(white: 1.0, alpha: style == .prominent ? 0.04 : 0.015)
                : UIColor(white: 1.0, alpha: style == .prominent ? 0.12 : 0.06)

        case .clear:
            requestedNativeEffectStyle = 1
            effect = UIGlassEffect(style: .clear)
            effect.tintColor = isDark ? UIColor(white: 0.0, alpha: 0.18) : nil

        case let .custom(customStyle, color):
            switch customStyle {
            case .default:
                effect = UIGlassEffect(style: .regular)
            case .clear:
                requestedNativeEffectStyle = 1
                effect = UIGlassEffect(style: .clear)
            }
            effect.tintColor = color
        }

        effect.isInteractive = isInteractive
        if let configured = NativeGlassDescriptorAdapter.applying(nativeDescriptorOptions, to: effect) {
            nativeContentLensingApplied = nativeDescriptorOptions.contentLensing
            return configured
        }
        nativeContentLensingApplied = false
        return effect
    }

    @available(iOS 26.0, *)
    private func applyNativeGlassEffect(
        _ desiredEffect: UIGlassEffect?,
        to nativeView: UIVisualEffectView,
        transition: ContainedViewLayoutTransition
    ) {
        guard let desiredEffect else {
            appliedNativeEffectStyle = nil
            appliedNativeDescriptorOptions = nil
            nativeContentLensingApplied = false
            guard nativeView.effect is UIGlassEffect else {
                return
            }
            let clearedEffect: UIVisualEffect?
            if #available(iOS 26.1, *) {
                clearedEffect = nil
            } else {
                clearedEffect = UIVisualEffect()
            }
            nativeGlassEffectAssignmentCountForTesting += 1
            if transition.isAnimated {
                transition.animateView { nativeView.effect = clearedEffect }
            } else {
                nativeView.effect = clearedEffect
            }
            return
        }

        if let current = nativeView.effect as? UIGlassEffect,
           current.tintColor == desiredEffect.tintColor,
           current.isInteractive == desiredEffect.isInteractive,
           appliedNativeEffectStyle == requestedNativeEffectStyle,
           appliedNativeDescriptorOptions == nativeDescriptorOptions {
            return
        }

        appliedNativeEffectStyle = requestedNativeEffectStyle
        appliedNativeDescriptorOptions = nativeDescriptorOptions
        nativeGlassEffectAssignmentCountForTesting += 1
        if transition.isAnimated {
            transition.animateView { nativeView.effect = desiredEffect }
        } else {
            nativeView.effect = desiredEffect
        }
    }

    private func applyNativeLuma(isDark: Bool, to nativeParamsView: EffectSettingsContainerView) {
        if isDark {
            nativeParamsView.lumaMin = 0.0
            nativeParamsView.lumaMax = 0.15
        } else {
            nativeParamsView.lumaMin = 0.8
            nativeParamsView.lumaMax = 0.801
        }
    }

    private static var shouldUseSyntheticStrokeFallback: Bool {
        if #available(iOS 27.0, *) {
            return false
        }
        return true
    }

    private var resolvedStrokeAppearance: AetherGlassStrokeAppearance {
        if let strokeAppearance {
            return strokeAppearance
        }
        let appearance = AetherAppearance.runtimeCurrent
        guard appliedAppearanceStyle == .liquidGlassV2, Self.shouldUseSyntheticStrokeFallback else {
            return .none
        }
        return .hairline(color: appearance.separatorColor, opacity: 0.40)
    }

    private func updateSyntheticStroke(size: CGSize, cornerRadius: CGFloat, isVisible: Bool, transition: ContainedViewLayoutTransition) {
        let wasHidden = syntheticStrokeLayer.isHidden

        func applyWithoutImplicitAnimation(_ update: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            update()
            CATransaction.commit()
        }

        guard isVisible, size.width > 0.0, size.height > 0.0 else {
            applyWithoutImplicitAnimation {
                syntheticStrokeLayer.isHidden = true
            }
            return
        }

        switch resolvedStrokeAppearance {
        case .none:
            applyWithoutImplicitAnimation {
                syntheticStrokeLayer.isHidden = true
            }
        case let .hairline(color, opacity):
            let explicitStyle = params?.isDark == true
                ? UIUserInterfaceStyle.dark
                : UIUserInterfaceStyle.light
            let resolvedTraits = UITraitCollection(traitsFrom: [
                traitCollection,
                UITraitCollection(userInterfaceStyle: explicitStyle)
            ])
            let strokeColor = (color ?? .separator)
                .resolvedColor(with: resolvedTraits)
                .withAlphaComponent(opacity)
            let lineWidth = 1.0 / max(window?.screen.scale ?? traitCollection.displayScale, 1.0)
            let bounds = CGRect(origin: .zero, size: size)
            let rect = bounds.insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
            let radius = min(
                max(0.0, cornerRadius - lineWidth * 0.5),
                max(0, min(rect.width, rect.height) * 0.5)
            )
            let pathGeometry = SyntheticStrokePathGeometry(
                bounds: bounds,
                cornerRadius: radius,
                lineWidth: lineWidth
            )
            let needsPathUpdate = syntheticStrokePathGeometry != pathGeometry
                || syntheticStrokeLayer.path == nil
            let previousFrame = needsPathUpdate
                ? (syntheticStrokeLayer.presentation()?.frame
                    ?? syntheticStrokeLayer.frame)
                : syntheticStrokeLayer.frame
            let previousPath = needsPathUpdate
                ? (syntheticStrokeLayer.presentation()?.path
                    ?? syntheticStrokeLayer.path)
                : syntheticStrokeLayer.path
            // `CGPath`'s rounded-rect initializer avoids the intermediate
            // UIBezierPath allocation that used to occur at display-link rate.
            let path = needsPathUpdate
                ? CGPath(
                    roundedRect: rect,
                    cornerWidth: radius,
                    cornerHeight: radius,
                    transform: nil
                )
                : syntheticStrokeLayer.path

            applyWithoutImplicitAnimation {
                syntheticStrokeLayer.isHidden = false
                if needsPathUpdate {
                    syntheticStrokeLayer.frame = bounds
                    syntheticStrokeLayer.path = path
                    syntheticStrokePathGeometry = pathGeometry
                    syntheticStrokePathUpdateCount += 1
                }
                syntheticStrokeLayer.lineWidth = lineWidth
                syntheticStrokeLayer.strokeColor = strokeColor.cgColor
            }

            guard needsPathUpdate, !wasHidden, transition.isAnimated else {
                return
            }
            if case let .animated(duration, curve) = transition {
                let timingFunction = curve.mediaTimingFunction()
                syntheticStrokeLayer.animateFrame(
                    from: previousFrame,
                    to: bounds,
                    duration: duration,
                    timingFunction: timingFunction
                )
                if let previousPath {
                    let animation = CABasicAnimation(keyPath: "path")
                    animation.fromValue = previousPath
                    animation.toValue = path
                    animation.duration = duration
                    animation.timingFunction = timingFunction
                    animation.isRemovedOnCompletion = true
                    animation.fillMode = .forwards
                    animation.aetherPreferHighFrameRate()
                    syntheticStrokeLayer.add(animation, forKey: "path")
                }
            }
        }
    }

    // MARK: Static image generators (port of helpers)

    public static func generateLegacyGlassImage(size: CGSize, inset: CGFloat, borderWidthFactor: CGFloat = 1.0, isDark: Bool, fillColor: UIColor) -> UIImage? {
        var size = size
        if size == .zero {
            size = CGSize(width: 2.0, height: 2.0)
        }
        let innerSize = size
        size.width += inset * 2.0
        size.height += inset * 2.0

        return UIGraphicsImageRenderer(size: size).image { ctx in
            let context = ctx.cgContext
            context.clear(CGRect(origin: .zero, size: size))

            // Outer shadow (light).
            func addOuterShadow(position: CGPoint, blur: CGFloat, spread: CGFloat, color: UIColor) {
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.saveGState()
                let rect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize).insetBy(dx: 0.25, dy: 0.25)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.5).cgPath

                context.setShadow(offset: CGSize(width: position.x, height: position.y), blur: blur + abs(spread), color: color.cgColor)
                context.setFillColor(UIColor.black.withAlphaComponent(1.0).cgColor)
                context.addPath(path)
                context.fillPath()

                let cleanRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize)
                let cleanPath = UIBezierPath(roundedRect: cleanRect, cornerRadius: min(cleanRect.width, cleanRect.height) * 0.5).cgPath
                context.setBlendMode(.copy)
                context.setFillColor(UIColor.clear.cgColor)
                context.addPath(cleanPath)
                context.fillPath()
                context.setBlendMode(.normal)
                context.restoreGState()
                context.endTransparencyLayer()
            }

            addOuterShadow(position: .zero, blur: 30.0, spread: 0.0, color: UIColor(white: 0.0, alpha: 0.045))
            addOuterShadow(position: .zero, blur: 20.0, spread: 0.0, color: UIColor(white: 0.0, alpha: 0.01))

            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bri: CGFloat = 0
            var a: CGFloat = 0
            fillColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
            _ = hue

            let innerImage = UIGraphicsImageRenderer(size: size).image { ictx in
                let ic = ictx.cgContext
                ic.setFillColor(fillColor.cgColor)
                var ellipseRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                ic.fillEllipse(in: ellipseRect)

                let lineWidth: CGFloat = (isDark ? 0.8 : 0.8) * borderWidthFactor
                let strokeColor: UIColor
                let blendMode: CGBlendMode
                let baseAlpha: CGFloat = isDark ? 0.3 : 0.6

                if sat == 0.0, abs(a - 0.7) < 0.1, !isDark {
                    blendMode = .normal
                    strokeColor = UIColor(white: 1.0, alpha: baseAlpha)
                } else if sat <= 0.3, !isDark {
                    blendMode = .normal
                    strokeColor = UIColor(white: 1.0, alpha: 0.7 * baseAlpha)
                } else if bri >= 0.2 {
                    let maxAlpha: CGFloat = isDark ? 0.7 : 0.8
                    blendMode = .overlay
                    strokeColor = UIColor(white: 1.0, alpha: max(0.5, min(1.0, maxAlpha * sat)) * baseAlpha)
                } else {
                    blendMode = .normal
                    strokeColor = UIColor(white: 1.0, alpha: 0.5 * baseAlpha)
                }

                ic.setStrokeColor(strokeColor.cgColor)
                ellipseRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                ic.addEllipse(in: ellipseRect)
                ic.clip()

                ellipseRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
                ic.setBlendMode(blendMode)

                let radius = ellipseRect.height * 0.5
                let smallerRadius = radius - lineWidth * 1.33
                ic.move(to: CGPoint(x: ellipseRect.minX, y: ellipseRect.minY + radius))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.minX, y: ellipseRect.minY), tangent2End: CGPoint(x: ellipseRect.minX + radius, y: ellipseRect.minY), radius: radius)
                ic.addLine(to: CGPoint(x: ellipseRect.maxX - smallerRadius, y: ellipseRect.minY))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.maxX, y: ellipseRect.minY), tangent2End: CGPoint(x: ellipseRect.maxX, y: ellipseRect.minY + smallerRadius), radius: smallerRadius)
                ic.addLine(to: CGPoint(x: ellipseRect.maxX, y: ellipseRect.maxY - radius))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.maxX, y: ellipseRect.maxY), tangent2End: CGPoint(x: ellipseRect.maxX - radius, y: ellipseRect.maxY), radius: radius)
                ic.addLine(to: CGPoint(x: ellipseRect.minX + smallerRadius, y: ellipseRect.maxY))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.minX, y: ellipseRect.maxY), tangent2End: CGPoint(x: ellipseRect.minX, y: ellipseRect.maxY - smallerRadius), radius: smallerRadius)
                ic.closePath()
                ic.strokePath()

                ic.resetClip()
                ic.setBlendMode(.normal)
            }
            innerImage.draw(in: CGRect(origin: .zero, size: size))
        }.stretchableImage(withLeftCapWidth: Int(size.width * 0.5), topCapHeight: Int(size.height * 0.5))
    }
}

// MARK: - GlassBackgroundContainerView (port of UIGlassContainerEffect host)

/// Groups multiple `GlassBackgroundView`s under a shared `UIGlassContainerEffect`
/// so that they merge visually when close together (iOS 26+). Falls back to a
/// plain container view for earlier systems.
public final class GlassBackgroundContainerView: UIView, AetherAppearanceConsumer {
    private final class LegacyContentView: UIView {}

    private let publicContentView: UIView
    private var legacyView: LegacyContentView?
    private var nativeView: UIVisualEffectView?
    private var nativeParamsView: EffectSettingsContainerView?
    private var appliedAppearanceStyle: AetherAppearanceStyle
    private var spacing: CGFloat

    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    public var contentView: UIView {
        publicContentView
    }

    public init(
        spacing: CGFloat = 7.0,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.publicContentView = UIView()
        self.nativeView = nil
        self.nativeParamsView = nil
        self.legacyView = nil
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        self.spacing = spacing

        super.init(frame: .zero)

        clipsToBounds = false
        publicContentView.backgroundColor = .clear
        publicContentView.clipsToBounds = false
        publicContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rebuildRenderer(for: appliedAppearanceStyle)
        AetherAppearanceConsumerRegistry.register(self)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal var isUsingNativeContainerEffect: Bool {
        nativeView != nil
    }

    internal var isUsingAnyGlassContainerEffect: Bool {
        nativeView != nil
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let style = appearanceStyleOverride ?? appearance.style
        guard style != appliedAppearanceStyle else { return }
        appliedAppearanceStyle = style
        rebuildRenderer(for: style)
        if let memo = lastUpdateMemo {
            update(size: memo.size, isDark: memo.isDark, transition: .immediate)
        } else {
            setNeedsLayout()
        }
    }

    private func rebuildRenderer(for style: AetherAppearanceStyle) {
        publicContentView.removeFromSuperview()
        nativeView?.effect = nil
        nativeParamsView?.layer.removeAllAnimations()
        nativeView?.layer.removeAllAnimations()
        nativeParamsView?.removeFromSuperview()
        legacyView?.removeFromSuperview()
        nativeView = nil
        nativeParamsView = nil
        legacyView = nil

        if style.usesLiquidGlass,
           GlassCompatibility.isLiquidDesignAvailable,
           #available(iOS 26.0, *),
           !GlassBackgroundView.useCustomGlassImpl {
            let effect = UIGlassContainerEffect()
            effect.spacing = spacing
            let native = UIVisualEffectView(effect: effect)
            native.clipsToBounds = false
            native.contentView.clipsToBounds = false
            nativeView = native

            let params = EffectSettingsContainerView(frame: .zero)
            params.clipsToBounds = false
            params.addSubview(native)
            nativeParamsView = params
            addSubview(params)
            native.contentView.addSubview(publicContentView)
        } else {
            let content = LegacyContentView()
            content.clipsToBounds = false
            legacyView = content
            addSubview(content)
            content.addSubview(publicContentView)
        }
        publicContentView.frame = bounds
    }

    /// Changes the merge reach of the native container without replacing its
    /// effect. Morphs use this as surface tension: nearby lobes pull together
    /// a little more strongly at peak deformation, then relax at rest.
    internal func setSpacing(_ spacing: CGFloat) {
        self.spacing = max(0, spacing)
        if #available(iOS 26.0, *),
           let effect = nativeView?.effect as? UIGlassContainerEffect {
            effect.spacing = self.spacing
        }
    }

    /// Explicit override for the `isDark` passed to `update(...)`. When
    /// non-`nil`, wins over the caller-supplied value so one container can
    /// be pinned to a specific theme regardless of what per-frame code
    /// threads through `update`. Default `nil` → the caller decides.
    public var isDarkOverride: Bool? {
        didSet {
            if isDarkOverride == oldValue { return }
            if let memo = lastUpdateMemo {
                update(size: memo.size, isDark: resolvedIsDark(passed: memo.isDark), transition: .immediate)
            }
        }
    }

    private struct UpdateMemo {
        let size: CGSize
        let isDark: Bool
    }
    private var lastUpdateMemo: UpdateMemo?

    private func resolvedIsDark(passed: Bool) -> Bool {
        isDarkOverride ?? passed
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }
        for view in contentView.subviews.reversed() {
            if let result = view.hitTest(self.convert(point, to: view), with: event), result.isUserInteractionEnabled {
                return result
            }
        }
        guard let result = contentView.hitTest(point, with: event) else { return nil }
        if result === contentView { return nil }
        return result
    }

    public func update(size: CGSize, isDark: Bool, transition: ContainedViewLayoutTransition) {
        // Remember the caller-supplied isDark so the `isDarkOverride`
        // setter can re-apply without needing a fresh update() call.
        self.lastUpdateMemo = UpdateMemo(size: size, isDark: isDark)
        let effectiveIsDark = resolvedIsDark(passed: isDark)

        if let nativeView, let nativeParamsView, #available(iOS 26.0, *) {
            let targetStyle: UIUserInterfaceStyle = effectiveIsDark ? .dark : .light
            if nativeView.overrideUserInterfaceStyle != targetStyle {
                nativeView.overrideUserInterfaceStyle = targetStyle
            }
            if effectiveIsDark {
                nativeParamsView.lumaMin = 0.0
                nativeParamsView.lumaMax = 0.15
            } else {
                nativeParamsView.lumaMin = 0.8
                nativeParamsView.lumaMax = 0.801
            }
            transition.setFrame(view: nativeParamsView, frame: CGRect(origin: .zero, size: size))

            if transition.isAnimated {
                transition.animateView({ nativeView.frame = CGRect(origin: .zero, size: size) })
            } else {
                nativeView.frame = CGRect(origin: .zero, size: size)
            }
        } else if let legacyView {
            transition.setFrame(view: legacyView, frame: CGRect(origin: .zero, size: size))
        }
        transition.setFrame(view: publicContentView, frame: CGRect(origin: .zero, size: size))
    }
}
