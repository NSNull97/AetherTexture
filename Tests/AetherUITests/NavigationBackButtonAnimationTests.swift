import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NavigationBackButtonAnimationTests: XCTestCase {
    private let backID = AnyHashable(BarButtonID("left.nav.back"))

    func testAnimatedPushFromEmptyRootMaterializesBackButton() async throws {
        try await verifyEmptyRootPush(hostedInTabBar: false)
    }

    func testAnimatedPushInsideTabBarMaterializesBackButton() async throws {
        for hidesBottomBar in [false, true] {
            try await verifyEmptyRootPush(hostedInTabBar: true, hidesBottomBar: hidesBottomBar)
        }
    }

    private func verifyEmptyRootPush(hostedInTabBar: Bool, hidesBottomBar: Bool = false) async throws {
        try requireAnimations()
        let root = makeController()
        let fixture = install(root, hostedInTabBar: hostedInTabBar)
        defer { fixture.window.isHidden = true }

        let detail = makeController()
        detail.hidesBottomBarWhenPushed = hidesBottomBar
        fixture.navigation.pushViewController(detail, animated: true)
        await waitForChrome(.push)

        let bar = try sharedBar(fixture.navigation)
        let back = try backEntry(in: bar)
        assertMaterializing(back.group, button: back.button)
        fixture.navigation.containerLayoutUpdated(fixture.layout, transition: .immediate)
        assertMaterializing(back.group, button: back.button)
        await waitUntilSettled(fixture.navigation)
    }

    func testAnimatedPushFromGeneratedOrCustomLeftButtonMaterializesBack() async throws {
        try requireAnimations()
        for hostedInTabBar in [false, true] {
            for usesCustomView in [false, true] {
                let root = makeController()
                if usesCustomView {
                    let button = UIButton(type: .system)
                    button.setTitle("Root action", for: .normal)
                    button.frame = CGRect(x: 0, y: 0, width: 112, height: 44)
                    root.navigationBarItem.leftBarButtonItem = UIBarButtonItem(customView: button)
                } else {
                    root.navigationBarItem.leftBarButtonItem = item("Root action")
                }
                let fixture = install(root, hostedInTabBar: hostedInTabBar)
                defer { fixture.window.isHidden = true }

                fixture.navigation.pushViewController(makeController(), animated: true)
                await waitForChrome(.push)

                let bar = try sharedBar(fixture.navigation)
                let back = try backEntry(in: bar)
                assertMaterializing(back.group, button: back.button)
                fixture.navigation.containerLayoutUpdated(fixture.layout, transition: .immediate)
                assertMaterializing(back.group, button: back.button)
                await waitUntilSettled(fixture.navigation)
            }
        }
    }

    func testBackToBackPushKeepsBackStableWhileChangedRightButtonMaterializes() async throws {
        try requireAnimations()
        for hostedInTabBar in [false, true] {
            let fixture = install(makeController(), hostedInTabBar: hostedInTabBar)
            defer { fixture.window.isHidden = true }
            let first = makeController()
            first.navigationBarItem.rightBarButtonItem = item("Edit")
            fixture.navigation.pushViewController(first, animated: false)
            fixture.navigation.containerLayoutUpdated(fixture.layout, transition: .immediate)
            let bar = try sharedBar(fixture.navigation)
            let originalBack = try backEntry(in: bar)
            let second = makeController()
            second.navigationBarItem.rightBarButtonItem = item("Apply changes")

            fixture.navigation.pushViewController(second, animated: true)
            await waitForChrome(.push)

            let retainedBack = try backEntry(in: bar)
            XCTAssertIdentical(retainedBack.group, originalBack.group)
            XCTAssertIdentical(retainedBack.button, originalBack.button)
            assertStable(retainedBack.group, button: retainedBack.button)
            let right = try sideEntry("right", in: bar)
            assertMaterializing(right.group, button: right.button)

            fixture.navigation.containerLayoutUpdated(fixture.layout, transition: .immediate)
            assertStable(retainedBack.group, button: retainedBack.button)
            assertMaterializing(right.group, button: right.button)
            await waitUntilSettled(fixture.navigation)
        }
    }

    func testTappingActualBackButtonMaterializesChangedButtonsOnPop() async throws {
        try await verifyBackTapPop(hostedInTabBar: false)
    }

    func testTappingActualBackInsideTabBarMaterializesChangedButtonsOnPop() async throws {
        for hidesBottomBar in [false, true] {
            try await verifyBackTapPop(hostedInTabBar: true, hidesBottomBar: hidesBottomBar)
        }
    }

    private func verifyBackTapPop(hostedInTabBar: Bool, hidesBottomBar: Bool = false) async throws {
        try requireAnimations()
        let root = makeController()
        root.navigationBarItem.leftBarButtonItem = item("Cancel")
        root.navigationBarItem.rightBarButtonItem = item("Edit")
        let fixture = install(root, hostedInTabBar: hostedInTabBar)
        defer { fixture.window.isHidden = true }
        let detail = makeController()
        detail.hidesBottomBarWhenPushed = hidesBottomBar
        detail.navigationBarItem.rightBarButtonItem = item("Apply changes")
        fixture.navigation.pushViewController(detail, animated: false)
        fixture.navigation.containerLayoutUpdated(fixture.layout, transition: .immediate)
        let bar = try sharedBar(fixture.navigation)
        let back = try backEntry(in: bar)
        let button = try XCTUnwrap(back.button as? HighlightTrackingButton)
        let tap = try XCTUnwrap(button.onTap)

        // The hostless test runner does not dispatch UIControl actions through
        // UIApplication. Invoke the actual closure installed on the back cell.
        tap()

        XCTAssertTrue(fixture.navigation.topController === root)
        XCTAssertTrue(fixture.navigation.isTransitioning)
        await waitForChrome(.pop)
        XCTAssertIdentical(bar.item, root.navigationBarItem)
        let left = try sideEntry("left", in: bar)
        let right = try sideEntry("right", in: bar)
        assertMaterializing(left.group, button: left.button)
        assertMaterializing(right.group, button: right.button)

        fixture.navigation.containerLayoutUpdated(fixture.layout, transition: .immediate)
        assertMaterializing(left.group, button: left.button)
        assertMaterializing(right.group, button: right.button)
        await waitUntilSettled(fixture.navigation)
    }

    private func requireAnimations() throws {
        guard !UIAccessibility.isReduceMotionEnabled, UIView.areAnimationsEnabled else {
            throw XCTSkip("Requires navigation chrome animations")
        }
    }

    private func makeController() -> AetherViewController {
        AetherViewController(navigationBarPresentationData:
            AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
                NavigationBarPresentationData.aetherAppearance()
            }
        )
    }

    private func item(_ title: String) -> UIBarButtonItem {
        UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
    }

    private func install(_ root: AetherViewController, hostedInTabBar: Bool = false) -> (
        window: UIWindow,
        navigation: AetherNavigationController,
        layout: ContainerViewLayout
    ) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigation = AetherNavigationController(rootViewController: root)
        let host: AetherViewController
        if hostedInTabBar {
            let tabs = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
                AetherTabBarController()
            }
            navigation.tabBarItem = UITabBarItem(title: "Navigation", image: nil, tag: 0)
            tabs.setControllers([navigation], selectedIndex: 0)
            tabs.updateAppearance(.liquidGlassV2)
            host = tabs
        } else {
            host = navigation
        }
        window.rootViewController = host
        window.isHidden = false
        host.loadViewIfNeeded()
        host.view.frame = window.bounds
        let layout = ContainerViewLayout(
            size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            additionalInsets: .zero,
            statusBarHeight: 47
        )
        host.containerLayoutUpdated(layout, transition: .immediate)
        host.view.layoutIfNeeded()
        return (window, navigation, layout)
    }

    private func sharedBar(_ navigation: AetherNavigationController) throws -> NavigationBarImpl {
        try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
    }

    private func groups(in view: UIView) -> [GlassControlGroup] {
        (view as? GlassControlGroup).map { [$0] } ?? view.subviews.flatMap(groups)
    }

    private func backEntry(in bar: NavigationBarImpl) throws -> (group: GlassControlGroup, button: UIView) {
        let group = try XCTUnwrap(groups(in: bar.debugButtonLayer).first {
            $0.items.contains(where: { $0.id == backID }) && !$0.isAwaitingAnimatedRemoval
        })
        return (group, try XCTUnwrap(group.itemButton(id: backID)))
    }

    private func sideEntry(_ side: String, in bar: NavigationBarImpl) throws -> (group: GlassControlGroup, button: UIView) {
        let group = try XCTUnwrap(groups(in: bar.debugButtonLayer).first {
            !$0.isAwaitingAnimatedRemoval && !$0.isFinishingContentRemoval
                && $0.items.contains(where: {
                    ($0.id.base as? BarButtonID)?.rawValue.hasPrefix("\(side).") == true
                })
        })
        let id = try XCTUnwrap(group.items.first?.id)
        return (group, try XCTUnwrap(group.itemButton(id: id)))
    }

    private func assertMaterializing(
        _ group: GlassControlGroup,
        button: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(group.sizeMorphPulseAnimationForTesting, "Changed chrome must pulse", file: file, line: line)
        XCTAssertTrue(
            AetherContentMaterialization.isAnimating(view: button)
                || (button.layer.animation(forKey: GlassControlGroup.contentMaterializationOpacityKey) != nil
                    && button.layer.animation(forKey: GlassControlGroup.contentMaterializationBlurKey) != nil),
            "Changed content must blur and fade on both normal and public fallback renderers",
            file: file,
            line: line
        )
    }

    private func assertStable(
        _ group: GlassControlGroup,
        button: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(group.sizeMorphPulseAnimationForTesting, file: file, line: line)
        XCTAssertNil(button.layer.animation(forKey: GlassControlGroup.contentMaterializationOpacityKey), file: file, line: line)
        XCTAssertNil(button.layer.animation(forKey: GlassControlGroup.contentMaterializationBlurKey), file: file, line: line)
        XCTAssertFalse(AetherContentMaterialization.isAnimating(view: button), file: file, line: line)
    }

    private func waitForChrome(_ direction: NavigationTransitionDirection) async {
        let timing = AetherNavigationController.navigationChromeTransitionTiming(
            direction: direction,
            isInteractive: false
        )
        let started = expectation(description: "Navigation button chrome started")
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.delay + 0.04) {
            started.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
    }

    private func waitUntilSettled(_ navigation: AetherNavigationController) async {
        let settled = expectation(description: "Navigation transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + AetherMotion.navigation.duration + 0.2) {
            XCTAssertFalse(navigation.isTransitioning)
            settled.fulfill()
        }
        await fulfillment(of: [settled], timeout: 2)
    }
}
