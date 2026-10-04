import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NavigationCustomTitleTransitionTests: XCTestCase {
    func testCustomTitlesFollowInteractivePopAndRestoreAfterCancellation() throws {
        try verifyInteractivePop(completed: false)
    }

    func testCustomTitlesFollowInteractivePopAndRestoreAfterCompletion() throws {
        try verifyInteractivePop(completed: true)
    }

    private func verifyInteractivePop(completed: Bool) throws {
        for appearance in [AetherAppearance.legacy, .liquidGlassV2] {
            let root = AetherViewController()
            let detail = AetherViewController()
            let rootTitle = makeTitle("Playlists")
            let detailTitle = makeTitle("My playlists")
            root.navigationItem.titleView = rootTitle
            detail.navigationItem.titleView = detailTitle
            let action = makeTitle("Sort")
            detail.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: action)

            let navigation = AetherNavigationController(rootViewController: root)
            navigation.updateAppearance(appearance)
            let window = install(navigation)
            defer { window.isHidden = true }
            navigation.pushViewController(detail, animated: false)
            navigation.containerLayoutUpdated(layout, transition: .immediate)
            let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
            let container = try XCTUnwrap(descendants(in: navigation.view)
                .compactMap { $0 as? NavigationContainer }.first)
            let initialTitleFrame = detailTitle.convert(detailTitle.bounds, to: navigation.view)
            let initialButtonFrame = action.convert(action.bounds, to: navigation.view)

            root.view.frame = CGRect(origin: .zero, size: layout.size)
            container.navigationBarTransitionBegan?(.pop, detail, root, layout, true)
            container.insertSubview(root.view, belowSubview: detail.view)
            let coordinator = NavigationTransitionCoordinator(
                container: container,
                direction: .pop,
                topView: detail.view,
                bottomView: root.view,
                topBar: nil,
                bottomBar: nil,
                isInteractive: true,
                progressUpdated: { progress, transition in
                    container.navigationBarTransitionProgress?(progress, transition)
                }
            )

            let sourceBar = try transitionBar(in: detail)
            let targetBar = try transitionBar(in: root)
            XCTAssertTrue(detailTitle.isDescendant(of: sourceBar.debugButtonsContainerView))
            XCTAssertTrue(rootTitle.isDescendant(of: targetBar.debugButtonsContainerView))
            XCTAssertFalse(detailTitle.isDescendant(of: bar.debugButtonLayer))
            XCTAssertEqual(detailTitle.convert(detailTitle.bounds, to: navigation.view), initialTitleFrame)
            let targetLocalFrame = rootTitle.convert(rootTitle.bounds, to: root.view)

            // Use the production screen coordinator, including a backwards
            // drag and a layout refresh while the gesture is in progress.
            for progress: CGFloat in [0.25, 0.65, 0.4, -0.05] {
                navigation.containerLayoutUpdated(layout, transition: .immediate)
                coordinator.updateProgress(progress, transition: .immediate, completion: {})
                let sourceFrame = detailTitle.convert(detailTitle.bounds, to: navigation.view)
                let targetFrame = rootTitle.convert(rootTitle.bounds, to: navigation.view)
                XCTAssertEqual(sourceFrame.minX, initialTitleFrame.minX + detail.view.frame.minX, accuracy: 0.5)
                XCTAssertEqual(targetFrame.minX, targetLocalFrame.minX + root.view.frame.minX, accuracy: 0.5)
                XCTAssertEqual(sourceFrame.size, initialTitleFrame.size)
                XCTAssertEqual(detailTitle.alpha, 1.0, accuracy: 0.001)
                XCTAssertEqual(rootTitle.alpha, 1.0, accuracy: 0.001)
                XCTAssertEqual(action.convert(action.bounds, to: navigation.view), initialButtonFrame)
            }

            container.navigationBarTransitionResolutionBegan?(completed, .immediate)
            XCTAssertTrue(detailTitle.isDescendant(of: sourceBar))
            XCTAssertTrue(rootTitle.isDescendant(of: targetBar))
            coordinator.updateProgress(completed ? 1.0 : 0.0, transition: .immediate, completion: {})
            let restoredTitle = completed ? rootTitle : detailTitle
            let settledFrame = restoredTitle.convert(restoredTitle.bounds, to: navigation.view)
            container.navigationBarTransitionEnded?(completed)

            XCTAssertTrue(restoredTitle.isDescendant(of: bar.debugButtonLayer))
            XCTAssertEqual(restoredTitle.convert(restoredTitle.bounds, to: navigation.view), settledFrame)
            XCTAssertEqual(restoredTitle.alpha, 1.0, accuracy: 0.001)
            XCTAssertTrue(restoredTitle.isUserInteractionEnabled)
            XCTAssertEqual(restoredTitle.transform, .identity)
            XCTAssertNil((completed ? detailTitle : rootTitle).superview)
            XCTAssertNil(sourceBar.superview)
            XCTAssertNil(targetBar.superview)
            XCTAssertIdentical(root.navigationItem.titleView, rootTitle)
            XCTAssertIdentical(detail.navigationItem.titleView, detailTitle)
        }
    }

    func testAnimatedPushAndPopKeepCustomTitleOnMovingScreenUntilSettled() async throws {
        let root = AetherViewController()
        root.navigationItem.title = "Library"
        let detail = AetherViewController()
        let title = makeTitle("Playlists")
        detail.navigationItem.titleView = title
        let navigation = AetherNavigationController(rootViewController: root)
        let window = install(navigation)
        defer { window.isHidden = true }
        let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)

        navigation.pushViewController(detail, animated: true)
        XCTAssertTrue(title.isDescendant(of: try transitionBar(in: detail)))
        XCTAssertFalse(title.isDescendant(of: bar.debugButtonLayer))
        await waitUntilSettled(navigation)
        XCTAssertTrue(title.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(title.alpha, 1.0, accuracy: 0.001)

        navigation.popViewController(animated: true)
        XCTAssertTrue(title.isDescendant(of: try transitionBar(in: detail)))
        XCTAssertEqual(title.alpha, 1.0, accuracy: 0.001)
        await waitUntilSettled(navigation)
        XCTAssertNil(title.superview)
        XCTAssertTrue(navigation.topController === root)
    }

    private func makeTitle(_ text: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.sizeToFit()
        return button
    }

    private var layout: ContainerViewLayout {
        ContainerViewLayout(
            size: CGSize(width: 390, height: 844),
            safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            additionalInsets: .zero,
            statusBarHeight: 47
        )
    }

    private func install(_ navigation: AetherNavigationController) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: layout.size))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.view.frame = window.bounds
        navigation.containerLayoutUpdated(layout, transition: .immediate)
        navigation.view.layoutIfNeeded()
        return window
    }

    private func transitionBar(in controller: AetherViewController) throws -> NavigationBarImpl {
        try XCTUnwrap(controller.view.subviews.compactMap { $0 as? NavigationBarImpl }.first)
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(in: $0) }
    }

    private func waitUntilSettled(_ navigation: AetherNavigationController) async {
        let deadline = Date().addingTimeInterval(3)
        while navigation.isTransitioning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(navigation.isTransitioning)
    }
}
