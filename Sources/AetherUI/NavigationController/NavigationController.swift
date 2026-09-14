import UIKit

// MARK: - Types

public enum NavigationStatusBarStyle {
    case black
    case white
}

public final class NavigationControllerTheme {
    public let statusBar: NavigationStatusBarStyle
    public let navigationBar: NavigationBarTheme
    public let emptyAreaColor: UIColor

    public init(statusBar: NavigationStatusBarStyle, navigationBar: NavigationBarTheme, emptyAreaColor: UIColor) {
        self.statusBar = statusBar
        self.navigationBar = navigationBar
        self.emptyAreaColor = emptyAreaColor
    }

    public static func liquidGlass(
        overallDarkAppearance: Bool = false,
        emptyAreaColor: UIColor = .systemBackground,
        edgeEffectAlpha: CGFloat = 0.75,
        edgeEffectBlurRadiusAtEdge: CGFloat = 2.0,
        edgeEffectBlurRadiusAtFade: CGFloat = 0.0,
        edgeEffectStyle: SystemGlassEffectStyle = .regular
    ) -> NavigationControllerTheme {
        return NavigationControllerTheme(
            statusBar: overallDarkAppearance ? .white : .black,
            navigationBar: .liquidGlass(
                overallDarkAppearance: overallDarkAppearance,
                buttonColor: overallDarkAppearance ? .white : .label,
                primaryTextColor: overallDarkAppearance ? .white : .label,
                edgeEffectAlpha: edgeEffectAlpha,
                edgeEffectBlurRadiusAtEdge: edgeEffectBlurRadiusAtEdge,
                edgeEffectBlurRadiusAtFade: edgeEffectBlurRadiusAtFade,
                edgeEffectStyle: edgeEffectStyle
            ),
            emptyAreaColor: emptyAreaColor
        )
    }
}

public struct NavigationAnimationOptions: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let removeOnMasterDetails = NavigationAnimationOptions(rawValue: 1 << 0)
}

public enum NavigationControllerMode {
    case single
    case automaticMasterDetail
}

private enum RootContainer {
    case flat(NavigationContainer)
    case split(NavigationSplitContainer)
}

/// Texture-root navigation controller with glass-style transitions and glass support.
/// Replaces the NavigationController.
open class AetherNavigationController: AetherViewController, UIGestureRecognizerDelegate {
    // MARK: - Properties

    private let mode: NavigationControllerMode
    private var appearance: AetherAppearance
    private var theme: NavigationControllerTheme
    /// Source-compatibility adapter for the former theme-owning initializer.
    /// It participates as a container-level override: active-screen providers
    /// remain higher priority, while application appearance remains the base.
    private var compatibilityThemeOverride: NavigationControllerTheme?
    private var defaultNavigationBarPresentationData: NavigationBarPresentationData

    private var rootContainer: RootContainer?
    private var overlayContainers: [NavigationOverlayContainer] = []
    private var sharedNavigationBar: NavigationBarImpl?
    private weak var sharedNavigationBarController: AetherViewController?
    private var isUpdatingSharedNavigationBar: Bool = false
    private var interactiveNavigationBarTransition: NavigationBarInteractiveTransition?
    private struct PendingViewControllersUpdate {
        let controllers: [AetherViewController]
        let animated: Bool
    }
    private var pendingViewControllersUpdate: PendingViewControllersUpdate?
    private var isApplyingPendingViewControllersUpdate: Bool = false

    var bottomBarVisibilityTransitionBegan: ((NavigationTransitionDirection, AetherViewController, AetherViewController, Bool) -> Void)?
    var bottomBarVisibilityTransitionProgress: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    var bottomBarVisibilityTransitionResolutionBegan: ((Bool, ContainedViewLayoutTransition) -> Void)?
    var bottomBarVisibilityTransitionEnded: ((Bool) -> Void)?
    var suppressesSelfComputedLayoutDuringBottomBarTransition: Bool = false
    var layoutForController: ((AetherViewController, ContainerViewLayout) -> ContainerViewLayout)? {
        didSet {
            updateRootContainerLayoutProviders()
        }
    }

    private final class NavigationBarInteractiveTransition {
        let direction: NavigationTransitionDirection
        let sourceController: AetherViewController
        let targetController: AetherViewController
        let sourceStack: [AetherViewController]
        let targetStack: [AetherViewController]
        let sourceBar: NavigationBarImpl
        let targetBar: NavigationBarImpl
        let isInteractive: Bool
        var sourceBaseFrame: CGRect = .zero
        var targetBaseFrame: CGRect = .zero
        var progress: CGFloat = 0.0
        var didResolveButtonTransition: Bool = false
        var resolvedCompleted: Bool?
        var scheduledButtonTransition: DispatchWorkItem?

        init(
            direction: NavigationTransitionDirection,
            sourceController: AetherViewController,
            targetController: AetherViewController,
            sourceStack: [AetherViewController],
            targetStack: [AetherViewController],
            sourceBar: NavigationBarImpl,
            targetBar: NavigationBarImpl,
            isInteractive: Bool
        ) {
            self.direction = direction
            self.sourceController = sourceController
            self.targetController = targetController
            self.sourceStack = sourceStack
            self.targetStack = targetStack
            self.sourceBar = sourceBar
            self.targetBar = targetBar
            self.isInteractive = isInteractive
        }
    }

    internal struct NavigationChromeTransitionTiming: Equatable {
        let duration: TimeInterval
        let delay: TimeInterval
    }

    /// The production profile keeps the screen and chrome endpoints aligned.
    /// Both non-interactive directions now start the full chrome clock
    /// immediately; interactive pop still uses the same fixed clock, so gesture
    /// progress and release velocity never enter this calculation.
    internal static func navigationChromeTransitionTiming(
        direction: NavigationTransitionDirection,
        isInteractive: Bool
    ) -> NavigationChromeTransitionTiming {
        let duration = max(0.01, AetherMotion.navigationChrome.geometry.duration)
        let pushDelay = max(0.0, AetherMotion.navigation.duration - duration)
        let delay: TimeInterval
        if isInteractive {
            delay = 0.0
        } else {
            switch direction {
            case .push:
                delay = pushDelay
            case .pop:
                delay = 0.0
            }
        }
        return NavigationChromeTransitionTiming(duration: duration, delay: delay)
    }

    public var minimizedContainer: MinimizedContainerProtocol? {
        didSet {
            if oldValue !== minimizedContainer {
                oldValue?.navigationController = nil
                oldValue?.removeFromSuperview()
            }

            minimizedContainer?.navigationController = self
            minimizedContainer?.willMaximize = { [weak self] _ in
                self?.requestLayout(transition: .animated(duration: 0.4, curve: .spring))
            }
            minimizedContainer?.willDismiss = { [weak self] _ in
                guard let self else { return }
                self.minimizedContainer = nil
                self.requestLayout(transition: .animated(duration: 0.4, curve: .spring))
            }
            minimizedContainer?.didDismiss = { container in
                container.removeFromSuperview()
            }
            minimizedContainer?.statusBarStyleUpdated = { [weak self] in
                self?.setNeedsStatusBarAppearanceUpdate()
            }

            if let layout = validLayout {
                updateMinimizedContainer(layout: layout, transition: .immediate)
            }
        }
    }

    private var _viewControllers: [AetherViewController] = []
    public var viewControllerStack: [AetherViewController] {
        _viewControllers
    }

    public var viewControllers: [UIViewController] {
        get {
            return _viewControllers
        }
        set {
            setViewControllers(newValue.compactMap { $0 as? AetherViewController }, animated: false)
        }
    }

    public var topViewController: UIViewController? {
        return topController
    }

    public var visibleViewController: UIViewController? {
        return topController
    }

    /// Whether the visible navigation stack is currently resolving a push or pop.
    /// User-driven routing should not enqueue another animated push while this is true.
    public var isTransitioning: Bool {
        if interactiveNavigationBarTransition != nil {
            return true
        }

        switch rootContainer {
        case let .flat(container):
            return container.isTransitioning
        case let .split(container):
            return container.masterContainer.isTransitioning || container.detailContainer.isTransitioning
        case nil:
            return false
        }
    }

    public var navigationBar: NavigationBarView {
        return ensureSharedNavigationBar()
    }

    public var topController: AetherViewController? {
        if let topOverlayController = overlayContainers.last?.controller {
            return topOverlayController
        }

        switch rootContainer {
        case let .flat(container):
            return container.topController
        case let .split(container):
            return container.detailContainer.topController ?? container.masterContainer.topController
        case nil:
            return _viewControllers.last
        }
    }

    private var validLayout: ContainerViewLayout?
    private var isApplyingSelfComputedLayout = false
    private var hasParentDrivenLayout = false

    // MARK: - Status Bar

    public var statusBarHost: AnyObject?
    private var currentStatusBarStyle: NavigationStatusBarStyle

    override open var childForStatusBarStyle: UIViewController? {
        topController
    }

    override open var childForStatusBarHidden: UIViewController? {
        topController
    }

    override open var preferredStatusBarStyle: UIStatusBarStyle {
        switch currentStatusBarStyle {
        case .black:
            return .darkContent
        case .white:
            return .lightContent
        }
    }

    override open var prefersStatusBarHidden: Bool {
        topController?.prefersStatusBarHidden ?? false
    }

    // MARK: - Init

    public init(mode: NavigationControllerMode = .single) {
        let appearance = AetherAppearance.runtimeCurrent
        let theme = NavigationControllerTheme(aetherAppearance: appearance)
        self.mode = mode
        self.appearance = appearance
        self.theme = theme
        self.currentStatusBarStyle = theme.statusBar
        self.defaultNavigationBarPresentationData = NavigationBarPresentationData(theme: theme.navigationBar)
        super.init(navigationBarPresentationData: nil)
    }

    public convenience init(rootViewController: AetherViewController, mode: NavigationControllerMode = .single) {
        self.init(mode: mode)
        setViewControllers([rootViewController], animated: false)
    }

    @available(*, deprecated, message: "Use app-level AppearanceStyle and AetherControllerAppearanceProviding overrides.")
    public convenience init(
        mode: NavigationControllerMode = .single,
        theme: NavigationControllerTheme
    ) {
        self.init(mode: mode)
        updateTheme(theme)
    }

    @available(*, deprecated, message: "Use app-level AppearanceStyle and AetherControllerAppearanceProviding overrides.")
    public convenience init(
        rootViewController: AetherViewController,
        mode: NavigationControllerMode = .single,
        theme: NavigationControllerTheme
    ) {
        self.init(mode: mode, theme: theme)
        setViewControllers([rootViewController], animated: false)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.emptyAreaColor
        _ = ensureSharedNavigationBar()
        wireControllers(_viewControllers)
        requestLayout(transition: .immediate)
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !suppressesSelfComputedLayoutDuringBottomBarTransition else {
            return
        }
        updateContainerLayout(transition: .immediate)
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard !suppressesSelfComputedLayoutDuringBottomBarTransition else {
            return
        }
        updateContainerLayout(transition: .immediate)
    }

    // MARK: - Layout

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        if !isApplyingSelfComputedLayout {
            hasParentDrivenLayout = true
        }
        let previousLayout = validLayout
        validLayout = layout
        let navigationChromeTransition: ContainedViewLayoutTransition = previousLayout.map { layout.differsOnlyInKeyboardInputOrBottomAdditionalInset(from: $0) } == true
            ? .immediate
            : transition
        updateVisibleContainers(layout: layout, transition: transition, navigationChromeTransition: navigationChromeTransition)
    }

    private func updateContainerLayout(transition: ContainedViewLayoutTransition) {
        // When hosted inside a AetherModalController the "status bar"
        // region is reused for the grabber strip: a navbar built with
        // statusBarHeight = grabberContainerHeight has its chrome laid
        // out below the grabber, and its own edge-effect frost covers
        // the grabber area naturally (no extra work). Outside a modal,
        // use the real window status bar height.
        let statusBarHeight: CGFloat? = isHostedInModal
            ? AetherModalController.grabberContainerHeight
            : view.window?.windowScene?.statusBarManager?.statusBarFrame.height

        let inheritedLayout = hasParentDrivenLayout ? validLayout : nil
        let layout = ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: inheritedLayout?.safeInsets ?? view.safeAreaInsets,
            additionalInsets: inheritedLayout?.additionalInsets ?? .zero,
            statusBarHeight: statusBarHeight,
            inputHeight: validLayout?.inputHeight,
            inputHeightIsInteractivellyChanging: validLayout?.inputHeightIsInteractivellyChanging ?? false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
        isApplyingSelfComputedLayout = true
        containerLayoutUpdated(layout, transition: transition)
        isApplyingSelfComputedLayout = false
    }

    private var isHostedInModal: Bool {
        var current: UIViewController? = self
        while let vc = current {
            if vc is AetherModalController { return true }
            current = vc.parent
        }
        return false
    }

    override public func requestLayout(transition: ContainedViewLayoutTransition) {
        guard !suppressesSelfComputedLayoutDuringBottomBarTransition else {
            return
        }
        updateContainerLayout(transition: transition)
    }

    /// Flush UIKit's inherited safe-area propagation without letting the
    /// navigation controller start an intermediate self-computed layout pass.
    /// The hosting chrome controller follows this with one explicit container
    /// layout using the canonical target insets.
    func settleInheritedSafeAreaPropagation() {
        guard let hostedView = viewIfLoaded else { return }
        let wasSuppressed = suppressesSelfComputedLayoutDuringBottomBarTransition
        suppressesSelfComputedLayoutDuringBottomBarTransition = true
        defer {
            suppressesSelfComputedLayoutDuringBottomBarTransition = wasSuppressed
        }
        hostedView.setNeedsLayout()
        hostedView.layoutIfNeeded()
    }

    // MARK: - Navigation Stack

    public func setViewControllers(_ viewControllers: [AetherViewController], animated: Bool = true) {
        // Match Telegram-iOS: silently drop duplicates rather than letting the
        // same controller appear twice in the stack (that guarantees broken
        // back-stack state — a single controller can't be its own previous).
        var deduped: [AetherViewController] = []
        deduped.reserveCapacity(viewControllers.count)
        for controller in viewControllers where !deduped.contains(where: { $0 === controller }) {
            deduped.append(controller)
        }

        _viewControllers = deduped
        wireControllers(deduped)

        if interactiveNavigationBarTransition != nil && !isApplyingPendingViewControllersUpdate {
            let shouldKeepAnimatedPendingUpdate: Bool
            if let pending = pendingViewControllersUpdate,
               pending.animated,
               viewControllerArraysAreEqual(pending.controllers, deduped) {
                shouldKeepAnimatedPendingUpdate = true
            } else {
                shouldKeepAnimatedPendingUpdate = false
            }
            pendingViewControllersUpdate = PendingViewControllersUpdate(
                controllers: deduped,
                animated: animated || shouldKeepAnimatedPendingUpdate
            )
            return
        }

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
    }

    public func setViewControllers(_ viewControllers: [UIViewController], animated: Bool, completion: @escaping () -> Void = {}) {
        setViewControllers(viewControllers.compactMap { $0 as? AetherViewController }, animated: animated)
        completion()
    }

    public func setScreenNodes(_ nodes: [AetherScreenNode], animated: Bool = true, completion: @escaping () -> Void = {}) {
        let controllers = nodes.map { AetherScreenController(screenNode: $0) }
        setViewControllers(controllers, animated: animated)
        completion()
    }

    public func pushViewController(_ controller: AetherViewController, animated: Bool = true) {
        guard !animated || !isTransitioning else {
            return
        }
        var controllers = _viewControllers
        controllers.append(controller)
        setViewControllers(controllers, animated: animated)
    }

    public func pushNode(_ node: AetherScreenNode, animated: Bool = true) {
        pushViewController(AetherScreenController(screenNode: node), animated: animated)
    }

    @discardableResult
    public func popViewController(animated: Bool = true) -> AetherViewController? {
        guard _viewControllers.count > 1 else {
            return nil
        }

        var controllers = _viewControllers
        let removedController = controllers.removeLast()
        setViewControllers(controllers, animated: animated)
        return removedController
    }

    public func popToRoot(animated: Bool = true) {
        guard let firstController = _viewControllers.first else {
            return
        }
        setViewControllers([firstController], animated: animated)
    }

    @discardableResult
    public func popToViewController(_ viewController: UIViewController, animated: Bool = true) -> [UIViewController]? {
        guard let target = viewController as? AetherViewController,
              let index = _viewControllers.firstIndex(where: { $0 === target })
        else {
            return nil
        }
        guard index < _viewControllers.count - 1 else {
            return []
        }
        let removed = Array(_viewControllers[(index + 1)..<_viewControllers.count])
        setViewControllers(Array(_viewControllers[...index]), animated: animated)
        return removed
    }

    public func replaceTopController(_ controller: AetherViewController, animated: Bool = true) {
        guard !_viewControllers.isEmpty else {
            pushViewController(controller, animated: animated)
            return
        }

        var controllers = _viewControllers
        controllers[controllers.count - 1] = controller
        setViewControllers(controllers, animated: animated)
    }

    public func replaceTopNode(_ node: AetherScreenNode, animated: Bool = true) {
        replaceTopController(AetherScreenController(screenNode: node), animated: animated)
    }

    public func replaceController(_ controller: AetherViewController, with replacement: AetherViewController, animated: Bool = true) {
        guard let index = _viewControllers.firstIndex(where: { $0 === controller }) else {
            return
        }
        var controllers = _viewControllers
        controllers[index] = replacement
        setViewControllers(controllers, animated: animated)
    }

    // MARK: - Overlay Presentation

    public var overlayControllers: [AetherViewController] {
        return overlayContainers.filter { !$0.isRemoved }.map(\.controller)
    }

    public var topOverlayController: AetherViewController? {
        return overlayContainers.last(where: { !$0.isRemoved })?.controller
    }

    public var globalOverlayControllers: [AetherViewController] {
        guard isViewLoaded, let window = view.window as? AetherWindow else {
            return []
        }
        return window.topLevelOverlayControllers.compactMap { $0 as? AetherViewController }
    }

    public func presentOverlay(controller: AetherViewController, inGlobal: Bool = false, blockInteraction: Bool = false, animated: Bool = true, completion: (() -> Void)? = nil) {
        if inGlobal, isViewLoaded, let window = view.window as? AetherWindow {
            window.presentInGlobalOverlay(controller, animated: animated, completion: completion)
            return
        }
        presentOverlay(controller, blocksInteractionUntilReady: blockInteraction, animated: animated, completion: completion)
    }

    public func presentOverlay(_ controller: AetherViewController, blocksInteractionUntilReady: Bool = false, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !overlayContainers.contains(where: { $0.controller === controller && !$0.isRemoved }) else {
            completion?()
            return
        }

        let container = NavigationOverlayContainer(controller: controller, blocksInteractionUntilReady: blocksInteractionUntilReady)
        container.isReadyUpdated = { [weak self] in
            self?.requestLayout(transition: .immediate)
        }
        overlayContainers.append(container)

        if controller.parent !== self {
            addChild(controller)
            controller.didMove(toParent: self)
        }

        if let layout = currentLayoutForComputation() {
            updateOverlayContainers(layout: overlayLayout(from: layout), transition: transitionForUpdate(animated: animated), appearingContainer: container, completion: completion)
            updateStatusBarAppearance()
        } else {
            completion?()
        }
    }

    public func dismissOverlay(_ controller: AetherViewController? = nil, animated: Bool = true, completion: (() -> Void)? = nil) {
        let targetIndex: Int?
        if let controller {
            targetIndex = overlayContainers.lastIndex(where: { $0.controller === controller && !$0.isRemoved })
        } else {
            targetIndex = overlayContainers.lastIndex(where: { !$0.isRemoved })
        }

        guard let index = targetIndex else {
            completion?()
            return
        }

        let container = overlayContainers.remove(at: index)
        container.isRemoved = true
        container.controller.willMove(toParent: nil)

        let finish = { [weak self, weak container] in
            guard let self, let container else {
                completion?()
                return
            }
            container.removeFromSuperview()
            container.controller.removeFromParent()
            self.cleanupRemovedChildren()
            self.updateStatusBarAppearance()
            completion?()
        }

        if container.superview != nil {
            container.transitionOut(animated: animated, completion: finish)
        } else {
            finish()
        }
    }

    // MARK: - Minimized Controllers

    public func minimizeViewController(
        _ viewController: MinimizableController,
        topEdgeOffset: CGFloat? = nil,
        beforeMaximize: @escaping (AetherNavigationController, @escaping () -> Void) -> Void,
        setupContainer: (MinimizedContainerProtocol?) -> MinimizedContainerProtocol?,
        animated: Bool = true
    ) {
        let container = setupContainer(minimizedContainer)
        if minimizedContainer !== container {
            minimizedContainer = container
        }

        let transition = transitionForUpdate(animated: animated)
        minimizedContainer?.addController(viewController, topEdgeOffset: topEdgeOffset, beforeMaximize: beforeMaximize, transition: transition)
        if let layout = validLayout {
            updateMinimizedContainer(layout: layout, transition: transition)
        }
    }

    public func maximizeViewController(_ viewController: MinimizableController, animated: Bool = true, completion: @escaping (Bool) -> Void) {
        minimizedContainer?.maximizeController(viewController, animated: animated, completion: completion)
    }

    public func dismissMinimizedControllers(completion: @escaping () -> Void = {}) {
        guard let minimizedContainer else {
            completion()
            return
        }

        self.minimizedContainer = nil
        minimizedContainer.dismissAll {
            minimizedContainer.removeFromSuperview()
            completion()
        }
    }

    // MARK: - Theme

    public func invalidateAppearance() {
        updateAppearance(appearance)
    }

    public func updateAppearance(_ appearance: AetherAppearance) {
        self.appearance = appearance
        applyNavigationControllerTheme(resolvedNavigationControllerTheme(for: appearance), transition: .immediate)
    }

    @available(*, deprecated, message: "Use app-level AppearanceStyle and AetherControllerAppearanceProviding overrides.")
    public func updateTheme(_ theme: NavigationControllerTheme) {
        compatibilityThemeOverride = theme
        applyNavigationControllerTheme(
            resolvedNavigationControllerTheme(for: appearance),
            transition: .immediate
        )
    }

    private func applyNavigationControllerTheme(_ theme: NavigationControllerTheme, transition: ContainedViewLayoutTransition) {
        self.theme = theme
        self.currentStatusBarStyle = theme.statusBar
        self.defaultNavigationBarPresentationData = NavigationBarPresentationData(theme: theme.navigationBar)
        if isViewLoaded {
            view.backgroundColor = theme.emptyAreaColor
        }
        sharedNavigationBar?.updatePresentationData(defaultNavigationBarPresentationData, transition: transition)

        if case let .split(container)? = rootContainer {
            container.updateTheme(theme: theme)
        }

        if let layout = validLayout {
            updateVisibleContainers(layout: layout, transition: transition)
        } else {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func resolvedNavigationBarAppearance(
        for controller: AetherViewController?,
        appearance: AetherAppearance
    ) -> AetherNavigationBarResolvedAppearance {
        var inheritedAppearance = appearance
        if let compatibilityThemeOverride {
            let barTheme = compatibilityThemeOverride.navigationBar
            inheritedAppearance = inheritedAppearance.resolvingAppearanceStyle(barTheme.appearanceStyle)
            inheritedAppearance.overallDarkAppearance = barTheme.overallDarkAppearance
            inheritedAppearance.emptyAreaColor = compatibilityThemeOverride.emptyAreaColor
            inheritedAppearance.edgeEffectColor = barTheme.edgeEffectColor ?? compatibilityThemeOverride.emptyAreaColor
            inheritedAppearance.edgeEffectAlpha = barTheme.edgeEffectAlpha
            inheritedAppearance.edgeEffectBlurRadiusAtEdge = barTheme.edgeEffectBlurRadiusAtEdge
            inheritedAppearance.edgeEffectBlurRadiusAtFade = barTheme.edgeEffectBlurRadiusAtFade
            inheritedAppearance.edgeEffectStyle = barTheme.edgeEffectStyle
            inheritedAppearance.separatorColor = barTheme.separatorColor
        }

        let overrideResolution = resolveAetherAppearanceOverride(
            appearance: inheritedAppearance,
            surface: .navigation,
            placement: .navigation,
            traitCollection: traitCollection,
            container: self,
            content: controller
        )
        let compatibilityOverride = compatibilityThemeOverride.map {
            navigationCompatibilityOverride(
                from: $0,
                includeRendererFields: overrideResolution.appearance.style == $0.navigationBar.appearanceStyle
            )
        }
        let mergedOverride = compatibilityOverride?
            .merged(with: overrideResolution.override)
            ?? overrideResolution.override
        let resolutionContext = AetherAppearanceResolutionContext(
            appearance: overrideResolution.appearance,
            surface: .navigation,
            placement: .navigation,
            traitCollection: traitCollection
        )
        return AetherNavigationBarAppearanceResolver.resolve(
            context: resolutionContext,
            override: mergedOverride?.navigationBar
        )
    }

    private func resolvedNavigationControllerTheme(for appearance: AetherAppearance) -> NavigationControllerTheme {
        let resolved = resolvedNavigationBarAppearance(for: topController, appearance: appearance)
        guard let compatibilityThemeOverride else {
            return NavigationControllerTheme(
                statusBar: resolved.overallDarkAppearance ? .white : .black,
                navigationBar: NavigationBarTheme(aetherResolvedAppearance: resolved),
                emptyAreaColor: resolved.emptyAreaColor
            )
        }

        let compatibilityBarTheme = compatibilityThemeOverride.navigationBar
        let adaptedBarTheme = NavigationBarTheme(
            aetherResolvedAppearance: resolved,
            accentButtonColor: compatibilityBarTheme.accentButtonColor,
            accentForegroundColor: compatibilityBarTheme.accentForegroundColor
        )
        let resolvedBarTheme = NavigationBarTheme(
            overallDarkAppearance: adaptedBarTheme.overallDarkAppearance,
            buttonColor: adaptedBarTheme.buttonColor,
            disabledButtonColor: compatibilityBarTheme.disabledButtonColor,
            primaryTextColor: adaptedBarTheme.primaryTextColor,
            backgroundColor: adaptedBarTheme.backgroundColor,
            opaqueBackgroundColor: adaptedBarTheme.opaqueBackgroundColor,
            enableBackgroundBlur: adaptedBarTheme.enableBackgroundBlur,
            separatorColor: adaptedBarTheme.separatorColor,
            badgeBackgroundColor: compatibilityBarTheme.badgeBackgroundColor,
            badgeStrokeColor: compatibilityBarTheme.badgeStrokeColor,
            badgeTextColor: compatibilityBarTheme.badgeTextColor,
            edgeEffectColor: adaptedBarTheme.edgeEffectColor,
            accentButtonColor: compatibilityBarTheme.accentButtonColor,
            accentForegroundColor: compatibilityBarTheme.accentForegroundColor,
            style: adaptedBarTheme.style,
            appearanceStyle: adaptedBarTheme.appearanceStyle,
            glassStyle: adaptedBarTheme.glassStyle,
            edgeEffectAlpha: adaptedBarTheme.edgeEffectAlpha,
            edgeEffectBlurRadiusAtEdge: adaptedBarTheme.edgeEffectBlurRadiusAtEdge,
            edgeEffectBlurRadiusAtFade: adaptedBarTheme.edgeEffectBlurRadiusAtFade,
            edgeEffectSolidBlur: adaptedBarTheme.edgeEffectSolidBlur,
            edgeEffectStyle: adaptedBarTheme.edgeEffectStyle,
            defaultContentHeight: compatibilityBarTheme.defaultContentHeight
        )
        return NavigationControllerTheme(
            statusBar: compatibilityThemeOverride.statusBar,
            navigationBar: resolvedBarTheme,
            emptyAreaColor: resolved.emptyAreaColor
        )
    }

    private func navigationCompatibilityOverride(
        from theme: NavigationControllerTheme,
        includeRendererFields: Bool
    ) -> AetherAppearanceOverride {
        let barTheme = theme.navigationBar
        let background: AetherBarBackgroundAppearance?
        let separator: AetherSeparatorAppearance?
        let edgeEffect: AetherEdgeEffectAppearance?

        if includeRendererFields {
            switch barTheme.style {
            case .legacy:
                background = .color(barTheme.backgroundColor)
            case .glass:
                if barTheme.enableBackgroundBlur {
                    let glassStyle: SystemGlassEffectStyle
                    switch barTheme.glassStyle {
                    case .default:
                        glassStyle = .regular
                    case .strong:
                        glassStyle = .strong
                    case .clear:
                        glassStyle = .clear
                    }
                    background = .glass(glassStyle)
                } else {
                    background = .transparent
                }
            }
            separator = .visible(color: barTheme.separatorColor, opacity: 1.0)
            edgeEffect = AetherEdgeEffectAppearance(
                isEnabled: barTheme.appearanceStyle.usesLiquidGlass,
                tintColor: barTheme.edgeEffectColor,
                alpha: barTheme.edgeEffectAlpha,
                blurRadiusAtEdge: barTheme.edgeEffectBlurRadiusAtEdge,
                blurRadiusAtFade: barTheme.edgeEffectBlurRadiusAtFade,
                solidBlur: barTheme.edgeEffectSolidBlur,
                style: barTheme.edgeEffectStyle
            )
        } else {
            background = nil
            separator = nil
            edgeEffect = nil
        }

        return AetherAppearanceOverride(
            appearanceStyle: barTheme.appearanceStyle,
            navigationBar: AetherNavigationBarAppearanceOverride(
                background: background,
                separator: separator,
                edgeEffect: edgeEffect,
                emptyAreaColor: theme.emptyAreaColor,
                buttonColor: barTheme.buttonColor,
                primaryTextColor: barTheme.primaryTextColor
            )
        )
    }

    // MARK: - Private

    private func navigationBarButtonMorphTransition() -> ContainedViewLayoutTransition {
        return .animated(
            duration: AetherMotion.navigationChrome.geometry.duration,
            // Land the real geometry monotonically at its model endpoint.
            // The independent glass size pulse supplies the visible elasticity;
            // the softer response avoids an initial kick while preserving the
            // exact endpoint that a short finite spring could not guarantee.
            curve: .navigationFluidMorph
        )
    }

    private func navigationBarButtonEffectTransition(from transition: ContainedViewLayoutTransition, appearing: Bool) -> ContainedViewLayoutTransition {
        guard transition.isAnimated else {
            return .immediate
        }
        let requestedDuration = appearing
            ? AetherMotion.navigationChrome.contentAppearanceDuration
            : AetherMotion.navigationChrome.contentDisappearanceDuration
        return .animated(
            duration: min(transition.duration, requestedDuration),
            curve: .easeInOut
        )
    }

    private func buttonPulseAmplitude(appearing: Bool) -> CGFloat {
        appearing
            ? AetherMotion.navigationChrome.appearancePulseAmplitude
            : AetherMotion.navigationChrome.disappearancePulseAmplitude
    }

    private func viewControllerArraysAreEqual(_ lhs: [AetherViewController], _ rhs: [AetherViewController]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        for (left, right) in zip(lhs, rhs) where left !== right {
            return false
        }
        return true
    }

    private func applyPendingViewControllersUpdateIfPossible() {
        guard interactiveNavigationBarTransition == nil, let pending = pendingViewControllersUpdate else {
            return
        }

        pendingViewControllersUpdate = nil
        isApplyingPendingViewControllersUpdate = true
        defer { isApplyingPendingViewControllersUpdate = false }

        _viewControllers = pending.controllers
        wireControllers(pending.controllers)
        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: pending.animated))
        }
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
    }

    private func updateVisibleContainers(
        layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        navigationChromeTransition: ContainedViewLayoutTransition? = nil
    ) {
        let navigationChromeTransition = navigationChromeTransition ?? transition
        let navigationLayout = makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers)
        let rootTopController = activeRootStack(for: navigationLayout.root).last
        let rootTransitionShouldDriveNavigationBar = navigationChromeTransition.isAnimated
            && rootTopController != nil
            && sharedNavigationBarController != nil
            && sharedNavigationBarController !== rootTopController

        if rootTransitionShouldDriveNavigationBar {
            let previousNavigationBarTransition = interactiveNavigationBarTransition
            updateRootContainer(for: navigationLayout.root, layout: layout, transition: transition)
            if interactiveNavigationBarTransition == nil || interactiveNavigationBarTransition === previousNavigationBarTransition {
                updateSharedNavigationBar(for: navigationLayout.root, layout: layout, transition: navigationChromeTransition)
            }
        } else {
            updateSharedNavigationBar(for: navigationLayout.root, layout: layout, transition: navigationChromeTransition)
            updateRootContainer(for: navigationLayout.root, layout: layout, transition: transition)
        }
        updateMinimizedContainer(layout: layout, transition: transition)
        updateOverlayContainers(layout: overlayLayout(from: layout), transition: transition)
        cleanupRemovedChildren()
        updateStatusBarAppearance()
    }

    private func updateRootContainer(for rootLayout: RootNavigationLayout, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        switch rootLayout {
        case let .flat(controllers):
            let container = ensureFlatRootContainer()
            container.frame = CGRect(origin: .zero, size: layout.size)
            container.setControllers(controllers, animated: transition.isAnimated)
            container.containerLayoutUpdated(layout, transition: transition)
        case let .split(masterControllers, detailControllers):
            let container = ensureSplitRootContainer()
            container.frame = CGRect(origin: .zero, size: layout.size)
            container.update(layout: layout, masterControllers: masterControllers, detailControllers: detailControllers, transition: transition)
        }
    }

    private func updateOverlayContainers(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition, appearingContainer: NavigationOverlayContainer? = nil, completion: (() -> Void)? = nil) {
        for container in overlayContainers where !container.isRemoved {
            let wasNotAdded = container.superview == nil
            if wasNotAdded {
                view.addSubview(container)
            }

            container.update(layout: layout, transition: transition)

            if wasNotAdded {
                container.transitionIn(animated: transition.isAnimated && container === appearingContainer, completion: container === appearingContainer ? completion : nil)
            } else if container === appearingContainer {
                completion?()
            }

            // bringSubviewToFront pays a z-reorder + implicit layout-invalidation
            // cost even when the view is already on top. Skip when no-op.
            if view.subviews.last !== container {
                view.bringSubviewToFront(container)
            }
        }

        if appearingContainer == nil {
            completion?()
        }
    }

    private func updateMinimizedContainer(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard let minimizedContainer else {
            return
        }

        if minimizedContainer.superview !== view {
            view.addSubview(minimizedContainer)
        }
        transition.updateFrame(view: minimizedContainer, frame: CGRect(origin: .zero, size: layout.size))
        minimizedContainer.updateLayout(layout, transition: transition)
        if view.subviews.last !== minimizedContainer {
            view.bringSubviewToFront(minimizedContainer)
        }
    }

    private func wireControllers(_ viewControllers: [AetherViewController]) {
        let sharedBar = self.sharedNavigationBar

        for controller in viewControllers {
            controller.navigationBarIsExternallyHosted = true

            if let bar = controller.navigationBarView, bar !== sharedBar {
                bar.removeFromSuperview()
                controller.navigationBarView = nil
            } else if controller.navigationBarView === sharedBar, controller !== sharedNavigationBarController {
                controller.navigationBarView = nil
            }

            controller.topBarAccessoryTransitionDidChange = { [weak self, weak controller] transition in
                guard let self, let controller else { return }
                guard !self.isUpdatingSharedNavigationBar else { return }
                guard self.sharedNavigationBarController === controller else { return }
                self.requestLayout(transition: transition)
            }

            if controller.parent !== self {
                addChild(controller)
                controller.didMove(toParent: self)
            }
        }
    }

    private func ensureSharedNavigationBar() -> NavigationBarImpl {
        if let sharedNavigationBar {
            return sharedNavigationBar
        }

        let bar = NavigationBarImpl(presentationData: defaultNavigationBarPresentationData)
        bar.autoresizingMask = [.flexibleWidth]
        bar.backPressed = { [weak self] in
            self?.popViewController(animated: true)
        }
        bar.requestContainerLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        bar.passthroughTouches = true
        sharedNavigationBar = bar

        if isViewLoaded, bar.superview !== view {
            view.addSubview(bar)
        }
        if isViewLoaded {
            bar.buttonLayerHostView = view
        }

        return bar
    }

    private func navigationBarPresentationData(for controller: AetherViewController) -> NavigationBarPresentationData {
        if let explicitNavigationBarPresentationData = controller.explicitNavigationBarPresentationData {
            return explicitNavigationBarPresentationData
        }
        let resolved = resolvedNavigationBarAppearance(for: controller, appearance: appearance)
        return NavigationBarPresentationData(theme: NavigationBarTheme(aetherResolvedAppearance: resolved))
    }

    private func activeRootStack(for rootLayout: RootNavigationLayout) -> [AetherViewController] {
        switch rootLayout {
        case let .flat(controllers):
            return controllers
        case let .split(masterControllers, detailControllers):
            return detailControllers.isEmpty ? masterControllers : detailControllers
        }
    }

    private func sharedNavigationLayout(for controller: AetherViewController, bar: NavigationBarView, layout: ContainerViewLayout) -> AetherViewController.NavigationLayout {
        let topOffset = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        let defaultNavigationBarHeight: CGFloat = 60.0
        let navBarContentHeight = bar.contentHeight(defaultHeight: defaultNavigationBarHeight)
        let navigationBarHeight = topOffset + navBarContentHeight + controller.additionalNavigationBarHeight

        var frame = CGRect(origin: .zero, size: CGSize(width: layout.size.width, height: navigationBarHeight))
        if !controller.displayNavigationBar {
            frame.origin.y = -navigationBarHeight
        }

        return AetherViewController.NavigationLayout(navigationFrame: frame, defaultContentHeight: defaultNavigationBarHeight)
    }

    private func estimatedTitleAreaHeight(for controller: AetherViewController, layout: ContainerViewLayout, defaultHeight: CGFloat) -> CGFloat {
        let titleHeight = NavigationBarImpl.measureTitleNaturalHeight(
            titleView: controller.navigationBarItem.titleView,
            for: layout.size,
            leftInset: layout.safeInsets.left,
            rightInset: layout.safeInsets.right
        )
        return max(defaultHeight, titleHeight)
    }

    private func estimatedSharedNavigationContentHeight(for controller: AetherViewController, layout: ContainerViewLayout, defaultHeight: CGFloat) -> CGFloat {
        let titleAreaHeight = controller.displayNavigationBar
            ? estimatedTitleAreaHeight(for: controller, layout: layout, defaultHeight: defaultHeight)
            : defaultHeight
        guard controller.displayNavigationBar, let contentView = controller.effectiveTopBarAccessory else {
            return titleAreaHeight
        }

        if let searchController = controller.searchController, searchController.placement == .navBar, searchController.isActive {
            if let stacked = contentView as? AetherStackedBarContent {
                return stacked.views.first?.nominalHeight ?? contentView.height
            }
            return contentView.height
        }

        switch contentView.mode {
        case .replacement:
            return contentView.height
        case .expansion:
            return titleAreaHeight + contentView.height
        }
    }

    private func estimatedExternalNavigationBarHeight(for controller: AetherViewController, layout: ContainerViewLayout) -> CGFloat {
        let topOffset = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        let defaultNavigationBarHeight: CGFloat = 60.0
        return topOffset
            + estimatedSharedNavigationContentHeight(for: controller, layout: layout, defaultHeight: defaultNavigationBarHeight)
            + controller.additionalNavigationBarHeight
    }

    private func updateExternalNavigationBarHeights(
        layout: ContainerViewLayout,
        resolvedTopController: AetherViewController?,
        resolvedTopHeight: CGFloat?
    ) {
        for controller in _viewControllers {
            controller.navigationBarIsExternallyHosted = true
            if let resolvedTopController, controller === resolvedTopController, let resolvedTopHeight {
                controller.externalNavigationBarHeight = resolvedTopHeight
            } else {
                controller.externalNavigationBarHeight = estimatedExternalNavigationBarHeight(for: controller, layout: layout)
            }
        }
    }

    private func updateExternalNavigationBarHeightsForTransition(
        _ state: NavigationBarInteractiveTransition,
        layout: ContainerViewLayout
    ) {
        for controller in _viewControllers {
            controller.navigationBarIsExternallyHosted = true
            if controller === state.sourceController {
                controller.externalNavigationBarHeight = state.sourceBaseFrame.height
            } else if controller === state.targetController {
                controller.externalNavigationBarHeight = state.targetBaseFrame.height
            } else {
                controller.externalNavigationBarHeight = estimatedExternalNavigationBarHeight(for: controller, layout: layout)
            }
        }
    }

    private func previousAction(for controller: AetherViewController, in stack: [AetherViewController]) -> NavigationPreviousAction? {
        guard let index = stack.firstIndex(where: { $0 === controller }), index > 0 else {
            return nil
        }
        return .item(stack[index - 1].navigationBarItem)
    }

    @discardableResult
    private func configureNavigationBar(
        _ bar: NavigationBarImpl,
        for controller: AetherViewController,
        in stack: [AetherViewController],
        layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        animateContent: Bool,
        buttonMorphTransition: ContainedViewLayoutTransition? = nil,
        includeAccessoryContent: Bool = true,
        allowsContainerLayoutRequests: Bool = true
    ) -> AetherViewController.NavigationLayout {
        let presentationData = navigationBarPresentationData(for: controller)
        if bar.presentationData !== presentationData {
            bar.updatePresentationData(presentationData, transition: transition)
        }

        let updateNavigationItem = {
            bar.item = controller.navigationBarItem
            bar.previousItem = self.previousAction(for: controller, in: stack)
        }
        if let buttonMorphTransition {
            bar.withButtonMorphTransition(buttonMorphTransition, updateNavigationItem)
        } else {
            updateNavigationItem()
        }
        bar.backPressed = { [weak self] in
            self?.popViewController(animated: true)
        }

        let requestLayout = allowsContainerLayoutRequests ? bar.requestContainerLayout : nil
        bar.requestContainerLayout = nil
        if includeAccessoryContent {
            bar.setContentHeightOverride(nil)
            bar.setContentView(controller.displayNavigationBar ? controller.effectiveTopBarAccessory : nil, animated: animateContent)
        } else {
            bar.setContentView(nil, animated: false)
            bar.setContentHeightOverride(
                estimatedSharedNavigationContentHeight(for: controller, layout: layout, defaultHeight: 60.0)
            )
        }
        if bar === sharedNavigationBar {
            bar.buttonLayerHostView = isViewLoaded ? view : nil
            bar.edgeEffectHostView = controller.isViewLoaded ? controller.view : nil
        } else {
            bar.edgeEffectHostView = nil
        }
        if allowsContainerLayoutRequests {
            bar.requestContainerLayout = requestLayout ?? { [weak self] transition in
                self?.requestLayout(transition: transition)
            }
        } else {
            bar.requestContainerLayout = nil
        }

        bar.updateMeasuredTitleHeight(
            titleView: controller.navigationBarItem.titleView,
            size: layout.size,
            defaultHeight: 60.0,
            leftInset: layout.safeInsets.left,
            rightInset: layout.safeInsets.right,
            requestLayoutIfNeeded: false
        )

        let navLayout = sharedNavigationLayout(for: controller, bar: bar, layout: layout)
        bar.frame = navLayout.navigationFrame
        let updateLayout = {
            bar.updateLayout(
                size: navLayout.navigationFrame.size,
                defaultHeight: navLayout.defaultContentHeight,
                additionalTopHeight: 0.0,
                additionalContentHeight: 0.0,
                additionalBackgroundHeight: 0.0,
                leftInset: layout.safeInsets.left,
                rightInset: layout.safeInsets.right,
                appearsHidden: !controller.displayNavigationBar,
                isLandscape: layout.size.width > layout.size.height,
                transition: transition
            )
        }
        if let buttonMorphTransition {
            bar.withButtonMorphTransition(buttonMorphTransition, updateLayout)
        } else {
            updateLayout()
        }
        return navLayout
    }

    private func updateSharedNavigationBar(for rootLayout: RootNavigationLayout, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard isViewLoaded else {
            return
        }

        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        if let interactiveNavigationBarTransition {
            bar.alpha = interactiveNavigationBarTransition.sourceController.displayNavigationBar ? 1.0 : 0.0
            bar.transform = .identity
            bar.setTitleContentHiddenForTransition(true)
            bar.setButtonContentHiddenForTransition(false)
            refreshInteractiveNavigationBarTransition(interactiveNavigationBarTransition, layout: layout, transition: transition)
            updateInteractiveNavigationBarTransition(progress: interactiveNavigationBarTransition.progress, transition: transition)
            return
        }

        let rootStack = activeRootStack(for: rootLayout)
        guard let topController = rootStack.last else {
            transition.updateAlpha(view: bar, alpha: 0.0)
            sharedNavigationBarController = nil
            for controller in _viewControllers {
                controller.navigationBarIsExternallyHosted = true
                controller.externalNavigationBarHeight = nil
                if controller.navigationBarView === bar {
                    controller.navigationBarView = nil
                }
            }
            return
        }
        topController.loadViewIfNeeded()

        let previousController = sharedNavigationBarController
        let shouldAnimateBarSwap = transition.isAnimated && previousController != nil && previousController !== topController
        if shouldAnimateBarSwap {
            bar.setTitleContentHiddenForTransition(true)
        } else {
            bar.setTitleContentHiddenForTransition(false)
        }
        bar.setButtonContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: .immediate)

        isUpdatingSharedNavigationBar = true
        defer { isUpdatingSharedNavigationBar = false }

        installSharedNavigationBarOwnership(bar, on: topController)

        let sharedButtonMorphTransition: ContainedViewLayoutTransition? = shouldAnimateBarSwap ? navigationBarButtonMorphTransition() : nil
        let navLayout = configureNavigationBar(
            bar,
            for: topController,
            in: rootStack,
            layout: layout,
            transition: shouldAnimateBarSwap ? .immediate : transition,
            animateContent: transition.isAnimated && !shouldAnimateBarSwap,
            buttonMorphTransition: sharedButtonMorphTransition
        )
        updateExternalNavigationBarHeights(
            layout: layout,
            resolvedTopController: topController,
            resolvedTopHeight: navLayout.navigationFrame.height
        )

        if shouldAnimateBarSwap {
            bar.alpha = topController.displayNavigationBar ? 1.0 : 0.0
            bar.transform = .identity
            bar.setTitleContentHiddenForTransition(true)
        } else {
            bar.alpha = topController.displayNavigationBar ? 1.0 : 0.0
            bar.transform = .identity
            bar.setTitleContentHiddenForTransition(false)
            bar.setButtonChromeScale(1.0, transition: .immediate)
        }

        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
        bar.bringButtonLayerToFrontIfNeeded()
    }

    private func installSharedNavigationBarOwnership(
        _ bar: NavigationBarImpl,
        on targetController: AetherViewController
    ) {
        for controller in _viewControllers {
            controller.navigationBarIsExternallyHosted = true
            if controller === targetController {
                controller.navigationBarView = bar
            } else if controller.navigationBarView === bar {
                controller.navigationBarView = nil
            }
        }
        sharedNavigationBarController = targetController
    }

    private func navigationStack(containing first: AetherViewController, pairedWith second: AetherViewController) -> [AetherViewController] {
        func stackByAppendingMissingSource(to controllers: [AetherViewController]) -> [AetherViewController]? {
            guard controllers.contains(where: { $0 === second }) else {
                return nil
            }
            if controllers.contains(where: { $0 === first }) {
                return controllers
            }

            var reconstructed = controllers
            reconstructed.append(first)
            return reconstructed
        }

        if let layout = currentLayoutForComputation() {
            switch makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers).root {
            case let .flat(controllers):
                if controllers.contains(where: { $0 === first }) && controllers.contains(where: { $0 === second }) {
                    return controllers
                }
                if let reconstructed = stackByAppendingMissingSource(to: controllers) {
                    return reconstructed
                }
            case let .split(masterControllers, detailControllers):
                if detailControllers.contains(where: { $0 === first }) && detailControllers.contains(where: { $0 === second }) {
                    return detailControllers
                }
                if masterControllers.contains(where: { $0 === first }) && masterControllers.contains(where: { $0 === second }) {
                    return masterControllers
                }
                if let reconstructed = stackByAppendingMissingSource(to: detailControllers) {
                    return reconstructed
                }
                if let reconstructed = stackByAppendingMissingSource(to: masterControllers) {
                    return reconstructed
                }
            }
        }
        if let reconstructed = stackByAppendingMissingSource(to: _viewControllers) {
            return reconstructed
        }
        return _viewControllers
    }

    private func makeTransitionNavigationBar(
        for controller: AetherViewController,
        in stack: [AetherViewController],
        layout: ContainerViewLayout
    ) -> NavigationBarImpl {
        controller.loadViewIfNeeded()
        let bar = NavigationBarImpl(presentationData: navigationBarPresentationData(for: controller))
        bar.autoresizingMask = [.flexibleWidth]
        bar.requestContainerLayout = nil
        bar.hostsNavigationItemTitleView = false
        // Transition bars render titles only. Enable that mode before the bar
        // is configured so layout never reparents caller-owned bar-button
        // custom views away from the persistent shared navigation bar.
        bar.setTitleTransitionMode(true)
        configureNavigationBar(
            bar,
            for: controller,
            in: stack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            allowsContainerLayoutRequests: false
        )
        bar.setTitleContentHiddenForTransition(false)
        return bar
    }

    private func installTransitionNavigationBars(_ state: NavigationBarInteractiveTransition) {
        if state.targetBar.superview !== state.targetController.view {
            state.targetBar.removeFromSuperview()
            state.targetController.view.addSubview(state.targetBar)
        }
        if state.sourceBar.superview !== state.sourceController.view {
            state.sourceBar.removeFromSuperview()
            state.sourceController.view.addSubview(state.sourceBar)
        }
        state.targetController.view.bringSubviewToFront(state.targetBar)
        state.sourceController.view.bringSubviewToFront(state.sourceBar)
    }

    private func beginInteractiveNavigationBarTransition(
        direction: NavigationTransitionDirection,
        sourceController: AetherViewController,
        targetController: AetherViewController,
        layout gestureLayout: ContainerViewLayout,
        isInteractive: Bool
    ) {
        guard isViewLoaded else {
            return
        }

        if let existingTransition = interactiveNavigationBarTransition {
            finishInteractiveNavigationBarTransition(existingTransition, completed: false)
        }

        let layout = validLayout ?? gestureLayout
        let stack = navigationStack(containing: sourceController, pairedWith: targetController)
        let sourceBar = makeTransitionNavigationBar(for: sourceController, in: stack, layout: layout)
        let targetBar = makeTransitionNavigationBar(for: targetController, in: stack, layout: layout)
        let state = NavigationBarInteractiveTransition(
            direction: direction,
            sourceController: sourceController,
            targetController: targetController,
            sourceStack: stack,
            targetStack: stack,
            sourceBar: sourceBar,
            targetBar: targetBar,
            isInteractive: isInteractive
        )
        interactiveNavigationBarTransition = state

        if let sharedNavigationBar {
            sharedNavigationBar.alpha = sourceController.displayNavigationBar ? 1.0 : 0.0
            sharedNavigationBar.transform = .identity
            sharedNavigationBar.setTitleContentHiddenForTransition(true)
            sharedNavigationBar.setButtonContentHiddenForTransition(false)
            sharedNavigationBar.setButtonChromeScale(1.0, transition: .immediate)
        }

        installTransitionNavigationBars(state)
        refreshInteractiveNavigationBarTransition(state, layout: layout, transition: .immediate)
        updateExternalNavigationBarHeightsForTransition(state, layout: layout)
        scheduleNavigationBarButtonTransition(state, layout: layout)
        sourceController.containerLayoutUpdated(layoutForController?(sourceController, layout) ?? layout, transition: .immediate)
        targetController.containerLayoutUpdated(layoutForController?(targetController, layout) ?? layout, transition: .immediate)
        installTransitionNavigationBars(state)
        updateInteractiveNavigationBarTransition(progress: 0.0, transition: .immediate)
    }

    private func scheduleNavigationBarButtonTransition(
        _ state: NavigationBarInteractiveTransition,
        layout: ContainerViewLayout
    ) {
        state.scheduledButtonTransition?.cancel()
        // During an interactive pop the source chrome must remain completely
        // stable under the finger. Resolve and start the semantic replacement
        // only after UIKit reports completion/cancellation on release.
        guard !state.isInteractive else {
            state.scheduledButtonTransition = nil
            return
        }
        let timing = Self.navigationChromeTransitionTiming(
            direction: state.direction,
            isInteractive: state.isInteractive
        )
        guard timing.delay > .ulpOfOne else {
            startNavigationBarButtonTransition(state, layout: layout)
            return
        }

        let workItem = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state,
                  self.interactiveNavigationBarTransition === state else {
                return
            }
            state.scheduledButtonTransition = nil
            self.startNavigationBarButtonTransition(state, layout: self.validLayout ?? layout)
        }
        state.scheduledButtonTransition = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.delay, execute: workItem)
    }

    private func startNavigationBarButtonTransition(
        _ state: NavigationBarInteractiveTransition,
        layout: ContainerViewLayout
    ) {
        guard interactiveNavigationBarTransition === state else {
            return
        }
        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        let buttonTransition = navigationBarButtonMorphTransition()
        configureNavigationBar(
            bar,
            for: state.targetController,
            in: state.targetStack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            buttonMorphTransition: buttonTransition,
            includeAccessoryContent: false
        )
        updateExternalNavigationBarHeights(
            layout: layout,
            resolvedTopController: state.targetController,
            resolvedTopHeight: bar.frame.height
        )

        bar.transform = .identity
        bar.alpha = state.targetController.displayNavigationBar ? 1.0 : 0.0
        bar.setTitleContentHiddenForTransition(true)
        bar.setButtonContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: .immediate)
        sharedNavigationBarController = state.targetController
        state.didResolveButtonTransition = true
        state.resolvedCompleted = true
        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
        bar.bringButtonLayerToFrontIfNeeded()
    }

    private func refreshInteractiveNavigationBarTransition(
        _ state: NavigationBarInteractiveTransition,
        layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        let sourceLayout = configureNavigationBar(
            state.sourceBar,
            for: state.sourceController,
            in: state.sourceStack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            allowsContainerLayoutRequests: false
        )
        state.sourceBaseFrame = sourceLayout.navigationFrame
        state.sourceBar.setTitleContentHiddenForTransition(false)

        let targetLayout = configureNavigationBar(
            state.targetBar,
            for: state.targetController,
            in: state.targetStack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            allowsContainerLayoutRequests: false
        )
        state.targetBaseFrame = targetLayout.navigationFrame
        state.targetBar.setTitleContentHiddenForTransition(false)

        installTransitionNavigationBars(state)
        updateExternalNavigationBarHeightsForTransition(state, layout: layout)
        if let minimizedContainer, minimizedContainer.superview === view {
            view.bringSubviewToFront(minimizedContainer)
        }
    }

    private func applyNavigationBarTitleTransitionProgress(
        _ state: NavigationBarInteractiveTransition,
        progress: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: ((Bool) -> Void)? = nil
    ) {
        transition.updateFrame(view: state.sourceBar, frame: state.sourceBaseFrame)
        transition.updateFrame(view: state.targetBar, frame: state.targetBaseFrame, completion: completion)

        state.sourceBar.alpha = state.sourceController.displayNavigationBar ? 1.0 : 0.0
        state.targetBar.alpha = state.targetController.displayNavigationBar ? 1.0 : 0.0
        state.targetBar.layer.mask = nil
    }

    private func updateInteractiveNavigationBarTransition(progress: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let state = interactiveNavigationBarTransition else {
            return
        }

        state.progress = progress

        applyNavigationBarTitleTransitionProgress(state, progress: progress, transition: transition)

        if let sharedNavigationBar {
            if let resolvedCompleted = state.resolvedCompleted {
                let resolvedController = resolvedCompleted ? state.targetController : state.sourceController
                sharedNavigationBar.alpha = resolvedController.displayNavigationBar ? 1.0 : 0.0
                sharedNavigationBar.transform = .identity
                sharedNavigationBar.setTitleContentHiddenForTransition(true)
                sharedNavigationBar.setButtonContentHiddenForTransition(false)
                sharedNavigationBar.setButtonChromeScale(1.0, transition: transition)
                sharedNavigationBar.bringButtonLayerToFrontIfNeeded()
                return
            }

            sharedNavigationBar.alpha = state.sourceController.displayNavigationBar ? 1.0 : 0.0
            sharedNavigationBar.transform = .identity
            sharedNavigationBar.setTitleContentHiddenForTransition(true)
            sharedNavigationBar.setButtonContentHiddenForTransition(false)
            sharedNavigationBar.setButtonChromeScale(1.0, transition: transition)
            sharedNavigationBar.bringButtonLayerToFrontIfNeeded()
        }
    }

    private func resolveInteractiveNavigationBarTransition(
        completed: Bool,
        transition _: ContainedViewLayoutTransition? = nil
    ) {
        guard let state = interactiveNavigationBarTransition else {
            return
        }
        state.scheduledButtonTransition?.cancel()
        state.scheduledButtonTransition = nil
        if state.didResolveButtonTransition && state.resolvedCompleted == completed {
            return
        }

        state.didResolveButtonTransition = true
        state.resolvedCompleted = completed
        let targetController = completed ? state.targetController : state.sourceController
        let targetStack = completed ? state.targetStack : state.sourceStack

        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        // Chrome owns a fixed clock. Interactive completion/cancellation may
        // velocity-compress the screen settle, but never the glass/content
        // hand-off; cancellation simply runs the same semantic morph back to
        // the source state.
        let buttonTransition = navigationBarButtonMorphTransition()
        if let layout = validLayout ?? currentLayoutForComputation() {
            configureNavigationBar(
                bar,
                for: targetController,
                in: targetStack,
                layout: layout,
                transition: .immediate,
                animateContent: false,
                buttonMorphTransition: buttonTransition,
                includeAccessoryContent: false
            )
            updateExternalNavigationBarHeights(
                layout: layout,
                resolvedTopController: targetController,
                resolvedTopHeight: bar.frame.height
            )
        }

        bar.transform = .identity
        bar.alpha = targetController.displayNavigationBar ? 1.0 : 0.0
        bar.setTitleContentHiddenForTransition(true)
        bar.setButtonContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: buttonTransition)
        sharedNavigationBarController = targetController
        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
        bar.bringButtonLayerToFrontIfNeeded()
    }

    private func finishInteractiveNavigationBarTransition(_ state: NavigationBarInteractiveTransition, completed: Bool) {
        state.scheduledButtonTransition?.cancel()
        state.scheduledButtonTransition = nil
        let targetController = completed ? state.targetController : state.sourceController
        let targetStack = completed ? state.targetStack : state.sourceStack
        interactiveNavigationBarTransition = nil

        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        let shouldRunFinishButtonMorph = completed && !state.didResolveButtonTransition
        let finishButtonTransition: ContainedViewLayoutTransition = shouldRunFinishButtonMorph ? navigationBarButtonMorphTransition() : .immediate
        if let layout = validLayout ?? currentLayoutForComputation() {
            configureNavigationBar(
                bar,
                for: targetController,
                in: targetStack,
                layout: layout,
                transition: .immediate,
                animateContent: false,
                buttonMorphTransition: shouldRunFinishButtonMorph ? finishButtonTransition : nil
            )
            updateExternalNavigationBarHeights(
                layout: layout,
                resolvedTopController: targetController,
                resolvedTopHeight: bar.frame.height
            )
        }
        bar.transform = .identity
        bar.alpha = targetController.displayNavigationBar ? 1.0 : 0.0
        bar.setTitleContentHiddenForTransition(false)
        bar.setButtonContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: finishButtonTransition)
        installSharedNavigationBarOwnership(bar, on: targetController)

        state.sourceBar.detachButtonLayerFromHost()
        state.sourceBar.removeFromSuperview()
        state.targetBar.detachButtonLayerFromHost()
        state.targetBar.removeFromSuperview()
        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
        bar.bringButtonLayerToFrontIfNeeded()
    }

    private func cleanupRemovedChildren() {
        var activeIdentifiers = Set(_viewControllers.map { ObjectIdentifier($0) })
        for overlayContainer in overlayContainers where !overlayContainer.isRemoved {
            activeIdentifiers.insert(ObjectIdentifier(overlayContainer.controller))
        }
        for child in children {
            guard let controller = child as? AetherViewController else {
                continue
            }
            guard !activeIdentifiers.contains(ObjectIdentifier(controller)) else {
                continue
            }
            guard controller.parent === self else {
                continue
            }
            controller.topBarAccessoryTransitionDidChange = nil
            controller.navigationBarIsExternallyHosted = false
            controller.externalNavigationBarHeight = nil
            if controller.navigationBarView === sharedNavigationBar {
                controller.navigationBarView = nil
            }
            controller.willMove(toParent: nil)
            controller.removeFromParent()
        }
    }

    private func handleControllerRemoved(_ controller: AetherViewController) {
        let wasPresent = _viewControllers.contains { $0 === controller }
        _viewControllers.removeAll { $0 === controller }
        if wasPresent {
            wireControllers(_viewControllers)
            if let layout = validLayout {
                updateVisibleContainers(layout: layout, transition: .immediate)
            }
        } else {
            cleanupRemovedChildren()
        }
    }

    private func handleControllerRemovalCommitted(_ controller: AetherViewController) {
        guard _viewControllers.contains(where: { $0 === controller }) else {
            return
        }
        _viewControllers.removeAll { $0 === controller }
        wireControllers(_viewControllers)
    }

    private func ensureFlatRootContainer() -> NavigationContainer {
        if case let .flat(container)? = rootContainer {
            return container
        }

        let container = NavigationContainer(frame: view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.controllerRemoved = { [weak self] controller in
            self?.handleControllerRemoved(controller)
        }
        container.controllerRemovalCommitted = { [weak self] controller in
            self?.handleControllerRemovalCommitted(controller)
        }
        container.requestLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        wireControllerLayoutProvider(to: container)
        wireNavigationBarTransitionCallbacks(to: container)

        installRootContainerView(container)
        rootContainer = .flat(container)
        return container
    }

    private func ensureSplitRootContainer() -> NavigationSplitContainer {
        if case let .split(container)? = rootContainer {
            return container
        }

        let container = NavigationSplitContainer(
            theme: theme,
            controllerRemoved: { [weak self] controller in
                self?.handleControllerRemoved(controller)
            },
            controllerRemovalCommitted: { [weak self] controller in
                self?.handleControllerRemovalCommitted(controller)
            },
            scrollToTop: { [weak self] target in
                guard let self else {
                    return
                }
                switch target {
                case .master:
                    if case let .split(container)? = self.rootContainer {
                        container.masterContainer.topController?.scrollToTop?()
                    }
                case .detail:
                    if case let .split(container)? = self.rootContainer {
                        container.detailContainer.topController?.scrollToTop?()
                    }
                }
            }
        )
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wireControllerLayoutProvider(to: container.masterContainer)
        wireControllerLayoutProvider(to: container.detailContainer)
        wireNavigationBarTransitionCallbacks(to: container.masterContainer)
        wireNavigationBarTransitionCallbacks(to: container.detailContainer)

        installRootContainerView(container)
        rootContainer = .split(container)
        return container
    }

    private func updateRootContainerLayoutProviders() {
        switch rootContainer {
        case let .flat(container):
            wireControllerLayoutProvider(to: container)
        case let .split(container):
            wireControllerLayoutProvider(to: container.masterContainer)
            wireControllerLayoutProvider(to: container.detailContainer)
        case nil:
            break
        }
    }

    private func wireControllerLayoutProvider(to container: NavigationContainer) {
        container.layoutForController = { [weak self] controller, layout in
            guard let self, let layoutForController = self.layoutForController else {
                return layout
            }
            return layoutForController(controller, layout)
        }
    }

    private func wireNavigationBarTransitionCallbacks(to container: NavigationContainer) {
        container.navigationBarTransitionBegan = { [weak self] direction, sourceController, targetController, layout, isInteractive in
            self?.beginInteractiveNavigationBarTransition(
                direction: direction,
                sourceController: sourceController,
                targetController: targetController,
                layout: layout,
                isInteractive: isInteractive
            )
        }
        container.navigationBarTransitionProgress = { [weak self] progress, transition in
            self?.updateInteractiveNavigationBarTransition(progress: progress, transition: transition)
        }
        container.navigationBarTransitionResolutionBegan = { [weak self] completed, transition in
            self?.resolveInteractiveNavigationBarTransition(completed: completed, transition: transition)
        }
        container.navigationBarTransitionEnded = { [weak self] completed in
            guard let self, let transition = self.interactiveNavigationBarTransition else {
                return
            }
            self.finishInteractiveNavigationBarTransition(transition, completed: completed)
            self.applyPendingViewControllersUpdateIfPossible()
        }

        container.bottomBarTransitionBegan = { [weak self] direction, sourceController, targetController, _, isInteractive in
            self?.bottomBarVisibilityTransitionBegan?(direction, sourceController, targetController, isInteractive)
        }
        container.bottomBarTransitionProgress = { [weak self] progress, transition in
            self?.bottomBarVisibilityTransitionProgress?(progress, transition)
        }
        container.bottomBarTransitionResolutionBegan = { [weak self] completed, transition in
            self?.bottomBarVisibilityTransitionResolutionBegan?(completed, transition)
        }
        container.bottomBarTransitionEnded = { [weak self] completed in
            self?.bottomBarVisibilityTransitionEnded?(completed)
        }
    }

    private func installRootContainerView(_ newView: UIView) {
        if let existingRootContainer = rootContainer {
            switch existingRootContainer {
            case let .flat(container):
                container.removeFromSuperview()
            case let .split(container):
                container.removeFromSuperview()
            }
        }

        view.insertSubview(newView, at: 0)
    }

    private func updateStatusBarAppearance() {
        currentStatusBarStyle = theme.statusBar
        setNeedsStatusBarAppearanceUpdate()
    }

    private func overlayLayout(from layout: ContainerViewLayout) -> ContainerViewLayout {
        guard let minimizedContainer, !minimizedContainer.isExpanded else {
            return layout
        }

        var additionalInsets = layout.additionalInsets
        additionalInsets.bottom += minimizedContainer.collapsedHeight(layout: layout)
        return layout.withUpdatedAdditionalInsets(additionalInsets)
    }

    private func currentLayoutForComputation() -> ContainerViewLayout? {
        if let validLayout {
            return validLayout
        }

        guard isViewLoaded else {
            return nil
        }

        let statusBarHeight: CGFloat? = isHostedInModal
            ? AetherModalController.grabberContainerHeight
            : view.window?.windowScene?.statusBarManager?.statusBarFrame.height

        return ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: view.safeAreaInsets,
            additionalInsets: .zero,
            statusBarHeight: statusBarHeight,
            inputHeight: nil,
            inputHeightIsInteractivellyChanging: false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
    }

    private func transitionForUpdate(animated: Bool) -> ContainedViewLayoutTransition {
        animated
            ? .animated(
                duration: AetherMotion.navigationChrome.geometry.duration,
                curve: .navigationFluidMorph
            )
            : .immediate
    }
}
