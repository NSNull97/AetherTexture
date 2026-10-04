import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NavigationChromePendingUpdateTests: XCTestCase {
    func testQueuedImmediateReplacementUpdatesSharedBarBeforePresentingFinalController() {
        let root = AetherViewController()
        root.navigationBarItem.title = "Root"
        let pushed = AetherViewController()
        pushed.navigationBarItem.title = "Pushed"
        let replacement = PendingChromeLayoutProbeController()
        replacement.navigationBarItem.title = "Replacement"
        let navigation = AetherNavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.view.frame = window.bounds
        navigation.containerLayoutUpdated(
            ContainerViewLayout(
                size: window.bounds.size,
                safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
                additionalInsets: .zero,
                statusBarHeight: 47
            ),
            transition: .immediate
        )
        navigation.view.layoutIfNeeded()

        var firstReplacementLayoutUsesOwnItem: Bool?
        replacement.willApplyLayout = { [weak navigation, weak replacement] in
            guard firstReplacementLayoutUsesOwnItem == nil,
                  let navigation, let replacement else { return }
            firstReplacementLayoutUsesOwnItem = navigation.navigationBar.item === replacement.navigationBarItem
        }

        navigation.pushViewController(pushed, animated: true)
        XCTAssertTrue(navigation.isTransitioning)
        navigation.setViewControllers([root, replacement], animated: false)

        let deadline = Date().addingTimeInterval(2)
        while navigation.isTransitioning && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertFalse(navigation.isTransitioning)
        XCTAssertTrue(navigation.topController === replacement)
        XCTAssertEqual(
            firstReplacementLayoutUsesOwnItem,
            true,
            "A queued immediate replacement must install its bar before content layout, without relying on a later UIKit layout"
        )
        XCTAssertTrue(navigation.navigationBar.item === replacement.navigationBarItem)
        XCTAssertTrue(replacement.navigationBarView === navigation.navigationBar)
    }
}

@MainActor
private final class PendingChromeLayoutProbeController: AetherViewController {
    var willApplyLayout: (() -> Void)?

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        willApplyLayout?()
        super.containerLayoutUpdated(layout, transition: transition)
    }
}
