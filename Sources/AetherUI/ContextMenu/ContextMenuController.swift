import UIKit
import AsyncDisplayKit

/// Classic dimming host used by Legacy context menus. This deliberately uses
/// only public UIKit material; it must never share the Liquid CAFilter/SDF
/// backdrop implementation used by `ContextMenuDimBlurView`.
final class ContextMenuLegacyDimView: UIVisualEffectView {
    let blurStyle: UIBlurEffect.Style

    init(tintColor: UIColor) {
        let blurStyle: UIBlurEffect.Style = .systemChromeMaterial
        self.blurStyle = blurStyle
        super.init(effect: UIBlurEffect(style: blurStyle))
        contentView.backgroundColor = tintColor
        contentView.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - ContextMenuController

/// Presents an action menu that grows out of its source button. Presentation
/// follows the resolved appearance automatically; both current generations
/// share the glassmorphic transition engine. An optional preview keeps lifted
/// source content above the menu instead of replacing the source surface.
public final class ContextMenuController: AetherAppearanceConsumer {
    // MARK: - Animation constants

    internal static let glassmorphicTiming = ContextMenuGlassmorphicTiming(
        // This renderer spends the last ~230 ms settling its shared surface
        // and row overscale. The generic source morph has a different clock.
        openDuration: 0.60,
        closeDuration: AetherMotion.contextMenu.dismissal.duration
    )
    private static let previewOpenDuration: TimeInterval = 0.29
    private static let previewDismissDuration: TimeInterval = 0.29
    private static let previewDismissMenuScale: CGFloat = 0.82
    private static let previewDismissMenuOffsetY: CGFloat = 14.0
    private static let previewDismissAccessoryScale: CGFloat = 0.84
    private static let previewDamping: CGFloat = 0.77
    private static let dismissDamping: CGFloat = 0.90

    private static func previewBezierTimingParameters() -> UICubicTimingParameters {
        UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.2, y: 0.8),
            controlPoint2: CGPoint(x: 0.2, y: 1.0)
        )
    }

    private static let dimAlpha: CGFloat = 0.08  // very faint separation veil (rec: ≤0.06-0.12)
    /// Radius of the backdrop blur applied to the dim layer, in points.
    /// Uses a raw CABackdropLayer + CAFilter("gaussianBlur"), so any
    /// non-negative radius works (unlike UIBlurEffect which snaps to
    /// a few fixed styles). 0 disables the blur and falls back to a
    /// plain tint. 2pt is the "barely-there" default — enough to
    /// soften the edges of background content without making it
    /// unreadable.
    public static var dimBlurRadius: CGFloat = 0.05
    public static var previewBlurRadius: CGFloat {
        get { dimBlurRadius }
        set { dimBlurRadius = newValue }
    }

    // MARK: - Self-retention

    private static var presentedControllers: Set<ContextMenuControllerBox> = []
    private lazy var retainBox = ContextMenuControllerBox(controller: self)

    // MARK: - Inputs

    public struct Source {
        public weak var view: UIView?
        public var cornerRadius: CGFloat?
        /// Source menus always lease and suppress the original view while a
        /// presentation proxy owns its appearance. This flag also describes
        /// the source intent for custom presentation integrations.
        public var hidesDuringPresentation: Bool

        public init(view: UIView, cornerRadius: CGFloat? = nil, hidesDuringPresentation: Bool = true) {
            self.view = view
            self.cornerRadius = cornerRadius
            self.hidesDuringPresentation = hidesDuringPresentation
        }

        public init(node: ASDisplayNode, cornerRadius: CGFloat? = nil, hidesDuringPresentation: Bool = true) {
            self.init(view: node.view, cornerRadius: cornerRadius, hidesDuringPresentation: hidesDuringPresentation)
        }
    }

    public struct PreviewContent {
        public let view: UIView
        public let preferredSize: CGSize

        public init(view: UIView, preferredSize: CGSize) {
            self.view = view
            self.preferredSize = preferredSize
        }

        public init(node: ASDisplayNode, preferredSize: CGSize) {
            self.init(view: node.view, preferredSize: preferredSize)
        }
    }

    public struct PreviewAccessory {
        public let view: UIView
        public let preferredSize: CGSize?
        public let spacing: CGFloat

        public init(view: UIView, preferredSize: CGSize? = nil, spacing: CGFloat = 8.0) {
            self.view = view
            self.preferredSize = preferredSize
            self.spacing = spacing
        }

        public init(node: ASDisplayNode, preferredSize: CGSize? = nil, spacing: CGFloat = 8.0) {
            self.init(view: node.view, preferredSize: preferredSize, spacing: spacing)
        }
    }

    /// Optional lifted content shown above the action menu.
    public struct Preview {
        public var verticalSpacing: CGFloat
        public var lift: CGFloat
        public var content: PreviewContent?
        public var accessory: PreviewAccessory?

        public init(
            verticalSpacing: CGFloat = 8.0,
            lift: CGFloat = 1.04,
            content: PreviewContent? = nil,
            accessory: PreviewAccessory? = nil
        ) {
            self.verticalSpacing = verticalSpacing
            self.lift = lift
            self.content = content
            self.accessory = accessory
        }
    }

    // MARK: - State

    private let source: Source
    private let items: [ContextMenuItem]
    private let preview: Preview?
    /// Exact renderer generation for this presentation. `nil` inherits the
    /// runtime appearance at the moment `present()` is called.
    public let appearanceStyle: AetherAppearanceStyle?
    private let onWillRemoveOverlay: (() -> Void)?
    private let onDismiss: (() -> Void)?
    private let catchTapsOutside: Bool
    private let hasHapticFeedback: Bool
    private let blurred: Bool
    private let isDark: Bool?
    private let skipCoordinateConversion: Bool

    private weak var hostView: UIView?
    private var dimView: UIView?
    private var glassmorphicHost: ContextMenuGlassmorphicTransitionView?
    /// Outer wrapper for the fixed-size menu below lifted preview content.
    private var previewMenuHost: UIView?
    private var menuContainer: MenuGlassSurfaceView?
    private var snapshotView: UIView?
    private var actionsView: ContextMenuActionsView?
    private var tapRecognizer: UITapGestureRecognizer?
    private var sourcePresentationLease: SourcePresentationLease?
    private var surfaceView: UIView? {
        glassmorphicHost?.finalMenuGlassSurfaceView ?? previewMenuHost
    }
    private var surfaceOverlayView: UIView? { surfaceView }
    /// Inline submenu overlay (Yandex Music style). When non-nil, the parent
    /// `actionsView` is dimmed + disabled and `submenuCard` is overlaid on
    /// the parent menu, anchored to the source row's Y position. Tap on the
    /// card's header chevron OR on the dimmed parent collapses it.
    private var submenuCard: MenuGlassSurfaceView?
    private var submenuActions: ContextMenuActionsView?
    /// Transparent hit-target placed inside the active menu surface while a
    /// submenu is open: catches taps that miss the submenu card and collapses
    /// instead of dismissing the entire menu.
    private var submenuCollapseHitView: UIView?

    /// Lifted source content, positioned in the overlay and scaled by the
    /// optional preview configuration.
    private var previewView: UIView?
    private var previewAccessoryContainer: UIView?
    private var previewInitialCenterInHost: CGPoint?
    private var previewFinalCenterInHost: CGPoint?

    private var menuFrameInHost: CGRect = .zero

    private var isPresented: Bool = false
    /// Retains the idempotent teardown while an animated dismissal is in
    /// flight. Appearance changes must be able to finish that teardown
    /// synchronously even though `isPresented` becomes false as soon as the
    /// dismiss animation starts.
    private var pendingCleanup: (() -> Void)?
    private var dismissHandle: ContextMenuDismissHandle?
    /// Original source opacity retained while a lifted preview is visible.
    private var savedSourceOpacity: Float?
    /// Original source transform captured while the menu owns the source
    /// fade/scale. Restored on dismiss so anchors that already had a custom
    /// transform are not flattened to identity.
    private var savedSourceTransform: CGAffineTransform?
    private var presentedAppearanceStyle: AetherAppearanceStyle?

    private var usesLiquidPresentation: Bool {
        (presentedAppearanceStyle ?? AetherAppearance.runtimeCurrent.style).usesLiquidGlass
    }

    private var resolvedAppearanceStyle: AetherAppearanceStyle {
        presentedAppearanceStyle
            ?? appearanceStyle
            ?? AetherAppearance.runtimeCurrent.style
    }

    private var resolvedMenuMetrics: ContextMenuActionsView.Metrics {
        ContextMenuActionsView.Metrics.resolve(for: resolvedAppearanceStyle)
    }

    private func applyLegacyReferenceShadow(
        to view: UIView,
        cornerRadius: CGFloat
    ) {
        guard resolvedAppearanceStyle == .legacy else { return }
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowRadius = 16.0
        view.layer.shadowOffset = .zero
        view.layer.shadowPath = UIBezierPath(
            roundedRect: view.bounds,
            cornerRadius: cornerRadius
        ).cgPath
    }

    // MARK: - Init

    public init(
        source: Source,
        items: [ContextMenuItem],
        preview: Preview? = nil,
        appearanceStyle: AetherAppearanceStyle? = nil,
        catchTapsOutside: Bool = true,
        hasHapticFeedback: Bool = true,
        blurred: Bool = true,
        isDark: Bool? = nil,
        skipCoordinateConversion: Bool = false,
        onWillRemoveOverlay: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.source = source
        self.items = items
        self.preview = preview
        self.appearanceStyle = appearanceStyle
        self.catchTapsOutside = catchTapsOutside
        self.hasHapticFeedback = hasHapticFeedback
        self.blurred = blurred
        self.isDark = isDark
        self.skipCoordinateConversion = skipCoordinateConversion
        self.onWillRemoveOverlay = onWillRemoveOverlay
        self.onDismiss = onDismiss
        AetherAppearanceConsumerRegistry.register(self)
    }

    private var usesLeasedSourcePresentation: Bool { preview == nil }

    private var resolvedPresentationStyle: ContextMenuPresentationStyle {
        resolvedAppearanceStyle.usesLiquidGlass ? .glassmorphic : .legacy
    }

    // MARK: - Public entry points

    /// Present the menu as an overlay on the window hosting the source view.
    public func present() {
        guard !isPresented,
              pendingCleanup == nil,
              let source = source.view,
              let window = source.window else { return }
        // Resolve appearance before creating any material. Both internal
        // presentation generations currently share one geometry engine.
        presentedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        isPresented = true
        ContextMenuController.presentedControllers.insert(retainBox)
        if hasHapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        let host = UIView(frame: window.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(host)
        self.hostView = host

        // A transparent background still owns outside taps. Zero view alpha
        // removes it from UIKit hit-testing, even with a recognizer attached.
        let hasClearBackground = usesLiquidPresentation && preview == nil
        let dim: UIView
        if hasClearBackground {
            dim = UIView()
            dim.backgroundColor = .clear
        } else if blurred {
            if usesLiquidPresentation {
                dim = ContextMenuDimBlurView(
                    blurRadius: ContextMenuController.dimBlurRadius,
                    tintAlpha: ContextMenuController.dimAlpha
                )
            } else {
                // Figma 754:62668 uses a real blurred dim layer behind the
                // lifted preview/menu. Legacy substitutes the mandated public
                // classic material and keeps its tint in the effect content.
                dim = ContextMenuLegacyDimView(
                    tintColor: UIColor(
                        red: 24.0 / 255.0,
                        green: 19.0 / 255.0,
                        blue: 43.0 / 255.0,
                        alpha: 0.21
                    )
                )
            }
        } else {
            let plainDim = UIView()
            plainDim.backgroundColor = usesLiquidPresentation
                ? UIColor.black.withAlphaComponent(ContextMenuController.dimAlpha)
                : AetherLegacySurfaceTokens
                    .resolve(role: .overlay, traitCollection: source.traitCollection)
                    .dimmingColor
            dim = plainDim
        }
        dim.frame = host.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.alpha = hasClearBackground ? 1 : 0
        dim.isUserInteractionEnabled = catchTapsOutside
        host.addSubview(dim)
        self.dimView = dim

        // Compute menu metrics.
        let menuMetrics = resolvedMenuMetrics
        let actionsView = ContextMenuActionsView(
            items: items,
            appearanceStyle: resolvedAppearanceStyle
        )
        let maxWidth = min(max(1.0, host.bounds.width - 24.0), menuMetrics.preferredWidth)
        let menuSize = actionsView.preferredSize(
            maxWidth: maxWidth,
            maxHeight: maximumMenuHeight(hostBounds: host.bounds)
        )
        var sourceCornerRadius = self.source.cornerRadius ?? source.layer.cornerRadius
        let activeSourceLease: SourcePresentationLease?
        let sourceVisualMode: ContextMenuSourceVisualMode?
        let sourceRectInHost: CGRect

        if usesLeasedSourcePresentation {
            guard let descriptor = makeSourceDescriptor(hitView: source, overlayView: host) else {
                host.removeFromSuperview()
                isPresented = false
                ContextMenuController.presentedControllers.remove(retainBox)
                return
            }
            let mode = descriptor.sourceMode
            let transitionMode: ContextMenuSourceVisualMode = .leasedGlassSource
            #if DEBUG
            print("ContextMenu source mode:", mode, "hit:", descriptor.hitView, "visual:", descriptor.visualView)
            #endif
            sourceVisualMode = transitionMode
            sourceCornerRadius = descriptor.sourceCornerRadius
            guard let lease = SourcePresentationLease(
                sourceID: ObjectIdentifier(descriptor.visualView),
                descriptor: descriptor,
                overlayView: host
            ) else {
                host.removeFromSuperview()
                isPresented = false
                ContextMenuController.presentedControllers.remove(retainBox)
                return
            }
            lease.acquire()
            self.sourcePresentationLease = lease
            activeSourceLease = lease
            sourceRectInHost = lease.sourceFrameInOverlay
            if sourceCornerRadius <= 0.0, Self.isGlassContextMenuSource(descriptor.visualView) || Self.isGlassContextMenuSource(descriptor.hitView) {
                sourceCornerRadius = min(sourceRectInHost.width, sourceRectInHost.height) / 2.0
            }
        } else if skipCoordinateConversion {
            activeSourceLease = nil
            sourceVisualMode = nil
            sourceRectInHost = source.frame
        } else {
            activeSourceLease = nil
            sourceVisualMode = nil
            sourceRectInHost = source.convert(source.bounds, to: host)
        }
        let previewLayout: PreviewLayout?
        let menuFrame: CGRect
        if let preview {
            let layout = computePreviewLayout(
                sourceRect: sourceRectInHost,
                menuSize: menuSize,
                hostBounds: host.bounds,
                verticalSpacing: preview.verticalSpacing,
                lift: preview.lift,
                content: preview.content,
                accessory: preview.accessory
            )
            previewLayout = layout
            menuFrame = layout.menuFrame
        } else {
            previewLayout = nil
            menuFrame = computeMenuFrame(sourceRect: sourceRectInHost, menuSize: menuSize, hostBounds: host.bounds)
        }
        #if DEBUG
        if usesLeasedSourcePresentation {
            assert(menuFrame.width <= host.bounds.width - 32.0 || host.bounds.width < 64.0, "Context menu target frame must be menu-sized, not overlay-sized.")
            assert(menuFrame.height < host.bounds.height * 0.75 || host.bounds.height < 64.0, "Context menu target frame is too tall for platter bloom geometry.")
            assert(menuFrame != host.bounds, "Context menu target frame must not equal overlay bounds.")
        }
        #endif
        self.menuFrameInHost = menuFrame

        let isDark = self.isDark ?? (source.traitCollection.userInterfaceStyle == .dark)
        if let previewLayout {
            let snapshot = makeSourceSnapshot(source: source)
            self.snapshotView = snapshot
            setupPreview(
                host: host,
                source: source,
                isDark: isDark,
                snapshot: snapshot,
                actionsView: actionsView,
                previewLayout: previewLayout
            )
        } else {
            guard let sourceVisualMode else { return }
            // The legacy presentation intentionally delegates to the same
            // engine for now; appearance still selects the actual material.
            switch resolvedPresentationStyle {
            case .legacy, .glassmorphic:
                setupGlassmorphic(
                    host: host,
                    isDark: isDark,
                    sourceLease: activeSourceLease,
                    sourceMode: sourceVisualMode,
                    actionsView: actionsView,
                    sourceRectInHost: sourceRectInHost,
                    sourceCornerRadius: sourceCornerRadius,
                    menuFrame: menuFrame
                )
            }
        }
        self.actionsView = actionsView

        // Tap-outside to dismiss.
        if catchTapsOutside {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
            dim.addGestureRecognizer(tap)
            self.tapRecognizer = tap
        }

        // Route action selection and submenu placement through the active surface.
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        if let surface = surfaceView {
            wireActionsView(actionsView, handle: handle, surfaceView: surface)
        }

        // Source menus already hold an exclusive lease. A lifted preview
        // instead fades the original under its independently positioned copy.
        if preview != nil {
            // Drive `UIView.alpha` (not `CALayer.opacity` directly) so
            // UIKit observers see the change — iOS 26's glass-effect
            // pipeline tracks alpha through the UIView setter, and a
            // direct `layer.opacity` write bypasses that and leaves
            // the shared `UIGlassContainerEffect` in a half-broken
            // "interactive but invisible" state where sibling glass
            // views in the same container also stop reacting to touch.
            self.savedSourceOpacity = Float(source.alpha)
            self.savedSourceTransform = source.transform
            UIView.animate(
                withDuration: ContextMenuController.previewOpenDuration * 0.82,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                source.alpha = 0
            }
        }

        animateIn(dim: dim)
    }

    /// Context menus own generation-specific transition objects which cannot
    /// be swapped in place safely. A global generation change therefore ends
    /// an inherited active presentation synchronously; the next presentation
    /// is created entirely in the new generation. An explicit local style
    /// remains authoritative and is unaffected by unrelated global changes.
    func aetherApplyAppearance(_ appearance: AetherAppearance, animated _: Bool) {
        guard (isPresented || pendingCleanup != nil || hostView != nil),
              let presentedAppearanceStyle else { return }
        let nextStyle = self.appearanceStyle ?? appearance.style
        guard nextStyle != presentedAppearanceStyle else { return }
        dismiss(animated: false)
    }

    internal var resolvedAppearanceStyleForTesting: AetherAppearanceStyle {
        resolvedAppearanceStyle
    }

    internal var isPresentedForTesting: Bool {
        isPresented
    }

    internal var hasLiquidTransitionResourcesForTesting: Bool {
        menuContainer?.usesLiquidSurfaceRendererForTesting == true
            || dimView is ContextMenuDimBlurView
    }

    internal var hasGlassmorphicTransitionForTesting: Bool { glassmorphicHost != nil }
    internal var usesSourcePresentationLeaseForTesting: Bool { sourcePresentationLease != nil }
    internal var resolvedPresentationStyleForTesting: ContextMenuPresentationStyle {
        resolvedPresentationStyle
    }

    internal var hasPresentationOverlayForTesting: Bool {
        hostView != nil
    }

    internal var menuUsesLegacySurfaceForTesting: Bool {
        menuContainer?.usesLegacySurfaceRendererForTesting == true
    }

    internal var menuLegacyBlurStyleForTesting: UIBlurEffect.Style? {
        menuContainer?.legacyBlurStyleForTesting
    }

    private func makeSourceDescriptor(hitView: UIView, overlayView: UIView) -> ContextMenuSourceDescriptor? {
        let visualView = Self.visualContextMenuSource(for: hitView)
        let mode = resolvedContextMenuSourceMode(hitView: hitView, visualView: visualView)
        let frame = visualView.convert(visualView.bounds, to: overlayView)
        var radius = source.cornerRadius ?? visualView.layer.cornerRadius
        if radius <= 0.0, mode == .leasedGlassSource {
            radius = min(frame.width, frame.height) / 2.0
        }
        return ContextMenuSourceDescriptor(
            sourceID: ObjectIdentifier(visualView),
            hitView: hitView,
            visualView: visualView,
            overlayView: overlayView,
            sourceCornerRadius: radius,
            sourceMode: mode
        )
    }

    private func resolvedContextMenuSourceMode(hitView: UIView, visualView: UIView) -> ContextMenuSourceVisualMode {
        if source.hidesDuringPresentation {
            return .leasedGlassSource
        }
        return Self.isGlassContextMenuSource(visualView) || Self.isGlassContextMenuSource(hitView) ? .leasedGlassSource : .persistentSource
    }

    private static func visualContextMenuSource(for hitView: UIView) -> UIView {
        var current: UIView? = hitView
        while let view = current {
            if let group = view as? GlassControlGroup,
               let visual = group.visualSourceView(containing: hitView) {
                return visual
            }
            if let group = view.superview as? GlassControlGroup,
               let visual = group.visualSourceView(containing: hitView) {
                return visual
            }
            if isGlassVisualOwner(view) {
                return view
            }
            current = view.superview
        }
        return hitView
    }

    private static func isGlassVisualOwner(_ view: UIView) -> Bool {
        if view is GlassBarButtonView
            || view is GlassButton
            || view is GlassButtonView
            || view is GlassControlGroup
            || view is GlassControlPanel
            || view is GlassContextExtractableContainerView
            || view is GlassBackgroundView
            || view is GlassBackgroundContainerView
            || view is LiquidLensView
            || view is MenuGlassSurfaceView {
            return true
        }

        if #available(iOS 26.0, *),
           let effectView = view as? UIVisualEffectView,
           effectView.effect is UIGlassEffect {
            return true
        }

        let className = NSStringFromClass(type(of: view))
        return className.localizedCaseInsensitiveContains("Glass")
    }

    private static func isGlassContextMenuSource(_ view: UIView) -> Bool {
        if view is GlassBarButtonView
            || view is GlassButton
            || view is GlassButtonView
            || view is GlassControlGroup
            || view is GlassControlPanel
            || view is GlassContextExtractableContainerView
            || view is GlassBackgroundView
            || view is GlassBackgroundContainerView
            || view is LiquidLensView
            || view is MenuGlassSurfaceView {
            return true
        }

        if #available(iOS 26.0, *),
           let effectView = view as? UIVisualEffectView,
           effectView.effect is UIGlassEffect {
            return true
        }

        let className = NSStringFromClass(type(of: view))
        if className.localizedCaseInsensitiveContains("Glass") {
            return true
        }

        for subview in view.subviews {
            if isGlassContextMenuSource(subview) {
                return true
            }
        }
        return false
    }

    // MARK: - Style-specific setup

    /// Connect the source lease and action content to the shared transition.
    private func setupGlassmorphic(
        host: UIView,
        isDark: Bool,
        sourceLease: SourcePresentationLease?,
        sourceMode: ContextMenuSourceVisualMode,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        sourceCornerRadius: CGFloat,
        menuFrame: CGRect
    ) {
        let platterHost = ContextMenuGlassmorphicTransitionView(
            sourceFrameInOverlay: sourceRectInHost,
            targetMenuFrameInOverlay: menuFrame,
            finalCornerRadius: resolvedMenuMetrics.cornerRadius,
            sourceCornerRadius: sourceCornerRadius,
            sourceMode: sourceMode,
            isDark: isDark,
            appearanceStyle: resolvedAppearanceStyle
        )
        platterHost.frame = host.bounds
        platterHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(platterHost)

        // The platter bloom always owns the visual source while presented:
        // glass and plain/content sources are represented by the leased proxy,
        // so the real source never remains visible/interactive underneath.
        sourceLease?.attachProxy(to: platterHost.sourceProxyContainer)
        platterHost.prepareSourceContentSnapshots()

        // Destination content is laid out at its final menu rect from the
        // beginning. The lens mask reveals it as the bloom grows/sharpens.
        actionsView.frame = platterHost.liveMenuContentView.bounds
        actionsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        actionsView.setRevealProgress(1)
        platterHost.liveMenuContentView.addSubview(actionsView)
        platterHost.prepareMenuContentSnapshots(from: actionsView)
        // The host already stages live/sharp/blurred content. Applying a
        // second row-level translation only to the live copy separates it
        // from its snapshots and doubles glyphs during the handoff.

        self.glassmorphicHost = platterHost
        self.menuContainer = platterHost.finalMenuGlassSurfaceView
    }

    private struct PreviewLayout {
        let initialPreviewFrame: CGRect
        let previewFrame: CGRect
        let menuFrame: CGRect
        let accessory: PreviewAccessory?
        let accessoryFrame: CGRect?
        let content: PreviewContent?
    }

    /// Places the action menu below lifted source content.
    private func setupPreview(
        host: UIView,
        source _: UIView,
        isDark: Bool,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        previewLayout: PreviewLayout
    ) {
        let menuFrame = previewLayout.menuFrame
        let previewMenuHost = UIView(frame: menuFrame)
        previewMenuHost.applyCornerRadius(
            resolvedMenuMetrics.cornerRadius,
            clipsChildren: false
        )
        applyLegacyReferenceShadow(
            to: previewMenuHost,
            cornerRadius: resolvedMenuMetrics.cornerRadius
        )
        host.addSubview(previewMenuHost)
        self.previewMenuHost = previewMenuHost

        let menuContainer = MenuGlassSurfaceView(
            isDark: isDark,
            appearanceStyle: resolvedAppearanceStyle
        )
        menuContainer.frame = previewMenuHost.bounds
        menuContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        menuContainer.setSurfaceCornerRadius(resolvedMenuMetrics.cornerRadius)
        previewMenuHost.addSubview(menuContainer)
        self.menuContainer = menuContainer

        // Lifted snapshot: its own wrapper at source rect with a soft
        // drop-shadow. Stays visible for the whole menu's lifetime.
        let preview = UIView(frame: previewLayout.initialPreviewFrame)
        let previewContentView = previewLayout.content?.view ?? snapshot
        previewContentView.frame = preview.bounds
        previewContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.addSubview(previewContentView)
        preview.layer.shadowColor = UIColor.black.cgColor
        if resolvedAppearanceStyle == .legacy {
            preview.layer.shadowOpacity = 0.2
            preview.layer.shadowRadius = 16.0
            preview.layer.shadowOffset = .zero
        } else {
            preview.layer.shadowOpacity = 0.18
            preview.layer.shadowRadius = 18.0
            preview.layer.shadowOffset = CGSize(width: 0, height: 8)
        }
        host.addSubview(preview)
        self.previewView = preview
        self.previewInitialCenterInHost = CGPoint(
            x: previewLayout.initialPreviewFrame.midX,
            y: previewLayout.initialPreviewFrame.midY
        )
        self.previewFinalCenterInHost = CGPoint(
            x: previewLayout.previewFrame.midX,
            y: previewLayout.previewFrame.midY
        )

        if let accessory = previewLayout.accessory,
           let accessoryFrame = previewLayout.accessoryFrame {
            let accessoryContainer = PreviewAccessoryContainerView(frame: accessoryFrame)
            accessoryContainer.clipsToBounds = false
            accessory.view.frame = accessoryContainer.bounds
            accessory.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            accessoryContainer.addSubview(accessory.view)
            host.addSubview(accessoryContainer)
            self.previewAccessoryContainer = accessoryContainer

            accessoryContainer.alpha = 0.0
            accessoryContainer.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }

        // Actions view fills the menu container.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        actionsView.alpha = 1.0
        menuContainer.contentView.addSubview(actionsView)

        // Pre-stage for spring-in.
        previewMenuHost.alpha = 0.0
        previewMenuHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else {
            if !animated {
                pendingCleanup?()
            }
            return
        }
        isPresented = false

        let sourceRestoreAlpha = savedSourceOpacity.map(CGFloat.init) ?? 1.0
        let sourceRestoreTransform = savedSourceTransform ?? .identity

        let host = hostView
        let dim = dimView
        let glassmorphicHost = self.glassmorphicHost
        let previewMenuHost = self.previewMenuHost
        let container = menuContainer
        let snapshot = snapshotView
        let actionsView = self.actionsView
        let sourceView = source.view
        let sourcePresentationLease = self.sourcePresentationLease
        let previewAccessoryContainer = self.previewAccessoryContainer

        var didClean = false
        let cleanup: () -> Void = { [weak self] in
            if didClean { return }
            didClean = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Defensive: restore transform/alpha in case the dismiss
            // path was non-animated (animated: false) or interrupted
            // before the spring finished — otherwise the source would
            // stay collapsed after a rapid dismiss.
            if sourcePresentationLease == nil {
                sourceView?.transform = sourceRestoreTransform
                sourceView?.alpha = sourceRestoreAlpha
            }
            CATransaction.commit()
            self?.savedSourceOpacity = nil
            self?.savedSourceTransform = nil
            self?.presentedAppearanceStyle = nil
            self?.pendingCleanup = nil
            // Stop every progress driver before touching filters or removing
            // views. This is required for synchronous generation-boundary
            // dismissal, which can interrupt any opening/closing phase.
            glassmorphicHost?.tearDownGlassEffects()
            // Restore the leased source while the bloom surface is still
            // present at the source frame. Removing the host first leaves a
            // one-frame hole where the original button flashes back late.
            sourcePresentationLease?.release()
            // Tear down `UIGlassEffect` registrations BEFORE removing
            // the views from their superviews. iOS 26's
            // `UIGlassContainerEffect` keeps a list of registered
            // `UIGlassEffect`-bearing views, and `removeFromSuperview`
            // alone doesn't always remove them from that list — the
            // leak leaves the global container in a state where
            // `UIGlassEffect.isInteractive` deformation no longer plays
            // on other glass views in the same window after our menu
            // cycle. Setting `effect = nil` on each `UIVisualEffectView`
            // we own deregisters cleanly.
            container?.tearDownGlassEffect()
            self?.submenuCard?.tearDownGlassEffect()
            self?.onWillRemoveOverlay?()
            dim?.removeFromSuperview()
            glassmorphicHost?.removeFromSuperview()
            previewMenuHost?.removeFromSuperview()
            container?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            snapshot?.removeFromSuperview()
            self?.previewView?.removeFromSuperview()
            previewAccessoryContainer?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.glassmorphicHost = nil
            self?.sourcePresentationLease = nil
            self?.previewMenuHost = nil
            self?.menuContainer = nil
            self?.snapshotView = nil
            self?.previewView = nil
            self?.previewAccessoryContainer = nil
            self?.previewInitialCenterInHost = nil
            self?.previewFinalCenterInHost = nil
            self?.actionsView = nil
            self?.submenuCard?.removeFromSuperview()
            self?.submenuCard = nil
            self?.submenuActions = nil
            self?.submenuCollapseHitView?.removeFromSuperview()
            self?.submenuCollapseHitView = nil
            self?.onDismiss?()
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }
        pendingCleanup = cleanup

        guard animated else { cleanup(); return }

        // If an inline submenu card is open, fade it out *in parallel* with
        // the main menu's dismiss morph — otherwise it would stay fully
        // visible through the morph and then snap to invisible inside
        // `cleanup` (which runs `removeFromSuperview` synchronously). The
        // submenu's hit-target view is non-visual; nothing to animate there.
        if let submenuCard {
            UIView.animate(
                withDuration: ContextMenuController.glassmorphicTiming.closeDuration,
                delay: 0,
                usingSpringWithDamping: 0.95,
                initialSpringVelocity: 0,
                options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    submenuCard.alpha = 0.0
                    submenuCard.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                },
                completion: nil
            )
        }

        if let previewMenuHost {
            animateOutPreview(
                previewMenuHost: previewMenuHost,
                dim: dim,
                preview: previewView,
                accessory: previewAccessoryContainer,
                completion: cleanup
            )
        } else {
            animateOutGlassmorphic(dim: dim, cleanup: cleanup)
        }
    }

    /// Dismiss the lifted preview: its content drops back to
    /// identity scale; menu chrome scales/fades out.
    private func animateOutPreview(
        previewMenuHost: UIView,
        dim: UIView?,
        preview: UIView?,
        accessory: UIView?,
        completion: @escaping () -> Void
    ) {
        let sourceView = self.source.view
        let sourceTargetAlpha = savedSourceOpacity.map(CGFloat.init) ?? 1.0
        let previewInitialCenter = self.previewInitialCenterInHost
        let menuDismissTransform = CGAffineTransform(
            translationX: 0,
            y: ContextMenuController.previewDismissMenuOffsetY
        ).scaledBy(
            x: ContextMenuController.previewDismissMenuScale,
            y: ContextMenuController.previewDismissMenuScale
        )
        let accessoryDismissTransform = CGAffineTransform(
            scaleX: ContextMenuController.previewDismissAccessoryScale,
            y: ContextMenuController.previewDismissAccessoryScale
        )

        UIView.animate(
            withDuration: ContextMenuController.previewDismissDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.dismissDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                // Make the close read as a real return: preview travels
                // back to the source while the menu visibly contracts.
                if let previewInitialCenter {
                    preview?.center = previewInitialCenter
                }
                previewMenuHost.transform = menuDismissTransform
                preview?.transform = .identity
                accessory?.transform = accessoryDismissTransform
            },
            completion: { _ in completion() }
        )

        Self.animateWithPreviewBezier(
            duration: ContextMenuController.previewDismissDuration * 0.58,
            delay: ContextMenuController.previewDismissDuration * 0.22,
            animations: {
                // Delayed fade keeps the geometry visible long enough to
                // read before the snapshot hands back to the real source.
                previewMenuHost.alpha = 0.0
                preview?.alpha = 0.0
                accessory?.alpha = 0.0
                sourceView?.alpha = sourceTargetAlpha
                dim?.alpha = 0.0
            },
            completion: nil
        )
    }

    // MARK: - Animate in

    private func animateIn(dim: UIView) {
        let dimDuration = usesLiquidPresentation ? 0.18 : AetherLegacySurfaceTokens.resolve(
            role: .popup,
            traitCollection: source.view?.traitCollection ?? UITraitCollection.current
        ).animationDuration
        if usesLiquidPresentation && preview == nil {
            dim.alpha = 1
        } else {
            UIView.animate(withDuration: dimDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                dim.alpha = 1
            }
        }
        if let preview, let previewMenuHost {
            animateInPreview(previewMenuHost: previewMenuHost, lift: preview.lift)
        } else {
            animateInGlassmorphic()
        }
    }

    /// Expand the shared source-to-menu surface.
    private func animateInGlassmorphic() {
        guard let glassmorphicHost else { return }
        glassmorphicHost.animateExpand(
            duration: ContextMenuController.glassmorphicTiming.openDuration,
            damping: AetherMotion.contextMenu.presentation.dampingRatio,
            completion: nil
        )
    }

    /// Reverse of `animateInGlassmorphic`: the menu platter shrinks back
    /// through the bubble/source path before cleanup restores the source.
    private func animateOutGlassmorphic(
        dim: UIView?,
        cleanup: @escaping () -> Void
    ) {
        guard let glassmorphicHost else { cleanup(); return }

        // Reset any active stretch transform first so the reverse morph
        // starts from identity, not from a press-release stretch left
        // over from the last touch.
        glassmorphicHost.finalMenuGlassSurfaceView.resetGlassInteractionTransform()

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: {
            dim?.alpha = 0.0
        })

        glassmorphicHost.animateCollapse(
            duration: ContextMenuController.glassmorphicTiming.closeDuration,
            damping: ContextMenuController.dismissDamping,
            completion: { cleanup() }
        )
    }

    /// Lifted preview + below-source menu spring-in (no morph).
    private func animateInPreview(previewMenuHost: UIView, lift: CGFloat) {
        // previewMenuHost was pre-staged at scale 0.9 + alpha 0; spring it to
        // identity. Menu chrome reads as "appearing fresh below the lifted
        // preview".
        UIView.animate(
            withDuration: ContextMenuController.previewOpenDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.previewDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                previewMenuHost.transform = .identity
            },
            completion: nil
        )
        Self.animateWithPreviewBezier(
            duration: ContextMenuController.previewOpenDuration,
            delay: 0,
            animations: {
                previewMenuHost.alpha = 1.0
            },
            completion: nil
        )

        // Lifted preview: scale up by `lift` from identity, with the same
        // spring so it lands in sync with the menu.
        if let preview = previewView {
            let finalCenter = previewFinalCenterInHost ?? preview.center
            preview.transform = .identity
            UIView.animate(
                withDuration: ContextMenuController.previewOpenDuration,
                delay: 0,
                usingSpringWithDamping: ContextMenuController.previewDamping,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    preview.center = finalCenter
                    preview.transform = CGAffineTransform(scaleX: lift, y: lift)
                },
                completion: nil
            )
        }

        if let accessory = previewAccessoryContainer {
            UIView.animate(
                withDuration: ContextMenuController.previewOpenDuration,
                delay: 0,
                usingSpringWithDamping: ContextMenuController.previewDamping,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    accessory.transform = .identity
                },
                completion: nil
            )
            Self.animateWithPreviewBezier(
                duration: ContextMenuController.previewOpenDuration,
                delay: 0,
                animations: {
                    accessory.alpha = 1.0
                },
                completion: nil
            )
        }
    }

    private static func animateWithPreviewBezier(
        duration: TimeInterval,
        delay: TimeInterval,
        animations: @escaping () -> Void,
        completion: (() -> Void)?
    ) {
        let animator = UIViewPropertyAnimator(
            duration: max(0.001, duration),
            timingParameters: previewBezierTimingParameters()
        )
        animator.addAnimations(animations)
        if let completion {
            animator.addCompletion { _ in completion() }
        }
        animator.startAnimation(afterDelay: delay)
    }

    // MARK: - Source snapshot

    private func makeSourceSnapshot(source: UIView) -> UIView {
        if let snap = source.snapshotView(afterScreenUpdates: false) {
            snap.frame = CGRect(origin: .zero, size: source.bounds.size)
            return snap
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: source.bounds, format: format).image { _ in
            source.drawHierarchy(in: source.bounds, afterScreenUpdates: true)
        }
        let view = UIImageView(image: image)
        view.frame = CGRect(origin: .zero, size: source.bounds.size)
        return view
    }

    // MARK: - Menu placement

    private func maximumMenuHeight(hostBounds: CGRect) -> CGFloat {
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)
        let availableHeight = max(1.0, hostBounds.height - safeTop - safeBottom)

        return preview == nil
            ? min(availableHeight, max(1.0, hostBounds.height * 0.74))
            : availableHeight
    }

    /// Source-menu placement preserves its attachment edge; lifted preview
    /// content uses the separate stacked layout above.
    private func computeMenuFrame(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGRect {
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)
        let x = computeMenuX(sourceRect: sourceRect, menuSize: menuSize, hostBounds: hostBounds)

        let initialY: CGFloat
        if let preview {
            initialY = sourceRect.maxY + preview.verticalSpacing
        } else {
            // Lens bloom behaves like UIKit's menu platter: it may cover the
            // original trigger. Keeping a source gap makes the lens look like
            // a detached popover and also leaves the trigger awkwardly visible
            // beside the menu.
            let downward = sourceRect.minY
            let upward = sourceRect.maxY - menuSize.height
            if downward + menuSize.height <= hostBounds.maxY - safeBottom {
                initialY = downward
            } else if upward >= safeTop {
                initialY = upward
            } else {
                initialY = min(
                    max(safeTop, downward),
                    hostBounds.maxY - safeBottom - menuSize.height
                )
            }
        }

        var y = initialY
        if y + menuSize.height > hostBounds.maxY - safeBottom {
            let upward: CGFloat
            if let preview {
                upward = sourceRect.minY - max(0.0, preview.verticalSpacing) - menuSize.height
            } else {
                upward = sourceRect.maxY - menuSize.height
            }
            if upward >= safeTop {
                y = upward
            } else {
                y = hostBounds.maxY - safeBottom - menuSize.height
            }
        }
        if y < safeTop {
            y = safeTop
        }

        return CGRect(x: x, y: y, width: menuSize.width, height: menuSize.height)
    }

    private func computePreviewLayout(
        sourceRect: CGRect,
        menuSize: CGSize,
        hostBounds: CGRect,
        verticalSpacing: CGFloat,
        lift: CGFloat,
        content: PreviewContent?,
        accessory: PreviewAccessory?
    ) -> PreviewLayout {
        let sideInset: CGFloat = 12.0
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)
        let maxContentWidth = max(1.0, hostBounds.width - sideInset * 2.0)
        let safeBottomY = hostBounds.maxY - safeBottom
        let spacing = max(0.0, verticalSpacing)
        let effectiveLift = max(0.01, lift)

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            guard upper >= lower else { return lower }
            return min(max(value, lower), upper)
        }

        let rawPreviewSize = content?.preferredSize ?? sourceRect.size
        let maxPreviewWidth = max(1.0, maxContentWidth / effectiveLift)
        let previewWidth = min(maxPreviewWidth, max(1.0, rawPreviewSize.width))

        let accessorySize = resolvedPreviewAccessorySize(
            accessory,
            maxWidth: maxContentWidth,
            fallbackWidth: min(max(previewWidth, menuSize.width), maxContentWidth)
        )
        let hasAccessory = accessory != nil && accessorySize.width > 0.0 && accessorySize.height > 0.0
        let accessorySpacing = hasAccessory ? max(0.0, accessory?.spacing ?? 0.0) : 0.0
        let topBlockHeight = hasAccessory ? accessorySpacing + accessorySize.height : 0.0

        let availableBlockHeight = max(1.0, safeBottomY - safeTop)
        let maxLiftedPreviewHeight = max(
            1.0,
            availableBlockHeight - topBlockHeight - spacing - menuSize.height
        )
        let maxPreviewHeight = max(1.0, maxLiftedPreviewHeight / effectiveLift)
        let previewHeight = min(maxPreviewHeight, max(1.0, rawPreviewSize.height))
        let previewSize = CGSize(width: previewWidth, height: previewHeight)
        let liftInsetX = previewSize.width * (effectiveLift - 1.0) / 2.0
        let liftInsetY = previewSize.height * (effectiveLift - 1.0) / 2.0

        let minPreviewX = sideInset + liftInsetX
        let maxPreviewX = hostBounds.maxX - sideInset - previewSize.width - liftInsetX
        let previewX = clamped(
            sourceRect.midX - previewSize.width / 2.0,
            lower: minPreviewX,
            upper: maxPreviewX
        )

        let minPreviewY = safeTop + topBlockHeight + liftInsetY
        let maxPreviewY = safeBottomY - spacing - menuSize.height - previewSize.height - liftInsetY
        let previewY = clamped(
            sourceRect.midY - previewSize.height / 2.0,
            lower: minPreviewY,
            upper: maxPreviewY
        )
        let previewFrame = CGRect(
            x: previewX,
            y: previewY,
            width: previewSize.width,
            height: previewSize.height
        )
        let initialPreviewFrame = content == nil ? sourceRect : previewFrame
        let liftedPreviewFrame = previewFrame.insetBy(
            dx: -liftInsetX,
            dy: -liftInsetY
        )

        let accessoryFrame: CGRect?
        if hasAccessory {
            var accessoryX = liftedPreviewFrame.midX - accessorySize.width / 2.0
            accessoryX = max(sideInset, min(accessoryX, hostBounds.maxX - sideInset - accessorySize.width))
            accessoryFrame = CGRect(
                x: accessoryX,
                y: liftedPreviewFrame.minY - accessorySpacing - accessorySize.height,
                width: accessorySize.width,
                height: accessorySize.height
            )
        } else {
            accessoryFrame = nil
        }

        let menuX = computePreviewMenuX(sourceRect: previewFrame, menuSize: menuSize, hostBounds: hostBounds)
        let menuY = clamped(
            liftedPreviewFrame.maxY + spacing,
            lower: safeTop,
            upper: safeBottomY - menuSize.height
        )

        return PreviewLayout(
            initialPreviewFrame: initialPreviewFrame,
            previewFrame: previewFrame,
            menuFrame: CGRect(x: menuX, y: menuY, width: menuSize.width, height: menuSize.height),
            accessory: accessory,
            accessoryFrame: accessoryFrame,
            content: content
        )
    }

    private func resolvedPreviewAccessorySize(
        _ accessory: PreviewAccessory?,
        maxWidth: CGFloat,
        fallbackWidth: CGFloat
    ) -> CGSize {
        guard let accessory else { return .zero }
        if let preferredSize = accessory.preferredSize {
            return CGSize(
                width: min(maxWidth, max(0.0, preferredSize.width)),
                height: max(0.0, preferredSize.height)
            )
        }

        let fittingTarget = CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height)
        let fittingSize = accessory.view.systemLayoutSizeFitting(
            fittingTarget,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        let sizeThatFits = accessory.view.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let intrinsicSize = accessory.view.intrinsicContentSize

        let width = firstPositive(
            fittingSize.width,
            accessory.view.bounds.width,
            sizeThatFits.width,
            intrinsicSize.width == UIView.noIntrinsicMetric ? 0.0 : intrinsicSize.width,
            fallbackWidth
        )
        let height = firstPositive(
            fittingSize.height,
            accessory.view.bounds.height,
            sizeThatFits.height,
            intrinsicSize.height == UIView.noIntrinsicMetric ? 0.0 : intrinsicSize.height
        )

        return CGSize(width: min(maxWidth, width), height: height)
    }

    private func firstPositive(_ values: CGFloat...) -> CGFloat {
        for value in values where value > 0.0 && value.isFinite {
            return value
        }
        return 0.0
    }

    private func computePreviewMenuX(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGFloat {
        let sideInset: CGFloat = 12.0
        let centerTolerance: CGFloat = 24.0
        let leftAlignedX = sourceRect.minX
        let rightAlignedX = sourceRect.maxX - menuSize.width
        let centerAlignedX = sourceRect.midX - menuSize.width / 2.0

        let preferredX: CGFloat
        if abs(sourceRect.midX - hostBounds.midX) <= centerTolerance {
            preferredX = centerAlignedX
        } else if sourceRect.midX < hostBounds.midX {
            preferredX = leftAlignedX
        } else {
            preferredX = rightAlignedX
        }

        let maxX = max(sideInset, hostBounds.maxX - sideInset - menuSize.width)
        return min(max(sideInset, preferredX), maxX)
    }

    private func computeMenuX(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGFloat {
        let sideInset: CGFloat = 12.0

        // Horizontal alignment strategy (restored — rolled back the
        // "always centre on source" attempt). The menu picks an
        // edge-aligned position that fits on screen; the animation
        // bubble is then placed at the menu's own midpoint (see
        // `setupMorphStyle`'s droplet), so the morph is a pure
        // bilateral expansion out of the menu's centre with no
        // cross-animation drift — regardless of how far that centre
        // ends up from the source.
        let leftAlignedX = sourceRect.minX
        let rightAlignedX = sourceRect.maxX - menuSize.width
        let centreAlignedX = sourceRect.midX - menuSize.width / 2

        let fitsLeftAligned = leftAlignedX >= sideInset
            && leftAlignedX + menuSize.width <= hostBounds.maxX - sideInset
        let fitsRightAligned = rightAlignedX >= sideInset
            && rightAlignedX + menuSize.width <= hostBounds.maxX - sideInset
        let fitsCentreAligned = centreAlignedX >= sideInset
            && centreAlignedX + menuSize.width <= hostBounds.maxX - sideInset

        let sourceCentreIsOnRight = sourceRect.midX > hostBounds.midX

        var x: CGFloat
        if fitsCentreAligned {
            x = centreAlignedX
        } else if sourceCentreIsOnRight && fitsRightAligned {
            x = rightAlignedX
        } else if !sourceCentreIsOnRight && fitsLeftAligned {
            x = leftAlignedX
        } else if fitsRightAligned {
            x = rightAlignedX
        } else {
            x = leftAlignedX
        }
        x = max(sideInset, x)
        if x + menuSize.width > hostBounds.maxX - sideInset {
            x = hostBounds.maxX - sideInset - menuSize.width
        }
        return x
    }

    // MARK: - Gestures

    @objc func handleBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        dismiss()
    }

    // MARK: - Submenu page stack

    /// Hooks an actions view into the controller — action callbacks,
    /// submenu push, back-tap, and stretch reporting. Used for both the
    /// root page and pushed submenu pages.
    private func wireActionsView(
        _ view: ContextMenuActionsView,
        handle: ContextMenuDismissHandle,
        surfaceView: UIView,
        isSubmenu: Bool = false
    ) {
        view.onActionSelected = { [weak self] actionItem in
            guard let self else { return }
            let shouldAutoDismiss = actionItem.action == nil
            actionItem.action?(actionItem, handle)
            if shouldAutoDismiss { self.dismiss(animated: true) }
        }
        view.onSubmenuRequested = { [weak self] actionItem in
            self?.openInlineSubmenu(from: actionItem)
        }
        view.onHeaderTapped = { [weak self] in
            // The submenu card's header (down-chevron) collapses the card.
            // The root actions view never has a header, so this only fires
            // for submenu cards.
            self?.collapseInlineSubmenu()
        }
        view.onStretchUpdate = nil
        view.onStretchRelease = nil

        if let glassSurface = surfaceView as? MenuGlassSurfaceView {
            glassSurface.gestureRecognizers?
                .compactMap { $0 as? ContextMenuSurfaceInteractionGestureRecognizer }
                .forEach { glassSurface.removeGestureRecognizer($0) }
            glassSurface.routesTouchesToGlassSurface = true

            // Selection/highlight is now driven by a recognizer installed on
            // the glass surface itself. The actions view stays visual-only so
            // iOS 26 `UIGlassEffect.isInteractive` and the legacy fallback
            // stretch the menu container, not row labels/icons.
            view.isUserInteractionEnabled = false
            glassSurface.addGestureRecognizer(ContextMenuSurfaceInteractionGestureRecognizer(actionsView: view))
        } else {
            view.isUserInteractionEnabled = true
        }
    }

    // MARK: - Inline submenu (Yandex-Music-style overlay)

    private static let submenuTransitionDuration: TimeInterval = 0.36
    private static let submenuTransitionDamping: CGFloat = 0.85
    /// Alpha applied to the parent actions view while a submenu card is open.
    /// The dimmed parent stays visible so the user has visual context, but
    /// becomes secondary to the popped-out submenu.
    private static let submenuParentDimAlpha: CGFloat = 0.32

    /// Open an inline submenu card overlaid on the parent menu, anchored to
    /// the source row's Y position. The parent actions view dims behind it;
    /// taps that miss the card collapse it (caught by `submenuCollapseHitView`).
    private func openInlineSubmenu(from item: ContextMenuActionItem) {
        guard
            let submenu = item.submenu,
            let host = self.hostView,
            let surfaceView = self.surfaceView,
            let surfaceOverlayView = self.surfaceOverlayView,
            let parentActions = self.actionsView,
            let handle = self.dismissHandle
        else { return }

        // If a submenu is already open, collapse it first (we don't stack
        // inline submenus — only one card at a time).
        if submenuCard != nil {
            collapseInlineSubmenu(animated: false)
        }

        // Build the card.
        let isDark = surfaceView.traitCollection.userInterfaceStyle == .dark
        let card = MenuGlassSurfaceView(
            isDark: isDark,
            appearanceStyle: resolvedAppearanceStyle
        )
        card.setSurfaceCornerRadius(resolvedMenuMetrics.cornerRadius)

        let submenuActions = ContextMenuActionsView(
            items: submenu,
            headerStyle: .disclosure(title: item.title),
            appearanceStyle: resolvedAppearanceStyle
        )
        let cardWidth = surfaceView.bounds.width
        let cardSize = submenuActions.preferredSize(maxWidth: cardWidth)
        submenuActions.frame = CGRect(origin: .zero, size: cardSize)
        submenuActions.autoresizingMask = [.flexibleWidth]
        card.contentView.addSubview(submenuActions)
        wireActionsView(submenuActions, handle: handle, surfaceView: card, isSubmenu: true)

        // Anchor card.minY to the source row's Y in screen coords. We can
        // approximate by finding the touched item's row in `parentActions`
        // — but a simpler robust path is "use the source row's frame directly".
        let cardOriginInParent = sourceRowFrame(for: item, in: parentActions)?.origin ?? .zero
        let cardOriginInHost = parentActions.convert(cardOriginInParent, to: host)
        let cardFrame = CGRect(
            x: surfaceView.frame.minX,
            y: cardOriginInHost.y,
            width: cardWidth,
            height: cardSize.height
        )
        card.frame = cardFrame
        applyLegacyReferenceShadow(
            to: card,
            cornerRadius: resolvedMenuMetrics.cornerRadius
        )
        host.addSubview(card)
        self.submenuCard = card
        self.submenuActions = submenuActions

        // Hit-target inside the active menu surface that catches taps which
        // miss the card. Lives BELOW the card in the host hierarchy (the
        // surface is below the card sibling), so card touches still go to
        // the card first.
        let hitView = UIView(frame: surfaceOverlayView.bounds)
        hitView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hitView.backgroundColor = .clear
        let collapseTap = UITapGestureRecognizer(target: self, action: #selector(handleCollapseTap))
        hitView.addGestureRecognizer(collapseTap)
        surfaceOverlayView.addSubview(hitView)
        self.submenuCollapseHitView = hitView

        // Dim parent + disable its touches so the card / hit-view interaction
        // model cleanly takes over. Also fade out the parent's sliding
        // highlight lens — `commitTouch` intentionally leaves it visible
        // after a tap (so regular actions can dismiss the whole menu with
        // the highlight still showing the "you tapped this row" state), but
        // for submenu opens we need to clear it here: otherwise when the
        // submenu closes and parent alpha returns to 1.0, a stale lens pops
        // back into view on the submenu-trigger row.
        parentActions.isUserInteractionEnabled = false
        parentActions.clearHighlight(animated: true)

        // Spring + fade-in. Card scales from 0.96 to 1.0 anchored at its
        // header center to match where the source row is — visually it pops
        // out of the row.
        card.alpha = 0.0
        card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        UIView.animate(
            withDuration: ContextMenuController.submenuTransitionDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.submenuTransitionDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                card.alpha = 1.0
                card.transform = .identity
                parentActions.alpha = ContextMenuController.submenuParentDimAlpha
            },
            completion: nil
        )
    }

    /// Walk the parent actions view's subview tree and return the frame
    /// (in `parent`'s own coordinates) of the row whose item matches `item`.
    /// Used to anchor the submenu card's Y position to the row that
    /// triggered the open.
    private func sourceRowFrame(for item: ContextMenuActionItem, in parent: UIView) -> CGRect? {
        guard let row = findActionRow(matching: item, in: parent) else { return nil }
        return row.convert(row.bounds, to: parent)
    }

    private func findActionRow(matching item: ContextMenuActionItem, in view: UIView) -> ContextMenuActionItemView? {
        if let row = view as? ContextMenuActionItemView, row.item.id == item.id {
            return row
        }
        for subview in view.subviews {
            if let found = findActionRow(matching: item, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Close the inline submenu card. Reverses the open animation; restores
    /// parent alpha + interaction.
    @discardableResult
    private func collapseInlineSubmenu(animated: Bool = true) -> Bool {
        guard let card = submenuCard else { return false }
        let parentActions = self.actionsView
        let hitView = self.submenuCollapseHitView

        let teardown = {
            card.removeFromSuperview()
            hitView?.removeFromSuperview()
            parentActions?.isUserInteractionEnabled = !(self.surfaceView is MenuGlassSurfaceView)
            self.submenuCard = nil
            self.submenuActions = nil
            self.submenuCollapseHitView = nil
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard animated else {
            parentActions?.alpha = 1.0
            teardown()
            return true
        }

        UIView.animate(
            withDuration: ContextMenuController.submenuTransitionDuration,
            delay: 0,
            usingSpringWithDamping: 0.95,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                card.alpha = 0.0
                card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                parentActions?.alpha = 1.0
            },
            completion: { _ in teardown() }
        )
        return true
    }

    @objc private func handleCollapseTap() {
        collapseInlineSubmenu()
    }

}

private final class PreviewAccessoryContainerView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }

        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 {
            let pointInSubview = subview.convert(point, from: self)
            if subview.point(inside: pointInSubview, with: event) {
                return true
            }
        }
        return false
    }
}

private final class ContextMenuSurfaceInteractionGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var actionsView: ContextMenuActionsView?
    private var trackedTouch: UITouch?

    init(actionsView: ContextMenuActionsView) {
        self.actionsView = actionsView
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func reset() {
        trackedTouch = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first, let actionsView else {
            state = .failed
            return
        }
        trackedTouch = touch
        actionsView.beginExternalInteraction(at: touch.location(in: actionsView))
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let actionsView else { return }
        actionsView.updateExternalInteraction(at: trackedTouch.location(in: actionsView))
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let actionsView else {
            state = .ended
            return
        }
        actionsView.endExternalInteraction(at: trackedTouch.location(in: actionsView))
        self.trackedTouch = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if trackedTouch != nil {
            actionsView?.cancelExternalInteraction()
        }
        trackedTouch = nil
        state = .cancelled
    }
}

// MARK: - Presentation convenience

public extension ContextMenuController {
    @discardableResult
    static func present(
        source: UIView,
        cornerRadius: CGFloat? = nil,
        items: [ContextMenuItem],
        preview: Preview? = nil,
        appearanceStyle: AetherAppearanceStyle? = nil,
        catchTapsOutside: Bool = true,
        hasHapticFeedback: Bool = true,
        blurred: Bool = true,
        isDark: Bool? = nil,
        skipCoordinateConversion: Bool = false,
        onWillRemoveOverlay: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> ContextMenuController {
        let controller = ContextMenuController(
            source: Source(view: source, cornerRadius: cornerRadius),
            items: items,
            preview: preview,
            appearanceStyle: appearanceStyle,
            catchTapsOutside: catchTapsOutside,
            hasHapticFeedback: hasHapticFeedback,
            blurred: blurred,
            isDark: isDark,
            skipCoordinateConversion: skipCoordinateConversion,
            onWillRemoveOverlay: onWillRemoveOverlay,
            onDismiss: onDismiss
        )
        controller.present()
        return controller
    }
}

// MARK: - Self-retain box

private final class ContextMenuControllerBox: Hashable {
    let controller: ContextMenuController

    init(controller: ContextMenuController) {
        self.controller = controller
    }

    static func == (lhs: ContextMenuControllerBox, rhs: ContextMenuControllerBox) -> Bool {
        return lhs.controller === rhs.controller
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(controller))
    }
}
