import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NavigationEdgeEffectTransitionTests: XCTestCase {
    func testPushAndPopPreserveEachScreensEffectWhenOtherScreenHasNone() throws {
        for (glassStyle, rootHasEffect) in [
            (NavigationBarGlassStyle.default, true),
            (.default, false),
            (.strong, true),
            (.strong, false)
        ] {
            let root = EdgeScrollController(hasEffect: rootHasEffect, glassStyle: glassStyle)
            let target = EdgeScrollController(hasEffect: !rootHasEffect, glassStyle: glassStyle)
            let navigation = AetherNavigationController(rootViewController: root)
            let window = install(navigation)
            defer { window.isHidden = true }

            navigation.pushViewController(target, animated: true)
            XCTAssertTrue(navigation.isTransitioning)
            try assertTransitionEdge(in: root, visible: rootHasEffect)
            try assertTransitionEdge(in: target, visible: !rootHasEffect)
            waitUntilSettled(navigation)
            try assertSharedEdge(navigation, owner: target, visible: !rootHasEffect)

            _ = navigation.popViewController(animated: true)
            XCTAssertTrue(navigation.isTransitioning)
            try assertTransitionEdge(in: target, visible: !rootHasEffect)
            try assertTransitionEdge(in: root, visible: rootHasEffect)
            waitUntilSettled(navigation)
            try assertSharedEdge(navigation, owner: root, visible: rootHasEffect)
        }
    }

    func testScrollCallbacksUpdateTheirOwnTransitionEndpoint() throws {
        let activePage = EdgeScrollController(hasEffect: true)
        let inactivePage = EdgeScrollController(hasEffect: false)
        let root = AetherPageViewController(
            pages: [
                .init(title: "Active", viewController: activePage),
                .init(title: "Inactive", viewController: inactivePage)
            ],
            installViewPagerAsTopBarAccessory: false,
            navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass())
        )
        let target = EdgeScrollController(hasEffect: true)
        target.scrollView.contentOffset.y = 4.0
        let navigation = AetherNavigationController(rootViewController: root)
        let window = install(navigation)
        defer { window.isHidden = true }

        navigation.pushViewController(target, animated: true)
        let sourceBar = try transitionBar(in: root)
        let targetBar = try transitionBar(in: target)
        let sourceEdge = try XCTUnwrap(sourceBar.debugEdgeEffectView)
        let targetEdge = try XCTUnwrap(targetBar.debugEdgeEffectView)
        XCTAssertEqual(sourceEdge.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(targetEdge.alpha, 0.25, accuracy: 0.001)

        activePage.scrollView.contentOffset.y = 8.0
        activePage.updateNavigationBarScrollEdgeOffset(for: activePage.scrollView, transition: .immediate)
        XCTAssertEqual(sourceEdge.alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(targetEdge.alpha, 0.25, accuracy: 0.001)

        inactivePage.applyNavigationBarScrollEdgeAlpha(0.0, transition: .immediate)
        XCTAssertEqual(sourceEdge.alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(targetEdge.alpha, 0.25, accuracy: 0.001)

        target.scrollView.contentOffset.y = 12.0
        target.updateNavigationBarScrollEdgeOffset(for: target.scrollView, transition: .immediate)
        XCTAssertEqual(sourceEdge.alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(targetEdge.alpha, 0.75, accuracy: 0.001)
        waitUntilSettled(navigation)
        let shared = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
        XCTAssertEqual(try XCTUnwrap(shared.debugEdgeEffectView).alpha, 0.75, accuracy: 0.001)
    }

    func testCancelledInteractivePopRestoresSourceEffectAndRemovesTemporaryBars() throws {
        let root = EdgeScrollController(hasEffect: false)
        let top = EdgeScrollController(hasEffect: true)
        let navigation = AetherNavigationController(rootViewController: root)
        let window = install(navigation)
        defer { window.isHidden = true }
        navigation.pushViewController(top, animated: false)
        let container = try XCTUnwrap(descendants(in: navigation.view)
            .compactMap { $0 as? NavigationContainer }.first)

        // Drive the same chrome callbacks as the gesture coordinator without
        // relying on UIKit's private recognizer-state mutation in a unit test.
        container.navigationBarTransitionBegan?(.pop, top, root, layout, true)
        container.navigationBarTransitionProgress?(0.5, .immediate)
        try assertTransitionEdge(in: top, visible: true)
        try assertTransitionEdge(in: root, visible: false)
        container.navigationBarTransitionResolutionBegan?(false, .immediate)
        try assertTransitionEdge(in: top, visible: true)
        container.navigationBarTransitionEnded?(false)

        try assertSharedEdge(navigation, owner: top, visible: true)
        XCTAssertTrue(top.view.subviews.compactMap { $0 as? NavigationBarImpl }.isEmpty)
        XCTAssertTrue(root.view.subviews.compactMap { $0 as? NavigationBarImpl }.isEmpty)
    }

    private var layout: ContainerViewLayout {
        ContainerViewLayout(
            size: CGSize(width: 390.0, height: 844.0),
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            additionalInsets: .zero,
            statusBarHeight: 47.0
        )
    }

    private func install(_ navigation: AetherNavigationController) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: layout.size))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.loadViewIfNeeded()
        navigation.view.frame = window.bounds
        navigation.containerLayoutUpdated(layout, transition: .immediate)
        navigation.view.layoutIfNeeded()
        return window
    }

    private func transitionBar(in controller: AetherViewController) throws -> NavigationBarImpl {
        try XCTUnwrap(controller.view.subviews.compactMap { $0 as? NavigationBarImpl }.first)
    }

    private func assertTransitionEdge(
        in controller: AetherViewController,
        visible: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let edge = try XCTUnwrap(try transitionBar(in: controller).debugEdgeEffectView)
        XCTAssertEqual(edge.isHidden, !visible, file: file, line: line)
        XCTAssertEqual(edge.alpha, visible ? 1.0 : 0.0, accuracy: 0.001, file: file, line: line)
    }

    private func assertSharedEdge(
        _ navigation: AetherNavigationController,
        owner: AetherViewController,
        visible: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
        let edge = try XCTUnwrap(bar.debugEdgeEffectView)
        XCTAssertTrue(owner.navigationBarView === bar, file: file, line: line)
        XCTAssertTrue(edge.superview === owner.view, file: file, line: line)
        XCTAssertEqual(edge.isHidden, !visible, file: file, line: line)
        XCTAssertEqual(edge.alpha, visible ? 1.0 : 0.0, accuracy: 0.001, file: file, line: line)
    }

    private func waitUntilSettled(_ navigation: AetherNavigationController) {
        let deadline = Date().addingTimeInterval(2.0)
        while navigation.isTransitioning && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(navigation.isTransitioning)
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(in: $0) }
    }
}

@MainActor
private final class EdgeScrollController: AetherViewController {
    private let hasScroll: Bool
    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentSize = CGSize(width: 390.0, height: 1_600.0)
        return scrollView
    }()

    init(hasEffect: Bool, glassStyle: NavigationBarGlassStyle = .default) {
        hasScroll = hasEffect
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: .liquidGlass(
                edgeEffectColor: hasEffect ? .systemBackground : .clear,
                glassStyle: glassStyle
            )
        ))
        scrollView.contentOffset.y = hasEffect ? 32.0 : 0.0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var primaryScrollViewForChrome: UIScrollView? { hasScroll ? scrollView : nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        if hasScroll {
            view.insertSubview(scrollView, at: 0)
        }
    }

    override func viewDidLayoutSubviews() {
        scrollView.frame = view.bounds
        super.viewDidLayoutSubviews()
    }
}
