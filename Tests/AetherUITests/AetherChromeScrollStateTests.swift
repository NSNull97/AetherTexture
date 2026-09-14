import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherChromeScrollStateTests: XCTestCase {
    func testLegacyTabAndNavigationChromeFollowTheSameObservedScreen() throws {
        let content = ChromeStateContentController(style: .legacy, contentHeight: 1_600)
        let fixture = makeFixture(style: .legacy, controllers: [content])
        defer { fixture.window.isHidden = true }

        XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === content.scrollView)
        let bar = try XCTUnwrap(content.navigationBarView as? NavigationBarImpl)
        let tabBar = try XCTUnwrap(fixture.tabs.view.subviews.compactMap { $0 as? TabBarView }.first)

        content.scrollView.contentOffset.y = 16
        XCTAssertEqual(bar.stripeNode.alpha, 1.0, accuracy: 0.001)
        let navigationTransition = try XCTUnwrap(
            bar.lastScrollEdgeTransitionForTesting
        )
        XCTAssertTrue(navigationTransition.isAnimated)

        content.scrollView.contentOffset.y = maximumOffset(of: content.scrollView)
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)
        XCTAssertEqual(tabBar.legacyBackgroundAlphaForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(tabBar.legacySeparatorAlphaForTesting, 0.0, accuracy: 0.001)
        XCTAssertTrue(tabBar.lastLegacyScrollEdgeTransitionWasAnimatedForTesting)
        XCTAssertEqual(
            tabBar.lastLegacyScrollEdgeTransitionDurationForTesting,
            navigationTransition.duration,
            accuracy: 0.001
        )

        content.scrollView.contentOffset.y -= 0.5
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)
        XCTAssertEqual(tabBar.legacyBackgroundAlphaForTesting, 1.0, accuracy: 0.001)
        XCTAssertEqual(tabBar.legacySeparatorAlphaForTesting, 1.0, accuracy: 0.001)
        XCTAssertTrue(tabBar.lastLegacyScrollEdgeTransitionWasAnimatedForTesting)
    }

    func testLegacyStateRestoresIndependentlyForEachTab() {
        let first = ChromeStateContentController(style: .legacy, contentHeight: 1_600)
        let second = ChromeStateContentController(style: .legacy, contentHeight: 1_600)
        let fixture = makeFixture(style: .legacy, controllers: [first, second])
        defer { fixture.window.isHidden = true }

        first.scrollView.contentOffset.y = maximumOffset(of: first.scrollView)
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)

        fixture.tabs.selectedIndex = 1
        fixture.tabs.view.layoutIfNeeded()
        second.scrollView.contentOffset.y = 120
        XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === second.scrollView)
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)

        fixture.tabs.selectedIndex = 0
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === first.scrollView)
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)

        fixture.tabs.selectedIndex = 1
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)
    }

    func testLegacyShortContentHysteresisSurvivesTabRoundTrip() {
        let first = ChromeStateContentController(style: .legacy, contentHeight: 200)
        let second = ChromeStateContentController(style: .legacy, contentHeight: 200)
        let fixture = makeFixture(style: .legacy, controllers: [first, second])
        defer { fixture.window.isHidden = true }

        first.scrollView.contentOffset.y = -52
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)
        first.scrollView.contentOffset.y = -32
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)
        XCTAssertEqual(
            fixture.tabs.cachedLegacyChromeVisibleForTesting(owner: first),
            true,
            "Visible short-content state was not cached before leaving"
        )

        fixture.tabs.selectedIndex = 1
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)
        XCTAssertEqual(
            fixture.tabs.cachedLegacyChromeVisibleForTesting(owner: first),
            true,
            "Leaving the tab overwrote its cached short-content state"
        )

        fixture.tabs.selectedIndex = 0
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === first.scrollView)
        XCTAssertEqual(
            fixture.tabs.cachedLegacyChromeVisibleForTesting(owner: first),
            true,
            "Returning to the tab overwrote its cached short-content state"
        )
        XCTAssertEqual(
            fixture.tabs.legacyScrollEdgeChromeVisibleForTesting,
            true,
            "The selected screen must restore the visible hysteresis branch before resampling"
        )
    }

    func testLiquidMinimizedEndpointIsSharedAcrossScreensForBothGenerations() {
        for style in [
            AetherAppearanceStyle.liquidGlassV1,
            .liquidGlassV2
        ] {
            let first = ChromeStateContentController(style: style, contentHeight: 1_600)
            let second = ChromeStateContentController(style: style, contentHeight: 1_600)
            let fixture = makeFixture(style: style, controllers: [first, second])

            fixture.tabs.selectedIndex = 1
            fixture.tabs.view.layoutIfNeeded()
            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            XCTAssertTrue(fixture.tabs.isTabBarMinimized, "Failed initial minimize for \(style)")

            fixture.tabs.selectedIndex = 0
            fixture.tabs.view.layoutIfNeeded()
            XCTAssertTrue(
                fixture.tabs.isTabBarMinimized,
                "Returning to another screen lost the shared minimized endpoint for \(style)"
            )

            fixture.tabs.setTabBarMinimized(false, transition: .immediate)
            fixture.tabs.selectedIndex = 1
            fixture.tabs.view.layoutIfNeeded()
            XCTAssertFalse(
                fixture.tabs.isTabBarMinimized,
                "Expanding on one screen did not update the shared endpoint for \(style)"
            )
            fixture.window.isHidden = true
        }
    }

    #if DEBUG
    func testMinimizedLiquidActiveTabStillRoutesReselectionForBothGenerations() {
        for style in [
            AetherAppearanceStyle.liquidGlassV1,
            .liquidGlassV2
        ] {
            let content = ChromeStateContentController(
                style: style,
                contentHeight: 1_600
            )
            var reselectionCount = 0
            content.scrollToTopWithTabBar = {
                reselectionCount += 1
            }
            let fixture = makeFixture(style: style, controllers: [content])

            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            fixture.tabs.simulateMinimizedActiveTabTapForTests()

            XCTAssertFalse(fixture.tabs.isTabBarMinimized)
            XCTAssertEqual(
                reselectionCount,
                1,
                "Compact selected-tab routing failed for \(style)"
            )
            fixture.window.isHidden = true
        }
    }
    #endif

    func testSelectedPageRebindsObservedScrollAcrossEveryAppearanceStyle() {
        for style in [
            AetherAppearanceStyle.legacy,
            .liquidGlassV1,
            .liquidGlassV2
        ] {
            let first = ChromeStateContentController(style: style, contentHeight: 1_600)
            let second = ChromeStateContentController(style: style, contentHeight: 1_600)
            let pageData = AetherAppearance.withRuntimeCurrent(
                AetherAppearance(style: style)
            ) {
                NavigationBarPresentationData.aetherAppearance()
            }
            let pages = AetherPageViewController(
                pages: [
                    .init(title: "First", viewController: first),
                    .init(title: "Second", viewController: second)
                ],
                selectedIndex: 0,
                installViewPagerAsTopBarAccessory: false,
                navigationBarPresentationData: pageData
            )
            let fixture = makeFixture(style: style, controllers: [pages])

            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === first.scrollView,
                "Initial page source failed for \(style)"
            )
            pages.setSelectedIndex(1, animated: false)
            pages.view.layoutIfNeeded()
            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === second.scrollView,
                "Programmatic page switch did not rebind for \(style)"
            )
            pages.setSelectedIndex(0, animated: false)
            pages.view.layoutIfNeeded()
            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === first.scrollView,
                "Page round-trip did not restore the source for \(style)"
            )
            fixture.window.isHidden = true
        }
    }

    func testLegacySelectedPageRestoresItsOwnBottomEdgeState() {
        let first = ChromeStateContentController(style: .legacy, contentHeight: 1_600)
        let second = ChromeStateContentController(style: .legacy, contentHeight: 1_600)
        let pageData = AetherAppearance.withRuntimeCurrent(.legacy) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let pages = AetherPageViewController(
            pages: [
                .init(title: "First", viewController: first),
                .init(title: "Second", viewController: second)
            ],
            installViewPagerAsTopBarAccessory: false,
            navigationBarPresentationData: pageData
        )
        let fixture = makeFixture(style: .legacy, controllers: [pages])
        defer { fixture.window.isHidden = true }

        first.scrollView.contentOffset.y = maximumOffset(of: first.scrollView)
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)

        pages.setSelectedIndex(1, animated: false)
        pages.view.layoutIfNeeded()
        second.scrollView.contentOffset.y = 80
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)

        pages.setSelectedIndex(0, animated: false)
        pages.view.layoutIfNeeded()
        XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === first.scrollView)
        XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)
    }

    func testSearchDismissalImmediatelyRestoresUnderlyingSourceAcrossStyles() {
        for style in [
            AetherAppearanceStyle.legacy,
            .liquidGlassV1,
            .liquidGlassV2
        ] {
            let content = ChromeStateContentController(style: style, contentHeight: 1_600)
            let search = ChromeStateContentController(style: style, contentHeight: 1_600)
            search.tabBarItem = SearchTabItem()
            let fixture = makeFixture(style: style, controllers: [content, search])
            let animationsWereEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)

            fixture.tabs.activateSearch()
            XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === search.scrollView)

            fixture.tabs.deactivateSearch()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))

            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === content.scrollView,
                "Dismissed Search retained chrome ownership for \(style)"
            )
            UIView.setAnimationsEnabled(animationsWereEnabled)
            fixture.window.isHidden = true
        }
    }

    func testNestedUIKitNavigationRebindsAndRestoresStateAcrossStyles() {
        for style in [
            AetherAppearanceStyle.legacy,
            .liquidGlassV1,
            .liquidGlassV2
        ] {
            let root = PlainChromeStateContentController(contentHeight: 1_600)
            let detail = PlainChromeStateContentController(contentHeight: 1_600)
            let navigation = UINavigationController(rootViewController: root)
            navigation.tabBarItem = UITabBarItem(
                title: "UIKit",
                image: UIImage(systemName: "square.stack"),
                selectedImage: UIImage(systemName: "square.stack.fill")
            )
            let fixture = makeFixture(style: style, controllers: [navigation])

            XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === root.scrollView)
            if style == .legacy {
                root.scrollView.contentOffset.y = maximumOffset(of: root.scrollView)
                XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)
            } else {
                fixture.tabs.setTabBarMinimized(true, transition: .immediate)
                XCTAssertTrue(fixture.tabs.isTabBarMinimized)
            }

            navigation.pushViewController(detail, animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.10))
            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === detail.scrollView,
                "UIKit push did not rebind for \(style)"
            )
            if style == .legacy {
                detail.scrollView.contentOffset.y = 80
                XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, true)
            } else {
                XCTAssertTrue(
                    fixture.tabs.isTabBarMinimized,
                    "Pushing a screen reset the shared minimized endpoint for \(style)"
                )
                fixture.tabs.setTabBarMinimized(false, transition: .immediate)
            }

            navigation.popViewController(animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.10))
            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === root.scrollView,
                "UIKit pop did not restore the source for \(style)"
            )
            if style == .legacy {
                XCTAssertEqual(fixture.tabs.legacyScrollEdgeChromeVisibleForTesting, false)
            } else {
                XCTAssertFalse(
                    fixture.tabs.isTabBarMinimized,
                    "Popping a screen restored a stale per-screen endpoint for \(style)"
                )
            }
            fixture.window.isHidden = true
        }
    }

    func testNestedUIKitPageControllerRebindsPlainPagesAcrossStyles() {
        for style in [
            AetherAppearanceStyle.legacy,
            .liquidGlassV1,
            .liquidGlassV2
        ] {
            let first = PlainChromeStateContentController(contentHeight: 1_600)
            let second = PlainChromeStateContentController(contentHeight: 1_600)
            let pages = UIPageViewController(
                transitionStyle: .scroll,
                navigationOrientation: .horizontal
            )
            pages.setViewControllers([first], direction: .forward, animated: false)
            pages.tabBarItem = UITabBarItem(
                title: "Pages",
                image: UIImage(systemName: "rectangle.on.rectangle"),
                selectedImage: UIImage(systemName: "rectangle.on.rectangle.fill")
            )
            let fixture = makeFixture(style: style, controllers: [pages])

            XCTAssertTrue(fixture.tabs.observedChromeScrollViewForTesting === first.scrollView)
            pages.setViewControllers([second], direction: .forward, animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            XCTAssertTrue(
                fixture.tabs.observedChromeScrollViewForTesting === second.scrollView,
                "UIKit page replacement did not rebind for \(style)"
            )
            fixture.window.isHidden = true
        }
    }

    func testNavigationAnimationUsesActualSurfaceStyleInsteadOfTabStyle() throws {
        let content = ChromeStateContentController(style: .legacy, contentHeight: 1_600)
        let fixture = makeFixture(style: .liquidGlassV1, controllers: [content])
        defer { fixture.window.isHidden = true }
        let bar = try XCTUnwrap(content.navigationBarView as? NavigationBarImpl)

        content.scrollView.contentOffset.y = 16

        XCTAssertEqual(bar.presentationData.theme.appearanceStyle, .legacy)
        XCTAssertEqual(bar.lastScrollEdgeTransitionForTesting?.isAnimated, true)
    }

    private func makeFixture(
        style: AetherAppearanceStyle,
        controllers: [UIViewController]
    ) -> (window: UIWindow, tabs: AetherTabBarController) {
        let size = CGSize(width: 390, height: 844)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let tabs = AetherAppearance.withRuntimeCurrent(
            AetherAppearance(style: style)
        ) {
            AetherTabBarController()
        }
        tabs.setControllers(controllers, selectedIndex: 0)
        tabs.updateAppearance(AetherAppearance(style: style))
        window.rootViewController = tabs
        window.isHidden = false
        tabs.loadViewIfNeeded()
        tabs.view.frame = window.bounds
        tabs.containerLayoutUpdated(
            ContainerViewLayout(
                size: size,
                safeInsets: .zero,
                additionalInsets: .zero
            ),
            transition: .immediate
        )
        tabs.view.layoutIfNeeded()
        tabs.invalidateTabBarMinimizeScrollView()
        return (window, tabs)
    }

    private func maximumOffset(of scrollView: UIScrollView) -> CGFloat {
        max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
    }
}

@MainActor
private final class ChromeStateContentController: AetherViewController {
    let scrollView = UIScrollView()
    private let contentHeight: CGFloat

    init(style: AetherAppearanceStyle, contentHeight: CGFloat) {
        self.contentHeight = contentHeight
        let presentationData = AetherAppearance.withRuntimeCurrent(
            AetherAppearance(style: style)
        ) {
            NavigationBarPresentationData.aetherAppearance()
        }
        super.init(navigationBarPresentationData: presentationData)
        tabBarItem = UITabBarItem(
            title: "Screen",
            image: UIImage(systemName: "circle"),
            selectedImage: UIImage(systemName: "circle.fill")
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var primaryScrollViewForChrome: UIScrollView? {
        scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        scrollView.contentSize = CGSize(
            width: max(1, view.bounds.width),
            height: contentHeight
        )
    }
}

@MainActor
private final class PlainChromeStateContentController: UIViewController {
    let scrollView = UIScrollView()
    private let contentHeight: CGFloat

    init(contentHeight: CGFloat) {
        self.contentHeight = contentHeight
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        scrollView.contentSize = CGSize(
            width: max(1, view.bounds.width),
            height: contentHeight
        )
    }
}
