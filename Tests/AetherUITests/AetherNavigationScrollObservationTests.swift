import XCTest
import UIKit
@testable import AetherUI

final class AetherNavigationScrollObservationTests: XCTestCase {
    @MainActor
    func testStandaloneNavigationBarAutomaticallyTracksPrimaryScrollForLegacyAndLiquid() throws {
        for style in [AetherAppearanceStyle.legacy, .liquidGlassV2] {
            let data = AetherAppearance.withRuntimeCurrent(
                AetherAppearance(style: style)
            ) {
                NavigationBarPresentationData.aetherAppearance()
            }
            let controller = StandaloneNavigationScrollFixtureController(
                navigationBarPresentationData: data
            )
            let window = installInWindow(controller)
            defer { window.isHidden = true }

            let bar = try XCTUnwrap(controller.navigationBarView as? NavigationBarImpl)
            controller.chromeScrollView.contentOffset.y = 32.0
            XCTAssertEqual(
                bar.stripeNode.alpha,
                1.0,
                accuracy: 0.001,
                "\(style) must receive automatic scroll-edge updates"
            )

            controller.chromeScrollView.contentOffset.y = 0.0
            XCTAssertEqual(bar.stripeNode.alpha, 0.0, accuracy: 0.001)
        }
    }

    @MainActor
    func testStandalonePageRebindsToProgrammaticAndInteractiveSelectedSources() throws {
        let data = AetherAppearance.withRuntimeCurrent(.legacy) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let first = StandaloneNavigationScrollFixtureController(
            navigationBarPresentationData: data
        )
        let second = StandaloneNavigationScrollFixtureController(
            navigationBarPresentationData: data
        )
        first.chromeScrollView.contentOffset.y = 32.0
        second.chromeScrollView.contentOffset.y = 0.0

        let pages = AetherPageViewController(
            pages: [
                .init(title: "First", viewController: first),
                .init(title: "Second", viewController: second)
            ],
            installViewPagerAsTopBarAccessory: false,
            navigationBarPresentationData: data
        )
        let window = installInWindow(pages)
        defer { window.isHidden = true }

        let bar = try XCTUnwrap(pages.navigationBarView as? NavigationBarImpl)
        XCTAssertEqual(bar.stripeNode.alpha, 1.0, accuracy: 0.001)

        pages.setSelectedIndex(1, animated: false)
        XCTAssertEqual(bar.stripeNode.alpha, 0.0, accuracy: 0.001)

        pages.setSelectedIndex(0, animated: false)
        XCTAssertEqual(bar.stripeNode.alpha, 1.0, accuracy: 0.001)

        let pager = try XCTUnwrap(
            allSubviews(in: pages.view).compactMap { $0 as? UIScrollView }
                .first(where: { $0.isPagingEnabled })
        )
        pager.contentOffset.x = pager.bounds.width
        pager.delegate?.scrollViewDidEndDecelerating?(pager)

        XCTAssertEqual(pages.selectedIndex, 1)
        XCTAssertEqual(bar.stripeNode.alpha, 0.0, accuracy: 0.001)
    }

    @MainActor
    func testNodeContainersPublishChromeSourceChanges() {
        var changedOwners = Set<ObjectIdentifier>()
        let token = NotificationCenter.default.addObserver(
            forName: AetherChromeScrollSourceResolver.didChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let owner = notification.object as AnyObject? {
                changedOwners.insert(ObjectIdentifier(owner))
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let navigation = AetherNavigationNode()
        navigation.push(AetherScreenNode(), animated: false)

        let page = AetherPageContainerNode(
            pages: [
                .init(contentNode: AetherScreenNode()),
                .init(contentNode: AetherScreenNode())
            ],
            selectedIndex: 0
        )
        page.selectPage(at: 1, animated: false)

        let tabs = AetherTabContainerNode(
            tabs: [
                .init(
                    contentNode: AetherScreenNode(),
                    barItemNode: AetherTabBarItemNode(title: "First")
                ),
                .init(
                    contentNode: AetherScreenNode(),
                    barItemNode: AetherTabBarItemNode(title: "Second")
                )
            ],
            selectedIndex: 0
        )
        tabs.selectTab(at: 1, animated: false)

        XCTAssertTrue(changedOwners.contains(ObjectIdentifier(navigation)))
        XCTAssertTrue(changedOwners.contains(ObjectIdentifier(page)))
        XCTAssertTrue(changedOwners.contains(ObjectIdentifier(tabs)))
    }

    @MainActor
    func testNavigationControllerPublishesTopControllerChanges() {
        let navigation = AetherNavigationController(mode: .single)
        let first = AetherViewController()
        let second = AetherViewController()
        var changeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: AetherChromeScrollSourceResolver.didChangeNotification,
            object: navigation,
            queue: .main
        ) { _ in
            changeCount += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        navigation.setViewControllers([first], animated: false)
        navigation.pushViewController(second, animated: false)
        _ = navigation.popViewController(animated: false)

        XCTAssertEqual(changeCount, 3)
    }

    @MainActor
    private func installInWindow(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        if let controller = controller as? AetherViewController {
            controller.containerLayoutUpdated(
                ContainerViewLayout(
                    size: window.bounds.size,
                    safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
                    statusBarHeight: 47.0
                ),
                transition: .immediate
            )
        }
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        return window
    }

    @MainActor
    private func allSubviews(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews(in:))
    }
}

@MainActor
private final class StandaloneNavigationScrollFixtureController: AetherViewController {
    let chromeScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentSize = CGSize(width: 390.0, height: 1_600.0)
        return scrollView
    }()

    override var primaryScrollViewForChrome: UIScrollView? {
        chromeScrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.insertSubview(chromeScrollView, at: 0)
    }

    override func viewDidLayoutSubviews() {
        chromeScrollView.frame = view.bounds
        super.viewDidLayoutSubviews()
    }
}
