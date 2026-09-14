import XCTest
import AsyncDisplayKit
@testable import AetherUI

final class AetherNodeArchitectureTests: XCTestCase {
    @MainActor
    func testChatBackgroundUsesTextureNodeAsPrimarySurface() {
        let node = ChatBackgroundNode(settings: .telegramClassic)
        node.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        node.view.layoutIfNeeded()

        XCTAssertEqual(node.frame.size, CGSize(width: 320, height: 480))
        XCTAssertTrue(node.subnodes?.isEmpty == false)
    }

    @MainActor
    func testChatBackgroundNodeRefreshesDynamicColorsWhenAppearanceChanges() {
        let dynamicBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
        let node = ChatBackgroundNode(settings: .init(content: .color(dynamicBackground)))
        let hostController = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = hostController
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()

        node.frame = hostController.view.bounds
        hostController.view.addSubview(node.view)
        hostController.view.layoutIfNeeded()
        node.view.layoutIfNeeded()

        XCTAssertFalse(node.contentStats.isDark)

        window.overrideUserInterfaceStyle = .dark
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostController.view.layoutIfNeeded()
        node.view.layoutIfNeeded()

        XCTAssertTrue(node.contentStats.isDark)
        window.isHidden = true
    }

    @MainActor
    func testRadialGradientUsesExplicitAppearanceWithoutOneStepLag() {
        let dynamicBase = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
        let gradient = ChatBackgroundSettings.RadialGradient(
            baseColor: dynamicBase,
            fields: []
        )
        let node = AetherMultiRadialGradientNode()
        node.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        _ = node.view

        node.configure(gradient, traits: UITraitCollection(userInterfaceStyle: .light))
        node.view.layoutIfNeeded()
        let lightPixels = renderedPixels(of: node)

        node.configure(gradient, traits: UITraitCollection(userInterfaceStyle: .dark))
        node.view.layoutIfNeeded()
        let darkPixels = renderedPixels(of: node)

        node.configure(gradient, traits: UITraitCollection(userInterfaceStyle: .light))
        node.view.layoutIfNeeded()
        let lightPixelsAgain = renderedPixels(of: node)

        XCTAssertNotEqual(lightPixels, darkPixels)
        XCTAssertEqual(lightPixels, lightPixelsAgain)
    }

    func testImmediateAnimationAppliesChangesAndCompletionSynchronously() {
        var didApplyChanges = false
        var completionValue: Bool?

        AetherAnimationEngine().animate(.immediate) {
            didApplyChanges = true
        } completion: { finished in
            completionValue = finished
        }

        XCTAssertTrue(didApplyChanges)
        XCTAssertEqual(completionValue, true)
    }

    private func renderedPixels(of node: ASDisplayNode) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: node.bounds.size,
            format: format
        ).image { output in
            node.view.layer.render(in: output.cgContext)
        }.pngData()
    }

    func testInteractiveTransitionClampsProgressAndCompletes() {
        var observedProgress: [CGFloat] = []
        var completionValue: Bool?
        let transition = AetherInteractiveTransition(
            animation: .immediate,
            applyProgress: { observedProgress.append($0) },
            completion: { completionValue = $0 }
        )

        transition.update(progress: -0.5)
        transition.update(progress: 0.4)
        transition.update(progress: 1.5)
        transition.cancel()
        transition.finish()

        XCTAssertEqual(observedProgress, [0.0, 0.4, 1.0, 0.0, 1.0])
        XCTAssertEqual(completionValue, true)
        XCTAssertEqual(transition.progress, 1.0)
    }

    func testNavigationNodeMaintainsTextureScreenStack() {
        let navigationNode = AetherNavigationNode()
        let first = TrackingScreenNode()
        let second = TrackingScreenNode()

        navigationNode.push(first, animated: false)
        navigationNode.push(second, animated: false)
        let popped = navigationNode.pop(animated: false)

        XCTAssertTrue(popped === second)
        XCTAssertEqual(navigationNode.stack.count, 1)
        XCTAssertTrue(navigationNode.topNode === first)
        XCTAssertEqual(first.events, ["willAppear", "didAppear", "willDisappear", "didDisappear", "willAppear", "didAppear"])
        XCTAssertEqual(second.events, ["willAppear", "didAppear", "willDisappear", "didDisappear"])
    }

    func testTabContainerSwitchesTextureScreens() {
        let first = AetherTabItemNode(
            contentNode: TrackingScreenNode(),
            barItemNode: AetherTabBarItemNode(title: "First")
        )
        let second = AetherTabItemNode(
            contentNode: TrackingScreenNode(),
            barItemNode: AetherTabBarItemNode(title: "Second")
        )
        let tabContainer = AetherTabContainerNode(tabs: [first, second], selectedIndex: 0)

        XCTAssertEqual(tabContainer.selectedIndex, 0)
        XCTAssertTrue(first.barItemNode.isSelected)
        XCTAssertFalse(second.barItemNode.isSelected)

        tabContainer.selectTab(at: 1, animated: false)

        XCTAssertEqual(tabContainer.selectedIndex, 1)
        XCTAssertFalse(first.barItemNode.isSelected)
        XCTAssertTrue(second.barItemNode.isSelected)
    }

    func testTabContainerReloadsTabsWithScreenLifecycle() {
        let firstScreen = TrackingScreenNode()
        let secondScreen = TrackingScreenNode()
        let first = AetherTabItemNode(
            contentNode: firstScreen,
            barItemNode: AetherTabBarItemNode(title: "First")
        )
        let second = AetherTabItemNode(
            contentNode: secondScreen,
            barItemNode: AetherTabBarItemNode(title: "Second")
        )
        let tabContainer = AetherTabContainerNode(tabs: [first], selectedIndex: 0)

        tabContainer.tabs = [second]

        XCTAssertEqual(firstScreen.events, ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        XCTAssertEqual(secondScreen.events, ["willAppear", "didAppear"])
        XCTAssertEqual(tabContainer.selectedIndex, 0)
    }

    func testPageContainerSwitchesTextureScreens() {
        let firstScreen = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "First Page"))
        let secondScreen = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Second Page"))
        let first = AetherPageItemNode(title: "First", contentNode: firstScreen)
        let second = AetherPageItemNode(title: "Second", contentNode: secondScreen)
        let pageContainer = AetherPageContainerNode(pages: [first, second], selectedIndex: 0)
        pageContainer.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        pageContainer.view.frame = pageContainer.frame
        pageContainer.view.layoutIfNeeded()

        pageContainer.selectPage(at: 1, animated: false)

        XCTAssertEqual(pageContainer.selectedIndex, 1)
        XCTAssertEqual(secondScreen.events, ["willAppear", "didAppear"])
    }

    func testNavigationBarNodeHostsLegacyAnimationSurfaceBehindNodeAPI() {
        let itemNode = AetherNavigationItemNode(title: "Title")
        let barNode = AetherNavigationBarNode(itemNode: itemNode)
        barNode.frame = CGRect(x: 0, y: 0, width: 320, height: 88)
        barNode.view.frame = barNode.frame
        barNode.view.layoutIfNeeded()

        itemNode.title = "Updated"

        XCTAssertFalse(String(describing: barNode.animationIdentity.rawValue).isEmpty)
        XCTAssertTrue(barNode.subnodes?.isEmpty == false)
    }

    func testSegmentedControlNodeUsesTextureSelectionState() {
        let segmentedNode = AetherSegmentedControlNode(
            items: [
                AetherSegmentedControl.Item(title: "One"),
                AetherSegmentedControl.Item(title: "Two", badgeValue: "3")
            ],
            selectedIndex: 0
        )

        segmentedNode.setSelectedIndex(1, animated: false)

        XCTAssertEqual(segmentedNode.selectedIndex, 1)
    }

    @MainActor
    func testAetherViewControllerHostsTextureRootContentNode() {
        let controller = AetherViewController()
        let contentNode = ASDisplayNode()

        controller.contentNode = contentNode
        controller.loadViewIfNeeded()
        controller.containerLayoutUpdated(
            ContainerViewLayout(size: CGSize(width: 320, height: 480), safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )

        XCTAssertTrue(controller.contentNode === contentNode)
        XCTAssertTrue(contentNode.view.superview === controller.view)
        XCTAssertEqual(contentNode.frame.size, CGSize(width: 320, height: 480))
        XCTAssertEqual(controller.view.subviews.first, contentNode.view)
    }

    @MainActor
    func testScreenControllerHostsTextureScreenNodeAtUIKitBoundary() {
        let screenNode = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Node Screen"))
        let controller = AetherScreenController(screenNode: screenNode)
        controller.loadViewIfNeeded()
        controller.containerLayoutUpdated(
            ContainerViewLayout(size: CGSize(width: 320, height: 480), safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )

        XCTAssertTrue(controller.contentNode === screenNode)
        XCTAssertTrue(screenNode.view.superview === controller.view)
        XCTAssertEqual(controller.navigationItem.title, "Node Screen")
        XCTAssertEqual(screenNode.frame.size, CGSize(width: 320, height: 480))

        screenNode.navigationItemNode.title = "Updated Node Screen"
        XCTAssertEqual(controller.navigationItem.title, "Updated Node Screen")
        XCTAssertEqual(controller.navigationBarItem.title, "Updated Node Screen")

        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()

        XCTAssertEqual(screenNode.events, ["willAppear", "didAppear"])
    }

    @MainActor
    func testNodeNavigationControllerUsesScreenNodesAsStackEntries() {
        let first = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "First"))
        let second = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Second"))
        let controller = AetherNodeNavigationController(rootNode: first)
        controller.loadViewIfNeeded()

        controller.push(second, animated: false)
        second.navigationItemNode.title = "Second Updated"
        XCTAssertEqual(controller.navigationItem.title, "Second Updated")

        let popped = controller.popNode(animated: false)
        first.navigationItemNode.title = "First Updated"

        XCTAssertTrue(controller.contentNode === controller.navigationNode)
        XCTAssertTrue(controller.navigationNode.view.superview === controller.view)
        XCTAssertTrue(popped === second)
        XCTAssertTrue(controller.navigationNode.topNode === first)
        XCTAssertEqual(controller.navigationItem.title, "First Updated")
    }

    @MainActor
    func testNodeTabContainerControllerSelectsTextureTabs() {
        let first = AetherTabItemNode(
            contentNode: TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "One Screen")),
            barItemNode: AetherTabBarItemNode(title: "One")
        )
        let second = AetherTabItemNode(
            contentNode: TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Two Screen")),
            barItemNode: AetherTabBarItemNode(title: "Two")
        )
        let controller = AetherNodeTabContainerController(tabs: [first, second], selectedIndex: 0)
        controller.loadViewIfNeeded()

        controller.selectTab(at: 1, animated: false)
        second.contentNode.navigationItemNode.title = "Two Updated"

        XCTAssertTrue(controller.contentNode === controller.tabContainerNode)
        XCTAssertTrue(controller.tabContainerNode.view.superview === controller.view)
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertTrue(second.barItemNode.isSelected)
        XCTAssertEqual(controller.navigationItem.title, "Two Updated")
    }

    @MainActor
    func testNodePageControllerHostsTexturePages() {
        let first = AetherPageItemNode(
            title: "One",
            contentNode: TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "One Screen"))
        )
        let second = AetherPageItemNode(
            title: "Two",
            contentNode: TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Two Screen"))
        )
        let controller = AetherNodePageController(pages: [first, second], selectedIndex: 0)
        controller.loadViewIfNeeded()

        controller.selectPage(at: 1, animated: false)

        XCTAssertTrue(controller.contentNode === controller.pageContainerNode)
        XCTAssertTrue(controller.pageContainerNode.view.superview === controller.view)
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(controller.navigationItem.title, "Two Screen")
    }

    @MainActor
    func testLegacyControllersAcceptScreenNodesAtUIKitBoundary() {
        let first = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "First Node"))
        let second = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Second Node"))

        let page = AetherPageViewController.Page(screenNode: first)
        XCTAssertEqual(page.title, "First Node")
        XCTAssertTrue((page.viewController as? AetherScreenController)?.screenNode === first)

        let tabController = AetherTabBarController()
        tabController.setScreenNodes([first, second], selectedIndex: 1)
        XCTAssertEqual(tabController.controllers.count, 2)
        XCTAssertTrue((tabController.controllers[0] as? AetherScreenController)?.screenNode === first)
        XCTAssertTrue((tabController.controllers[1] as? AetherScreenController)?.screenNode === second)

        let navigationController = AetherNavigationController()
        navigationController.setScreenNodes([first], animated: false)
        navigationController.pushNode(second, animated: false)
        XCTAssertTrue((navigationController.topViewController as? AetherScreenController)?.screenNode === second)

        XCTAssertTrue((first.aetherWindowContentController as? AetherScreenController)?.screenNode === first)
    }

    @MainActor
    func testWindowExposesNodeFirstRootAndOverlayEntryPoints() {
        let window = AetherNativeWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let rootNode = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Root"))
        let overlayNode = TrackingScreenNode(navigationItemNode: AetherNavigationItemNode(title: "Overlay"))

        window.contentNode = rootNode
        let overlayController = window.presentInGlobalOverlay(overlayNode, animated: false)

        XCTAssertTrue(window.contentNode === rootNode)
        XCTAssertTrue(window.contentController is AetherScreenController)
        XCTAssertTrue(overlayController.screenNode === overlayNode)

        window.dismissGlobalOverlay(overlayNode, animated: false)
    }

    @MainActor
    func testContainedTransitionAcceptsNodeTargets() {
        let node = ASDisplayNode()
        ContainedViewLayoutTransition.immediate.updateFrame(
            node: node,
            frame: CGRect(x: 3, y: 4, width: 50, height: 60)
        )
        ContainedViewLayoutTransition.immediate.updateAlpha(node: node, alpha: 0.4)
        ContainedViewLayoutTransition.immediate.setScale(node: node, scale: 0.5)

        XCTAssertEqual(node.frame, CGRect(x: 3, y: 4, width: 50, height: 60))
        XCTAssertEqual(node.view.alpha, 0.4, accuracy: 0.001)
        XCTAssertEqual(node.view.transform.a, 0.5, accuracy: 0.001)
    }

    func testToolbarNodeUsesTextureControls() {
        var didTap = false
        let toolbarNode = AetherToolbarNode(
            toolbar: AetherToolbar(leftAction: AetherToolbarAction(title: "Done"))
        )
        toolbarNode.leftTapped = { didTap = true }
        toolbarNode.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        toolbarNode.view.frame = toolbarNode.frame
        toolbarNode.view.layoutIfNeeded()

        XCTAssertFalse(toolbarNode.subnodes?.isEmpty ?? true)
        XCTAssertEqual(AetherToolbarNode.preferredHeight(bottomSafeInset: 20), 64)
        toolbarNode.leftTapped()
        XCTAssertTrue(didTap)
    }

    func testStateNodesExposeContentUnavailableAndSkeletonAsTextureNodes() {
        var configuration = AetherContentUnavailableConfiguration.empty()
        configuration.text = "Empty"
        let contentNode = AetherContentUnavailableNode(configuration: configuration)
        contentNode.setConfiguration(nil, animated: false)

        let skeletonNode = AetherSkeletonNode(theme: .light, isAnimating: false)
        skeletonNode.isAnimating = true
        let skeletonHostView = AetherSkeletonBlockView(theme: .light)
        skeletonHostView.frame = CGRect(x: 0, y: 0, width: 120, height: 44)
        skeletonHostView.layoutIfNeeded()

        XCTAssertFalse(String(describing: contentNode.animationIdentity.rawValue).isEmpty)
        XCTAssertFalse(String(describing: skeletonNode.animationIdentity.rawValue).isEmpty)
        XCTAssertTrue(skeletonHostView.contentNode.view.superview === skeletonHostView)
    }

    func testContentUnavailableNodeDoesNotHostLegacyUIViewRenderer() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Node/AetherStateNodes.swift"))
        let contentStart = try XCTUnwrap(source.range(of: "public final class AetherContentUnavailableNode"))
        let skeletonStart = try XCTUnwrap(source.range(of: "open class AetherSkeletonNode", range: contentStart.upperBound..<source.endIndex))
        let contentNodeSource = source[contentStart.lowerBound..<skeletonStart.lowerBound]
        let viewSource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ContentState/AetherContentUnavailable.swift"))

        XCTAssertFalse(contentNodeSource.contains("viewBlock"))
        XCTAssertFalse(contentNodeSource.contains("AetherContentUnavailableView"))
        XCTAssertTrue(contentNodeSource.contains("ASImageNode"))
        XCTAssertTrue(contentNodeSource.contains("ASTextNode"))
        XCTAssertTrue(contentNodeSource.contains("AetherContentUnavailableButtonNode"))
        XCTAssertTrue(viewSource.contains("public let contentNode: AetherContentUnavailableNode"))
        XCTAssertFalse(viewSource.contains("UIImageView()"))
        XCTAssertFalse(viewSource.contains("UILabel()"))
        XCTAssertFalse(viewSource.contains("UIButton(type:"))
    }

    func testSkeletonNodeOwnsRendererWhileViewsOnlyHostNodes() throws {
        let stateNodeSource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Node/AetherStateNodes.swift"))
        let skeletonStart = try XCTUnwrap(stateNodeSource.range(of: "open class AetherSkeletonNode"))
        let skeletonSource = stateNodeSource[skeletonStart.lowerBound..<stateNodeSource.endIndex]
        let viewSource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Skeleton/AetherSkeletonView.swift"))

        XCTAssertFalse(skeletonSource.contains("viewBlock"))
        XCTAssertFalse(skeletonSource.contains("AetherSkeletonView"))
        XCTAssertTrue(skeletonSource.contains("CAGradientLayer"))
        XCTAssertTrue(skeletonSource.contains("AetherSkeletonLineNode"))
        XCTAssertTrue(skeletonSource.contains("AetherSkeletonBlockNode"))
        XCTAssertTrue(skeletonSource.contains("AetherSkeletonCircleNode"))
        XCTAssertTrue(viewSource.contains("public let contentNode: AetherSkeletonNode"))
        XCTAssertFalse(viewSource.contains("CAGradientLayer"))
    }

    func testOverlayContentRenderingUsesTextureNodes() throws {
        let files = [
            "Sources/AetherUI/ActionSheet/AetherActionSheetItem.swift",
            "Sources/AetherUI/ActionSheet/AetherActionSheetButtonItem.swift",
            "Sources/AetherUI/ActionSheet/AetherActionSheetTextItem.swift",
            "Sources/AetherUI/ActionSheet/AetherActionSheetCheckboxItem.swift",
            "Sources/AetherUI/Alert/AetherAlertController.swift",
            "Sources/AetherUI/Toast/AetherToastController.swift",
            "Sources/AetherUI/Tooltip/AetherTooltipController.swift"
        ]
        let source = try files.map {
            try String(contentsOf: sourceRoot().appendingPathComponent($0))
        }.joined(separator: "\n")
        let switchSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ActionSheet/AetherActionSheetSwitchItem.swift")
        )

        XCTAssertTrue(source.contains("ASTextNode"))
        XCTAssertTrue(source.contains("ASImageNode"))
        XCTAssertTrue(source.contains("ASControlNode"))
        XCTAssertFalse(source.contains("UILabel()"))
        XCTAssertFalse(source.contains("UIImageView()"))
        XCTAssertFalse(source.contains("UIButton("))
        XCTAssertTrue(switchSource.contains("UISwitch()"))
        XCTAssertTrue(switchSource.contains("ASDisplayNode(viewBlock:"))
    }

    func testContextAndAttachmentRowsRenderThroughTextureNodes() throws {
        let contextActionSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ContextMenu/ContextMenuActionItemView.swift")
        )
        let contextCellSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ContextMenu/ContextMenuActionRowCellView.swift")
        )
        let contextActionsSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ContextMenu/ContextMenuActionsView.swift")
        )
        let attachmentSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/AttachmentMenu/AetherSourceMorphController.swift")
        )
        let attachmentStart = try XCTUnwrap(attachmentSource.range(of: "private final class AttachmentMenuRowView"))
        let attachmentRowSource = attachmentSource[attachmentStart.lowerBound..<attachmentSource.endIndex]

        for source in [contextActionSource, contextCellSource, String(attachmentRowSource)] {
            XCTAssertTrue(source.contains("ASTextNode"))
            XCTAssertTrue(source.contains("ASImageNode"))
            XCTAssertFalse(source.contains("UILabel()"))
            XCTAssertFalse(source.contains("UIImageView()"))
        }

        XCTAssertTrue(contextActionsSource.contains("ASTextNode"))
        XCTAssertTrue(contextActionsSource.contains("ASImageNode"))
        XCTAssertFalse(contextActionsSource.contains("UILabel()"))
        XCTAssertFalse(contextActionsSource.contains("UIImageView()"))

    }

    func testTabBarPassiveChromeRendersThroughTextureNodes() throws {
        let tabBarSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/TabBar/TabBarView.swift")
        )
        let itemStart = try XCTUnwrap(tabBarSource.range(of: "private final class TabBarItemView"))
        let itemEnd = try XCTUnwrap(tabBarSource.range(of: "// MARK: - Gesture recognizer delegate", range: itemStart.upperBound..<tabBarSource.endIndex))
        let itemSource = tabBarSource[itemStart.lowerBound..<itemEnd.lowerBound]
        let badgeSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/NavigationBarBadgeView.swift")
        )

        XCTAssertTrue(tabBarSource.contains("private let separatorNode: ASDisplayNode"))
        XCTAssertFalse(tabBarSource.contains("private let separatorView: UIView"))
        XCTAssertTrue(tabBarSource.contains("private var minimizedIconNode: ASImageNode?"))
        XCTAssertTrue(itemSource.contains("ASImageNode"))
        XCTAssertTrue(itemSource.contains("ASTextNode"))
        XCTAssertFalse(itemSource.contains("UIImageView"))
        XCTAssertFalse(itemSource.contains("UILabel"))

        XCTAssertTrue(badgeSource.contains("private final class NavigationBarBadgeNode: ASDisplayNode"))
        XCTAssertTrue(badgeSource.contains("ASTextNode"))
        XCTAssertFalse(badgeSource.contains("UILabel()"))
        XCTAssertFalse(badgeSource.contains("UIView()"))
    }

    func testNavigationBarPassiveChromeRendersThroughTextureNodes() throws {
        let source = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/NavigationBarImpl.swift")
        )
        let backButtonStart = try XCTUnwrap(source.range(of: "// MARK: - Back Button View"))
        let backButtonSource = source[backButtonStart.lowerBound..<source.endIndex]

        XCTAssertTrue(source.contains("private let titleNode: ASTextNode"))
        XCTAssertTrue(source.contains("private let subtitleNode: ASTextNode"))
        XCTAssertTrue(source.contains("public let stripeNode: ASDisplayNode"))
        XCTAssertFalse(source.contains("public let stripeView: UIView"))
        XCTAssertTrue(source.contains("geometryTransition.updateFrame(node: titleNode"))
        XCTAssertTrue(source.contains("transition.updateFrame(node: stripeNode"))
        XCTAssertFalse(source.contains("private final class BackButtonContentView"))
        XCTAssertTrue(backButtonSource.contains("ASImageNode"))
        XCTAssertTrue(backButtonSource.contains("ASTextNode"))
        XCTAssertFalse(backButtonSource.contains("UIImageView()"))
        XCTAssertFalse(backButtonSource.contains("UILabel()"))
    }

    func testNavigationSearchPassiveChromeRendersThroughTextureNodes() throws {
        let searchBarSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/AetherSearchBarContent.swift")
        )
        let activeSearchSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/AetherActiveSearchBar.swift")
        )
        let controllerSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/AetherSearchController.swift")
        )
        let bottomInstallStart = try XCTUnwrap(controllerSource.range(of: "private func installBottomPill"))
        let bottomInstallEnd = try XCTUnwrap(controllerSource.range(of: "private func removeBottomPill", range: bottomInstallStart.upperBound..<controllerSource.endIndex))
        let bottomInstallSource = controllerSource[bottomInstallStart.lowerBound..<bottomInstallEnd.lowerBound]

        XCTAssertTrue(searchBarSource.contains("private let iconNode = ASImageNode()"))
        XCTAssertTrue(searchBarSource.contains("private let placeholderNode = ASTextNode()"))
        XCTAssertFalse(searchBarSource.contains("UIImageView()"))
        XCTAssertFalse(searchBarSource.contains("UILabel()"))
        XCTAssertTrue(activeSearchSource.contains("private let iconNode = ASImageNode()"))
        XCTAssertFalse(activeSearchSource.contains("UIImageView()"))
        XCTAssertTrue(controllerSource.contains("private var bottomPillIcon: ASImageNode?"))
        XCTAssertTrue(controllerSource.contains("private var bottomPillLabel: ASTextNode?"))
        XCTAssertTrue(bottomInstallSource.contains("ASImageNode()"))
        XCTAssertTrue(bottomInstallSource.contains("ASTextNode()"))
        XCTAssertFalse(bottomInstallSource.contains("UIImageView"))
        XCTAssertFalse(bottomInstallSource.contains("UILabel"))
    }

    func testContainerPassiveFillsRenderThroughTextureNodes() throws {
        let navigationBackgroundSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Views/NavigationBackgroundView.swift")
        )
        let splitContainerSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationController/NavigationSplitContainer.swift")
        )

        XCTAssertTrue(navigationBackgroundSource.contains("private let backgroundColorNode: ASDisplayNode"))
        XCTAssertTrue(navigationBackgroundSource.contains("transition.updateFrame(node: self.backgroundColorNode"))
        XCTAssertFalse(navigationBackgroundSource.contains("private let backgroundColorView: UIView"))

        XCTAssertTrue(splitContainerSource.contains("private let separatorNode: ASDisplayNode"))
        XCTAssertTrue(splitContainerSource.contains("transition.updateFrame(node: separatorNode"))
        XCTAssertFalse(splitContainerSource.contains("private let separator: UIView"))
    }

    func testSliderNodeWrapsGestureCriticalSliderBehindNodeAPI() {
        let sliderNode = AetherSliderNode(value: 0.25)
        sliderNode.minimumValue = 0.0
        sliderNode.maximumValue = 2.0
        sliderNode.setValue(1.5, animated: false)

        XCTAssertEqual(sliderNode.value, 1.5)
        XCTAssertFalse(String(describing: sliderNode.animationIdentity.rawValue).isEmpty)
    }

    @MainActor
    func testModalAndOverlayControllersExposeNodeFirstEntrypoints() {
        let modal = AetherModalController()
        let contentNode = ASDisplayNode()
        let footerNode = ASDisplayNode()

        modal.setContentNode(contentNode)
        modal.setFooterNode(footerNode)

        XCTAssertTrue(contentNode.view.superview === modal.contentView)
        XCTAssertTrue(modal.footerView === footerNode.view)

        let alertContentNode = ASDisplayNode()
        let alert = AetherAlertController(
            title: "Title",
            message: "Message",
            actions: [],
            customContentNode: alertContentNode
        )
        XCTAssertTrue(alert.customContentNode === alertContentNode)
        XCTAssertTrue(alert.customContentView === alertContentNode.view)

        let sheet = AetherActionSheetController()
        let overlayNode = ASDisplayNode()
        sheet.setItemGroupOverlayNode(groupIndex: 0, node: overlayNode)

        let navModal = AetherModalNodeNavigationController(rootNode: TrackingScreenNode())
        XCTAssertNotNil(navModal.topNode)
    }

    func testListNodeExposesNodeFirstCompatibilityReplacements() {
        let listNode = AetherListNode()
        let topBackgroundNode = ASDisplayNode()
        let bottomBackgroundNode = ASDisplayNode()

        listNode.topOverscrollBackgroundNode = topBackgroundNode
        listNode.bottomOverscrollBackgroundNode = bottomBackgroundNode
        listNode.keyboardDismissBehavior = .interactive

        XCTAssertTrue(listNode.topOverscrollBackgroundNode === topBackgroundNode)
        XCTAssertTrue(listNode.bottomOverscrollBackgroundNode === bottomBackgroundNode)
        XCTAssertEqual(listNode.keyboardDismissBehavior, .interactive)
        XCTAssertEqual(listNode.panVelocity(relativeTo: nil), .zero)
    }

    func testListNodeKeepsUIKitDelegatesOutOfPublicDeclaration() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListNode.swift"))

        XCTAssertFalse(source.contains("open class AetherListNode: ASDisplayNode, UIScrollViewDelegate"))
        XCTAssertFalse(source.contains("open class AetherListNode: ASDisplayNode, UIGestureRecognizerDelegate"))
        XCTAssertFalse(source.contains("public func scrollView"))
        XCTAssertFalse(source.contains("public func gestureRecognizer"))
        XCTAssertTrue(source.contains("private final class AetherListNodeDelegateProxy"))
    }

    func testListNodeScrollHotPathAvoidsFullItemEnumeration() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListNode.swift"))
        let stickyStart = try XCTUnwrap(source.range(of: "private func makeStickyHeaderDescriptors"))
        let stickyEnd = try XCTUnwrap(source.range(of: "private func currentStickyHeaderIndices", range: stickyStart.upperBound..<source.endIndex))
        let stickyBody = source[stickyStart.lowerBound..<stickyEnd.lowerBound]
        let asyncStart = try XCTUnwrap(source.range(of: "private func makeAsyncLayoutCommands"))
        let asyncEnd = try XCTUnwrap(source.range(of: "private func prefetchAsyncLayouts", range: asyncStart.upperBound..<source.endIndex))
        let asyncBody = source[asyncStart.lowerBound..<asyncEnd.lowerBound]

        XCTAssertTrue(source.contains("private var stickyHeaderItemIndices"))
        XCTAssertFalse(stickyBody.contains("items.enumerated()"))
        XCTAssertFalse(stickyBody.contains("0..<items.count"))
        XCTAssertFalse(asyncBody.contains("items.enumerated()"))
        XCTAssertTrue(asyncBody.contains("pendingLayoutTasks.keys"))
    }

    func testListNodeSuppressesSelectionTapWhileScrollMomentumIsStopping() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListNode.swift"))
        let tapStart = try XCTUnwrap(source.range(of: "func performTap(at point: CGPoint)"))
        let tapEnd = try XCTUnwrap(source.range(of: "func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)", range: tapStart.upperBound..<source.endIndex))
        let tapBody = source[tapStart.lowerBound..<tapEnd.lowerBound]

        XCTAssertTrue(source.contains("private var tapSelectionSuppressedUntil"))
        XCTAssertTrue(source.contains("suppressTapSelectionAfterScrollMomentum()"))
        XCTAssertTrue(tapBody.contains("guard !isTapSelectionSuppressedByScrollMomentum() else"))
        XCTAssertTrue(source.contains("guard !isTapSelectionSuppressedByScrollMomentum() else { return false }"))
    }

    func testListNodeSwipeActionsUseCircularIconButtonsWithExternalTitles() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListNode.swift"))
        let actionsStart = try XCTUnwrap(source.range(of: "private final class AetherListSwipeActionsNode"))
        let actionsEnd = try XCTUnwrap(source.range(of: "open class AetherListNode", range: actionsStart.upperBound..<source.endIndex))
        let actionsBody = source[actionsStart.lowerBound..<actionsEnd.lowerBound]

        XCTAssertTrue(actionsBody.contains("private let circleNode = ASDisplayNode()"))
        XCTAssertTrue(actionsBody.contains("circleNode.addSubnode(imageNode)"))
        XCTAssertTrue(actionsBody.contains("backgroundColor = .clear"))
        XCTAssertTrue(actionsBody.contains("circleNode.cornerRadius = circleSide / 2.0"))
        XCTAssertTrue(actionsBody.contains("circleNode.layer.cornerRadius = circleSide / 2.0"))
        XCTAssertTrue(actionsBody.contains("circleNode.layer.masksToBounds = true"))
    }

    func testListAndWindowDebugChromeRenderTextThroughTextureOverlay() throws {
        let listNodeSource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListNode.swift"))
        let windowSource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Window/AetherWindow.swift"))
        let coordinatorSource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Window/AetherWindowCoordinators.swift"))
        let overlaySource = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Core/AetherTextNodeOverlayView.swift"))

        XCTAssertTrue(overlaySource.contains("private let textNode = ASTextNode()"))
        XCTAssertTrue(listNodeSource.contains("private weak var debugOverlayLabel: AetherTextNodeOverlayView?"))
        XCTAssertTrue(windowSource.contains("private var forceInCallStatusBarView: AetherTextNodeOverlayView?"))
        XCTAssertTrue(coordinatorSource.contains("private weak var overlayLabel: AetherTextNodeOverlayView?"))

        for source in [listNodeSource, windowSource, coordinatorSource] {
            XCTAssertFalse(source.contains("UILabel()"))
        }
    }

    func testListItemPrimaryProtocolIsNodeFirst() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListItem.swift"))
        let primaryStart = try XCTUnwrap(source.range(of: "public protocol AetherListItem"))
        let layoutStart = try XCTUnwrap(source.range(of: "public struct AetherListItemLayoutParams"))
        let primaryProtocol = source[primaryStart.lowerBound..<layoutStart.lowerBound]

        XCTAssertFalse(primaryProtocol.contains("AetherListView"))
        XCTAssertFalse(source.contains("AetherLegacyListItem"))
        XCTAssertTrue(primaryProtocol.contains("selected(listNode: AetherListNode)"))
        XCTAssertTrue(primaryProtocol.contains("swipeActionSelected(_ action: AetherListSwipeAction, listNode: AetherListNode"))
    }

    func testLegacyListViewIsRemovedFromTextureTarget() throws {
        let legacyPath = sourceRoot().appendingPathComponent("Sources/AetherUI/ListView/AetherListView.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath.path))
    }

    func testTestsAndExampleDoNotInstantiateRemovedListView() throws {
        let scannedRoots = [
            sourceRoot().appendingPathComponent("Tests"),
            sourceRoot().appendingPathComponent("Example")
        ]
        let forbiddenConstructor = "AetherList" + "View("
        var violations: [String] = []

        for root in scannedRoots {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "swift" else { continue }
                let source = try String(contentsOf: fileURL)
                for (lineIndex, line) in source.components(separatedBy: .newlines).enumerated()
                    where line.contains(forbiddenConstructor) {
                    violations.append("\(fileURL.lastPathComponent):\(lineIndex + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testControlNodesDoNotHostLegacyUIKitControls() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Node/AetherControlNodes.swift"))

        XCTAssertFalse(source.contains("setViewBlock"))
        XCTAssertFalse(source.contains("GlassButton("))
        XCTAssertFalse(source.contains("AetherSegmentedControl("))
    }

    func testReusableGlassAndSegmentedControlsRenderPassiveContentThroughTexture() throws {
        let segmentedSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/SegmentedControl/AetherSegmentedControl.swift")
        )
        let glassButtonSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/GlassButtonView.swift")
        )
        let legacyGlassButtonSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/GlassButton.swift")
        )
        let glassBarButtonSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/GlassBarButtonView.swift")
        )
        let glassControlGroupSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/GlassControlGroup.swift")
        )
        let floatingToolbarSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Toolbar/AetherFloatingToolbar.swift")
        )
        let legacyToolbarSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Toolbar/AetherToolbar.swift")
        )

        XCTAssertTrue(segmentedSource.contains("private var normalTitleNodes: [ASTextNode]"))
        XCTAssertTrue(segmentedSource.contains("private var selectedTitleNodes: [ASTextNode]"))
        XCTAssertFalse(segmentedSource.contains("UILabel()"))

        XCTAssertTrue(glassButtonSource.contains("private let iconNode: ASImageNode"))
        XCTAssertTrue(glassButtonSource.contains("private let labelNode: ASTextNode?"))
        XCTAssertFalse(glassButtonSource.contains("UIImageView()"))
        XCTAssertFalse(glassButtonSource.contains("UILabel()"))

        XCTAssertTrue(legacyGlassButtonSource.contains("private var iconNode: ASImageNode?"))
        XCTAssertTrue(legacyGlassButtonSource.contains("private var titleNode: ASTextNode?"))
        XCTAssertFalse(legacyGlassButtonSource.contains("UIImageView("))
        XCTAssertFalse(legacyGlassButtonSource.contains("UILabel("))

        XCTAssertTrue(glassBarButtonSource.contains("private var iconNode: ASImageNode?"))
        XCTAssertTrue(glassBarButtonSource.contains("private var titleNode: ASTextNode?"))
        XCTAssertFalse(glassBarButtonSource.contains("UIImageView("))
        XCTAssertFalse(glassBarButtonSource.contains("UILabel("))

        XCTAssertTrue(glassControlGroupSource.contains("GlassControlGroupIconContentView"))
        XCTAssertTrue(glassControlGroupSource.contains("GlassControlGroupTextContentView"))
        XCTAssertTrue(glassControlGroupSource.contains("ASImageNode"))
        XCTAssertTrue(glassControlGroupSource.contains("ASTextNode"))
        XCTAssertFalse(glassControlGroupSource.contains("UIImageView("))
        XCTAssertFalse(glassControlGroupSource.contains("UILabel("))

        XCTAssertTrue(floatingToolbarSource.contains("private let iconNode: ASImageNode"))
        XCTAssertTrue(floatingToolbarSource.contains("private let stackContainerView = UIView()"))
        XCTAssertFalse(floatingToolbarSource.contains("UIStackView("))
        XCTAssertFalse(floatingToolbarSource.contains("private let stackView"))
        XCTAssertFalse(floatingToolbarSource.contains("UIImageView("))
        XCTAssertFalse(floatingToolbarSource.contains("UILabel("))

        XCTAssertTrue(legacyToolbarSource.contains("private final class AetherToolbarViewButtonNode: AetherControlNode"))
        XCTAssertTrue(legacyToolbarSource.contains("private let tintNode = ASDisplayNode()"))
        XCTAssertTrue(legacyToolbarSource.contains("private let separatorNode = ASDisplayNode()"))
        XCTAssertTrue(legacyToolbarSource.contains("private let titleNode = ASTextNode()"))
        XCTAssertFalse(legacyToolbarSource.contains("private let tintView = UIView()"))
        XCTAssertFalse(legacyToolbarSource.contains("private let separatorView = UIView()"))
        XCTAssertFalse(legacyToolbarSource.contains("UIButton("))
        XCTAssertFalse(legacyToolbarSource.contains("UILabel("))
    }

    func testNodeControllersUseAetherViewControllerContentNodeBoundary() throws {
        let source = try String(contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Node/AetherNodeControllers.swift"))

        XCTAssertTrue(source.contains("contentNode = screenNode"))
        XCTAssertTrue(source.contains("contentNode = navigationNode"))
        XCTAssertTrue(source.contains("contentNode = tabContainerNode"))
        XCTAssertTrue(source.contains("contentNode = pageContainerNode"))
        XCTAssertFalse(source.contains("_AetherNodeHostView"))
        XCTAssertFalse(source.contains("AetherNodeHostingView"))
        XCTAssertFalse(source.contains("override func loadView()"))
        XCTAssertFalse(source.contains("public private(set) var hostingView"))
    }

    func testNavigationAndTabChromeRenderPassiveContentThroughTexture() throws {
        let navigationBarSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/NavigationBarImpl.swift")
        )
        let tabBarSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/TabBar/TabBarView.swift")
        )
        let searchControllerSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/AetherSearchController.swift")
        )
        let activeSearchSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationBar/AetherActiveSearchBar.swift")
        )
        let searchIconSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Texture/AetherSearchIconLeftView.swift")
        )

        XCTAssertTrue(navigationBarSource.contains("private let backArrowNode: ASImageNode"))
        XCTAssertTrue(navigationBarSource.contains("public let stripeNode: ASDisplayNode"))
        XCTAssertTrue(navigationBarSource.contains("private final class AetherNavigationBarLegacyButtonView: UIControl"))
        XCTAssertTrue(navigationBarSource.contains("private let imageNode = ASImageNode()"))
        XCTAssertTrue(navigationBarSource.contains("private let titleNode = ASTextNode()"))
        XCTAssertFalse(navigationBarSource.contains("UIButton(type: .system)"))
        // Passive controls use Texture. An outgoing custom view may need a
        // raster fallback when UIKit cannot provide its transition snapshot;
        // the snapshot-only allowlist below checks that exception precisely.
        XCTAssertFalse(navigationBarSource.contains("UIImageView(image: iconImage)"))

        XCTAssertTrue(tabBarSource.contains("private let separatorNode: ASDisplayNode"))
        XCTAssertTrue(tabBarSource.contains("private let imageNode: ASImageNode"))
        XCTAssertTrue(tabBarSource.contains("private let titleNode: ASTextNode"))
        XCTAssertTrue(tabBarSource.contains("tf.leftView = AetherSearchIconLeftView()"))
        XCTAssertFalse(tabBarSource.contains("UIImageView(image: iconImage)"))

        XCTAssertTrue(searchControllerSource.contains("tf.leftView = AetherSearchIconLeftView()"))
        XCTAssertTrue(activeSearchSource.contains("private final class AetherActiveSearchCancelButton: UIControl"))
        XCTAssertTrue(activeSearchSource.contains("private let titleNode = ASTextNode()"))
        XCTAssertTrue(searchIconSource.contains("private let iconNode = ASImageNode()"))
        XCTAssertFalse(searchControllerSource.contains("UIImageView(image: iconImage)"))
        XCTAssertFalse(activeSearchSource.contains("UIButton("))
        XCTAssertFalse(activeSearchSource.contains("UILabel("))
        XCTAssertFalse(searchIconSource.contains("UIImageView("))
    }

    func testPresentedChromeRootsKeepContentNodeBacked() throws {
        let alertSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Alert/AetherAlertController.swift")
        )
        let actionSheetControllerSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ActionSheet/AetherActionSheetController.swift")
        )
        let actionSheetItemSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ActionSheet/AetherActionSheetItem.swift")
        )
        let modalSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Modal/AetherModalController.swift")
        )
        let toastSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Toast/AetherToastController.swift")
        )
        let tooltipSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Tooltip/AetherTooltipController.swift")
        )

        XCTAssertTrue(alertSource.contains("private let titleNode = ASTextNode()"))
        XCTAssertTrue(alertSource.contains("private let messageNode = ASTextNode()"))
        XCTAssertTrue(alertSource.contains("private final class AetherAlertPillButtonNode: ASDisplayNode"))
        XCTAssertFalse(alertSource.contains("UILabel("))

        XCTAssertTrue(actionSheetControllerSource.contains("setItemGroupOverlayNode(groupIndex: Int, node: ASDisplayNode?)"))
        XCTAssertTrue(actionSheetItemSource.contains("public let contentNode: AetherActionSheetItemNode"))
        XCTAssertFalse(actionSheetItemSource.contains("UILabel("))

        XCTAssertTrue(modalSource.contains("public func setContentNode(_ node: ASDisplayNode?)"))
        XCTAssertTrue(modalSource.contains("public func setFooterNode(_ node: ASDisplayNode?)"))

        XCTAssertTrue(toastSource.contains("private let contentNode: AetherToastContentNode"))
        XCTAssertTrue(toastSource.contains("private final class AetherToastContentNode: ASDisplayNode"))
        XCTAssertTrue(tooltipSource.contains("private let contentNode: AetherTooltipContentNode"))
        XCTAssertTrue(tooltipSource.contains("private final class AetherTooltipContentNode: ASDisplayNode"))
        XCTAssertFalse(toastSource.contains("UILabel("))
        XCTAssertFalse(tooltipSource.contains("UILabel("))
    }

    func testPassiveBitmapRenderSurfacesUseTextureNodes() throws {
        let glassBackgroundSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/GlassBackgroundView.swift")
        )
        let liquidLensSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/LiquidLensView.swift")
        )
        let edgeEffectSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Glass/EdgeEffectView.swift")
        )
        let chatBackgroundSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/ChatBackground/ChatBackgroundView.swift")
        )
        let navigationTransitionSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/NavigationController/NavigationTransitionCoordinator.swift")
        )
        let contentCoverSource = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/AetherUI/Core/AetherContentCover.swift")
        )

        XCTAssertTrue(glassBackgroundSource.contains("public final class ContentImageView: UIView, ContentView"))
        XCTAssertTrue(glassBackgroundSource.contains("private let imageNode = ASImageNode()"))
        // Renderer swapping owns these nodes only while the compatibility
        // Liquid backend is mounted, so they are intentionally optional vars.
        XCTAssertTrue(glassBackgroundSource.contains("private var foregroundNode: ASImageNode?"))
        XCTAssertTrue(glassBackgroundSource.contains("private var shadowNode: ASImageNode?"))
        XCTAssertFalse(glassBackgroundSource.contains("UIImageView"))

        XCTAssertTrue(liquidLensSource.contains("private var legacyContentMaskBlobNode: ASImageNode?"))
        XCTAssertTrue(liquidLensSource.contains("private var legacyLiftedContentBlobMaskNode: ASImageNode?"))
        XCTAssertFalse(liquidLensSource.contains("UIImageView"))

        // These images are UIKit mask hosts, not independently rendered
        // Texture content. ASImageNode retains visible interface state when a
        // mask is detached and can assert during an in-flight chrome update.
        XCTAssertTrue(edgeEffectSource.contains("private let contentMaskView: UIImageView"))
        XCTAssertTrue(edgeEffectSource.contains("private var blurMaskView: UIImageView?"))
        XCTAssertTrue(edgeEffectSource.contains("private let imageMaskView: UIImageView?"))
        XCTAssertFalse(edgeEffectSource.contains("contentMaskNode: ASImageNode"))

        XCTAssertTrue(chatBackgroundSource.contains("private let imageNode = ASImageNode()"))
        XCTAssertTrue(chatBackgroundSource.contains("private let overlayImageNode = ASImageNode()"))
        XCTAssertFalse(chatBackgroundSource.contains("UIImageView"))

        XCTAssertTrue(navigationTransitionSource.contains("private let shadowNode: ASImageNode"))
        XCTAssertFalse(navigationTransitionSource.contains("UIImageView"))

        XCTAssertTrue(contentCoverSource.contains("private let spotNode = ASImageNode()"))
        XCTAssertFalse(contentCoverSource.contains("UIImageView"))
    }

    func testRemainingUIImageViewsAreSnapshotOnly() throws {
        let sourceDirectory = sourceRoot().appendingPathComponent("Sources/AetherUI")
        let allowed: [String: [String]] = [
            "Modal/AetherModalTransitionAnimation.swift": [
                "let imageView = UIImageView(image: image)"
            ],
            "AttachmentMenu/AetherSourceMorphController.swift": [
                "let imageView = UIImageView(image: image)"
            ],
            "Window/AetherPortal.swift": [
                "let imageView = UIImageView(image: image)"
            ],
            "ContextMenu/ContextMenuSourcePresentationLease.swift": [
                "let imageView = UIImageView(image: image)"
            ],
            "ContextMenu/ContextMenuController.swift": [
                "let view = UIImageView(image: image)"
            ],
            "ContextMenu/ContextMenuGlassmorphicTransitionView.swift": [
                "SnapshotView = UIImageView()"
            ],
            "Glass/AetherContentMaterialization.swift": [
                "private let imageView = UIImageView()"
            ],
            "NavigationBar/NavigationBarImpl.swift": [
                "return UIImageView(image: image)"
            ],
            "TabBar/BottomBarAccessoryTransitionParticipant.swift": [
                "keeps one UIImageView/layer alive",
                "BottomBarAccessoryRasterizedRepresentationView: UIImageView"
            ],
            "Glass/EdgeEffectView.swift": [
                "contentMaskView",
                "blurMaskView",
                "imageMaskView",
                "let mask: UIImageView",
                "mask = UIImageView()"
            ]
        ]
        var violations: [String] = []

        let enumerator = FileManager.default.enumerator(at: sourceDirectory, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: sourceDirectory.path + "/", with: "")
            let allowedFragments = allowed[relativePath] ?? []
            let source = try String(contentsOf: fileURL)
            for (lineIndex, line) in source.components(separatedBy: .newlines).enumerated()
                where line.contains("UIImageView") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard allowedFragments.contains(where: { trimmed.contains($0) }) else {
                    violations.append("\(relativePath):\(lineIndex + 1): \(trimmed)")
                    continue
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testControllerLayerUsesTextureRootControllers() throws {
        let controllerSources = try [
            "Sources/AetherUI/Core/AetherViewController.swift",
            "Sources/AetherUI/NavigationController/NavigationController.swift",
            "Sources/AetherUI/TabBar/TabBarController.swift",
            "Sources/AetherUI/PageController/AetherPageViewController.swift",
            "Sources/AetherUI/Modal/AetherModalController.swift",
            "Sources/AetherUI/Alert/AetherAlertController.swift",
            "Sources/AetherUI/ActionSheet/AetherActionSheetController.swift",
            "Sources/AetherUI/Window/AetherWindowRootViewController.swift",
            "Sources/AetherUI/NavigationBar/AetherSearchDisplayController.swift"
        ].map {
            try String(contentsOf: sourceRoot().appendingPathComponent($0))
        }.joined(separator: "\n")

        XCTAssertTrue(controllerSources.contains("open class AetherViewController: ASDKViewController<ASDisplayNode>"))
        XCTAssertTrue(controllerSources.contains("open class AetherNavigationController: AetherViewController"))
        XCTAssertTrue(controllerSources.contains("open class AetherTabBarController: AetherViewController"))
        XCTAssertTrue(controllerSources.contains("open class AetherPageViewController: AetherViewController"))
        XCTAssertTrue(controllerSources.contains("open class AetherModalController: ASDKViewController<ASDisplayNode>"))
        XCTAssertTrue(controllerSources.contains("open class AetherAlertController: ASDKViewController<ASDisplayNode>"))
        XCTAssertTrue(controllerSources.contains("open class AetherActionSheetController: ASDKViewController<ASDisplayNode>"))
        XCTAssertTrue(controllerSources.contains("public final class AetherWindowRootViewController: ASDKViewController<ASDisplayNode>"))
        XCTAssertTrue(controllerSources.contains("open class AetherSearchContentController: ASDKViewController<ASDisplayNode>"))
    }

    func testPageControllerOwnsTextureScrollNode() throws {
        let source = try String(
            contentsOf: sourceRoot()
                .appendingPathComponent("Sources/AetherUI/PageController/AetherPageViewController.swift")
        )

        XCTAssertTrue(source.contains("public let scrollNode: ASScrollNode"))
        XCTAssertTrue(source.contains("node.insertSubnode(scrollNode"))
        XCTAssertFalse(source.contains("public let scrollView: UIScrollView"))
        XCTAssertFalse(source.contains("PageScrollView: UIScrollView"))
        XCTAssertFalse(source.contains("AetherPageViewController: AetherViewController, UIScrollViewDelegate"))
    }

    func testSegmentedControlUsesTextureHostsForPassiveRenderAndHitTargets() throws {
        let source = try String(
            contentsOf: sourceRoot()
                .appendingPathComponent("Sources/AetherUI/SegmentedControl/AetherSegmentedControl.swift")
        )

        XCTAssertTrue(source.contains("private let scrollNode = ASScrollNode()"))
        XCTAssertTrue(source.contains("private let contentHostNode = ASDisplayNode()"))
        XCTAssertTrue(source.contains("private let normalContentNode = ASDisplayNode()"))
        XCTAssertTrue(source.contains("private let selectedContentHostNode = ASDisplayNode()"))
        XCTAssertTrue(source.contains("private final class SegmentedItemControlNode: AetherControlNode"))
        XCTAssertFalse(source.contains("private let scrollView = UIScrollView()"))
        XCTAssertFalse(source.contains("private let contentHostView = UIView()"))
        XCTAssertFalse(source.contains("private let normalContentView = UIView()"))
        XCTAssertFalse(source.contains("private let selectedContentHostView = UIView()"))
        XCTAssertFalse(source.contains("SegmentedItemButton: UIButton"))
    }

    func testSourcesDoNotDeclareDirectUIViewControllerSubclasses() throws {
        let sourceDirectory = sourceRoot().appendingPathComponent("Sources/AetherUI")
        let pattern = #"\bclass\s+\w+[^:\n]*:\s*UIViewController\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        var violations: [String] = []

        let enumerator = FileManager.default.enumerator(at: sourceDirectory, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL)
            for (lineIndex, line) in source.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard regex.firstMatch(in: line, range: range) != nil else { continue }
                violations.append("\(fileURL.lastPathComponent):\(lineIndex + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testNodeLayerPublicDeclarationsAvoidUIKitContainers() throws {
        let nodeDirectory = sourceRoot().appendingPathComponent("Sources/AetherUI/Node")
        let forbiddenTokens = [
            "UIViewController",
            "UINavigationController",
            "UITabBarController",
            "UIScrollView",
            "UICollectionView",
            "UITableView",
            "NSLayoutConstraint"
        ]
        var violations: [String] = []

        let enumerator = FileManager.default.enumerator(at: nodeDirectory, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL)
            for (lineIndex, line) in source.components(separatedBy: .newlines).enumerated() {
                guard line.contains("public ") || line.contains("open ") else { continue }
                for token in forbiddenTokens where line.contains(token) {
                    violations.append("\(fileURL.lastPathComponent):\(lineIndex + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class TrackingScreenNode: AetherScreenNode {
    private(set) var events: [String] = []

    override func screenWillAppear() {
        events.append("willAppear")
    }

    override func screenDidAppear() {
        events.append("didAppear")
    }

    override func screenWillDisappear() {
        events.append("willDisappear")
    }

    override func screenDidDisappear() {
        events.append("didDisappear")
    }
}
