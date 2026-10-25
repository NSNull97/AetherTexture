import XCTest
import UIKit
import AsyncDisplayKit
@testable import AetherUI

@MainActor
final class NavigationContainerLifecycleTests: XCTestCase {
    private let size = CGSize(width: 390, height: 700)

    func testImmediatePopReplacementAndEmptyStackRemoveObsoleteViews() {
        let container = makeContainer()
        let root = AetherViewController()
        let detail = AetherViewController()
        let replacement = AetherViewController()
        container.setControllers([root, detail], animated: false)
        container.setControllers([root], animated: false)
        XCTAssertNil(detail.view.superview)
        XCTAssertTrue(root.view.superview === container)

        container.setControllers([replacement], animated: false)
        XCTAssertNil(root.view.superview)
        XCTAssertTrue(replacement.view.superview === container)
        container.setControllers([], animated: false)
        XCTAssertNil(replacement.view.superview)
        XCTAssertTrue(container.subviews.isEmpty)
    }

    func testEndObserversSeeSettledStackBeforeQueuedReplacementStarts() async {
        let root = AetherViewController()
        let detail = AetherViewController()
        let replacement = AetherViewController()
        let navigation = AetherNavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        navigation.view.frame = CGRect(origin: .zero, size: size)
        navigation.containerLayoutUpdated(layout(size), transition: .immediate)
        var didEnd = false
        navigation.bottomBarVisibilityTransitionEnded = { completed in
            didEnd = true
            XCTAssertTrue(completed)
            XCTAssertFalse(navigation.isTransitioning)
            XCTAssertTrue(navigation.topController === detail)
            XCTAssertNil(root.view.superview)
            XCTAssertNotNil(detail.view.superview)
        }

        navigation.pushViewController(detail, animated: true)
        navigation.setViewControllers([root, replacement], animated: false)
        XCTAssertTrue(navigation.topController === detail)
        await waitUntil { !navigation.isTransitioning }
        XCTAssertTrue(didEnd)
        XCTAssertTrue(navigation.topController === replacement)
        XCTAssertNil(detail.view.superview)
        XCTAssertNil(detail.parent)
    }

    func testInteractiveInstallationSurvivesReentrantLayoutAndCancelCleansTarget() async {
        let container = makeContainer()
        let root = AetherViewController()
        let detail = AetherViewController()
        container.setControllers([root, detail], animated: false)
        container.bottomBarTransitionBegan = { _, _, _, layout, _ in
            // Model the synchronous layout request raised when a screen or
            // chrome host is attached during interactive-pop installation.
            container.setControllers([root, detail], animated: false)
            container.containerLayoutUpdated(layout, transition: .immediate)
            XCTAssertTrue(container.isTransitioning)
        }
        var cancellationObserved = false
        container.bottomBarTransitionEnded = { completed in
            cancellationObserved = true
            XCTAssertFalse(completed)
            XCTAssertFalse(container.isTransitioning)
            XCTAssertNil(root.view.superview)
            XCTAssertTrue(detail.view.superview === container)
            XCTAssertEqual(detail.view.frame, container.bounds)
        }
        let pan = LifecyclePanGestureRecognizer()
        pan.mockTranslation = CGPoint(x: 80, y: 0)
        send(pan, state: .changed, to: container)
        XCTAssertTrue(root.view.superview === container)
        XCTAssertTrue(detail.view.superview === container)
        send(pan, state: .cancelled, to: container)
        let frameAtCancellation = detail.view.frame
        pan.mockTranslation = CGPoint(x: 260, y: 0)
        send(pan, state: .changed, to: container)
        XCTAssertEqual(detail.view.frame, frameAtCancellation)
        await waitUntil { !container.isTransitioning }
        XCTAssertTrue(cancellationObserved)
    }

    func testInteractiveResizeUpdatesBothPagesAndConfiguredCornersRestore() async {
        let container = makeContainer()
        let root = AetherViewController()
        let detail = AetherViewController()
        detail.loadViewIfNeeded()
        detail.view.layer.cornerRadius = 7
        container.transitionCornerRadius = 30
        container.setControllers([root, detail], animated: false)
        let pan = LifecyclePanGestureRecognizer()
        pan.mockTranslation = CGPoint(x: 117, y: 0)
        send(pan, state: .changed, to: container)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(detail.view.cornerConfiguration, .uniformEdges(topRadius: .fixed(30), bottomRadius: .fixed(30)))
        } else {
            XCTAssertEqual(detail.view.layer.cornerRadius, 30)
        }
        // The page follows the finger (directly, or through the tracking
        // spring when one is configured).
        await waitUntil { abs(detail.view.frame.minX - 117) < 0.05 }

        let resized = CGSize(width: 500, height: 480)
        container.frame.size = resized
        container.containerLayoutUpdated(layout(resized), transition: .immediate)
        XCTAssertEqual(detail.view.frame.minX, 150, accuracy: 0.2)
        XCTAssertEqual(root.view.frame.minX, -105, accuracy: 0.2)
        XCTAssertEqual(root.view.bounds.size, resized)
        XCTAssertEqual(detail.view.bounds.size, resized)

        send(pan, state: .cancelled, to: container)
        await waitUntil { !container.isTransitioning }
        XCTAssertEqual(detail.view.layer.cornerRadius, 7)
        XCTAssertEqual(detail.view.frame, container.bounds)
    }

    func testIndependentBottomCornersKeepExpandedPageSquareAndRestoreOnCancel() async {
        let container = makeContainer()
        let root = AetherViewController()
        let detail = AetherViewController()
        detail.loadViewIfNeeded()
        let originalMask = CALayer()
        detail.view.layer.mask = originalMask
        detail.view.layer.cornerRadius = 7
        detail.view.clipsToBounds = false
        if #available(iOS 26.0, *) {
            detail.view.cornerConfiguration = .uniformEdges(topRadius: .fixed(9), bottomRadius: .fixed(5))
        }
        container.transitionCornerRadius = 34
        container.transitionBottomCornerRadius = 0
        container.setControllers([root, detail], animated: false)
        let pan = LifecyclePanGestureRecognizer()
        pan.mockTranslation = CGPoint(x: 100, y: 0)
        send(pan, state: .changed, to: container)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(detail.view.cornerConfiguration, .uniformEdges(topRadius: .fixed(34), bottomRadius: .fixed(0)))
            XCTAssertNil(detail.view.layer.mask)
        } else {
            let path = (detail.view.layer.mask as? CAShapeLayer)?.path
            XCTAssertTrue(path?.contains(CGPoint(x: 1, y: size.height - 1)) == true)
            XCTAssertFalse(path?.contains(CGPoint(x: 1, y: 1)) == true)
        }
        container.transitionBottomCornerRadius = 12
        if #available(iOS 26.0, *) {
            XCTAssertEqual(detail.view.cornerConfiguration, .uniformEdges(topRadius: .fixed(34), bottomRadius: .fixed(12)))
        }
        send(pan, state: .cancelled, to: container)
        await waitUntil { !container.isTransitioning }
        XCTAssertTrue(detail.view.layer.mask === originalMask)
        XCTAssertEqual(detail.view.layer.cornerRadius, 7)
        XCTAssertFalse(detail.view.clipsToBounds)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(detail.view.cornerConfiguration, .uniformEdges(topRadius: .fixed(9), bottomRadius: .fixed(5)))
        }
    }

    func testTransitionTitlesAreRenderedBeforeSharedTitleIsHidden() {
        let root = AetherViewController()
        root.navigationItem.title = "Create playlist"
        let detail = AetherViewController()
        detail.navigationItem.title = "Choose tracks"
        let navigation = AetherNavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        navigation.view.frame = CGRect(origin: .zero, size: size)
        navigation.containerLayoutUpdated(layout(size), transition: .immediate)
        navigation.pushViewController(detail, animated: true)

        for (controller, title) in [(root, "Create playlist"), (detail, "Choose tracks")] {
            let bar = controller.view.subviews.compactMap { $0 as? NavigationBarImpl }.first
            XCTAssertNotNil(bar)
            let text = bar.flatMap { titleNode(in: $0, text: title) }
            XCTAssertNotNil(text)
            XCTAssertNotNil(text?.layer.contents, "The first transition frame must already have rendered title pixels")
        }
    }

    func testInteractiveCompletionDoesNotRestoreStackEchoedByLayout() async {
        let container = makeContainer()
        let root = AetherViewController()
        let detail = AetherViewController()
        container.setControllers([root, detail], animated: false)
        let pan = LifecyclePanGestureRecognizer()
        pan.mockTranslation = CGPoint(x: 375, y: 0)
        send(pan, state: .changed, to: container)
        container.setControllers([root, detail], animated: false)
        container.containerLayoutUpdated(layout(size), transition: .immediate)
        var completed = false
        container.bottomBarTransitionEnded = { didComplete in
            completed = didComplete
            XCTAssertFalse(container.isTransitioning)
            XCTAssertTrue(container.topController === root)
            XCTAssertNil(detail.view.superview)
        }
        send(pan, state: .ended, to: container)
        await waitUntil { !container.isTransitioning }
        XCTAssertTrue(completed)
        XCTAssertTrue(container.topController === root)
        XCTAssertEqual(container.controllers.count, 1)
        XCTAssertNil(detail.view.superview)
    }

    func testProgrammaticPopResizesOutgoingControllerUntilRemoval() async {
        let container = makeContainer()
        let root = LifecycleLayoutController()
        let detail = LifecycleLayoutController()
        container.setControllers([root, detail], animated: false)
        container.setControllers([root], animated: true)
        let resized = CGSize(width: 500, height: 480)
        container.frame.size = resized
        container.containerLayoutUpdated(layout(resized), transition: .immediate)
        XCTAssertEqual(detail.lastLayoutSize, resized)
        XCTAssertEqual(detail.view.bounds.size, resized)
        XCTAssertEqual(root.view.bounds.size, resized)
        await waitUntil { !container.isTransitioning }
        XCTAssertNil(detail.view.superview)
        XCTAssertEqual(root.view.frame, container.bounds)
    }

    func testModalPageBackingPreservesOpaqueColorAndReleasesRemovedPage() {
        let root = AetherViewController()
        root.loadViewIfNeeded()
        root.view.backgroundColor = .clear
        let navigation = AetherNavigationController(rootViewController: root)
        navigation.pageBackgroundColor = .blue
        navigation.loadViewIfNeeded()
        navigation.view.frame = CGRect(origin: .zero, size: size)
        navigation.containerLayoutUpdated(layout(size), transition: .immediate)
        let rootBacking = root.view.subviews.first
        XCTAssertEqual(rootBacking?.backgroundColor, .blue)
        XCTAssertEqual(rootBacking?.frame, root.view.bounds)

        let detail = AetherViewController()
        detail.loadViewIfNeeded()
        detail.view.backgroundColor = .red
        navigation.pushViewController(detail, animated: false)
        XCTAssertEqual(detail.view.backgroundColor, .red)
        XCTAssertEqual(detail.view.subviews.first?.backgroundColor, .clear)
        let detailBacking = detail.view.subviews.first
        navigation.popViewController(animated: false)
        XCTAssertNil(detailBacking?.superview)
        navigation.pageBackgroundColor = nil
        XCTAssertNil(rootBacking?.superview)
    }

    private func makeContainer() -> NavigationContainer {
        let container = NavigationContainer(frame: CGRect(origin: .zero, size: size))
        container.containerLayoutUpdated(layout(size), transition: .immediate)
        return container
    }

    private func titleNode(in view: UIView, text: String) -> ASTextNode? {
        if let node = ASViewToDisplayNode(view) as? ASTextNode, node.attributedText?.string == text {
            return node
        }
        return view.subviews.lazy.compactMap { self.titleNode(in: $0, text: text) }.first
    }

    private func layout(_ size: CGSize) -> ContainerViewLayout {
        ContainerViewLayout(size: size, safeInsets: .zero, additionalInsets: .zero, statusBarHeight: 0)
    }

    private func send(_ pan: LifecyclePanGestureRecognizer, state: UIGestureRecognizer.State, to container: NavigationContainer) {
        pan.mockState = state
        container.perform(NSSelectorFromString("panGesture:"), with: pan)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition())
    }
}

private final class LifecyclePanGestureRecognizer: UIPanGestureRecognizer {
    var mockState: UIGestureRecognizer.State = .possible
    var mockTranslation = CGPoint.zero

    override var state: UIGestureRecognizer.State {
        get { mockState }
        set { mockState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { mockTranslation }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}

private final class LifecycleLayoutController: AetherViewController {
    var lastLayoutSize: CGSize?

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        lastLayoutSize = layout.size
        super.containerLayoutUpdated(layout, transition: transition)
    }
}
