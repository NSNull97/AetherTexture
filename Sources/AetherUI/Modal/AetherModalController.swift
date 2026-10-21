import UIKit
import AsyncDisplayKit

public protocol AetherModalControllerDelegate: AnyObject {
    /// Fires continuously (per-frame during drag and during the settle
    /// animation) as the sheet scrolls between detents. Progress is 0 at
    /// stage1 and 1 at stage2; values are clamped to `0...1`.
    func modalController(
        _ controller: AetherModalController,
        didUpdateDetentProgress progress: CGFloat
    )
    /// Fires when the sheet commits to a detent — at the start of a settle
    /// animation or a programmatic `setDetent`.
    func modalController(
        _ controller: AetherModalController,
        didChangeDetent detent: AetherModalController.Detent
    )
    /// Fires the moment the sheet starts moving — pan `.began` (when the
    /// sheet decides it owns the gesture) or the start of a settle /
    /// programmatic-`setDetent` animation. Bracketed with a matching
    /// `didEndInteractiveResize` once motion has fully stopped.
    ///
    /// Content remains live and is laid out for the visible sheet bounds.
    /// Consumers can use this hook to pause expensive work while resizing.
    func modalControllerWillBeginInteractiveResize(
        _ controller: AetherModalController
    )
    /// Fires once interactive resize has fully stopped — pan ended without
    /// triggering settle, or the settle animation completed/was cancelled.
    /// Always paired with a prior `willBeginInteractiveResize`.
    func modalControllerDidEndInteractiveResize(
        _ controller: AetherModalController
    )
}

public extension AetherModalControllerDelegate {
    func modalController(
        _ controller: AetherModalController,
        didUpdateDetentProgress progress: CGFloat
    ) {}
    func modalController(
        _ controller: AetherModalController,
        didChangeDetent detent: AetherModalController.Detent
    ) {}
    func modalControllerWillBeginInteractiveResize(
        _ controller: AetherModalController
    ) {}
    func modalControllerDidEndInteractiveResize(
        _ controller: AetherModalController
    ) {}
}

open class AetherModalController: ASDKViewController<ASDisplayNode> {
    public enum Detent: Hashable {
        case stage1
        case stage2
    }

    public struct Config: Equatable {
        /// Horizontal sheet margin at stage1, or at both detents when
        /// `sizesToContent` is enabled.
        public var sideInset: CGFloat
        /// Distance from the sheet's bottom edge to the screen bottom at
        /// stage1. Default 8pt — the sheet floats above the home indicator.
        public var bottomInsetStage1: CGFloat
        /// Distance from the sheet's bottom edge to the screen bottom at
        /// stage2. Default 0 — the sheet nestles into the device corners.
        public var bottomInsetStage2: CGFloat
        /// Distance from the safe-area top at stage1. A negative value
        /// resolves automatically to half of the current container height.
        public var topInsetStage1: CGFloat
        public var topInsetStage2: CGFloat
        public var topCornerRadius: CGFloat
        /// Nil uses the top radius for the floating compact sheet.
        public var bottomCornerRadiusStage1: CGFloat?
        /// Nil uses zero at the screen edge, or the top radius when floating.
        public var bottomCornerRadiusStage2: CGFloat?
        /// On iOS 26+, derives the bottom outline from the containing window
        /// and the sheet's inset. Configured bottom radii remain the minimum
        /// and the fallback on earlier systems.
        public var bottomCornersFollowContainer: Bool
        /// Dim alpha applied over the presenting view at stage1.
        public var dimAlphaStage1: CGFloat
        /// Dim alpha applied over the presenting view at stage2.
        public var dimAlphaStage2: CGFloat
        public var dimTintColor: UIColor
        /// Detents the sheet is allowed to rest at. When a single detent
        /// is specified the sheet opens at that detent and drags toward
        /// the other detent are blocked — only a strong downward drag can
        /// dismiss the sheet. Must contain at least one detent.
        public var detents: Set<Detent>
        /// Detent the sheet opens at. Must be contained in `detents`.
        /// Nil → pick the first allowed detent (stage1 preferred).
        public var initialDetent: Detent?
        /// Optional intrinsic-sized presentation. When set, the modal is
        /// centered in the safe area at this size instead of using the
        /// sheet's half-height/full-height detent geometry.
        public var fixedSize: CGSize?
        /// Uses `contentHeight(forWidth:safeAreaInsets:)` for a sheet that
        /// fits its content within `sideInset` and the current detent's bottom
        /// margin. Content supplies the total height, including the portion
        /// of the bottom safe area that overlaps the sheet.
        /// Takes precedence over `fixedSize` when both are configured.
        public var sizesToContent: Bool
        /// Whether the sheet grabber is visible. Compact card modals can
        /// hide it when their content already defines the surface chrome.
        public var showsGrabber: Bool

        public init(
            sideInset: CGFloat = 8.0,
            bottomInsetStage1: CGFloat = 8.0,
            bottomInsetStage2: CGFloat = 0.0,
            topInsetStage1: CGFloat = -1.0,
            topInsetStage2: CGFloat = 10.0,
            topCornerRadius: CGFloat = 34.0,
            bottomCornerRadiusStage1: CGFloat? = nil,
            bottomCornerRadiusStage2: CGFloat? = nil,
            bottomCornersFollowContainer: Bool = false,
            dimAlphaStage1: CGFloat = 0.25,
            dimAlphaStage2: CGFloat = 0.4,
            dimTintColor: UIColor = .systemBackground,
            detents: Set<Detent> = [.stage1, .stage2],
            initialDetent: Detent? = nil,
            fixedSize: CGSize? = nil,
            sizesToContent: Bool = false,
            showsGrabber: Bool = true
        ) {
            self.sideInset = sideInset
            self.bottomInsetStage1 = bottomInsetStage1
            self.bottomInsetStage2 = bottomInsetStage2
            self.topInsetStage1 = topInsetStage1
            self.topInsetStage2 = topInsetStage2
            self.topCornerRadius = topCornerRadius
            self.bottomCornerRadiusStage1 = bottomCornerRadiusStage1
            self.bottomCornerRadiusStage2 = bottomCornerRadiusStage2
            self.bottomCornersFollowContainer = bottomCornersFollowContainer
            self.dimAlphaStage1 = dimAlphaStage1
            self.dimAlphaStage2 = dimAlphaStage2
            self.dimTintColor = dimTintColor
            self.detents = detents.isEmpty ? [.stage1, .stage2] : detents
            self.initialDetent = initialDetent
            self.fixedSize = fixedSize
            self.sizesToContent = sizesToContent
            self.showsGrabber = showsGrabber
        }

        /// Resolved opening detent — `initialDetent` if allowed,
        /// otherwise stage1 (if allowed), otherwise stage2.
        public var resolvedInitialDetent: Detent {
            if let requested = initialDetent, detents.contains(requested) {
                return requested
            }
            return detents.contains(.stage1) ? .stage1 : .stage2
        }
    }

    public let config: Config

    /// Optional renderer generation pinned to this modal. `nil` follows the
    /// application appearance (including controller-local overrides).
    ///
    /// The value is resolved before the modal surface is allocated, so a
    /// Legacy modal never briefly constructs a Liquid renderer while its view
    /// hierarchy is being loaded.
    public var appearanceStyle: AetherAppearanceStyle? = nil {
        didSet {
            guard appearanceStyle != oldValue else { return }
            applyResolvedAppearance(animated: true)
        }
    }

    private var inheritedAppearance: AetherAppearance
    private var appliedAppearanceStyle: AetherAppearanceStyle

    /// Public host for your sheet's content. Subclasses populate this
    /// in `viewDidLoad` (`contentView.addSubview(...)` or `embedContent(_:)`).
    ///
    /// Bounds always match the visible sheet. Content and material are
    /// separate siblings; neither is scaled or rasterized during resizing.
    public let contentView: UIView

    /// Optional sticky footer — anchored to the bottom of the visible
    /// modal so it follows the sheet across detents (i.e. it lives in
    /// `presentedView` coordinates, not in `contentView` coordinates).
    /// Setting this:
    ///   * positions `footerView` at `(0, footerEdgeFadeHeight, modal.width, footerHeight)`
    ///     inside an internal host
    ///   * applies a scroll-edge frost that fades upward into the
    ///     content area (`footerEdgeFadeHeight`)
    ///   * reserves its full height at the bottom, accounting for the inherited
    ///     safe area so scroll content can move clear of the footer
    ///
    /// Use `footerHeight` to declare the footer's total height (the
    /// modal can't reliably ask the view itself — auto-layout-only
    /// footers without intrinsic height would report 0).
    public var footerView: UIView? {
        didSet {
            if isViewLoaded { view.setNeedsLayout() }
        }
    }

    private var footerNode: ASDisplayNode?

    public func setFooterNode(_ node: ASDisplayNode?) {
        footerNode = node
        footerView = node?.view
    }

    /// Total height (in points) of the contents of `footerView`. Drives
    /// both the visible footer band and the bottom safe-area inset added
    /// onto the content host. Does NOT include the edge-effect fade
    /// height — that's `footerEdgeFadeHeight`.
    public var footerHeight: CGFloat = 0 {
        didSet {
            if oldValue != footerHeight, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }

    /// Height of the gradient fade that sits above the footer and
    /// dissolves the scroll content into the frost. 28pt by default —
    /// matches the look used by the original Telegram-style modal.
    public var footerEdgeFadeHeight: CGFloat = 28 {
        didSet {
            if oldValue != footerEdgeFadeHeight, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }

    /// Tint colour drawn behind the footer. `nil` → derive from
    /// `config.dimTintColor` with 0.86 alpha (sensible default that
    /// matches the modal background).
    public var footerEdgeTintColor: UIColor? {
        didSet { invalidateFooterEdgeCache() }
    }

    /// Blur radius behind the footer band. 2pt by default — same as
    /// the legacy edge-effect setting.
    public var footerEdgeBlurRadius: CGFloat = 2 {
        didSet { invalidateFooterEdgeCache() }
    }

    /// Whether the modal draws its frosted edge behind the footer. Disable
    /// this for a standalone glass control that should float over content.
    public var footerEdgeEffectEnabled = true {
        didSet {
            if oldValue != footerEdgeEffectEnabled, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }

    /// Scroll view inside the modal that should cooperate with sheet drag.
    /// Subclasses set this in `viewDidLoad` to opt into:
    ///   * gesture arbitration — the modal yields to scroll when the
    ///     touch starts inside scroll content and scroll isn't at top;
    ///   * automatic keyboard adjustment — the modal observes
    ///     `keyboardWillChangeFrame` and pushes the on-screen keyboard
    ///     overlap into `primaryScrollView.contentInset.bottom` (and
    ///     scroll-indicator inset), then scrolls the active first
    ///     responder into the visible area.
    public weak var primaryScrollView: UIScrollView? {
        didSet {
            guard oldValue !== primaryScrollView else { return }
            // Move our keyboard contribution from the old scroll view to
            // the new one — otherwise the previous scroll keeps a stale
            // bottom inset and the new one starts without ours.
            if lastKeyboardScrollInset != 0 {
                oldValue?.contentInset.bottom -= lastKeyboardScrollInset
                oldValue?.verticalScrollIndicatorInsets.bottom -= lastKeyboardScrollInset
            }
            lastKeyboardScrollInset = keyboardOverlap
            primaryScrollView?.contentInset.bottom += lastKeyboardScrollInset
            primaryScrollView?.verticalScrollIndicatorInsets.bottom += lastKeyboardScrollInset
        }
    }

    public weak var delegate: AetherModalControllerDelegate?

    /// Optional presentation/dismissal animation provider.
    ///
    /// `nil` keeps the default bottom-sheet slide animation. Set this to
    /// `AetherModalSourceTransition(sourceView:)` for Telegram-style
    /// expansion from a button, or provide your own
    /// `AetherModalTransitionAnimation` implementation for fully custom
    /// UIKit transition animators.
    public var transitionAnimation: AetherModalTransitionAnimation?

    public private(set) var currentDetent: Detent = .stage1
    public var currentDetentProgress: CGFloat { detentProgress }

    /// Created only after the modal's explicit and controller-local appearance
    /// have been resolved. `GlassBackgroundView`'s style-aware initializer
    /// enters its classic UIKit-material branch directly for Legacy.
    private var glassBackground: GlassBackgroundView!
    private let tintOverlayView = UIView()
    private let grabberContainer = UIView()
    private let grabberView = UIView()
    private let footerHost = AetherModalFooterHostView()
    private let incomingFooterHost = AetherModalFooterHostView()
    private let maskLayer = CAShapeLayer()

    /// Footer's contribution to `additionalSafeAreaInsets.bottom`.
    /// Tracked separately so subclasses can add to the same bottom inset
    /// without us overwriting their delta.
    private var lastFooterBottomInset: CGFloat = 0
    /// Current keyboard overlap (in modal's coordinate space). Updated
    /// from `UIResponder.keyboardWillChangeFrameNotification` so the
    /// footer slides up over the keyboard and `primaryScrollView`'s
    /// `contentInset.bottom` includes the obscured area. The didSet
    /// marks layout dirty so the next `view.layoutIfNeeded()` call
    /// (driven from inside the keyboard animation block) actually
    /// reaches `layoutFooter()` and slides the footer over the
    /// keyboard — without it the call would be a no-op and the
    /// footer would stay flush against the modal's bottom edge.
    private var keyboardFrameInWindow: CGRect?
    private var keyboardOverlap: CGFloat = 0 {
        didSet {
            if oldValue != keyboardOverlap, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }
    /// Our contribution to `primaryScrollView.contentInset.bottom` for
    /// keyboard handling. Delta-tracked so the caller's baseline
    /// `contentInset.bottom` (anything they set themselves before the
    /// keyboard appears) survives our adjustments.
    private var lastKeyboardScrollInset: CGFloat = 0
    private var keyboardObserversInstalled = false

    private var lastAppliedGlassSize: CGSize = .zero

    private(set) var isInteractivelyResizing = false
    var isContentTransitioning: Bool { false }
    var reservesFooterSafeArea: Bool { true }

    private struct FooterTransition {
        let source: AetherModalFooterConfiguration
        let target: AetherModalFooterConfiguration
        let direction: NavigationTransitionDirection
        var progress: CGFloat
        var sourceOffsetFraction: CGFloat?
        var targetOffsetFraction: CGFloat?
    }
    private var footerTransition: FooterTransition?

    private func invalidateFooterEdgeCache() {
        if isViewLoaded {
            view.setNeedsLayout()
        }
    }

    /// Height of the grabber container area at the top of the sheet.
    /// Content anchored to `view.safeAreaLayoutGuide.topAnchor` ends up
    /// below this strip — the modal pushes a matching top inset onto
    /// `additionalSafeAreaInsets` for the entire content subtree.
    public static let grabberContainerHeight: CGFloat = 17.0
    private static let grabberSize: CGSize = CGSize(width: 36.0, height: 5.0)

    private let modalTransitioningDelegate: AetherModalTransitioningDelegate

    public init(config: Config = Config()) {
        let inheritedAppearance = AetherAppearance.runtimeCurrent
        self.config = config
        self.inheritedAppearance = inheritedAppearance
        self.appliedAppearanceStyle = inheritedAppearance.style
        self.contentView = UIView()
        self.modalTransitioningDelegate = AetherModalTransitioningDelegate()
        super.init(node: ASDisplayNode(viewBlock: {
            RootView()
        }))
        modalPresentationStyle = .custom
        transitioningDelegate = modalTransitioningDelegate
        AetherAppearanceConsumerRegistry.register(self)
    }

    public convenience init(
        config: Config = Config(),
        appearanceStyle: AetherAppearanceStyle
    ) {
        self.init(config: config)
        self.appearanceStyle = appearanceStyle
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Notification-center observers retain self until removed.
        // Footer keyboard observation is the only one we install — drop
        // it unconditionally; it's a no-op if we never registered.
        NotificationCenter.default.removeObserver(self)
    }

    /// Content whose local appearance participates in the modal surface
    /// decision. Navigation-backed modals already know their root before view
    /// loading, which lets us honor that provider without materializing any
    /// renderer first.
    private var hostedAppearanceContentController: UIViewController? {
        if let navigationModal = self as? AetherModalNavigationController {
            return navigationModal.topViewController
                ?? navigationModal.internalNavigationController
        }
        if let nodeNavigationModal = self as? AetherModalNodeNavigationController {
            return nodeNavigationModal.internalNavigationController
        }
        return nil
    }

    private func resolvedAppearanceStyle(
        for appearance: AetherAppearance
    ) -> AetherAppearanceStyle {
        // Seed provider contexts with the explicit style when present, while
        // keeping the explicit modal value authoritative after the local
        // inheritance chain has been evaluated.
        let seededAppearance = appearance.resolvingAppearanceStyle(appearanceStyle)
        let modalResolution = resolveAetherAppearanceOverride(
            appearance: seededAppearance,
            surface: .navigation,
            placement: .navigation,
            traitCollection: traitCollection,
            container: presentingViewController,
            content: self
        )

        let contentResolution: AetherAppearanceOverrideResolution
        if let hostedAppearanceContentController,
           hostedAppearanceContentController !== self {
            contentResolution = resolveAetherAppearanceOverride(
                appearance: modalResolution.appearance,
                surface: .navigation,
                placement: .navigation,
                traitCollection: traitCollection,
                container: nil,
                content: hostedAppearanceContentController
            )
        } else {
            contentResolution = modalResolution
        }

        return appearanceStyle ?? contentResolution.appearance.style
    }

    private func applyResolvedAppearance(animated: Bool) {
        let resolvedStyle = resolvedAppearanceStyle(for: inheritedAppearance)
        appliedAppearanceStyle = resolvedStyle
        propagateResolvedAppearanceToHostedNavigation(resolvedStyle)

        if !resolvedStyle.usesLiquidGlass {
            // A source morph owns a display link, property animator, snapshots
            // and (on supported systems) UIGlassEffect. Finish that transition
            // synchronously before replacing the modal surface with Legacy.
            (transitionAnimation as? AetherModalLiquidTransitionStateControlling)?
                .aetherModalCancelLiquidTransitionState()

        }

        guard isViewLoaded, let glassBackground else { return }
        glassBackground.appearanceStyleOverride = resolvedStyle
        lastCornerSignature = nil
        lastAppliedGlassSize = .zero
        invalidateFooterEdgeCache()
        view.setNeedsLayout()
        if !animated {
            view.layoutIfNeeded()
        }
    }

    /// Resolved style used by transition factories before they allocate a
    /// generation-specific animator or source-morph surface.
    internal var resolvedAppearanceStyleForModalTransition: AetherAppearanceStyle {
        resolvedAppearanceStyle(for: inheritedAppearance)
    }

    internal var appearanceStyleForTesting: AetherAppearanceStyle {
        resolvedAppearanceStyleForModalTransition
    }

    internal var modalSurfaceForTesting: GlassBackgroundView? {
        glassBackground
    }

    internal var hasLiquidModalSurfaceForTesting: Bool {
        glassBackground?.usesAnyGlassRendererForTesting ?? false
    }

    internal var legacyModalBlurStyleForTesting: UIBlurEffect.Style? {
        glassBackground?.legacyBlurStyleForTesting
    }

    internal var hasFooterLiquidEdgeEffectForTesting: Bool {
        footerHost.hasEdgeEffect && appliedAppearanceStyle.usesLiquidGlass
    }

    private func propagateResolvedAppearanceToHostedNavigation(
        _ resolvedStyle: AetherAppearanceStyle
    ) {
        guard let navigationModal = self as? AetherModalNavigationController else {
            return
        }
        navigationModal.internalNavigationController.updateAppearance(
            inheritedAppearance.resolvingAppearanceStyle(resolvedStyle)
        )
    }

    /// Composition helper — embeds an existing VC inside `contentView`.
    /// Equivalent to wiring up `addChild` + `addSubview` + `didMove`
    /// manually with full-bounds auto-resizing. Safe to call before
    /// `viewDidLoad`; the embed is queued and flushed when the view
    /// loads. Use this for "I have an existing VC, please host it"
    /// — for fully-custom layouts, just add subviews to `contentView`
    /// directly inside `viewDidLoad`.
    public func embedContent(_ child: UIViewController) {
        pendingEmbed = child
        if isViewLoaded {
            flushPendingEmbed()
        }
    }

    public func embedContent(_ node: AetherScreenNode) {
        embedContent(AetherScreenController(screenNode: node))
    }

    public func setContentNode(_ node: ASDisplayNode?) {
        contentNode?.view.removeFromSuperview()
        contentNode = node
        guard let node else { return }
        node.view.frame = contentView.bounds
        node.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(node.view)
    }

    private var pendingEmbed: UIViewController?
    private var contentNode: ASDisplayNode?

    private func flushPendingEmbed() {
        guard let child = pendingEmbed else { return }
        pendingEmbed = nil
        addChild(child)
        child.view.frame = contentView.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(child.view)
        child.didMove(toParent: self)
    }

    open override func loadView() {
        super.loadView()
        guard let root = view as? RootView else { return }
        root.backgroundColor = .clear
        root.grabberSafeAreaHeight = config.showsGrabber ? Self.grabberContainerHeight : 0

        // Resolve before allocation. In particular, do not construct a
        // default-runtime Liquid surface and switch it to a local Legacy
        // override afterward: UIGlassEffect/private backdrop objects would
        // already have existed for that interval.
        let resolvedStyle = resolvedAppearanceStyle(for: inheritedAppearance)
        appliedAppearanceStyle = resolvedStyle
        propagateResolvedAppearanceToHostedNavigation(resolvedStyle)
        let glassBackground = GlassBackgroundView(
            style: .regular,
            appearanceStyle: resolvedStyle
        )
        glassBackground.surfaceRole = .card
        self.glassBackground = glassBackground
        // Live material and navigation are siblings in the same coordinates.
        // A material must never be captured in a scaled/rasterized page tree.
        root.addSubview(glassBackground)
        glassBackground.isUserInteractionEnabled = false
        glassBackground.glassIsInteractive = false
        tintOverlayView.backgroundColor = config.dimTintColor
        tintOverlayView.isUserInteractionEnabled = false
        root.addSubview(tintOverlayView)
        root.addSubview(contentView)
        root.addSubview(footerHost)
        root.addSubview(incomingFooterHost)
        root.addSubview(grabberContainer)
        incomingFooterHost.isHidden = true

        grabberView.backgroundColor = UIColor.label.withAlphaComponent(0.28)
        grabberView.layer.cornerRadius = Self.grabberSize.height / 2.0
        grabberView.layer.cornerCurve = .continuous
        grabberView.isUserInteractionEnabled = false
        grabberContainer.isUserInteractionEnabled = false
        grabberContainer.isHidden = !config.showsGrabber
        grabberContainer.addSubview(grabberView)

    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        flushPendingEmbed()
        // Always observe the keyboard — even modals with no footer
        // benefit from the automatic `primaryScrollView.contentInset`
        // adjustment so subclasses don't have to roll their own
        // `keyboardWillChangeFrame` observer.
        installKeyboardObserversIfNeeded()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChrome()
        updateCornerShape()
    }

    /// Total height for `Config.sizesToContent` at the current container
    /// width after subtracting side margins. Override to measure your content,
    /// including grabber space and bottom safe-area padding. The supplied
    /// bottom inset is already reduced by the sheet's bottom margin, so it
    /// must not be subtracted again. The sheet stays within the safe-area top.
    ///
    /// The default uses `preferredContentSize.height` when supplied;
    /// otherwise it fits the content host's Auto Layout constraints and adds
    /// the grabber and bottom safe-area padding.
    open func contentHeight(forWidth width: CGFloat, safeAreaInsets: UIEdgeInsets) -> CGFloat {
        if preferredContentSize.height > 0 {
            return preferredContentSize.height
        }
        loadViewIfNeeded()
        let contentSize = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return contentSize.height
            + (config.showsGrabber ? Self.grabberContainerHeight : 0)
            + max(0, safeAreaInsets.bottom)
    }

    public func setDetent(_ detent: Detent, animated: Bool) {
        guard let presentation = presentationController as? AetherModalPresentationController else {
            return
        }
        presentation.setDetent(detent, animated: animated)
    }

    private var detentProgress: CGFloat = 0.0

    func applyDetentProgress(_ progress: CGFloat) {
        let clamped = max(0.0, min(1.0, progress))

        // Changing UIGlassEffect.tintColor creates a fresh effect and
        // invalidates the entire glass hierarchy. Doing that for every
        // pan update was the remaining drag hot path on iOS 26. Keep the
        // effect itself stable and animate a plain overlay's opacity — a
        // single compositing property with no layout or effect rebuild.
        let effectiveAlpha: CGFloat
        if usesNativeGlassBackend {
            effectiveAlpha = clamped
        } else {
            let legacyFloor: CGFloat = 0.5
            effectiveAlpha = max(legacyFloor, clamped)
        }
        tintOverlayView.alpha = effectiveAlpha

        guard abs(detentProgress - clamped) > 0.0001 else { return }
        detentProgress = clamped
        if isViewLoaded { view.setNeedsLayout() }
        delegate?.modalController(self, didUpdateDetentProgress: clamped)
    }

    private var usesNativeGlassBackend: Bool {
        guard appliedAppearanceStyle.usesLiquidGlass else {
            return false
        }
        if #available(iOS 26.0, *) {
            return GlassCompatibility.isLiquidDesignAvailable
                && !GlassBackgroundView.useCustomGlassImpl
        }
        return false
    }

    func applyCurrentDetent(_ detent: Detent) {
        guard currentDetent != detent else { return }
        currentDetent = detent
        delegate?.modalController(self, didChangeDetent: detent)
    }

    private func layoutChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = view.bounds
        if let keyboardFrameInWindow, let window = view.window {
            let keyboard = view.convert(keyboardFrameInWindow, from: window)
            let intersection = bounds.intersection(keyboard)
            keyboardOverlap = intersection.isNull ? 0 : intersection.height
            syncPrimaryScrollViewKeyboardInset()
        }
        glassBackground.frame = bounds
        if lastAppliedGlassSize != bounds.size {
            lastAppliedGlassSize = bounds.size
            glassBackground.update(size: bounds.size, cornerRadius: 0, transition: .immediate)
        }
        contentView.frame = bounds
        tintOverlayView.frame = bounds
        grabberContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.grabberContainerHeight)
        grabberView.frame = CGRect(
            x: (bounds.width - Self.grabberSize.width) / 2,
            y: (Self.grabberContainerHeight - Self.grabberSize.height) / 2,
            width: Self.grabberSize.width, height: Self.grabberSize.height
        )
        layoutFooter()
    }

    private var currentFooterConfiguration: AetherModalFooterConfiguration {
        AetherModalFooterConfiguration(view: footerView, height: footerHeight,
            fadeHeight: footerEdgeFadeHeight, tintColor: footerEdgeTintColor,
            blurRadius: footerEdgeBlurRadius, drawsEdge: footerEdgeEffectEnabled)
    }

    func applyFooterConfiguration(_ configuration: AetherModalFooterConfiguration) {
        footerView = configuration.view
        footerHeight = configuration.visibleHeight
        footerEdgeFadeHeight = configuration.fadeHeight
        footerEdgeTintColor = configuration.tintColor
        footerEdgeBlurRadius = configuration.blurRadius
        footerEdgeEffectEnabled = configuration.drawsEdge
        if isViewLoaded { layoutFooter() }
    }

    func beginFooterTransition(from source: AetherModalFooterConfiguration,
                               to target: AetherModalFooterConfiguration,
                               direction: NavigationTransitionDirection) {
        footerTransition = FooterTransition(source: source, target: target, direction: direction, progress: 0)
        footerHost.configure(source)
        if source.view !== target.view {
            incomingFooterHost.configure(target)
        }
        footerHost.isUserInteractionEnabled = false
        incomingFooterHost.isUserInteractionEnabled = false
        layoutFooter()
    }

    func updateFooterTransition(progress: CGFloat, sourceOffset: CGFloat, targetOffset: CGFloat) {
        guard footerTransition != nil else { return }
        footerTransition?.progress = progress
        let width = max(1, view.bounds.width)
        footerTransition?.sourceOffsetFraction = sourceOffset / width
        footerTransition?.targetOffsetFraction = targetOffset / width
        layoutFooter()
    }

    func endFooterTransition(completed: Bool) {
        guard let transition = footerTransition else { return }
        footerTransition = nil
        // Detach the incoming slot before transferring its content to the
        // persistent slot. Reassigning the same view also restores ownership.
        incomingFooterHost.configure(AetherModalFooterConfiguration())
        incomingFooterHost.isHidden = true
        footerHost.isUserInteractionEnabled = true
        applyFooterConfiguration(completed ? transition.target : transition.source)
    }

    private func layoutFooter() {
        guard isViewLoaded else { return }
        let width = view.bounds.width
        let bottom = max(0, view.bounds.height - keyboardOverlap)
        var sourceOffset: CGFloat = 0
        var targetOffset: CGFloat = 0
        var sourceVisibleWidth: CGFloat?
        if let state = footerTransition {
            if state.source.view !== state.target.view {
                switch state.direction {
                case .push:
                    sourceOffset = -width * 0.3 * state.progress
                    targetOffset = width * (1 - state.progress)
                    view.insertSubview(footerHost, belowSubview: incomingFooterHost)
                case .pop:
                    sourceOffset = width * state.progress
                    targetOffset = -width * 0.3 * (1 - state.progress)
                    view.insertSubview(incomingFooterHost, belowSubview: footerHost)
                }
                sourceOffset = state.sourceOffsetFraction.map { $0 * width } ?? sourceOffset
                targetOffset = state.targetOffsetFraction.map { $0 * width } ?? targetOffset
                let targetVisibleWidth: CGFloat?
                switch state.direction {
                case .push:
                    sourceVisibleWidth = targetOffset - sourceOffset
                    targetVisibleWidth = nil
                case .pop:
                    targetVisibleWidth = sourceOffset - targetOffset
                }
                incomingFooterHost.update(width: width, bottom: bottom, offsetX: targetOffset, visibleWidth: targetVisibleWidth,
                    usesLiquidGlass: appliedAppearanceStyle.usesLiquidGlass, defaultTint: config.dimTintColor)
            }
        } else {
            footerHost.configure(currentFooterConfiguration)
        }
        footerHost.update(width: width, bottom: bottom, offsetX: sourceOffset, visibleWidth: sourceVisibleWidth,
            usesLiquidGlass: appliedAppearanceStyle.usesLiquidGlass, defaultTint: config.dimTintColor)

        let inheritedBottom = max(0, view.safeAreaInsets.bottom - lastFooterBottomInset)
        let target = reservesFooterSafeArea ? max(0, currentFooterConfiguration.visibleHeight - inheritedBottom) : 0
        if abs(target - lastFooterBottomInset) > 0.5 {
            let delta = target - lastFooterBottomInset
            lastFooterBottomInset = target
            additionalSafeAreaInsets.bottom += delta
        }
    }

    // MARK: - Keyboard observation

    private func installKeyboardObserversIfNeeded() {
        guard !keyboardObserversInstalled else { return }
        keyboardObserversInstalled = true
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleKeyboardWillChange(_:)),
                       name: UIResponder.keyboardWillChangeFrameNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleKeyboardWillHide(_:)),
                       name: UIResponder.keyboardWillHideNotification,
                       object: nil)
    }

    @objc private func handleKeyboardWillChange(_ note: Notification) {
        guard
            let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
            let window = view.window
        else { return }
        let converted: CGRect
        if let screen = window.windowScene?.screen {
            let frameInWindow = screen.coordinateSpace.convert(end, to: window)
            keyboardFrameInWindow = frameInWindow
            converted = view.convert(frameInWindow, from: window)
        } else {
            converted = view.convert(end, from: nil)
            keyboardFrameInWindow = window.convert(end, from: nil)
        }
        let intersection = view.bounds.intersection(converted)
        let overlap = intersection.isNull ? 0 : intersection.height
        applyKeyboardOverlap(overlap, using: note)
    }

    @objc private func handleKeyboardWillHide(_ note: Notification) {
        keyboardFrameInWindow = nil
        applyKeyboardOverlap(0, using: note)
    }

    private func applyKeyboardOverlap(_ overlap: CGFloat, using note: Notification) {
        guard abs(keyboardOverlap - overlap) > 0.5 else { return }
        keyboardOverlap = overlap
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        // Drive layout + scroll-inset adjustment inside the keyboard's
        // own animation curve so the footer rides up flush with the
        // keyboard top and `primaryScrollView` content drifts up in
        // lockstep — instead of either catching up a frame later.
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
            self.syncPrimaryScrollViewKeyboardInset()
        }
        // Pull the active first responder into view AFTER its containing
        // scroll has been resized for the keyboard. `scrollRectToVisible`
        // is a no-op when the rect is already inside the visible area,
        // so this is harmless when the responder is above the keyboard.
        if overlap > 0 {
            scrollFirstResponderIntoView()
        }
    }

    /// Moves our keyboard contribution into `primaryScrollView.contentInset.bottom`
    /// (and the scroll-indicator inset) via a delta. Caller-set baselines
    /// on the scroll view's bottom inset survive — we only add/remove our
    /// own contribution.
    private func syncPrimaryScrollViewKeyboardInset() {
        let target = keyboardOverlap
        guard abs(target - lastKeyboardScrollInset) > 0.5 else { return }
        let delta = target - lastKeyboardScrollInset
        lastKeyboardScrollInset = target
        primaryScrollView?.contentInset.bottom += delta
        primaryScrollView?.verticalScrollIndicatorInsets.bottom += delta
    }

    /// Walks `primaryScrollView`'s subview tree, finds the active first
    /// responder, and scrolls a small padded rect around it into the
    /// visible area. No-op if no responder lives inside the scroll, or
    /// the responder is already on-screen.
    private func scrollFirstResponderIntoView() {
        guard let scroll = primaryScrollView,
              let responder = Self.findFirstResponder(in: scroll) else { return }
        var rect = responder.convert(responder.bounds, to: scroll)
        // Small breathing margin above + below the responder so the
        // caret sits a little inside the visible area, not flush against
        // the keyboard edge.
        rect = rect.insetBy(dx: 0, dy: -16)
        scroll.scrollRectToVisible(rect, animated: false)
    }

    private static func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let r = findFirstResponder(in: sub) { return r }
        }
        return nil
    }

    func beginInteractiveResize() {
        isInteractivelyResizing = true
    }

    func endInteractiveResize() {
        isInteractivelyResizing = false
    }

    private struct MaskSignature: Equatable {
        let bounds: CGRect
        let topRadius: CGFloat
        let bottomRadius: CGFloat
    }
    private var lastMaskSignature: MaskSignature?
    private struct CornerSignature: Equatable {
        let topRadius: CGFloat
        let bottomRadius: CGFloat
        let bottomCornersFollowContainer: Bool
        let clipsRoot: Bool
    }
    private var lastCornerSignature: CornerSignature?

    /// Numeric radii for the legacy sheet and optional source morph. On
    /// iOS 26+, container-following bottom corners use this as their minimum.
    func resolvedCornerRadii(for size: CGSize? = nil) -> (top: CGFloat, bottom: CGFloat) {
        let boundsSize = size ?? view.bounds.size
        let limit = max(0, min(boundsSize.width, boundsSize.height) / 2)
        let top = max(0, min(config.topCornerRadius, limit))
        let compact = config.bottomCornerRadiusStage1 ?? config.topCornerRadius
        let expanded = config.bottomCornerRadiusStage2
            ?? (config.bottomInsetStage2 > 0 ? config.topCornerRadius : 0)
        let bottom = compact + (expanded - compact) * detentProgress
        return (top, max(0, min(bottom, limit)))
    }

    private func updateCornerShape() {
        if #available(iOS 26.0, *) {
            applyCornerConfiguration(clipRoot: true)
        } else {
            updateMaskPath()
        }
    }

    @available(iOS 26.0, *)
    private func applyCornerConfiguration(clipRoot: Bool) {
        let (topRadius, bottomRadius) = resolvedCornerRadii()
        let signature = CornerSignature(
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            bottomCornersFollowContainer: config.bottomCornersFollowContainer,
            clipsRoot: clipRoot
        )
        if signature == lastCornerSignature { return }
        lastCornerSignature = signature

        let configuration = UICornerConfiguration.uniformEdges(
            topRadius: .fixed(topRadius),
            bottomRadius: config.bottomCornersFollowContainer
                ? .containerConcentric(minimum: bottomRadius)
                : .fixed(bottomRadius)
        )
        // Disable implicit CALayer animations on the property writes —
        // `cornerConfiguration` setters can otherwise kick off a default
        // animation between successive pan ticks, which on a 120Hz slow
        // drag stack into visible jitter as the modal frame edges chase
        // their own animated values.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Identical unscaled geometry for the sheet and its live material.
        view.cornerConfiguration = configuration
        glassBackground.setNativeCornerConfiguration(configuration)
        view.clipsToBounds = clipRoot
        // The mask layer is the alternate, expensive path — drop it so
        // we don't end up with both a corner-config shape AND a stale
        // CAShapeLayer mask competing.
        if view.layer.mask === maskLayer {
            view.layer.mask = nil
        }
        view.layer.cornerRadius = 0
        CATransaction.commit()
    }

    private func updateMaskPath() {
        let bounds = view.bounds
        let (topRadius, bottomRadius) = resolvedCornerRadii()

        // Equal corners use the continuous CALayer path.
        if topRadius == bottomRadius {
            if view.layer.mask != nil {
                view.layer.mask = nil
            }
            view.layer.cornerCurve = .continuous
            view.layer.masksToBounds = true
            if abs(view.layer.cornerRadius - topRadius) > 0.01 {
                view.layer.cornerRadius = topRadius
            }
            // Drop the cached path signature — the next time corners go
            // asymmetric again (theme switch?), updateMaskPath will
            // re-wire the CAShapeLayer mask from scratch.
            lastMaskSignature = nil
            return
        }

        // Pre-iOS 26 needs a path for independent top and bottom radii.
        if view.layer.mask !== maskLayer {
            view.layer.cornerRadius = 0.0
            view.layer.masksToBounds = false
            view.layer.mask = maskLayer
        }

        let signature = MaskSignature(bounds: bounds, topRadius: topRadius, bottomRadius: bottomRadius)
        if signature == lastMaskSignature {
            return
        }
        lastMaskSignature = signature

        let newPath = Self.roundedRectPath(
            in: bounds,
            topLeftRadius: topRadius,
            topRightRadius: topRadius,
            bottomLeftRadius: bottomRadius,
            bottomRightRadius: bottomRadius
        ).cgPath

        let oldPath = maskLayer.path
        maskLayer.frame = bounds
        maskLayer.path = newPath

        if UIView.inheritedAnimationDuration <= 0, oldPath != newPath {
            maskLayer.removeAnimation(forKey: "path")
        }
    }

    /// Root view for the presented modal. UIKit propagates the window's
    /// full safe area (including the status bar) to the presented view even
    /// when the sheet frame doesn't overlap the status bar — this override
    /// computes the top inset from the sheet's actual position in the
    /// window so content anchored to `view.safeAreaLayoutGuide.topAnchor`
    /// doesn't get a phantom status-bar-sized gap at the top.
    private final class RootView: UIView {
        var grabberSafeAreaHeight: CGFloat = AetherModalController.grabberContainerHeight

        override var safeAreaInsets: UIEdgeInsets {
            let inherited = super.safeAreaInsets
            let topInWindow = convert(CGPoint.zero, to: nil).y
            let windowSafeTop = window?.safeAreaInsets.top ?? 0.0
            let overlap = max(0.0, windowSafeTop - topInWindow)
            // Reserve the grabber strip as the modal's top safe area —
            // subclass content (or any embedded child VC) anchored to
            // `safeAreaLayoutGuide.topAnchor` ends up below the grabber
            // pill. Bundling it here (as opposed to into
            // `additionalSafeAreaInsets`) keeps `applyCompensatedSafeAreaTop`'s
            // formula a stable fixed-point — adding `additional` would
            // grow without bound because this override discards the
            // additional-derived top that the formula tries to subtract.
            return UIEdgeInsets(
                top: overlap + grabberSafeAreaHeight,
                left: inherited.left,
                bottom: inherited.bottom,
                right: inherited.right
            )
        }
    }

    private static func roundedRectPath(
        in rect: CGRect,
        topLeftRadius tl: CGFloat,
        topRightRadius tr: CGFloat,
        bottomLeftRadius bl: CGFloat,
        bottomRightRadius br: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(
            withCenter: CGPoint(x: w - tr, y: tr),
            radius: tr,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(
            withCenter: CGPoint(x: w - br, y: h - br),
            radius: br,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(
            withCenter: CGPoint(x: bl, y: h - bl),
            radius: bl,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(
            withCenter: CGPoint(x: tl, y: tl),
            radius: tl,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        path.close()
        return path
    }
}

extension AetherModalController: AetherAppearanceConsumer {
    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        inheritedAppearance = appearance
        applyResolvedAppearance(animated: animated)
    }
}
