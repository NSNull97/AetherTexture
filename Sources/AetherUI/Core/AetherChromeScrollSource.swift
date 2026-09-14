import UIKit

/// The one active content source used by scroll-edge chrome and tab
/// reselection. Keeping this resolution in one place prevents a horizontal
/// pager or an attached neighbouring page from winning over the visible
/// vertical screen.
@MainActor
struct AetherChromeScrollSource {
    let owner: AnyObject
    let controllerPath: [UIViewController]
    let contentRootView: UIView?
    let scrollView: UIScrollView?
}

@MainActor
enum AetherChromeScrollSourceResolver {
    static let didChangeNotification = Notification.Name(
        "AetherUI.ChromeScrollSourceDidChange"
    )

    static func notifyDidChange(from owner: AnyObject) {
        NotificationCenter.default.post(
            name: didChangeNotification,
            object: owner
        )
    }

    static func resolve(from rootController: UIViewController?) -> AetherChromeScrollSource? {
        guard let rootController else { return nil }
        let path = activeControllerPath(from: rootController)
        guard let activeController = path.last else { return nil }

        let nodeContent = activeNodeContent(for: activeController)
        let contentRoot = nodeContent?.view ?? activeController.viewIfLoaded
        let explicitScroll = path.reversed().compactMap { controller in
            (controller as? AetherViewController)?.primaryScrollViewForChrome
        }.first
        let scrollView = explicitScroll ?? contentRoot.flatMap {
            primaryVerticalScrollView(in: $0)
        }

        return AetherChromeScrollSource(
            owner: nodeContent ?? activeController,
            controllerPath: path,
            contentRootView: contentRoot,
            scrollView: scrollView
        )
    }

    static func activeControllerPath(from rootController: UIViewController) -> [UIViewController] {
        var path: [UIViewController] = []
        var visited = Set<ObjectIdentifier>()
        var current: UIViewController? = rootController

        while let controller = current {
            let identifier = ObjectIdentifier(controller)
            guard visited.insert(identifier).inserted else { break }
            path.append(controller)
            current = activeChildController(of: controller)
        }
        return path
    }

    static func primaryVerticalScrollView(in rootView: UIView) -> UIScrollView? {
        struct Candidate {
            let scrollView: UIScrollView
            let depth: Int
            let visibleArea: CGFloat
            let isMoving: Bool
            let scrollsToTop: Bool
        }

        var queue: [(view: UIView, depth: Int, ancestorsVisible: Bool)] = [
            (rootView, 0, true)
        ]
        var candidates: [Candidate] = []

        while !queue.isEmpty {
            let entry = queue.removeFirst()
            let view = entry.view
            let visible = entry.ancestorsVisible
                && !view.isHidden
                && view.alpha > 0.01
            guard visible else { continue }

            if let scrollView = view as? UIScrollView,
               isEligibleVerticalScrollView(scrollView),
               isVisiblyIntersecting(scrollView, within: rootView) {
                let visibleRect = scrollView.convert(scrollView.bounds, to: rootView)
                    .intersection(rootView.bounds)
                candidates.append(
                    Candidate(
                        scrollView: scrollView,
                        depth: entry.depth,
                        visibleArea: max(0.0, visibleRect.width * visibleRect.height),
                        isMoving: scrollView.isTracking
                            || scrollView.isDragging
                            || scrollView.isDecelerating,
                        scrollsToTop: scrollView.scrollsToTop
                    )
                )
            }

            queue.append(contentsOf: view.subviews.map {
                ($0, entry.depth + 1, visible)
            })
        }

        return candidates.max { lhs, rhs in
            if lhs.isMoving != rhs.isMoving { return !lhs.isMoving }
            if lhs.scrollsToTop != rhs.scrollsToTop { return !lhs.scrollsToTop }
            if abs(lhs.visibleArea - rhs.visibleArea) > 0.5 {
                return lhs.visibleArea < rhs.visibleArea
            }
            return lhs.depth > rhs.depth
        }?.scrollView
    }

    private static func activeChildController(of controller: UIViewController) -> UIViewController? {
        if let presented = controller.presentedViewController,
           !presented.isBeingDismissed {
            return presented
        }
        if let modal = controller as? AetherModalNavigationController {
            return modal.internalNavigationController
        }
        if let modal = controller as? AetherModalNodeNavigationController {
            return modal.internalNavigationController
        }
        if let navigation = controller as? AetherNavigationController {
            return navigation.topController
        }
        if let navigation = controller as? UINavigationController {
            return navigation.visibleViewController ?? navigation.topViewController
        }
        if let tabs = controller as? AetherTabBarController {
            return tabs.currentController
        }
        if let tabs = controller as? UITabBarController {
            return tabs.selectedViewController
        }
        if let pages = controller as? AetherPageViewController {
            return pages.selectedPage?.viewController
        }
        if let pages = controller as? UIPageViewController {
            return mostVisibleController(
                among: pages.viewControllers ?? [],
                in: pages.viewIfLoaded
            )
        }
        if let split = controller as? UISplitViewController {
            return mostVisibleController(
                among: split.viewControllers,
                in: split.viewIfLoaded
            )
        }

        return mostVisibleController(
            among: controller.children,
            in: controller.viewIfLoaded
        )
    }

    private static func mostVisibleController(
        among controllers: [UIViewController],
        in containerView: UIView?
    ) -> UIViewController? {
        guard !controllers.isEmpty else { return nil }
        guard let containerView else {
            return controllers.last
        }

        return controllers.enumerated().compactMap { index, controller -> (
            controller: UIViewController,
            area: CGFloat,
            centerDistance: CGFloat,
            index: Int
        )? in
            guard controller.isViewLoaded,
                  let view = controller.viewIfLoaded,
                  view.superview != nil,
                  !view.isHidden,
                  view.alpha > 0.01 else {
                return nil
            }
            let rect = view.convert(view.bounds, to: containerView)
            let intersection = rect.intersection(containerView.bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            let area = max(0.0, intersection.width * intersection.height)
            let centerDistance = hypot(
                rect.midX - containerView.bounds.midX,
                rect.midY - containerView.bounds.midY
            )
            return (controller, area, centerDistance, index)
        }.max { lhs, rhs in
            if abs(lhs.area - rhs.area) > 0.5 { return lhs.area < rhs.area }
            if abs(lhs.centerDistance - rhs.centerDistance) > 0.5 {
                return lhs.centerDistance > rhs.centerDistance
            }
            return lhs.index < rhs.index
        }?.controller
    }

    private static func activeNodeContent(for controller: UIViewController) -> AetherScreenNode? {
        if let controller = controller as? AetherNodePageController,
           controller.pageContainerNode.pages.indices.contains(controller.selectedIndex) {
            return controller.pageContainerNode.pages[controller.selectedIndex].contentNode
        }
        if let controller = controller as? AetherNodeTabContainerController,
           controller.tabContainerNode.tabs.indices.contains(controller.selectedIndex) {
            return controller.tabContainerNode.tabs[controller.selectedIndex].contentNode
        }
        if let controller = controller as? AetherNodeNavigationController {
            return controller.navigationNode.topNode
        }
        if let controller = controller as? AetherScreenController {
            return controller.screenNode
        }
        return nil
    }

    private static func isEligibleVerticalScrollView(_ scrollView: UIScrollView) -> Bool {
        guard scrollView.isScrollEnabled else { return false }
        let inset = scrollView.adjustedContentInset
        let verticalRange = scrollView.contentSize.height
            + inset.top
            + inset.bottom
            - scrollView.bounds.height
        return verticalRange > 0.5
            || scrollView.alwaysBounceVertical
            || abs(scrollView.contentOffset.y + inset.top) > 0.5
    }

    private static func isVisiblyIntersecting(
        _ scrollView: UIScrollView,
        within rootView: UIView
    ) -> Bool {
        if scrollView === rootView { return true }
        let rect = scrollView.convert(scrollView.bounds, to: rootView)
        return !rect.intersection(rootView.bounds).isNull
            && !rect.intersection(rootView.bounds).isEmpty
    }
}

/// Passively watches UIKit containers that do not publish Aether's explicit
/// source-change notification. It never replaces a container delegate: KVO is
/// used for discrete navigation/tab mutations and the private paging scroll
/// view is observed only for its horizontal offset.
@MainActor
final class AetherChromeContainerSourceObserver {
    private final class WeakController {
        weak var value: UIViewController?

        init(_ value: UIViewController) {
            self.value = value
        }
    }

    private var observations: [NSKeyValueObservation] = []
    private var isChangeScheduled = false
    private let onChange: () -> Void
    private var polledContainers: [WeakController] = []
    private var lastPolledSignature: [ObjectIdentifier] = []
    private var pollTimer: Timer?

    init(
        controllerPath: [UIViewController],
        onChange: @escaping () -> Void
    ) {
        self.onChange = onChange

        var observed = Set<ObjectIdentifier>()
        for controller in controllerPath {
            guard observed.insert(ObjectIdentifier(controller)).inserted else {
                continue
            }

            if let navigation = controller as? UINavigationController {
                polledContainers.append(WeakController(navigation))
                observations.append(
                    navigation.observe(\.viewControllers, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor [weak self] in
                            self?.scheduleChangeFromObservation()
                        }
                    }
                )
                // `UINavigationController.viewControllers` is not reliably
                // KVO-emitting on every supported UIKit runtime. The public
                // navigation bar updates its item stack for the same
                // push/pop operations and gives us a second passive signal
                // without taking ownership of `navigation.delegate`.
                observations.append(
                    navigation.navigationBar.observe(\.items, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor [weak self] in
                            self?.scheduleChangeFromObservation()
                        }
                    }
                )
            }
            if let tabs = controller as? UITabBarController {
                polledContainers.append(WeakController(tabs))
                observations.append(
                    tabs.observe(\.selectedIndex, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor [weak self] in
                            self?.scheduleChangeFromObservation()
                        }
                    }
                )
            }
            if let pages = controller as? UIPageViewController {
                polledContainers.append(WeakController(pages))
                observations.append(
                    pages.observe(\.viewControllers, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor [weak self] in
                            self?.scheduleChangeFromObservation()
                        }
                    }
                )
                if let pagingScrollView = Self.pagingScrollView(in: pages.viewIfLoaded) {
                    observations.append(
                        pagingScrollView.observe(\.contentOffset, options: [.new]) {
                            [weak self] _, _ in
                            Task { @MainActor [weak self] in
                                self?.scheduleChangeFromObservation()
                            }
                        }
                    )
                }
            }
            if let split = controller as? UISplitViewController {
                polledContainers.append(WeakController(split))
                observations.append(
                    split.observe(\.viewControllers, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor [weak self] in
                            self?.scheduleChangeFromObservation()
                        }
                    }
                )
            }
        }

        if !polledContainers.isEmpty {
            lastPolledSignature = currentPolledSignature()
            let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) {
                [weak self] timer in
                guard self != nil else {
                    timer.invalidate()
                    return
                }
                Task { @MainActor [weak self] in
                    self?.pollContainerSelection()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    func invalidate() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        polledContainers.removeAll()
        isChangeScheduled = false
    }

    private func pollContainerSelection() {
        let signature = currentPolledSignature()
        guard signature != lastPolledSignature else { return }
        lastPolledSignature = signature
        scheduleChangeFromObservation()
    }

    private func currentPolledSignature() -> [ObjectIdentifier] {
        polledContainers.flatMap { reference -> [ObjectIdentifier] in
            guard let controller = reference.value else { return [] }
            var result = [ObjectIdentifier(controller)]
            if let navigation = controller as? UINavigationController {
                if let visible = navigation.visibleViewController
                    ?? navigation.topViewController {
                    result.append(ObjectIdentifier(visible))
                }
            } else if let tabs = controller as? UITabBarController {
                if let selected = tabs.selectedViewController {
                    result.append(ObjectIdentifier(selected))
                }
            } else if let pages = controller as? UIPageViewController {
                result.append(contentsOf: (pages.viewControllers ?? []).map(
                    ObjectIdentifier.init
                ))
            } else if let split = controller as? UISplitViewController {
                result.append(contentsOf: split.viewControllers.map(
                    ObjectIdentifier.init
                ))
            }
            return result
        }
    }

    private func scheduleChangeFromObservation() {
        guard !isChangeScheduled else { return }
        isChangeScheduled = true
        // Container setters often publish KVO before the destination view is
        // mounted. Resolve on the next main-loop turn so the source is stable.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isChangeScheduled = false
            self.onChange()
        }
    }

    private static func pagingScrollView(in rootView: UIView?) -> UIScrollView? {
        guard let rootView else { return nil }
        var queue = [rootView]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? UIScrollView,
               scrollView.isPagingEnabled {
                return scrollView
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

@MainActor
enum AetherTabReselectionRouter {
    @discardableResult
    static func perform(from rootController: UIViewController?) -> Bool {
        guard let source = AetherChromeScrollSourceResolver.resolve(
            from: rootController
        ) else {
            return false
        }

        for controller in source.controllerPath.reversed() {
            if let modal = controller as? AetherModalNavigationController,
               modal.viewControllers.count > 1 {
                modal.popToRoot(animated: true)
                return true
            }
            if let modal = controller as? AetherModalNodeNavigationController,
               modal.nodes.count > 1 {
                modal.popToRoot(animated: true)
                return true
            }
            if let navigation = controller as? AetherNavigationController,
               navigation.viewControllerStack.count > 1 {
                navigation.popToRoot(animated: true)
                return true
            }
            if let navigation = controller as? UINavigationController,
               navigation.viewControllers.count > 1 {
                navigation.popToRootViewController(animated: true)
                return true
            }
            if let navigation = controller as? AetherNodeNavigationController,
               navigation.navigationNode.stack.count > 1,
               let root = navigation.navigationNode.stack.first {
                navigation.setStack([root], animated: true)
                return true
            }
        }

        for controller in source.controllerPath.reversed() {
            guard let controller = controller as? AetherViewController else {
                continue
            }
            if let action = controller.scrollToTopWithTabBar {
                action()
                return true
            }
            if let action = controller.scrollToTop {
                action()
                return true
            }
        }

        guard let scrollView = source.scrollView else { return false }
        let top = -scrollView.adjustedContentInset.top
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: top),
            animated: true
        )
        return true
    }
}
