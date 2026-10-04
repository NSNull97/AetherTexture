import UIKit

/// Modal sheet that hosts a `AetherNavigationController` inside its
/// content area — gives consumers `pushViewController` / `popViewController` /
/// `viewControllers` and a navbar at the top of the sheet without
/// the boilerplate of wiring nav + form + embed by hand.
///
/// Use it the way you'd use a vanilla `UINavigationController`:
///
/// ```swift
/// final class MyModal: AetherModalNavigationController {
///     init() {
///         super.init(rootViewController: MyFormVC(), config: .init(...))
///     }
///     override func viewDidLoad() {
///         super.viewDidLoad()
///         contentConfigurationMode = .manual
///         footerView = sendButton
///         footerHeight = 98
///         primaryScrollView = (rootViewController as? MyFormVC)?.scroll
///     }
/// }
/// ```
///
/// The internal `AetherNavigationController` is exposed read-only as
/// `internalNavigationController` for callers that need its specific API
/// (overlay containers, popover hosts, etc.). Otherwise the forwarded
/// methods on this class cover the standard navigation surface —
/// `viewControllers`, `pushViewController(_:animated:)`,
/// `popViewController(animated:)`, `popToRoot(animated:)`,
/// `setViewControllers(_:animated:)`.
///
/// The navigation bar absorbs the grabber strip (its `statusBarHeight`
/// is overridden to `grabberContainerHeight` when hosted in a modal —
/// see `AetherNavigationController.updateContainerLayout`), so the
/// chrome reads as a single rounded sheet with its own bar rather than
/// as a navbar grafted onto a separate container.
open class AetherModalNavigationController: AetherModalController {
    /// Internal navigation controller. Exposed for advanced cases where
    /// the caller needs its full surface (minimized container, custom
    /// transitions). Most consumers should use the forwarded methods on
    /// this class instead.
    public let internalNavigationController: AetherNavigationController
    public enum ContentConfigurationMode {
        /// Each visible screen supplies its own footer and scroll view.
        case perScreen
        /// The modal's caller configures footerView and primaryScrollView.
        case manual
    }

    /// Automatic configuration no longer depends on the root adopting a
    /// protocol. Choose manual when a subclass owns a stack-wide footer.
    public var contentConfigurationMode: ContentConfigurationMode = .perScreen {
        didSet {
            if isViewLoaded, contentTransition == nil { refreshContentConfiguration() }
        }
    }

    private struct ContentTransition {
        let source: AetherViewController
        let target: AetherViewController
        let sourceFooter: AetherModalFooterConfiguration
        let targetFooter: AetherModalFooterConfiguration
        let managesFooter: Bool
    }
    private var contentTransition: ContentTransition?

    private var usesPerScreenContentConfiguration: Bool {
        contentTransition?.managesFooter ?? (contentConfigurationMode == .perScreen)
    }

    override var isContentTransitioning: Bool {
        internalNavigationController.isTransitioning || contentTransition != nil
    }

    override var reservesFooterSafeArea: Bool {
        !usesPerScreenContentConfiguration
    }

    /// Convenience for "the VC at the bottom of the stack" — what a
    /// vanilla `UINavigationController` calls `viewControllers.first`.
    public var rootViewController: AetherViewController? {
        internalNavigationController.viewControllerStack.first
    }

    public var topViewController: AetherViewController? {
        internalNavigationController.topController
    }

    public var viewControllers: [AetherViewController] {
        get { internalNavigationController.viewControllerStack }
        set { internalNavigationController.setViewControllers(newValue, animated: false) }
    }

    /// Initialize an empty navigation stack. Add VCs via `viewControllers`
    /// or `pushViewController` after construction.
    public init(
        config: Config = Config(),
        navigationMode: NavigationControllerMode = .single
    ) {
        self.internalNavigationController = AetherNavigationController(mode: navigationMode)
        super.init(config: config)
    }


    public init(
        config: Config = Config(),
        navigationMode: NavigationControllerMode = .single,
        appearanceStyle: AetherAppearanceStyle
    ) {
        self.internalNavigationController = AetherNavigationController(mode: navigationMode)
        super.init(config: config)
        self.appearanceStyle = appearanceStyle
    }

    /// Initialize with a root VC — the navigation controller is seeded
    /// with `[rootViewController]` so `topViewController` / `rootViewController`
    /// are valid the moment `init` returns. Both flavours of init are
    /// `designated`: a subclass `init` can call either as its `super.init`.
    /// (A `convenience` super-init would force an awkward
    /// `self.init(config:)` + `setViewControllers([root])` two-step in
    /// the subclass.)
    public init(
        rootViewController: AetherViewController,
        config: Config = Config(),
        navigationMode: NavigationControllerMode = .single
    ) {
        self.internalNavigationController = AetherNavigationController(mode: navigationMode)
        super.init(config: config)
        internalNavigationController.setViewControllers([rootViewController], animated: false)
    }

    public init(
        rootViewController: AetherViewController,
        config: Config = Config(),
        navigationMode: NavigationControllerMode = .single,
        appearanceStyle: AetherAppearanceStyle
    ) {
        self.internalNavigationController = AetherNavigationController(mode: navigationMode)
        super.init(config: config)
        internalNavigationController.setViewControllers([rootViewController], animated: false)
        self.appearanceStyle = appearanceStyle
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        internalNavigationController.transitionCornerRadius = max(0, config.topCornerRadius)
        internalNavigationController.pageBackgroundColor = config.dimTintColor
        internalNavigationController.layoutForController = { [weak self] controller, layout in
            guard let self, self.usesPerScreenContentConfiguration else { return layout }
            let footer: AetherModalFooterConfiguration
            if let state = self.contentTransition, controller === state.source {
                footer = state.sourceFooter
            } else if let state = self.contentTransition, controller === state.target {
                footer = state.targetFooter
            } else {
                footer = self.configuration(for: controller)
            }
            var insets = layout.additionalInsets
            insets.bottom += max(0, footer.visibleHeight - layout.safeInsets.bottom)
            return layout.withUpdatedAdditionalInsets(insets)
        }
        internalNavigationController.topControllerDidChange = { [weak self] _ in
            guard let self, !self.isContentTransitioning else { return }
            self.applyTopContentConfiguration()
        }
        internalNavigationController.bottomBarVisibilityTransitionBegan = { [weak self] direction, source, target, _ in
            self?.beginContentTransition(from: source, to: target, direction: direction)
        }
        internalNavigationController.bottomBarVisibilityTransitionProgress = { [weak self] progress, _ in
            guard let self, let state = self.contentTransition, state.managesFooter else { return }
            self.updateFooterTransition(progress: progress,
                sourceOffset: state.source.view.frame.minX,
                targetOffset: state.target.view.frame.minX)
        }
        internalNavigationController.bottomBarVisibilityTransitionEnded = { [weak self] completed in
            self?.finishContentTransition(completed: completed)
        }
        embedContent(internalNavigationController)
        applyTopContentConfiguration()
        (presentationController as? AetherModalPresentationController)?.resumePendingDetentIfPossible()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let corners = resolvedCornerRadii()
        internalNavigationController.transitionCornerRadius = corners.top
        internalNavigationController.transitionBottomCornerRadius = corners.bottom
        guard contentConfigurationMode == .perScreen, !isContentTransitioning else { return }
        let configuration = configuration(for: topViewController)
        if footerView !== configuration.view || abs(footerHeight - configuration.visibleHeight) > 0.5 {
            applyFooterConfiguration(configuration)
            internalNavigationController.requestLayout(transition: .immediate)
        }
    }

    private func configuration(for controller: AetherViewController?) -> AetherModalFooterConfiguration {
        controller?.loadViewIfNeeded()
        guard let content = controller as? AetherModalContent else { return .init() }
        return .init(view: content.modalFooterView, height: content.modalFooterHeight,
                     fadeHeight: content.modalFooterEdgeFadeHeight, tintColor: content.modalFooterEdgeTintColor,
                     blurRadius: content.modalFooterEdgeBlurRadius, drawsEdge: content.modalFooterEdgeEffectEnabled)
    }

    private func applyTopContentConfiguration() {
        guard isViewLoaded, contentConfigurationMode == .perScreen else { return }
        let top = topViewController
        top?.loadViewIfNeeded()
        primaryScrollView = (top as? AetherModalContent)?.modalPrimaryScrollView ?? top?.primaryScrollViewForChrome
        applyFooterConfiguration(configuration(for: top))
    }

    private func refreshContentConfiguration() {
        applyTopContentConfiguration()
        // Switching ownership changes where the footer's inset is reserved,
        // even when the footer view and its height are unchanged.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        internalNavigationController.requestLayout(transition: .immediate)
    }

    private func beginContentTransition(from source: AetherViewController,
                                        to target: AetherViewController,
                                        direction: NavigationTransitionDirection) {
        let managesFooter = contentConfigurationMode == .perScreen
        let sourceFooter = managesFooter ? configuration(for: source) : .init()
        let targetFooter = managesFooter ? configuration(for: target) : .init()
        contentTransition = ContentTransition(source: source, target: target,
            sourceFooter: sourceFooter, targetFooter: targetFooter, managesFooter: managesFooter)
        (presentationController as? AetherModalPresentationController)?.suspendForContentTransition()
        if managesFooter {
            beginFooterTransition(from: sourceFooter, to: targetFooter, direction: direction)
        }
    }

    private func finishContentTransition(completed: Bool) {
        guard let state = contentTransition else { return }
        // Navigation guarantees that both the stack and its bars are settled
        // before notifying us. Cancellation has exactly the same cleanup path.
        contentTransition = nil
        if state.managesFooter {
            endFooterTransition(completed: completed)
        }
        refreshContentConfiguration()
        (presentationController as? AetherModalPresentationController)?.resumePendingDetentIfPossible()
    }

    // MARK: - Forwarded navigation API

    public func pushViewController(_ controller: AetherViewController, animated: Bool = true) {
        internalNavigationController.pushViewController(controller, animated: animated)
    }

    @discardableResult
    public func popViewController(animated: Bool = true) -> AetherViewController? {
        internalNavigationController.popViewController(animated: animated)
    }

    public func popToRoot(animated: Bool = true) {
        internalNavigationController.popToRoot(animated: animated)
    }

    public func setViewControllers(_ viewControllers: [AetherViewController], animated: Bool = true) {
        internalNavigationController.setViewControllers(viewControllers, animated: animated)
    }

    public func replaceTopController(_ controller: AetherViewController, animated: Bool = true) {
        internalNavigationController.replaceTopController(controller, animated: animated)
    }

}
