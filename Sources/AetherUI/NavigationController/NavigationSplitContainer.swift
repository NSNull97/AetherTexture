import UIKit
import AsyncDisplayKit

/// Scroll-to-top target for split container.
enum NavigationSplitContainerScrollToTop {
    case master
    case detail
}

/// Split view container for iPad-style master-detail navigation.
/// Replaces the original NavigationSplitContainer.
final class NavigationSplitContainer: UIView {
    private var theme: NavigationControllerTheme

    private let masterScrollToTopView: ScrollToTopView
    private let detailScrollToTopView: ScrollToTopView
    let masterContainer: NavigationContainer
    let detailContainer: NavigationContainer
    private let separatorNode: ASDisplayNode

    private(set) var masterControllers: [AetherViewController] = []
    private(set) var detailControllers: [AetherViewController] = []

    var isInFocus: Bool = false {
        didSet {
            if isInFocus != oldValue {
                masterContainer.topController?.isInFocus = isInFocus
                detailContainer.topController?.isInFocus = isInFocus
            }
        }
    }

    init(
        theme: NavigationControllerTheme,
        controllerRemoved: @escaping (AetherViewController) -> Void,
        controllerRemovalCommitted: @escaping (AetherViewController) -> Void,
        scrollToTop: @escaping (NavigationSplitContainerScrollToTop) -> Void
    ) {
        self.theme = theme

        self.masterScrollToTopView = ScrollToTopView(frame: .zero)
        self.masterScrollToTopView.action = { scrollToTop(.master) }

        self.detailScrollToTopView = ScrollToTopView(frame: .zero)
        self.detailScrollToTopView.action = { scrollToTop(.detail) }

        self.masterContainer = NavigationContainer(frame: .zero)
        self.masterContainer.clipsToBounds = true
        self.masterContainer.controllerRemoved = controllerRemoved
        self.masterContainer.controllerRemovalCommitted = controllerRemovalCommitted

        self.detailContainer = NavigationContainer(frame: .zero)
        self.detailContainer.clipsToBounds = true
        self.detailContainer.controllerRemoved = controllerRemoved
        self.detailContainer.controllerRemovalCommitted = controllerRemovalCommitted

        self.separatorNode = ASDisplayNode()
        self.separatorNode.backgroundColor = theme.navigationBar.separatorColor

        super.init(frame: .zero)

        addSubview(masterContainer)
        addSubview(detailContainer)
        addSubview(separatorNode.view)
        addSubview(masterScrollToTopView)
        addSubview(detailScrollToTopView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTheme(theme: NavigationControllerTheme) {
        self.theme = theme
        separatorNode.backgroundColor = theme.navigationBar.separatorColor
    }

    func update(layout: ContainerViewLayout, masterControllers: [AetherViewController], detailControllers: [AetherViewController], transition: ContainedViewLayoutTransition) {
        let masterWidth = min(max(320.0, floor(layout.size.width / 3.0)), floor(layout.size.width / 2.0))
        let detailWidth = layout.size.width - masterWidth

        masterScrollToTopView.frame = CGRect(x: 0, y: -1, width: masterWidth, height: 1)
        detailScrollToTopView.frame = CGRect(x: masterWidth, y: -1, width: detailWidth, height: 1)

        transition.updateFrame(view: masterContainer, frame: CGRect(x: 0, y: 0, width: masterWidth, height: layout.size.height))
        transition.updateFrame(view: detailContainer, frame: CGRect(x: masterWidth, y: 0, width: detailWidth, height: layout.size.height))
        let pixel = 1.0 / max(window?.screen.scale ?? traitCollection.displayScale, 1.0)
        transition.updateFrame(node: separatorNode, frame: CGRect(x: masterWidth, y: 0, width: pixel, height: layout.size.height))

        let masterLayout = ContainerViewLayout(
            size: CGSize(width: masterWidth, height: layout.size.height),
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: .zero,
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
        masterContainer.setControllers(masterControllers, animated: transition.isAnimated)
        masterContainer.containerLayoutUpdated(masterLayout, transition: transition)

        let detailLayout = ContainerViewLayout(
            size: CGSize(width: detailWidth, height: layout.size.height),
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: layout.additionalInsets,
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
        detailContainer.setControllers(detailControllers, animated: transition.isAnimated)
        detailContainer.containerLayoutUpdated(detailLayout, transition: transition)

        self.masterControllers = masterControllers
        self.detailControllers = detailControllers
    }

    func combinedSupportedOrientations(currentOrientationToLock: UIInterfaceOrientationMask) -> AetherViewController.SupportedOrientations {
        var result = AetherViewController.SupportedOrientations()
        result = result.intersection(masterContainer.combinedSupportedOrientations(currentOrientationToLock: currentOrientationToLock))
        result = result.intersection(detailContainer.combinedSupportedOrientations(currentOrientationToLock: currentOrientationToLock))
        return result
    }
}
