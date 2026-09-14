import UIKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

/// Observes the compact tab-bar morph on the main thread.
///
/// The update is atomic: `progress` and `bottomBarAccessoryFrame` describe
/// the same rendered frame. This makes it safe to drive adjacent chrome,
/// artwork, or other effects without reconstructing AetherUI's animation
/// timing externally. Once an accessory is logically removed its frame is
/// `nil`, even if an outgoing installation is still completing a retirement
/// fade that no longer belongs to the public accessory slot.
@MainActor
public protocol AetherTabBarControllerMinimizationDelegate: AnyObject {
    /// Called whenever a rendered compact-morph sample changes, for exact
    /// endpoints, and whenever the installed compact accessory changes
    /// geometry outside the morph (for example after installation, intrinsic
    /// resize, removal, rotation, or a container resize).
    ///
    /// - Parameters:
    ///   - progress: `0` for the expanded pill and `1` for minimized chrome.
    ///     The value is clamped even while the visual spring overshoots.
    ///   - bottomBarAccessoryFrame: The accessory glass frame in
    ///     `controller.view` coordinates, or `nil` when no compact accessory
    ///     is installed or the surface is owned by its fullscreen transition.
    ///     During animation this is the actual rendered frame, not the
    ///     model-layer destination.
    func tabBarController(
        _ controller: AetherTabBarController,
        didUpdateMinimizationProgress progress: CGFloat,
        bottomBarAccessoryFrame: CGRect?
    )
}

public extension AetherTabBarControllerMinimizationDelegate {
    func tabBarController(
        _ controller: AetherTabBarController,
        didUpdateMinimizationProgress progress: CGFloat,
        bottomBarAccessoryFrame: CGRect?
    ) {}
}

private final class TabBarVisibilityDisplayLinkTarget: NSObject {
    var tick: ((CADisplayLink) -> Void)?

    @objc func handleDisplayLink(_ displayLink: CADisplayLink) {
        tick?(displayLink)
    }
}

private final class TabBarCompactMorphDisplayLinkTarget: NSObject {
    var tick: ((CADisplayLink) -> Void)?

    @objc func handleDisplayLink(_ displayLink: CADisplayLink) {
        tick?(displayLink)
    }
}

private final class TabBarPerSourceChromeState {
    weak var owner: AnyObject?
    var legacyChromeVisible: Bool?
    var navigationEdgeAlpha: CGFloat?

    init(owner: AnyObject) {
        self.owner = owner
    }
}

/// Container for top-level tabs. Pure UIKit replacement for the original
/// TabBarController.
///
/// Architecture (native-iOS shape, no shared nav bar):
/// - `AetherTabBarController` is the window's rootViewController.
/// - Each tab's controller is typically a `AetherNavigationController`
///   hosting its own navigation stack and its own nav bar. The tab bar
///   controller never owns a nav bar — every screen brings its own, so
///   push/pop inside a tab animates the bar naturally along with the
///   content (no snapshot crossfades, no hiding of child bars).
/// - The floating tab bar sits on top of the currently-visible tab's
///   content. `updateIsTabBarHidden(_:)` slides it out when a pushed
///   screen wants a full-height layout.
open class AetherTabBarController: AetherViewController {
    // MARK: - Properties

    private let tabBarView: TabBarView
    private var appearance: AetherAppearance
    /// Deprecated full-theme API adapter. It is resolved as a container-level
    /// override, below the active screen and above application appearance.
    private var compatibilityTabBarTheme: TabBarView.Theme?
    private var resolvedAppearanceStyle: AetherAppearanceStyle
    private var _controllers: [UIViewController] = []
    private var searchItem: SearchTabItem?
    private var searchItemSourceController: UIViewController?
    private weak var presentedSearchController: UIViewController?
    private var searchTransitionGeneration: Int = 0
    private var isDeliveringSearchDeactivationLifecycle = false
    private var hasDeliveredSearchDeactivationLifecycle = false
    private var _selectedIndex: Int = 0
    public private(set) var resolvedAppearance: AetherTabBarResolvedAppearance

    /// Receives per-frame compact chrome geometry on the main thread.
    /// Kept weak so an owning screen can safely use itself as the observer.
    public weak var minimizationDelegate: AetherTabBarControllerMinimizationDelegate? {
        didSet {
            guard minimizationDelegate !== oldValue else { return }
            // Dedupe belongs to one observer lifetime. A newly-installed
            // delegate needs an immediate baseline even if the chrome has not
            // moved since a previous observer (or since no observer at all).
            lastPublishedMinimizationSnapshot = nil
            guard minimizationDelegate != nil else { return }
            publishMinimizationUpdate(accessoryFrame: bottomBarAccessoryFrame)
        }
    }

    public var controllers: [UIViewController] {
        return _controllers
    }

    /// Controller for the currently-visible tab.
    public var currentController: UIViewController? {
        guard _selectedIndex < _controllers.count else { return nil }
        return _controllers[_selectedIndex]
    }

    private var currentAppearanceController: UIViewController? {
        if let navigationController = currentController as? AetherNavigationController {
            return navigationController.topController
        }
        return currentController
    }

    public var selectedIndex: Int {
        get { _selectedIndex }
        set {
            guard newValue != _selectedIndex, newValue < _controllers.count else { return }
            // Freeze the outgoing screen's endpoint before detaching its
            // view. Removing a short, over-scrolled UIScrollView can emit a
            // final bounds/inset KVO sample; if that sample is allowed to
            // reach the reducer it overwrites the screen's hysteresis state
            // just before we cache it.
            detachScrollObserver()
            let previousIndex = _selectedIndex
            _selectedIndex = newValue
            tabBarView.selectedIndex = newValue
            transitionToController(at: newValue, from: previousIndex, animated: true)
            invalidateAppearance()
        }
    }

    private var appliedTabBarTheme: TabBarView.Theme {
        didSet {
            if appliedTabBarTheme.appearanceStyle == .legacy {
                cancelScrollMinimizeArming(transition: .immediate)
                isTabBarMinimized = false
                scrollObserver?.synchronize(minimized: false)
                tabBarMinimizationProgress = 0.0
                tabBarMinimizeAnimation = nil
                accessoryFrameObservation = nil
                invalidateAccessoryCompactMorphDisplayLink()
                tabBarMinimizedBeforeSearchActivation = nil
                legacyScrollEdgeChromeVisible = currentPerSourceChromeState(
                    createIfNeeded: false
                )?.legacyChromeVisible
            }
            tabBarView.updateTheme(appliedTabBarTheme)
            if appliedTabBarTheme.appearanceStyle == .legacy,
               let legacyScrollEdgeChromeVisible {
                tabBarView.setLegacyScrollEdgeChromeVisible(
                    legacyScrollEdgeChromeVisible,
                    transition: .immediate
                )
            }
            if let layout = currentlyAppliedLayout {
                containerLayoutUpdated(layout, transition: .immediate)
            } else if isViewLoaded {
                attachScrollObserverIfPossible()
            }
            if appliedTabBarTheme.appearanceStyle == .legacy {
                publishMinimizationUpdate(accessoryFrame: bottomBarAccessoryFrame)
            }
        }
    }

    /// Deprecated full-theme compatibility adapter.
    ///
    /// Assignments are retained as a container-level override. Active-screen
    /// appearance providers still resolve above it, and app appearance remains
    /// the inherited base.
    @available(*, deprecated, message: "Use app-level AppearanceStyle and AetherControllerAppearanceProviding overrides.")
    public var tabBarTheme: TabBarView.Theme {
        get { compatibilityTabBarTheme ?? appliedTabBarTheme }
        set {
            compatibilityTabBarTheme = newValue
            invalidateAppearance()
        }
    }

    /// Closure returning the `ContextMenuItem`s for a tab on long-press.
    /// Called with the tab index; return an empty array to suppress the
    /// menu for that tab. Setup-time configuration path — preferred over
    /// subclassing for most call sites (e.g. SceneDelegate wiring).
    ///
    /// Subclasses can alternatively override `contextMenuItems(forTabAt:)`
    /// and ignore this closure. The default implementation of that method
    /// calls this closure, so mixing the two is rarely needed.
    public var tabContextMenuItemsProvider: ((Int) -> [ContextMenuItem])?

    // MARK: - Bottom Bar Accessory

    /// Accessory view anchored directly above the tab bar chrome and wrapped
    /// in a style-aware surface. Mirrors iOS 26's
    /// `UITabBarController.bottomAccessory`.
    ///
    /// Legacy uses 16pt side insets, its classic minimum height, and a 4pt gap
    /// above the attached tab bar. Liquid Glass keeps the theme's side inset, the
    /// accessory's requested height and its 8pt floating gap.
    ///
    /// Use `setBottomBarAccessory(_:animated:)` for an animated crossfade;
    /// direct assignment swaps immediately.
    public var bottomBarAccessory: TabBarAccessoryView? {
        get { _bottomBarAccessory }
        set { setBottomBarAccessory(newValue, animated: false) }
    }

    /// Current geometry of the installed compact accessory in `view`
    /// coordinates. Reads the presentation layer while UIKit owns a regular
    /// resize. The frame remains available when compact chrome is temporarily
    /// hidden, and becomes `nil` while Full Player owns the reusable surface.
    public var bottomBarAccessoryFrame: CGRect? {
        guard isViewLoaded,
              expandedAccessoryViewController == nil,
              let wrapper = bottomBarAccessoryWrapper,
              let superview = wrapper.superview else {
            return nil
        }
        // The sampled compact path is applied inside this display-link turn
        // and committed together with delegate-driven mutations. Its model
        // frame is therefore the geometry for the frame being produced;
        // Core Animation's presentation copy still describes the previous
        // committed frame until the transaction closes. Ordinary UIKit resize
        // animations continue to expose their live presentation geometry.
        let frameInSuperview: CGRect
        if let appliedFrame = bottomBarAccessoryAppliedFrame,
           Self.framesNearlyEqual(appliedFrame, wrapper.frame) {
            frameInSuperview = appliedFrame
        } else {
            frameInSuperview = wrapper.layer.presentation()?.frame
                ?? wrapper.frame
        }
        return superview.convert(frameInSuperview, to: view)
    }

    /// Assign the bottom bar accessory with an optional crossfade
    /// animation. `animated = false` matches direct property assignment.
    public func setBottomBarAccessory(_ accessory: TabBarAccessoryView?, animated: Bool) {
        guard accessory !== _bottomBarAccessory else { return }
        let scrollSnapshot = captureObservedRawScrollOffset()
        // Installation/replacement owns wrapper geometry and crossfade state.
        // Cancel the short arming preview first so the new surface is never
        // installed under a transform owned by the old accessory session.
        cancelScrollMinimizeArming(transition: .immediate)
        bottomBarAccessoryAppliedFrame = nil
        if let wrapper = bottomBarAccessoryWrapper,
           tabBarMinimizeAnimation?.accessoryTargetFrame != nil {
            cancelAccessoryCompactMorph(wrapper: wrapper)
        }
        pendingAccessoryCompactMorphDirection = nil
        let old = _bottomBarAccessory
        _bottomBarAccessory = accessory
        installBottomBarAccessory(old: old, new: accessory, animated: animated)
        restoreObservedRawScrollOffsetAfterLayout(scrollSnapshot)
    }

    private var _bottomBarAccessory: TabBarAccessoryView?
    private var bottomBarAccessoryWrapper: GlassBackgroundView?
    /// Last geometry explicitly committed by our sampled/immediate owner.
    /// Core Animation's presentation copy remains one transaction behind
    /// inside the callback that produced a frame, so the public getter uses
    /// this value until a regular UIKit geometry animation takes ownership.
    private var bottomBarAccessoryAppliedFrame: CGRect?
    private var bottomBarAccessoryTap: UITapGestureRecognizer?
    private var bottomBarAccessoryPress: GlassHighlightGestureRecognizer?
    private static let liquidBottomBarAccessoryBottomGap: CGFloat = 8.0
    private static let legacyBottomBarAccessoryShadow =
        GlassBackgroundView.LegacyShadowOverride(
            opacity: 0.26,
            radius: 8.0,
            offset: CGSize(width: 0.0, height: 2.0)
        )
    private lazy var legacyBottomChromeBackdropGroupingIdentifier =
        "AetherUI.BottomChrome.\(UUID().uuidString)"
    private static let scrollMinimizeArmedHorizontalInset: CGFloat = 4.0
    private static let scrollMinimizeArmedAccessoryScale: CGFloat = 0.985
    private static let scrollMinimizeArmedAccessoryTransformAnimationKey =
        "aether.tabBar.scrollMinimizeArmedAccessoryTransform"
    private static let bottomBarAccessoryCrossfadeDuration: TimeInterval = AetherMotion.tabBarSelection.duration * 0.82
    private static let bottomBarAccessoryCrossfadeBlurRadius: CGFloat = 10.0
    #if !APPSTORE_SAFE
    private static let ownedTransitionBlurAnimationKey = ObfuscatedSymbols.keypath(
        ObfuscatedSymbols.filters,
        ObfuscatedSymbols.gaussianBlur,
        ObfuscatedSymbols.filterRadiusKey
    )
    #endif

    private var resolvedBottomBarAccessoryBottomGap: CGFloat {
        appliedTabBarTheme.appearanceStyle == .legacy
            ? TabBarView.LegacyLayout.accessoryBottomGap
            : Self.liquidBottomBarAccessoryBottomGap
    }

    private var resolvedBottomBarAccessorySideInset: CGFloat {
        appliedTabBarTheme.appearanceStyle == .legacy
            ? TabBarView.LegacyLayout.accessorySideInset
            : appliedTabBarTheme.sideInset
    }

    private func resolvedBottomBarAccessoryHeight(
        _ accessory: TabBarAccessoryView?
    ) -> CGFloat {
        let requestedHeight = max(0.0, accessory?.height ?? 0.0)
        guard requestedHeight > 0.0,
              appliedTabBarTheme.appearanceStyle == .legacy else {
            return requestedHeight
        }
        return max(
            TabBarView.LegacyLayout.minimumAccessoryHeight,
            requestedHeight
        )
    }
    private var bottomBarAccessoryTransitionGeneration: Int = 0
    /// A wrapper whose animated removal has not completed yet. Keep an
    /// explicit handle so a rapid stop -> play (or any other replacement)
    /// can cancel that outgoing installation before adding the next glass
    /// surface. Otherwise the detached model pointer and still-visible view
    /// briefly allow two overlapping `GlassBackgroundView`s.
    private weak var bottomBarAccessoryOutgoingWrapper: GlassBackgroundView?
    /// Visual-only reservation retained while the outgoing wrapper finishes
    /// its fade. Child safe areas move to the new model endpoint immediately,
    /// but the Legacy chrome field and hidden separator must remain behind the
    /// accessory for as long as it is still on screen.
    private var bottomBarAccessoryOutgoingVisualReservation: CGFloat = 0.0

    private static func clearOwnedTransitionBlur(from layer: CALayer) {
        #if APPSTORE_SAFE
        // Safe builds never install the private Gaussian transition filter.
        return
        #else
        for key in layer.animationKeys() ?? [] {
            let keyPath = (layer.animation(forKey: key) as? CAPropertyAnimation)?.keyPath
            if key == ownedTransitionBlurAnimationKey
                || keyPath?.contains(ObfuscatedSymbols.gaussianBlur) == true {
                layer.removeAnimation(forKey: key)
            }
        }
        guard let filters = layer.filters else {
            return
        }
        let retainedFilters = filters.filter { candidate in
            guard let object = candidate as? NSObject else {
                return true
            }
            return !object.description.contains(ObfuscatedSymbols.gaussianBlur)
        }
        layer.filters = retainedFilters.isEmpty ? nil : retainedFilters
        #endif
    }

    // MARK: - Expanded Accessory (Apple-Music-style morph)

    /// Controller currently presented in the expanded form. `nil` while
    /// the accessory sits in its collapsed pill state.
    public private(set) var expandedAccessoryViewController: UIViewController?

    /// Generic transition tuning. Values are read when a new expansion
    /// session begins; changing them never rebuilds the installed accessory.
    public var bottomBarAccessoryTransitionConfiguration: BottomBarAccessoryTransitionConfiguration = .default

    /// Observable deterministic state for diagnostics and integration tests.
    public var bottomBarAccessoryPresentationState: BottomBarAccessoryPresentationState {
        bottomBarAccessoryTransitionCoordinator?.state ?? .collapsed
    }

    /// VoiceOver ownership is intentionally state-based rather than progress-
    /// based. A partially visible endpoint is not a stable accessibility
    /// surface: exposing it during a morph lets focus escape into controls
    /// whose geometry is still moving, or briefly exposes both Mini and Full.
    internal enum BottomBarAccessoryAccessibilityOwnership: Equatable {
        case collapsed
        case expanded
        case transition
    }

    internal static func bottomBarAccessoryAccessibilityOwnership(
        for state: BottomBarAccessoryPresentationState
    ) -> BottomBarAccessoryAccessibilityOwnership {
        switch state {
        case .collapsed:
            return .collapsed
        case .expanded:
            return .expanded
        case .expanding, .dragging, .settlingToExpanded, .settlingToCollapsed:
            return .transition
        }
    }

    /// Single logical VoiceOver destination after Full Player collapses.
    /// Exposed internally so integration tests can verify the nil-accessory
    /// fallback without relying on global VoiceOver process state.
    internal var collapsedAccessoryAccessibilityFocusTargetForTesting: UIView? {
        collapsedAccessoryAccessibilityFocusTarget
    }

    /// Runtime integration hook for verifying that shared-element pixels live
    /// in the framework-owned overlay above the one morphing glass surface.
    internal var bottomBarAccessorySharedElementHostForTesting: UIView? {
        bottomBarAccessorySharedElementHost
    }

    /// Verifies that system chrome remains alive underneath the Full surface;
    /// the player reveals it by occlusion rather than fading it out.
    internal var playerUnderlyingTabBarViewForTesting: UIView {
        tabBarView
    }

    private var collapsedAccessoryAccessibilityFocusTarget: UIView? {
        _bottomBarAccessory ?? currentController?.view
    }

    private var bottomBarAccessoryCollapsedContentHost: UIView?
    private var bottomBarAccessoryExpandedContentHost: UIView?
    private var bottomBarAccessorySharedElementHost: UIView?
    private var bottomBarAccessoryTransitionCoordinator: BottomBarAccessoryTransitionCoordinator?
    private var bottomBarAccessoryReduceMotionStatusObserver: NSObjectProtocol?
    /// Production reads the live UIKit accessibility value. The internal
    /// closure keeps notification behavior deterministic in package tests
    /// without attempting to mutate the process-wide accessibility setting.
    internal var bottomBarAccessoryReduceMotionStatusProvider: () -> Bool = {
        UIAccessibility.isReduceMotionEnabled
    }
    private var accessoryDismissGesture: InteractiveTransitionGestureRecognizer?
    private var accessoryTransitionGeometry: BottomBarAccessoryTransitionGeometry?
    /// Immutable tab-bar state captured at the exact moment an accessory
    /// expansion starts. The full-player session owns this docking contract
    /// until collapse completes: scroll/search/navigation chrome may continue
    /// producing layout callbacks, but they must never replace the attraction
    /// point under the expanded card.
    private struct AccessoryPresentationSession {
        let dockingContext: BottomBarAccessoryDockingContext
        let sourceCollapsedFrame: CGRect
        let wasTabBarMinimized: Bool
        let wasTabBarHidden: Bool
        let tabBarHiddenProgress: CGFloat
        let wasSearchActive: Bool
        var resolvedLayoutSize: CGSize
        var resolvedSafeInsets: UIEdgeInsets
    }
    private var accessoryPresentationSession: AccessoryPresentationSession?
    private var accessoryPresentationProgress: CGFloat = 0
    private var accessoryUsesExpandedSystemChrome = false
    private var accessoryControllerAttachedByExpansion = false
    private var accessoryDismissCompletions: [() -> Void] = []
    private var accessoryForcedCollapse = false

    /// The compact player changes lanes as the tab bar minimizes. Both axes
    /// share one sampled clock, but use a direction-aware curved response:
    /// width leads the descent and the rise leads width on expansion. There is
    /// no waypoint or second animator, so the path remains one fluid gesture.
    private enum BottomBarAccessoryCompactMorphDirection: Equatable {
        case minimize
        case expand
    }
    private struct TabBarMinimizeAnimation {
        let generation: UInt
        let sourceProgress: CGFloat
        let targetProgress: CGFloat
        let direction: BottomBarAccessoryCompactMorphDirection
        let duration: TimeInterval
        let curve: ContainedViewLayoutTransitionCurve
        var elapsed: TimeInterval
        var lastTimestamp: CFTimeInterval?
        var accessorySourceFrame: CGRect?
        var accessoryTargetFrame: CGRect?
    }
    private struct BottomBarAccessoryFrameObservation {
        let generation: UInt
        let duration: TimeInterval
        var elapsed: TimeInterval
        var lastTimestamp: CFTimeInterval?
    }
    private struct TabBarMinimizationPublishedSnapshot: Equatable {
        let progress: CGFloat
        let accessoryFrame: CGRect?
    }
    private var pendingAccessoryCompactMorphDirection: BottomBarAccessoryCompactMorphDirection?
    private var tabBarMinimizeAnimation: TabBarMinimizeAnimation?
    private var accessoryFrameObservation: BottomBarAccessoryFrameObservation?
    private var accessoryCompactMorphDisplayLink: CADisplayLink?
    private var accessoryCompactMorphDisplayLinkTarget: TabBarCompactMorphDisplayLinkTarget?
    private var tabBarMinimizeAnimationGeneration: UInt = 0
    private var accessoryFrameObservationGeneration: UInt = 0
    private var isPublishingMinimizationUpdate = false
    private var lastPublishedMinimizationSnapshot: TabBarMinimizationPublishedSnapshot?
    private var pendingMinimizationSnapshot: TabBarMinimizationPublishedSnapshot?

    /// `true` once the dismiss pan has decided to "own" the gesture
    /// (either no scroll view under the finger, or the scroll view was
    /// already at its top edge). Until then, scroll views inside the
    /// expanded controller handle the touch and our handler is a no-op.
    private var accessoryDismissDragActive: Bool = false
    /// Captures one relevant vertical scroll owner at gesture begin and keeps
    /// it through handoff. Re-hit-testing every sample can accidentally switch
    /// from a scrolled lyrics view to an at-top horizontal pager (or to nil
    /// after the finger leaves its bounds) and dismiss the card too early.
    private let accessoryDismissScrollHandoff =
        BottomBarAccessoryDismissScrollHandoff()

    /// Animate the accessory wrapper + its inner accessory through the
    /// minimize morph.
    ///
    /// Why a sampled frame clock instead of `transition.updateFrame`:
    /// the `ContainedViewLayoutTransition.updateFrame` helper schedules
    /// the frame change and the child layout pass in *separate*
    /// animation blocks. With `GlassBackgroundView` (which re-applies
    /// internal effect-view frames inside its own `update(...)`) the
    /// nested blocks raced with the outer one and the wrapper would
    /// snap to the new frame while the spring kept running on a stale
    /// destination. Applying wrapper, inner content, material size and the
    /// public callback in one display-link sample gives them one geometry
    /// owner and one rendered clock.
    private func applyAccessoryFrame(
        _ wrapper: GlassBackgroundView,
        frame: CGRect,
        transition: ContainedViewLayoutTransition,
        compactMorphDirection: BottomBarAccessoryCompactMorphDirection? = nil
    ) {
        let chromeAppearance = tabBarView.chromeGlassAppearance
        configureBottomBarAccessorySurface(
            wrapper,
            chromeAppearance: chromeAppearance
        )

        if let compactMorphDirection, transition.isAnimated,
           !bottomBarAccessoryReduceMotionStatusProvider() {
            startAccessoryCompactMorph(
                wrapper,
                targetFrame: frame,
                direction: compactMorphDirection,
                transition: transition,
                chromeAppearance: chromeAppearance
            )
            return
        }

        if let activeTarget = tabBarMinimizeAnimation?.accessoryTargetFrame {
            if Self.framesNearlyEqual(activeTarget, frame) {
                return
            }
            cancelAccessoryCompactMorph(wrapper: wrapper)
        }

        bottomBarAccessoryAppliedFrame = transition.isAnimated ? nil : frame

        let innerSize = frame.size
        let accessory = _bottomBarAccessory
        let expandedHost = bottomBarAccessoryExpandedContentHost
        let sharedElementHost = bottomBarAccessorySharedElementHost
        let applyFrames = {
            wrapper.frame = frame
            let bounds = CGRect(origin: .zero, size: innerSize)
            expandedHost?.frame = bounds
            sharedElementHost?.frame = bounds
            accessory?.frame = bounds
        }

        // Keep both setters in one animation transaction, but preserve the
        // actual requested curve. The previous bridge accidentally mapped a
        // regular spring to damping 500 and every cubic curve to damping 1,
        // which made accessory geometry feel disconnected from the tab bar.
        transition.animateView(applyFrames)

        wrapper.update(
            size: innerSize,
            cornerRadius: resolvedBottomBarAccessoryCornerRadius(
                for: frame.size
            ),
            isDark: chromeAppearance.isDark,
            tintColor: chromeAppearance.tint,
            isInteractive: false,
            isVisible: true,
            transition: transition
        )
        // The wide compact player uses Aether's bounded press profile below.
        // Native UIGlassEffect interaction can translate this short capsule
        // dozens of points and visually detach it from the tab bar.
        wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
        wrapper.transitionMaterialInteractionEnabled = false
        accessory?.updateLayout(size: innerSize, transition: transition)

        if transition.isAnimated {
            startAccessoryFrameObservation(duration: transition.duration)
        } else {
            publishMinimizationUpdate(accessoryFrame: frame)
        }
    }

    private static func framesNearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    /// Legacy mini players are floating rounded rectangles, not Liquid Glass
    /// capsules. Resolve the radius from the semantic floating-surface token
    /// while preserving the native capsule geometry for Liquid Glass.
    private func resolvedBottomBarAccessoryCornerRadius(
        for size: CGSize
    ) -> CGFloat {
        let capsuleRadius = max(0.0, min(size.width, size.height) / 2.0)
        guard appliedTabBarTheme.appearanceStyle == .legacy else {
            return capsuleRadius
        }
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .floatingSurface,
            traitCollection: bottomBarAccessoryWrapper?.traitCollection
                ?? traitCollection
        )
        return min(capsuleRadius, tokens.cornerRadius)
    }

    /// Keep geometry, renderer generation and the style-specific material in
    /// one recipe. The classic mini player uses a full-alpha public
    /// `systemUltraThinMaterial`; it does not simulate density with a color
    /// wash over the tab bar's chrome material.
    private func configureBottomBarAccessorySurface(
        _ wrapper: GlassBackgroundView,
        chromeAppearance: TabBarChromeGlassAppearance
    ) {
        configureBottomBarAccessoryMaterialOwnership(
            wrapper,
            theme: appliedTabBarTheme
        )
        wrapper.updateStyle(chromeAppearance.viewStyle)
        // Keep the layout-driven source of truth aligned with the explicit
        // update below. Otherwise a later layout pass can restore `.panel`
        // even though the current rendered params use the shared tab tint.
        wrapper.glassTintColor = chromeAppearance.tint
        wrapper.isDarkOverride = chromeAppearance.isDark
        wrapper.overrideUserInterfaceStyle = chromeAppearance.isDark
            ? .dark
            : .light
    }

    private func configureBottomBarAccessoryMaterialOwnership(
        _ wrapper: GlassBackgroundView,
        theme: TabBarView.Theme
    ) {
        let appearanceStyle = theme.appearanceStyle
        let usesLegacyMaterial = appearanceStyle == .legacy && theme.enableBlur
        let groupingIdentifier = usesLegacyMaterial
            ? legacyBottomChromeBackdropGroupingIdentifier
            : nil
        tabBarView.setLegacyBackdropGroupingIdentifier(groupingIdentifier)
        wrapper.legacyBackdropGroupingIdentifier = groupingIdentifier
        wrapper.legacyBlurStyleOverride = appearanceStyle == .legacy
            ? .systemUltraThinMaterial
            : nil
        wrapper.legacyUsesExternalBlurMaterial = false
        wrapper.legacyUsesBlurMaterial = appearanceStyle == .legacy
            ? theme.enableBlur
            : true
        wrapper.legacyBorderWidthOverride = appearanceStyle == .legacy
            ? 0.0
            : nil
        wrapper.legacyShadowOverride = appearanceStyle == .legacy
            ? Self.legacyBottomBarAccessoryShadow
            : nil
        wrapper.legacySurfaceColorOverride = nil
        // Apply the renderer generation last so a live style switch installs
        // it with the complete Legacy recipe in one pass.
        wrapper.appearanceStyleOverride = appearanceStyle
    }

    private func applyAccessoryGeometryImmediately(
        _ wrapper: GlassBackgroundView,
        frame: CGRect,
        chromeAppearance: TabBarChromeGlassAppearance
    ) {
        bottomBarAccessoryAppliedFrame = frame
        configureBottomBarAccessorySurface(
            wrapper,
            chromeAppearance: chromeAppearance
        )
        wrapper.frame = frame
        let bounds = CGRect(origin: .zero, size: frame.size)
        bottomBarAccessoryExpandedContentHost?.frame = bounds
        bottomBarAccessorySharedElementHost?.frame = bounds
        _bottomBarAccessory?.frame = bounds
        wrapper.update(
            size: frame.size,
            cornerRadius: resolvedBottomBarAccessoryCornerRadius(
                for: frame.size
            ),
            isDark: chromeAppearance.isDark,
            tintColor: chromeAppearance.tint,
            isInteractive: false,
            isVisible: true,
            transition: .immediate
        )
        wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
        wrapper.transitionMaterialInteractionEnabled = false
        _bottomBarAccessory?.updateLayout(size: frame.size, transition: .immediate)
    }

    private func cancelAccessoryCompactMorph(wrapper: GlassBackgroundView) {
        guard var animation = tabBarMinimizeAnimation,
              animation.accessoryTargetFrame != nil else { return }
        let currentFrame = wrapper.layer.presentation()?.frame ?? wrapper.frame
        animation.accessorySourceFrame = nil
        animation.accessoryTargetFrame = nil
        tabBarMinimizeAnimation = animation
        wrapper.layer.removeAllAnimations()
        applyAccessoryGeometryImmediately(
            wrapper,
            frame: currentFrame,
            chromeAppearance: tabBarView.chromeGlassAppearance
        )
    }

    private func startAccessoryCompactMorph(
        _ wrapper: GlassBackgroundView,
        targetFrame: CGRect,
        direction: BottomBarAccessoryCompactMorphDirection,
        transition: ContainedViewLayoutTransition,
        chromeAppearance: TabBarChromeGlassAppearance
    ) {
        if tabBarMinimizeAnimation == nil {
            startTabBarMinimizeAnimation(
                to: direction == .minimize ? 1.0 : 0.0,
                transition: transition
            )
        }
        guard var animation = tabBarMinimizeAnimation,
              animation.direction == direction else { return }

        let sourceFrame = bottomBarAccessoryAppliedFrame
            ?? wrapper.layer.presentation()?.frame
            ?? wrapper.frame
        let sourceSublayerTransform = wrapper.layer.presentation()?.sublayerTransform
            ?? wrapper.layer.sublayerTransform
        wrapper.layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wrapper.layer.sublayerTransform = CATransform3DIdentity
        CATransaction.commit()
        if !CATransform3DEqualToTransform(
            sourceSublayerTransform,
            CATransform3DIdentity
        ) {
            let release = CASpringAnimation(keyPath: "sublayerTransform")
            release.mass = 1.0
            release.stiffness = 120.0
            release.damping = 2.0
                * Double(AetherMotion.tabBarMorph.dampingRatio)
                * sqrt(release.stiffness * release.mass)
            release.initialVelocity = Double(AetherMotion.tabBarMorph.initialVelocity)
            release.fromValue = NSValue(caTransform3D: sourceSublayerTransform)
            release.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            release.duration = transition.duration
            release.isRemovedOnCompletion = true
            wrapper.layer.add(
                release,
                forKey: Self.scrollMinimizeArmedAccessoryTransformAnimationKey
            )
        }
        applyAccessoryGeometryImmediately(
            wrapper,
            frame: sourceFrame,
            chromeAppearance: chromeAppearance
        )
        accessoryFrameObservation = nil
        animation.accessorySourceFrame = sourceFrame
        animation.accessoryTargetFrame = targetFrame
        tabBarMinimizeAnimation = animation
        ensureAccessoryCompactMorphDisplayLink()
    }

    private func startTabBarMinimizeAnimation(
        to targetProgress: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        guard case let .animated(duration, curve) = transition,
              duration > 0.0 else {
            invalidateAccessoryCompactMorphDisplayLink()
            tabBarMinimizeAnimation = nil
            accessoryFrameObservation = nil
            tabBarMinimizationProgress = max(0.0, min(1.0, targetProgress))
            return
        }

        tabBarMinimizeAnimationGeneration &+= 1
        let sourceProgress = tabBarView.minimizationPresentationProgress
            ?? tabBarMinimizationProgress
        tabBarMinimizationProgress = max(0.0, min(1.0, sourceProgress))
        let direction: BottomBarAccessoryCompactMorphDirection = targetProgress >= sourceProgress
            ? .minimize
            : .expand
        tabBarMinimizeAnimation = TabBarMinimizeAnimation(
            generation: tabBarMinimizeAnimationGeneration,
            sourceProgress: sourceProgress,
            targetProgress: max(0.0, min(1.0, targetProgress)),
            direction: direction,
            duration: max(0.01, duration),
            curve: curve,
            elapsed: 0.0,
            lastTimestamp: nil,
            accessorySourceFrame: nil,
            accessoryTargetFrame: nil
        )
        accessoryFrameObservation = nil
        ensureAccessoryCompactMorphDisplayLink()
    }

    private func startAccessoryFrameObservation(duration: TimeInterval) {
        // The minimize clock already samples either our manually-driven frame
        // or UIKit's presentation frame, so a second observer would publish
        // duplicate samples for the same rendered frame.
        guard tabBarMinimizeAnimation == nil else { return }
        accessoryFrameObservationGeneration &+= 1
        accessoryFrameObservation = BottomBarAccessoryFrameObservation(
            generation: accessoryFrameObservationGeneration,
            duration: max(0.01, duration),
            elapsed: 0.0,
            lastTimestamp: nil
        )
        ensureAccessoryCompactMorphDisplayLink()
    }

    private func ensureAccessoryCompactMorphDisplayLink() {
        guard accessoryCompactMorphDisplayLink == nil else { return }
        let target = TabBarCompactMorphDisplayLinkTarget()
        target.tick = { [weak self] displayLink in
            self?.handleAccessoryCompactMorphDisplayLink(displayLink)
        }
        let displayLink = CADisplayLink(
            target: target,
            selector: #selector(TabBarCompactMorphDisplayLinkTarget.handleDisplayLink(_:))
        )
        if #available(iOS 15.0, *) {
            let screenMaximum = view.window?.screen.maximumFramesPerSecond
                ?? UIScreen.main.maximumFramesPerSecond
            let preferred = Float(min(120, max(60, screenMaximum > 0 ? screenMaximum : 120)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60.0,
                maximum: preferred,
                preferred: preferred
            )
        }
        accessoryCompactMorphDisplayLinkTarget = target
        accessoryCompactMorphDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    private func invalidateAccessoryCompactMorphDisplayLink() {
        accessoryCompactMorphDisplayLink?.invalidate()
        accessoryCompactMorphDisplayLink = nil
        accessoryCompactMorphDisplayLinkTarget?.tick = nil
        accessoryCompactMorphDisplayLinkTarget = nil
    }

    private func invalidateAccessoryCompactMorphDisplayLinkIfIdle() {
        if tabBarMinimizeAnimation == nil, accessoryFrameObservation == nil {
            invalidateAccessoryCompactMorphDisplayLink()
        }
    }

    private func handleAccessoryCompactMorphDisplayLink(_ displayLink: CADisplayLink) {
        let frameTimestamp = displayLink.targetTimestamp > displayLink.timestamp
            ? displayLink.targetTimestamp
            : displayLink.timestamp
        let firstFrameDelta = displayLink.duration > 0.0
            ? displayLink.duration
            : 1.0 / 60.0

        if var animation = tabBarMinimizeAnimation {
            let delta: TimeInterval
            if let lastTimestamp = animation.lastTimestamp {
                // CA/UIKit animations advance in wall time. Never cap a hitch:
                // doing so leaves the manual accessory behind the pill after
                // a blocked main thread or foreground resume.
                delta = max(0.0, frameTimestamp - lastTimestamp)
            } else {
                delta = firstFrameDelta
            }
            animation.elapsed = min(animation.duration, animation.elapsed + delta)
            animation.lastTimestamp = frameTimestamp
            let linearProgress = CGFloat(animation.elapsed / animation.duration)
            let fallbackJourneyProgress = Self.sampledTransitionProgress(
                curve: animation.curve,
                linearProgress: linearProgress
            )
            let fallbackAbsoluteProgress = animation.sourceProgress
                + (animation.targetProgress - animation.sourceProgress)
                    * fallbackJourneyProgress
            let renderedAbsoluteProgress = tabBarView.minimizationPresentationProgress
                ?? fallbackAbsoluteProgress
            let progressDistance = animation.targetProgress - animation.sourceProgress
            let visualProgress = abs(progressDistance) > 0.0001
                ? (renderedAbsoluteProgress - animation.sourceProgress) / progressDistance
                : 1.0
            tabBarMinimizationProgress = max(0.0, min(1.0, renderedAbsoluteProgress))

            var renderedAccessoryFrame = expandedAccessoryViewController == nil
                ? bottomBarAccessoryFrame
                : nil
            if let sourceFrame = animation.accessorySourceFrame,
               let targetFrame = animation.accessoryTargetFrame,
               let wrapper = bottomBarAccessoryWrapper,
               wrapper.superview != nil {
                let sampledFrame = Self.sampledAccessoryCompactFrame(
                    from: sourceFrame,
                    to: targetFrame,
                    journeyProgress: visualProgress,
                    direction: animation.direction
                )
                applyAccessoryGeometryImmediately(
                    wrapper,
                    frame: sampledFrame,
                    chromeAppearance: tabBarView.chromeGlassAppearance
                )
                renderedAccessoryFrame = sampledFrame
            }

            let completed = animation.elapsed >= animation.duration
            let generation = animation.generation
            if completed {
                if let targetFrame = animation.accessoryTargetFrame,
                   let wrapper = bottomBarAccessoryWrapper,
                   wrapper.superview != nil {
                    applyAccessoryGeometryImmediately(
                        wrapper,
                        frame: targetFrame,
                        chromeAppearance: tabBarView.chromeGlassAppearance
                    )
                    renderedAccessoryFrame = targetFrame
                } else if expandedAccessoryViewController == nil,
                          let wrapper = bottomBarAccessoryWrapper,
                          wrapper.superview != nil,
                          !wrapper.isHidden {
                    // UIKit owns Reduce Motion / ordinary frame animation in
                    // this branch. Publish its exact model endpoint once the
                    // shared clock completes instead of a one-frame-old
                    // presentation sample.
                    renderedAccessoryFrame = wrapper.frame
                }
                tabBarMinimizationProgress = animation.targetProgress
                tabBarMinimizeAnimation = nil
                invalidateAccessoryCompactMorphDisplayLinkIfIdle()
            } else {
                tabBarMinimizeAnimation = animation
            }

            publishMinimizationUpdate(accessoryFrame: renderedAccessoryFrame)
            // A delegate may synchronously reverse the morph or replace the
            // accessory. Never let this old tick clean up that new owner.
            guard tabBarMinimizeAnimation == nil
                    || tabBarMinimizeAnimation?.generation == generation else {
                return
            }
            return
        }

        if var observation = accessoryFrameObservation {
            let delta: TimeInterval
            if let lastTimestamp = observation.lastTimestamp {
                delta = max(0.0, frameTimestamp - lastTimestamp)
            } else {
                delta = firstFrameDelta
            }
            observation.elapsed = min(observation.duration, observation.elapsed + delta)
            observation.lastTimestamp = frameTimestamp
            let completed = observation.elapsed >= observation.duration
            let generation = observation.generation
            if completed {
                accessoryFrameObservation = nil
                invalidateAccessoryCompactMorphDisplayLinkIfIdle()
            } else {
                accessoryFrameObservation = observation
            }
            publishMinimizationUpdate(
                accessoryFrame: completed ? bottomBarAccessoryWrapper?.frame : bottomBarAccessoryFrame
            )
            guard accessoryFrameObservation == nil
                    || accessoryFrameObservation?.generation == generation else {
                return
            }
            return
        }

        invalidateAccessoryCompactMorphDisplayLink()
    }

    private static func sampledTransitionProgress(
        curve: ContainedViewLayoutTransitionCurve,
        linearProgress: CGFloat
    ) -> CGFloat {
        let linearProgress = max(0.0, min(1.0, linearProgress))
        switch curve {
        case .spring:
            return sampledSpringProgress(
                linearProgress,
                dampingRatio: AetherMotion.navigation.dampingRatio,
                initialVelocity: AetherMotion.navigation.initialVelocity
            )
        case let .customSpring(damping, initialVelocity):
            return sampledSpringProgress(
                linearProgress,
                dampingRatio: damping,
                initialVelocity: initialVelocity
            )
        case .linear, .easeInOut, .custom:
            return curve.value(at: linearProgress)
        }
    }

    private static func sampledSpringProgress(
        _ progress: CGFloat,
        dampingRatio: CGFloat,
        initialVelocity: CGFloat
    ) -> CGFloat {
        let damping = max(0.01, dampingRatio)
        let angularFrequency: CGFloat = 10.0
        let velocity = initialVelocity * angularFrequency

        func response(at time: CGFloat) -> CGFloat {
            if damping < 0.999 {
                let dampedFrequency = angularFrequency
                    * sqrt(max(0.0001, 1.0 - damping * damping))
                let coefficient = (damping * angularFrequency - velocity)
                    / dampedFrequency
                return 1.0 - exp(-damping * angularFrequency * time)
                    * (cos(dampedFrequency * time)
                        + coefficient * sin(dampedFrequency * time))
            }
            // A critically-damped continuation stays finite for custom
            // damping values at or above one while preserving y(0) = 0.
            return 1.0 - exp(-angularFrequency * time)
                * (1.0 + (angularFrequency - velocity) * time)
        }

        let endpoint = response(at: 1.0)
        guard abs(endpoint) > 0.0001 else { return progress }
        return response(at: progress) / endpoint
    }

    private static func sampledAccessoryCompactFrame(
        from source: CGRect,
        to target: CGRect,
        journeyProgress: CGFloat,
        direction: BottomBarAccessoryCompactMorphDirection
    ) -> CGRect {
        let clamped = max(0.0, min(1.0, journeyProgress))
        let overshoot = journeyProgress - clamped
        // Keep only a small, symmetric directional bias. Squaring both ends
        // of the phase makes its derivative zero at the spring endpoints, so
        // crossing an overshooting endpoint cannot introduce a velocity kink.
        // Using the same coefficient on lead and lag also makes minimize and
        // expand exact spatial reverses of one another.
        let inverse = 1.0 - clamped
        let phase = 4.0 * clamped * clamped * inverse * inverse
        let lead = clamped + 0.13 * phase + overshoot
        let lag = clamped - 0.13 * phase + overshoot
        let horizontalProgress: CGFloat
        let verticalProgress: CGFloat
        switch direction {
        case .minimize:
            horizontalProgress = lead
            verticalProgress = lag
        case .expand:
            verticalProgress = lead
            horizontalProgress = lag
        }

        func interpolate(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
            from + (to - from) * progress
        }
        return CGRect(
            x: interpolate(source.minX, target.minX, horizontalProgress),
            y: interpolate(source.minY, target.minY, verticalProgress),
            width: interpolate(source.width, target.width, horizontalProgress),
            height: interpolate(source.height, target.height, horizontalProgress)
        )
    }

    private func publishMinimizationUpdate(accessoryFrame: CGRect?) {
        let snapshot = TabBarMinimizationPublishedSnapshot(
            progress: tabBarMinimizationProgress,
            accessoryFrame: accessoryFrame
        )
        publishMinimizationSnapshot(snapshot)
    }

    private func publishMinimizationSnapshot(
        _ snapshot: TabBarMinimizationPublishedSnapshot
    ) {
        if isPublishingMinimizationUpdate {
            // A callback is allowed to reverse the bar or replace / resize its
            // accessory. Coalesce that nested mutation and deliver it after
            // the current callback so an immediate endpoint is never lost.
            // Always replace the pending value, even when it equals the outer
            // snapshot: A -> B -> A must clear the stale B publication.
            pendingMinimizationSnapshot = snapshot
            return
        }
        guard snapshot != lastPublishedMinimizationSnapshot else { return }

        isPublishingMinimizationUpdate = true
        var nextSnapshot: TabBarMinimizationPublishedSnapshot? = snapshot
        var synchronousDeliveries = 0
        while let currentSnapshot = nextSnapshot, synchronousDeliveries < 4 {
            nextSnapshot = nil
            if currentSnapshot != lastPublishedMinimizationSnapshot {
                lastPublishedMinimizationSnapshot = currentSnapshot
                minimizationDelegate?.tabBarController(
                    self,
                    didUpdateMinimizationProgress: currentSnapshot.progress,
                    bottomBarAccessoryFrame: currentSnapshot.accessoryFrame
                )
            }
            if let pendingMinimizationSnapshot {
                nextSnapshot = pendingMinimizationSnapshot
                self.pendingMinimizationSnapshot = nil
            }
            synchronousDeliveries += 1
        }
        isPublishingMinimizationUpdate = false

        // Avoid an infinite synchronous loop for a pathological delegate that
        // mutates chrome on every callback, while still preserving its newest
        // atomic sample on the next main-run-loop turn.
        if let deferredSnapshot = nextSnapshot ?? pendingMinimizationSnapshot {
            pendingMinimizationSnapshot = nil
            DispatchQueue.main.async { [weak self] in
                self?.publishMinimizationSnapshot(deferredSnapshot)
            }
        }
    }

    /// Replaces only the compact content tree while preserving the framework-
    /// owned glass and expanded/shared transition hosts. Both compact
    /// endpoints remain direct siblings in the glass `contentView` for the
    /// duration of an optional crossfade.
    private func replaceCollapsedAccessoryContent(
        old: TabBarAccessoryView,
        new: TabBarAccessoryView,
        in contentView: UIView,
        animated: Bool,
        generation: Int
    ) {
        // Retire a stale content crossfade before beginning the next one. This
        // keeps rapid A -> B -> C replacement to exactly two content endpoints
        // inside the same single glass surface.
        for subview in contentView.subviews {
            guard let accessorySubview = subview as? TabBarAccessoryView,
                  accessorySubview !== old else {
                continue
            }
            accessorySubview.layer.removeAllAnimations()
            accessorySubview.removeFromSuperview()
        }
        old.layer.removeAllAnimations()
        old.alpha = 1
        old.isUserInteractionEnabled = false
        old.accessibilityElementsHidden = true

        new.layer.removeAllAnimations()
        new.translatesAutoresizingMaskIntoConstraints = true
        new.autoresizingMask = []
        new.frame = old.frame
        new.alpha = animated ? 0 : 1
        new.isHidden = false
        new.isUserInteractionEnabled = true
        new.accessibilityElementsHidden = false
        contentView.addSubview(new)

        guard animated else {
            old.removeFromSuperview()
            return
        }

        UIView.animate(
            withDuration: Self.bottomBarAccessoryCrossfadeDuration,
            delay: 0,
            options: [
                .beginFromCurrentState,
                .allowUserInteraction,
                .curveEaseInOut
            ],
            animations: {
                old.alpha = 0
                new.alpha = 1
            },
            completion: { [weak self, weak old, weak new] _ in
                old?.removeFromSuperview()
                guard let self,
                      let new,
                      self.bottomBarAccessoryTransitionGeneration == generation,
                      self._bottomBarAccessory === new else {
                    return
                }
                new.alpha = 1
                new.isUserInteractionEnabled = true
                new.accessibilityElementsHidden = false
            }
        )
    }

    private func installBottomBarAccessory(old: TabBarAccessoryView?, new: TabBarAccessoryView?, animated: Bool) {
        bottomBarAccessoryTransitionGeneration += 1
        let transitionGeneration = bottomBarAccessoryTransitionGeneration

        // An earlier animated removal may still be rendering even though
        // `bottomBarAccessoryWrapper` already points elsewhere (or is nil).
        // Retire it before installing the next surface so there is never an
        // outgoing glass behind a newly-created one.
        if let outgoingWrapper = bottomBarAccessoryOutgoingWrapper {
            outgoingWrapper.layer.removeAllAnimations()
            Self.clearOwnedTransitionBlur(from: outgoingWrapper.layer)
            outgoingWrapper.alpha = 1
            outgoingWrapper.transform = .identity
            outgoingWrapper.removeFromSuperview()
            bottomBarAccessoryOutgoingWrapper = nil
            bottomBarAccessoryOutgoingVisualReservation = 0.0
        }

        // Remove listener from the outgoing accessory first so it can't
        // trigger a re-layout we're about to discard anyway.
        old?.requestLayout = { _ in }

        guard isViewLoaded else {
            old?.removeFromSuperview()
            bottomBarAccessoryPress?.isEnabled = false
            bottomBarAccessoryPress?.resetVisualState()
            bottomBarAccessoryWrapper?.removeFromSuperview()
            bottomBarAccessoryWrapper = nil
            bottomBarAccessoryTap = nil
            bottomBarAccessoryPress = nil
            bottomBarAccessoryCollapsedContentHost = nil
            bottomBarAccessoryExpandedContentHost = nil
            bottomBarAccessorySharedElementHost = nil
            bottomBarAccessoryTransitionCoordinator = nil
            bottomBarAccessoryOutgoingVisualReservation = 0.0
            publishMinimizationUpdate(accessoryFrame: nil)
            return
        }

        let oldWrapper = bottomBarAccessoryWrapper
        // Let the coordinator finish while its delegate can still resolve the
        // active wrapper/hosts. Clearing those references first makes the
        // delegate's completion guard fail and leaves the expanded controller
        // attached as an invisible child when the accessory is removed or
        // replaced directly.
        bottomBarAccessoryTransitionCoordinator?.reset(to: .collapsed)
        bottomBarAccessoryTransitionCoordinator = nil

        // A -> B reuses the active surface and its hosts. This branch runs
        // after a possible expanded session has synchronously settled, so the
        // same rule also covers replacement while Full Player is open without
        // leaking its controller or transition gesture.
        if let old,
           let new,
           let oldWrapper,
           bottomBarAccessoryCollapsedContentHost === old,
           old.superview === oldWrapper.contentView,
           let expandedHost = bottomBarAccessoryExpandedContentHost,
           let sharedElementHost = bottomBarAccessorySharedElementHost {
            replaceCollapsedAccessoryContent(
                old: old,
                new: new,
                in: oldWrapper.contentView,
                animated: animated,
                generation: transitionGeneration
            )
            bottomBarAccessoryCollapsedContentHost = new
            expandedHost.alpha = 0
            expandedHost.isUserInteractionEnabled = false
            expandedHost.accessibilityElementsHidden = true
            sharedElementHost.removeFromSuperview()
            sharedElementHost.accessibilityElementsHidden = true
            bottomBarAccessoryOutgoingWrapper = nil
            bottomBarAccessoryOutgoingVisualReservation = 0.0
            new.requestLayout = { [weak self] transition in
                self?.updateBottomBarAccessoryLayoutPreservingObservedContentOffset(
                    transition: transition
                )
            }
            if let layout = currentlyAppliedLayout {
                containerLayoutUpdated(layout, transition: .immediate)
            }
            return
        }

        if let press = bottomBarAccessoryPress {
            press.isEnabled = false
            press.resetVisualState()
            oldWrapper?.removeGestureRecognizer(press)
        }
        bottomBarAccessoryWrapper = nil
        bottomBarAccessoryTap = nil
        bottomBarAccessoryPress = nil
        bottomBarAccessoryCollapsedContentHost = nil
        bottomBarAccessoryExpandedContentHost = nil
        bottomBarAccessorySharedElementHost = nil

        let newWrapper: GlassBackgroundView?
        if let new {
            let wrapper = GlassBackgroundView(
                style: .regular,
                appearanceStyle: resolvedAppearanceStyle
            )
            wrapper.surfaceRole = .floatingSurface
            wrapper.appearanceStyleOverride = resolvedAppearanceStyle
            wrapper.glassIsInteractive = false
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
            wrapper.transitionMaterialInteractionEnabled = false
            // The compact accessory is actual glass content, not a sibling
            // overlay: callers relying on native vibrancy and hit testing
            // must observe `accessory.superview === wrapper.contentView`.
            // Full Player remains on the independent plain transition plane
            // so its backdrop is not faded with the compact glass material.
            let compactContentView = wrapper.contentView
            let expandedHost = UIView(frame: wrapper.bounds)
            let sharedElementHost = UIView(frame: view.bounds)
            expandedHost.translatesAutoresizingMaskIntoConstraints = true
            expandedHost.autoresizingMask = []
            expandedHost.backgroundColor = .clear
            expandedHost.isOpaque = false
            wrapper.transitionContentView.addSubview(expandedHost)
            sharedElementHost.translatesAutoresizingMaskIntoConstraints = true
            sharedElementHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sharedElementHost.backgroundColor = .clear
            sharedElementHost.isOpaque = false
            expandedHost.alpha = 0
            expandedHost.isUserInteractionEnabled = false
            expandedHost.accessibilityElementsHidden = true
            sharedElementHost.isUserInteractionEnabled = false
            sharedElementHost.isAccessibilityElement = false
            sharedElementHost.accessibilityElementsHidden = true

            new.translatesAutoresizingMaskIntoConstraints = true
            new.autoresizingMask = []
            new.frame = compactContentView.bounds
            new.alpha = 1
            new.isHidden = false
            new.isUserInteractionEnabled = true
            new.accessibilityElementsHidden = false
            // Mini and Full keep independent layout spaces. The accessory is
            // never reparented into the expanded controller and the full
            // controller is never laid out inside compact bounds.
            compactContentView.addSubview(new)
            view.addSubview(wrapper)
            newWrapper = wrapper
            bottomBarAccessoryCollapsedContentHost = new
            bottomBarAccessoryExpandedContentHost = expandedHost
            bottomBarAccessorySharedElementHost = sharedElementHost
            new.requestLayout = { [weak self] transition in
                self?.updateBottomBarAccessoryLayoutPreservingObservedContentOffset(
                    transition: transition
                )
            }

            // Tap on the glass surface → expand into the accessory's
            // optional companion controller (Apple-Music-style "open
            // the player"). The recognizer is always attached, but the
            // handler bails out if no provider is set, so toggling the
            // provider on and off doesn't require re-installing the
            // accessory.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleAccessoryTap(_:)))
            tap.delegate = self
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            wrapper.addGestureRecognizer(tap)
            bottomBarAccessoryTap = tap

        } else {
            newWrapper = nil
        }

        bottomBarAccessoryWrapper = newWrapper
        setBottomBarAccessoryPressEnabled(newWrapper != nil)
        if let layout = currentlyAppliedLayout, let newWrapper {
            if let frame = resolvedBottomBarAccessoryFrame(for: layout) {
                applyAccessoryFrame(newWrapper, frame: frame, transition: .immediate)
                newWrapper.isHidden = false
            } else {
                newWrapper.isHidden = true
                publishMinimizationUpdate(accessoryFrame: nil)
            }
        }

        if animated, oldWrapper != nil || newWrapper != nil {
            if let oldWrapper, oldWrapper !== newWrapper {
                bottomBarAccessoryOutgoingWrapper = oldWrapper
                bottomBarAccessoryOutgoingVisualReservation = max(
                    0.0,
                    oldWrapper.frame.height
                        + resolvedBottomBarAccessoryBottomGap
                )
            }
            let usesLiquidAccessoryCrossfade = resolvedAppearanceStyle
                .usesLiquidGlass
            if usesLiquidAccessoryCrossfade {
                newWrapper?.alpha = 0
            } else {
                // The Legacy tab-bar material has a rounded cutout for the
                // accessory's own ultra-thin effect. Keep that effect plane
                // fully opaque while an accessory appears or disappears;
                // fading the entire wrapper would expose an unblurred hole.
                // Only compact content fades, then the cutout/material swap
                // is committed atomically at the endpoint.
                newWrapper?.alpha = 1
                oldWrapper?.alpha = 1
                new?.alpha = 0
                old?.alpha = 1
            }
            newWrapper?.transform = .identity
            oldWrapper?.transform = .identity
            if usesLiquidAccessoryCrossfade {
                if let newWrapper {
                    ContainedViewLayoutTransition.immediate.setBlur(
                        layer: newWrapper.layer,
                        radius: Self.bottomBarAccessoryCrossfadeBlurRadius
                    )
                    ContainedViewLayoutTransition
                        .animated(duration: Self.bottomBarAccessoryCrossfadeDuration, curve: .easeInOut)
                        .setBlur(layer: newWrapper.layer, radius: 0.0) { [weak self, weak newWrapper] _ in
                            guard let self, let newWrapper else { return }
                            if self.bottomBarAccessoryWrapper === newWrapper,
                               self.bottomBarAccessoryTransitionGeneration == transitionGeneration {
                                Self.clearOwnedTransitionBlur(from: newWrapper.layer)
                            }
                        }
                }
                if let oldWrapper {
                    ContainedViewLayoutTransition
                        .animated(duration: Self.bottomBarAccessoryCrossfadeDuration, curve: .easeInOut)
                        .setBlur(layer: oldWrapper.layer, radius: Self.bottomBarAccessoryCrossfadeBlurRadius)
                }
            } else {
                // Classic iOS accessory swaps are alpha-only. The system
                // chrome material remains stable and no layer filter is
                // installed, even for an animated nil <-> accessory change.
                if let newWrapper {
                    Self.clearOwnedTransitionBlur(from: newWrapper.layer)
                }
                if let oldWrapper {
                    Self.clearOwnedTransitionBlur(from: oldWrapper.layer)
                }
            }
            UIView.animate(withDuration: Self.bottomBarAccessoryCrossfadeDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: {
                if usesLiquidAccessoryCrossfade {
                    oldWrapper?.alpha = 0
                    newWrapper?.alpha = 1
                } else {
                    old?.alpha = 0
                    new?.alpha = 1
                }
            }, completion: { [weak self, weak oldWrapper] _ in
                guard let oldWrapper else { return }
                if self?.bottomBarAccessoryWrapper !== oldWrapper {
                    oldWrapper.removeFromSuperview()
                }
                if let self,
                   self.bottomBarAccessoryOutgoingWrapper === oldWrapper {
                    self.bottomBarAccessoryOutgoingWrapper = nil
                    self.bottomBarAccessoryOutgoingVisualReservation = 0.0
                    if let layout = self.currentlyAppliedLayout {
                        self.containerLayoutUpdated(
                            layout,
                            transition: .immediate
                        )
                    }
                }
                oldWrapper.alpha = 1.0
                oldWrapper.transform = .identity
                Self.clearOwnedTransitionBlur(from: oldWrapper.layer)
            })
        } else {
            oldWrapper?.removeFromSuperview()
            if bottomBarAccessoryOutgoingWrapper === oldWrapper {
                bottomBarAccessoryOutgoingWrapper = nil
                bottomBarAccessoryOutgoingVisualReservation = 0.0
            }
            if let oldWrapper {
                Self.clearOwnedTransitionBlur(from: oldWrapper.layer)
            }
            newWrapper?.alpha = 1.0
            newWrapper?.transform = .identity
            if let newWrapper {
                Self.clearOwnedTransitionBlur(from: newWrapper.layer)
            }
        }

        // Re-run layout so the new accessory gets positioned (and any
        // safe-area / edge-effect changes propagate to children).
        if let layout = currentlyAppliedLayout {
            // The wrapper runs its own blur crossfade above. Keep the
            // accompanying safe-area / tab-bar relayout synchronous so
            // unchanged chrome, especially trailing search/nav buttons, does
            // not animate just because the accessory reservation changed.
            containerLayoutUpdated(layout, transition: .immediate)
        }
        if new == nil {
            publishMinimizationUpdate(accessoryFrame: nil)
        }
    }

    private func setBottomBarAccessoryPressEnabled(_ enabled: Bool) {
        let effectiveEnabled = enabled && !isTabBarScrollMinimizeArmed
        if resolvedAppearanceStyle.usesLiquidGlass {
            if bottomBarAccessoryPress == nil, let wrapper = bottomBarAccessoryWrapper {
                let press = GlassHighlightGestureRecognizer(target: nil, action: nil)
                press.motionProfile = AetherMotion.bottomBarAccessoryPress
                press.touchEffectView = wrapper
                press.highlightContainerView = wrapper.contentView
                wrapper.addGestureRecognizer(press)
                bottomBarAccessoryPress = press
            }
            bottomBarAccessoryPress?.resetVisualState()
            bottomBarAccessoryPress?.isEnabled = effectiveEnabled
            if effectiveEnabled {
                bottomBarAccessoryWrapper?.transform = .identity
            }
        } else {
            if let press = bottomBarAccessoryPress {
                press.isEnabled = false
                press.resetVisualState()
                bottomBarAccessoryWrapper?.removeGestureRecognizer(press)
                bottomBarAccessoryPress = nil
            }
        }

        // `resetVisualState()` owns the sublayer transform, but keeping the
        // wrapper's public transform exact as well makes repeated/reentrant
        // transitions insensitive to an interrupted UIKit press transaction.
        if let wrapper = bottomBarAccessoryWrapper {
            wrapper.layer.removeAnimation(
                forKey: TouchEffect.transformAnimationKey
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            wrapper.layer.sublayerTransform = isTabBarScrollMinimizeArmed
                ? CATransform3DMakeScale(
                    Self.scrollMinimizeArmedAccessoryScale,
                    Self.scrollMinimizeArmedAccessoryScale,
                    1.0
                )
                : CATransform3DIdentity
            CATransaction.commit()
            if !resolvedAppearanceStyle.usesLiquidGlass {
                wrapper.layer.removeAnimation(forKey: "opacity")
                wrapper.layer.removeAnimation(forKey: "transform")
                wrapper.alpha = 1
            }
            wrapper.transform = .identity
        }
    }

    @objc private func handleAccessoryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard let provider = _bottomBarAccessory?.expandedViewControllerProvider,
              let controller = provider() else {
            return
        }

        if let current = expandedAccessoryViewController {
            guard current === controller,
                  bottomBarAccessoryPresentationState == .settlingToCollapsed
            else {
                return
            }
            accessoryForcedCollapse = false
            if let coordinator = bottomBarAccessoryTransitionCoordinator {
                refreshBottomBarAccessoryReduceMotionStatus(on: coordinator)
                coordinator.settle(to: .expanded, initialVelocity: 0)
            }
            return
        }

        presentExpandedAccessory(controller, animated: true)
    }

    /// Frame of the expanded morphing surface in this controller's coordinate
    /// space. It is intentionally derived from the live container rather than
    /// a screen singleton so split view, rotation, and window resizing remain
    /// valid.
    private func expandedAccessoryFrame() -> CGRect {
        view.bounds
    }

    private func currentCollapsedAccessoryFrame(
        wrapper: GlassBackgroundView
    ) -> CGRect? {
        if let presentation = wrapper.layer.presentation() {
            let frame = presentation.frame
            if frame.width > 0, frame.height > 0,
               frame.origin.x.isFinite, frame.origin.y.isFinite {
                return frame
            }
        }
        if wrapper.frame.width > 0, wrapper.frame.height > 0,
           wrapper.frame.origin.x.isFinite, wrapper.frame.origin.y.isFinite {
            return wrapper.frame
        }
        if let layout = currentlyAppliedLayout {
            return resolvedBottomBarAccessoryFrame(
                for: layout,
                whileExpanded: true
            )
        }
        return nil
    }

    private func makeAccessoryTransitionGeometry(
        collapsedFrame: CGRect
    ) -> BottomBarAccessoryTransitionGeometry? {
        let expandedFrame = expandedAccessoryFrame()
        guard collapsedFrame.width > 0,
              collapsedFrame.height > 0,
              expandedFrame.width > 0,
              expandedFrame.height > 0 else {
            return nil
        }

        let safeInsets = currentlyAppliedLayout?.safeInsets
            ?? view.safeAreaInsets
        return BottomBarAccessoryTransitionGeometry(
            collapsedFrame: collapsedFrame,
            expandedFrame: expandedFrame,
            collapsedCornerRadius: resolvedBottomBarAccessoryCornerRadius(
                for: collapsedFrame.size
            ),
            expandedCornerRadius: 0,
            safeInsets: safeInsets,
            layoutSize: view.bounds.size
        )
    }

    private func prepareExpandedAccessoryController(
        _ controller: UIViewController,
        expandedHost: UIView,
        geometry: BottomBarAccessoryTransitionGeometry
    ) -> Bool {
        guard controller.parent == nil else { return false }

        expandedHost.frame = CGRect(
            origin: .zero,
            size: geometry.expandedFrame.size
        )
        controller.loadViewIfNeeded()
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        controller.view.autoresizingMask = []
        controller.view.frame = expandedHost.bounds
        controller.view.layer.cornerCurve = .continuous
        controller.view.clipsToBounds = false

        addChild(controller)
        expandedHost.addSubview(controller.view)
        controller.didMove(toParent: self)
        accessoryControllerAttachedByExpansion = true

        if let aetherController = controller as? AetherViewController,
           let layout = currentlyAppliedLayout {
            aetherController.containerLayoutUpdated(
                ContainerViewLayout(
                    size: geometry.expandedFrame.size,
                    metrics: layout.metrics,
                    safeInsets: layout.safeInsets,
                    additionalInsets: layout.additionalInsets,
                    statusBarHeight: layout.statusBarHeight,
                    inputHeight: layout.inputHeight,
                    inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
                    inVoiceOver: layout.inVoiceOver
                ),
                transition: .immediate
            )
        } else {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
        return true
    }

    private func installAccessoryDismissGesture(
        on wrapper: GlassBackgroundView
    ) {
        if let current = accessoryDismissGesture {
            wrapper.removeGestureRecognizer(current)
        }

        let gesture = InteractiveTransitionGestureRecognizer(
            target: self,
            action: #selector(handleAccessoryDismissGesture(_:)),
            allowedDirections: { [weak self] _ in
                guard self?.expandedAccessoryViewController != nil else {
                    return []
                }
                return [.down]
            }
        )
        gesture.delegate = self
        gesture.maximumNumberOfTouches = 1
        wrapper.addGestureRecognizer(gesture)
        accessoryDismissGesture = gesture
    }

    /// Expands the framework-owned glass surface while keeping compact and
    /// expanded UI in independent layout spaces. The expanded controller is
    /// fully laid out before the first sample; the coordinator only changes
    /// surface position/bounds/radius and participant choreography.
    public func presentExpandedAccessory(
        _ controller: UIViewController,
        animated: Bool = true
    ) {
        guard isViewLoaded,
              !tabBarView.isSearchActive,
              presentedSearchController == nil,
              let wrapper = bottomBarAccessoryWrapper,
              let accessory = _bottomBarAccessory,
              let collapsedHost = bottomBarAccessoryCollapsedContentHost,
              collapsedHost === accessory,
              let expandedHost = bottomBarAccessoryExpandedContentHost,
              let sharedElementHost = bottomBarAccessorySharedElementHost
        else {
            return
        }

        // Full Player takes exclusive ownership of the reusable accessory
        // surface. Settle any scroll-arming preview before sampling the compact
        // source frame so its +4pt inset/scale cannot leak into the Full
        // session's canonical docking geometry.
        cancelScrollMinimizeArming(transition: .immediate)

        if let current = expandedAccessoryViewController {
            guard current === controller else { return }
            accessoryForcedCollapse = false
            if animated {
                if let coordinator = bottomBarAccessoryTransitionCoordinator {
                    refreshBottomBarAccessoryReduceMotionStatus(on: coordinator)
                    coordinator.settle(to: .expanded, initialVelocity: 0)
                }
            } else {
                bottomBarAccessoryTransitionCoordinator?.reset(to: .expanded)
            }
            return
        }

        // Expansion owns and reparents the supplied controller's view. Never
        // steal a current tab, presented Search child, or a controller owned
        // by another hierarchy: teardown could not restore that foreign host.
        guard controller.parent == nil else { return }

        view.layoutIfNeeded()
        guard let visualCollapsedFrame = currentCollapsedAccessoryFrame(
            wrapper: wrapper
        ) else {
            // A temporarily missing docking slot is not a valid zero target.
            // The next layout/tap can retry once chrome geometry exists.
            return
        }

        let sampledCollapsedCornerRadius = wrapper.layer.presentation()?.cornerRadius
            ?? wrapper.layer.cornerRadius

        // Full Player becomes the sole owner of wrapper geometry. Commit the
        // exact visual source, then detach the compact clock so its last sample
        // cannot overwrite the expansion coordinator.
        if tabBarMinimizeAnimation?.accessoryTargetFrame != nil {
            cancelAccessoryCompactMorph(wrapper: wrapper)
        }
        if var animation = tabBarMinimizeAnimation {
            // Keep sampling the pill itself to its exact logical endpoint,
            // but detach the accessory geometry: Full Player becomes that
            // surface's sole owner from this frame onward.
            animation.accessorySourceFrame = nil
            animation.accessoryTargetFrame = nil
            tabBarMinimizeAnimation = animation
            accessoryFrameObservation = nil
            ensureAccessoryCompactMorphDisplayLink()
        } else if accessoryFrameObservation != nil {
            accessoryFrameObservation = nil
            invalidateAccessoryCompactMorphDisplayLinkIfIdle()
        }
        pendingAccessoryCompactMorphDirection = nil

        let dockingContext = BottomBarAccessoryDockingContext(
            mode: isTabBarMinimized ? .inline : .regular,
            isTabBarVisible: effectiveTabBarHiddenProgress < 0.999,
            isSearchActive: tabBarView.isSearchActive
        )
        let canonicalCollapsedFrame = currentlyAppliedLayout.flatMap { layout in
            resolvedBottomBarAccessoryFrame(
                for: layout,
                dockingContext: dockingContext
            )
        } ?? visualCollapsedFrame
        guard let geometry = makeAccessoryTransitionGeometry(
            collapsedFrame: canonicalCollapsedFrame
        ) else { return }
        let initialSurfaceGeometry = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(
                x: visualCollapsedFrame.midX,
                y: visualCollapsedFrame.midY
            ),
            bounds: CGRect(origin: .zero, size: visualCollapsedFrame.size),
            cornerRadius: sampledCollapsedCornerRadius > 0.001
                ? max(
                    0.0,
                    min(
                        sampledCollapsedCornerRadius,
                        visualCollapsedFrame.height / 2.0
                    )
                )
                : geometry.collapsedCornerRadius
        )
        // A tap can still have the compact press-release spring in flight.
        // Commit its exact rest state before the morph takes geometry
        // ownership so the two animations cannot add together.
        setBottomBarAccessoryPressEnabled(false)

        accessoryPresentationSession = AccessoryPresentationSession(
            dockingContext: dockingContext,
            sourceCollapsedFrame: geometry.collapsedFrame,
            wasTabBarMinimized: isTabBarMinimized,
            wasTabBarHidden: tabBarHidden,
            tabBarHiddenProgress: effectiveTabBarHiddenProgress,
            wasSearchActive: tabBarView.isSearchActive,
            resolvedLayoutSize: geometry.layoutSize,
            resolvedSafeInsets: geometry.safeInsets
        )

        expandedAccessoryViewController = controller
        accessoryTransitionGeometry = geometry
        accessoryForcedCollapse = false
        accessoryPresentationProgress = 0
        sharedElementHost.frame = CGRect(
            origin: .zero,
            size: geometry.expandedFrame.size
        )
        sharedElementHost.removeFromSuperview()
        view.addSubview(sharedElementHost)

        guard prepareExpandedAccessoryController(
            controller,
            expandedHost: expandedHost,
            geometry: geometry
        ) else {
            setBottomBarAccessoryPressEnabled(true)
            sharedElementHost.removeFromSuperview()
            sharedElementHost.accessibilityElementsHidden = true
            expandedAccessoryViewController = nil
            accessoryTransitionGeometry = nil
            accessoryPresentationSession = nil
            return
        }

        detachScrollObserver()
        // Native interactive glass must only own touches while it is the
        // stable compact endpoint. Letting the same UIGlassEffect receive a
        // fullscreen dismiss pan leaves its large elastic deformation alive
        // when the surface becomes a 48pt Mini again, which makes the next
        // tap/stretch jump dramatically. The expanded subtree still receives
        // the touch and the wrapper's ancestor dismiss recognizer continues
        // to observe it.
        wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
        wrapper.transitionMaterialInteractionEnabled = false
        installAccessoryDismissGesture(on: wrapper)
        wrapper.layer.cornerCurve = .continuous
        wrapper.beginInteractiveGeometryUpdates()
        view.bringSubviewToFront(wrapper)
        view.bringSubviewToFront(sharedElementHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: view,
            surfaceView: wrapper,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedElementHost,
            configuration: bottomBarAccessoryTransitionConfiguration
        )
        coordinator.delegate = self
        bottomBarAccessoryTransitionCoordinator = coordinator

        let didBegin = coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: dockingContext,
            collapsedParticipant: accessory as? BottomBarAccessoryTransitionParticipant,
            expandedParticipant: controller as? BottomBarAccessoryTransitionParticipant,
            reduceMotion: bottomBarAccessoryReduceMotionStatusProvider(),
            initialSurfaceGeometry: initialSurfaceGeometry
        )
        guard didBegin else {
            teardownExpandedAccessoryController(controller)
            sharedElementHost.removeFromSuperview()
            wrapper.endInteractiveGeometryUpdates(
                size: geometry.collapsedFrame.size,
                cornerRadius: geometry.collapsedCornerRadius
            )
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
            wrapper.transitionMaterialInteractionEnabled = false
            setBottomBarAccessoryPressEnabled(true)
            bottomBarAccessoryTransitionCoordinator = nil
            expandedAccessoryViewController = nil
            accessoryTransitionGeometry = nil
            accessoryPresentationSession = nil
            return
        }

        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if !animated {
            coordinator.reset(to: .expanded)
        }

        // Compact geometry is intentionally unavailable while the Full
        // coordinator owns the reusable surface. Progress may still finish an
        // interrupted tab-pill morph; Full geometry has its own participant
        // callback and must not leak into this compact delegate. Publish last:
        // the delegate may synchronously dismiss or replace this session.
        publishMinimizationUpdate(accessoryFrame: nil)
    }

    /// Retargets the single active coordinator. A call during a drag records a
    /// forced model target but leaves the card under the finger until release.
    @discardableResult
    public func dismissExpandedAccessory(
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> Bool {
        guard let controller = expandedAccessoryViewController else {
            return false
        }
        if let completion {
            accessoryDismissCompletions.append(completion)
            accessoryForcedCollapse = true
        }

        guard let coordinator = bottomBarAccessoryTransitionCoordinator else {
            teardownExpandedAccessoryController(controller)
            completion?()
            return true
        }

        if coordinator.state == .dragging {
            return true
        }
        if animated {
            refreshBottomBarAccessoryReduceMotionStatus(on: coordinator)
            coordinator.settle(to: .collapsed, initialVelocity: 0)
        } else {
            coordinator.reset(to: .collapsed)
        }
        return true
    }

    private func teardownExpandedAccessoryController(
        _ controller: UIViewController
    ) {
        if accessoryControllerAttachedByExpansion {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        } else {
            controller.view.removeFromSuperview()
        }
        accessoryControllerAttachedByExpansion = false
    }

    /// Restores the chrome snapshot before normal collapsed layout and scroll
    /// observation resume. Public mutation entry points are frozen while full,
    /// so the assignments are normally idempotent; keeping this explicit also
    /// makes interruption/removal cleanup deterministic.
    private func restoreAccessoryPresentationSession(
        _ session: AccessoryPresentationSession
    ) {
        if tabBarView.isSearchActive != session.wasSearchActive {
            if session.wasSearchActive {
                tabBarView.activateSearchMode(animated: false)
            } else {
                tabBarView.deactivateSearchMode(animated: false)
            }
        }

        let restoredMinimized = session.wasTabBarMinimized
            && appliedTabBarTheme.appearanceStyle.usesLiquidGlass
        if isTabBarMinimized != restoredMinimized {
            isTabBarMinimized = restoredMinimized
            tabBarView.setMinimized(
                restoredMinimized,
                transition: .immediate
            )
        }
        tabBarMinimizationProgress = restoredMinimized ? 1.0 : 0.0
        tabBarMinimizeAnimation = nil
        accessoryFrameObservation = nil
        invalidateAccessoryCompactMorphDisplayLink()

        tabBarVisibilityTransitionState = nil
        tabBarHidden = session.wasTabBarHidden
        tabBarVisibilityAnimationGeneration += 1
        invalidateTabBarVisibilityDisplayLink()
        tabBarVisibilityContentAnimation = nil
        isLegacyTabBarVisibilityAlphaAnimating = false
        isFinalizingTabBarVisibilityContentAnimation = false
        applyTabBarVisibilityVisualHiddenProgress(
            session.tabBarHiddenProgress
        )
    }

    private var shouldDelegateSystemChromeToExpandedAccessory: Bool {
        expandedAccessoryViewController != nil
            && accessoryUsesExpandedSystemChrome
    }

    open override var childForStatusBarStyle: UIViewController? {
        shouldDelegateSystemChromeToExpandedAccessory
            ? expandedAccessoryViewController
            : super.childForStatusBarStyle
    }

    open override var childForStatusBarHidden: UIViewController? {
        shouldDelegateSystemChromeToExpandedAccessory
            ? expandedAccessoryViewController
            : super.childForStatusBarHidden
    }

    open override var childForHomeIndicatorAutoHidden: UIViewController? {
        accessoryPresentationProgress >= 0.85
            ? (expandedAccessoryViewController
                ?? super.childForHomeIndicatorAutoHidden)
            : super.childForHomeIndicatorAutoHidden
    }

    private var tabBarHidden: Bool = false
    private struct TabBarVisibilityTransitionState {
        let direction: NavigationTransitionDirection
        let sourceHidden: Bool
        let targetHidden: Bool
        let isInteractive: Bool
        var progress: CGFloat
        var resolvedCompleted: Bool?
    }
    private var tabBarVisibilityTransitionState: TabBarVisibilityTransitionState?

    internal struct TabBarVisibilityContentTiming: Equatable {
        let duration: TimeInterval
        let delay: TimeInterval
    }

    private struct TabBarVisibilityContentAnimation {
        let generation: Int
        let fromHiddenProgress: CGFloat
        let toHiddenProgress: CGFloat
        let timing: TabBarVisibilityContentTiming
        var elapsed: TimeInterval
    }

    /// Visual state is intentionally independent from navigation progress.
    /// The screen coordinator continues to own push/pop geometry while the
    /// tab chrome uses one fixed blur+fade clock (the same contract as a
    /// custom navbar titleView). This also keeps an interactive pop velocity
    /// from compressing the chrome hand-off.
    private var tabBarVisibilityVisualHiddenProgress: CGFloat = 0.0
    private var tabBarVisibilityContentAnimation: TabBarVisibilityContentAnimation?
    private var tabBarVisibilityDisplayLink: CADisplayLink?
    private var tabBarVisibilityDisplayLinkTarget: TabBarVisibilityDisplayLinkTarget?
    private var tabBarVisibilityLastTimestamp: CFTimeInterval?
    private var tabBarVisibilityAnimationGeneration: Int = 0
    private var isFinalizingTabBarVisibilityContentAnimation = false
    private var isLegacyTabBarVisibilityAlphaAnimating = false
    private var tabBarVisibilityBlurFilter: NSObject?
    private var bottomAccessoryVisibilityBlurFilter: NSObject?
    private weak var bottomAccessoryVisibilityBlurLayer: CALayer?
    private var tabBarVisibilityCurrentBlurRadius: CGFloat = 0.0
    private var lastTabBarVisibilityContentTiming: TabBarVisibilityContentTiming?
    private var lastTabBarVisibilityContentWasInteractive = false
    private var lastTabBarVisibilityContentDirection: NavigationTransitionDirection?

    internal static func tabBarVisibilityContentTiming(
        direction: NavigationTransitionDirection,
        isInteractive: Bool
    ) -> TabBarVisibilityContentTiming {
        // Keep the tab-bar blur/fade on the same fixed clock as navbar chrome.
        // Deriving both duration and push phase from AetherMotion keeps their
        // endpoints aligned when the shared production profile changes.
        let duration = max(0.01, AetherMotion.navigationChrome.contentAppearanceDuration)
        let pushDelay = max(0.0, AetherMotion.navigation.duration - duration)
        return TabBarVisibilityContentTiming(
            duration: duration,
            delay: !isInteractive && direction == .push ? pushDelay : 0.0
        )
    }

    internal var tabBarVisibilityContentTimingForTesting: TabBarVisibilityContentTiming? {
        lastTabBarVisibilityContentTiming
    }

    internal var tabBarVisibilityContentIsInteractiveForTesting: Bool {
        lastTabBarVisibilityContentWasInteractive
    }

    internal var tabBarVisibilityContentDirectionForTesting: NavigationTransitionDirection? {
        lastTabBarVisibilityContentDirection
    }

    internal var tabBarVisibilityVisualHiddenProgressForTesting: CGFloat {
        tabBarVisibilityVisualHiddenProgress
    }

    internal var tabBarVisibilityBlurRadiusForTesting: CGFloat {
        tabBarVisibilityCurrentBlurRadius
    }

    internal var tabBarVisibilityAlphaForTesting: CGFloat {
        tabBarView.alpha
    }

    internal var tabBarVisibilityTransformForTesting: CGAffineTransform {
        tabBarView.transform
    }

    internal var isTabBarVisibilityContentAnimatingForTesting: Bool {
        tabBarVisibilityContentAnimation != nil || isLegacyTabBarVisibilityAlphaAnimating
    }

    internal var isTabBarVisibilityDisplayLinkActiveForTesting: Bool {
        tabBarVisibilityDisplayLink != nil
    }

    internal var hasOwnedTabBarVisibilityBlurFilterForTesting: Bool {
        tabBarVisibilityBlurFilter != nil || bottomAccessoryVisibilityBlurFilter != nil
    }

    private var effectiveTabBarHiddenProgress: CGFloat {
        tabBarVisibilityVisualHiddenProgress
    }

    private var isTabBarVisibilityContentAnimationActive: Bool {
        tabBarVisibilityContentAnimation != nil
            || isFinalizingTabBarVisibilityContentAnimation
            || isLegacyTabBarVisibilityAlphaAnimating
    }

    private func invalidateTabBarVisibilityDisplayLink() {
        tabBarVisibilityDisplayLink?.invalidate()
        tabBarVisibilityDisplayLink = nil
        tabBarVisibilityDisplayLinkTarget = nil
        tabBarVisibilityLastTimestamp = nil
    }

    private static func updateManagedVisibilityBlurFilter(
        _ filter: inout NSObject?,
        on layer: CALayer,
        radius: CGFloat
    ) {
        #if APPSTORE_SAFE
        // Layer-level blur has no public API. Safe builds keep the existing
        // system-material chrome and remove only a filter retained by this
        // controller from an earlier configuration.
        if let filter {
            layer.filters = (layer.filters ?? []).filter { candidate in
                (candidate as AnyObject) !== filter
            }
        }
        filter = nil
        #else
        let resolvedRadius = max(0.0, radius)
        if resolvedRadius <= 0.001 {
            if let filter {
                layer.filters = (layer.filters ?? []).filter { candidate in
                    (candidate as AnyObject) !== filter
                }
            }
            filter = nil
            return
        }

        if filter == nil {
            filter = CALayer.blur()
        }
        guard let filter else {
            return
        }

        filter.setValue(resolvedRadius as NSNumber, forKey: ObfuscatedSymbols.filterRadiusKey)
        var filters = layer.filters ?? []
        if !filters.contains(where: { candidate in
            (candidate as AnyObject) === filter
        }) {
            filters.append(filter)
        }
        layer.filters = filters
        #endif
    }

    private func clearLegacyVisibilityBlurState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        Self.updateManagedVisibilityBlurFilter(
            &tabBarVisibilityBlurFilter,
            on: tabBarView.layer,
            radius: 0.0
        )
        if let accessoryLayer = bottomAccessoryVisibilityBlurLayer {
            Self.updateManagedVisibilityBlurFilter(
                &bottomAccessoryVisibilityBlurFilter,
                on: accessoryLayer,
                radius: 0.0
            )
        }
        bottomAccessoryVisibilityBlurFilter = nil
        bottomAccessoryVisibilityBlurLayer = nil
        tabBarVisibilityCurrentBlurRadius = 0.0
        if let wrapper = bottomBarAccessoryWrapper {
            Self.clearOwnedTransitionBlur(from: wrapper.layer)
        }
        if let outgoingWrapper = bottomBarAccessoryOutgoingWrapper {
            Self.clearOwnedTransitionBlur(from: outgoingWrapper.layer)
        }
        CATransaction.commit()
    }

    private func updateTabBarVisibilityBlur(hiddenProgress: CGFloat) {
        guard resolvedAppearanceStyle.usesLiquidGlass else {
            clearLegacyVisibilityBlurState()
            return
        }
        let radius = max(0.0, min(1.0, hiddenProgress))
            * AetherMotion.navigationChrome.contentBlurRadius
        tabBarVisibilityCurrentBlurRadius = radius

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        Self.updateManagedVisibilityBlurFilter(
            &tabBarVisibilityBlurFilter,
            on: tabBarView.layer,
            radius: radius
        )

        let accessoryLayer = expandedAccessoryViewController == nil
            ? bottomBarAccessoryWrapper?.layer
            : nil
        if bottomAccessoryVisibilityBlurLayer !== accessoryLayer {
            if let oldLayer = bottomAccessoryVisibilityBlurLayer {
                Self.updateManagedVisibilityBlurFilter(
                    &bottomAccessoryVisibilityBlurFilter,
                    on: oldLayer,
                    radius: 0.0
                )
            }
            bottomAccessoryVisibilityBlurLayer = accessoryLayer
        }
        if let accessoryLayer {
            Self.updateManagedVisibilityBlurFilter(
                &bottomAccessoryVisibilityBlurFilter,
                on: accessoryLayer,
                radius: radius
            )
        }
        CATransaction.commit()
    }

    private func applyTabBarVisibilityVisualHiddenProgress(_ progress: CGFloat) {
        let hiddenProgress = max(0.0, min(1.0, progress))
        tabBarVisibilityVisualHiddenProgress = hiddenProgress
        let visibleProgress = 1.0 - hiddenProgress

        tabBarView.alpha = visibleProgress
        tabBarView.isUserInteractionEnabled = visibleProgress > 0.01
        if expandedAccessoryViewController == nil, let wrapper = bottomBarAccessoryWrapper {
            wrapper.alpha = (tabBarView.isSearchActive ? 0.0 : 1.0) * visibleProgress
        }
        updateTabBarVisibilityBlur(hiddenProgress: hiddenProgress)
    }

    private func startTabBarVisibilityContentAnimation(
        toHidden hidden: Bool,
        direction: NavigationTransitionDirection,
        isInteractive: Bool,
        timing: TabBarVisibilityContentTiming? = nil
    ) {
        tabBarVisibilityAnimationGeneration += 1
        let generation = tabBarVisibilityAnimationGeneration
        invalidateTabBarVisibilityDisplayLink()

        let resolvedTiming = timing ?? Self.tabBarVisibilityContentTiming(
            direction: direction,
            isInteractive: isInteractive
        )
        lastTabBarVisibilityContentTiming = resolvedTiming
        lastTabBarVisibilityContentWasInteractive = isInteractive
        lastTabBarVisibilityContentDirection = direction

        let fromProgress = tabBarVisibilityVisualHiddenProgress
        let toProgress: CGFloat = hidden ? 1.0 : 0.0
        guard abs(fromProgress - toProgress) > 0.001 else {
            tabBarVisibilityContentAnimation = nil
            isLegacyTabBarVisibilityAlphaAnimating = false
            applyTabBarVisibilityVisualHiddenProgress(toProgress)
            return
        }

        if !resolvedAppearanceStyle.usesLiquidGlass {
            // In Legacy the system material itself stays constant. UIKit owns
            // the alpha interpolation; the Liquid-only display-link/filter
            // clock is not retained or sampled.
            tabBarVisibilityContentAnimation = nil
            clearLegacyVisibilityBlurState()
            isLegacyTabBarVisibilityAlphaAnimating = true
            UIView.animate(
                withDuration: resolvedTiming.duration,
                delay: resolvedTiming.delay,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: { [weak self] in
                    self?.applyTabBarVisibilityVisualHiddenProgress(toProgress)
                },
                completion: { [weak self] _ in
                    guard let self,
                          self.tabBarVisibilityAnimationGeneration == generation else {
                        return
                    }
                    self.isLegacyTabBarVisibilityAlphaAnimating = false
                    self.applyTabBarVisibilityVisualHiddenProgress(toProgress)
                    if let layout = self.currentlyAppliedLayout {
                        self.containerLayoutUpdated(layout, transition: .immediate)
                    }
                }
            )
            return
        }

        isLegacyTabBarVisibilityAlphaAnimating = false

        tabBarVisibilityContentAnimation = TabBarVisibilityContentAnimation(
            generation: generation,
            fromHiddenProgress: fromProgress,
            toHiddenProgress: toProgress,
            timing: resolvedTiming,
            elapsed: 0.0
        )

        let target = TabBarVisibilityDisplayLinkTarget()
        target.tick = { [weak self] displayLink in
            self?.handleTabBarVisibilityDisplayLink(displayLink)
        }
        let displayLink = CADisplayLink(target: target, selector: #selector(TabBarVisibilityDisplayLinkTarget.handleDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            let screenMaximum = view.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
            let preferred = Float(min(120, max(60, screenMaximum > 0 ? screenMaximum : 120)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60.0,
                maximum: preferred,
                preferred: preferred
            )
        }
        tabBarVisibilityDisplayLinkTarget = target
        tabBarVisibilityDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    private func handleTabBarVisibilityDisplayLink(_ displayLink: CADisplayLink) {
        let timestamp = displayLink.targetTimestamp > displayLink.timestamp
            ? displayLink.targetTimestamp
            : displayLink.timestamp
        let delta: CFTimeInterval
        if let lastTimestamp = tabBarVisibilityLastTimestamp {
            delta = min(max(0.0, timestamp - lastTimestamp), 1.0 / 30.0)
        } else {
            delta = displayLink.duration > 0.0 ? displayLink.duration : 1.0 / 60.0
        }
        tabBarVisibilityLastTimestamp = timestamp
        _ = advanceTabBarVisibilityContentAnimation(by: delta)
    }

    @discardableResult
    private func advanceTabBarVisibilityContentAnimation(by delta: TimeInterval) -> Bool {
        guard var animation = tabBarVisibilityContentAnimation,
              animation.generation == tabBarVisibilityAnimationGeneration else {
            return true
        }

        animation.elapsed += max(0.0, delta)
        tabBarVisibilityContentAnimation = animation
        let activeElapsed = animation.elapsed - animation.timing.delay
        guard activeElapsed >= 0.0 else {
            applyTabBarVisibilityVisualHiddenProgress(animation.fromHiddenProgress)
            return false
        }

        let linearProgress = min(1.0, activeElapsed / max(0.001, animation.timing.duration))
        // Quintic smootherstep keeps velocity *and acceleration* at zero at
        // both ends, so the glass fades/defocuses without a perceptible start
        // or stop while preserving the same midpoint and total duration.
        let easedProgress = linearProgress * linearProgress * linearProgress
            * (linearProgress * (linearProgress * 6.0 - 15.0) + 10.0)
        let hiddenProgress = animation.fromHiddenProgress
            + (animation.toHiddenProgress - animation.fromHiddenProgress) * easedProgress
        applyTabBarVisibilityVisualHiddenProgress(hiddenProgress)

        guard linearProgress >= 1.0 else {
            return false
        }

        invalidateTabBarVisibilityDisplayLink()
        tabBarVisibilityContentAnimation = nil
        isFinalizingTabBarVisibilityContentAnimation = true
        applyTabBarVisibilityVisualHiddenProgress(animation.toHiddenProgress)
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
        isFinalizingTabBarVisibilityContentAnimation = false
        return true
    }

    internal func advanceTabBarVisibilityContentAnimationForTesting(by delta: TimeInterval) {
        _ = advanceTabBarVisibilityContentAnimation(by: delta)
    }

    private func setTabBarVisibilityContentImmediately(hidden: Bool) {
        tabBarVisibilityAnimationGeneration += 1
        invalidateTabBarVisibilityDisplayLink()
        tabBarVisibilityContentAnimation = nil
        isLegacyTabBarVisibilityAlphaAnimating = false
        applyTabBarVisibilityVisualHiddenProgress(hidden ? 1.0 : 0.0)
    }

    /// Layout reservation for `hidesBottomBarWhenPushed`.
    ///
    /// The tab bar's visual hide/show is interactive, but mutating
    /// `additionalSafeAreaInsets` on every navigation-progress tick causes
    /// UIKit to re-enter the child navigation controller while its own push/pop
    /// coordinator is still installing frames. Non-interactive transitions
    /// switch the parent safe-area reservation to the target immediately so
    /// the incoming controller never receives a first layout pass with the
    /// source tab-bar inset. Interactive transitions stay on the source value
    /// until the gesture resolves, preserving cancel-without-relayout behavior.
    private var tabBarLayoutVisibleProgress: CGFloat {
        if let state = tabBarVisibilityTransitionState {
            let hidden: Bool
            if state.isInteractive, state.resolvedCompleted == nil {
                hidden = state.sourceHidden
            } else if let resolvedCompleted = state.resolvedCompleted {
                hidden = resolvedCompleted ? state.targetHidden : state.sourceHidden
            } else {
                hidden = state.targetHidden
            }
            return hidden ? 0.0 : 1.0
        }
        return tabBarHidden ? 0.0 : 1.0
    }

    private struct BottomBarLayoutReservation {
        let tabBarContentInset: CGFloat
        let accessoryTotalReservation: CGFloat
        let accessoryHeight: CGFloat

        var total: CGFloat {
            return tabBarContentInset + accessoryTotalReservation
        }
    }

    private func bottomBarLayoutReservation(visibleProgress: CGFloat, rawSafeBottom: CGFloat) -> BottomBarLayoutReservation {
        let tabBarHeight = resolvedTabBarHeight(rawSafeBottom: rawSafeBottom)
        let tabBarContentInset = visibleProgress * max(0.0, tabBarHeight - rawSafeBottom)
        let accessoryHeight: CGFloat = (!isTabBarMinimized && !tabBarView.isSearchActive)
            ? resolvedBottomBarAccessoryHeight(_bottomBarAccessory)
            : 0
        let accessoryTotalReservation: CGFloat = accessoryHeight > 0
            ? visibleProgress * (
                accessoryHeight + resolvedBottomBarAccessoryBottomGap
            )
            : 0

        return BottomBarLayoutReservation(
            tabBarContentInset: tabBarContentInset,
            accessoryTotalReservation: accessoryTotalReservation,
            accessoryHeight: accessoryHeight
        )
    }

    private func resolvedInlineAccessoryFrame(
        layoutWidth: CGFloat,
        pillTopInController: CGFloat
    ) -> CGRect {
        let pillSize = TabBarView.minimizedButtonSize
        let sideInset = max(0.0, appliedTabBarTheme.minimizedSideInset)
        let interGap = max(0.0, appliedTabBarTheme.minimizedInterItemSpacing)
        let accessoryX = sideInset + pillSize + interGap
        let accessoryRight = layoutWidth - sideInset - pillSize - interGap
        return CGRect(
            x: accessoryX,
            y: pillTopInController,
            width: max(0.0, accessoryRight - accessoryX),
            height: pillSize
        )
    }

    /// Preview geometry is deliberately independent from the logical compact
    /// state. Insetting only the rendered chrome keeps the child's safe-area
    /// reservation byte-for-byte identical throughout the arming interval.
    private func resolvedScrollMinimizeArmedAccessoryFrame(
        _ frame: CGRect
    ) -> CGRect {
        guard isTabBarScrollMinimizeArmed, !isTabBarMinimized else {
            return frame
        }
        let inset = Self.scrollMinimizeArmedHorizontalInset
            * max(0.0, min(1.0, tabBarScrollMinimizeArmingProgress))
        return CGRect(
            x: frame.minX + inset,
            y: frame.minY,
            width: max(0.0, frame.width - inset * 2.0),
            height: frame.height
        )
    }

    /// The safe-area contribution inherited from the window / parent,
    /// excluding the reservation written by this controller itself.
    ///
    /// Reading `window.safeAreaInsets.bottom` is not sufficient for a root
    /// controller: UIKit can reflect the root controller's own
    /// `additionalSafeAreaInsets` back through the window while it is laying
    /// the hierarchy out. Feeding that value into the next reservation pass
    /// makes the inset oscillate between zero and the full tab-bar height.
    private var inheritedSafeAreaBottom: CGFloat {
        max(0.0, view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
    }

    private func resolvedTabBarHeight(rawSafeBottom: CGFloat) -> CGFloat {
        if appliedTabBarTheme.appearanceStyle == .legacy {
            return TabBarView.LegacyLayout.totalHeight(bottomSafeAreaInset: rawSafeBottom)
        }
        return TabBarView.defaultHeight
    }

    private func resolvedBottomBarAccessoryFrame(
        for layout: ContainerViewLayout,
        whileExpanded: Bool = false
    ) -> CGRect? {
        guard whileExpanded || expandedAccessoryViewController == nil else {
            return nil
        }
        guard _bottomBarAccessory != nil else {
            return nil
        }

        let chromeVisibleProgress = 1.0 - effectiveTabBarHiddenProgress
        guard chromeVisibleProgress > 0.001 else {
            return nil
        }

        let layoutVisibleProgress = tabBarLayoutVisibleProgress
        let rawSafeBottom = inheritedSafeAreaBottom
        let tabBarHeight = resolvedTabBarHeight(rawSafeBottom: rawSafeBottom)
        let reservation = bottomBarLayoutReservation(visibleProgress: layoutVisibleProgress, rawSafeBottom: rawSafeBottom)
        let isKeyboardVisible = (layout.inputHeight ?? 0) > 0
        let keyboardLift: CGFloat = tabBarView.isSearchActive ? (layout.inputHeight ?? 0) : 0
        let tabBarY = layout.size.height - tabBarHeight - keyboardLift
        let tabBarFrame = CGRect(x: 0, y: tabBarY, width: layout.size.width, height: tabBarHeight)
        let searchTopAdjustment: CGFloat = tabBarView.isSearchActive && !isKeyboardVisible
            ? tabBarView.searchRowTopOffset
            : 0
        let pillFrameInTab = tabBarView.computePillFrame(in: tabBarFrame.size, minimized: isTabBarMinimized)
        let pillTopInController = tabBarY + pillFrameInTab.minY

        if isTabBarMinimized {
            return resolvedInlineAccessoryFrame(
                layoutWidth: layout.size.width,
                pillTopInController: pillTopInController
            )
        }

        let accessoryHeight = reservation.accessoryHeight
        guard accessoryHeight > 0 else {
            return nil
        }
        let accessoryAnchorY = pillTopInController + searchTopAdjustment
        let sideInset = resolvedBottomBarAccessorySideInset
        return resolvedScrollMinimizeArmedAccessoryFrame(
            CGRect(
                x: sideInset,
                y: accessoryAnchorY
                    - resolvedBottomBarAccessoryBottomGap
                    - accessoryHeight,
                width: max(0, layout.size.width - sideInset * 2),
                height: accessoryHeight
            )
        )
    }

    /// Recomputes a collapsed endpoint after a genuine container geometry
    /// change (rotation, split-view resize, safe-area change) without consulting
    /// mutable live chrome state. In particular, an inline session always gets
    /// another inline frame; it can never detour through the regular accessory
    /// slot because a scroll/search/navigation callback happened while full.
    private func resolvedBottomBarAccessoryFrame(
        for layout: ContainerViewLayout,
        dockingContext: BottomBarAccessoryDockingContext
    ) -> CGRect? {
        guard let accessory = _bottomBarAccessory else { return nil }

        let tabBarHeight = resolvedTabBarHeight(rawSafeBottom: inheritedSafeAreaBottom)
        let isKeyboardVisible = (layout.inputHeight ?? 0) > 0
        let keyboardLift: CGFloat = dockingContext.isSearchActive
            ? (layout.inputHeight ?? 0)
            : 0
        let tabBarY = layout.size.height - tabBarHeight - keyboardLift
        let tabBarFrame = CGRect(
            x: 0,
            y: tabBarY,
            width: layout.size.width,
            height: tabBarHeight
        )
        let minimized = dockingContext.mode == .inline
        let pillFrameInTab = tabBarView.computePillFrame(
            in: tabBarFrame.size,
            minimized: minimized
        )
        let pillTopInController = tabBarY + pillFrameInTab.minY

        if minimized {
            return resolvedInlineAccessoryFrame(
                layoutWidth: layout.size.width,
                pillTopInController: pillTopInController
            )
        }

        let sideInset = resolvedBottomBarAccessorySideInset
        let accessoryHeight = resolvedBottomBarAccessoryHeight(accessory)
        guard accessoryHeight > 0 else { return nil }
        let searchTopAdjustment: CGFloat = dockingContext.isSearchActive
            && !isKeyboardVisible
            ? tabBarView.searchRowTopOffset
            : 0
        return CGRect(
            x: sideInset,
            y: pillTopInController + searchTopAdjustment
                - resolvedBottomBarAccessoryBottomGap - accessoryHeight,
            width: max(0, layout.size.width - sideInset * 2),
            height: accessoryHeight
        )
    }

    private func childLayout(from layout: ContainerViewLayout, reservation: BottomBarLayoutReservation) -> ContainerViewLayout {
        return ContainerViewLayout(
            size: layout.size,
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: UIEdgeInsets(
                top: layout.additionalInsets.top,
                left: layout.additionalInsets.left,
                bottom: layout.additionalInsets.bottom + reservation.total,
                right: layout.additionalInsets.right
            ),
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
    }

    private func settleChildSafeAreaPropagation(_ controller: UIViewController) {
        if let navigationController = controller as? AetherNavigationController {
            navigationController.settleInheritedSafeAreaPropagation()
        } else if controller.transitionCoordinator == nil,
                  let childView = controller.viewIfLoaded {
            childView.setNeedsLayout()
            childView.layoutIfNeeded()
        }
    }

    /// Re-entry guard for `containerLayoutUpdated`. Setting
    /// `additionalSafeAreaInsets` synchronously triggers UIKit's safe-area
    /// machinery, which calls `viewSafeAreaInsetsDidChange` →
    /// `applySelfComputedLayout(transition: .immediate)` →
    /// `containerLayoutUpdated(.immediate)`. Without this guard, the
    /// nested `.immediate` pass writes `wrapper.frame` directly BEFORE
    /// the outer animated pass has a chance to register its `UIView.animate`
    /// block — by the time the outer call gets there, the model frame
    /// already equals the target, so the animation captures `from == to`
    /// and renders no visible morph (looks like a snap). The pill /
    /// search circle live INSIDE `tabBarView` and animate inside
    /// `setMinimized` *before* we ever hit `containerLayoutUpdated`, so
    /// they're unaffected — only the bottom accessory was getting eaten.
    private var isApplyingContainerLayout: Bool = false
    private var isApplyingSelfComputedLayout = false
    private var hasParentDrivenLayout = false

    // MARK: - Minimize Behavior (iOS 26 `tabBarMinimizeBehavior`)

    /// How the tab bar should behave when content scrolls. Mirrors the
    /// iOS 26 `UITabBarController.tabBarMinimizeBehavior` API surface.
    public enum TabBarMinimizeBehavior {
        /// Tab bar always stays in its full pill form (default).
        case never
        /// Scrolling DOWN (away from the top) collapses the tab bar into
        /// the iOS 26 minimized chrome: pill → 48×48 active-tab circle on
        /// the leading edge, search tab item → matching circle on the
        /// trailing edge, `bottomBarAccessory` reflows between them.
        /// Scrolling UP (or hitting the content top) expands it back.
        case onScrollDown
    }

    /// Drives the auto-minimize behaviour on scroll. Setting this to
    /// `.onScrollDown` enables Liquid tab-bar minimization for the current
    /// screen. Shared scroll observation remains active in `.never` because
    /// it also drives navigation scroll-edge chrome and Legacy tab chrome.
    public var tabBarMinimizeBehavior: TabBarMinimizeBehavior = .never {
        didSet {
            guard tabBarMinimizeBehavior != oldValue else { return }
            switch tabBarMinimizeBehavior {
            case .never:
                if isTabBarMinimized {
                    setTabBarMinimized(false, transition: Self.tabBarMinimizeMorphTransition)
                }
                // Metrics observation also drives navigation scroll-edge
                // chrome and Legacy tab backgrounds. Keep it attached even
                // when Liquid auto-minimize itself is disabled.
                attachScrollObserverIfPossible()
            case .onScrollDown:
                attachScrollObserverIfPossible()
            }
        }
    }

    /// Current minimize state. Toggled either by the scroll observer
    /// (when `tabBarMinimizeBehavior == .onScrollDown`) or directly by
    /// callers via `setTabBarMinimized(_:transition:)`.
    public private(set) var isTabBarMinimized: Bool = false

    /// Live compact-morph progress. `0` is the expanded pill and `1` is the
    /// minimized row. Unlike `isTabBarMinimized`, this changes per frame.
    public private(set) var tabBarMinimizationProgress: CGFloat = 0.0
    private var tabBarMinimizedBeforeSearchActivation: Bool?
    private var isTabBarScrollMinimizeArmed = false
    private var tabBarScrollMinimizeArmingProgress: CGFloat = 0.0
    private var scrollMinimizeAccessoryTransformGeneration: Int = 0
    private var isHandlingScrollMinimizeObserverEvent = false
    private var deferredScrollSafeAreaReservationTotal: CGFloat?
    private weak var deferredScrollSafeAreaSource: UIScrollView?
    private var deferredScrollSafeAreaGeneration: UInt = 0

    private struct ObservedScrollOffsetSnapshot {
        enum VerticalAnchor {
            case top(overscroll: CGFloat)
            case middle(normalizedFromTop: CGFloat, bottomGap: CGFloat)
            case bottom(gap: CGFloat)
        }

        let scrollView: UIScrollView
        let contentOffsetX: CGFloat
        let verticalAnchor: VerticalAnchor
    }

    /// Accessory installation is chrome-only. Unlike a minimize transition,
    /// it must not reinterpret a list parked near the bottom as a bottom
    /// anchor and move its raw `contentOffset` when the safe-area reservation
    /// changes.
    private struct ObservedRawScrollOffsetSnapshot {
        let scrollView: UIScrollView
        let contentOffset: CGPoint
    }

    private static let tabBarMinimizeMorphTransition: ContainedViewLayoutTransition = .animated(
        duration: AetherMotion.tabBarMorph.duration,
        curve: .customSpring(
            damping: AetherMotion.tabBarMorph.dampingRatio,
            initialVelocity: AetherMotion.tabBarMorph.initialVelocity
        )
    )
    private static let tabBarScrollMinimizeArmingTransition: ContainedViewLayoutTransition = .animated(
        duration: 0.24,
        curve: .customSpring(damping: 0.78, initialVelocity: 0.10)
    )
    private static let legacyScrollEdgeChromeTransition =
        AetherChromeScrollTransitions.legacyEndpoint

    private func resolvedTabBarMinimizeTransition(
        _ transition: ContainedViewLayoutTransition
    ) -> ContainedViewLayoutTransition {
        guard transition.isAnimated,
              bottomBarAccessoryReduceMotionStatusProvider() else {
            return transition
        }
        return .animated(
            duration: min(0.20, max(0.01, transition.duration)),
            curve: .easeInOut
        )
    }

    private func resolvedTabBarScrollMinimizeArmingTransition(
        _ transition: ContainedViewLayoutTransition
    ) -> ContainedViewLayoutTransition {
        return bottomBarAccessoryReduceMotionStatusProvider()
            ? .immediate
            : transition
    }

    private var canArmTabBarScrollMinimize: Bool {
        isViewLoaded
            && appliedTabBarTheme.appearanceStyle.usesLiquidGlass
            && tabBarMinimizeBehavior == .onScrollDown
            && !isTabBarMinimized
            && !tabBarView.isSearchActive
            && expandedAccessoryViewController == nil
    }

    private var observedScrollViewIsMoving: Bool {
        scrollViewIsMoving(observedScrollView)
    }

    private func scrollViewIsMoving(_ scrollView: UIScrollView?) -> Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking
            || scrollView.isDragging
            || scrollView.isDecelerating
    }

    private var hasActiveChildNavigationTransition: Bool {
        let current = presentedSearchController ?? currentController
        if let navigationController = current as? AetherNavigationController,
           navigationController.isTransitioning {
            return true
        }
        return current?.transitionCoordinator != nil
    }

    private func beginDeferredScrollSafeAreaReservationIfNeeded(
        targetTotal: CGFloat
    ) {
        guard _bottomBarAccessory != nil,
              isHandlingScrollMinimizeObserverEvent,
              observedScrollViewIsMoving,
              abs(additionalSafeAreaInsets.bottom - targetTotal) > 0.5 else {
            return
        }
        if deferredScrollSafeAreaReservationTotal == nil {
            deferredScrollSafeAreaReservationTotal = additionalSafeAreaInsets.bottom
            deferredScrollSafeAreaSource = observedScrollView
        }
        deferredScrollSafeAreaGeneration &+= 1
        pollDeferredScrollSafeAreaReservation(
            generation: deferredScrollSafeAreaGeneration
        )
    }

    private func pollDeferredScrollSafeAreaReservation(generation: UInt) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  self.deferredScrollSafeAreaGeneration == generation,
                  self.deferredScrollSafeAreaReservationTotal != nil else {
                return
            }
            if self.scrollViewIsMoving(self.deferredScrollSafeAreaSource)
                || self.scrollViewIsMoving(self.observedScrollView)
                || self.hasActiveChildNavigationTransition {
                self.pollDeferredScrollSafeAreaReservation(generation: generation)
                return
            }
            let originScrollView = self.deferredScrollSafeAreaSource
            let originSnapshot = self.captureScrollOffset(
                from: originScrollView ?? self.observedScrollView
            )
            let activeSnapshot: ObservedScrollOffsetSnapshot?
            if let originScrollView,
               self.observedScrollView !== originScrollView {
                activeSnapshot = self.captureObservedScrollOffset()
            } else {
                activeSnapshot = nil
            }
            self.scrollObserver?.beginOwnedGeometryMutation()
            self.deferredScrollSafeAreaReservationTotal = nil
            self.deferredScrollSafeAreaSource = nil
            if let layout = self.currentlyAppliedLayout {
                self.containerLayoutUpdated(layout, transition: .immediate)
            }
            // Safe-area propagation is allowed to update layout, but it does
            // not own the user's visible scroll anchor. Restore it once in the
            // same run-loop transaction: middle content keeps its exact visual
            // position, while a list parked at the bottom keeps the same
            // bottom gap instead of being left in overscroll and snapping on a
            // later UIKit rubber-band pass.
            self.view.layoutIfNeeded()
            self.restoreScrollOffset(originSnapshot, requiresObservedIdentity: false)
            self.restoreObservedScrollOffset(activeSnapshot)
        }
    }

    private func captureObservedScrollOffset() -> ObservedScrollOffsetSnapshot? {
        captureScrollOffset(from: observedScrollView)
    }

    private func captureScrollOffset(
        from scrollView: UIScrollView?
    ) -> ObservedScrollOffsetSnapshot? {
        guard let scrollView,
              scrollView.contentOffset.x.isFinite,
              scrollView.contentOffset.y.isFinite else {
            return nil
        }
        let topInset = scrollView.adjustedContentInset.top.isFinite
            ? scrollView.adjustedContentInset.top
            : 0.0
        let bottomInset = scrollView.adjustedContentInset.bottom.isFinite
            ? scrollView.adjustedContentInset.bottom
            : 0.0
        let minimumY = -topInset
        let contentHeight = scrollView.contentSize.height.isFinite
            ? max(0.0, scrollView.contentSize.height)
            : 0.0
        let boundsHeight = scrollView.bounds.height.isFinite
            ? max(0.0, scrollView.bounds.height)
            : 0.0
        let maximumY = max(
            minimumY,
            contentHeight - boundsHeight + bottomInset
        )
        let rawY = scrollView.contentOffset.y
        let clampedY = min(maximumY, max(minimumY, rawY))
        let verticalAnchor: ObservedScrollOffsetSnapshot.VerticalAnchor
        if maximumY - minimumY <= 0.5 || clampedY <= minimumY + 0.5 {
            verticalAnchor = .top(overscroll: rawY - minimumY)
        } else if maximumY - clampedY <= 8.0 {
            verticalAnchor = .bottom(gap: maximumY - rawY)
        } else {
            verticalAnchor = .middle(
                normalizedFromTop: clampedY + topInset,
                bottomGap: maximumY - clampedY
            )
        }
        return ObservedScrollOffsetSnapshot(
            scrollView: scrollView,
            contentOffsetX: scrollView.contentOffset.x,
            verticalAnchor: verticalAnchor
        )
    }

    private func restoreObservedScrollOffset(
        _ snapshot: ObservedScrollOffsetSnapshot?
    ) {
        restoreScrollOffset(snapshot, requiresObservedIdentity: true)
    }

    private func restoreScrollOffset(
        _ snapshot: ObservedScrollOffsetSnapshot?,
        requiresObservedIdentity: Bool
    ) {
        guard let snapshot,
              !requiresObservedIdentity || observedScrollView === snapshot.scrollView else {
            return
        }
        let scrollView = snapshot.scrollView
        let topInset = scrollView.adjustedContentInset.top.isFinite
            ? scrollView.adjustedContentInset.top
            : 0.0
        let bottomInset = scrollView.adjustedContentInset.bottom.isFinite
            ? scrollView.adjustedContentInset.bottom
            : 0.0
        let minimumY = -topInset
        let contentHeight = scrollView.contentSize.height.isFinite
            ? max(0.0, scrollView.contentSize.height)
            : 0.0
        let boundsHeight = scrollView.bounds.height.isFinite
            ? max(0.0, scrollView.bounds.height)
            : 0.0
        let maximumY = max(
            minimumY,
            contentHeight - boundsHeight + bottomInset
        )
        let targetY: CGFloat
        switch snapshot.verticalAnchor {
        case let .top(overscroll):
            targetY = overscroll < 0.0
                ? minimumY + overscroll
                : minimumY
        case let .middle(normalizedFromTop, bottomGap):
            let positionFromTop = normalizedFromTop - topInset
            if positionFromTop > maximumY {
                // A shrinking bottom inset can move the new maximum above a
                // previously valid near-bottom position. Preserve its former
                // bottom gap instead of clamping it to zero (or leaving it in
                // overscroll for a later rubber-band snap).
                targetY = min(
                    maximumY,
                    max(minimumY, maximumY - bottomGap)
                )
            } else {
                targetY = max(minimumY, positionFromTop)
            }
        case let .bottom(gap):
            targetY = gap < 0.0
                ? maximumY - gap
                : min(maximumY, max(minimumY, maximumY - gap))
        }
        let target = CGPoint(x: snapshot.contentOffsetX, y: targetY)
        let current = scrollView.contentOffset
        guard abs(current.x - target.x) > 0.01
                || abs(current.y - target.y) > 0.01 else {
            return
        }
        scrollObserver?.beginOwnedGeometryMutation()
        scrollView.setContentOffset(target, animated: false)
    }

    private func captureObservedRawScrollOffset() -> ObservedRawScrollOffsetSnapshot? {
        guard let scrollView = activeScrollViewForRawOffsetPreservation,
              scrollView.contentOffset.x.isFinite,
              scrollView.contentOffset.y.isFinite else {
            return nil
        }
        return ObservedRawScrollOffsetSnapshot(
            scrollView: scrollView,
            contentOffset: scrollView.contentOffset
        )
    }

    private func restoreObservedRawScrollOffsetAfterLayout(
        _ snapshot: ObservedRawScrollOffsetSnapshot?
    ) {
        guard let snapshot,
              activeScrollViewForRawOffsetPreservation === snapshot.scrollView else {
            return
        }
        // `AetherListNode` can synchronously bottom-anchor while receiving
        // the new automatic safe-area inset. Settle every pending child pass
        // first, then restore the chrome-independent raw position once.
        view.layoutIfNeeded()
        let scrollView = snapshot.scrollView
        let current = scrollView.contentOffset
        guard abs(current.x - snapshot.contentOffset.x) > 0.01
                || abs(current.y - snapshot.contentOffset.y) > 0.01 else {
            return
        }
        scrollObserver?.beginOwnedGeometryMutation()
        scrollView.setContentOffset(snapshot.contentOffset, animated: false)
    }

    /// Tab switches deliberately detach the observer before changing child
    /// ownership. An accessory can still be installed or removed from a
    /// lifecycle callback inside that window, so resolve the newly-active
    /// source directly and use the observer only as a stable fallback.
    private var activeScrollViewForRawOffsetPreservation: UIScrollView? {
        if isViewLoaded,
           let rootController = presentedSearchController ?? currentController,
           let source = AetherChromeScrollSourceResolver.resolve(
               from: rootController
           ),
           source.contentRootView != nil,
           let scrollView = source.scrollView {
            return scrollView
        }
        return observedScrollView
    }

    private func updateBottomBarAccessoryLayoutPreservingObservedContentOffset(
        transition: ContainedViewLayoutTransition
    ) {
        guard let layout = currentlyAppliedLayout else { return }
        let scrollSnapshot = captureObservedRawScrollOffset()
        containerLayoutUpdated(layout, transition: transition)
        restoreObservedRawScrollOffsetAfterLayout(scrollSnapshot)
    }

    private func cancelDeferredScrollSafeAreaReservation() {
        deferredScrollSafeAreaGeneration &+= 1
        deferredScrollSafeAreaReservationTotal = nil
        deferredScrollSafeAreaSource = nil
    }

    @discardableResult
    private func setScrollMinimizeArmingPreview(
        progress: CGFloat,
        isActive: Bool,
        transition: ContainedViewLayoutTransition,
        updatesLayout: Bool = true
    ) -> Bool {
        if isActive, !canArmTabBarScrollMinimize {
            return false
        }
        let resolvedProgress = isActive
            ? max(0.0, min(1.0, progress))
            : 0.0
        guard isTabBarScrollMinimizeArmed != isActive
                || abs(tabBarScrollMinimizeArmingProgress - resolvedProgress) > 0.0001 else {
            return true
        }

        let resolvedTransition = resolvedTabBarScrollMinimizeArmingTransition(
            transition
        )
        isTabBarScrollMinimizeArmed = isActive
        tabBarScrollMinimizeArmingProgress = resolvedProgress
        tabBarView.setScrollMinimizeArmingProgress(
            resolvedProgress,
            isActive: isActive,
            transition: resolvedTransition,
            updatesLayout: updatesLayout
        )
        updateScrollMinimizeAccessoryPreviewTransform(
            progress: resolvedProgress,
            isActive: isActive,
            transition: resolvedTransition
        )

        if updatesLayout, let layout = currentlyAppliedLayout {
            updateScrollMinimizePreviewAccessoryLayout(
                layout: layout,
                transition: resolvedTransition
            )
        }
        return true
    }

    /// Preview is local chrome feedback. Running the full controller layout
    /// here would resend an otherwise unchanged layout to the child scroll
    /// view on every drag sample (and again on cancellation), which can make
    /// UIKit adjust contentOffset. The tab bar lays itself out above; only the
    /// separately hosted accessory needs a matching local frame update.
    private func updateScrollMinimizePreviewAccessoryLayout(
        layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        guard expandedAccessoryViewController == nil,
              let wrapper = bottomBarAccessoryWrapper,
              !wrapper.isHidden,
              let frame = resolvedBottomBarAccessoryFrame(for: layout) else {
            return
        }
        applyAccessoryFrame(
            wrapper,
            frame: frame,
            transition: transition
        )
        view.bringSubviewToFront(wrapper)
    }

    @discardableResult
    private func setScrollMinimizeArmingPreview(
        _ armed: Bool,
        transition: ContainedViewLayoutTransition,
        updatesLayout: Bool = true
    ) -> Bool {
        setScrollMinimizeArmingPreview(
            progress: armed ? 1.0 : 0.0,
            isActive: armed,
            transition: transition,
            updatesLayout: updatesLayout
        )
    }

    private func updateScrollMinimizeAccessoryPreviewTransform(
        progress: CGFloat,
        isActive: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        scrollMinimizeAccessoryTransformGeneration &+= 1
        let generation = scrollMinimizeAccessoryTransformGeneration
        guard let wrapper = bottomBarAccessoryWrapper else { return }

        // Compact press feedback owns the same sublayerTransform property.
        // Retire it before taking preview ownership; wrapper.transform stays
        // identity so frame-based layout and presentation-frame reads remain
        // well-defined throughout the arming interval.
        bottomBarAccessoryPress?.isEnabled = false
        if isActive {
            bottomBarAccessoryPress?.resetVisualState()
        }
        wrapper.layer.removeAnimation(forKey: TouchEffect.transformAnimationKey)

        let clampedProgress = isActive
            ? max(0.0, min(1.0, progress))
            : 0.0
        let scale = 1.0
            - (1.0 - Self.scrollMinimizeArmedAccessoryScale) * clampedProgress
        let targetTransform = CATransform3DMakeScale(scale, scale, 1.0)
        let sourceTransform = wrapper.layer.presentation()?.sublayerTransform
            ?? wrapper.layer.sublayerTransform
        wrapper.layer.removeAnimation(
            forKey: Self.scrollMinimizeArmedAccessoryTransformAnimationKey
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wrapper.layer.sublayerTransform = targetTransform
        CATransaction.commit()

        guard case let .animated(duration, _) = transition,
              duration > 0.0 else {
            if !isActive,
               expandedAccessoryViewController == nil,
               bottomBarAccessoryWrapper === wrapper {
                setBottomBarAccessoryPressEnabled(true)
            }
            return
        }

        let animation: CABasicAnimation
        switch transition {
        case let .animated(_, curve):
            switch curve {
            case let .customSpring(damping, initialVelocity):
                let spring = CASpringAnimation(keyPath: "sublayerTransform")
                spring.mass = 1.0
                spring.stiffness = 120.0
                spring.damping = 2.0 * Double(damping)
                    * sqrt(spring.stiffness * spring.mass)
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
        case .immediate:
            animation = CABasicAnimation(keyPath: "sublayerTransform")
        }
        animation.fromValue = NSValue(caTransform3D: sourceTransform)
        animation.toValue = NSValue(caTransform3D: targetTransform)
        animation.duration = duration
        animation.isRemovedOnCompletion = true

        CATransaction.begin()
        if !isActive {
            CATransaction.setCompletionBlock { [weak self, weak wrapper] in
                guard let self,
                      let wrapper,
                      self.scrollMinimizeAccessoryTransformGeneration == generation,
                      !self.isTabBarScrollMinimizeArmed,
                      self.expandedAccessoryViewController == nil,
                      self.bottomBarAccessoryWrapper === wrapper else {
                    return
                }
                self.setBottomBarAccessoryPressEnabled(true)
            }
        }
        wrapper.layer.add(
            animation,
            forKey: Self.scrollMinimizeArmedAccessoryTransformAnimationKey
        )
        CATransaction.commit()
    }

    /// Commit is a handoff, not a preview cancellation. Keep TabBarView's
    /// armed presentation alive until `setMinimized` captures it, and keep the
    /// accessory's inset frame as the compact morph source. Only transform
    /// ownership is returned to identity before the shared compact clock starts.
    private func handOffScrollMinimizeArmingPreviewForCommit(
        transition: ContainedViewLayoutTransition
    ) {
        guard isTabBarScrollMinimizeArmed else { return }
        isTabBarScrollMinimizeArmed = false
        tabBarScrollMinimizeArmingProgress = 0.0
        updateScrollMinimizeAccessoryPreviewTransform(
            progress: 0.0,
            isActive: false,
            transition: resolvedTabBarScrollMinimizeArmingTransition(transition)
        )
    }

    private func handleScrollMinimizeObserverEvent(
        _ event: TabBarScrollMinimizeObserver.Event
    ) -> Bool {
        guard !isHandlingScrollMinimizeObserverEvent else { return false }
        isHandlingScrollMinimizeObserverEvent = true
        defer { isHandlingScrollMinimizeObserverEvent = false }

        switch event {
        case let .armingProgress(progress, isActive):
            return setScrollMinimizeArmingPreview(
                progress: progress,
                isActive: isActive,
                // Live scroll distance is the clock; animating every KVO
                // sample would make the chrome chase the finger and jitter.
                transition: isActive ? .immediate : Self.tabBarScrollMinimizeArmingTransition
            )

        case .commitMinimize:
            guard canArmTabBarScrollMinimize else {
                _ = setScrollMinimizeArmingPreview(
                    false,
                    transition: Self.tabBarScrollMinimizeArmingTransition
                )
                return false
            }
            // Clear preview ownership without laying out the expanded endpoint
            // in between. `setTabBarMinimized` performs the one geometry pass
            // that targets the compact row, so commit cannot flash regular
            // accessory geometry for a frame.
            handOffScrollMinimizeArmingPreviewForCommit(
                transition: Self.tabBarScrollMinimizeArmingTransition
            )
            setTabBarMinimized(
                true,
                transition: Self.tabBarMinimizeMorphTransition
            )
            // The compact morph intentionally removes wrapper-layer
            // animations after capturing the preview presentation frame.
            // Re-enable press ownership explicitly because that removal also
            // retires the preview transform's completion callback.
            if isTabBarMinimized {
                setBottomBarAccessoryPressEnabled(
                    bottomBarAccessoryWrapper != nil
                )
            } else {
                // Defensive recovery if endpoint eligibility changed during a
                // synchronous callback: neither preview owner may stay armed.
                tabBarView.setScrollMinimizeArmed(
                    false,
                    transition: .immediate,
                    updatesLayout: true
                )
                if let layout = currentlyAppliedLayout {
                    containerLayoutUpdated(layout, transition: .immediate)
                }
            }
            return isTabBarMinimized

        case .requestExpand:
            _ = setScrollMinimizeArmingPreview(
                false,
                transition: Self.tabBarScrollMinimizeArmingTransition,
                updatesLayout: false
            )
            setTabBarMinimized(
                false,
                transition: Self.tabBarMinimizeMorphTransition
            )
            return !isTabBarMinimized
        }
    }

    private func cancelScrollMinimizeArming(
        transition: ContainedViewLayoutTransition,
        updatesLayout: Bool = true
    ) {
        if !isHandlingScrollMinimizeObserverEvent {
            scrollObserver?.synchronize(minimized: isTabBarMinimized)
        }
        _ = setScrollMinimizeArmingPreview(
            false,
            transition: transition,
            updatesLayout: updatesLayout
        )
    }

    /// Toggle the minimized state with an animated morph.
    ///
    /// Drives both the tab bar's own pill→circle morph and the
    /// `bottomBarAccessory` reflow (between the circles) via the same
    /// transition. Safe to call repeatedly with the same value (no-op).
    public func setTabBarMinimized(_ minimized: Bool, transition: ContainedViewLayoutTransition) {
        if !isHandlingScrollMinimizeObserverEvent {
            cancelDeferredScrollSafeAreaReservation()
        }
        // A programmatic/search/full-player state change supersedes a pending
        // scroll intent. Clear preview before evaluating endpoint guards so a
        // same-value request (notably `setTabBarMinimized(false)`) still
        // cancels a partial scroll preview and restores canonical geometry.
        cancelScrollMinimizeArming(
            transition: Self.tabBarScrollMinimizeArmingTransition,
            updatesLayout: true
        )
        guard !minimized || appliedTabBarTheme.appearanceStyle.usesLiquidGlass else { return }
        guard isTabBarMinimized != minimized else { return }
        // Preserve the docking mode captured by the active accessory session.
        // Rotation may update its frame, but scroll ticks must not switch the
        // target between regular and inline while the full card is open.
        guard expandedAccessoryViewController == nil else { return }
        // Search mode uses the minimized active-tab circle as its anchor.
        // Do not expand the tab bar while search is active; the search
        // deactivation path restores the pre-search state explicitly.
        if !minimized && tabBarView.isSearchActive {
            return
        }
        let scrollSnapshot = captureObservedScrollOffset()
        let resolvedTransition = resolvedTabBarMinimizeTransition(transition)
        isTabBarMinimized = minimized
        if !isHandlingScrollMinimizeObserverEvent {
            scrollObserver?.synchronize(minimized: minimized)
        }

        startTabBarMinimizeAnimation(
            to: minimized ? 1.0 : 0.0,
            transition: resolvedTransition
        )

        let canSequenceAccessory = resolvedTransition.isAnimated
            && !bottomBarAccessoryReduceMotionStatusProvider()
            && _bottomBarAccessory != nil
            && bottomBarAccessoryWrapper?.isHidden == false
            && currentlyAppliedLayout != nil

        pendingAccessoryCompactMorphDirection = canSequenceAccessory
            ? (minimized ? .minimize : .expand)
            : nil
        // All chrome starts on the same clock. The accessory bends that one
        // response directionally without starting a second animation phase.
        tabBarView.setMinimized(minimized, transition: resolvedTransition)
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: resolvedTransition)
        }
        restoreObservedScrollOffset(scrollSnapshot)
        if !resolvedTransition.isAnimated {
            publishMinimizationUpdate(accessoryFrame: bottomBarAccessoryFrame)
        }
    }

    private var scrollObserver: TabBarScrollMinimizeObserver?
    private weak var observedScrollView: UIScrollView?
    private weak var observedChromeStateOwner: AnyObject?
    private weak var observedNavigationScrollController: AetherViewController?
    private var chromeContainerSourceObserver: AetherChromeContainerSourceObserver?
    private var observedChromeContainerPath: [ObjectIdentifier] = []
    private var legacyScrollEdgeChromeVisible: Bool?
    private var perSourceChromeStates: [ObjectIdentifier: TabBarPerSourceChromeState] = [:]
    private var isUpdatingScrollObserver = false

    /// Idempotent: re-binds the scroll observer to the current tab's
    /// primary scroll view if it differs from whatever's currently
    /// observed. Cheap to call on every layout pass — comparison is a
    /// single reference equality check when the target hasn't changed.
    ///
    /// Called on every `containerLayoutUpdated` so push/pop inside a
    /// tab's nav stack rebinds the observer to the freshly-visible
    /// detail screen — without it, scrolling a pushed list never
    /// triggers minimize because we'd still be watching the root.
    private func attachScrollObserverIfPossible() {
        guard !isUpdatingScrollObserver else { return }
        isUpdatingScrollObserver = true
        defer { isUpdatingScrollObserver = false }

        guard isViewLoaded else {
            detachScrollObserver()
            return
        }

        guard let rootController = presentedSearchController ?? currentController else {
            detachScrollObserver()
            legacyScrollEdgeChromeVisible = nil
            return
        }
        guard let source = AetherChromeScrollSourceResolver.resolve(
            from: rootController
        ), source.contentRootView != nil else {
            // Page/navigation transitions can notify before the destination
            // installs its view. Keep the previous observer and rendered
            // endpoint until a stable source is available; resetting through
            // a transient nil causes a visible background flash.
            return
        }
        let target = source.scrollView
        let sourceOwner: AnyObject? = source.owner
        let hasCachedChromeState = sourceOwner.flatMap {
            chromeState(for: $0, createIfNeeded: false)
        } != nil
        let isReturningToCachedChromeState = hasCachedChromeState
            && !(observedChromeStateOwner === sourceOwner)
        let navigationController = source.controllerPath.reversed().compactMap {
            $0 as? AetherViewController
        }.first
        updateChromeContainerSourceObservation(for: source.controllerPath)

        if let observedOwner = observedChromeStateOwner,
           let sourceOwner,
           observedOwner === sourceOwner,
           observedScrollView === target {
            observedNavigationScrollController = navigationController
            scrollObserver?.refreshScrollMetrics()
            return
        }

        persistObservedChromeState()
        scrollObserver?.invalidate()
        scrollObserver = nil
        _ = setScrollMinimizeArmingPreview(false, transition: .immediate)
        observedScrollView = target
        observedChromeStateOwner = sourceOwner
        observedNavigationScrollController = navigationController
        restoreObservedChromeState(for: sourceOwner, hasScrollView: target != nil)

        guard let target else {
            return
        }
        scrollObserver = TabBarScrollMinimizeObserver(
            scrollView: target,
            initiallyMinimized: isTabBarMinimized,
            emitsInitialScrollMetrics: !isReturningToCachedChromeState,
            onEvent: { [weak self] event in
                guard let self else { return false }
                guard self.appliedTabBarTheme.appearanceStyle.usesLiquidGlass,
                      self.tabBarMinimizeBehavior == .onScrollDown else {
                    return false
                }
                return self.handleScrollMinimizeObserverEvent(event)
            },
            onScrollMetricsChange: { [weak self] metrics in
                self?.updateObservedChrome(metrics: metrics)
            }
        )
    }

    private func detachScrollObserver() {
        persistObservedChromeState()
        scrollObserver?.invalidate()
        scrollObserver = nil
        chromeContainerSourceObserver?.invalidate()
        chromeContainerSourceObserver = nil
        observedChromeContainerPath.removeAll()
        observedScrollView = nil
        observedChromeStateOwner = nil
        observedNavigationScrollController = nil
        _ = setScrollMinimizeArmingPreview(false, transition: .immediate)
    }

    private func updateObservedChrome(metrics: LegacyTabBarScrollMetrics) {
        let navigationAlpha = min(
            1.0,
            max(0.0, (metrics.contentOffsetY + metrics.adjustedTopInset) / 16.0)
        )
        let state = currentPerSourceChromeState(createIfNeeded: true)
        let previousNavigationAlpha = state?.navigationEdgeAlpha
        state?.navigationEdgeAlpha = navigationAlpha
        let arrivedAtNavigationEndpoint: Bool
        if let previousNavigationAlpha {
            arrivedAtNavigationEndpoint =
                (navigationAlpha <= 0.001 && previousNavigationAlpha > 0.001)
                || (navigationAlpha >= 0.999 && previousNavigationAlpha < 0.999)
        } else {
            arrivedAtNavigationEndpoint = false
        }
        let navigationTransition: ContainedViewLayoutTransition =
            observedNavigationScrollController?.navigationScrollEdgeAppearanceStyle == .legacy
                && arrivedAtNavigationEndpoint
                ? Self.legacyScrollEdgeChromeTransition
                : .immediate
        observedNavigationScrollController?.applyNavigationBarScrollEdgeAlpha(
            navigationAlpha,
            transition: navigationTransition
        )

        updateLegacyScrollEdgeChrome(metrics: metrics)
    }

    private func updateLegacyScrollEdgeChrome(metrics: LegacyTabBarScrollMetrics) {
        guard appliedTabBarTheme.appearanceStyle == .legacy else { return }
        let visible = LegacyTabBarScrollEdgeResolver.isChromeVisible(
            metrics: metrics,
            previouslyVisible: legacyScrollEdgeChromeVisible ?? false
        )
        updateLegacyScrollEdgeChrome(
            visible: visible,
            transition: legacyScrollEdgeChromeVisible == nil
                ? .immediate
                : Self.legacyScrollEdgeChromeTransition
        )
    }

    private func updateLegacyScrollEdgeChrome(
        visible: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        guard appliedTabBarTheme.appearanceStyle == .legacy else { return }
        guard legacyScrollEdgeChromeVisible != visible else { return }
        legacyScrollEdgeChromeVisible = visible
        currentPerSourceChromeState(createIfNeeded: true)?.legacyChromeVisible = visible
        tabBarView.setLegacyScrollEdgeChromeVisible(visible, transition: transition)
    }

    public func invalidateTabBarMinimizeScrollView() {
        persistObservedChromeState()
        scrollObserver?.invalidate()
        scrollObserver = nil
        chromeContainerSourceObserver?.invalidate()
        chromeContainerSourceObserver = nil
        observedChromeContainerPath.removeAll()
        observedScrollView = nil
        attachScrollObserverIfPossible()
    }

    private func updateChromeContainerSourceObservation(
        for controllerPath: [UIViewController]
    ) {
        let signature = controllerPath.map(ObjectIdentifier.init)
        guard signature != observedChromeContainerPath else { return }
        chromeContainerSourceObserver?.invalidate()
        observedChromeContainerPath = signature
        chromeContainerSourceObserver = AetherChromeContainerSourceObserver(
            controllerPath: controllerPath
        ) { [weak self] in
            // Re-resolve without first discarding the current observer/state.
            // `attach...` performs an atomic old-source persist -> new-source
            // restore only when the active owner actually changed.
            self?.attachScrollObserverIfPossible()
        }
    }

    internal func advanceTabBarMinimizeArmingForTesting(by delta: TimeInterval) {
        scrollObserver?.advanceArmingForTesting(by: delta)
    }

    internal func endTabBarMinimizeScrollInteractionForTesting() {
        scrollObserver?.endPanForTesting()
    }

    private func chromeState(
        for owner: AnyObject,
        createIfNeeded: Bool
    ) -> TabBarPerSourceChromeState? {
        if perSourceChromeStates.count > 32 {
            perSourceChromeStates = perSourceChromeStates.filter {
                $0.value.owner != nil
            }
        }
        let identifier = ObjectIdentifier(owner)
        if let state = perSourceChromeStates[identifier], state.owner === owner {
            return state
        }
        guard createIfNeeded else { return nil }
        let state = TabBarPerSourceChromeState(owner: owner)
        perSourceChromeStates[identifier] = state
        return state
    }

    private func currentPerSourceChromeState(
        createIfNeeded: Bool
    ) -> TabBarPerSourceChromeState? {
        guard let owner = observedChromeStateOwner else { return nil }
        return chromeState(for: owner, createIfNeeded: createIfNeeded)
    }

    private func persistObservedChromeState() {
        guard let state = currentPerSourceChromeState(createIfNeeded: true) else {
            return
        }
        if appliedTabBarTheme.appearanceStyle == .legacy {
            state.legacyChromeVisible = legacyScrollEdgeChromeVisible
        }
    }

    private func restoreObservedChromeState(
        for owner: AnyObject?,
        hasScrollView: Bool
    ) {
        guard let owner else {
            legacyScrollEdgeChromeVisible = nil
            observedNavigationScrollController?.applyNavigationBarScrollEdgeAlpha(
                0.0,
                transition: .immediate
            )
            if appliedTabBarTheme.appearanceStyle == .legacy {
                updateLegacyScrollEdgeChrome(visible: false, transition: .immediate)
            }
            return
        }

        let state = chromeState(for: owner, createIfNeeded: true)
        if let navigationAlpha = state?.navigationEdgeAlpha {
            observedNavigationScrollController?.applyNavigationBarScrollEdgeAlpha(
                navigationAlpha,
                transition: .immediate
            )
        } else if !hasScrollView {
            observedNavigationScrollController?.applyNavigationBarScrollEdgeAlpha(
                0.0,
                transition: .immediate
            )
        }

        if appliedTabBarTheme.appearanceStyle == .legacy {
            legacyScrollEdgeChromeVisible = nil
            if let visible = state?.legacyChromeVisible {
                updateLegacyScrollEdgeChrome(visible: visible, transition: .immediate)
            } else if !hasScrollView {
                updateLegacyScrollEdgeChrome(visible: false, transition: .immediate)
            }
        } else {
            // Liquid minimization belongs to the tab-bar controller, not to
            // an individual scroll source. Rebinding after a tab/page/nav
            // change must keep the currently rendered endpoint; the new
            // observer is initialized from `isTabBarMinimized` below.
            legacyScrollEdgeChromeVisible = nil
        }
    }

    internal var observedChromeScrollViewForTesting: UIScrollView? {
        observedScrollView
    }

    internal var legacyScrollEdgeChromeVisibleForTesting: Bool? {
        legacyScrollEdgeChromeVisible
    }

    internal func cachedLegacyChromeVisibleForTesting(
        owner: AnyObject
    ) -> Bool? {
        chromeState(for: owner, createIfNeeded: false)?.legacyChromeVisible
    }

    // MARK: - Init

    public init() {
        let appearance = AetherAppearance.runtimeCurrent
        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .tab,
            placement: .tab
        )
        let resolved = AetherTabBarAppearanceResolver.resolve(context: context)
        let tabBarTheme = TabBarView.Theme(aetherResolvedAppearance: resolved)
        self.appearance = appearance
        self.resolvedAppearanceStyle = appearance.style
        self.resolvedAppearance = resolved
        self.appliedTabBarTheme = tabBarTheme
        self.tabBarView = TabBarView(theme: tabBarTheme)

        // Deliberately no nav bar: each tab brings its own through its
        // embedded navigation controller / content screen.
        super.init(navigationBarPresentationData: nil)

        bottomBarAccessoryReduceMotionStatusObserver = NotificationCenter
            .default.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshBottomBarAccessoryReduceMotionStatus()
            }
    }

    @available(*, deprecated, message: "Use app-level AppearanceStyle and AetherControllerAppearanceProviding overrides.")
    public convenience init(tabBarTheme: TabBarView.Theme) {
        self.init()
        compatibilityTabBarTheme = tabBarTheme
        invalidateAppearance()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshBottomBarAccessoryReduceMotionStatus(
        on coordinator: BottomBarAccessoryTransitionCoordinator? = nil
    ) {
        let reduceMotionEnabled = bottomBarAccessoryReduceMotionStatusProvider()
        (coordinator ?? bottomBarAccessoryTransitionCoordinator)?
            .updateReduceMotionEnabled(reduceMotionEnabled)

        // Full Player owns a separate coordinator above. Compact chrome is a
        // UIKit pill animation plus our sampled accessory clock, so explicitly
        // retarget both owners when the accessibility preference changes.
        guard coordinator == nil,
              tabBarMinimizeAnimation != nil else { return }
        let transition: ContainedViewLayoutTransition = reduceMotionEnabled
            ? .animated(duration: 0.20, curve: .easeInOut)
            : Self.tabBarMinimizeMorphTransition
        let targetProgress: CGFloat = isTabBarMinimized ? 1.0 : 0.0
        startTabBarMinimizeAnimation(
            to: targetProgress,
            transition: transition
        )
        let compactAccessoryIsAvailable = expandedAccessoryViewController == nil
        let canDriveCurvedAccessory = compactAccessoryIsAvailable
            && !reduceMotionEnabled
            && _bottomBarAccessory != nil
            && bottomBarAccessoryWrapper?.isHidden == false
            && currentlyAppliedLayout != nil
        pendingAccessoryCompactMorphDirection = canDriveCurvedAccessory
            ? (isTabBarMinimized ? .minimize : .expand)
            : nil
        tabBarView.retargetCurrentMinimizeTransition(transition)
        if compactAccessoryIsAvailable, let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    public func invalidateAppearance() {
        updateAppearance(appearance)
    }

    public func updateAppearance(_ appearance: AetherAppearance) {
        self.appearance = appearance
        var inheritedAppearance = appearance
        if let compatibilityTabBarTheme {
            inheritedAppearance = inheritedAppearance.resolvingAppearanceStyle(
                compatibilityTabBarTheme.appearanceStyle
            )
            inheritedAppearance.overallDarkAppearance = compatibilityTabBarTheme.isDark
            inheritedAppearance.edgeEffectColor = compatibilityTabBarTheme.edgeEffectTintColor
                ?? inheritedAppearance.edgeEffectColor
            inheritedAppearance.edgeEffectAlpha = compatibilityTabBarTheme.edgeEffectAlpha
            inheritedAppearance.edgeEffectBlurRadiusAtEdge = compatibilityTabBarTheme.edgeEffectBlurRadiusAtEdge
            inheritedAppearance.edgeEffectBlurRadiusAtFade = compatibilityTabBarTheme.edgeEffectBlurRadiusAtFade
            inheritedAppearance.edgeEffectStyle = compatibilityTabBarTheme.glassEffectStyle
            inheritedAppearance.separatorColor = compatibilityTabBarTheme.tabBarSeparatorColor
        }
        let overrideResolution = resolveAetherAppearanceOverride(
            appearance: inheritedAppearance,
            surface: .tab,
            placement: .tab,
            traitCollection: traitCollection,
            container: self,
            content: currentAppearanceController
        )
        let compatibilityOverride = compatibilityTabBarTheme.map {
            tabBarCompatibilityOverride(
                from: $0,
                includeRendererFields: overrideResolution.appearance.style == $0.appearanceStyle
            )
        }
        let mergedOverride = compatibilityOverride?
            .merged(with: overrideResolution.override)
            ?? overrideResolution.override
        let context = AetherAppearanceResolutionContext(
            appearance: overrideResolution.appearance,
            surface: .tab,
            placement: .tab,
            traitCollection: traitCollection
        )
        let resolved = AetherTabBarAppearanceResolver.resolve(
            context: context,
            override: mergedOverride?.tabBar
        )
        let previousAppearanceStyle = resolvedAppearanceStyle
        resolvedAppearanceStyle = overrideResolution.appearance.style
        if resolvedAppearanceStyle == .legacy {
            if previousAppearanceStyle.usesLiquidGlass,
               let activeAnimation = tabBarVisibilityContentAnimation {
                let activeElapsed = max(
                    0.0,
                    activeAnimation.elapsed - activeAnimation.timing.delay
                )
                let remainingTiming = TabBarVisibilityContentTiming(
                    duration: max(
                        0.01,
                        activeAnimation.timing.duration - activeElapsed
                    ),
                    delay: max(
                        0.0,
                        activeAnimation.timing.delay - activeAnimation.elapsed
                    )
                )
                let targetHidden = activeAnimation.toHiddenProgress >= 0.5
                startTabBarVisibilityContentAnimation(
                    toHidden: targetHidden,
                    direction: lastTabBarVisibilityContentDirection
                        ?? (targetHidden ? .push : .pop),
                    isInteractive: lastTabBarVisibilityContentWasInteractive,
                    timing: remainingTiming
                )
            } else {
                invalidateTabBarVisibilityDisplayLink()
                tabBarVisibilityContentAnimation = nil
                clearLegacyVisibilityBlurState()
            }
            if let wrapper = bottomBarAccessoryWrapper {
                Self.clearOwnedTransitionBlur(from: wrapper.layer)
            }
            if let outgoingWrapper = bottomBarAccessoryOutgoingWrapper {
                Self.clearOwnedTransitionBlur(from: outgoingWrapper.layer)
            }
        }
        setBottomBarAccessoryPressEnabled(
            bottomBarAccessoryPresentationState == .collapsed
        )
        resolvedAppearance = resolved
        appliedTabBarTheme = resolvedTabBarTheme(
            from: resolved,
            preserving: compatibilityTabBarTheme
        )
        let chromeAppearance = tabBarView.chromeGlassAppearance
        if let wrapper = bottomBarAccessoryWrapper {
            configureBottomBarAccessorySurface(
                wrapper,
                chromeAppearance: chromeAppearance
            )
        }
        if let outgoingWrapper = bottomBarAccessoryOutgoingWrapper {
            configureBottomBarAccessorySurface(
                outgoingWrapper,
                chromeAppearance: chromeAppearance
            )
        }
    }

    private func tabBarCompatibilityOverride(
        from theme: TabBarView.Theme,
        includeRendererFields: Bool
    ) -> AetherAppearanceOverride {
        let background: AetherBarBackgroundAppearance?
        let separator: AetherSeparatorAppearance?
        let edgeEffect: AetherEdgeEffectAppearance?

        if includeRendererFields {
            switch theme.style {
            case .legacy:
                background = .color(theme.tabBarBackgroundColor)
            case .liquidGlass:
                background = theme.enableBlur
                    ? .glass(theme.glassEffectStyle)
                    : .transparent
            }
            separator = .visible(
                color: theme.tabBarSeparatorColor,
                opacity: theme.appearanceStyle == .legacy ? 0.25 : 1.0
            )
            edgeEffect = AetherEdgeEffectAppearance(
                isEnabled: theme.appearanceStyle.usesLiquidGlass,
                tintColor: theme.edgeEffectTintColor,
                alpha: theme.edgeEffectAlpha,
                blurRadiusAtEdge: theme.edgeEffectBlurRadiusAtEdge,
                blurRadiusAtFade: theme.edgeEffectBlurRadiusAtFade,
                solidBlur: theme.edgeEffectSolidBlur,
                style: theme.glassEffectStyle
            )
        } else {
            background = nil
            separator = nil
            edgeEffect = nil
        }

        return AetherAppearanceOverride(
            appearanceStyle: theme.appearanceStyle,
            tabBar: AetherTabBarAppearanceOverride(
                background: background,
                backgroundColor: theme.tabBarBackgroundColor,
                separator: separator,
                edgeEffect: edgeEffect,
                overallDarkAppearance: theme.isDarkAppearanceExplicit ? theme.isDark : nil,
                iconColor: theme.tabBarIconColor,
                selectedIconColor: theme.tabBarSelectedIconColor,
                textColor: theme.tabBarTextColor,
                selectedTextColor: theme.tabBarSelectedTextColor
            )
        )
    }

    private func resolvedTabBarTheme(
        from appearance: AetherTabBarResolvedAppearance,
        preserving compatibilityTheme: TabBarView.Theme?
    ) -> TabBarView.Theme {
        let adapted = TabBarView.Theme(aetherResolvedAppearance: appearance)
        guard let compatibilityTheme else {
            return adapted
        }

        return TabBarView.Theme(
            appearanceStyle: adapted.appearanceStyle,
            tabBarBackgroundColor: adapted.tabBarBackgroundColor,
            tabBarSeparatorColor: adapted.tabBarSeparatorColor,
            tabBarIconColor: adapted.tabBarIconColor,
            tabBarSelectedIconColor: adapted.tabBarSelectedIconColor,
            tabBarTextColor: adapted.tabBarTextColor,
            tabBarSelectedTextColor: adapted.tabBarSelectedTextColor,
            tabBarBadgeBackgroundColor: compatibilityTheme.tabBarBadgeBackgroundColor,
            tabBarBadgeStrokeColor: compatibilityTheme.tabBarBadgeStrokeColor,
            tabBarBadgeTextColor: compatibilityTheme.tabBarBadgeTextColor,
            enableBlur: adapted.enableBlur,
            isDark: adapted.isDark,
            isDarkAppearanceExplicit: adapted.isDarkAppearanceExplicit,
            style: adapted.style,
            outerInsets: compatibilityTheme.outerInsets,
            pillHeight: compatibilityTheme.pillHeight,
            totalHeight: compatibilityTheme.totalHeight,
            bottomInset: compatibilityTheme.bottomInset,
            sideInset: compatibilityTheme.sideInset,
            minimizedSideInset: compatibilityTheme.minimizedSideInset,
            minimizedInterItemSpacing: compatibilityTheme.minimizedInterItemSpacing,
            innerPadding: compatibilityTheme.innerPadding,
            maximumRowWidth: compatibilityTheme.maximumRowWidth,
            preferredItemWidth: compatibilityTheme.preferredItemWidth,
            showcaseSpacing: compatibilityTheme.showcaseSpacing,
            edgeEffectAlpha: adapted.edgeEffectAlpha,
            edgeEffectBlurRadiusAtEdge: adapted.edgeEffectBlurRadiusAtEdge,
            edgeEffectBlurRadiusAtFade: adapted.edgeEffectBlurRadiusAtFade,
            edgeEffectSolidBlur: adapted.edgeEffectSolidBlur,
            glassEffectStyle: adapted.glassEffectStyle,
            edgeEffectTintColor: adapted.edgeEffectTintColor
        )
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        tabBarView.tabSelected = { [weak self] index in
            guard let self = self else { return }
            if index == self._selectedIndex {
                self.handleActiveTabReTap()
            } else {
                self.selectedIndex = index
            }
        }

        tabBarView.tabDoubleTapped = { [weak self] index in
            guard let self, index < self._controllers.count else { return }
            (self._controllers[index] as? AetherViewController)?.tabBarItemPerformDoubleTapAction()
        }

        tabBarView.itemHasDoubleTapAction = { [weak self] index in
            guard let self, index < self._controllers.count else { return false }
            return (self._controllers[index] as? AetherViewController)?.tabBarItemHasDoubleTapAction() ?? false
        }

        tabBarView.tabLongPressed = { [weak self] index, sourceView, gesture in
            guard let self, index < self._controllers.count else { return }

            // Modern menu-items path — resolved via
            // `contextMenuItems(forTabAt:)`, no dependency on the tab's
            // controller being a Aether `ViewController`. Works for
            // plain `UIViewController` and `AetherNavigationController`
            // tabs (which used to fall through the old `as? ViewController`
            // guard and never get a menu).
            let menuItems = self.contextMenuItems(forTabAt: index)
            if !menuItems.isEmpty {
                ContextMenuController.present(
                    source: sourceView,
                    items: menuItems,
                    appearanceStyle: self.appliedTabBarTheme.appearanceStyle
                )
                return
            }

            // Legacy path — requires a Aether `ViewController`. Honour
            // the controller's explicit `tabBarItemContextActionType`
            // choice; silent no-op for non-Aether controllers (their
            // only "new" path is the menu-items API above).
            guard let controller = self._controllers[index] as? AetherViewController else { return }
            switch controller.tabBarItemContextActionType {
            case .none:
                controller.longTapWithTabBar?()
            case .always:
                controller.tabBarItemContextAction(sourceView: sourceView, gesture: gesture)
            case .whenActive:
                if index == self._selectedIndex {
                    controller.tabBarItemContextAction(sourceView: sourceView, gesture: gesture)
                } else {
                    controller.longTapWithTabBar?()
                }
            }
        }

        tabBarView.tabSwipeAction = { [weak self] index, direction in
            guard let self, index < self._controllers.count else { return }
            (self._controllers[index] as? AetherViewController)?.tabBarItemSwipeAction(direction: direction)
        }

        tabBarView.disabledPressed = { [weak self] in
            (self?.currentController as? AetherViewController)?.tabBarDisabledAction()
        }

        // Tap on the collapsed pill in minimized mode → expand back to
        // the full chrome. The tab bar fires this when the user taps
        // the 48×48 active-tab circle.
        tabBarView.onExpandRequested = { [weak self] in
            guard let self else { return }
            self.setTabBarMinimized(false, transition: Self.tabBarMinimizeMorphTransition)
        }

        view.addSubview(tabBarView)

        // `bottomBarAccessory` is a setup-time API too. If it was assigned
        // before the controller loaded its view, materialize the saved value
        // now instead of silently keeping `_bottomBarAccessory` without a
        // wrapper until the caller assigns it a second time.
        if let accessory = _bottomBarAccessory,
           bottomBarAccessoryWrapper == nil {
            installBottomBarAccessory(
                old: nil,
                new: accessory,
                animated: false
            )
        }

        if let current = currentController {
            showController(current, animated: false)
        }

        // After the first tab is shown, subscribe to its primary scroll
        // view if `tabBarMinimizeBehavior` is on. Subsequent tab switches
        // rebind through `transitionToController` / `showController`.
        attachScrollObserverIfPossible()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySelfComputedLayout(transition: .immediate)
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applySelfComputedLayout(transition: .immediate)
    }

    /// When this controller is used as a root (the common case — tab bar
    /// at the window level), there is no parent driving layout for us.
    /// Compute a `ContainerViewLayout` from our own view's bounds + safe
    /// area insets and flow it through `containerLayoutUpdated` so our
    /// tab bar positions itself and the child tab receives an updated
    /// layout.
    private func applySelfComputedLayout(transition: ContainedViewLayoutTransition) {
        let inheritedLayout = hasParentDrivenLayout ? currentlyAppliedLayout : nil
        let layout = ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: inheritedLayout?.safeInsets ?? view.safeAreaInsets,
            additionalInsets: inheritedLayout?.additionalInsets ?? .zero,
            statusBarHeight: view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
            inputHeight: currentlyAppliedLayout?.inputHeight,
            inputHeightIsInteractivellyChanging: currentlyAppliedLayout?.inputHeightIsInteractivellyChanging ?? false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
        isApplyingSelfComputedLayout = true
        containerLayoutUpdated(layout, transition: transition)
        isApplyingSelfComputedLayout = false
    }

    // MARK: - Public API

    private struct ResolvedSearchItem {
        let item: SearchTabItem
        let sourceController: UIViewController
    }

    public func setControllers(_ controllers: [UIViewController], selectedIndex: Int?) {
        teardownPresentedSearchForControllerReplacementIfNeeded()
        let previousController = currentController
        var regularControllers: [UIViewController] = []
        var detectedSearchItem: ResolvedSearchItem?

        for controller in controllers {
            // A SearchTabItem is still provided through a normal
            // UIViewController.tabBarItem slot. When tabs are wrapped in a
            // navigation controller, apps often set it on the root screen
            // instead of the wrapper, so resolve through the visible stack.
            if let item = resolvedSearchItem(for: controller) {
                if detectedSearchItem == nil {
                    detectedSearchItem = item
                }
                continue
            }
            regularControllers.append(controller)
        }

        if detectedSearchItem == nil, shouldPreserveCurrentSearchItem(for: controllers) {
            if let item = searchItem, let sourceController = searchItemSourceController {
                detectedSearchItem = ResolvedSearchItem(item: item, sourceController: sourceController)
            }
        }

        if detectedSearchItem?.item.action == nil {
            detectedSearchItem?.item.action = { [weak self] in
                self?.activateSearch()
            }
        }

        self._controllers = regularControllers
        self.searchItem = detectedSearchItem?.item
        self.searchItemSourceController = detectedSearchItem?.sourceController
        let requestedSelectedIndex = selectedIndex ?? _selectedIndex
        self._selectedIndex = max(0, min(requestedSelectedIndex, max(0, regularControllers.count - 1)))
        regularControllers.forEach(installBottomBarVisibilityCallbacks(on:))
        tabBarView.setSearchItem(detectedSearchItem?.item)

        reloadTabBarItems()

        if let previous = previousController, previous !== currentController {
            detachControllerIfNeeded(previous)
        }

        if let current = currentController, isViewLoaded {
            showController(current, animated: false)
        }

        // New tab tree → new primary scroll view. Drop the old observer
        // and bind to the freshly visible tab's content.
        attachScrollObserverIfPossible()
        invalidateAppearance()
    }

    /// Controller replacement is a synchronous ownership boundary. An
    /// animated Search dismissal would complete against the newly-installed
    /// tree and leave the old search source attached/visible, so retire the
    /// old presentation before mutating `_controllers` or its Search source.
    private func teardownPresentedSearchForControllerReplacementIfNeeded() {
        guard tabBarView.isSearchActive || presentedSearchController != nil else {
            return
        }
        searchTransitionGeneration += 1
        if let searchController = presentedSearchController {
            searchController.view.layer.removeAllAnimations()
            deliverSearchDeactivationLifecycleIfNeeded(to: searchController)
        }
        currentController?.view.layer.removeAllAnimations()

        tabBarView.onSearchDismissed = nil
        tabBarView.deactivateSearchMode(animated: false)
        let restoreExpanded = tabBarMinimizedBeforeSearchActivation == false
        tabBarMinimizedBeforeSearchActivation = nil
        if restoreExpanded, isTabBarMinimized {
            setTabBarMinimized(false, transition: .immediate)
        }

        if let searchController = presentedSearchController {
            detachControllerIfNeeded(searchController)
        }
        presentedSearchController = nil
        currentController?.view.alpha = 1.0
        currentController?.view.transform = .identity
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    /// App lifecycle hooks are override points and may synchronously replace
    /// the controller tree or request another dismissal. Deliver the hook at
    /// most once per synchronous stack; the generation check at the call site
    /// then lets the newest mutation retain ownership of Search teardown.
    private func deliverSearchDeactivationLifecycleIfNeeded(
        to controller: UIViewController
    ) {
        guard !hasDeliveredSearchDeactivationLifecycle,
              !isDeliveringSearchDeactivationLifecycle else { return }
        // Mark the whole Search presentation before entering app code. This
        // prevents both synchronous recursion and a later controller-tree
        // replacement during the dismissal animation from delivering the
        // lifecycle hook twice for one activation.
        hasDeliveredSearchDeactivationLifecycle = true
        isDeliveringSearchDeactivationLifecycle = true
        defer { isDeliveringSearchDeactivationLifecycle = false }
        searchLifecycleController(for: controller)?.tabBarDeactivateSearch()
    }

    /// Reloads titles, icons and badges without detaching or reattaching tab controllers.
    public func reloadTabBarItems() {
        tabBarView.items = _controllers.map { controller in
            let tabItem = controller.tabBarItem
            return AetherTabBarItem(
                title: tabItem?.title ?? "",
                image: tabItem?.image,
                selectedImage: tabItem?.selectedImage,
                badgeValue: tabItem?.badgeValue,
                isEnabled: true
            )
        }
        tabBarView.selectedIndex = _selectedIndex
    }

    public func setScreenNodes(_ nodes: [AetherScreenNode], selectedIndex: Int?) {
        let controllers = nodes.map { node -> AetherScreenController in
            let controller = AetherScreenController(screenNode: node)
            controller.tabBarItem.title = node.navigationItemNode.title
            controller.title = node.navigationItemNode.title
            return controller
        }
        setControllers(controllers, selectedIndex: selectedIndex)
    }

    public func setTabNodes(_ tabs: [AetherTabItemNode], selectedIndex: Int?) {
        let controllers = tabs.map { tab -> AetherScreenController in
            let controller = AetherScreenController(screenNode: tab.contentNode)
            controller.tabBarItem.title = tab.barItemNode.title
            controller.tabBarItem.badgeValue = tab.barItemNode.badgeValue
            controller.title = tab.barItemNode.title
            return controller
        }
        setControllers(controllers, selectedIndex: selectedIndex)
    }

    private func shouldPreserveCurrentSearchItem(for controllers: [UIViewController]) -> Bool {
        guard searchItem != nil, !controllers.isEmpty, controllers.count == _controllers.count else {
            return false
        }
        return zip(controllers, _controllers).allSatisfy { incoming, current in
            incoming === current
        }
    }

    private func resolvedSearchItem(for controller: UIViewController) -> ResolvedSearchItem? {
        if let item = controller.tabBarItem as? SearchTabItem {
            return ResolvedSearchItem(item: item, sourceController: controller)
        }

        if let navigationController = controller as? AetherNavigationController {
            if let item = navigationController.topController?.tabBarItem as? SearchTabItem {
                return ResolvedSearchItem(item: item, sourceController: navigationController)
            }
            if let sourceController = navigationController.viewControllerStack.first(where: { $0.tabBarItem is SearchTabItem }),
               let item = sourceController.tabBarItem as? SearchTabItem {
                return ResolvedSearchItem(item: item, sourceController: navigationController)
            }
            return nil
        }

        if let navigationController = controller as? UINavigationController {
            if let item = navigationController.topViewController?.tabBarItem as? SearchTabItem {
                return ResolvedSearchItem(item: item, sourceController: navigationController)
            }
            if let sourceController = navigationController.viewControllers.first(where: { $0.tabBarItem is SearchTabItem }),
               let item = sourceController.tabBarItem as? SearchTabItem {
                return ResolvedSearchItem(item: item, sourceController: navigationController)
            }
            return nil
        }

        return nil
    }

    public func updateIsTabBarHidden(_ hidden: Bool, transition: ContainedViewLayoutTransition) {
        // The expanded accessory owns a frozen tab-bar docking session. A
        // navigation/search callback may request different chrome underneath
        // it, but applying that request would replace the collapse target.
        guard expandedAccessoryViewController == nil else { return }
        tabBarVisibilityTransitionState = nil
        self.tabBarHidden = hidden
        if transition.isAnimated {
            startTabBarVisibilityContentAnimation(
                toHidden: hidden,
                direction: hidden ? .push : .pop,
                isInteractive: false,
                timing: TabBarVisibilityContentTiming(
                    duration: max(0.01, transition.duration),
                    delay: 0.0
                )
            )
        } else {
            setTabBarVisibilityContentImmediately(hidden: hidden)
        }
        if let layout = currentlyAppliedLayout {
            // Safe-area reservation lands at the logical endpoint eagerly;
            // only the chrome's blur+fade owns the visual clock.
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    public func updateIsTabBarEnabled(_ enabled: Bool, transition: ContainedViewLayoutTransition) {
        tabBarView.updateInteractionsEnabled(enabled, transition: transition)
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        tabBarView.updateBackgroundAlpha(alpha, transition: transition)
    }

    public func frameForControllerTab(controller: UIViewController) -> CGRect? {
        guard let index = _controllers.firstIndex(where: { $0 === controller }) else { return nil }
        return tabBarView.frameForTab(at: index)
    }

    public func isPointInsideContentArea(point: CGPoint) -> Bool {
        if effectiveTabBarHiddenProgress >= 0.999 {
            return true
        }
        let tabBarFrame = tabBarView.frame
        return point.y < tabBarFrame.minY
    }

    /// Frame of the tab bar pill (selection capsule) in `targetView`'s
    /// coordinate space. Returns `nil` if the tab bar hasn't laid out yet
    /// or the two views don't share a window.
    ///
    /// Use this to anchor floating overlays (toolbars, badges, etc.) to
    /// the pill without hardcoding the theme's pill height / bottom
    /// inset, which would drift the moment either is customized.
    public func pillFrame(in targetView: UIView) -> CGRect? {
        guard isViewLoaded, tabBarView.bounds.width > 0 else { return nil }
        let pillInTabBar = tabBarView.pillFrame
        guard pillInTabBar.width > 0 else { return nil }
        return tabBarView.convert(pillInTabBar, to: targetView)
    }

    /// Resolve the list of context-menu items to present on a long-press
    /// of the tab at `index`. Default implementation forwards to
    /// `tabContextMenuItemsProvider`; subclasses may override for more
    /// complex logic (per-state menus, async data, etc.). Returning an
    /// empty array suppresses the menu for that tab.
    open func contextMenuItems(forTabAt index: Int) -> [ContextMenuItem] {
        return tabContextMenuItemsProvider?(index) ?? []
    }

    // MARK: - Layout

    override open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        if !isApplyingSelfComputedLayout {
            hasParentDrivenLayout = true
        }
        // Intentionally NOT calling super: the base `ViewController`
        // implementation assumes this controller owns a nav bar and
        // computes `additionalSafeAreaInsets` for that. TabBarController
        // has no nav bar and needs to set `additionalSafeAreaInsets` to
        // propagate the TAB BAR height instead — letting super run
        // causes the two writers to fight and re-trigger each other via
        // UIKit's "safe area changed → schedule layout" path (infinite
        // recursion).

        // Skip the nested `.immediate` re-entry caused by setting
        // `additionalSafeAreaInsets` mid-pass. See `isApplyingContainerLayout`
        // doc comment — if we let it run we'd snap the accessory frame
        // before the outer animated pass registers its UIView.animate
        // block, killing the morph.
        if isApplyingContainerLayout {
            return
        }
        isApplyingContainerLayout = true
        defer { isApplyingContainerLayout = false }

        updateCurrentContainerLayout(layout)

        let hiddenProgress = effectiveTabBarHiddenProgress
        let chromeVisibleProgress = 1.0 - hiddenProgress
        let layoutVisibleProgress = tabBarLayoutVisibleProgress
        // Use RAW device safe area (not layout.safeInsets which includes
        // our own additionalSafeAreaInsets — using that causes infinite recursion).
        let rawSafeBottom = inheritedSafeAreaBottom
        let tabBarHeight = resolvedTabBarHeight(rawSafeBottom: rawSafeBottom)
        let reservation = bottomBarLayoutReservation(visibleProgress: layoutVisibleProgress, rawSafeBottom: rawSafeBottom)
        beginDeferredScrollSafeAreaReservationIfNeeded(
            targetTotal: reservation.total
        )
        if let heldTotal = deferredScrollSafeAreaReservationTotal,
           abs(heldTotal - reservation.total) <= 0.5 {
            cancelDeferredScrollSafeAreaReservation()
        }
        let childReservationTotal = deferredScrollSafeAreaReservationTotal
            ?? reservation.total
        let childReservation = BottomBarLayoutReservation(
            tabBarContentInset: reservation.tabBarContentInset,
            accessoryTotalReservation: max(
                0.0,
                childReservationTotal - reservation.tabBarContentInset
            ),
            accessoryHeight: reservation.accessoryHeight
        )

        // Accessory chrome pushed onto children in addition to the pill.
        // Hidden when the tab bar itself hides (the accessory has no
        // standalone anchor — it lives on top of the pill).
        // In minimized mode, the accessory reflows INTO the pill row
        // (between the two 48×48 circles), so it no longer reserves
        // vertical space above the pill — children get only the tab
        // bar height and the accessory shares the same row.
        let accessoryHeight = reservation.accessoryHeight

        // Propagate the tab-bar height + accessory reservation to embedded
        // children via UIKit's safe area machinery. Anything below us —
        // embedded nav controllers, plain view controllers — will see
        // their `view.safeAreaInsets.bottom` include both, so they can
        // lay content above our chrome without knowing we exist.
        let desiredChildInsets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: childReservation.total,
            right: 0
        )
        let childSafeAreaInsetsChanged = additionalSafeAreaInsets != desiredChildInsets
        if childSafeAreaInsetsChanged {
            // The accessory changes vertical ownership when it moves into or
            // out of the compact row. Mark the mutation before UIKit rewrites
            // adjustedContentInset/contentOffset so the observer cannot read
            // that delayed compensation as an intentional reverse scroll.
            scrollObserver?.beginOwnedGeometryMutation()
            additionalSafeAreaInsets = desiredChildInsets
        }

        // When tab bar search is active AND keyboard is visible, lift the tab bar above the keyboard
        let isKeyboardVisible = (layout.inputHeight ?? 0) > 0
        let keyboardLift: CGFloat = tabBarView.isSearchActive ? (layout.inputHeight ?? 0) : 0
        let visibleTabBarY: CGFloat = layout.size.height - tabBarHeight - keyboardLift
        let tabBarY: CGFloat = visibleTabBarY
        let tabBarFrame = CGRect(x: 0, y: tabBarY, width: layout.size.width, height: tabBarHeight)
        transition.updateFrame(view: tabBarView, frame: tabBarFrame)
        transition.updateAlpha(view: tabBarView, alpha: chromeVisibleProgress)
        tabBarView.isUserInteractionEnabled = chromeVisibleProgress > 0.01

        // Drive any search-mode geometry that depends on keyboard state.
        // Opening search does not focus the field; this only matters
        // after the user explicitly taps into the input and the keyboard
        // appears.
        tabBarView.setKeyboardVisible(isKeyboardVisible, transition: transition)

        // Search uses the minimized row between the 48pt active-tab
        // button and the trailing search/close controls. A bottom
        // accessory would occupy the same row, so keep it faded for the
        // whole search session, not only while the keyboard is visible.
        let shouldFadeAccessoryForSearch = tabBarView.isSearchActive
        // Kept for the non-minimized fallback path: the search row may
        // be shorter than the full pill, so accessory anchoring needs
        // the row's top offset if a direct caller activates search
        // without first collapsing.
        let searchTopAdjustment: CGFloat = tabBarView.isSearchActive && !isKeyboardVisible
            ? tabBarView.searchRowTopOffset
            : 0

        // Pill frame is computed analytically rather than read after a
        // synchronous `tabBarView.layoutSubviews()` — that synchronous
        // call would override the in-flight morph by re-setting inner
        // frames with `.immediate`, snapping the pill / search circle
        // into place and killing the animation.
        let pillFrameInTab = tabBarView.computePillFrame(in: tabBarFrame.size, minimized: isTabBarMinimized)
        let pillTopInController = tabBarY + pillFrameInTab.minY

        // Position the bottom bar accessory surface.
        //
        // Regular geometry is style-aware: Legacy is attached with 16pt side
        // insets, no gap and a 58pt minimum height; Liquid keeps the theme
        // side inset and its 8pt floating gap.
        // In minimized Liquid geometry the accessory reflows INTO the pill
        // row between the two
        //     48×48 circles (matches iOS 26's `tabBarMinimizeBehavior`,
        //     where the accessory drops down to fill the gap created by
        //     the collapsing tab bar).
        // Skip canonical accessory layout while the wrapper is in its
        // expanded card form — `presentExpandedAccessory` owns the
        // wrapper frame at that point, and overwriting it here mid-
        // morph would yank the card back to the pill position. Layout
        // resumes its normal control once the dismiss morph finishes.
        let updateAccessoryAlpha = { [weak self] (wrapper: GlassBackgroundView) in
            guard let _ = self else { return }
            let target: CGFloat = (shouldFadeAccessoryForSearch ? 0.0 : 1.0) * chromeVisibleProgress
            if abs(wrapper.alpha - target) > 0.001 {
                transition.updateAlpha(view: wrapper, alpha: target)
            }
        }

        if expandedAccessoryViewController != nil {
            // The coordinator owns live surface geometry while expanded. A
            // real container layout change updates both endpoints while
            // preserving the current presentation position; no `.zero`
            // fallback and no per-gesture root relayout are involved.
            if let coordinator = bottomBarAccessoryTransitionCoordinator,
               var presentationSession = accessoryPresentationSession {
                var compactFrame = accessoryTransitionGeometry?.collapsedFrame
                    ?? presentationSession.sourceCollapsedFrame
                var resolvedDockingContext = presentationSession.dockingContext
                // Legacy has no inline/minimized endpoint. A live style switch
                // while Full Player is open must retarget directly to the
                // attached 16pt/58pt slot instead of first collapsing into the
                // stale Liquid row and snapping on the next layout pass.
                if appliedTabBarTheme.appearanceStyle == .legacy {
                    resolvedDockingContext.mode = .regular
                }
                // Re-resolve on every expanded layout. Besides rotation this
                // captures style recipes and dynamic accessory-height changes;
                // the immutable docking context still prevents scroll/search
                // callbacks from stealing the session's attraction point.
                if let recomputedFrame = resolvedBottomBarAccessoryFrame(
                        for: layout,
                        dockingContext: resolvedDockingContext
                   ),
                   recomputedFrame.width > 0,
                   recomputedFrame.height > 0 {
                    compactFrame = recomputedFrame
                    presentationSession.resolvedLayoutSize = layout.size
                    presentationSession.resolvedSafeInsets = layout.safeInsets
                    accessoryPresentationSession = presentationSession
                }

                let updatedGeometry = BottomBarAccessoryTransitionGeometry(
                    collapsedFrame: compactFrame,
                    expandedFrame: CGRect(origin: .zero, size: layout.size),
                    collapsedCornerRadius: resolvedBottomBarAccessoryCornerRadius(
                        for: compactFrame.size
                    ),
                    expandedCornerRadius: 0,
                    safeInsets: layout.safeInsets,
                    layoutSize: layout.size
                )
                let geometryChanged = accessoryTransitionGeometry != updatedGeometry
                accessoryTransitionGeometry = updatedGeometry
                _bottomBarAccessory?.frame = CGRect(
                    origin: .zero,
                    size: compactFrame.size
                )
                bottomBarAccessoryExpandedContentHost?.frame = CGRect(
                    origin: .zero,
                    size: layout.size
                )
                bottomBarAccessorySharedElementHost?.frame = CGRect(
                    origin: .zero,
                    size: layout.size
                )
                expandedAccessoryViewController?.view.frame = CGRect(
                    origin: .zero,
                    size: layout.size
                )
                if let controller = expandedAccessoryViewController
                    as? AetherViewController {
                    controller.containerLayoutUpdated(layout, transition: transition)
                } else {
                    expandedAccessoryViewController?.view.setNeedsLayout()
                    expandedAccessoryViewController?.view.layoutIfNeeded()
                }
                // UIKit can ask for root layout while system chrome is being
                // invalidated during a display-link sample. Re-targeting the
                // same endpoints would capture and restart the spring every
                // frame, leaving its presentation layer apparently pinned.
                // Only real endpoint changes (rotation, resize, docking)
                // belong on the coordinator's geometry-retarget path.
                if geometryChanged {
                    coordinator.updateGeometry(
                        updatedGeometry,
                        preservingVisualState: true
                    )
                }
            }
        } else if isTabBarMinimized,
                  _bottomBarAccessory != nil,
                  let wrapper = bottomBarAccessoryWrapper,
                  chromeVisibleProgress > 0.001 || isTabBarVisibilityContentAnimationActive {
            let accessoryFrame = resolvedInlineAccessoryFrame(
                layoutWidth: layout.size.width,
                pillTopInController: pillTopInController
            )
            let compactMorphDirection = pendingAccessoryCompactMorphDirection
            pendingAccessoryCompactMorphDirection = nil
            applyAccessoryFrame(
                wrapper,
                frame: accessoryFrame,
                transition: transition,
                compactMorphDirection: compactMorphDirection
            )
            wrapper.isHidden = false
            updateAccessoryAlpha(wrapper)
            view.bringSubviewToFront(wrapper)
        } else if let _ = _bottomBarAccessory, let wrapper = bottomBarAccessoryWrapper, accessoryHeight > 0 {
            let accessoryAnchorY = pillTopInController + searchTopAdjustment
            let accessoryY = accessoryAnchorY
                - resolvedBottomBarAccessoryBottomGap
                - accessoryHeight
            let sideInset = resolvedBottomBarAccessorySideInset
            let accessoryWidth = max(0, layout.size.width - sideInset * 2)
            let accessoryFrame = resolvedScrollMinimizeArmedAccessoryFrame(
                CGRect(
                    x: sideInset,
                    y: accessoryY,
                    width: accessoryWidth,
                    height: accessoryHeight
                )
            )
            let compactMorphDirection = pendingAccessoryCompactMorphDirection
            pendingAccessoryCompactMorphDirection = nil
            applyAccessoryFrame(
                wrapper,
                frame: accessoryFrame,
                transition: transition,
                compactMorphDirection: compactMorphDirection
            )
            wrapper.isHidden = chromeVisibleProgress <= 0.001
                && !isTabBarVisibilityContentAnimationActive
            updateAccessoryAlpha(wrapper)
            if chromeVisibleProgress > 0.001 {
                view.bringSubviewToFront(wrapper)
            }
        } else if let wrapper = bottomBarAccessoryWrapper {
            // Tab bar hidden (or accessory set but h == 0) — park wrapper
            // off-screen so child layout isn't affected by stale frames.
            wrapper.isHidden = !isTabBarVisibilityContentAnimationActive
        }
        // A mode request is valid for this layout pass only. Keeping it after
        // a hidden/zero-height branch would make an unrelated later resize
        // replay a stale minimize/expand choreography.
        pendingAccessoryCompactMorphDirection = nil

        // Extend the bottom chrome's material region upward to cover the
        // accessory + its style-resolved bottom gap. Liquid uses its edge
        // effect; Legacy extends the tab bar's single NavigationBackgroundView.
        // Scroll content then dissolves through both as one visual band.
        //
        // While the accessory is faded out for the search keyboard, the
        // material region should snap back to the tab bar's own height — leaving
        // the extension up would render a tall blur band over content
        // with nothing actually sitting in it. `additionalSafeAreaInsets`
        // (computed above) keeps using the canonical reservation so
        // child controllers don't dance their content up and down as
        // the keyboard toggles.
        // Legacy groups the tab-bar and accessory effects onto one backdrop.
        // During a hide animation the logical safe-area endpoint changes
        // immediately, but the progressive extension must remain until UIKit
        // finishes fading the still-visible wrapper. Showing already resolves
        // to progress 1.
        let materialVisibleProgress = appliedTabBarTheme.appearanceStyle == .legacy
            && isLegacyTabBarVisibilityAlphaAnimating
            ? 1.0
            : layoutVisibleProgress
        let canonicalVisibleAccessoryReservation: CGFloat = shouldFadeAccessoryForSearch
            ? 0
            : materialVisibleProgress * max(
                0,
                (
                    accessoryHeight > 0
                        ? accessoryHeight + resolvedBottomBarAccessoryBottomGap
                        : 0
                ) - searchTopAdjustment
            )
        let outgoingVisibleAccessoryReservation: CGFloat = shouldFadeAccessoryForSearch
            ? 0.0
            : materialVisibleProgress * bottomBarAccessoryOutgoingVisualReservation
        let visibleAccessoryReservation = max(
            canonicalVisibleAccessoryReservation,
            outgoingVisibleAccessoryReservation
        )
        if tabBarView.bottomAccessoryReservedHeight != visibleAccessoryReservation {
            transition.animateView { [weak tabBarView] in
                tabBarView?.bottomAccessoryReservedHeight = visibleAccessoryReservation
                tabBarView?.layoutIfNeeded()
            }
        }

        if let current = currentController {
            transition.updateFrame(view: current.view, frame: CGRect(origin: .zero, size: layout.size))
            // `additionalSafeAreaInsets` reaches descendant UIKit views before
            // their Aether container layout is necessarily recomputed. Settle
            // that propagation after installing the target frame, then send
            // one canonical explicit layout below. Otherwise a child can keep
            // the previous accessory reservation until the next push/pop and
            // move its list by exactly that stale delta.
            if childSafeAreaInsetsChanged,
               tabBarVisibilityTransitionState == nil,
               !isTabBarVisibilityContentAnimationActive {
                settleChildSafeAreaPropagation(current)
            }
            // Our AetherNavigationController recomputes its own layout
            // from `view.safeAreaInsets` in `viewDidLayoutSubviews`, so
            // setting `self.additionalSafeAreaInsets` above is enough —
            // UIKit will flow the new safe-area into the child and
            // trigger a layout pass there. We still forward an explicit
            // containerLayoutUpdated for non-AetherNavigation children
            // that rely on our layout object shape.
            let childLayout = childLayout(from: layout, reservation: childReservation)
            if let navController = current as? AetherNavigationController {
                // During an interactive/programmatic nav transition where only
                // `hidesBottomBarWhenPushed` visibility is changing, do not
                // re-enter the child navigation controller on every tab-bar
                // alpha tick. Its root container already owns the active
                // push/pop layers; reapplying the updated stack here can make
                // the lower transition layer resolve to the top controller's
                // view, which looks like the pushed screen was duplicated.
                if tabBarVisibilityTransitionState == nil,
                   !isTabBarVisibilityContentAnimationActive {
                    navController.containerLayoutUpdated(childLayout, transition: transition)
                }
            } else if let tgController = current as? AetherViewController {
                tgController.containerLayoutUpdated(childLayout, transition: transition)
            }
        }

        if let searchController = presentedSearchController {
            transition.updateFrame(view: searchController.view, frame: CGRect(origin: .zero, size: layout.size))
            if childSafeAreaInsetsChanged {
                settleChildSafeAreaPropagation(searchController)
            }
            let searchLayout = childLayout(from: layout, reservation: childReservation)
            if let navigationController = searchController as? AetherNavigationController {
                navigationController.containerLayoutUpdated(searchLayout, transition: transition)
            } else if let controller = searchController as? AetherViewController {
                controller.containerLayoutUpdated(searchLayout, transition: transition)
            }
        }

        // While expanded, the player is the top overlay and the tab bar stays
        // in the layer underneath it. In collapsed state the accessory pill
        // also sits above the tab bar, with the same z-order continuity.
        if expandedAccessoryViewController != nil, let wrapper = bottomBarAccessoryWrapper {
            view.bringSubviewToFront(wrapper)
            if let sharedElementHost = bottomBarAccessorySharedElementHost,
               sharedElementHost.superview === view {
                view.bringSubviewToFront(sharedElementHost)
            }
        } else {
            view.bringSubviewToFront(tabBarView)
            if let wrapper = bottomBarAccessoryWrapper, !wrapper.isHidden {
                view.bringSubviewToFront(wrapper)
            }
        }

        // After layout settles, re-check the observed scroll view —
        // push/pop inside the visible tab swaps in a new top controller
        // (and therefore a new primary scroll view) without going
        // through `transitionToController`, so the binding has to be
        // refreshed here too. Idempotent when the scroll view hasn't
        // changed.
        attachScrollObserverIfPossible()
    }

    /// Y coordinate (in `targetView`'s coord space) of the topmost edge
    /// of the tab bar's visible chrome — the accessory top when one is
    /// installed, otherwise the pill top. Floating overlays (toolbars,
    /// banners) should anchor to this so they always sit above whatever
    /// chrome is currently showing.
    public func chromeTopY(in targetView: UIView) -> CGFloat? {
        guard isViewLoaded, tabBarView.bounds.width > 0 else { return nil }
        guard effectiveTabBarHiddenProgress < 0.999 else { return nil }
        if let wrapper = bottomBarAccessoryWrapper, !wrapper.isHidden {
            let origin = wrapper.convert(CGPoint.zero, to: targetView)
            return origin.y
        }
        let pillInTabBar = tabBarView.pillFrame
        guard pillInTabBar.width > 0 else { return nil }
        let pillTopInTargetView = tabBarView.convert(CGPoint(x: pillInTabBar.minX, y: pillInTabBar.minY), to: targetView)
        return pillTopInTargetView.y
    }

    /// Activate tab bar search: expands the search button into a search field.
    /// Does NOT affect the navigation bar — that's a separate action.
    public func activateSearch() {
        guard expandedAccessoryViewController == nil,
              !tabBarView.isSearchActive,
              presentedSearchController == nil,
              let searchController = searchItemSourceController else { return }

        searchTransitionGeneration += 1
        let generation = searchTransitionGeneration
        guard attachSearchControllerForPresentation(searchController) else { return }
        hasDeliveredSearchDeactivationLifecycle = false
        searchLifecycleController(for: searchController)?.tabBarActivateSearch()
        guard searchTransitionGeneration == generation,
              presentedSearchController === searchController else {
            return
        }

        tabBarMinimizedBeforeSearchActivation = isTabBarMinimized
        if !isTabBarMinimized {
            setTabBarMinimized(true, transition: Self.tabBarMinimizeMorphTransition)
        }
        tabBarView.onSearchDismissed = { [weak self] in
            self?.deactivateSearch()
        }
        tabBarView.activateSearchMode(animated: true)

        // `isSearchActive` changes after the minimize layout above. Request a
        // second pass immediately so an already-minimized bar still fades its
        // accessory out of the Search row instead of waiting for a keyboard or
        // unrelated layout notification.
        requestLayout(
            transition: .animated(
                duration: AetherMotion.search.presentation.duration,
                curve: .easeInOut
            )
        )

        let profile = AetherMotion.search.presentation
        UIView.animate(
            withDuration: profile.duration,
            delay: 0.0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) { [weak self, weak searchController] in
            guard let self, let searchController else { return }
            searchController.view.alpha = 1.0
            searchController.view.transform = .identity
            self.currentController?.view.alpha = 0.0
            self.currentController?.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        } completion: { [weak self] _ in
            guard let self, self.searchTransitionGeneration == generation else { return }
            self.currentController?.view.alpha = 0.0
        }
    }

    /// Deactivate tab bar search: collapses the search field back to the tab bar.
    public func deactivateSearch() {
        guard expandedAccessoryViewController == nil,
              tabBarView.isSearchActive || presentedSearchController != nil else {
            return
        }
        searchTransitionGeneration += 1
        let generation = searchTransitionGeneration
        let searchController = presentedSearchController
        if let searchController {
            deliverSearchDeactivationLifecycleIfNeeded(to: searchController)
            // The override is allowed to replace the tab tree or recursively
            // request dismissal. In that case its newer generation already
            // owns teardown; do not animate stale views against the new tree.
            guard searchTransitionGeneration == generation,
                  presentedSearchController === searchController else {
                return
            }
        }

        let restoreExpanded = tabBarMinimizedBeforeSearchActivation == false
        tabBarMinimizedBeforeSearchActivation = nil

        tabBarView.deactivateSearchMode(animated: true)
        if restoreExpanded {
            setTabBarMinimized(false, transition: Self.tabBarMinimizeMorphTransition)
        }
        // When dismissed via the active-tab circle the keyboard is
        // already down, so no `keyboardWillHide` notification fires to
        // re-run our `containerLayoutUpdated` — the accessory would be
        // left at its search-row offset / shrunken frost reservation.
        // Force a layout pass through the same transition used by the
        // search collapse so the accessory and frost spring back to
        // their canonical position together with the chrome morph.
        requestLayout(
            transition: .animated(
                duration: AetherMotion.search.dismissal.duration,
                curve: .easeInOut
            )
        )

        let profile = AetherMotion.search.dismissal
        UIView.animate(
            withDuration: profile.duration,
            delay: 0.0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) { [weak self, weak searchController] in
            guard let self else { return }
            searchController?.view.alpha = 0.0
            searchController?.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            self.currentController?.view.alpha = 1.0
            self.currentController?.view.transform = .identity
        } completion: { [weak self, weak searchController] _ in
            guard let self, self.searchTransitionGeneration == generation else { return }
            if let searchController {
                self.detachControllerIfNeeded(searchController)
            }
            self.presentedSearchController = nil
            self.currentController?.view.alpha = 1.0
            self.currentController?.view.transform = .identity
            // The dismissal layout above intentionally ran while Search was
            // still the presented source. Rebind only after ownership is
            // cleared so the underlying tab/page immediately restores its
            // own nav/tab endpoint instead of keeping Search's KVO observer.
            self.invalidateTabBarMinimizeScrollView()
        }
    }

    @discardableResult
    private func attachSearchControllerForPresentation(_ controller: UIViewController) -> Bool {
        guard controller !== currentController else { return false }
        guard controller.parent == nil || controller.parent === self else { return false }

        controller.loadViewIfNeeded()
        if controller.view.backgroundColor == nil {
            controller.view.backgroundColor = .systemBackground
        }
        controller.view.layer.removeAllAnimations()
        controller.view.frame = view.bounds
        controller.view.alpha = 0.0
        controller.view.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)

        let didAttach = attachControllerIfNeeded(controller)
        view.insertSubview(controller.view, belowSubview: tabBarView)
        if didAttach {
            controller.didMove(toParent: self)
        }
        presentedSearchController = controller
        view.bringSubviewToFront(tabBarView)

        if let layout = currentlyAppliedLayout {
            let rawSafeBottom = inheritedSafeAreaBottom
            let reservation = bottomBarLayoutReservation(
                visibleProgress: tabBarLayoutVisibleProgress,
                rawSafeBottom: rawSafeBottom
            )
            let resolvedLayout = childLayout(from: layout, reservation: reservation)
            if let navigationController = controller as? AetherNavigationController {
                navigationController.containerLayoutUpdated(resolvedLayout, transition: .immediate)
            } else if let controller = controller as? AetherViewController {
                controller.containerLayoutUpdated(resolvedLayout, transition: .immediate)
            }
        }
        return true
    }

    private func searchLifecycleController(for controller: UIViewController) -> AetherViewController? {
        if let navigationController = controller as? AetherNavigationController {
            return navigationController.topController
        }
        if let navigationController = controller as? UINavigationController {
            return navigationController.topViewController as? AetherViewController
        }
        return controller as? AetherViewController
    }

    #if DEBUG
    func simulateMinimizedActiveTabTapForTests() {
        tabBarView.simulateMinimizedActiveTabTapForTests()
    }
    #endif

    // MARK: - Private

    private func installBottomBarVisibilityCallbacks(on controller: UIViewController) {
        guard let navigationController = controller as? AetherNavigationController else {
            return
        }

        navigationController.layoutForController = { [weak self, weak navigationController] controller, baseLayout in
            guard let self, let navigationController, self.currentController === navigationController else {
                return baseLayout
            }
            return self.bottomBarAdjustedLayout(
                for: controller,
                in: navigationController,
                baseLayout: baseLayout
            )
        }

        navigationController.bottomBarVisibilityTransitionBegan = { [weak self, weak navigationController] direction, sourceController, targetController, isInteractive in
            guard let self, let navigationController, self.currentController === navigationController else {
                return
            }
            self.beginBottomBarVisibilityTransition(
                in: navigationController,
                direction: direction,
                sourceController: sourceController,
                targetController: targetController,
                isInteractive: isInteractive
            )
        }
        navigationController.bottomBarVisibilityTransitionProgress = { [weak self, weak navigationController] progress, transition in
            guard let self, let navigationController, self.currentController === navigationController else {
                return
            }
            self.updateBottomBarVisibilityTransition(progress: progress, transition: transition)
        }
        navigationController.bottomBarVisibilityTransitionResolutionBegan = { [weak self, weak navigationController] completed, transition in
            guard let self, let navigationController, self.currentController === navigationController else {
                return
            }
            self.resolveBottomBarVisibilityTransition(completed: completed, transition: transition)
        }
        navigationController.bottomBarVisibilityTransitionEnded = { [weak self, weak navigationController] completed in
            guard let self, let navigationController, self.currentController === navigationController else {
                return
            }
            self.finishBottomBarVisibilityTransition(completed: completed)
            navigationController.suppressesSelfComputedLayoutDuringBottomBarTransition = false

            // Resolve per-screen chrome only after the navigation transition
            // has committed (or rolled back). During an interactive pop the
            // source controller remains authoritative until this callback;
            // resolving earlier can leave the source screen's forced-dark
            // icon colors on the light destination tab bar.
            self.invalidateAppearance()
        }
    }

    private func bottomBarAdjustedLayout(
        for controller: AetherViewController,
        in navigationController: AetherNavigationController,
        baseLayout: ContainerViewLayout
    ) -> ContainerViewLayout {
        let rawSafeBottom = inheritedSafeAreaBottom
        let baseVisibleProgress: CGFloat
        if let state = tabBarVisibilityTransitionState {
            baseVisibleProgress = state.sourceHidden ? 0.0 : 1.0
        } else {
            baseVisibleProgress = tabBarHidden ? 0.0 : 1.0
        }
        let baseReservation = bottomBarLayoutReservation(
            visibleProgress: baseVisibleProgress,
            rawSafeBottom: rawSafeBottom
        )
        let targetVisibleProgress: CGFloat = bottomBarHidden(for: controller, in: navigationController) ? 0.0 : 1.0
        let targetReservation = bottomBarLayoutReservation(
            visibleProgress: targetVisibleProgress,
            rawSafeBottom: rawSafeBottom
        )

        var additionalInsets = baseLayout.additionalInsets
        additionalInsets.bottom = max(
            0.0,
            additionalInsets.bottom - baseReservation.total + targetReservation.total
        )
        return baseLayout.withUpdatedAdditionalInsets(additionalInsets)
    }

    private func bottomBarHidden(for controller: AetherViewController, in navigationController: AetherNavigationController) -> Bool {
        guard controller.hidesBottomBarWhenPushed else {
            return false
        }
        guard let rootController = navigationController.viewControllerStack.first else {
            return controller.hidesBottomBarWhenPushed
        }
        return controller !== rootController
    }

    private func bottomBarHiddenForCurrentController() -> Bool {
        guard let navigationController = currentController as? AetherNavigationController,
              let topController = navigationController.topController
        else {
            return false
        }
        return bottomBarHidden(for: topController, in: navigationController)
    }

    private func syncTabBarHiddenForCurrentController(transition: ContainedViewLayoutTransition) {
        guard expandedAccessoryViewController == nil,
              tabBarVisibilityTransitionState == nil else {
            return
        }
        let hidden = bottomBarHiddenForCurrentController()
        guard tabBarHidden != hidden else {
            return
        }
        tabBarHidden = hidden
        if transition.isAnimated {
            startTabBarVisibilityContentAnimation(
                toHidden: hidden,
                direction: hidden ? .push : .pop,
                isInteractive: false,
                timing: TabBarVisibilityContentTiming(
                    duration: max(0.01, transition.duration),
                    delay: 0.0
                )
            )
        } else {
            setTabBarVisibilityContentImmediately(hidden: hidden)
        }
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    private func beginBottomBarVisibilityTransition(
        in navigationController: AetherNavigationController,
        direction: NavigationTransitionDirection,
        sourceController: AetherViewController,
        targetController: AetherViewController,
        isInteractive: Bool
    ) {
        guard expandedAccessoryViewController == nil else {
            navigationController.suppressesSelfComputedLayoutDuringBottomBarTransition = false
            return
        }
        let sourceHidden = bottomBarHidden(for: sourceController, in: navigationController)
        let targetHidden = bottomBarHidden(for: targetController, in: navigationController)
        navigationController.suppressesSelfComputedLayoutDuringBottomBarTransition = sourceHidden != targetHidden
        tabBarHidden = targetHidden

        if sourceHidden == targetHidden {
            tabBarVisibilityTransitionState = nil
        } else {
            tabBarVisibilityTransitionState = TabBarVisibilityTransitionState(
                direction: direction,
                sourceHidden: sourceHidden,
                targetHidden: targetHidden,
                isInteractive: isInteractive,
                progress: 0.0,
                resolvedCompleted: nil
            )
            // Interactive pop starts the same autonomous default animation at
            // gesture begin. Progress/velocity only move the screen; they never
            // scrub or compress tab chrome. A cancelled gesture starts the same
            // fixed clock back toward the source state in `resolve...`.
            startTabBarVisibilityContentAnimation(
                toHidden: targetHidden,
                direction: direction,
                isInteractive: isInteractive
            )
        }

        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    private func updateBottomBarVisibilityTransition(progress: CGFloat, transition _: ContainedViewLayoutTransition) {
        guard var state = tabBarVisibilityTransitionState else {
            return
        }
        state.progress = progress
        tabBarVisibilityTransitionState = state
    }

    private func resolveBottomBarVisibilityTransition(completed: Bool, transition _: ContainedViewLayoutTransition) {
        guard var state = tabBarVisibilityTransitionState else {
            return
        }
        state.progress = completed ? 1.0 : 0.0
        state.resolvedCompleted = completed
        tabBarVisibilityTransitionState = state
        if state.isInteractive && !completed {
            startTabBarVisibilityContentAnimation(
                toHidden: state.sourceHidden,
                direction: state.direction,
                isInteractive: true
            )
        }
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    private func finishBottomBarVisibilityTransition(completed: Bool) {
        guard expandedAccessoryViewController == nil else { return }
        if let state = tabBarVisibilityTransitionState {
            tabBarHidden = completed ? state.targetHidden : state.sourceHidden
        } else {
            tabBarHidden = bottomBarHiddenForCurrentController()
        }
        tabBarVisibilityTransitionState = nil
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    /// Respond to a tap on the already-selected tab.
    ///
    /// Native-iOS behaviour the user expects:
    ///   1. Nav stack has anything pushed → `popToRoot(animated:)`.
    ///   2. Already at root → scroll the visible content to top.
    ///      Prefers the explicit `scrollToTopWithTabBar` closure on
    ///      the top controller, falls back to the first scrollable
    ///      view inside the controller's view hierarchy so the
    ///      behaviour works out of the box without the controller
    ///      having to wire the closure.
    private func handleActiveTabReTap() {
        AetherTabReselectionRouter.perform(from: currentController)
    }

    /// Breadth-first search for the first visible `UIScrollView`
    /// descendant. BFS (not DFS) because a typical screen layout puts
    /// the main content scroll view near the top of the subview list —
    /// DFS would prefer nested scroll views inside menus, headers, etc.
    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        var queue: [UIView] = [view]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scroll = next as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01 {
                return scroll
            }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }

    private func transitionToController(at index: Int, from previousIndex: Int, animated: Bool) {
        guard index < _controllers.count else { return }
        let newController = _controllers[index]
        installBottomBarVisibilityCallbacks(on: newController)

        for (controllerIndex, controller) in _controllers.enumerated() where controller.isViewLoaded {
            controller.view.layer.removeAllAnimations()
            if controllerIndex == index { continue }
            detachControllerIfNeeded(controller)
            controller.view.alpha = 1.0
            controller.view.transform = .identity
        }

        if animated {
            newController.view.frame = view.bounds
            // iOS 18-style tab switch: barely-noticeable scale + fade.
            newController.view.alpha = 0.0
            newController.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)

            let didAttach = attachControllerIfNeeded(newController)
            view.insertSubview(newController.view, belowSubview: tabBarView)
            if didAttach {
                newController.didMove(toParent: self)
            }
            view.bringSubviewToFront(tabBarView)
            let profile = AetherMotion.tabBarSelection
            let contentTransition: ContainedViewLayoutTransition = .animated(
                duration: profile.duration,
                curve: .customSpring(
                    damping: profile.dampingRatio,
                    initialVelocity: profile.initialVelocity
                )
            )
            syncTabBarHiddenForCurrentController(transition: contentTransition)

            UIView.animate(
                withDuration: profile.duration,
                delay: 0,
                usingSpringWithDamping: profile.dampingRatio,
                initialSpringVelocity: profile.initialVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    newController.view.alpha = 1.0
                    newController.view.transform = .identity
                },
                completion: { [weak self] finished in
                    guard let self else { return }
                    guard finished, self._selectedIndex == index else { return }
                    newController.view.transform = .identity
                    if let layout = self.currentlyAppliedLayout {
                        self.containerLayoutUpdated(layout, transition: .immediate)
                    }
                }
            )
        } else {
            showController(newController, animated: false)
        }

        // Tab swap → bind the scroll observer to the new tab's content
        // so the next scroll-down minimize fires off this tab's data.
        attachScrollObserverIfPossible()
    }

    private func showController(_ controller: UIViewController, animated: Bool) {
        installBottomBarVisibilityCallbacks(on: controller)
        let didAttach = attachControllerIfNeeded(controller)
        controller.view.frame = view.bounds
        view.insertSubview(controller.view, belowSubview: tabBarView)
        if didAttach {
            controller.didMove(toParent: self)
        }
        view.bringSubviewToFront(tabBarView)
        syncTabBarHiddenForCurrentController(
            transition: animated
                ? .animated(
                    duration: AetherMotion.tabBarSelection.duration,
                    curve: .customSpring(
                        damping: AetherMotion.tabBarSelection.dampingRatio,
                        initialVelocity: AetherMotion.tabBarSelection.initialVelocity
                    )
                )
                : .immediate
        )

        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    @discardableResult
    private func attachControllerIfNeeded(_ controller: UIViewController) -> Bool {
        guard controller.parent !== self else { return false }
        addChild(controller)
        return true
    }

    private func detachControllerIfNeeded(_ controller: UIViewController) {
        controller.view.removeFromSuperview()
        guard controller.parent === self else { return }
        controller.willMove(toParent: nil)
        controller.removeFromParent()
    }

    @objc private func handleAccessoryDismissGesture(
        _ recognizer: InteractiveTransitionGestureRecognizer
    ) {
        guard let coordinator = bottomBarAccessoryTransitionCoordinator,
              let wrapper = bottomBarAccessoryWrapper,
              expandedAccessoryViewController != nil else {
            return
        }

        switch recognizer.state {
        case .began:
            accessoryDismissDragActive = false
            accessoryDismissScrollHandoff.reset()
            accessoryDismissScrollHandoff.captureCandidate(
                at: recognizer.location(in: wrapper),
                in: wrapper
            )
            updateAccessoryDismissDrag(
                recognizer,
                coordinator: coordinator
            )

        case .changed:
            updateAccessoryDismissDrag(
                recognizer,
                coordinator: coordinator
            )

        case .ended, .cancelled, .failed:
            defer {
                accessoryDismissDragActive = false
                accessoryDismissScrollHandoff.reset()
            }
            guard accessoryDismissDragActive else { return }

            let translationY = recognizer.translation(in: view).y
            let velocityY = recognizer.velocity(in: view).y
            refreshBottomBarAccessoryReduceMotionStatus(on: coordinator)
            if accessoryForcedCollapse {
                coordinator.updateDrag(translationY: translationY)
                coordinator.settle(
                    to: .collapsed,
                    initialVelocity: velocityY
                )
            } else {
                _ = coordinator.endDrag(
                    translationY: translationY,
                    velocityY: velocityY,
                    reason: BottomBarAccessoryGestureEndReason(
                        gestureState: recognizer.state
                    )
                )
            }

        default:
            break
        }
    }

    /// Begins or advances a direct accessory drag from the recognizer's
    /// current sample. The first direction-validated move arrives as
    /// `.began`, so both `.began` and `.changed` must use this path for the
    /// surface to track the finger without a one-event dead zone.
    private func updateAccessoryDismissDrag(
        _ recognizer: InteractiveTransitionGestureRecognizer,
        coordinator: BottomBarAccessoryTransitionCoordinator
    ) {
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)

        if !accessoryDismissDragActive {
            guard case let .begin(translationOriginY) =
                accessoryDismissScrollHandoff.decision(
                    translationY: translation.y,
                    velocityY: velocity.y
                ) else {
                return
            }
            // A direct surface drag must include the recognizer's first valid
            // translation. Only a gesture that genuinely waited for a nested
            // scroll view to reach its top rebases at the handoff sample.
            refreshBottomBarAccessoryReduceMotionStatus(on: coordinator)
            guard coordinator.beginDrag(
                translationOriginY: translationOriginY
            ) else {
                return
            }
            accessoryDismissDragActive = true
            accessoryDismissScrollHandoff.commitHandoff()
        }

        accessoryDismissScrollHandoff.pinCommittedScrollToTop()
        coordinator.updateDrag(translationY: translation.y)
    }

    deinit {
        if let bottomBarAccessoryReduceMotionStatusObserver {
            NotificationCenter.default.removeObserver(
                bottomBarAccessoryReduceMotionStatusObserver
            )
        }
        invalidateTabBarVisibilityDisplayLink()
        invalidateAccessoryCompactMorphDisplayLink()
        if let accessoryLayer = bottomAccessoryVisibilityBlurLayer {
            Self.updateManagedVisibilityBlurFilter(
                &bottomAccessoryVisibilityBlurFilter,
                on: accessoryLayer,
                radius: 0.0
            )
        }
        Self.updateManagedVisibilityBlurFilter(
            &tabBarVisibilityBlurFilter,
            on: tabBarView.layer,
            radius: 0.0
        )
    }
}

extension AetherTabBarController: BottomBarAccessoryTransitionCoordinatorDelegate {
    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didChangeState state: BottomBarAccessoryPresentationState
    ) {
        guard coordinator === bottomBarAccessoryTransitionCoordinator else {
            return
        }
        bottomBarAccessoryWrapper?
            .transitionContentPassesUnclaimedTouchesToMaterial =
                false
        bottomBarAccessoryWrapper?.transitionMaterialInteractionEnabled = false
        setBottomBarAccessoryPressEnabled(state == .collapsed)
        applyBottomBarAccessoryAccessibilityOwnership(for: state)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didUpdateSurfaceGeometry surfaceGeometry: BottomBarAccessorySurfaceGeometry,
        context: BottomBarAccessoryTransitionContext
    ) {
        guard coordinator === bottomBarAccessoryTransitionCoordinator,
              let wrapper = bottomBarAccessoryWrapper else {
            return
        }

        let previousPresentationProgress = accessoryPresentationProgress
        accessoryPresentationProgress = context.presentationProgress
        // A normal native settle owns the material hierarchy on Core
        // Animation using the surface's exact key lattice. Display link still
        // publishes state/participant samples, but must not wake the effect
        // view's layout and mask hierarchy every frame. Interactive drag,
        // Reduce Motion, and the legacy renderer remain direct.
        let preservesCapturedGlassForRetarget =
            wrapper.hasPendingTransitionCompositorPresentation
            && context.state != .dragging
        if !wrapper.isTransitionCompositorSettleActive,
           !preservesCapturedGlassForRetarget {
            wrapper.updateInteractiveGeometry(
                size: surfaceGeometry.bounds.size,
                cornerRadius: surfaceGeometry.cornerRadius
            )
            let materialAlpha = Self.bottomBarAccessoryMaterialAlpha(
                presentationProgress: context.presentationProgress
            )
            if abs(wrapper.transitionMaterialAlpha - materialAlpha) > 0.000_1 {
                wrapper.transitionMaterialAlpha = materialAlpha
            }
        }
        if wrapper.layer.cornerCurve != .continuous {
            wrapper.layer.cornerCurve = .continuous
        }
        if wrapper.isHidden {
            wrapper.isHidden = false
        }

        // Endpoint content owns stable, independent layout spaces. These
        // frames do not interpolate and neither subtree is re-laid out at
        // display-link frequency; the changing glass surface clips them.
        let collapsedBounds = CGRect(
            origin: .zero,
            size: context.geometry.collapsedFrame.size
        )
        let expandedBounds = CGRect(
            origin: .zero,
            size: context.geometry.expandedFrame.size
        )
        let stableFramesNeedUpdate =
            _bottomBarAccessory?.frame != collapsedBounds
            || bottomBarAccessoryExpandedContentHost?.frame != expandedBounds
            || expandedAccessoryViewController?.view.frame != expandedBounds
            || bottomBarAccessorySharedElementHost?.frame != expandedBounds
        if stableFramesNeedUpdate {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if _bottomBarAccessory?.frame != collapsedBounds {
                _bottomBarAccessory?.frame = collapsedBounds
            }
            if bottomBarAccessoryExpandedContentHost?.frame != expandedBounds {
                bottomBarAccessoryExpandedContentHost?.frame = expandedBounds
            }
            if expandedAccessoryViewController?.view.frame != expandedBounds {
                expandedAccessoryViewController?.view.frame = expandedBounds
            }
            if bottomBarAccessorySharedElementHost?.frame != expandedBounds {
                bottomBarAccessorySharedElementHost?.frame = expandedBounds
            }
            CATransaction.commit()
        }

        let tabReveal: CGFloat
        switch context.state {
        case .collapsed:
            tabReveal = 1
        case .expanded:
            tabReveal = 1
        case .dragging:
            tabReveal = 1
        case .settlingToCollapsed:
            tabReveal = 1
        case .expanding, .settlingToExpanded:
            tabReveal = 1
        }

        let chromeVisible = max(0, 1 - effectiveTabBarHiddenProgress)
        let tabBarAlpha = chromeVisible * tabReveal
        if abs(tabBarView.alpha - tabBarAlpha) > 0.000_1 {
            tabBarView.alpha = tabBarAlpha
        }
        let tabBarIsInteractive = context.state == .collapsed
            && tabBarAlpha > 0.99
        if tabBarView.isUserInteractionEnabled != tabBarIsInteractive {
            tabBarView.isUserInteractionEnabled = tabBarIsInteractive
        }
        // Accessibility ownership follows the deterministic state machine,
        // never the visual crossfade. Every transient state hides both
        // endpoint trees as well as the content underneath the morph.
        applyBottomBarAccessoryAccessibilityOwnership(for: context.state)

        let shouldUseExpandedChrome = context.presentationProgress >= 0.32
        if shouldUseExpandedChrome != accessoryUsesExpandedSystemChrome {
            accessoryUsesExpandedSystemChrome = shouldUseExpandedChrome
            setNeedsStatusBarAppearanceUpdate()
        }
        // Asking UIKit to reevaluate the home indicator on every display-link
        // sample schedules a root layout pass. That layout retargets the
        // accessory coordinator from its presentation geometry, effectively
        // restarting the spring every frame. The delegated controller changes
        // only when this threshold is crossed, so invalidate chrome once.
        let previouslyUsedExpandedHomeIndicator = previousPresentationProgress >= 0.85
        let usesExpandedHomeIndicator = context.presentationProgress >= 0.85
        if previouslyUsedExpandedHomeIndicator != usesExpandedHomeIndicator {
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        if let sharedElementHost = bottomBarAccessorySharedElementHost,
           sharedElementHost.superview === view {
            let subviews = view.subviews
            let hierarchyIsCorrect = subviews.last === sharedElementHost
                && subviews.dropLast().last === wrapper
            if !hierarchyIsCorrect {
                view.bringSubviewToFront(wrapper)
                view.bringSubviewToFront(sharedElementHost)
            }
        } else if view.subviews.last !== wrapper {
            view.bringSubviewToFront(wrapper)
        }
    }

    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didComplete target: BottomBarAccessoryReleaseTarget
    ) {
        guard coordinator === bottomBarAccessoryTransitionCoordinator,
              let wrapper = bottomBarAccessoryWrapper,
              let geometry = accessoryTransitionGeometry else {
            return
        }

        switch target {
        case .expanded:
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
            wrapper.transitionMaterialInteractionEnabled = false
            setBottomBarAccessoryPressEnabled(false)
            wrapper.endInteractiveGeometryUpdates(
                size: geometry.expandedFrame.size,
                cornerRadius: geometry.expandedCornerRadius
            )
            wrapper.transitionMaterialAlpha = 0
            accessoryPresentationProgress = 1
            accessoryUsesExpandedSystemChrome = true
            tabBarView.alpha = max(0, 1 - effectiveTabBarHiddenProgress)
            tabBarView.isUserInteractionEnabled = false
            applyBottomBarAccessoryAccessibilityOwnership(for: .expanded)
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(
                    notification: .screenChanged,
                    argument: expandedAccessoryViewController?.view
                )
            }

        case .collapsed:
            let presentationSession = accessoryPresentationSession
            wrapper.endInteractiveGeometryUpdates(
                size: geometry.collapsedFrame.size,
                cornerRadius: geometry.collapsedCornerRadius
            )
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial = false
            wrapper.transitionMaterialInteractionEnabled = false
            setBottomBarAccessoryPressEnabled(true)
            wrapper.transitionMaterialAlpha = 1
            if let controller = expandedAccessoryViewController {
                teardownExpandedAccessoryController(controller)
            }
            if let gesture = accessoryDismissGesture {
                wrapper.removeGestureRecognizer(gesture)
            }
            accessoryDismissGesture = nil
            coordinator.delegate = nil
            bottomBarAccessoryTransitionCoordinator = nil
            expandedAccessoryViewController = nil
            accessoryTransitionGeometry = nil
            accessoryPresentationSession = nil
            accessoryPresentationProgress = 0
            accessoryUsesExpandedSystemChrome = false
            accessoryForcedCollapse = false
            bottomBarAccessoryCollapsedContentHost?.alpha = 1
            bottomBarAccessoryCollapsedContentHost?.isUserInteractionEnabled = true
            bottomBarAccessoryExpandedContentHost?.alpha = 0
            bottomBarAccessoryExpandedContentHost?.isUserInteractionEnabled = false
            bottomBarAccessorySharedElementHost?.removeFromSuperview()
            if let presentationSession {
                restoreAccessoryPresentationSession(presentationSession)
            }
            applyBottomBarAccessoryAccessibilityOwnership(for: .collapsed)
            let chromeVisible = max(0, 1 - effectiveTabBarHiddenProgress)
            tabBarView.alpha = chromeVisible
            tabBarView.isUserInteractionEnabled = chromeVisible > 0.99
            if let layout = currentlyAppliedLayout {
                containerLayoutUpdated(layout, transition: .immediate)
            }
            attachScrollObserverIfPossible()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(
                    notification: .screenChanged,
                    argument: collapsedAccessoryAccessibilityFocusTarget
                )
            }

            let completions = accessoryDismissCompletions
            accessoryDismissCompletions.removeAll()
            completions.forEach { $0() }
        }
    }

    /// Applies one atomic accessibility boundary for the whole player
    /// construction. During a transition there is deliberately no accessible
    /// player endpoint; after completion exactly one endpoint owns focus.
    private func applyBottomBarAccessoryAccessibilityOwnership(
        for state: BottomBarAccessoryPresentationState
    ) {
        let ownership = Self.bottomBarAccessoryAccessibilityOwnership(for: state)
        let collapsedHidden = ownership != .collapsed
        if bottomBarAccessoryCollapsedContentHost?.accessibilityElementsHidden
            != collapsedHidden {
            bottomBarAccessoryCollapsedContentHost?.accessibilityElementsHidden =
                collapsedHidden
        }
        let expandedHidden = ownership != .expanded
        if bottomBarAccessoryExpandedContentHost?.accessibilityElementsHidden
            != expandedHidden {
            bottomBarAccessoryExpandedContentHost?.accessibilityElementsHidden =
                expandedHidden
        }

        let hidesUnderlyingContent = ownership != .collapsed
        if tabBarView.accessibilityElementsHidden != hidesUnderlyingContent {
            tabBarView.accessibilityElementsHidden = hidesUnderlyingContent
        }
        if currentController?.view.accessibilityElementsHidden
            != hidesUnderlyingContent {
            currentController?.view.accessibilityElementsHidden = hidesUnderlyingContent
        }
        if presentedSearchController?.view.accessibilityElementsHidden
            != hidesUnderlyingContent {
            presentedSearchController?.view.accessibilityElementsHidden =
                hidesUnderlyingContent
        }
    }

    /// Keep optical glass local to the compact end of the morph. Full Player
    /// supplies its own artwork backdrop; allowing the regular material to
    /// remain opaque once the surface is card/fullscreen-sized creates a
    /// white veil, especially while expanded content crossfades on collapse.
    static func bottomBarAccessoryMaterialAlpha(
        presentationProgress: CGFloat
    ) -> CGFloat {
        BottomBarAccessoryTransitionCoordinator.transitionMaterialAlpha(
            presentationProgress: presentationProgress
        )
    }
}

@MainActor
final class BottomBarAccessoryDismissScrollHandoff {
    enum Decision: Equatable {
        case wait
        case begin(translationOriginY: CGFloat)
    }

    private(set) weak var pendingScrollView: UIScrollView?
    private(set) weak var committedScrollView: UIScrollView?
    private(set) var didWaitForScroll = false

    func reset() {
        pendingScrollView = nil
        committedScrollView = nil
        didWaitForScroll = false
    }

    func captureCandidate(at location: CGPoint, in container: UIView) {
        pendingScrollView = Self.relevantVerticalScrollView(
            at: location,
            in: container
        )
    }

    func decision(translationY: CGFloat, velocityY: CGFloat) -> Decision {
        if let pendingScrollView, !Self.isAtTop(pendingScrollView) {
            didWaitForScroll = true
            return .wait
        }
        guard translationY > 0 || velocityY > 0 else { return .wait }
        return .begin(
            translationOriginY: didWaitForScroll ? translationY : 0
        )
    }

    func commitHandoff() {
        committedScrollView = pendingScrollView
        pendingScrollView = nil
    }

    func pinCommittedScrollToTop() {
        guard let scrollView = committedScrollView else { return }
        let top = -scrollView.adjustedContentInset.top
        guard abs(scrollView.contentOffset.y - top) > 0.25 else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: top),
            animated: false
        )
    }

    /// Returns the deepest vertical scroller that can still consume upward
    /// movement. An at-top vertical candidate is retained only as a fallback,
    /// allowing a scrolled vertical ancestor to win over an inner pager.
    static func relevantVerticalScrollView(
        at location: CGPoint,
        in container: UIView
    ) -> UIScrollView? {
        guard let hit = container.hitTest(location, with: nil) else { return nil }
        var current: UIView? = hit
        var atTopFallback: UIScrollView?

        while let view = current {
            if let scrollView = view as? UIScrollView,
               scrollView.isScrollEnabled,
               isVerticallyRelevant(scrollView) {
                if !isAtTop(scrollView) {
                    return scrollView
                }
                if atTopFallback == nil {
                    atTopFallback = scrollView
                }
            }
            if view === container { break }
            current = view.superview
        }
        return atTopFallback
    }

    private static func isVerticallyRelevant(_ scrollView: UIScrollView) -> Bool {
        let top = -scrollView.adjustedContentInset.top
        let bottom = scrollView.contentSize.height
            - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
        let hasVerticalRange = bottom > top + 0.5
        return hasVerticalRange
            || scrollView.alwaysBounceVertical
            || !isAtTop(scrollView)
    }

    private static func isAtTop(_ scrollView: UIScrollView) -> Bool {
        let top = -scrollView.adjustedContentInset.top
        return scrollView.contentOffset.y <= top + 0.5
    }
}

extension AetherTabBarController: UIGestureRecognizerDelegate {
    open func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // `require(toFail:)` is permanent for the lifetime of the tap
        // recognizer. The dismiss recognizer is recreated for every Full
        // presentation, so installing a static requirement each time leaves
        // the stable Mini waiting on a growing set of retired recognizers.
        // Resolve only the currently active pair dynamically instead.
        gestureRecognizer === bottomBarAccessoryTap
            && otherGestureRecognizer === accessoryDismissGesture
    }

    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === accessoryDismissGesture {
            return expandedAccessoryViewController != nil
        }
        return true
    }

    open func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === bottomBarAccessoryTap
                || gestureRecognizer === accessoryDismissGesture
        else {
            return true
        }

        return shouldReceiveBottomBarAccessorySurfaceTouch(in: touch.view)
    }

    /// Keeps the accessory's free surface tappable without turning the
    /// wrapper into a competing tap owner for interactive descendants.
    /// `internal` also gives focused tests a deterministic path that does not
    /// need to fabricate UIKit-owned `UITouch` instances.
    internal func shouldReceiveBottomBarAccessorySurfaceTouch(
        in touchedView: UIView?
    ) -> Bool {
        var candidate = touchedView
        while let view = candidate, view !== bottomBarAccessoryWrapper {
            if view is UIControl || view is UIScrollView {
                return false
            }
            if view.gestureRecognizers?.contains(where: { $0.isEnabled }) == true {
                return false
            }
            candidate = view.superview
        }
        return true
    }

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let pairContainsDismiss = gestureRecognizer === accessoryDismissGesture
            || otherGestureRecognizer === accessoryDismissGesture
        guard pairContainsDismiss else { return false }
        let other = gestureRecognizer === accessoryDismissGesture
            ? otherGestureRecognizer
            : gestureRecognizer
        guard let scrollView = other.view as? UIScrollView else { return false }
        return other === scrollView.panGestureRecognizer
    }
}

struct LegacyTabBarScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let boundsHeight: CGFloat
    let adjustedTopInset: CGFloat
    let adjustedBottomInset: CGFloat
    let tabBarContentHeight: CGFloat

    init(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        boundsHeight: CGFloat,
        adjustedTopInset: CGFloat,
        adjustedBottomInset: CGFloat,
        tabBarContentHeight: CGFloat = TabBarView.LegacyLayout.contentHeight
    ) {
        self.contentOffsetY = contentOffsetY
        self.contentHeight = contentHeight
        self.boundsHeight = boundsHeight
        self.adjustedTopInset = adjustedTopInset
        self.adjustedBottomInset = adjustedBottomInset
        self.tabBarContentHeight = tabBarContentHeight
    }

    init(scrollView: UIScrollView) {
        self.init(
            contentOffsetY: scrollView.contentOffset.y,
            contentHeight: scrollView.contentSize.height,
            boundsHeight: scrollView.bounds.height,
            adjustedTopInset: scrollView.adjustedContentInset.top,
            adjustedBottomInset: scrollView.adjustedContentInset.bottom
        )
    }

    var viewportHeightWithoutTabBar: CGFloat {
        let bottomInsetWithoutTabBar = max(0.0, adjustedBottomInset - tabBarContentHeight)
        return max(0.0, boundsHeight - adjustedTopInset - bottomInsetWithoutTabBar)
    }

    var maximumContentOffsetY: CGFloat {
        max(-adjustedTopInset, contentHeight - boundsHeight + adjustedBottomInset)
    }

    var minimumContentOffsetY: CGFloat {
        -adjustedTopInset
    }
}

enum LegacyTabBarScrollEdgeResolver {
    static let shortContentTopOverscrollRevealThreshold: CGFloat = 48.0
    static let shortContentTopOverscrollResetThreshold: CGFloat = 24.0

    static func isChromeVisible(
        metrics: LegacyTabBarScrollMetrics,
        previouslyVisible: Bool
    ) -> Bool {
        let isLongContent = metrics.contentHeight
            >= metrics.viewportHeightWithoutTabBar
        if isLongContent {
            // Hide only at the actual terminal content offset. A value even
            // slightly above that endpoint restores classic chrome.
            return metrics.contentOffsetY < metrics.maximumContentOffsetY
        }

        let overscroll = metrics.minimumContentOffsetY - metrics.contentOffsetY
        let threshold = previouslyVisible
            ? shortContentTopOverscrollResetThreshold
            : shortContentTopOverscrollRevealThreshold
        return overscroll >= threshold
    }
}

/// Reduces raw UIScrollView KVO into stable minimize intent.
///
/// Offsets are normalized against `adjustedContentInset.top` and clamped to
/// the real scrollable range, so top/bottom rubber-banding cannot masquerade
/// as a direction reversal. Programmatic offsets and geometry/inset changes
/// are ownership boundaries: they cancel a pending preview and establish a
/// fresh baseline instead of toggling chrome. Event callbacks are guarded
/// against synchronous safe-area/layout re-entry; any nested KVO is coalesced
/// into one post-callback rebase.
private final class TabBarScrollMinimizeObserver: NSObject {
    enum Event {
        case armingProgress(CGFloat, isActive: Bool)
        case commitMinimize
        case requestExpand
    }

    private struct Geometry {
        let contentSize: CGSize
        let boundsSize: CGSize
        let adjustedInsets: UIEdgeInsets

        func isNearlyEqual(to other: Geometry) -> Bool {
            abs(contentSize.width - other.contentSize.width) < 0.5
                && abs(contentSize.height - other.contentSize.height) < 0.5
                && abs(boundsSize.width - other.boundsSize.width) < 0.5
                && abs(boundsSize.height - other.boundsSize.height) < 0.5
                && abs(adjustedInsets.top - other.adjustedInsets.top) < 0.25
                && abs(adjustedInsets.left - other.adjustedInsets.left) < 0.25
                && abs(adjustedInsets.bottom - other.adjustedInsets.bottom) < 0.25
                && abs(adjustedInsets.right - other.adjustedInsets.right) < 0.25
        }
    }

    private struct Sample {
        let geometry: Geometry
        let normalizedOffsetY: CGFloat
        let maximumNormalizedOffsetY: CGFloat
    }

    private struct ArmingState {
        let token: Int
        let originOffsetY: CGFloat
        var progress: CGFloat
    }

    private enum State {
        case expanded
        case arming(ArmingState)
        case minimized
    }

    private weak var scrollView: UIScrollView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var contentInsetObservation: NSKeyValueObservation?
    private let onEvent: (Event) -> Bool
    private let onScrollMetricsChange: (LegacyTabBarScrollMetrics) -> Void

    private var state: State
    private var decisionAnchorOffsetY: CGFloat
    private var lastGeometry: Geometry
    private var nextArmingToken: Int = 0
    private var isDispatchingCallback = false
    private var needsRebaseAfterCallback = false
    private var needsArmingCancellationAfterCallback = false
    private var pendingSynchronizedMinimized: Bool?
    private var pendingGeometryRebaseGeneration: Int?
    private var nextGeometryRebaseGeneration: Int = 0
    private var geometryRebaseOffsetY: CGFloat = 0.0
    private var geometryRebasePanTranslationY: CGFloat = 0.0
    private var isInvalidated = false
    /// Reattachment commonly causes safe-area/bounds churn (and can clamp
    /// rubber-band offsets) before the user touches the screen again. Those
    /// lifecycle samples must not overwrite the controller-owned Liquid
    /// endpoint or a cached Legacy/navigation edge state.
    private var suppressesRestoredMetricsUntilOffsetMutation: Bool
    private var acceptsProgrammaticRestoredOffsetMutation: Bool

    /// Apple-style preparation starts after a small dead zone and reaches its
    /// full 4pt inset after roughly 56pt of sustained downward travel.
    private static let armingActivationDistance: CGFloat = 8.0
    private static let armingProgressDistance: CGFloat = 48.0
    private static let expansionDirectionThreshold: CGFloat = 12.0
    private static let minimumScrollableRange: CGFloat = 0.5

    init(
        scrollView: UIScrollView,
        initiallyMinimized: Bool,
        emitsInitialScrollMetrics: Bool = true,
        onEvent: @escaping (Event) -> Bool,
        onScrollMetricsChange: @escaping (LegacyTabBarScrollMetrics) -> Void
    ) {
        let initialSample = Self.sample(scrollView: scrollView)
        self.scrollView = scrollView
        self.onEvent = onEvent
        self.onScrollMetricsChange = onScrollMetricsChange
        self.state = initiallyMinimized ? .minimized : .expanded
        self.decisionAnchorOffsetY = initialSample.normalizedOffsetY
        self.lastGeometry = initialSample.geometry
        self.suppressesRestoredMetricsUntilOffsetMutation = !emitsInitialScrollMetrics
        self.acceptsProgrammaticRestoredOffsetMutation = emitsInitialScrollMetrics
        super.init()

        // KVO avoids stealing the host's UIScrollViewDelegate. Geometry
        // observations cover keyboard/safe-area adjustment and split-view
        // resizing even when no contentOffset callback accompanies them.
        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            self?.processContentOffset(scrollView: scrollView)
        }
        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
            self?.processGeometryMutation(
                scrollView: scrollView,
                expectsCompensatingOffset: false
            )
        }
        boundsObservation = scrollView.observe(\.bounds, options: [.new]) { [weak self] scrollView, _ in
            self?.processGeometryMutation(
                scrollView: scrollView,
                expectsCompensatingOffset: false
            )
        }
        contentInsetObservation = scrollView.observe(\.contentInset, options: [.new]) { [weak self] scrollView, _ in
            self?.processGeometryMutation(
                scrollView: scrollView,
                expectsCompensatingOffset: true
            )
        }
        scrollView.panGestureRecognizer.addTarget(
            self,
            action: #selector(handleObservedPanStateChanged(_:))
        )
        if emitsInitialScrollMetrics {
            emitScrollMetrics(scrollView: scrollView)
        } else {
            // Detach/reattach can synchronously clamp a rubber-band offset
            // without any user intent. Give that UIKit lifecycle churn one
            // short settling window; real finger-driven movement is accepted
            // immediately, and later programmatic scrolling remains valid.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                [weak self] in
                self?.acceptsProgrammaticRestoredOffsetMutation = true
            }
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        scrollView?.panGestureRecognizer.removeTarget(
            self,
            action: #selector(handleObservedPanStateChanged(_:))
        )
        contentOffsetObservation?.invalidate()
        contentOffsetObservation = nil
        contentSizeObservation?.invalidate()
        contentSizeObservation = nil
        boundsObservation?.invalidate()
        boundsObservation = nil
        contentInsetObservation?.invalidate()
        contentInsetObservation = nil
        pendingSynchronizedMinimized = nil
        needsArmingCancellationAfterCallback = false
        pendingGeometryRebaseGeneration = nil
    }

    func refreshScrollMetrics() {
        guard !isInvalidated, let scrollView else { return }
        if isDispatchingCallback {
            if case .arming = state {
                needsArmingCancellationAfterCallback = true
            }
            needsRebaseAfterCallback = true
            return
        }
        let sample = Self.sample(scrollView: scrollView)
        if suppressesRestoredMetricsUntilOffsetMutation {
            rebase(to: sample, cancelArming: true)
            return
        }
        guard !lastGeometry.isNearlyEqual(to: sample.geometry) else {
            return
        }
        emitScrollMetrics(scrollView: scrollView)
        guard !isInvalidated else { return }
        rebase(to: sample, cancelArming: true)
    }

    /// Marks a safe-area/layout mutation initiated by the tab controller.
    /// UIKit may deliver its compensating contentOffset one or more callbacks
    /// after the geometry change while `isDragging` is still true; that sample
    /// belongs to layout, not to scroll intent.
    func beginOwnedGeometryMutation() {
        guard !isInvalidated else { return }
        armPostGeometryOffsetRebase(anchorOffsetY: decisionAnchorOffsetY)
    }

    /// Synchronizes programmatic/search-owned endpoint changes without
    /// producing another callback into the controller.
    func synchronize(minimized: Bool) {
        guard !isInvalidated else { return }
        if isDispatchingCallback {
            pendingSynchronizedMinimized = minimized
            needsRebaseAfterCallback = true
            return
        }
        applySynchronizedEndpoint(minimized: minimized)
        rebaseToCurrentOffset()
    }

    func advanceArmingForTesting(by _: TimeInterval) {}

    func endPanForTesting() {
        cancelPartialArmingForFingerRelease()
    }

    deinit {
        scrollView?.panGestureRecognizer.removeTarget(
            self,
            action: #selector(handleObservedPanStateChanged(_:))
        )
        contentOffsetObservation?.invalidate()
        contentSizeObservation?.invalidate()
        boundsObservation?.invalidate()
        contentInsetObservation?.invalidate()
    }

    private static func finite(_ value: CGFloat, fallback: CGFloat = 0.0) -> CGFloat {
        value.isFinite ? value : fallback
    }

    private static func sample(scrollView: UIScrollView) -> Sample {
        let contentSize = CGSize(
            width: finite(scrollView.contentSize.width),
            height: max(0.0, finite(scrollView.contentSize.height))
        )
        let boundsSize = CGSize(
            width: max(0.0, finite(scrollView.bounds.width)),
            height: max(0.0, finite(scrollView.bounds.height))
        )
        let adjustedInsets = UIEdgeInsets(
            top: finite(scrollView.adjustedContentInset.top),
            left: finite(scrollView.adjustedContentInset.left),
            bottom: finite(scrollView.adjustedContentInset.bottom),
            right: finite(scrollView.adjustedContentInset.right)
        )
        let maximumOffset = max(
            0.0,
            contentSize.height
                + adjustedInsets.top
                + adjustedInsets.bottom
                - boundsSize.height
        )
        let normalizedOffset = min(
            maximumOffset,
            max(
                0.0,
                finite(scrollView.contentOffset.y) + adjustedInsets.top
            )
        )
        return Sample(
            geometry: Geometry(
                contentSize: contentSize,
                boundsSize: boundsSize,
                adjustedInsets: adjustedInsets
            ),
            normalizedOffsetY: normalizedOffset,
            maximumNormalizedOffsetY: maximumOffset
        )
    }

    private func processContentOffset(scrollView: UIScrollView) {
        guard !isInvalidated, self.scrollView === scrollView else { return }
        if isDispatchingCallback {
            if case .arming = state {
                needsArmingCancellationAfterCallback = true
            }
            needsRebaseAfterCallback = true
            return
        }

        let sample = Self.sample(scrollView: scrollView)
        if suppressesRestoredMetricsUntilOffsetMutation {
            let userDriven = scrollView.isTracking
                || scrollView.isDragging
                || scrollView.isDecelerating
            if !userDriven, !acceptsProgrammaticRestoredOffsetMutation {
                rebase(to: sample, cancelArming: true)
                return
            }
            if pendingGeometryRebaseGeneration != nil
                || !lastGeometry.isNearlyEqual(to: sample.geometry) {
                if userDriven {
                    pendingGeometryRebaseGeneration = nil
                    suppressesRestoredMetricsUntilOffsetMutation = false
                } else {
                    rebase(to: sample, cancelArming: true)
                    return
                }
            } else {
                // A same-geometry offset mutation is either an actual gesture
                // or an explicit programmatic scroll and therefore becomes
                // the first new authoritative state for this screen.
                suppressesRestoredMetricsUntilOffsetMutation = false
            }
        }

        emitScrollMetrics(scrollView: scrollView)
        guard !isInvalidated else { return }

        if pendingGeometryRebaseGeneration != nil {
            let panTranslationY = scrollView.panGestureRecognizer
                .translation(in: scrollView).y
            let panDelta = panTranslationY - geometryRebasePanTranslationY
            let offsetDelta = sample.normalizedOffsetY - geometryRebaseOffsetY
            let isExplicitFingerDirection = (offsetDelta < -0.5 && panDelta > 0.5)
                || (offsetDelta > 0.5 && panDelta < -0.5)
            if isExplicitFingerDirection {
                pendingGeometryRebaseGeneration = nil
            } else {
                // Safe-area propagation can produce several callbacks: first
                // the new inset, then the compensating offset. Keep ownership
                // until the normalized visual position returns to the anchor.
                if abs(sample.normalizedOffsetY - geometryRebaseOffsetY) < 0.75 {
                    pendingGeometryRebaseGeneration = nil
                }
                rebase(to: sample, cancelArming: true)
                return
            }
        }

        // Insets/bounds/content size can synchronously adjust contentOffset.
        // Geometry wins over a simultaneous gesture flag and establishes a
        // new baseline instead of being interpreted as user direction.
        guard lastGeometry.isNearlyEqual(to: sample.geometry) else {
            armPostGeometryOffsetRebase(anchorOffsetY: decisionAnchorOffsetY)
            rebase(to: sample, cancelArming: true)
            return
        }

        let userDriven = scrollView.isTracking
            || scrollView.isDragging
            || scrollView.isDecelerating
        guard userDriven else {
            rebase(to: sample, cancelArming: true)
            return
        }
        processUserDriven(
            sample: sample,
            allowsNewArming: scrollView.isTracking || scrollView.isDragging
        )
    }

    @objc private func handleObservedPanStateChanged(
        _ recognizer: UIPanGestureRecognizer
    ) {
        guard !isInvalidated,
              recognizer === scrollView?.panGestureRecognizer else {
            return
        }
        switch recognizer.state {
        case .ended, .cancelled, .failed:
            cancelPartialArmingForFingerRelease()
        default:
            break
        }
    }

    private func cancelPartialArmingForFingerRelease() {
        guard case .arming = state else { return }
        cancelArming(
            at: currentSample()?.normalizedOffsetY ?? decisionAnchorOffsetY
        )
    }

    private func processGeometryMutation(
        scrollView: UIScrollView,
        expectsCompensatingOffset: Bool
    ) {
        guard !isInvalidated, self.scrollView === scrollView else { return }
        if isDispatchingCallback {
            if case .arming = state {
                needsArmingCancellationAfterCallback = true
            }
            if expectsCompensatingOffset {
                armPostGeometryOffsetRebase(anchorOffsetY: decisionAnchorOffsetY)
            }
            needsRebaseAfterCallback = true
            return
        }
        let sample = Self.sample(scrollView: scrollView)
        // UIScrollView implements scrolling by changing bounds.origin, so the
        // bounds KVO also fires for ordinary offset changes. Only size/inset/
        // content changes are geometry ownership boundaries.
        guard !lastGeometry.isNearlyEqual(to: sample.geometry) else { return }
        armPostGeometryOffsetRebase(anchorOffsetY: decisionAnchorOffsetY)
        if suppressesRestoredMetricsUntilOffsetMutation {
            rebase(to: sample, cancelArming: true)
            return
        }
        emitScrollMetrics(scrollView: scrollView)
        guard !isInvalidated else { return }
        rebase(to: Self.sample(scrollView: scrollView), cancelArming: true)
    }

    private func armPostGeometryOffsetRebase(anchorOffsetY: CGFloat? = nil) {
        let isNewWindow = pendingGeometryRebaseGeneration == nil
        nextGeometryRebaseGeneration &+= 1
        let generation = nextGeometryRebaseGeneration
        pendingGeometryRebaseGeneration = generation
        if isNewWindow, let scrollView {
            let sample = Self.sample(scrollView: scrollView)
            geometryRebaseOffsetY = anchorOffsetY
                ?? sample.normalizedOffsetY
            geometryRebasePanTranslationY = scrollView.panGestureRecognizer
                .translation(in: scrollView).y
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.pendingGeometryRebaseGeneration == generation else {
                return
            }
            self.pendingGeometryRebaseGeneration = nil
        }
    }

    private func processUserDriven(
        sample: Sample,
        allowsNewArming: Bool
    ) {
        guard sample.maximumNormalizedOffsetY > Self.minimumScrollableRange else {
            // A short source has no direction from which to derive a new
            // chrome intent. Keep the controller-wide endpoint inherited on
            // attach: expanding here would make a short pushed screen reset
            // minimized chrome, then replay the minimize (and its safe-area
            // change) when the previous long list becomes active again.
            rebase(to: sample, cancelArming: true)
            return
        }

        let y = sample.normalizedOffsetY
        switch state {
        case .expanded:
            guard allowsNewArming else {
                // Momentum after a partial preview was cancelled must not
                // re-arm the chrome after the finger has already lifted.
                decisionAnchorOffsetY = y
                return
            }
            if y <= Self.minimumScrollableRange {
                decisionAnchorOffsetY = y
                return
            }
            let delta = y - decisionAnchorOffsetY
            if delta >= Self.armingActivationDistance {
                beginArming(
                    originOffsetY: decisionAnchorOffsetY,
                    currentOffsetY: y
                )
            } else if delta < 0.0 {
                // Follow the low-water mark while moving upward. The next
                // minimize intent must be a fresh sustained downward move.
                decisionAnchorOffsetY = y
            }

        case var .arming(arming):
            guard allowsNewArming else {
                cancelArming(at: y)
                return
            }
            let progress = Self.armingProgress(
                offsetY: y,
                originOffsetY: arming.originOffsetY
            )
            // Rewind the preview with the finger instead of snapping the
            // entire chrome back after a small retreat from its peak. Once
            // the gesture returns to the 8pt dead zone there is no remaining
            // visual preview to own, so retire the arming state locally.
            if y <= arming.originOffsetY + Self.armingActivationDistance {
                cancelArming(at: y)
                return
            }
            let progressChanged = abs(progress - arming.progress) > 0.0001
            arming.progress = progress
            state = .arming(arming)
            if progressChanged {
                let accepted = dispatchEvent(
                    .armingProgress(progress, isActive: true)
                )
                if !accepted {
                    state = .expanded
                    finishDeferredWork()
                    decisionAnchorOffsetY = currentSample()?.normalizedOffsetY ?? y
                    return
                }
                finishDeferredWork()
            }
            if progress >= 1.0 {
                commitMinimize(token: arming.token)
            }

        case .minimized:
            let delta = y - decisionAnchorOffsetY
            if delta <= -Self.expansionDirectionThreshold {
                requestExpand(at: y)
            } else if delta > 0.0 {
                // Follow the high-water mark so bottom rubber-band return is
                // zero after clamping and cannot look like an upward intent.
                decisionAnchorOffsetY = y
            }
        }
    }

    private static func armingProgress(
        offsetY: CGFloat,
        originOffsetY: CGFloat
    ) -> CGFloat {
        let progress = (
            offsetY - originOffsetY - armingActivationDistance
        ) / armingProgressDistance
        return max(0.0, min(1.0, progress))
    }

    private func beginArming(
        originOffsetY: CGFloat,
        currentOffsetY: CGFloat
    ) {
        nextArmingToken &+= 1
        let progress = Self.armingProgress(
            offsetY: currentOffsetY,
            originOffsetY: originOffsetY
        )
        let arming = ArmingState(
            token: nextArmingToken,
            originOffsetY: originOffsetY,
            progress: progress
        )
        state = .arming(arming)
        let accepted = dispatchEvent(
            .armingProgress(progress, isActive: true)
        )
        if !accepted {
            state = .expanded
        }
        finishDeferredWork()

        guard !isInvalidated,
              case let .arming(currentArming) = state,
              currentArming.token == arming.token else {
            return
        }
        if currentArming.progress >= 1.0 {
            commitMinimize(token: currentArming.token)
        }
    }

    private func cancelArming(at offsetY: CGFloat) {
        guard case .arming = state else {
            decisionAnchorOffsetY = offsetY
            return
        }
        state = .expanded
        _ = dispatchEvent(.armingProgress(0.0, isActive: false))
        finishDeferredWork()
        decisionAnchorOffsetY = currentSample()?.normalizedOffsetY ?? offsetY
    }

    private func requestExpand(at offsetY: CGFloat) {
        guard case .minimized = state else { return }
        state = .expanded
        let accepted = dispatchEvent(.requestExpand)
        if !accepted {
            state = .minimized
        }
        finishDeferredWork()
        decisionAnchorOffsetY = currentSample()?.normalizedOffsetY ?? offsetY
    }

    private func commitMinimize(token: Int) {
        guard !isInvalidated else { return }
        guard case let .arming(arming) = state,
              arming.token == token else {
            return
        }
        guard let sample = currentSample() else {
            cancelArming(at: decisionAnchorOffsetY)
            return
        }
        guard lastGeometry.isNearlyEqual(to: sample.geometry),
              sample.maximumNormalizedOffsetY > Self.minimumScrollableRange,
              arming.progress >= 0.999 else { return }
        guard Self.armingProgress(
            offsetY: sample.normalizedOffsetY,
            originOffsetY: arming.originOffsetY
        ) >= 0.999 else {
            rebase(to: sample, cancelArming: true)
            return
        }

        state = .minimized
        let accepted = dispatchEvent(.commitMinimize)
        if !accepted {
            state = .expanded
        }
        finishDeferredWork()
        rebaseToCurrentOffset()
    }

    private func rebase(to sample: Sample, cancelArming shouldCancelArming: Bool) {
        lastGeometry = sample.geometry
        if shouldCancelArming, case .arming = state {
            cancelArming(at: sample.normalizedOffsetY)
            return
        }
        decisionAnchorOffsetY = sample.normalizedOffsetY
    }

    private func applySynchronizedEndpoint(minimized: Bool) {
        state = minimized ? .minimized : .expanded
    }

    private func rebaseToCurrentOffset() {
        guard let sample = currentSample() else { return }
        lastGeometry = sample.geometry
        decisionAnchorOffsetY = sample.normalizedOffsetY
    }

    private func currentSample() -> Sample? {
        guard let scrollView else { return nil }
        return Self.sample(scrollView: scrollView)
    }

    private func emitScrollMetrics(scrollView: UIScrollView) {
        guard !isInvalidated else { return }
        if isDispatchingCallback {
            needsRebaseAfterCallback = true
            return
        }
        isDispatchingCallback = true
        onScrollMetricsChange(LegacyTabBarScrollMetrics(scrollView: scrollView))
        isDispatchingCallback = false
        finishDeferredWork()
    }

    private func dispatchEvent(_ event: Event) -> Bool {
        guard !isInvalidated, !isDispatchingCallback else { return false }
        isDispatchingCallback = true
        let accepted = onEvent(event)
        isDispatchingCallback = false
        return accepted && !isInvalidated
    }

    private func finishDeferredWork() {
        guard !isDispatchingCallback, !isInvalidated else { return }

        if let minimized = pendingSynchronizedMinimized {
            pendingSynchronizedMinimized = nil
            applySynchronizedEndpoint(minimized: minimized)
            needsRebaseAfterCallback = true
        }
        if needsArmingCancellationAfterCallback {
            needsArmingCancellationAfterCallback = false
            if case .arming = state {
                cancelArming(
                    at: currentSample()?.normalizedOffsetY
                        ?? decisionAnchorOffsetY
                )
                return
            }
        }
        if needsRebaseAfterCallback {
            needsRebaseAfterCallback = false
            rebaseToCurrentOffset()
        }
    }
}
