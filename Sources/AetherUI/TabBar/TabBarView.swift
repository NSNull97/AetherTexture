import UIKit
import AsyncDisplayKit

/// One optical recipe for every piece of compact bottom chrome. Interaction
/// deliberately stays outside this value: the tab pill, Search, and an
/// accessory have different touch owners, but must resolve the same material.
internal struct TabBarChromeGlassAppearance: Equatable {
    let viewStyle: GlassBackgroundView.Style
    let tint: GlassBackgroundView.TintColor
    let isDark: Bool
}

/// Plain geometry owner whose hit-testing follows its presentation layer.
/// The shared glass container commits endpoint frames before its spring has
/// visually settled; regular UIView hit-testing would otherwise expose the new
/// endpoint and leave the visible moving pill untappable.
private final class TabBarPillGeometryHostView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }
        guard layer.animationKeys()?.isEmpty == false,
              let presentation = layer.presentation(),
              let modelSuperlayer = layer.superlayer,
              let presentationSuperlayer = presentation.superlayer else {
            return super.hitTest(point, with: event)
        }
        let pointInSuperlayer = layer.convert(point, to: modelSuperlayer)
        let presentationPoint = presentation.convert(
            pointInSuperlayer,
            from: presentationSuperlayer
        )
        return super.hitTest(presentationPoint, with: event)
    }
}

/// Custom tab bar view with glass-style rendering and glass support.
/// Replaces the original TabBarNode.
public final class TabBarView: UIView, AetherAppearanceConsumer {
    // MARK: - Types

    struct LegacyLayout {
        static let contentHeight: CGFloat = 49.0
        static let itemHeight: CGFloat = 40.0
        static let itemTopInset: CGFloat = 7.0
        static let accessorySideInset: CGFloat = 16.0
        static let accessoryBottomGap: CGFloat = 4.0
        static let minimumAccessoryHeight: CGFloat = 56.0
        static let accessoryCornerRadius: CGFloat = 14.0

        struct ItemContentFrames: Equatable {
            let icon: CGRect
            let title: CGRect
        }

        static func totalHeight(bottomSafeAreaInset: CGFloat) -> CGFloat {
            bottomSafeAreaInset > 0.0 ? 83.0 : contentHeight
        }

        static func itemFrame(index: Int, count: Int, width: CGFloat) -> CGRect {
            guard count > 0 else { return .zero }
            let itemWidth = width / CGFloat(count)
            return CGRect(
                x: CGFloat(index) * itemWidth,
                y: itemTopInset,
                width: itemWidth,
                height: itemHeight
            )
        }

        static func itemContentFrames(bounds: CGRect, titleLineHeight: CGFloat) -> ItemContentFrames {
            let horizontalInset: CGFloat = 8.0
            let iconSize: CGFloat = 24.0
            let titleHeight = min(22.0, ceil(titleLineHeight))
            return ItemContentFrames(
                icon: CGRect(
                    x: (bounds.width - iconSize) / 2.0,
                    y: 0.0,
                    width: iconSize,
                    height: iconSize
                ),
                title: CGRect(
                    x: horizontalInset,
                    y: max(0.0, bounds.height - titleHeight),
                    width: max(0.0, bounds.width - horizontalInset * 2.0),
                    height: titleHeight
                )
            )
        }
    }

    public enum Style {
        case legacy
        case liquidGlass
    }

    public struct TabBarAppearance {
        public struct EdgeEffect {
            public let alpha: CGFloat
            public let blurRadiusAtEdge: CGFloat
            public let blurRadiusAtFade: CGFloat
            public let solidBlur: Bool
            public let tintColor: UIColor?

            public init(
                alpha: CGFloat = 0.75,
                blurRadiusAtEdge: CGFloat = 2.0,
                blurRadiusAtFade: CGFloat = 0.0,
                solidBlur: Bool = false,
                tintColor: UIColor? = nil
            ) {
                self.alpha = alpha
                self.blurRadiusAtEdge = blurRadiusAtEdge
                self.blurRadiusAtFade = blurRadiusAtFade
                self.solidBlur = solidBlur
                self.tintColor = tintColor
            }
        }

        public let backgroundColor: UIColor
        public let separatorColor: UIColor
        public let enableBlur: Bool
        public let edgeEffect: EdgeEffect?

        public init(
            backgroundColor: UIColor = .clear,
            separatorColor: UIColor = .separator,
            enableBlur: Bool = true,
            edgeEffect: EdgeEffect? = EdgeEffect()
        ) {
            self.backgroundColor = backgroundColor
            self.separatorColor = separatorColor
            self.enableBlur = enableBlur
            self.edgeEffect = edgeEffect
        }
    }

    public struct Theme {
        public let appearanceStyle: AetherAppearanceStyle
        public let tabBarBackgroundColor: UIColor
        public let tabBarSeparatorColor: UIColor
        public let tabBarIconColor: UIColor
        public let tabBarSelectedIconColor: UIColor
        public let tabBarTextColor: UIColor
        public let tabBarSelectedTextColor: UIColor
        public let tabBarBadgeBackgroundColor: UIColor
        public let tabBarBadgeStrokeColor: UIColor
        public let tabBarBadgeTextColor: UIColor
        public let enableBlur: Bool
        public let isDark: Bool
        /// When false, `isDark == false` follows the hosting trait collection.
        /// A resolved per-screen override sets this to true so light can be
        /// forced just as reliably as dark.
        public let isDarkAppearanceExplicit: Bool
        public let style: Style
        public let outerInsets: UIEdgeInsets

        // Liquid Glass layout
        public let pillHeight: CGFloat
        public let totalHeight: CGFloat
        public let bottomInset: CGFloat
        public let sideInset: CGFloat
        /// Dedicated minimized-row inset. The compact row is narrower than
        /// the expanded pill, matching the native Apple Music composition.
        public let minimizedSideInset: CGFloat
        /// Gap between each 48pt edge circle and an inline accessory.
        public let minimizedInterItemSpacing: CGFloat
        public let innerPadding: CGFloat
        /// Maximum centered pill width for compact layouts with up to three tabs.
        public let maximumRowWidth: CGFloat
        /// Width of each tab slot before the pill reaches its row cap.
        public let preferredItemWidth: CGFloat
        /// Legacy expanded-Search spacing retained for source compatibility.
        /// Current expanded Search lives in the shared pill; compact spacing is
        /// controlled by `minimizedInterItemSpacing`.
        public let showcaseSpacing: CGFloat

        // Edge effect (scroll-content frost). Blur is a progressive ramp
        // anchored at the solid edge (`…AtEdge`, full strength) tapering to
        // `…AtFade` at the content boundary. The TabBar's solid edge sits
        // at the bottom of the screen, so the heavy blur lives at the
        // bottom and tapers to zero where it meets the scrolling content.
        public let edgeEffectAlpha: CGFloat
        public let edgeEffectBlurRadiusAtEdge: CGFloat
        public let edgeEffectBlurRadiusAtFade: CGFloat
        public let edgeEffectSolidBlur: Bool
        public let glassEffectStyle: SystemGlassEffectStyle
        public let edgeEffectTintColor: UIColor?

        public init(
            appearanceStyle: AetherAppearanceStyle = .liquidGlassV1,
            tabBarBackgroundColor: UIColor = .systemBackground,
            tabBarSeparatorColor: UIColor = .separator,
            tabBarIconColor: UIColor? = nil,
            tabBarSelectedIconColor: UIColor = .systemBlue,
            tabBarTextColor: UIColor? = nil,
            tabBarSelectedTextColor: UIColor = .systemBlue,
            tabBarBadgeBackgroundColor: UIColor = .systemRed,
            tabBarBadgeStrokeColor: UIColor = .white,
            tabBarBadgeTextColor: UIColor = .white,
            enableBlur: Bool = true,
            isDark: Bool = false,
            isDarkAppearanceExplicit: Bool? = nil,
            style: Style = .liquidGlass,
            tabBarAppearance: TabBarAppearance? = nil,
            outerInsets: UIEdgeInsets = UIEdgeInsets(top: 4.0, left: 21.0, bottom: 4.0, right: 21.0),
            pillHeight: CGFloat = 60.0,
            totalHeight: CGFloat = 95.0,
            bottomInset: CGFloat = 21.0,
            sideInset: CGFloat = 25.0,
            minimizedSideInset: CGFloat = 28.0,
            minimizedInterItemSpacing: CGFloat = 13.0,
            innerPadding: CGFloat = 10.0,
            maximumRowWidth: CGFloat = 344.0,
            preferredItemWidth: CGFloat = 88.0,
            showcaseSpacing: CGFloat = 7.0,
            edgeEffectAlpha: CGFloat = 0.75,
            edgeEffectBlurRadiusAtEdge: CGFloat = 2.0,
            edgeEffectBlurRadiusAtFade: CGFloat = 0.0,
            edgeEffectSolidBlur: Bool = false,
            glassEffectStyle: SystemGlassEffectStyle = .regular,
            edgeEffectTintColor: UIColor? = nil
        ) {
            // The exact appearance generation is canonical.  The historical
            // coarse `style` remains accepted, but either Legacy spelling must
            // resolve both fields to Legacy.
            let resolvesLegacy = style == .legacy || appearanceStyle == .legacy
            self.appearanceStyle = resolvesLegacy ? .legacy : appearanceStyle
            self.tabBarBackgroundColor = tabBarAppearance?.backgroundColor ?? tabBarBackgroundColor
            self.tabBarSeparatorColor = tabBarAppearance?.separatorColor ?? tabBarSeparatorColor
            let defaultUnselectedTint = resolvesLegacy
                ? UIColor(
                    red: 153.0 / 255.0,
                    green: 153.0 / 255.0,
                    blue: 153.0 / 255.0,
                    alpha: 1.0
                )
                : UIColor.label
            self.tabBarIconColor = tabBarIconColor ?? defaultUnselectedTint
            self.tabBarSelectedIconColor = tabBarSelectedIconColor
            self.tabBarTextColor = tabBarTextColor ?? defaultUnselectedTint
            self.tabBarSelectedTextColor = tabBarSelectedTextColor
            self.tabBarBadgeBackgroundColor = tabBarBadgeBackgroundColor
            self.tabBarBadgeStrokeColor = tabBarBadgeStrokeColor
            self.tabBarBadgeTextColor = tabBarBadgeTextColor
            self.enableBlur = tabBarAppearance?.enableBlur ?? enableBlur
            self.isDark = isDark
            self.isDarkAppearanceExplicit = isDarkAppearanceExplicit ?? isDark
            self.style = resolvesLegacy ? .legacy : .liquidGlass
            self.outerInsets = outerInsets
            self.pillHeight = pillHeight
            self.totalHeight = totalHeight
            self.bottomInset = bottomInset
            self.sideInset = sideInset
            self.minimizedSideInset = minimizedSideInset
            self.minimizedInterItemSpacing = minimizedInterItemSpacing
            self.innerPadding = innerPadding
            self.maximumRowWidth = maximumRowWidth
            self.preferredItemWidth = preferredItemWidth
            self.showcaseSpacing = showcaseSpacing
            if let tabBarAppearance {
                self.edgeEffectAlpha = tabBarAppearance.edgeEffect?.alpha ?? 0.0
                self.edgeEffectBlurRadiusAtEdge = tabBarAppearance.edgeEffect?.blurRadiusAtEdge ?? edgeEffectBlurRadiusAtEdge
                self.edgeEffectBlurRadiusAtFade = tabBarAppearance.edgeEffect?.blurRadiusAtFade ?? edgeEffectBlurRadiusAtFade
                self.edgeEffectSolidBlur = tabBarAppearance.edgeEffect?.solidBlur ?? edgeEffectSolidBlur
                self.glassEffectStyle = glassEffectStyle
                self.edgeEffectTintColor = tabBarAppearance.edgeEffect?.tintColor
            } else {
                self.edgeEffectAlpha = edgeEffectAlpha
                self.edgeEffectBlurRadiusAtEdge = edgeEffectBlurRadiusAtEdge
                self.edgeEffectBlurRadiusAtFade = edgeEffectBlurRadiusAtFade
                self.edgeEffectSolidBlur = edgeEffectSolidBlur
                self.glassEffectStyle = glassEffectStyle
                self.edgeEffectTintColor = edgeEffectTintColor
            }
        }
    }

    // MARK: - Properties

    // MARK: - Types

    private let backgroundView: NavigationBackgroundView
    private let separatorNode: ASDisplayNode
    private var reduceTransparencyObserver: NSObjectProtocol?
    /// Last public background-alpha request. Scroll-edge visibility gates this
    /// value instead of replacing it, so restoring Legacy chrome also restores
    /// any caller-specified partial opacity.
    private var requestedBackgroundAlpha: CGFloat = 1.0
    private var appliedSharedLegacyAccessoryMaterial = false
    /// Stable, full-row glass group. It deliberately does not morph with the
    /// pill: keeping both the pill material and Search's material below one
    /// `UIGlassContainerEffect` is what lets UIKit render a real merge/split.
    private let tabBarGlassContainer: GlassBackgroundContainerView
    /// Plain geometry owner for the leading pill. The shared glass group stays
    /// full-size while this view alone morphs from the expanded pill to 48pt.
    private let pillGeometryHost: TabBarPillGeometryHostView
    private let liquidLensView: LiquidLensView
    private var searchItemView: GlassBarButtonView?
    /// Pixel-only expanded Search title. The stable GlassBarButton below it
    /// owns the icon, touch, and accessibility throughout the morph.
    private var expandedSearchItemView: TabBarItemView?
    private var legacySearchItemView: TabBarItemView?
    private var searchItem: SearchTabItem?

    private var displayedSearchItemView: UIView? {
        legacySearchItemView ?? searchItemView
    }

    /// Native merge is available only when the grouping host owns an actual
    /// `UIGlassContainerEffect`. The fallback renderer keeps the same stable
    /// hierarchy/geometry, but still uses an overlapping glyph handoff because
    /// two fallback surfaces cannot optically union.
    private var usesNativeSearchMerge: Bool {
        theme.appearanceStyle.usesLiquidGlass
            && tabBarGlassContainer.isUsingNativeContainerEffect
    }
    private var itemViews: [TabBarItemView] = []
    private var selectedItemViews: [TabBarItemView] = []

    private var glassBackgroundView: GlassBackgroundView?
    /// Scroll-edge fade at the bottom — makes content dissolve as it approaches
    /// the floating tab bar pill (mirrors edge-effect on the TabBar).
    private var edgeEffectView: EdgeEffectView?
    private var theme: Theme
    private let followsRuntimeAppearance: Bool

    private var chromeColorTraitCollection: UITraitCollection {
        UITraitCollection(traitsFrom: [
            traitCollection,
            UITraitCollection(userInterfaceStyle: isEffectivelyDark ? .dark : .light)
        ])
    }

    private static let legacyChromeBackgroundAlpha: CGFloat = 0.18
    private static let liquidGlassChromeBackgroundAlpha: CGFloat = 0.20

    internal var chromeGlassAppearance: TabBarChromeGlassAppearance {
        let backgroundAlpha = theme.appearanceStyle.usesLiquidGlass
            ? Self.liquidGlassChromeBackgroundAlpha
            : Self.legacyChromeBackgroundAlpha
        let backgroundColor = resolvedChromeColor(theme.tabBarBackgroundColor)
        let tint: GlassBackgroundView.TintColor
        if backgroundColor.cgColor.alpha <= 0.001 {
            // `UIGlassEffect.tintColor = UIColor.clear` is not equivalent to
            // leaving the tint unset: on-device it produces an opaque dark
            // material. Use the semantic clear recipe so the native renderer
            // receives `nil` in light appearance and remains truly untinted.
            tint = .init(kind: .clear)
        } else {
            tint = .init(
                kind: .custom(
                    style: .clear,
                    color: backgroundColor.withAlphaComponent(
                        backgroundColor.cgColor.alpha * backgroundAlpha
                    )
                )
            )
        }
        return TabBarChromeGlassAppearance(
            viewStyle: theme.glassEffectStyle == .strong ? .prominent : .regular,
            tint: tint,
            isDark: isEffectivelyDark
        )
    }

    private var tabBarChromeTint: GlassBackgroundView.TintColor {
        chromeGlassAppearance.tint
    }

    private func resolvedChromeColor(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: chromeColorTraitCollection)
    }

    /// Additional vertical real estate the bottom chrome material should
    /// cover ABOVE the tab bar's own top edge. Liquid extends its edge effect;
    /// Legacy extends the existing `NavigationBackgroundView` around a rounded
    /// cutout occupied by the accessory's grouped ultra-thin effect.
    public var bottomAccessoryReservedHeight: CGFloat = 0 {
        didSet {
            guard bottomAccessoryReservedHeight != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Effective bottom offset from the tab bar's bottom edge to the pill.
    /// The floating tab bar keeps a fixed visual gap from the screen bottom
    /// so it remains consistent across home-indicator and non-indicator
    /// devices.
    private var effectiveBottomInset: CGFloat {
        return theme.bottomInset
    }

    func setSearchItem(_ item: SearchTabItem?) {
        guard searchItem !== item else { return }
        searchItem = item
        rebuildSearchItemView()
    }

    // MARK: - Minimize Mode (iOS 26 `tabBarMinimizeBehavior`)

    /// Diameter of the collapsed pill / search circle and the height the
    /// `bottomBarAccessory` reflows into between them. Matches the native
    /// 48pt minimized chrome on iOS 26.
    public static let minimizedButtonSize: CGFloat = 48.0

    /// `true` while the tab bar is collapsed into the iOS 26 minimized
    /// state — the pill shrinks to a 48×48 circle on the leading edge
    /// (showing the active tab's icon), the search tab item becomes a
    /// matching 48×48 circle on the trailing edge, and any
    /// `bottomBarAccessory` reflows into the gap between them.
    ///
    /// External callers drive the state through
    /// `setMinimized(_:transition:)` — assignment isn't directly exposed
    /// because we need a transition value to animate the morph.
    public private(set) var isMinimized: Bool = false

    /// Tap handler for the collapsed pill — invoked when the user taps
    /// the 48×48 active-tab circle while minimized. The owning controller
    /// uses this to expand the tab bar back to its full pill form. The normal
    /// `tabSelected` callback is emitted as well, so selected-tab pop/scroll
    /// routing does not disappear merely because Liquid chrome is compact.
    public var onExpandRequested: (() -> Void)?

    /// Active-tab icon drawn inside `pillGeometryHost` while minimized.
    private var minimizedIconNode: ASImageNode?

    private var elasticPressRecognizer: GlassHighlightGestureRecognizer?

    /// Transition the next `layoutLiquidGlassItems` pass should drive
    /// inner frames / glass corner-radius animation through. Set by
    /// `setMinimized`, consumed once by the very next layout pass, then
    /// cleared so subsequent layouts (rotation, selection change) don't
    /// re-animate stale state.
    private var pendingMinimizeTransition: ContainedViewLayoutTransition?
    private var pendingScrollMinimizeArmingTransition: ContainedViewLayoutTransition?
    private var isScrollMinimizeArmed = false
    private var scrollMinimizeArmingProgress: CGFloat = 0.0
    private var minimizeContentAnimationGeneration: UInt = 0
    private var legacyScrollEdgeChromeVisible = true
    internal private(set) var lastLegacyScrollEdgeTransitionWasAnimatedForTesting = false
    internal private(set) var lastLegacyScrollEdgeTransitionDurationForTesting: Double = 0.0

    private static let scrollMinimizeArmedHorizontalInset: CGFloat = 4.0
    private static let scrollMinimizeArmedScale: CGFloat = 0.985
    private static let scrollMinimizeArmedScaleAnimationKey = "aether.tabBar.scrollMinimizeArmedScale"

    /// Expanded-only scroll-intent preview. Geometry is inset locally inside
    /// the tab bar; safe-area reservation and logical minimized state do not
    /// change until the controller commits the actual transition.
    internal func setScrollMinimizeArmingProgress(
        _ progress: CGFloat,
        isActive: Bool,
        transition: ContainedViewLayoutTransition,
        updatesLayout: Bool = true
    ) {
        let resolvedArmed = isActive
            && !isMinimized
            && theme.appearanceStyle.usesLiquidGlass
        let resolvedProgress = resolvedArmed
            ? max(0.0, min(1.0, progress))
            : 0.0
        guard isScrollMinimizeArmed != resolvedArmed
                || abs(scrollMinimizeArmingProgress - resolvedProgress) > 0.0001 else {
            return
        }
        isScrollMinimizeArmed = resolvedArmed
        scrollMinimizeArmingProgress = resolvedProgress
        pendingScrollMinimizeArmingTransition = transition
        if resolvedArmed {
            elasticPressRecognizer?.resetVisualState()
        }
        elasticPressRecognizer?.isEnabled = !resolvedArmed
        guard updatesLayout else { return }
        setNeedsLayout()
        layoutIfNeeded()
    }

    internal func setScrollMinimizeArmed(
        _ armed: Bool,
        transition: ContainedViewLayoutTransition,
        updatesLayout: Bool = true
    ) {
        setScrollMinimizeArmingProgress(
            armed ? 1.0 : 0.0,
            isActive: armed,
            transition: transition,
            updatesLayout: updatesLayout
        )
    }

    /// Toggle the minimized state with an animated morph.
    ///
    /// The morph is layout-driven: pill / search item / lens / icon all
    /// re-frame through the same `transition` so the glass surface
    /// deforms continuously (iOS 26's "liquid" feel) instead of
    /// cross-fading two distinct shapes.
    public func setMinimized(_ minimized: Bool, transition: ContainedViewLayoutTransition) {
        guard theme.appearanceStyle.usesLiquidGlass else {
            forceExpandedWithoutMorph()
            return
        }
        guard isMinimized != minimized else { return }
        // Search is anchored to the minimized active-tab circle. Allow
        // collapsing into that state, but do not expand the tab bar
        // while the search capsule is still active.
        if !minimized && isSearchActive {
            return
        }
        if minimized, isScrollMinimizeArmed {
            // The compact endpoint never inherits the transient preview inset
            // or scale. Its spring starts from the preview's presentation
            // geometry through begin-from-current-state.
            isScrollMinimizeArmed = false
            scrollMinimizeArmingProgress = 0.0
            pendingScrollMinimizeArmingTransition = nil
            elasticPressRecognizer?.isEnabled = true
        }
        isMinimized = minimized

        let resolvedTransition: ContainedViewLayoutTransition
        if transition.isAnimated, UIAccessibility.isReduceMotionEnabled {
            resolvedTransition = .animated(
                duration: min(0.20, max(0.01, transition.duration)),
                curve: .easeInOut
            )
        } else {
            resolvedTransition = transition
        }

        if minimized {
            ensureMinimizedIconView()
        }
        refreshMinimizedIconImage()

        // Stash the transition so the next layout pass can animate
        // every inner frame + glass cornerRadius update through it.
        pendingMinimizeTransition = resolvedTransition

        // Cross-fade item icons ⇄ collapsed icon. The lens itself stays
        // fully opaque — the glass surface IS the collapsed circle, so
        // hiding the lens would make the minimized button transparent.
        // Only the items (which live inside the lens) and the new icon
        // animate their alpha.
        updateMinimizeContentVisibility(
            minimized: minimized,
            transition: resolvedTransition
        )

        // Run the layout pass synchronously so it consumes
        // `pendingMinimizeTransition` while the values are still fresh.
        // `layoutSubviews` itself isn't wrapped in `UIView.animate` —
        // each inner `transition.updateFrame` call runs its own animation
        // block, which is what makes the morph actually animate (the
        // earlier wrapping was getting overridden by subsequent
        // `.immediate` layout passes triggered by `setNeedsLayout`).
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Re-times an in-flight morph without changing its model endpoint. Used
    /// when Reduce Motion changes while UIKit's original spring is running.
    /// `beginFromCurrentState` inside the transition helpers captures the
    /// presentation geometry, so the replacement never jumps backward.
    internal func retargetCurrentMinimizeTransition(
        _ transition: ContainedViewLayoutTransition
    ) {
        guard theme.appearanceStyle.usesLiquidGlass,
              transition.isAnimated else { return }
        pendingMinimizeTransition = transition
        updateMinimizeContentVisibility(
            minimized: isMinimized,
            transition: transition
        )
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Reconciles endpoint channels after an appearance renderer swap (for
    /// example native Liquid Glass to the custom fallback) without rebuilding
    /// either Search representation or changing its geometry/identity.
    private func synchronizeSearchChromeEndpoint() {
        guard !isSearchActive else { return }
        expandedSearchItemView?.alpha = isMinimized ? 0.0 : 1.0
        expandedSearchItemView?.isUserInteractionEnabled = false
        expandedSearchItemView?.accessibilityElementsHidden = true
        searchItemView?.alpha = 1.0
        searchItemView?.transform = .identity
        searchItemView?.chromeMorphKeepsContentIndependentOfMaterial = !usesNativeSearchMerge
        searchItemView?.chromeMorphMaterialAlpha = usesNativeSearchMerge
            ? 1.0
            : (isMinimized ? 1.0 : 0.0)
        searchItemView?.chromeMorphContentAlpha = 1.0
        searchItemView?.isUserInteractionEnabled = true
        searchItemView?.accessibilityElementsHidden = false
    }

    /// Geometry owns the merge clock. Native material stays alive at full
    /// opacity and `UIGlassContainerEffect` decides when the overlapping Search
    /// lobe is still part of the pill and when it has separated. The Search
    /// icon has one stable owner and trajectory; the pixel overlay contributes
    /// only the expanded title, so no late icon handoff can jump vertically.
    private func updateMinimizeContentVisibility(
        minimized: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        minimizeContentAnimationGeneration &+= 1
        let generation = minimizeContentAnimationGeneration
        let regularViews = itemViews + selectedItemViews
        let expandedSearch = expandedSearchItemView
        let minimizedSearch = searchItemView
        let minimizedIcon = minimizedIconNode?.view
        let nativeMerge = usesNativeSearchMerge

        // Search's moving glass host is the one stable interaction and
        // accessibility owner at both endpoints. The expanded TabBarItemView
        // is pixels only and therefore cannot steal a press from native glass.
        expandedSearch?.isUserInteractionEnabled = false
        expandedSearch?.accessibilityElementsHidden = true
        minimizedSearch?.isUserInteractionEnabled = !isSearchActive
        minimizedSearch?.accessibilityElementsHidden = isSearchActive
        minimizedSearch?.alpha = 1.0
        minimizedSearch?.chromeMorphKeepsContentIndependentOfMaterial = !nativeMerge
        minimizedSearch?.chromeMorphContentAlpha = 1.0
        if nativeMerge {
            // Never fade or replace a live native Search effect. Its overlap
            // with the pill is resolved by their shared container effect.
            minimizedSearch?.chromeMorphMaterialAlpha = 1.0
        }

        let applyEndpoint = {
            regularViews.forEach { $0.alpha = minimized ? 0.0 : 1.0 }
            expandedSearch?.alpha = minimized ? 0.0 : 1.0
            minimizedIcon?.alpha = minimized ? 1.0 : 0.0
            minimizedSearch?.alpha = 1.0
            minimizedSearch?.chromeMorphMaterialAlpha = nativeMerge
                ? 1.0
                : (minimized ? 1.0 : 0.0)
            minimizedSearch?.chromeMorphContentAlpha = 1.0
        }

        guard transition.isAnimated else {
            applyEndpoint()
            return
        }

        UIView.animateKeyframes(
            withDuration: max(0.01, transition.duration),
            delay: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction, .calculationModeCubic],
            animations: {
                if minimized {
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.30) {
                        regularViews.forEach { $0.alpha = 0.0 }
                        // The icon is already moving continuously. Only its
                        // expanded title leaves here; fallback material joins
                        // the same early interval instead of appearing later
                        // as a separate wrapping phase.
                        expandedSearch?.alpha = 0.0
                        if !nativeMerge {
                            minimizedSearch?.chromeMorphMaterialAlpha = 1.0
                        }
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.28, relativeDuration: 0.30) {
                        minimizedIcon?.alpha = 1.0
                    }
                } else {
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.26) {
                        minimizedIcon?.alpha = 0.0
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.18, relativeDuration: 0.38) {
                        regularViews.forEach { $0.alpha = 1.0 }
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.68, relativeDuration: 0.32) {
                        // Restore the title only after the stable moving icon
                        // has nearly reached its exact expanded icon frame.
                        // Native material stays live; fallback material fades
                        // over the same interval.
                        expandedSearch?.alpha = 1.0
                        if !nativeMerge {
                            minimizedSearch?.chromeMorphMaterialAlpha = 0.0
                        }
                    }
                }
            },
            completion: { [weak self] _ in
                guard self?.minimizeContentAnimationGeneration == generation else { return }
                applyEndpoint()
            }
        )
    }

    private func forceExpandedWithoutMorph() {
        guard isMinimized else {
            pendingMinimizeTransition = nil
            return
        }
        isMinimized = false
        pendingMinimizeTransition = nil
        itemViews.forEach { $0.alpha = 1.0 }
        selectedItemViews.forEach { $0.alpha = 1.0 }
        minimizedIconNode?.alpha = 0.0
        expandedSearchItemView?.alpha = 1.0
        expandedSearchItemView?.isUserInteractionEnabled = false
        expandedSearchItemView?.accessibilityElementsHidden = true
        searchItemView?.alpha = 1.0
        searchItemView?.chromeMorphKeepsContentIndependentOfMaterial = !usesNativeSearchMerge
        searchItemView?.chromeMorphMaterialAlpha = usesNativeSearchMerge ? 1.0 : 0.0
        searchItemView?.chromeMorphContentAlpha = 1.0
        searchItemView?.isUserInteractionEnabled = !isSearchActive
        searchItemView?.accessibilityElementsHidden = isSearchActive
        setNeedsLayout()
    }

    private func ensureMinimizedIconView() {
        guard minimizedIconNode == nil else { return }
        let icon = ASImageNode()
        icon.contentMode = .center
        icon.view.isUserInteractionEnabled = false
        icon.alpha = 0.0
        // Sibling of the lens inside the pill geometry host. Putting it
        // INSIDE the lens (`contentView` / `selectedContentView`) makes
        // it disappear: the lens applies a selection-shaped mask to
        // those views so anything outside the selection capsule is
        // clipped, and at the morph endpoints the geometry doesn't line up.
        // The plain host follows the pill's presentation frame while the
        // outer glass group remains full-row and stable.
        pillGeometryHost.addSubview(icon.view)
        minimizedIconNode = icon
    }

    /// (Re)apply the current active-tab image to the collapsed icon
    /// view, using the raw image without any symbol configuration — that
    /// keeps the glyph the same visual size as the regular tab item
    /// icons (which also render the raw image with `.center` content
    /// mode). The 48×48 glass capsule provides the surrounding chrome;
    /// the icon itself doesn't need to grow.
    private func refreshMinimizedIconImage() {
        guard let icon = minimizedIconNode, let raw = activeTabIcon() else { return }
        icon.image = raw.withRenderingMode(.alwaysTemplate)
        icon.tintColor = resolvedChromeColor(theme.tabBarSelectedIconColor)
    }

    private func handleMinimizedActiveTabTap() {
        if isSearchActive {
            onSearchDismissed?()
            return
        }
        guard isMinimized else { return }
        onExpandRequested?()
        tabSelected?(selectedIndex)
    }

    #if DEBUG
    func simulateMinimizedActiveTabTapForTests() {
        handleMinimizedActiveTabTap()
    }

    internal var effectiveDarkAppearanceForTesting: Bool {
        isEffectivelyDark
    }

    internal var legacySearchItemFrameForTesting: CGRect? {
        legacySearchItemView?.frame
    }

    internal var searchSharesGlassContainerForTesting: Bool {
        guard let searchItemView else { return false }
        return searchItemView.isDescendant(of: tabBarGlassContainer.contentView)
            && liquidLensView.isDescendant(of: tabBarGlassContainer.contentView)
    }

    internal var usesNativeSearchMergeForTesting: Bool {
        usesNativeSearchMerge
    }

    internal var pillGeometryFrameForTesting: CGRect {
        pillGeometryHost.frame
    }
    #endif

    private struct ExpandedChromeLayout {
        let pillFrame: CGRect
        let searchFrame: CGRect?
    }

    /// Resolves the reference layout for the expanded liquid-glass row.
    ///
    /// The whole row is capped and centered first. With Search, the expanded
    /// endpoint is one full-width surface and Search occupies its final slot;
    /// only the minimized endpoint detaches Search into a trailing circle.
    /// Without Search the pill keeps the content-sized behaviour.
    private func expandedChromeLayout(
        in size: CGSize,
        itemCount: Int,
        horizontalInset: CGFloat = 0.0
    ) -> ExpandedChromeLayout {
        let sideInset = max(0.0, theme.sideInset)
        let horizontalCapacity = max(0.0, size.width - sideInset * 2.0)
        let hasSearchItem = searchItem != nil
        // Four tabs (or a Search slot) use the production screen margins.
        // screen margins. Compact bars with up to three tabs keep the
        // centered, content-sized geometry.
        let usesFixedScreenMargins = hasSearchItem || itemCount >= 4
        let rowWidth = usesFixedScreenMargins
            ? horizontalCapacity
            : min(horizontalCapacity, max(0.0, theme.maximumRowWidth))
        let rowX = usesFixedScreenMargins ? sideInset : max(sideInset, (size.width - rowWidth) / 2.0)
        let pillY = size.height - effectiveBottomInset - theme.pillHeight

        let maximumPillWidth = rowWidth
        let preferredPillWidth: CGFloat
        if itemCount > 0 {
            preferredPillWidth = max(0.0, theme.innerPadding * 2.0)
                + CGFloat(itemCount + (hasSearchItem ? 1 : 0))
                    * max(0.0, theme.preferredItemWidth)
        } else {
            preferredPillWidth = 0.0
        }
        // The production wide row is a real edge-to-edge container inside
        // those margins, not merely a cap around content. This keeps the
        // four-tab capsule and the tabs+search combination aligned to exactly
        // the same screen grid on every device width.
        let pillWidth = usesFixedScreenMargins
            ? maximumPillWidth
            : min(maximumPillWidth, preferredPillWidth)
        let pillX = rowX + (rowWidth - pillWidth) / 2.0
        let basePillFrame = CGRect(
            x: pillX,
            y: pillY,
            width: pillWidth,
            height: theme.pillHeight
        )
        let resolvedInset = min(
            max(0.0, horizontalInset),
            max(0.0, basePillFrame.width * 0.5)
        )
        let pillFrame = CGRect(
            x: basePillFrame.minX + resolvedInset,
            y: basePillFrame.minY,
            width: max(0.0, basePillFrame.width - resolvedInset * 2.0),
            height: basePillFrame.height
        )

        let searchFrame: CGRect?
        if hasSearchItem {
            let slotCount = max(1, itemCount + 1)
            let slotAreaWidth = max(0.0, pillFrame.width - theme.innerPadding * 2.0)
            let slotWidth = slotAreaWidth / CGFloat(slotCount)
            searchFrame = CGRect(
                x: pillFrame.minX + theme.innerPadding + CGFloat(itemCount) * slotWidth,
                y: pillFrame.minY,
                width: slotWidth,
                height: pillFrame.height
            )
        } else {
            searchFrame = nil
        }

        return ExpandedChromeLayout(pillFrame: pillFrame, searchFrame: searchFrame)
    }

    /// Pure-function pill frame for the given bounds size and minimize
    /// state. Lets the owning controller compute accessory layout
    /// without forcing a synchronous `tabBarView.layoutSubviews()` —
    /// that synchronous call was clobbering the in-flight morph
    /// animation by re-setting inner frames with `.immediate`.
    public func computePillFrame(in size: CGSize, minimized: Bool) -> CGRect {
        if theme.appearanceStyle == .legacy {
            return CGRect(x: 0.0, y: 0.0, width: size.width, height: LegacyLayout.contentHeight)
        }
        // Use the same fixed visual bottom inset as the actual layout pass.
        let bottomInset = effectiveBottomInset
        let sideInset = theme.minimizedSideInset
        if minimized {
            let pillSize = Self.minimizedButtonSize
            let pillY = size.height - bottomInset - pillSize
            return CGRect(x: sideInset, y: pillY, width: pillSize, height: pillSize)
        }
        let armingInset = isScrollMinimizeArmed && !isMinimized
            ? Self.scrollMinimizeArmedHorizontalInset * scrollMinimizeArmingProgress
            : 0.0
        return expandedChromeLayout(
            in: size,
            itemCount: items.count,
            horizontalInset: armingInset
        ).pillFrame
    }

    // MARK: - Search Mode (morph animation)

    /// When `true`, the tab bar is morphed into search mode.
    public private(set) var isSearchActive: Bool = false

    /// Mirrors the on-screen keyboard. Set by the owning controller from
    /// `containerLayoutUpdated` (driven by `AetherWindow`'s keyboard
    /// notifications). Search-mode chrome reflows through the same
    /// keyboard transition after the user explicitly focuses the field.
    public private(set) var isKeyboardVisible: Bool = false

    /// Vertical distance the search row sits below the current chrome
    /// top while search is active. Mostly used by compatibility layout
    /// paths; normal search activation keeps the bar minimized and
    /// hides bottom accessories from the occupied row.
    public var searchRowTopOffset: CGFloat {
        guard isSearchActive else { return 0 }
        let referenceHeight = isMinimized ? Self.minimizedButtonSize : theme.pillHeight
        return max(0, (referenceHeight - Self.searchModeHeight) / 2)
    }

    /// Sync the cached keyboard state and reflow search chrome through
    /// the keyboard transition. Idempotent — called every layout pass.
    public func setKeyboardVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        guard isKeyboardVisible != visible else { return }
        isKeyboardVisible = visible
        // Use `animateView` so the frame setters inside
        // `positionSearchViewsExpanded` ride the keyboard's transition
        // instead of snapping if the field is focused later.
        if isSearchActive {
            transition.animateView { [weak self] in
                self?.positionSearchViewsExpanded()
            }
        }
    }

    /// Text entered in the search field while search is active.
    public var searchText: String { searchTextField?.text ?? "" }

    /// Called when search text changes.
    public var onSearchTextChanged: ((String) -> Void)?

    /// Called when search is dismissed via the active-tab circle.
    public var onSearchDismissed: (() -> Void)?

    // Search mode views
    private var searchCapsule: GlassBackgroundView?       // expanded glass capsule for text field
    private var searchTextField: UITextField?               // text field inside capsule
    private var searchCloseButton: GlassBarButtonView?      // round glass X button
    private var searchDimView: EdgeEffectView?               // edge-effect bg

    private static let searchOpenMorphDuration = AetherMotion.search.presentation.duration
    private static let searchOpenMorphDamping = AetherMotion.search.presentation.dampingRatio
    private static let searchOpenMorphVelocity = AetherMotion.search.presentation.initialVelocity
    private static let searchCloseMorphDuration = AetherMotion.search.dismissal.duration
    private static let searchCloseMorphDamping = AetherMotion.search.dismissal.dampingRatio
    private static let searchCloseMorphVelocity = AetherMotion.search.dismissal.initialVelocity

    private func setSearchTriggerHiddenForSearchMode(_ hidden: Bool) {
        if hidden {
            searchItemView?.alpha = 0.0
            searchItemView?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            expandedSearchItemView?.alpha = 0.0
            expandedSearchItemView?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } else {
            searchItemView?.alpha = 1.0
            searchItemView?.transform = .identity
            expandedSearchItemView?.alpha = isMinimized ? 0.0 : 1.0
            expandedSearchItemView?.transform = .identity
        }
    }

    /// Morph: pill → active-tab circle, search button → capsule with text field.
    public func activateSearchMode(animated: Bool) {
        guard !isSearchActive else { return }
        isSearchActive = true
        buildSearchViews()
        // Alpha does not remove an element from hit-testing/accessibility.
        // Quarantine the stable Search owner for the whole active-search
        // session before the visual morph starts.
        searchItemView?.isUserInteractionEnabled = false
        searchItemView?.accessibilityElementsHidden = true

        if animated {
            positionSearchViewsAtOrigin()
            // Start capsule small for the glass morph feel.
            searchCapsule?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            searchCloseButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            UIView.animate(
                withDuration: Self.searchOpenMorphDuration,
                delay: 0,
                usingSpringWithDamping: Self.searchOpenMorphDamping,
                initialSpringVelocity: Self.searchOpenMorphVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.positionSearchViewsExpanded()
                self.searchCapsule?.transform = .identity
                self.searchCloseButton?.transform = .identity
                self.searchCloseButton?.alpha = 1.0
                self.tabBarGlassContainer.alpha = 1.0
                self.tabBarGlassContainer.transform = .identity
                // Search circle (the standalone "открыть поиск" button)
                // morphs into the expanded capsule, so hide the original
                // item while search is active — otherwise it stays
                // visible next to the expanded search field.
                self.setSearchTriggerHiddenForSearchMode(true)
                self.searchDimView?.alpha = 1.0
            }
        } else {
            positionSearchViewsExpanded()
            tabBarGlassContainer.alpha = 1.0
            tabBarGlassContainer.transform = .identity
            setSearchTriggerHiddenForSearchMode(true)
            searchCloseButton?.alpha = 1.0
            searchDimView?.alpha = 1.0
        }
    }

    /// Reverse morph: capsule → search button. The owning controller
    /// restores the tab bar's pre-search minimized state in parallel.
    public func deactivateSearchMode(animated: Bool) {
        guard isSearchActive else { return }
        isSearchActive = false
        searchTextField?.resignFirstResponder()
        // Keep the underlying Search target quarantined until the closing
        // capsule has actually left the screen.
        searchItemView?.isUserInteractionEnabled = false
        searchItemView?.accessibilityElementsHidden = true

        if animated {
            // Phase 1: quick fade of search elements + shrink toward origins
            UIView.animate(
                withDuration: Self.searchCloseMorphDuration,
                delay: 0,
                usingSpringWithDamping: Self.searchCloseMorphDamping,
                initialSpringVelocity: Self.searchCloseMorphVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                // Fade + scale-down all search elements
                self.searchCapsule?.alpha = 0.0
                self.searchCapsule?.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                self.searchTextField?.alpha = 0.0
                self.searchCloseButton?.alpha = 0.0
                self.searchCloseButton?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                self.searchDimView?.alpha = 0.0

                // Restore tab bar + search circle (hidden during search).
                self.tabBarGlassContainer.alpha = 1.0
                self.tabBarGlassContainer.transform = .identity
                self.setSearchTriggerHiddenForSearchMode(false)
            } completion: { _ in
                self.teardownSearchViews()
                self.searchItemView?.isUserInteractionEnabled = true
                self.searchItemView?.accessibilityElementsHidden = false
            }
        } else {
            tabBarGlassContainer.alpha = 1.0
            tabBarGlassContainer.transform = .identity
            setSearchTriggerHiddenForSearchMode(false)
            teardownSearchViews()
            searchItemView?.isUserInteractionEnabled = true
            searchItemView?.accessibilityElementsHidden = false
        }
    }

    // -- Build / teardown

    private func buildSearchViews() {
        if theme.style == .liquidGlass {
            let dim = EdgeEffectView()
            dim.appearanceStyleOverride = theme.appearanceStyle
            dim.isUserInteractionEnabled = false
            dim.alpha = 0.0
            if let edgeEffectView {
                insertSubview(dim, aboveSubview: edgeEffectView)
            } else {
                insertSubview(dim, aboveSubview: backgroundView)
            }
            searchDimView = dim
        }

        let capsule = GlassBackgroundView(
            style: chromeGlassAppearance.viewStyle,
            appearanceStyle: theme.appearanceStyle
        )
        capsule.surfaceRole = .input
        capsule.isDarkOverride = isEffectivelyDark
        addSubview(capsule)
        searchCapsule = capsule

        let tf = UITextField()
        tf.placeholder = "Search"
        tf.font = .aetherScaledSystemFont(
            ofSize: 17,
            maximumPointSize: 24,
            compatibleWith: traitCollection
        )
        tf.textColor = resolvedChromeColor(.label)
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        tf.alpha = 0.0
        tf.delegate = self
        tf.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
        // leftView wrapper: icon pinned near the left edge, right-side
        // padding controls the visible gap before the placeholder.
        tf.leftView = AetherSearchIconLeftView()
        (tf.leftView as? AetherSearchIconLeftView)?.updateTintColor(
            resolvedChromeColor(.secondaryLabel)
        )
        tf.leftViewMode = .always
        addSubview(tf)
        searchTextField = tf

        // Round glass close button (X)
        let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        let close = GlassBarButtonView(
            icon: closeIcon,
            state: .glass,
            appearanceStyle: theme.appearanceStyle
        )
        close.glassStyle = chromeGlassAppearance.viewStyle
        close.contentTintColor = resolvedChromeColor(.label)
        close.glassTintColor = tabBarChromeTint
        close.isDarkAppearance = isEffectivelyDark
        close.alpha = 0.0
        close.accessibilityIdentifier = "aether.search.close"
        close.accessibilityLabel = "Close search"
        close.action = { [weak self] _ in self?.onSearchDismissed?() }
        addSubview(close)
        searchCloseButton = close

        // The active-tab control is not a separate search view. It is
        // the real minimized tab bar (`tabBarGlassContainer`) kept
        // visible while the search button expands into the field.
    }

    private func teardownSearchViews() {
        searchCapsule?.removeFromSuperview()
        searchTextField?.removeFromSuperview()
        searchCloseButton?.removeFromSuperview()
        searchDimView?.removeFromSuperview()
        searchCapsule = nil
        searchTextField = nil
        searchCloseButton = nil
        searchDimView = nil
    }

    private func activeTabIcon() -> UIImage? {
        guard selectedIndex < itemViews.count else { return nil }
        let item = items[selectedIndex]
        return item.selectedImage ?? item.image
    }

    // -- Positioning

    /// Reference frames in TabBarView coordinates.
    private var searchItemFrame: CGRect {
        guard let searchButton = displayedSearchItemView else {
            return CGRect(x: bounds.width - theme.sideInset - theme.pillHeight,
                          y: bounds.height - effectiveBottomInset - theme.pillHeight,
                          width: theme.pillHeight, height: theme.pillHeight)
        }
        return convert(searchButton.bounds, from: searchButton)
    }

    private var activeTabSearchAnchorFrame: CGRect {
        return computePillFrame(in: bounds.size, minimized: true)
    }

    private static let searchModeHeight: CGFloat = 42.0

    /// Start: capsule at search item origin.
    private func positionSearchViewsAtOrigin() {
        let h = Self.searchModeHeight
        let itemFrame = searchItemFrame

        updateSearchDimFrame()

        // Capsule starts at the search item's position (small circle)
        let capsuleFrame = CGRect(x: itemFrame.midX - h / 2, y: itemFrame.midY - h / 2, width: h, height: h)
        searchCapsule?.frame = capsuleFrame
        searchCapsule?.update(size: capsuleFrame.size, cornerRadius: h / 2, isDark: isEffectivelyDark,
                              tintColor: tabBarChromeTint, isInteractive: false, isVisible: true, transition: .immediate)

        // Text field hidden at capsule position
        searchTextField?.frame = CGRect(x: capsuleFrame.minX + 8, y: capsuleFrame.minY, width: max(0, capsuleFrame.width - 16), height: h)
        searchTextField?.alpha = 0.0

        // Close button hidden at capsule right edge
        searchCloseButton?.frame = CGRect(x: capsuleFrame.maxX - h, y: capsuleFrame.minY, width: h, height: h)
        searchCloseButton?.alpha = 0.0

    }

    /// End: capsule fills the row to the right of the minimized active
    /// tab. The active-tab control itself is the real 48×48 tab bar
    /// circle, not a duplicate search-mode view.
    /// The capsule always reserves the trailing close-button slot so the
    /// dismissal affordance remains visible before and after keyboard focus.
    private func positionSearchViewsExpanded() {
        let h = Self.searchModeHeight
        let sideInset = theme.minimizedSideInset
        let activeFrame = activeTabSearchAnchorFrame
        let pillY = activeFrame.midY - h / 2.0

        updateSearchDimFrame()

        // Close button remains in its rightmost slot for the whole search
        // session, independently of text-field focus.
        let closeFrame = CGRect(x: bounds.width - sideInset - h, y: pillY, width: h, height: h)
        searchCloseButton?.frame = closeFrame

        let capsuleFrame = capsuleFrameExpanded(
            pillY: pillY,
            activeTabRight: activeFrame.maxX,
            closeMinX: closeFrame.minX
        )
        searchCapsule?.frame = capsuleFrame
        searchCapsule?.update(size: capsuleFrame.size, cornerRadius: h / 2, isDark: isEffectivelyDark,
                              tintColor: tabBarChromeTint, isInteractive: false, isVisible: true, transition: .immediate)

        // Text field inside capsule
        searchTextField?.frame = CGRect(x: capsuleFrame.minX + 8, y: pillY, width: max(0, capsuleFrame.width - 16), height: h)
        searchTextField?.alpha = 1.0
    }

    /// Capsule's target frame, ending 8pt before the always-visible close
    /// button.
    private func capsuleFrameExpanded(pillY: CGFloat, activeTabRight: CGFloat, closeMinX: CGFloat) -> CGRect {
        let h = Self.searchModeHeight
        let spacing: CGFloat = 8.0
        let capsuleX = activeTabRight + spacing
        let trailing = closeMinX - spacing
        let capsuleWidth = max(0, trailing - capsuleX)
        return CGRect(x: capsuleX, y: pillY, width: capsuleWidth, height: h)
    }

    private func updateSearchDimFrame() {
        guard let dim = searchDimView else { return }
        // Regular edge effect keeps the historical bleed below bounds to cover
        // keyboard-corner gaps. Strong edge effect is a bounded Liquid Glass v2 surface.
        let overflow: CGFloat = theme.glassEffectStyle == .regular ? 40.0 : 0.0
        let extFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + overflow)
        dim.frame = extFrame
        dim.clipsToBounds = theme.glassEffectStyle != .regular
        let hasVisibleEdgeEffect = self.hasVisibleEdgeEffect
        dim.isHidden = !hasVisibleEdgeEffect
        let fadeHeight: CGFloat = min(48.0, bounds.height * 0.4)
        let usesProgressiveBlur = theme.glassEffectStyle == .regular
        dim.update(
            content: hasVisibleEdgeEffect ? (theme.edgeEffectTintColor ?? theme.tabBarBackgroundColor) : .clear,
            blur: hasVisibleEdgeEffect,
            alpha: theme.edgeEffectAlpha,
            rect: CGRect(origin: .zero, size: extFrame.size),
            edge: .bottom,
            edgeSize: usesProgressiveBlur ? fadeHeight : 0.0,
            blurRadiusAtEdge: theme.edgeEffectBlurRadiusAtEdge,
            blurRadiusAtFade: usesProgressiveBlur ? 0.0 : theme.edgeEffectBlurRadiusAtEdge,
            solidBlur: !usesProgressiveBlur,
            minimumFadeAlpha: usesProgressiveBlur ? 0.0 : 0.04,
            transition: .immediate
        )
    }

    private var hasVisibleEdgeEffect: Bool {
        theme.edgeEffectAlpha > 0.001
            || theme.edgeEffectBlurRadiusAtEdge > 0.001
            || theme.edgeEffectBlurRadiusAtFade > 0.001
    }

    @discardableResult
    private func ensureEdgeEffectView() -> EdgeEffectView {
        if let edgeEffectView {
            return edgeEffectView
        }
        let edge = EdgeEffectView()
        edge.appearanceStyleOverride = theme.appearanceStyle
        edge.isUserInteractionEnabled = false
        insertSubview(edge, aboveSubview: backgroundView)
        edgeEffectView = edge
        return edge
    }

    @objc private func searchTextDidChange() {
        onSearchTextChanged?(searchTextField?.text ?? "")
    }

    public var items: [AetherTabBarItem] = [] {
        didSet {
            rebuildItemViews()
        }
    }

    public var selectedIndex: Int = 0 {
        didSet {
            if selectedIndex != oldValue {
                if theme.style == .liquidGlass, pendingLensSelectionTransition == nil {
                    pendingLensSelectionTransition = .animated(
                        duration: AetherMotion.tabBarSelection.duration,
                        curve: .customSpring(
                            damping: AetherMotion.tabBarSelection.dampingRatio,
                            initialVelocity: AetherMotion.tabBarSelection.initialVelocity
                        )
                    )
                }
                updateSelection(animated: true)
            }
        }
    }

    public var tabSelected: ((Int) -> Void)?
    public var tabDoubleTapped: ((Int) -> Void)?
    public var tabLongPressed: ((Int, UIView, UIGestureRecognizer) -> Void)?
    public var tabSwipeAction: ((Int, TabBarItemSwipeDirection) -> Void)?
    public var itemHasDoubleTapAction: ((Int) -> Bool)?
    public var disabledPressed: (() -> Void)?

    private var interactionsEnabled: Bool = true
    private var lastTapIndex: Int?
    private var lastTapTimestamp: CFTimeInterval = 0.0

    /// Drag-to-select state. Mirrors `TabBarComponent.selectionGestureState`:
    /// the native iOS 26 interaction where the liquid lens follows the user's
    /// finger as they drag across tabs.
    private struct SelectionGestureState {
        var startIndex: Int
        var currentIndex: Int
        var currentX: CGFloat
        var itemWidth: CGFloat
        var contentOriginX: CGFloat
    }
    private var selectionGestureState: SelectionGestureState?
    private var pendingLensSelectionTransition: ContainedViewLayoutTransition?

    // MARK: - Init

    public init(theme explicitTheme: Theme? = nil) {
        let theme: Theme
        if let explicitTheme {
            theme = explicitTheme
        } else {
            let appearance = AetherAppearance.runtimeCurrent
            let context = AetherAppearanceResolutionContext(
                appearance: appearance,
                surface: .tab,
                placement: .tab
            )
            theme = Theme(
                aetherResolvedAppearance: AetherTabBarAppearanceResolver.resolve(
                    context: context
                )
            )
        }
        self.theme = theme
        self.followsRuntimeAppearance = explicitTheme == nil
        self.backgroundView = NavigationBackgroundView(
            color: theme.tabBarBackgroundColor,
            enableBlur: theme.enableBlur,
            blurStyle: theme.appearanceStyle == .legacy ? .systemChromeMaterial : .systemMaterial
        )
        self.separatorNode = ASDisplayNode()
        self.tabBarGlassContainer = GlassBackgroundContainerView(
            spacing: 7.0,
            appearanceStyle: theme.appearanceStyle
        )
        self.pillGeometryHost = TabBarPillGeometryHostView()
        self.liquidLensView = LiquidLensView(
            kind: .externalContainer,
            appearanceStyle: theme.appearanceStyle,
            renderingSuspended: theme.appearanceStyle == .legacy
        )
        self.edgeEffectView = nil

        super.init(frame: .zero)

        reduceTransparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.backgroundView.refreshReduceTransparencyStatus()
            self?.refreshLegacyTabItemVibrancy()
            self?.setNeedsLayout()
        }

        let styleOverride = theme.appearanceStyle
        tabBarGlassContainer.appearanceStyleOverride = styleOverride
        liquidLensView.appearanceStyleOverride = styleOverride

        addSubview(backgroundView)
        separatorNode.backgroundColor = theme.tabBarSeparatorColor
        addSubview(separatorNode.view)

        // Bottom scroll-edge fade — placed under the floating tab pill so
        // scroll content dissolves as it approaches the pill edge (mirrors
        // EdgeEffect on TabBar).
        if theme.style == .liquidGlass {
            _ = ensureEdgeEffectView()
        }

        // The outer container is a stable, full-row grouping effect. The pill
        // and Search are independent geometry/touch owners below it, but their
        // UIGlassEffects are siblings in one group so proximity — not an alpha
        // cross-fade — performs the native iOS 26 merge and separation.
        addSubview(tabBarGlassContainer)
        pillGeometryHost.backgroundColor = .clear
        pillGeometryHost.clipsToBounds = false
        tabBarGlassContainer.contentView.addSubview(pillGeometryHost)
        pillGeometryHost.addSubview(liquidLensView)

        let lensTap = UITapGestureRecognizer(target: self, action: #selector(lensTapped(_:)))
        lensTap.delegate = self
        liquidLensView.addGestureRecognizer(lensTap)
        liquidLensView.glassStyle = theme.glassEffectStyle == .strong ? .prominent : .regular
        liquidLensView.glassTintColor = tabBarChromeTint

        // Drag-to-select: lens follows the finger. Matches the native iOS 26
        // TabBarController pan interaction.
        let lensPan = TabSelectionRecognizer(target: self, action: #selector(lensPanned(_:)))
        lensPan.delegate = self
        liquidLensView.addGestureRecognizer(lensPan)

        let lensLongPress = UILongPressGestureRecognizer(target: self, action: #selector(lensLongPressed(_:)))
        lensLongPress.delegate = self
        liquidLensView.addGestureRecognizer(lensLongPress)

        let lensSwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(lensSwiped(_:)))
        lensSwipeLeft.direction = .left
        lensSwipeLeft.delegate = self
        liquidLensView.addGestureRecognizer(lensSwipeLeft)

        let lensSwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(lensSwiped(_:)))
        lensSwipeRight.direction = .right
        lensSwipeRight.delegate = self
        liquidLensView.addGestureRecognizer(lensSwipeRight)

        // Pre-iOS 26 elastic press feedback for the whole tab-bar glass
        // capsule. iOS 26+ gets the native UIGlassContainerEffect warp
        // (the container's own `isInteractive` hook).
        updateElasticPressRenderer()

        setGlassStyle(enabled: theme.enableBlur)
        applyEffectiveGlassAppearanceOverride()
        refreshSemanticChromeForCurrentTraits()
        if followsRuntimeAppearance {
            AetherAppearanceConsumerRegistry.register(self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let reduceTransparencyObserver {
            NotificationCenter.default.removeObserver(
                reduceTransparencyObserver
            )
        }
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        guard followsRuntimeAppearance else { return }
        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .tab,
            placement: .tab,
            traitCollection: traitCollection
        )
        updateTheme(
            Theme(
                aetherResolvedAppearance: AetherTabBarAppearanceResolver.resolve(
                    context: context
                )
            )
        )
    }

    internal var appearanceStyleForTesting: AetherAppearanceStyle {
        theme.appearanceStyle
    }

    #if DEBUG
    internal var legacyUnifiedBottomMaterialFrameForTesting: CGRect? {
        guard theme.appearanceStyle == .legacy,
              bottomAccessoryReservedHeight > 0.001,
              theme.enableBlur else {
            return nil
        }
        return backgroundView.frame
    }

    internal var legacyUnifiedBottomMaterialMaskFrameForTesting: CGRect? {
        backgroundView.bottomAccessoryMaterialMaskFrameForTesting
    }

    internal var legacyUnifiedBottomMaterialCutoutFrameForTesting: CGRect? {
        backgroundView.bottomAccessoryMaterialCutoutFrameForTesting
    }

    internal var legacyItemVibrancyStatesForTesting: [Bool] {
        itemViews.map(\.contentUsesUIKitVibrancyForTesting)
    }

    internal var legacySearchItemUsesVibrancyForTesting: Bool? {
        legacySearchItemView?.contentUsesUIKitVibrancyForTesting
    }

    internal var legacyUnifiedBottomMaterialAlphaForTesting: CGFloat? {
        legacyUnifiedBottomMaterialFrameForTesting == nil
            ? nil
            : backgroundView.alpha
    }

    internal var legacyUnifiedBottomMaterialUsesPublicBlurForTesting: Bool {
        backgroundView.usesPublicBlurEffectForTesting
    }

    internal var legacyUnifiedAttachedChromeAlphaForTesting: CGFloat? {
        backgroundView.bottomAccessoryAttachedChromeAlphaForTesting
    }

    internal var isLiquidLensRendererSuspendedForTesting: Bool {
        liquidLensView.isRendererSuspendedForTesting
    }

    internal var hasInstalledLiquidLensRendererForTesting: Bool {
        liquidLensView.hasInstalledRendererForTesting
    }

    internal var attachedBackgroundBlurStyleForTesting: UIBlurEffect.Style {
        backgroundView.blurStyle
    }

    internal var attachedBackgroundUsesPublicBlurForTesting: Bool {
        backgroundView.usesPublicBlurEffectForTesting
    }
    #endif

    // MARK: - Theme

    public func updateTheme(_ theme: Theme) {
        let previousStyle = self.theme.style
        self.theme = theme
        if theme.appearanceStyle == .legacy {
            isScrollMinimizeArmed = false
            scrollMinimizeArmingProgress = 0.0
            pendingScrollMinimizeArmingTransition = nil
            updateScrollMinimizeArmingScale(progress: 0.0, transition: .immediate)
            elasticPressRecognizer?.isEnabled = true
            forceExpandedWithoutMorph()
            liquidLensView.setRendererSuspended(true)
        }
        let styleOverride = theme.appearanceStyle
        tabBarGlassContainer.appearanceStyleOverride = styleOverride
        liquidLensView.appearanceStyleOverride = styleOverride
        if theme.appearanceStyle.usesLiquidGlass {
            liquidLensView.setRendererSuspended(false)
        }
        glassBackgroundView?.appearanceStyleOverride = styleOverride
        edgeEffectView?.appearanceStyleOverride = styleOverride
        searchDimView?.appearanceStyleOverride = styleOverride
        searchCapsule?.appearanceStyleOverride = styleOverride
        searchItemView?.appearanceStyleOverride = styleOverride
        searchItemView?.glassStyle = chromeGlassAppearance.viewStyle
        searchCloseButton?.appearanceStyleOverride = styleOverride
        searchCloseButton?.glassStyle = chromeGlassAppearance.viewStyle
        searchCapsule?.updateStyle(chromeGlassAppearance.viewStyle)
        updateElasticPressRenderer()
        if theme.style == .liquidGlass {
            _ = ensureEdgeEffectView()
        } else {
            edgeEffectView?.layer.removeAllAnimations()
            edgeEffectView?.removeFromSuperview()
            edgeEffectView = nil
        }
        if theme.appearanceStyle.usesLiquidGlass {
            backgroundView.clearBottomAccessoryMaterialMask()
        }
        backgroundView.blurStyle = theme.appearanceStyle == .legacy ? .systemChromeMaterial : .systemMaterial
        backgroundView.updateColor(color: theme.tabBarBackgroundColor, enableBlur: theme.enableBlur, transition: .immediate)
        separatorNode.backgroundColor = resolvedChromeColor(theme.tabBarSeparatorColor)
        liquidLensView.glassStyle = theme.glassEffectStyle == .strong ? .prominent : .regular
        liquidLensView.glassTintColor = tabBarChromeTint
        applyEffectiveGlassAppearanceOverride()
        setGlassStyle(enabled: theme.enableBlur)
        if theme.appearanceStyle == .legacy {
            applyLegacyScrollEdgeChromeVisibility()
        }
        if previousStyle != theme.style {
            rebuildItemViews()
            rebuildSearchItemView()
        } else {
            itemViews.forEach { $0.updateTheme(theme, colorTraitCollection: chromeColorTraitCollection) }
            selectedItemViews.forEach { $0.updateTheme(theme, colorTraitCollection: chromeColorTraitCollection) }
            expandedSearchItemView?.updateTheme(theme, colorTraitCollection: chromeColorTraitCollection)
            legacySearchItemView?.updateTheme(theme, colorTraitCollection: chromeColorTraitCollection)
        }
        refreshSemanticChromeForCurrentTraits()
        refreshLegacyTabItemVibrancy()
        synchronizeSearchChromeEndpoint()
        updateSelection(animated: false)
        setNeedsLayout()
    }

    private func updateElasticPressRenderer() {
        guard #unavailable(iOS 26.0) else { return }
        if theme.appearanceStyle.usesLiquidGlass {
            guard elasticPressRecognizer == nil else { return }
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.motionProfile = AetherMotion.tabBarPress
            // Search is a sibling in the shared optical group. Scope fallback
            // press feedback to the pill geometry so pressing one control never
            // scales/highlights the other.
            elastic.touchEffectView = pillGeometryHost
            elastic.highlightContainerView = pillGeometryHost
            pillGeometryHost.addGestureRecognizer(elastic)
            elasticPressRecognizer = elastic
        } else if let elasticPressRecognizer {
            elasticPressRecognizer.resetVisualState()
            pillGeometryHost.removeGestureRecognizer(elasticPressRecognizer)
            self.elasticPressRecognizer = nil
        }
    }

    // MARK: - Glass

    public func setGlassStyle(enabled: Bool) {
        if theme.appearanceStyle == .legacy {
            // `backgroundView` already owns the canonical public UIKit
            // `systemChromeMaterial` renderer. Installing another surface
            // here stacked a tint/border above that blur and made the bar
            // look like an opaque colour block.
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 1.0
            liquidLensView.isHidden = true
            separatorNode.alpha = legacyScrollEdgeChromeVisible ? 1.0 : 0.0
            return
        }

        if theme.style == .liquidGlass {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 0.0
            separatorNode.alpha = 0.0
            liquidLensView.isHidden = false
            return
        }

        liquidLensView.isHidden = true
        separatorNode.alpha = 1.0
        if enabled {
            if glassBackgroundView == nil {
                let glass = GlassBackgroundView(style: .regular)
                glass.surfaceRole = .attachedBar
                glass.appearanceStyleOverride = theme.appearanceStyle
                glass.isDarkOverride = isEffectivelyDark
                insertSubview(glass, aboveSubview: backgroundView)
                self.glassBackgroundView = glass
                layoutGlassBackground()
            }
            backgroundView.alpha = 0.0
        } else {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 1.0
        }
    }

    public func updateInteractionsEnabled(_ enabled: Bool, transition: ContainedViewLayoutTransition) {
        interactionsEnabled = enabled
        transition.updateAlpha(view: self, alpha: enabled ? 1.0 : 0.5)
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        requestedBackgroundAlpha = alpha
        let resolvedAlpha = theme.appearanceStyle == .legacy
            && !legacyScrollEdgeChromeVisible
            && !usesSharedLegacyAccessoryMaterial
            ? 0.0
            : requestedBackgroundAlpha
        backgroundView.updateBackgroundAlpha(resolvedAlpha, transition: transition)
        let separatorAlpha = theme.appearanceStyle == .legacy
            && !legacyScrollEdgeChromeVisible
            ? 0.0
            : requestedBackgroundAlpha
        transition.updateAlpha(node: separatorNode, alpha: separatorAlpha)
        if let glassBackgroundView {
            transition.updateAlpha(view: glassBackgroundView, alpha: resolvedAlpha)
        }
        transition.updateAlpha(view: liquidLensView, alpha: resolvedAlpha)
    }

    func setLegacyScrollEdgeChromeVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        guard theme.appearanceStyle == .legacy else { return }
        guard legacyScrollEdgeChromeVisible != visible else { return }
        legacyScrollEdgeChromeVisible = visible
        lastLegacyScrollEdgeTransitionWasAnimatedForTesting = transition.isAnimated
        lastLegacyScrollEdgeTransitionDurationForTesting = transition.duration
        applyLegacyScrollEdgeChromeVisibility(transition: transition)
    }

    internal var legacyBackgroundAlphaForTesting: CGFloat {
        backgroundView.alpha
    }

    internal var legacySeparatorAlphaForTesting: CGFloat {
        separatorNode.alpha
    }

    internal var legacySeparatorIsHiddenForTesting: Bool {
        separatorNode.view.isHidden
    }

    internal var legacyBackdropGroupingIdentifierForTesting: String? {
        backgroundView.backdropGroupingIdentifierForTesting
    }

    func setLegacyBackdropGroupingIdentifier(_ identifier: String?) {
        backgroundView.backdropGroupingIdentifier = identifier
    }

    private func applyLegacyScrollEdgeChromeVisibility(
        transition: ContainedViewLayoutTransition = .immediate
    ) {
        let attachedChromeAlpha: CGFloat = legacyScrollEdgeChromeVisible
            ? 1.0
            : 0.0
        let backgroundAlpha: CGFloat = legacyScrollEdgeChromeVisible
            || usesSharedLegacyAccessoryMaterial
            ? requestedBackgroundAlpha
            : 0.0
        backgroundView.updateBackgroundAlpha(
            backgroundAlpha,
            transition: transition
        )
        transition.updateAlpha(
            node: separatorNode,
            alpha: legacyScrollEdgeChromeVisible
                ? requestedBackgroundAlpha
                : 0.0
        )
        backgroundView.updateBottomAccessoryAttachedChromeAlpha(
            attachedChromeAlpha,
            transition: transition
        )
        if let glassBackgroundView {
            transition.updateAlpha(
                view: glassBackgroundView,
                alpha: legacyScrollEdgeChromeVisible
                    ? requestedBackgroundAlpha
                    : 0.0
            )
        }
    }

    private var usesSharedLegacyAccessoryMaterial: Bool {
        theme.appearanceStyle == .legacy
            && bottomAccessoryReservedHeight > 0.001
            && theme.enableBlur
    }

    private func layoutBackgroundMaterial() {
        let reservedHeight = max(0.0, bottomAccessoryReservedHeight)
        let hasAttachedLegacyAccessory = theme.appearanceStyle == .legacy
            && reservedHeight > 0.001
        let usesSharedMaterial = hasAttachedLegacyAccessory && theme.enableBlur
        if appliedSharedLegacyAccessoryMaterial != usesSharedMaterial {
            appliedSharedLegacyAccessoryMaterial = usesSharedMaterial
            if theme.appearanceStyle == .legacy {
                applyLegacyScrollEdgeChromeVisibility()
            }
        }
        separatorNode.view.isHidden = hasAttachedLegacyAccessory

        guard usesSharedMaterial else {
            backgroundView.frame = bounds
            backgroundView.update(size: bounds.size, transition: .immediate)
            backgroundView.clearBottomAccessoryMaterialMask()
            return
        }

        let size = CGSize(
            width: bounds.width,
            height: bounds.height + reservedHeight
        )
        let accessorySurfaceHeight = max(
            0.0,
            reservedHeight - LegacyLayout.accessoryBottomGap
        )
        backgroundView.frame = CGRect(
            x: 0.0,
            y: -reservedHeight,
            width: size.width,
            height: size.height
        )
        backgroundView.update(size: size, transition: .immediate)
        backgroundView.updateBottomAccessoryMaterialMask(
            size: size,
            tabBarMinY: reservedHeight,
            accessoryFrame: CGRect(
                x: LegacyLayout.accessorySideInset,
                y: 0.0,
                width: max(
                    0.0,
                    size.width - LegacyLayout.accessorySideInset * 2.0
                ),
                height: accessorySurfaceHeight
            ),
            accessoryCornerRadius: LegacyLayout.accessoryCornerRadius,
            attachedChromeAlpha: legacyScrollEdgeChromeVisible ? 1.0 : 0.0,
            transition: .immediate
        )
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        layoutBackgroundMaterial()

        let pixel = 1.0 / max(window?.screen.scale ?? traitCollection.displayScale, 1.0)
        separatorNode.frame = CGRect(x: 0, y: 0, width: bounds.width, height: pixel)

        // Scroll-edge frost: fade zone starts at the TOP of the tab bar
        // view (plus any accessory reservation) and ramps to solid below.
        // The top of the frost band is the boundary where scroll content
        // begins dissolving.
        //
        // When a screen installs a `bottomBarAccessory`, we extend the
        // frost band upward by `bottomAccessoryReservedHeight` so the
        // accessory pill (sitting just above our top edge) also rides on
        // the frost. That means the edge-effect view's frame reaches
        // beyond our own bounds — `clipsToBounds` stays false so the
        // overflow renders.
        if theme.style == .liquidGlass, hasVisibleEdgeEffect {
            let edgeEffectView = ensureEdgeEffectView()
            edgeEffectView.isHidden = false
            // Edge-effect frost band:
            //   • Expanded — covers the full tab bar height plus any
            //     reserved space ABOVE our top edge for a `bottomBarAccessory`
            //     so accessory + pill + scroll fade dissolve as one band.
            //   • Minimized — collapses to a tight band starting just
            //     above the 48pt circle row. The accessory has reflowed
            //     INTO that row (between the two circles), so it doesn't
            //     need its own reservation above us anymore — the band
            //     only needs to mask scroll content as it approaches the
            //     mini chrome.
            //
            // The band is offset DOWN and grown by `bandShift` so the
            // solid edge spills past the tab bar's bottom (covering the
            // gap between bounds and home-indicator area) and the fade
            // zone starts a touch lower — kills the visible
            // "просвет" the user reported between the chrome and the
            // device bottom.
            let edgeFrame: CGRect
            let fadeHeight: CGFloat
            // Empirical bleed — top edge of band moves DOWN by `bandShift`,
            // bottom edge moves DOWN by `2 * bandShift`. Net effect: the
            // band shifts down AND grows, exactly matching the user's
            // ask of "опустить вниз + увеличить пропорционально высоту".
            let allowsEdgeBleed = theme.glassEffectStyle == .regular
            edgeEffectView.clipsToBounds = !allowsEdgeBleed
            let bandShift: CGFloat = allowsEdgeBleed ? 12.0 : 0.0
            if isMinimized {
                let pillSize = Self.minimizedButtonSize
                let pillTop = bounds.height - effectiveBottomInset - pillSize
                let extraTop: CGFloat = 12.0
                let edgeTop = max(0.0, pillTop - extraTop)
                edgeFrame = CGRect(
                    x: 0.0,
                    y: edgeTop + bandShift,
                    width: bounds.width,
                    height: bounds.height - edgeTop + bandShift
                )
                fadeHeight = min(36.0, edgeFrame.height * 0.45)
            } else {
                let reservedAbove = allowsEdgeBleed ? max(0, bottomAccessoryReservedHeight) : 0.0
                edgeFrame = CGRect(
                    x: 0.0,
                    y: -reservedAbove + bandShift,
                    width: bounds.width,
                    height: bounds.height + reservedAbove + bandShift
                )
                fadeHeight = min(48.0, edgeFrame.height * 0.4)
            }
            edgeEffectView.frame = edgeFrame
            edgeEffectView.update(
                content: theme.edgeEffectTintColor ?? theme.tabBarBackgroundColor,
                blur: true,
                alpha: theme.edgeEffectAlpha,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom,
                edgeSize: allowsEdgeBleed ? fadeHeight : 0.0,
                blurRadiusAtEdge: theme.edgeEffectBlurRadiusAtEdge,
                blurRadiusAtFade: allowsEdgeBleed ? 0.0 : theme.edgeEffectBlurRadiusAtEdge,
                solidBlur: !allowsEdgeBleed,
                minimumFadeAlpha: allowsEdgeBleed ? 0.0 : 0.04,
                transition: .immediate
            )
        } else if let edgeEffectView {
            edgeEffectView.isHidden = true
            edgeEffectView.update(
                content: .clear,
                blur: false,
                alpha: 0.0,
                rect: CGRect(origin: .zero, size: edgeEffectView.bounds.size),
                edge: .bottom,
                edgeSize: 0.0,
                blurRadiusAtEdge: 0.0,
                blurRadiusAtFade: 0.0,
                transition: .immediate
            )
        }

        layoutGlassBackground()
        if theme.style == .liquidGlass {
            // The container effect is a transparent grouping field, not the
            // visible pill. Keeping its bounds stable prevents UIKit from
            // unregistering/re-registering either child glass effect while a
            // spring is interrupted or reversed.
            tabBarGlassContainer.frame = bounds
            tabBarGlassContainer.update(
                size: bounds.size,
                isDark: isEffectivelyDark,
                transition: .immediate
            )
        }
        layoutItemViews()

        if isSearchActive {
            positionSearchViewsExpanded()
        }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard theme.style == .liquidGlass,
              let searchItemView,
              searchItemView.isUserInteractionEnabled,
              !searchItemView.isHidden,
              searchItemView.alpha > 0.01,
              searchItemView.layer.animationKeys()?.isEmpty == false,
              let presentation = searchItemView.layer.presentation() else {
            return super.hitTest(point, with: event)
        }

        let sharedContent = tabBarGlassContainer.contentView
        let sharedPoint = sharedContent.convert(point, from: self)
        let presentationContainsPoint = presentation.frame.contains(sharedPoint)
        let modelContainsPoint = searchItemView.frame.contains(sharedPoint)

        if presentationContainsPoint {
            if modelContainsPoint {
                // Normal descent reaches GlassBackgroundView, preserving the
                // native interactive-glass press effect.
                return super.hitTest(point, with: event)
            }
            // The visible moving control is outside its already-committed
            // model endpoint. Keep taps on its stable action owner; the next
            // settled frame resumes normal native-effect hit descent.
            return searchItemView
        }

        if modelContainsPoint {
            // Do not expose the invisible endpoint ahead of the compositor.
            // The moving pill may currently occupy the same point, so offer it
            // the touch before falling back to this view as a harmless sink.
            let pillPoint = pillGeometryHost.convert(sharedPoint, from: sharedContent)
            return pillGeometryHost.hitTest(pillPoint, with: event) ?? self
        }

        return super.hitTest(point, with: event)
    }

    /// Effective dark flag. The default theme follows the host traits, while
    /// a per-screen appearance override can explicitly pin either light or
    /// dark without being undone by a parent controller's interface style.
    private var isEffectivelyDark: Bool {
        if theme.isDarkAppearanceExplicit {
            return theme.isDark
        }
        return traitCollection.userInterfaceStyle == .dark
    }

    private func applyEffectiveGlassAppearanceOverride() {
        let isDark = isEffectivelyDark
        let interfaceStyle: UIUserInterfaceStyle = isDark ? .dark : .light
        tabBarGlassContainer.isDarkOverride = isDark
        tabBarGlassContainer.overrideUserInterfaceStyle = interfaceStyle
        liquidLensView.isDarkAppearance = isDark
        glassBackgroundView?.isDarkOverride = isDark
        searchItemView?.isDarkAppearance = isDark
        searchCapsule?.isDarkOverride = isDark
        searchCloseButton?.isDarkAppearance = isDark
    }

    private func refreshSemanticChromeForCurrentTraits() {
        applyEffectiveGlassAppearanceOverride()
        let colorTraits = chromeColorTraitCollection
        itemViews.forEach { $0.refreshAppearance(colorTraitCollection: colorTraits) }
        selectedItemViews.forEach { $0.refreshAppearance(colorTraitCollection: colorTraits) }
        expandedSearchItemView?.refreshAppearance(colorTraitCollection: colorTraits)
        legacySearchItemView?.refreshAppearance(colorTraitCollection: colorTraits)
        minimizedIconNode?.tintColor = resolvedChromeColor(theme.tabBarSelectedIconColor)
        liquidLensView.glassTintColor = tabBarChromeTint
        searchItemView?.contentTintColor = resolvedChromeColor(theme.tabBarIconColor)
        searchItemView?.glassTintColor = tabBarChromeTint
        searchItemView?.glassStyle = chromeGlassAppearance.viewStyle
        searchItemView?.isDarkAppearance = isEffectivelyDark
        searchCloseButton?.contentTintColor = resolvedChromeColor(.label)
        searchCloseButton?.glassTintColor = tabBarChromeTint
        searchCloseButton?.glassStyle = chromeGlassAppearance.viewStyle
        searchCapsule?.updateStyle(chromeGlassAppearance.viewStyle)
        searchTextField?.textColor = resolvedChromeColor(.label)
        (searchTextField?.leftView as? AetherSearchIconLeftView)?.updateTintColor(
            resolvedChromeColor(.secondaryLabel)
        )
    }

    /// Keeps Legacy's inactive icon and label content in a real UIKit
    /// vibrancy renderer paired with the tab bar's current material. Active
    /// content stays outside the effect so it retains the accent colour.
    private func refreshLegacyTabItemVibrancy() {
        let usesLegacyVibrancy = theme.appearanceStyle == .legacy
        for itemView in itemViews {
            itemView.setLegacyVibrancyEffect(
                usesLegacyVibrancy
                    ? backgroundView.makeVibrancyEffect(style: .secondaryLabel)
                    : nil
            )
        }
        legacySearchItemView?.setLegacyVibrancyEffect(
            usesLegacyVibrancy
                ? backgroundView.makeVibrancyEffect(style: .secondaryLabel)
                : nil
        )
    }

    private func layoutGlassBackground() {
        guard let glassBackgroundView else {
            return
        }
        glassBackgroundView.frame = bounds
        glassBackgroundView.update(
            size: bounds.size,
            cornerRadius: 0.0,
            isDark: isEffectivelyDark,
            tintColor: tabBarChromeTint,
            isInteractive: false,
            isVisible: true,
            transition: .immediate
        )
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            refreshSemanticChromeForCurrentTraits()
            setNeedsLayout()
        }
        if let previousTraitCollection,
           traitCollection.preferredContentSizeCategory != previousTraitCollection.preferredContentSizeCategory {
            rebuildItemViews()
            setNeedsLayout()
        }
    }

    private func layoutItemViews() {
        let regularCount = itemViews.count
        if theme.style == .liquidGlass {
            guard regularCount > 0 else { return }
            layoutLiquidGlassItems(count: regularCount)
            return
        }

        liquidLensView.isHidden = true
        let count = regularCount + (legacySearchItemView == nil ? 0 : 1)
        guard count > 0 else { return }
        for (index, itemView) in itemViews.enumerated() {
            itemView.frame = LegacyLayout.itemFrame(index: index, count: count, width: bounds.width)
        }
        legacySearchItemView?.frame = LegacyLayout.itemFrame(
            index: count - 1,
            count: count,
            width: bounds.width
        )
    }

    private func rebuildSearchItemView() {
        searchItemView?.removeFromSuperview()
        searchItemView = nil
        expandedSearchItemView?.removeFromSuperview()
        expandedSearchItemView = nil
        legacySearchItemView?.removeFromSuperview()
        legacySearchItemView = nil

        guard let item = searchItem else {
            setNeedsLayout()
            return
        }

        if theme.appearanceStyle == .legacy {
            let legacyItem = AetherTabBarItem(
                title: item.title ?? "Search",
                image: item.image,
                selectedImage: item.selectedImage
            )
            let itemView = TabBarItemView(
                item: legacyItem,
                theme: theme,
                selected: false,
                colorTraitCollection: chromeColorTraitCollection
            )
            let tap = UITapGestureRecognizer(target: self, action: #selector(legacySearchItemTapped(_:)))
            tap.delegate = self
            itemView.addGestureRecognizer(tap)
            addSubview(itemView)
            legacySearchItemView = itemView
            refreshLegacyTabItemVibrancy()
            setNeedsLayout()
            return
        }

        let expandedItem = AetherTabBarItem(
            title: item.title ?? "Search",
            image: item.image ?? item.selectedImage,
            selectedImage: item.selectedImage ?? item.image
        )
        let expandedView = TabBarItemView(
            item: expandedItem,
            theme: theme,
            selected: false,
            colorTraitCollection: chromeColorTraitCollection
        )
        expandedView.alpha = isMinimized ? 0.0 : 1.0
        // Pixel-only expanded endpoint. Search's stable GlassBarButton below
        // it owns touch, native press feedback, and accessibility throughout
        // the morph, so there is no responder/AX handoff at completion.
        expandedView.isUserInteractionEnabled = false
        expandedView.isAccessibilityElement = false
        expandedView.accessibilityElementsHidden = true
        expandedView.accessibilityIdentifier = "aether.tabbar.search.expandedVisual"
        expandedView.hidesIconForSearchMorph = true
        addSubview(expandedView)
        expandedSearchItemView = expandedView

        let button = GlassBarButtonView(
            icon: item.image ?? item.selectedImage,
            title: nil,
            state: .glass,
            appearanceStyle: theme.appearanceStyle
        )
        button.glassStyle = chromeGlassAppearance.viewStyle
        button.contentTintColor = resolvedChromeColor(theme.tabBarIconColor)
        button.glassTintColor = tabBarChromeTint
        button.isDarkAppearance = isEffectivelyDark
        button.action = { [weak item] _ in item?.action?() }
        button.alpha = 1.0
        button.chromeMorphKeepsContentIndependentOfMaterial = !usesNativeSearchMerge
        button.chromeMorphMaterialAlpha = usesNativeSearchMerge
            ? 1.0
            : (isMinimized ? 1.0 : 0.0)
        button.chromeMorphContentAlpha = 1.0
        button.isUserInteractionEnabled = !isSearchActive
        button.isAccessibilityElement = true
        button.accessibilityIdentifier = "aether.tabbar.search.moving"
        button.accessibilityLabel = expandedItem.title
        button.accessibilityTraits = .button
        button.accessibilityElementsHidden = isSearchActive
        // A sibling of pillGeometryHost inside the same full-row container:
        // native UIKit now sees both UIGlassEffects under one
        // UIGlassContainerEffect and performs the optical union itself.
        tabBarGlassContainer.contentView.addSubview(button)
        searchItemView = button
        setNeedsLayout()
    }

    @objc private func legacySearchItemTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        searchItem?.action?()
    }

    private func updateScrollMinimizeArmingScale(
        progress: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        let clampedProgress = max(0.0, min(1.0, progress))
        let scale = 1.0
            - (1.0 - Self.scrollMinimizeArmedScale) * clampedProgress
        let target = CATransform3DMakeScale(scale, scale, 1.0)
        let candidateViews: [UIView?] = [
            pillGeometryHost,
            searchItemView,
            expandedSearchItemView
        ]
        let views = candidateViews.compactMap { $0 }

        for view in views {
            let source = view.layer.presentation()?.sublayerTransform
                ?? view.layer.sublayerTransform
            view.layer.removeAnimation(forKey: Self.scrollMinimizeArmedScaleAnimationKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer.sublayerTransform = target
            CATransaction.commit()

            guard case let .animated(duration, curve) = transition,
                  duration > 0.0 else {
                continue
            }
            let animation: CABasicAnimation
            switch curve {
            case let .customSpring(damping, initialVelocity):
                let spring = CASpringAnimation(keyPath: "sublayerTransform")
                spring.mass = 1.0
                spring.stiffness = 120.0
                spring.damping = 2.0 * Double(damping) * sqrt(spring.stiffness * spring.mass)
                spring.initialVelocity = Double(initialVelocity)
                animation = spring
            case .spring:
                let spring = CASpringAnimation(keyPath: "sublayerTransform")
                spring.mass = 1.0
                spring.stiffness = 120.0
                spring.damping = 2.0
                    * Double(AetherMotion.navigation.dampingRatio)
                    * sqrt(spring.stiffness * spring.mass)
                spring.initialVelocity = Double(AetherMotion.navigation.initialVelocity)
                animation = spring
            default:
                let basic = CABasicAnimation(keyPath: "sublayerTransform")
                basic.timingFunction = curve.mediaTimingFunction()
                animation = basic
            }
            animation.fromValue = NSValue(caTransform3D: source)
            animation.toValue = NSValue(caTransform3D: target)
            animation.duration = duration
            animation.isRemovedOnCompletion = true
            view.layer.add(
                animation,
                forKey: Self.scrollMinimizeArmedScaleAnimationKey
            )
        }
    }

    private func layoutLiquidGlassItems(count: Int) {
        liquidLensView.isHidden = false

        // Single-use morph transition. When set (by `setMinimized`), every
        // inner frame and the glass cornerRadius update animate through it,
        // so the pill, lens, icon, and search circle morph together. After
        // this layout pass it's cleared, so subsequent layouts (rotation,
        // selection change) snap with `.immediate` instead of triggering a
        // stale animation.
        let activeTransition: ContainedViewLayoutTransition = pendingMinimizeTransition
            ?? pendingScrollMinimizeArmingTransition
            ?? .immediate
        pendingMinimizeTransition = nil
        pendingScrollMinimizeArmingTransition = nil
        let selectionTransition = pendingLensSelectionTransition
        pendingLensSelectionTransition = nil

        let minimizedSideInset = theme.minimizedSideInset
        let innerPadding = theme.innerPadding
        let bottomInset = effectiveBottomInset
        let activeArmingProgress = isScrollMinimizeArmed && !isMinimized
            ? scrollMinimizeArmingProgress
            : 0.0
        let armingInset = Self.scrollMinimizeArmedHorizontalInset
            * activeArmingProgress
        let expandedLayout = expandedChromeLayout(
            in: bounds.size,
            itemCount: count,
            horizontalInset: armingInset
        )
        updateScrollMinimizeArmingScale(
            progress: activeArmingProgress,
            transition: activeTransition
        )

        // The expanded representation remains parked at its final slot while
        // the moving Search control travels. It is a non-interactive pixel
        // overlay used only for the icon+label endpoint handoff.
        if let expandedSearchItemView, let searchFrame = expandedLayout.searchFrame {
            activeTransition.updateFrame(view: expandedSearchItemView, frame: searchFrame)
        }

        // Minimized layout: pill collapses to a 48×48 active-tab circle on
        // the leading edge, search tab item mirrors it on the trailing
        // edge, and the band between them is reserved for the
        // `bottomBarAccessory` (which the controller reflows there).
        if isMinimized {
            let pillSize = Self.minimizedButtonSize
            let pillY = bounds.height - bottomInset - pillSize
            let containerFrame = CGRect(x: minimizedSideInset, y: pillY, width: pillSize, height: pillSize)
            activeTransition.updateFrame(view: pillGeometryHost, frame: containerFrame)

            // Lens still fills the container so its stretchy press
            // feedback lines up with the circle. `isCollapsed: true`
            // drops the lens's resting tint layer — without this the
            // active-tab circle reads as a heavier glass than the
            // search tab item / accessory pill that sit beside it.
            activeTransition.updateFrame(view: liquidLensView, frame: CGRect(origin: .zero, size: containerFrame.size))
            liquidLensView.update(
                size: containerFrame.size,
                selectionOrigin: .zero,
                selectionSize: containerFrame.size,
                inset: 0.0,
                isDark: isEffectivelyDark,
                isLifted: false,
                isCollapsed: true,
                transition: activeTransition
            )

            // Active-tab icon centered inside the circle. 10pt inset
            // gives a 28×28 hit area for the SF symbol and visually
            // matches the expanded item icon's weight in 48pt chrome.
            if let icon = minimizedIconNode {
                let iconInset: CGFloat = 10
                let iconFrame = CGRect(origin: .zero, size: containerFrame.size).insetBy(dx: iconInset, dy: iconInset)
                activeTransition.updateFrame(node: icon, frame: iconFrame)
            }

            // Tab item views ride along inside the lens; keep them at
            // their normal frames so re-expand finds them in place, but
            // they're invisible while the lens alpha is 0. No transition
            // needed — they're not visible during the morph.
            let itemHeight = theme.pillHeight
            let pillWidthForItems = expandedLayout.pillFrame.width
            let tabAreaWidth = pillWidthForItems - innerPadding * 2.0
            let slotCount = count + (searchItem == nil ? 0 : 1)
            let itemWidth = max(1.0, tabAreaWidth / CGFloat(max(1, slotCount)))
            for (index, itemView) in itemViews.enumerated() {
                itemView.frame = CGRect(x: innerPadding + CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: itemHeight)
                if index < selectedItemViews.count {
                    selectedItemViews[index].frame = itemView.frame
                }
            }

            // Search tab item shrunk to 48×48 on the trailing edge.
            if let searchButton = searchItemView {
                let searchFrame = CGRect(
                    x: bounds.width - minimizedSideInset - pillSize,
                    y: pillY,
                    width: pillSize,
                    height: pillSize
                )
                activeTransition.updateFrame(view: searchButton, frame: searchFrame)
                searchButton.updateChromeMorphIconFrame(
                    CGRect(origin: .zero, size: searchFrame.size),
                    transition: activeTransition
                )
            }

            return
        }

        // Expanded layout — one pill with an optional final Search slot.
        let lensSize = expandedLayout.pillFrame.size

        // The material-less Search overlay remains a sibling for independent
        // press handling, but its pixels sit inside this single glass pill.
        let containerFrame = expandedLayout.pillFrame
        activeTransition.updateFrame(view: pillGeometryHost, frame: containerFrame)

        // Reset minimized icon frame so when the bar morphs back to
        // minimized the icon doesn't briefly appear at full pill size.
        if let icon = minimizedIconNode {
            let iconInset: CGFloat = 10
            let iconBox = CGRect(x: 0, y: 0, width: Self.minimizedButtonSize, height: Self.minimizedButtonSize).insetBy(dx: iconInset, dy: iconInset)
            activeTransition.updateFrame(node: icon, frame: iconBox)
        }

        // Lens covers the whole unified pill.
        activeTransition.updateFrame(view: liquidLensView, frame: CGRect(origin: .zero, size: lensSize))

        // Keep the dormant minimized material at the Search slot while
        // expanded; it is alpha-zero, so the next detach begins from the
        // correct model geometry without reparenting a live glass effect.
        if let searchButton = searchItemView, let searchFrame = expandedLayout.searchFrame {
            activeTransition.updateFrame(view: searchButton, frame: searchFrame)
            let iconFrame = expandedSearchItemView?.liquidIconFrame(
                in: CGRect(origin: .zero, size: searchFrame.size)
            ) ?? CGRect(origin: .zero, size: searchFrame.size)
            searchButton.updateChromeMorphIconFrame(
                iconFrame,
                transition: activeTransition
            )
        }
        // Tab items fill the pill width with inner side padding.
        let tabAreaWidth = lensSize.width - innerPadding * 2.0
        let slotCount = count + (searchItem == nil ? 0 : 1)
        let itemWidth = max(1.0, tabAreaWidth / CGFloat(max(1, slotCount)))
        // `LiquidLensView` applies its own 4pt inset below. Expanding the
        // selection frame by the pill padding keeps the rendered lens at the
        // same 4pt visual edge it had before item-count sizing introduced a
        // wider 10pt item-area padding. Custom themes that still use the old
        // 2pt padding retain the previous 4pt expansion exactly.
        let selectionExpansion = max(4.0, innerPadding)
        var selectionFrame = CGRect(x: 0.0, y: 0.0, width: max(56.0, itemWidth), height: lensSize.height)

        for (index, itemView) in itemViews.enumerated() {
            let itemFrame = CGRect(x: innerPadding + CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: lensSize.height)
            itemView.frame = itemFrame
            if index < selectedItemViews.count {
                selectedItemViews[index].frame = itemFrame
            }
            if index == selectedIndex {
                selectionFrame = itemFrame.insetBy(dx: -selectionExpansion, dy: 0.0)
            }
        }

        // Drag-to-select: override the lens origin to follow the user's finger.
        // Clamped to the lens bounds so the lens can't leave the pill.
        if let drag = selectionGestureState {
            let regularTabsMaxX = innerPadding + CGFloat(count) * itemWidth
            let maxOriginX = min(
                lensSize.width - selectionFrame.width,
                regularTabsMaxX + selectionExpansion - selectionFrame.width
            )
            let targetX = max(
                -selectionExpansion,
                min(maxOriginX, drag.currentX - selectionExpansion)
            )
            selectionFrame.origin.x = targetX
        }

        selectionFrame.origin.x = max(0.0, min(selectionFrame.origin.x, lensSize.width - selectionFrame.width))

        // iOS 26 native "liquid" lift: while the user is actively dragging
        // the lens, forward `isLifted = true` to the underlying
        // `_UILiquidLensView`. This triggers the system's liquid morph —
        // the selection capsule elevates/stretches out of the pill as the
        // finger moves, matching the Figma / iOS 26 reference.
        let isDraggingLens = selectionGestureState != nil
        let lensTransition: ContainedViewLayoutTransition
        if let selectionTransition {
            lensTransition = selectionTransition
        } else if isDraggingLens {
            // Finger motion is the clock while lifted. Animating every sample
            // makes the lens trail behind and queues stale private-SPI updates.
            lensTransition = .immediate
        } else if activeTransition.isAnimated {
            lensTransition = activeTransition
        } else {
            lensTransition = .immediate
        }
        liquidLensView.update(
            size: lensSize,
            selectionOrigin: selectionFrame.origin,
            selectionSize: selectionFrame.size,
            inset: 4.0,
            isDark: isEffectivelyDark,
            isLifted: isDraggingLens,
            transition: lensTransition
        )
        // Lens already positioned at (0, 0, lensSize) inside the container.
    }

    // MARK: - Items

    private func rebuildItemViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        selectedItemViews.forEach { $0.removeFromSuperview() }
        itemViews = []
        selectedItemViews = []

        for (index, item) in items.enumerated() {
            let itemView = TabBarItemView(
                item: item,
                theme: theme,
                selected: theme.style == .legacy && index == selectedIndex,
                colorTraitCollection: chromeColorTraitCollection
            )
            itemView.tag = index

            let tap = UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:)))
            tap.delegate = self
            itemView.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(itemLongPressed(_:)))
            longPress.delegate = self
            itemView.addGestureRecognizer(longPress)

            let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(itemSwiped(_:)))
            swipeLeft.direction = .left
            swipeLeft.delegate = self
            itemView.addGestureRecognizer(swipeLeft)

            let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(itemSwiped(_:)))
            swipeRight.direction = .right
            swipeRight.delegate = self
            itemView.addGestureRecognizer(swipeRight)

            let selectedItemView = TabBarItemView(
                item: item,
                theme: theme,
                selected: true,
                colorTraitCollection: chromeColorTraitCollection
            )
            selectedItemView.tag = index
            selectedItemView.isUserInteractionEnabled = false

            if theme.style == .liquidGlass {
                liquidLensView.contentView.addSubview(itemView)
                liquidLensView.selectedContentView.addSubview(selectedItemView)
            } else {
                addSubview(itemView)
            }
            itemViews.append(itemView)
            selectedItemViews.append(selectedItemView)
        }

        refreshLegacyTabItemVibrancy()
        setNeedsLayout()
    }

    private func updateSelection(animated: Bool) {
        for (index, itemView) in itemViews.enumerated() {
            let isSelected = theme.style == .legacy && index == selectedIndex
            if animated {
                UIView.animate(withDuration: AetherMotion.tabBarSelection.duration * 0.60) {
                    itemView.isSelected = isSelected
                    if index < self.selectedItemViews.count {
                        self.selectedItemViews[index].isSelected = true
                    }
                }
            } else {
                itemView.isSelected = isSelected
                if index < selectedItemViews.count {
                    selectedItemViews[index].isSelected = true
                }
            }
        }
        // Refresh the collapsed-pill icon when the active tab changes —
        // the minimized circle shows whichever tab is currently selected.
        if let icon = minimizedIconNode {
            let newImage = activeTabIcon()?.withRenderingMode(.alwaysTemplate)
            if animated, isMinimized {
                UIView.transition(
                    with: icon.view,
                    duration: AetherMotion.tabBarSelection.duration * 0.60,
                    options: [.transitionCrossDissolve, .beginFromCurrentState]
                ) {
                    icon.image = newImage
                    icon.tintColor = self.resolvedChromeColor(self.theme.tabBarSelectedIconColor)
                }
            } else {
                icon.image = newImage
                icon.tintColor = resolvedChromeColor(theme.tabBarSelectedIconColor)
            }
        }
        setNeedsLayout()
    }

    // MARK: - Actions

    private func activateItem(at index: Int) {
        guard index < items.count else { return }
        guard interactionsEnabled, items[index].isEnabled else {
            disabledPressed?()
            return
        }

        let timestamp = CACurrentMediaTime()
        let isDoubleTap = lastTapIndex == index && (timestamp - lastTapTimestamp) < 0.35
        lastTapIndex = index
        lastTapTimestamp = timestamp

        if isDoubleTap, itemHasDoubleTapAction?(index) == true {
            tabDoubleTapped?(index)
            return
        }

        selectedIndex = index
        tabSelected?(index)
    }

    private func index(at point: CGPoint) -> Int? {
        for (index, itemView) in itemViews.enumerated() {
            let frame = convert(itemView.bounds, from: itemView)
            if frame.contains(point) {
                return index
            }
        }
        return nil
    }

    @objc private func lensPanned(_ recognizer: TabSelectionRecognizer) {
        guard theme.style == .liquidGlass, !items.isEmpty else { return }

        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: liquidLensView)
            let translation = recognizer.translation(in: liquidLensView).x
            let initialX = location.x - translation
            guard let idx = indexInLens(x: initialX) else { return }
            let contentOriginX = min(
                max(0.0, theme.innerPadding),
                liquidLensView.bounds.width / 2.0
            )
            let itemAreaWidth = max(0.0, liquidLensView.bounds.width - contentOriginX * 2.0)
            let slotCount = items.count + (searchItem == nil ? 0 : 1)
            let itemW = max(1.0, itemAreaWidth / CGFloat(max(1, slotCount)))
            let currentIndex = indexInLens(x: location.x) ?? idx
            selectionGestureState = SelectionGestureState(
                startIndex: idx,
                currentIndex: currentIndex,
                currentX: contentOriginX + CGFloat(idx) * itemW + translation,
                itemWidth: itemW,
                contentOriginX: contentOriginX
            )
            pendingLensSelectionTransition = .animated(
                duration: AetherMotion.tabBarPress.press.duration,
                curve: .customSpring(
                    damping: AetherMotion.tabBarPress.press.dampingRatio,
                    initialVelocity: AetherMotion.tabBarPress.press.initialVelocity
                )
            )
            setNeedsLayout()
            layoutIfNeeded()
        case .changed:
            guard var state = selectionGestureState else { return }
            let translation = recognizer.translation(in: liquidLensView).x
            state.currentX = state.contentOriginX
                + CGFloat(state.startIndex) * state.itemWidth
                + translation
            let location = recognizer.location(in: liquidLensView)
            if let idx = indexInLens(x: location.x) {
                state.currentIndex = idx
            }
            selectionGestureState = state
            setNeedsLayout()
            layoutIfNeeded()
        case .ended:
            if let state = selectionGestureState, items.indices.contains(state.currentIndex) {
                let velocityX = recognizer.velocity(in: liquidLensView).x
                let projectedOrigin = state.currentX + velocityX * 0.10
                let projectedIndex = Int((
                    (projectedOrigin - state.contentOriginX) / max(1.0, state.itemWidth)
                ).rounded())
                let newIndex = min(items.count - 1, max(0, projectedIndex))
                pendingLensSelectionTransition = Self.lensSettleTransition(
                    velocityX: velocityX,
                    itemWidth: state.itemWidth
                )
                selectionGestureState = nil
                if newIndex != selectedIndex {
                    selectedIndex = newIndex
                    tabSelected?(newIndex)
                } else {
                    setNeedsLayout()
                    layoutIfNeeded()
                }
            } else {
                selectionGestureState = nil
                setNeedsLayout()
                layoutIfNeeded()
            }
        case .cancelled, .failed:
            pendingLensSelectionTransition = .animated(
                duration: AetherMotion.tabBarSelection.duration,
                curve: .customSpring(
                    damping: AetherMotion.tabBarSelection.dampingRatio,
                    initialVelocity: AetherMotion.tabBarSelection.initialVelocity
                )
            )
            selectionGestureState = nil
            setNeedsLayout()
            layoutIfNeeded()
        default:
            break
        }
    }

    private func indexInLens(x: CGFloat) -> Int? {
        guard !items.isEmpty else { return nil }
        let contentOriginX = min(
            max(0.0, theme.innerPadding),
            liquidLensView.bounds.width / 2.0
        )
        let itemAreaWidth = max(0.0, liquidLensView.bounds.width - contentOriginX * 2.0)
        let slotCount = items.count + (searchItem == nil ? 0 : 1)
        let itemW = max(1.0, itemAreaWidth / CGFloat(max(1, slotCount)))
        let contentX = max(0.0, min(itemAreaWidth, x - contentOriginX))
        let idx = Int((contentX / itemW).rounded(.down))
        guard idx >= 0, idx < items.count else { return nil }
        return idx
    }

    private static func lensSettleTransition(
        velocityX: CGFloat,
        itemWidth: CGFloat
    ) -> ContainedViewLayoutTransition {
        let normalizedVelocity = min(2.4, abs(velocityX) / max(240.0, itemWidth * 6.0))
        let duration = max(
            0.38,
            AetherMotion.tabBarSelection.duration - Double(normalizedVelocity) * 0.055
        )
        return .animated(
            duration: duration,
            curve: .customSpring(
                damping: AetherMotion.tabBarSelection.dampingRatio,
                initialVelocity: normalizedVelocity
            )
        )
    }

    @objc private func lensTapped(_ recognizer: UITapGestureRecognizer) {
        guard theme.style == .liquidGlass, recognizer.state == .ended else {
            return
        }
        // In minimized state the lens is the collapsed pill itself —
        // tapping it should expand the bar back, or close search if
        // search is currently expanded from the trailing button.
        if isMinimized || isSearchActive {
            handleMinimizedActiveTabTap()
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        activateItem(at: index)
    }

    @objc private func lensLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard theme.style == .liquidGlass, recognizer.state == .began else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        tabLongPressed?(index, itemViews[index], recognizer)
    }

    @objc private func lensSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard theme.style == .liquidGlass else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        let direction: TabBarItemSwipeDirection = recognizer.direction == .left ? .left : .right
        tabSwipeAction?(index, direction)
    }

    @objc private func itemTapped(_ recognizer: UITapGestureRecognizer) {
        guard let itemView = recognizer.view else { return }
        let index = itemView.tag
        activateItem(at: index)
    }

    @objc private func itemLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let itemView = recognizer.view else { return }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        tabLongPressed?(itemView.tag, itemView, recognizer)
    }

    @objc private func itemSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard let itemView = recognizer.view else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        let direction: TabBarItemSwipeDirection = recognizer.direction == .left ? .left : .right
        tabSwipeAction?(itemView.tag, direction)
    }

    // MARK: - Public

    public func frameForTab(at index: Int) -> CGRect? {
        guard index < itemViews.count else { return nil }
        return convert(itemViews[index].bounds, from: itemViews[index])
    }

    /// Frame of the pill (selection capsule) in this view's coordinate
    /// space. Consumers — e.g. a floating toolbar that wants to sit just
    /// above the pill — should read this rather than hardcoding the
    /// pill's theme constants, otherwise they'll drift whenever the theme
    /// changes `pillHeight` / `bottomInset`.
    public var pillFrame: CGRect {
        if theme.style == .liquidGlass {
            return pillGeometryHost.frame
        }
        // Legacy style: items span the full width near the top. Use the
        // item row as the "pill" for anchoring purposes.
        if let first = itemViews.first {
            return first.frame.union(legacySearchItemView?.frame ?? itemViews.last?.frame ?? first.frame)
        }
        return legacySearchItemView?.frame ?? .zero
    }

    /// Actual presentation progress of the morphing pill. The controller uses
    /// this as the authoritative compact clock so its accessory and public
    /// callback follow UIKit's duration-fitted spring exactly, including frame
    /// drops and begin-from-current-state reversals.
    internal var minimizationPresentationProgress: CGFloat? {
        guard theme.appearanceStyle.usesLiquidGlass,
              let presentationFrame = pillGeometryHost.layer.presentation()?.frame else {
            return nil
        }
        // The progress denominator stays canonical while the scroll preview
        // applies its transient 4pt inset. Otherwise clearing the preview at
        // commit changes the denominator underneath the display-link and
        // creates a small forward jump before the spring even starts.
        let expandedFrame = expandedChromeLayout(
            in: bounds.size,
            itemCount: items.count,
            horizontalInset: 0.0
        ).pillFrame
        let minimizedFrame = computePillFrame(in: bounds.size, minimized: true)
        let widthDelta = minimizedFrame.width - expandedFrame.width
        guard abs(widthDelta) > 0.5 else { return nil }
        let progress = (presentationFrame.width - expandedFrame.width) / widthDelta
        return progress.isFinite ? progress : nil
    }

    /// Height the controller should reserve for the tab bar above the bottom
    /// safe area. Includes the 60pt pill, bottom gap, and top edge-effect zone.
    public class var defaultHeight: CGFloat {
        return 95.0
    }
}

// MARK: - TabBarItemView

private final class TabBarItemView: UIView {
    private let imageNode: ASImageNode
    private let titleNode: ASTextNode
    private let badgeView: NavigationBarBadgeView
    private let legacyVibrancyView: UIVisualEffectView
    private var legacyVibrancyEnabled = false
    private var item: AetherTabBarItem
    private var theme: TabBarView.Theme
    private var colorTraitCollectionOverride: UITraitCollection?
    private var titleFont = UIFont.aetherScaledSystemFont(ofSize: 10.0, weight: .medium, maximumPointSize: 11.5)

    var hidesIconForSearchMorph = false {
        didSet {
            imageNode.alpha = hidesIconForSearchMorph ? 0.0 : 1.0
        }
    }

    func liquidIconFrame(in bounds: CGRect) -> CGRect {
        let contentInset: CGFloat = 8.0
        let textHeight = min(22.0, ceil(titleFont.lineHeight))
        let imageSize = min(
            36.0,
            max(24.0, bounds.height - contentInset * 2.0 - textHeight)
        )
        let totalHeight = imageSize + textHeight
        let availableHeight = max(totalHeight, bounds.height - contentInset * 2.0)
        let topY = contentInset + floor((availableHeight - totalHeight) / 2.0)
        return CGRect(
            x: (bounds.width - imageSize) / 2.0,
            y: topY,
            width: imageSize,
            height: imageSize
        )
    }

    var isSelected: Bool = false {
        didSet {
            updateLegacyContentHost()
            updateAppearance()
        }
    }

    init(
        item: AetherTabBarItem,
        theme: TabBarView.Theme,
        selected: Bool,
        colorTraitCollection: UITraitCollection? = nil
    ) {
        self.item = item
        self.theme = theme
        self.isSelected = selected
        self.imageNode = ASImageNode()
        self.titleNode = ASTextNode()
        self.badgeView = NavigationBarBadgeView()
        self.legacyVibrancyView = UIVisualEffectView(effect: nil)
        self.colorTraitCollectionOverride = colorTraitCollection

        super.init(frame: .zero)

        legacyVibrancyView.isUserInteractionEnabled = false
        legacyVibrancyView.backgroundColor = .clear
        addSubview(legacyVibrancyView)

        imageNode.contentMode = .center
        imageNode.view.isUserInteractionEnabled = false
        addSubview(imageNode.view)

        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.view.isUserInteractionEnabled = false
        addSubview(titleNode.view)

        addSubview(badgeView)
        if let badge = item.badgeValue, !badge.isEmpty {
            badgeView.text = badge
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Texture requires loaded nodes to leave the visible hierarchy before
        // they are released. UIKit can tear down a still-visible UIWindow
        // without delivering that transition to nested node-backed views.
        imageNode.view.removeFromSuperview()
        titleNode.view.removeFromSuperview()
        badgeView.removeFromSuperview()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateAppearance()
        }
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateAppearance()
            setNeedsLayout()
        }
    }

    func updateTheme(_ theme: TabBarView.Theme, colorTraitCollection: UITraitCollection) {
        self.theme = theme
        self.colorTraitCollectionOverride = colorTraitCollection
        updateAppearance()
        setNeedsLayout()
    }

    func refreshAppearance(colorTraitCollection: UITraitCollection) {
        colorTraitCollectionOverride = colorTraitCollection
        updateAppearance()
    }

    func setLegacyVibrancyEffect(_ effect: UIVibrancyEffect?) {
        legacyVibrancyView.effect = effect
        legacyVibrancyEnabled = effect != nil
        updateLegacyContentHost()
    }

    private func updateLegacyContentHost() {
        let contentHost: UIView = legacyVibrancyEnabled && !isSelected
            ? legacyVibrancyView.contentView
            : self
        if imageNode.view.superview !== contentHost {
            imageNode.view.removeFromSuperview()
            contentHost.addSubview(imageNode.view)
        }
        if titleNode.view.superview !== contentHost {
            titleNode.view.removeFromSuperview()
            contentHost.addSubview(titleNode.view)
        }
        bringSubviewToFront(badgeView)
    }

    #if DEBUG
    var contentUsesUIKitVibrancyForTesting: Bool {
        legacyVibrancyView.effect is UIVibrancyEffect
            && imageNode.view.superview === legacyVibrancyView.contentView
            && titleNode.view.superview === legacyVibrancyView.contentView
    }
    #endif

    private func resolvedColor(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: colorTraitCollectionOverride ?? traitCollection)
    }

    private func updateAppearance() {
        imageNode.image = (isSelected ? item.selectedImage : item.image)?.withRenderingMode(.alwaysTemplate)
        let iconColor = resolvedColor(isSelected ? theme.tabBarSelectedIconColor : theme.tabBarIconColor)
        imageNode.tintColor = iconColor
        // ASImageNode can retain the previously rendered template image when
        // only its semantic tint changes (for example forced-dark -> light
        // after a pop). Keep UIKit's backing view in sync and invalidate the
        // node display so the icon changes in the same transaction as text.
        imageNode.view.tintColor = iconColor
        imageNode.setNeedsDisplay()
        imageNode.view.setNeedsDisplay()

        titleFont = UIFont.aetherScaledSystemFont(
            ofSize: 10.0,
            // The liquid lens overlays its selected-content view on the
            // regular-content view. Different weights do not share glyph
            // outlines and leave a dark fringe around the selected title.
            weight: .medium,
            maximumPointSize: 11.5,
            compatibleWith: traitCollection
        )

        titleNode.attributedText = NSAttributedString(
            string: item.title,
            attributes: [
                .font: titleFont,
                .foregroundColor: resolvedColor(isSelected ? theme.tabBarSelectedTextColor : theme.tabBarTextColor),
                .paragraphStyle: Self.centeredParagraphStyle
            ]
        )

        badgeView.badgeColor = resolvedColor(theme.tabBarBadgeBackgroundColor)
        badgeView.textColor = resolvedColor(theme.tabBarBadgeTextColor)
        badgeView.strokeColor = resolvedColor(theme.tabBarBadgeStrokeColor)
        badgeView.isHidden = item.badgeValue?.isEmpty ?? true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        legacyVibrancyView.frame = bounds

        if theme.appearanceStyle == .legacy {
            let frames = TabBarView.LegacyLayout.itemContentFrames(
                bounds: bounds,
                titleLineHeight: titleFont.lineHeight
            )
            imageNode.frame = frames.icon
            titleNode.frame = frames.title

            let badgeSize = badgeView.sizeThatFits(CGSize(width: 40, height: 20))
            badgeView.frame = CGRect(
                x: bounds.width / 2.0 + 8.0,
                y: -2.0,
                width: badgeSize.width,
                height: badgeSize.height
            )
            return
        }

        // Figma spec: 8pt inset on all sides of the item's content (icon +
        // label). With a 60pt-tall pill that leaves 44pt of vertical content,
        // which fits the 30pt icon + 1pt gap + 13pt label exactly.
        let contentInset: CGFloat = 8.0
        let textHeight = min(22.0, ceil(titleFont.lineHeight))
        let iconFrame = liquidIconFrame(in: bounds)
        let imageSize = iconFrame.height
        let totalHeight = imageSize + textHeight
        // Vertical content is pinned between the 8pt top and 8pt bottom insets.
        let availableHeight = max(totalHeight, bounds.height - contentInset * 2.0)
        let topY = contentInset + floor((availableHeight - totalHeight) / 2.0)

        imageNode.frame = iconFrame
        // Label gets 8pt horizontal inset so long titles respect the padding
        // rather than bleeding to the pill edge.
        titleNode.frame = CGRect(
            x: contentInset,
            y: topY + imageSize,
            width: max(0.0, bounds.width - contentInset * 2.0),
            height: textHeight
        )

        let badgeSize = badgeView.sizeThatFits(CGSize(width: 40, height: 20))
        badgeView.frame = CGRect(
            x: bounds.width / 2.0 + 8.0,
            y: topY - 2.0,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }

    private static let centeredParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style.copy() as? NSParagraphStyle ?? style
    }()
}

// MARK: - Gesture recognizer delegate

extension TabBarView: UIGestureRecognizerDelegate {
    /// Gesture arbitration policy:
    ///   - Two tab-bar recognisers (both attached to views inside this
    ///     view): **default compete**. Tap and long-press in particular
    ///     must NOT fire simultaneously — a held press that opens the
    ///     context menu must not ALSO emit a tap on finger-up, which
    ///     would round-trip through `tabSelected` and trigger
    ///     pop-to-root / scroll-to-top on the active tab.
    ///   - One of the recognisers is external (parent scroll, system
    ///     edge-swipe back, etc.): **simultaneous**. The tab bar
    ///     shouldn't steal touches from the surrounding hierarchy.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let ourFirst = gestureRecognizer.view?.isDescendant(of: self) ?? false
        let ourSecond = otherGestureRecognizer.view?.isDescendant(of: self) ?? false
        if ourFirst && ourSecond {
            return false
        }
        return true
    }
}

// MARK: - Search text field delegate

extension TabBarView: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        guard textField === searchTextField, let close = searchCloseButton else { return }
        let profile = AetherMotion.tabBarPress.press
        UIView.animate(withDuration: profile.duration, delay: 0, usingSpringWithDamping: profile.dampingRatio, initialSpringVelocity: profile.initialVelocity, options: [.beginFromCurrentState]) {
            close.alpha = 1.0
            close.transform = .identity
            self.positionSearchViewsExpanded()
        }
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === searchTextField, let close = searchCloseButton else { return }
        UIView.animate(withDuration: AetherMotion.tabBarPress.release.duration * 0.65, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            close.alpha = 1.0
            close.transform = .identity
            self.positionSearchViewsExpanded()
        }
    }
}
