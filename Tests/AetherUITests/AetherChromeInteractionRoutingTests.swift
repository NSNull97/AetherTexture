import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherChromeInteractionRoutingTests: XCTestCase {
    func testSelectedAetherPageVerticalScrollWinsOverPagerAndAttachedNeighbours() throws {
        let first = ChromeRoutingContentController()
        let selected = ChromeRoutingContentController()
        let third = ChromeRoutingContentController()
        let pager = makePager(
            controllers: [first, selected, third],
            selectedIndex: 1
        )

        // AetherPageViewController deliberately keeps the selected page and
        // both immediate neighbours attached. Resolution must still start at
        // the selected controller rather than searching the whole pager tree.
        XCTAssertTrue(first.parent === pager)
        XCTAssertTrue(selected.parent === pager)
        XCTAssertTrue(third.parent === pager)

        let source = try XCTUnwrap(
            AetherChromeScrollSourceResolver.resolve(from: pager)
        )

        XCTAssertTrue(source.controllerPath.last === selected)
        XCTAssertTrue(source.owner === selected)
        XCTAssertTrue(source.scrollView === selected.verticalScrollView)
        XCTAssertFalse(source.scrollView === pager.backingScrollViewForTesting)
        XCTAssertFalse(source.scrollView === first.verticalScrollView)
        XCTAssertFalse(source.scrollView === third.verticalScrollView)
    }

    func testExplicitPrimaryScrollViewWinsOverVisibleAutomaticCandidate() throws {
        let controller = ExplicitChromeRoutingContentController()
        controller.loadViewIfNeeded()

        let competing = makeVerticalScrollView(frame: controller.view.bounds)
        competing.scrollsToTop = true
        controller.view.insertSubview(competing, at: 0)

        let source = try XCTUnwrap(
            AetherChromeScrollSourceResolver.resolve(from: controller)
        )

        XCTAssertTrue(source.scrollView === controller.verticalScrollView)
        XCTAssertFalse(source.scrollView === competing)
    }

    func testPrimaryVerticalScrollDiscoveryIgnoresHiddenAncestorSubtree() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let hiddenHost = UIView(frame: root.bounds)
        hiddenHost.isHidden = true
        let hiddenScroll = makeVerticalScrollView(frame: hiddenHost.bounds)
        hiddenHost.addSubview(hiddenScroll)
        root.addSubview(hiddenHost)

        let visibleScroll = makeVerticalScrollView(
            frame: CGRect(x: 0, y: 80, width: 320, height: 480)
        )
        root.addSubview(visibleScroll)

        let resolved = try XCTUnwrap(
            AetherChromeScrollSourceResolver.primaryVerticalScrollView(in: root)
        )

        XCTAssertTrue(resolved === visibleScroll)
        XCTAssertFalse(resolved === hiddenScroll)
    }

    func testPageReselectionCallsSelectedChildClosureWithoutMovingPagerOrNeighbours() {
        let neighbour = ChromeRoutingContentController()
        let selected = ChromeRoutingContentController()
        var selectedClosureCalls = 0
        selected.scrollToTopWithTabBar = {
            selectedClosureCalls += 1
        }
        let pager = makePager(
            controllers: [neighbour, selected],
            selectedIndex: 1
        )
        neighbour.verticalScrollView.contentOffset.y = 260
        selected.verticalScrollView.contentOffset.y = 180
        let pagerOffset = pager.backingScrollViewForTesting.contentOffset
        let neighbourOffset = neighbour.verticalScrollView.contentOffset
        let selectedOffset = selected.verticalScrollView.contentOffset

        XCTAssertTrue(AetherTabReselectionRouter.perform(from: pager))

        XCTAssertEqual(selectedClosureCalls, 1)
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset, pagerOffset)
        XCTAssertEqual(neighbour.verticalScrollView.contentOffset, neighbourOffset)
        XCTAssertEqual(selected.verticalScrollView.contentOffset, selectedOffset)
    }

    func testPageReselectionScrollsOnlySelectedPageAndPreservesPagerX() {
        let neighbour = ChromeRoutingContentController()
        let selected = ChromeRoutingContentController()
        selected.verticalScrollView.contentInset.top = 18
        let pager = makePager(
            controllers: [neighbour, selected],
            selectedIndex: 1
        )
        neighbour.verticalScrollView.contentOffset.y = 280
        selected.verticalScrollView.contentOffset.y = 220
        let pagerOffset = pager.backingScrollViewForTesting.contentOffset
        let neighbourOffset = neighbour.verticalScrollView.contentOffset

        var performed = false
        UIView.performWithoutAnimation {
            performed = AetherTabReselectionRouter.perform(from: pager)
        }

        XCTAssertTrue(performed)
        XCTAssertEqual(
            selected.verticalScrollView.contentOffset.y,
            -selected.verticalScrollView.adjustedContentInset.top,
            accuracy: 0.001
        )
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset, pagerOffset)
        XCTAssertEqual(neighbour.verticalScrollView.contentOffset, neighbourOffset)
    }

    func testNestedUIKitNavigationReselectionPopsToRoot() {
        let root = UIViewController()
        let detail = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(detail, animated: false)
        let pager = makePager(
            controllers: [ChromeRoutingContentController(), navigation],
            selectedIndex: 1
        )

        XCTAssertTrue(AetherTabReselectionRouter.perform(from: pager))

        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertTrue(navigation.topViewController === root)
    }

    func testAetherNodeNavigationReselectionPopsToRootNode() {
        let root = AetherScreenNode()
        let detail = AetherScreenNode()
        let navigation = AetherNodeNavigationController(rootNode: root)
        navigation.push(detail, animated: false)

        XCTAssertTrue(AetherTabReselectionRouter.perform(from: navigation))

        XCTAssertEqual(navigation.navigationNode.stack.count, 1)
        XCTAssertTrue(navigation.navigationNode.topNode === root)
    }

    func testTabControllerReselectionRoutesSelectedPageAcrossAppearanceStyles() throws {
        for style in [
            AetherAppearanceStyle.legacy,
            .liquidGlassV1,
            .liquidGlassV2
        ] {
            let selected = ChromeRoutingContentController()
            var calls = 0
            selected.scrollToTopWithTabBar = {
                calls += 1
            }
            let pager = makePager(
                controllers: [ChromeRoutingContentController(), selected],
                selectedIndex: 1
            )
            let tabs = AetherAppearance.withRuntimeCurrent(
                AetherAppearance(style: style)
            ) {
                AetherTabBarController()
            }
            tabs.setControllers([pager], selectedIndex: 0)
            tabs.updateAppearance(AetherAppearance(style: style))
            tabs.loadViewIfNeeded()

            let tabBarView = try XCTUnwrap(
                tabs.view.subviews.compactMap { $0 as? TabBarView }.first,
                "Missing TabBarView for \(style)"
            )
            tabBarView.tabSelected?(0)

            XCTAssertEqual(calls, 1, "Failed selected-page route for \(style)")
        }
    }

    private func makePager(
        controllers: [UIViewController],
        selectedIndex: Int
    ) -> AetherPageViewController {
        let pager = AetherPageViewController(
            pages: controllers.enumerated().map { index, controller in
                AetherPageViewController.Page(
                    title: "Page \(index)",
                    viewController: controller
                )
            },
            selectedIndex: selectedIndex,
            installViewPagerAsTopBarAccessory: false
        )
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.containerLayoutUpdated(
            ContainerViewLayout(
                size: pager.view.bounds.size,
                safeInsets: .zero,
                additionalInsets: .zero
            ),
            transition: .immediate
        )
        pager.view.layoutIfNeeded()
        return pager
    }

    private func makeVerticalScrollView(frame: CGRect) -> UIScrollView {
        let scrollView = UIScrollView(frame: frame)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentSize = CGSize(
            width: max(1, frame.width),
            height: max(1_600, frame.height * 2)
        )
        return scrollView
    }
}

@MainActor
private class ChromeRoutingContentController: AetherViewController {
    let verticalScrollView = UIScrollView()

    init() {
        super.init(navigationBarPresentationData: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verticalScrollView.contentInsetAdjustmentBehavior = .never
        verticalScrollView.alwaysBounceVertical = true
        verticalScrollView.scrollsToTop = true
        verticalScrollView.contentSize = CGSize(width: 320, height: 1_600)
        verticalScrollView.frame = view.bounds
        verticalScrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(verticalScrollView)
    }
}

@MainActor
private final class ExplicitChromeRoutingContentController: ChromeRoutingContentController {
    override var primaryScrollViewForChrome: UIScrollView? {
        verticalScrollView
    }
}
