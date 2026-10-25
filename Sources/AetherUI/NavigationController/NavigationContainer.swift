import UIKit

/// Container view managing a stack of view controllers with push/pop transitions.
/// Replaces the original NavigationContainer.
public final class NavigationContainer: UIView, UIGestureRecognizerDelegate {
    public struct Child {
        public let controller: AetherViewController
        public let view: UIView
        public let navigationBar: NavigationBarView?
    }

    // MARK: - State

    private(set) var controllers: [AetherViewController] = []
    private var controllerViews: [UIView] = []
    private var transitionCoordinator: NavigationTransitionCoordinator?
    /// A controller-rendered transition replacing `transitionCoordinator`.
    private var customTransition: AetherCustomNavigationTransition?
    /// Set once an interactive custom pop has been released, so late pan
    /// samples cannot drive a transition that is already resolving.
    private var isResolvingCustomTransition: Bool = false
    /// Only a custom pop started by the pan gesture is driven by it; a
    /// running non-interactive custom push or pop ignores pan updates.
    private var isCustomTransitionInteractive: Bool = false
    private var transitionControllers: [AetherViewController] = []

    private struct PendingControllersUpdate {
        let controllers: [AetherViewController]
        let animated: Bool
    }

    private var pendingControllersUpdate: PendingControllersUpdate?
    private var isDeferringPendingControllersUpdate: Bool = false

    /// True during the narrow window inside `performTransition` between
    /// `addSubview(to.view)` and assigning `self.transitionCoordinator`.
    /// UIKit fires `viewWillAppear` on the incoming controller synchronously
    /// from `addSubview`, which in our base `ViewController` triggers
    /// `bar.requestContainerLayout?(.immediate)` → `AetherNavigationController.
    /// requestLayout` → reentrant `setControllers` on this container.
    /// Without this flag, that reentry sees `transitionCoordinator == nil`
    /// and takes the non-animated path, which evicts the outgoing
    /// controller's view from the hierarchy — leaving the outgoing screen
    /// blank at animation start. Treat this flag as "coordinator is about
    /// to be installed, stay out."
    private(set) var isInstallingTransition: Bool = false

    private var isTransitionActive: Bool {
        return transitionCoordinator != nil || customTransition != nil || isInstallingTransition || isDeferringPendingControllersUpdate
    }

    var isTransitioning: Bool {
        isTransitionActive
    }

    /// A controller-rendered transition owns the motion of its chrome too;
    /// navigation bar observers skip their own title morphs for it.
    var isCustomTransitionActive: Bool {
        customTransition != nil
    }

    public var topController: AetherViewController? {
        return controllers.last
    }

    private var validLayout: ContainerViewLayout?
    private var interactiveGestureRecognizer: InteractiveTransitionGestureRecognizer?

    public var isReady: Bool = true
    public var readyChanged: (() -> Void)?

    public var controllerRemoved: ((AetherViewController) -> Void)?
    var controllerRemovalCommitted: ((AetherViewController) -> Void)?
    public var requestLayout: ((ContainedViewLayoutTransition) -> Void)?
    var navigationBarTransitionBegan: ((NavigationTransitionDirection, AetherViewController, AetherViewController, ContainerViewLayout, Bool) -> Void)?
    var navigationBarTransitionProgress: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    var navigationBarTransitionResolutionBegan: ((Bool, ContainedViewLayoutTransition) -> Void)?
    var navigationBarTransitionEnded: ((Bool) -> Void)?
    var bottomBarTransitionBegan: ((NavigationTransitionDirection, AetherViewController, AetherViewController, ContainerViewLayout, Bool) -> Void)?
    var bottomBarTransitionProgress: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    var bottomBarTransitionResolutionBegan: ((Bool, ContainedViewLayoutTransition) -> Void)?
    var bottomBarTransitionEnded: ((Bool) -> Void)?
    /// Runs after both end observers have seen the settled hierarchy. Queued
    /// routing must wait until this point so an old transition cannot tear
    /// down views belonging to the next one.
    var transitionDidSettle: (() -> Void)?
    var layoutForController: ((AetherViewController, ContainerViewLayout) -> ContainerViewLayout)?

    /// Radius of the moving page, supplied by the containing surface.
    /// Embedded navigation never assumes the physical display's geometry.
    public var transitionCornerRadius: CGFloat = 0 {
        didSet {
            transitionCoordinator?.updateCornerRadii(top: transitionCornerRadius, bottom: transitionBottomCornerRadius)
        }
    }

    public var transitionBottomCornerRadius: CGFloat? {
        didSet {
            transitionCoordinator?.updateCornerRadii(top: transitionCornerRadius, bottom: transitionBottomCornerRadius)
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.clipsToBounds = true

        let panRecognizer = InteractiveTransitionGestureRecognizer(
            target: self,
            action: #selector(panGesture(_:)),
            allowedDirections: { [weak self] point in
                return self?.interactivePopGestureDirections(at: point) ?? []
            },
            edgeWidth: .constant(20.0)
        )
        panRecognizer.edgeWidthOverride = { [weak self] in
            self?.controllers.last?.interactiveNavivationGestureEdgeWidth
        }
        panRecognizer.delegate = self
        addGestureRecognizer(panRecognizer)
        self.interactiveGestureRecognizer = panRecognizer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Controller Management

    public func setControllers(_ controllers: [AetherViewController], animated: Bool) {
        let dedupedControllers = deduplicatedControllers(controllers)

        let previousControllers = self.controllers
        let previousTopController = self.controllers.last
        let newTopController = dedupedControllers.last

        // If a transition is already in flight (e.g. an interactive pop
        // gesture), the coordinator owns the frames of top/bottom views.
        // Running updateControllerViews here would reset the top view's
        // frame to (0,0,w,h) via transition.updateFrame, stomping on the
        // gesture's in-progress frame. The follow-up containerLayoutUpdated
        // call (from the same updateRootContainer site) already takes the
        // transition-aware path and forwards layout per-controller.
        //
        // Also bail when `isInstallingTransition` is set: we're in the
        // narrow window of `performTransition` where `addSubview(to.view)`
        // has fired `viewWillAppear` on the incoming controller, which
        // cascades back into this method before the coordinator has been
        // assigned. See the flag's declaration for the full story.
        if isTransitionActive {
            // Layout refreshes repeat the current committed stack. Recording
            // that echo as a pending update would resurrect the popped page
            // after an interactive transition removes it.
            guard !controllersAreEqual(self.controllers, dedupedControllers) else { return }
            let shouldKeepAnimatedPendingUpdate: Bool
            if let pending = pendingControllersUpdate, pending.animated, controllersAreEqual(pending.controllers, dedupedControllers) {
                shouldKeepAnimatedPendingUpdate = true
            } else {
                shouldKeepAnimatedPendingUpdate = false
            }
            pendingControllersUpdate = PendingControllersUpdate(
                controllers: dedupedControllers,
                animated: animated || shouldKeepAnimatedPendingUpdate
            )
            return
        }

        pendingControllersUpdate = nil
        self.controllers = dedupedControllers

        if let layout = validLayout {
            if animated, let previousTop = previousTopController, let newTop = newTopController, previousTop !== newTop {
                let isPush = dedupedControllers.count >= previousControllers.count
                performTransition(from: previousTop, to: newTop, push: isPush, layout: layout)
            } else {
                updateControllerViews(
                    layout: layout,
                    transition: animated
                        ? .animated(duration: AetherMotion.navigation.duration, curve: .easeInOut)
                        : .immediate
                )
            }
        }
    }

    private func deduplicatedControllers(_ controllers: [AetherViewController]) -> [AetherViewController] {
        var dedupedControllers: [AetherViewController] = []
        dedupedControllers.reserveCapacity(controllers.count)
        for controller in controllers where !dedupedControllers.contains(where: { $0 === controller }) {
            dedupedControllers.append(controller)
        }
        return dedupedControllers
    }

    private func controllersAreEqual(_ lhs: [AetherViewController], _ rhs: [AetherViewController]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        for (left, right) in zip(lhs, rhs) where left !== right {
            return false
        }
        return true
    }

    private func resolvedLayout(for controller: AetherViewController, baseLayout: ContainerViewLayout) -> ContainerViewLayout {
        return layoutForController?(controller, baseLayout) ?? baseLayout
    }

    private func applyPendingControllersUpdateIfPossible(deferred: Bool = false, completion: (() -> Void)? = nil) {
        guard !isTransitionActive, let pending = pendingControllersUpdate else {
            completion?()
            return
        }

        pendingControllersUpdate = nil
        guard !controllersAreEqual(controllers, pending.controllers) else {
            completion?()
            return
        }

        let applyUpdate: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.isDeferringPendingControllersUpdate = false
            self.setControllers(pending.controllers, animated: pending.animated)
            completion?()
        }

        if deferred && pending.animated {
            isDeferringPendingControllersUpdate = true
            DispatchQueue.main.async(execute: applyUpdate)
        } else {
            applyUpdate()
        }
    }

    public func pushController(_ controller: AetherViewController, animated: Bool) {
        var controllers = self.controllers
        controllers.append(controller)
        setControllers(controllers, animated: animated)
    }

    public func popController(animated: Bool) -> AetherViewController? {
        guard controllers.count > 1 else { return nil }
        var updatedControllers = controllers
        let removedController = updatedControllers.removeLast()
        setControllers(updatedControllers, animated: animated)
        return removedController
    }

    // MARK: - Layout

    public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout

        if !isTransitionActive {
            updateControllerViews(layout: layout, transition: transition)
        } else {
            // A push/pop animation is in flight — the coordinator owns
            // child view frames so we mustn't touch them, but we DO need
            // to forward the layout to every currently-hosted controller
            // so they can react to changes in ancestors (e.g. the outer
            // nav bar growing back to include the filter bar on pop,
            // which changes the `additionalInsets.top` the root should
            // use for its contentInset). Without this propagation, the
            // "to" controller's contentInset stays stuck at whatever it
            // was when the animation started — the exact "scroll
            // contentInset wrong after pop" bug.
            var updated = Set<ObjectIdentifier>()
            for controller in controllers + transitionControllers where controller.isViewLoaded && updated.insert(ObjectIdentifier(controller)).inserted {
                controller.containerLayoutUpdated(resolvedLayout(for: controller, baseLayout: layout), transition: transition)
            }
            transitionCoordinator?.updateLayout()
        }
    }

    private func updateControllerViews(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let topController = controllers.last
        for view in controllerViews where view !== topController?.viewIfLoaded {
            view.removeFromSuperview()
        }
        controllerViews.removeAll()
        guard let topController else { return }

        if topController.view.superview !== self {
            addSubview(topController.view)
        }
        controllerViews = [topController.view]

        let frame = CGRect(origin: .zero, size: layout.size)
        transition.updateFrame(view: topController.view, frame: frame)
        topController.containerLayoutUpdated(resolvedLayout(for: topController, baseLayout: layout), transition: transition)
    }

    // MARK: - Transitions

    private func performTransition(from: AetherViewController, to: AetherViewController, push: Bool, layout: ContainerViewLayout) {
        let frame = CGRect(origin: .zero, size: layout.size)

        let owner = push ? to : from
        if let custom = owner.customNavigationTransition(
            for: push ? .push : .pop,
            from: from,
            to: to,
            isInteractive: false
        ) {
            performCustomTransition(custom, from: from, to: to, push: push, layout: layout)
            return
        }

        // Mark the transition as "being installed" BEFORE any call that
        // could reach the view hierarchy for `to` (including
        // `to.containerLayoutUpdated` which lays out the bar, and
        // `addSubview` which fires UIKit's appearance transitions). Both
        // can cause `viewWillAppear` → `bar.requestContainerLayout` →
        // `requestLayout` reentry into this container before the
        // coordinator reference is assigned.
        isInstallingTransition = true
        transitionControllers = [from, to]
        controllerViews = [from.view, to.view]
        to.view.frame = frame
        bottomBarTransitionBegan?(push ? .push : .pop, from, to, layout, false)
        to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

        if push {
            to.view.frame = frame.offsetBy(dx: frame.width, dy: 0)
            navigationBarTransitionBegan?(.push, from, to, layout, false)
            addSubview(to.view)
            to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .push,
                topView: to.view,
                bottomView: from.view,
                topBar: nil,
                bottomBar: nil,
                isInteractive: false,
                screenCornerRadius: transitionCornerRadius,
                bottomCornerRadius: transitionBottomCornerRadius,
                progressUpdated: { [weak self] progress, transition in
                    self?.navigationBarTransitionProgress?(progress, transition)
                    self?.bottomBarTransitionProgress?(progress, transition)
                }
            )
            self.transitionCoordinator = coordinator
            isInstallingTransition = false

            coordinator.animateCompletion { [weak self] in
                guard let self = self else { return }
                from.view.removeFromSuperview()
                self.finishTransition(completed: true)
            }
        } else {
            navigationBarTransitionBegan?(.pop, from, to, layout, false)
            insertSubview(to.view, belowSubview: from.view)
            to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .pop,
                topView: from.view,
                bottomView: to.view,
                topBar: nil,
                bottomBar: nil,
                isInteractive: false,
                screenCornerRadius: transitionCornerRadius,
                bottomCornerRadius: transitionBottomCornerRadius,
                progressUpdated: { [weak self] progress, transition in
                    self?.navigationBarTransitionProgress?(progress, transition)
                    self?.bottomBarTransitionProgress?(progress, transition)
                }
            )
            self.transitionCoordinator = coordinator
            isInstallingTransition = false

            coordinator.animateCompletion { [weak self] in
                guard let self = self else { return }
                from.view.removeFromSuperview()
                self.finishTransition(completed: true, removedController: from)
            }
        }
    }

    private func finishTransition(completed: Bool, removedController: AetherViewController? = nil) {
        let endedCustomTransition = customTransition
        transitionCoordinator = nil
        customTransition = nil
        isResolvingCustomTransition = false
        isCustomTransitionInteractive = false
        transitionControllers.removeAll()
        controllerViews = controllers.last.map { [$0.view!] } ?? []
        navigationBarTransitionEnded?(completed)
        if let removedController {
            controllerRemoved?(removedController)
        }
        bottomBarTransitionEnded?(completed)
        endedCustomTransition?.didEnd(completed: completed)
        transitionDidSettle?()
        applyPendingControllersUpdateIfPossible(deferred: true)
    }

    // MARK: - Custom Transitions

    /// Installs both views at their settled frames and hands the motion to a
    /// controller-provided transition. Navigation bar and bottom bar
    /// observers receive the same lifecycle as the default slide.
    private func performCustomTransition(
        _ custom: AetherCustomNavigationTransition,
        from: AetherViewController,
        to: AetherViewController,
        push: Bool,
        layout: ContainerViewLayout
    ) {
        let frame = CGRect(origin: .zero, size: layout.size)

        isInstallingTransition = true
        customTransition = custom
        isCustomTransitionInteractive = false
        transitionControllers = [from, to]
        controllerViews = [from.view, to.view]
        to.view.frame = frame
        bottomBarTransitionBegan?(push ? .push : .pop, from, to, layout, false)
        to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

        navigationBarTransitionBegan?(push ? .push : .pop, from, to, layout, false)
        if push {
            addSubview(to.view)
        } else {
            insertSubview(to.view, belowSubview: from.view)
        }
        to.view.frame = frame
        to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

        isInstallingTransition = false

        custom.prepare(context: AetherNavigationTransitionContext(
            operation: push ? .push : .pop,
            containerView: self,
            fromController: from,
            toController: to,
            isInteractive: false
        ))
        navigationBarTransitionProgress?(0.0, .immediate)
        bottomBarTransitionProgress?(0.0, .immediate)

        custom.animate { [weak self] in
            guard let self, self.customTransition === custom else { return }
            self.navigationBarTransitionProgress?(1.0, .immediate)
            self.bottomBarTransitionProgress?(1.0, .immediate)
            from.view.removeFromSuperview()
            self.finishTransition(completed: true, removedController: push ? nil : from)
        }
    }

    /// Starts an interactive pop rendered by the popped controller. Returns
    /// `false` when the controller keeps the default slide.
    private func beginInteractiveCustomPop(
        currentController: AetherViewController,
        previousController: AetherViewController,
        layout: ContainerViewLayout,
        translation: CGPoint,
        location: CGPoint
    ) -> Bool {
        guard let custom = currentController.customNavigationTransition(
            for: .pop,
            from: currentController,
            to: previousController,
            isInteractive: true
        ) else {
            return false
        }

        let frame = CGRect(origin: .zero, size: layout.size)
        isInstallingTransition = true
        customTransition = custom
        isCustomTransitionInteractive = true
        transitionControllers = [currentController, previousController]
        controllerViews = [currentController.view, previousController.view]
        previousController.view.frame = frame
        previousController.containerLayoutUpdated(resolvedLayout(for: previousController, baseLayout: layout), transition: .immediate)
        navigationBarTransitionBegan?(.pop, currentController, previousController, layout, true)
        bottomBarTransitionBegan?(.pop, currentController, previousController, layout, true)
        insertSubview(previousController.view, belowSubview: currentController.view)
        previousController.view.frame = frame
        previousController.containerLayoutUpdated(resolvedLayout(for: previousController, baseLayout: layout), transition: .immediate)

        isResolvingCustomTransition = false
        isInstallingTransition = false

        custom.prepare(context: AetherNavigationTransitionContext(
            operation: .pop,
            containerView: self,
            fromController: currentController,
            toController: previousController,
            isInteractive: true
        ))
        custom.updateInteractive(translation: translation, location: location)
        currentController.view.endEditing(true)
        return true
    }

    private func resolveInteractiveCustomPop(
        _ custom: AetherCustomNavigationTransition,
        recognizer: UIPanGestureRecognizer
    ) {
        guard !isResolvingCustomTransition else { return }
        isResolvingCustomTransition = true

        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        let shouldComplete = recognizer.state == .ended
            && custom.shouldCompleteInteractive(translation: translation, velocity: velocity)
        let chromeTransition: ContainedViewLayoutTransition = .animated(
            duration: AetherMotion.navigation.duration,
            curve: .easeInOut
        )

        if shouldComplete {
            let committedController = controllers.last!
            custom.finishInteractive(velocity: velocity) { [weak self] in
                guard let self, self.customTransition === custom else { return }
                let removed = self.controllers.removeLast()
                removed.view.removeFromSuperview()
                self.finishTransition(completed: true, removedController: removed)
            }
            navigationBarTransitionResolutionBegan?(true, chromeTransition)
            bottomBarTransitionResolutionBegan?(true, chromeTransition)
            controllerRemovalCommitted?(committedController)
        } else {
            custom.cancelInteractive(velocity: velocity) { [weak self] in
                guard let self, self.customTransition === custom else { return }
                let previousController = self.controllers[self.controllers.count - 2]
                previousController.view.removeFromSuperview()
                self.finishTransition(completed: false)
            }
            navigationBarTransitionResolutionBegan?(false, chromeTransition)
            bottomBarTransitionResolutionBegan?(false, chromeTransition)
        }
    }

    // MARK: - Interactive Gesture

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        guard controllers.count > 1 else { return }

        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        let width = max(1.0, bounds.width)

        // Map raw pan translation to transition progress with iOS-style
        // rubberband resistance for out-of-range pulls. Inside [0, width] it's
        // a 1:1 linear mapping; outside, the standard UIScrollView damping
        // formula `(1 - 1/(x*c/d + 1)) * d` returns a logarithmically-
        // attenuated effective offset, so the user feels a soft, decelerating
        // pull instead of a hard wall — matching iOS 26 nav-stack feel where
        // dragging the popping screen *back past its origin* (or *past full
        // completion*) tugs with resistance.
        //
        // Match UIScrollView's stock rubber-band constant. The previous 0.32
        // made edge overpull feel too heavy and removed the visible overpop
        // when the user throws the screen away with a fast back gesture.
        let rubberbandC: CGFloat = 0.55
        let progress: CGFloat
        if translation.x < 0 {
            // Backward overscroll — user is dragging the popping screen LEFT
            // past its starting position. Rubberband the negative side.
            let overshoot = -translation.x
            let damped = (1.0 - 1.0 / (overshoot * rubberbandC / width + 1.0)) * width
            progress = -damped / width
        } else if translation.x > width {
            // Forward overscroll past completion. Rare but possible on slow
            // drags after the threshold; same damping.
            let overshoot = translation.x - width
            let damped = (1.0 - 1.0 / (overshoot * rubberbandC / width + 1.0)) * width
            progress = (width + damped) / width
        } else {
            progress = translation.x / width
        }

        switch recognizer.state {
        case .began:
            // Don't spawn the pop coordinator yet. Wait for the first .changed
            // with translation.x > 0 — that's the user actually moving the
            // screen to the right (the pop intent). Spawning on .began would
            // engage the backward-rubberband path even for a stray left-going
            // pan from the screen edge, which is not a pop gesture at all
            // (just an idle drag) and shouldn't visibly tug the screen left.
            break

        case .changed:
            if let custom = customTransition {
                if isCustomTransitionInteractive, !isResolvingCustomTransition {
                    custom.updateInteractive(translation: translation, location: recognizer.location(in: self))
                }
            } else if let coordinator = transitionCoordinator, !coordinator.animatingCompletion {
                // Coordinator already exists — user has started a pop and is
                // now in the middle of it. The page follows the (possibly
                // rubberbanded) finger progress through the tracking spring,
                // including negative values for backward overscroll.
                coordinator.trackInteractiveProgress(progress)
            } else if transitionCoordinator == nil, translation.x > 0, let layout = validLayout {
                // First *rightward* movement — spawn the pop coordinator now
                // and immediately apply the current progress. Anything before
                // this point (idle .began, leftward .changed before any
                // rightward intent) is ignored.
                let currentController = controllers.last!
                let previousController = controllers[controllers.count - 2]
                guard currentController.attemptNavigation({}) else {
                    (recognizer as? InteractiveTransitionGestureRecognizer)?.cancel()
                    return
                }

                if beginInteractiveCustomPop(
                    currentController: currentController,
                    previousController: previousController,
                    layout: layout,
                    translation: translation,
                    location: recognizer.location(in: self)
                ) {
                    return
                }

                isInstallingTransition = true
                transitionControllers = [currentController, previousController]
                controllerViews = [currentController.view, previousController.view]
                previousController.view.frame = CGRect(origin: .zero, size: layout.size)
                previousController.containerLayoutUpdated(resolvedLayout(for: previousController, baseLayout: layout), transition: .immediate)
                navigationBarTransitionBegan?(.pop, currentController, previousController, layout, true)
                bottomBarTransitionBegan?(.pop, currentController, previousController, layout, true)
                insertSubview(previousController.view, belowSubview: currentController.view)
                previousController.containerLayoutUpdated(resolvedLayout(for: previousController, baseLayout: layout), transition: .immediate)

                let coordinator = NavigationTransitionCoordinator(
                    container: self,
                    direction: .pop,
                    topView: currentController.view,
                    bottomView: previousController.view,
                    topBar: nil,
                    bottomBar: nil,
                    isInteractive: true,
                    screenCornerRadius: transitionCornerRadius,
                    bottomCornerRadius: transitionBottomCornerRadius,
                    progressUpdated: { [weak self] progress, transition in
                        self?.navigationBarTransitionProgress?(progress, transition)
                        self?.bottomBarTransitionProgress?(progress, transition)
                    }
                )
                self.transitionCoordinator = coordinator
                isInstallingTransition = false
                coordinator.trackInteractiveProgress(progress)

                // Dismiss the keyboard along with the outgoing view. Done *after*
                // the coordinator is installed so the keyboard's synchronous
                // layout cascade hits the transition-aware branch of
                // containerLayoutUpdated rather than stomping the interactive
                // frames.
                currentController.view.endEditing(true)
            }
            // else: pre-coordinator state, translation still <= 0 — no-op.

        case .ended, .cancelled:
            if let custom = customTransition {
                if isCustomTransitionInteractive {
                    resolveInteractiveCustomPop(custom, recognizer: recognizer)
                }
                break
            }
            guard let coordinator = transitionCoordinator, !coordinator.animatingCompletion else {
                break
            }
            let shouldComplete = recognizer.state == .ended && coordinator.shouldCompleteInteractivePop(progress: progress, velocity: velocity.x)
            if shouldComplete {
                let committedController = controllers.last!
                let completionTransition = coordinator.completionTransition(velocity: velocity.x)
                coordinator.animateCompletion(velocity: velocity.x) { [weak self] in
                    guard let self = self else { return }
                    let removed = self.controllers.removeLast()
                    removed.view.removeFromSuperview()
                    self.finishTransition(completed: true, removedController: removed)
                }
                navigationBarTransitionResolutionBegan?(true, completionTransition)
                bottomBarTransitionResolutionBegan?(true, completionTransition)
                controllerRemovalCommitted?(committedController)
            } else {
                let cancelTransition = coordinator.cancelTransition(velocity: velocity.x)
                coordinator.animateCancel(velocity: velocity.x) { [weak self] in
                    guard let self = self else { return }
                    let previousController = self.controllers[self.controllers.count - 2]
                    previousController.view.removeFromSuperview()
                    self.finishTransition(completed: false)
                }
                navigationBarTransitionResolutionBegan?(false, cancelTransition)
                bottomBarTransitionResolutionBegan?(false, cancelTransition)
            }

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard controllers.count > 1, !isTransitionActive else {
            return false
        }
        guard let topController = controllers.last else {
            return false
        }
        if let edgeWidth = topController.interactiveNavivationGestureEdgeWidth?.effectiveWidth(for: bounds.width), edgeWidth <= 0.0 {
            return false
        }
        return true
    }

    func interactivePopGestureDirections(at point: CGPoint) -> InteractiveTransitionGestureRecognizerDirections {
        guard controllers.count > 1 else {
            return []
        }
        guard let topController = controllers.last else {
            return []
        }
        if let edgeWidth = topController.interactiveNavivationGestureEdgeWidth?.effectiveWidth(for: bounds.width), edgeWidth <= 0.0 {
            return []
        }
        return [.leftEdge, .right]
    }

    public func combinedSupportedOrientations(currentOrientationToLock: UIInterfaceOrientationMask) -> AetherViewController.SupportedOrientations {
        var result = AetherViewController.SupportedOrientations()
        for controller in controllers {
            result = result.intersection(controller.supportedOrientations)
        }
        return result
    }
}
