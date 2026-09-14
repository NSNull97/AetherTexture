import XCTest
import UIKit
@testable import AetherUI

final class NavigationContainerLayoutProviderTests: XCTestCase {
    private final class LayoutProbeController: AetherViewController {
        var receivedLayouts: [ContainerViewLayout] = []

        override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
            receivedLayouts.append(layout)
            super.containerLayoutUpdated(layout, transition: transition)
        }
    }

    private final class InteractivePopDisabledController: AetherViewController {
        override var interactiveNavivationGestureEdgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth? {
            return .constant(0.0)
        }
    }

    private final class TransitionProbeAccessoryView: NavigationBarContentView {
        var receivedTransitions: [ContainedViewLayoutTransition] = []

        override var nominalHeight: CGFloat {
            return 36.0
        }

        override var mode: NavigationBarContentMode {
            return .expansion
        }

        override func updateLayout(
            size: CGSize,
            leftInset: CGFloat,
            rightInset: CGFloat,
            transition: ContainedViewLayoutTransition
        ) -> CGSize {
            receivedTransitions.append(transition)
            return CGSize(width: size.width, height: nominalHeight)
        }
    }

    func testNavigationTransitionDurationsMatchLiquidGlassV1Storyboard() {
        let pushTransition = NavigationTransitionCoordinator.nonInteractiveCompletionTransition(direction: .push)
        let popTransition = NavigationTransitionCoordinator.nonInteractiveCompletionTransition(direction: .pop)

        XCTAssertEqual(pushTransition.duration, AetherMotion.navigation.duration, accuracy: 0.001)
        XCTAssertEqual(popTransition.duration, AetherMotion.navigation.duration, accuracy: 0.001)

        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let topView = UIView(frame: container.bounds)
        let bottomView = UIView(frame: container.bounds)
        let coordinator = NavigationTransitionCoordinator(
            container: container,
            direction: .pop,
            topView: topView,
            bottomView: bottomView,
            topBar: nil,
            bottomBar: nil,
            isInteractive: true
        )

        coordinator.updateProgress(0.5, transition: .immediate, completion: {})
        XCTAssertEqual(coordinator.cancelTransition.duration, AetherMotion.navigation.duration, accuracy: 0.001)
        XCTAssertLessThan(coordinator.cancelTransition(velocity: -1200.0).duration, AetherMotion.navigation.duration)
        XCTAssertEqual(coordinator.cancelTransition(velocity: 1200.0).duration, AetherMotion.navigation.duration, accuracy: 0.001)
        XCTAssertEqual(coordinator.completionTransition(velocity: 0.0).duration, AetherMotion.navigation.duration, accuracy: 0.001)
        XCTAssertLessThan(coordinator.completionTransition(velocity: 1200.0).duration, AetherMotion.navigation.duration)

        coordinator.updateProgress(0.85, transition: .immediate, completion: {})
        let lightReleaseDuration = coordinator.completionTransition(velocity: 1000.0).duration
        XCTAssertGreaterThanOrEqual(lightReleaseDuration, 0.20)
        XCTAssertLessThan(lightReleaseDuration, AetherMotion.navigation.duration)

        coordinator.updateProgress(0.85, transition: .immediate, completion: {})
        let strongReleaseDuration = coordinator.completionTransition(velocity: 1600.0).duration
        XCTAssertGreaterThanOrEqual(strongReleaseDuration, 0.20)
        XCTAssertLessThanOrEqual(strongReleaseDuration, lightReleaseDuration)
        XCTAssertLessThan(strongReleaseDuration, AetherMotion.navigation.duration)
    }

    func testAnimatedNavigationTransitionRestoresSharedBarAndAccessoryOwnership() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let root = LayoutProbeController()
        root.topBarAccessory = TransitionProbeAccessoryView()
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds
        navigationController.containerLayoutUpdated(
            ContainerViewLayout(
                size: window.bounds.size,
                safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
                additionalInsets: .zero,
                statusBarHeight: 47.0
            ),
            transition: .immediate
        )

        let target = LayoutProbeController()
        let targetAccessory = TransitionProbeAccessoryView()
        target.topBarAccessory = targetAccessory
        navigationController.pushViewController(target, animated: true)

        waitForCondition(description: "push settles") {
            target.navigationBarView != nil
                && root.navigationBarView == nil
                && targetAccessory.superview != nil
        }

        XCTAssertNotNil(target.navigationBarView)
        XCTAssertNil(root.navigationBarView)
        XCTAssertNotNil(targetAccessory.superview)
        if let targetBar = target.navigationBarView {
            XCTAssertTrue(targetAccessory.isDescendant(of: targetBar))
        }

        _ = navigationController.popViewController(animated: true)
        waitForCondition(description: "pop settles") {
            root.navigationBarView != nil && target.navigationBarView == nil
        }

        XCTAssertNotNil(root.navigationBarView)
        XCTAssertNil(target.navigationBarView)
        if let rootBar = root.navigationBarView {
            XCTAssertTrue(root.topBarAccessory?.isDescendant(of: rootBar) ?? false)
        }
        window.isHidden = true
    }

    func testNonInteractivePushAndPopAnimateSharedButtonChrome() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Navigation chrome animation is disabled with Reduce Motion")
        }

        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let root = LayoutProbeController()
        root.navigationBarItem.leftBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil)
        ]
        root.navigationBarItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        ]

        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds
        navigationController.containerLayoutUpdated(
            ContainerViewLayout(
                size: window.bounds.size,
                safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
                additionalInsets: .zero,
                statusBarHeight: 47.0
            ),
            transition: .immediate
        )

        let details = LayoutProbeController(
            navigationBarPresentationData: NavigationBarPresentationData(
                theme: .liquidGlass(
                    overallDarkAppearance: true,
                    buttonColor: .white,
                    primaryTextColor: .white,
                    edgeEffectColor: .clear,
                    glassStyle: .clear
                )
            )
        )
        navigationController.pushViewController(details, animated: true)

        let pushChromeStarted = expectation(description: "push button chrome starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            let bar = navigationController.navigationBar as! NavigationBarImpl
            let groups = Self.descendants(
                of: GlassControlGroup.self,
                in: bar.debugButtonLayer
            )
            let activeGroups = groups.filter {
                !$0.isHidden && $0.alpha > 0.01 && !$0.items.isEmpty && $0.bounds.width > 0.0
            }
            let pulsingGroup = activeGroups.first { $0.sizeMorphPulseAnimationForTesting != nil }
            XCTAssertNotNil(pulsingGroup)
            let buttons = activeGroups.flatMap { Self.descendants(of: UIButton.self, in: $0) }
            let materializingButton = buttons.first {
                $0.layer.opacity >= 0.49
                    && $0.layer.animation(forKey: GlassControlGroup.contentMaterializationOpacityKey) != nil
            }
            XCTAssertNotNil(
                materializingButton,
                "Push must materialize or dematerialize navbar button content"
            )
            pushChromeStarted.fulfill()
        }
        wait(for: [pushChromeStarted], timeout: 1.0)

        waitForCondition(description: "push transition settles") {
            !navigationController.isTransitioning
        }

        _ = navigationController.popViewController(animated: true)
        let popChromeStarted = expectation(description: "pop button chrome starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            let bar = navigationController.navigationBar as! NavigationBarImpl
            let groups = Self.descendants(
                of: GlassControlGroup.self,
                in: bar.debugButtonLayer
            )
            let activeGroups = groups.filter {
                !$0.isHidden && $0.alpha > 0.01 && !$0.items.isEmpty && $0.bounds.width > 0.0
            }
            let pulsingGroup = activeGroups.first { $0.sizeMorphPulseAnimationForTesting != nil }
            XCTAssertNotNil(pulsingGroup)
            let buttons = activeGroups.flatMap { Self.descendants(of: UIButton.self, in: $0) }
            let materializingButton = buttons.first {
                $0.layer.opacity >= 0.49
                    && $0.layer.animation(forKey: GlassControlGroup.contentMaterializationOpacityKey) != nil
            }
            XCTAssertNotNil(
                materializingButton,
                "Pop must materialize or dematerialize navbar button content"
            )
            popChromeStarted.fulfill()
        }
        wait(for: [popChromeStarted], timeout: 1.0)

        window.isHidden = true
    }

    func testNonInteractivePushAndPopAnimateCustomButtonsWithoutReparentingThem() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Navigation chrome animation is disabled with Reduce Motion")
        }

        let presentationData = NavigationBarPresentationData(
            theme: .liquidGlass(
                overallDarkAppearance: true,
                buttonColor: .white,
                primaryTextColor: .white,
                edgeEffectColor: .clear,
                glassStyle: .clear
            )
        )
        let root = LayoutProbeController(navigationBarPresentationData: presentationData)
        let rootButton = UIButton(type: .system)
        rootButton.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 44.0)
        rootButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        root.navigationBarItem.rightBarButtonItems = [UIBarButtonItem(customView: rootButton)]

        let details = LayoutProbeController(navigationBarPresentationData: presentationData)
        let detailsButton = UIButton(type: .system)
        detailsButton.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 44.0)
        detailsButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        details.navigationBarItem.rightBarButtonItems = [UIBarButtonItem(customView: detailsButton)]

        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        defer { window.isHidden = true }

        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds
        navigationController.containerLayoutUpdated(
            ContainerViewLayout(
                size: window.bounds.size,
                safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
                additionalInsets: .zero,
                statusBarHeight: 47.0
            ),
            transition: .immediate
        )

        let bar = navigationController.navigationBar as! NavigationBarImpl
        XCTAssertTrue(rootButton.isDescendant(of: bar.debugButtonLayer))

        navigationController.pushViewController(details, animated: true)

        // A transition-only title bar must never take ownership of either
        // caller-provided custom view. Both live in the shared button layer
        // while the old one dematerializes and the new one materializes.
        XCTAssertTrue(rootButton.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(detailsButton.isDescendant(of: bar.debugButtonLayer))
        assertCustomButtonTransitionAnimations(on: rootButton, appearing: false)
        assertCustomButtonTransitionAnimations(on: detailsButton, appearing: true)

        waitForCondition(description: "custom button push settles") {
            !navigationController.isTransitioning
        }
        XCTAssertNil(rootButton.superview)
        XCTAssertTrue(detailsButton.isDescendant(of: bar.debugButtonLayer))

        _ = navigationController.popViewController(animated: true)

        XCTAssertTrue(detailsButton.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(rootButton.isDescendant(of: bar.debugButtonLayer))
        assertCustomButtonTransitionAnimations(on: detailsButton, appearing: false)
        assertCustomButtonTransitionAnimations(on: rootButton, appearing: true)

        waitForCondition(description: "custom button pop settles") {
            !navigationController.isTransitioning
        }
        XCTAssertNil(detailsButton.superview)
        XCTAssertTrue(rootButton.isDescendant(of: bar.debugButtonLayer))
    }

    func testAnimatedPushRejectsAnotherPushUntilTransitionFinishes() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let root = LayoutProbeController()
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds
        navigationController.containerLayoutUpdated(
            ContainerViewLayout(
                size: window.bounds.size,
                safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
                additionalInsets: .zero,
                statusBarHeight: 47.0
            ),
            transition: .immediate
        )

        let profile = LayoutProbeController()
        let post = LayoutProbeController()
        navigationController.pushViewController(profile, animated: true)

        XCTAssertTrue(navigationController.isTransitioning)
        navigationController.pushViewController(post, animated: true)
        XCTAssertEqual(navigationController.viewControllerStack.count, 2)
        XCTAssertTrue(navigationController.topController === profile)

        waitForCondition(description: "push settles") {
            !navigationController.isTransitioning
        }
        navigationController.pushViewController(post, animated: true)
        XCTAssertEqual(navigationController.viewControllerStack.count, 3)
        XCTAssertTrue(navigationController.topController === post)

        window.isHidden = true
    }

    private func waitForCondition(
        description: String,
        timeout: TimeInterval = 12.0,
        condition: @escaping () -> Bool
    ) {
        let settled = expectation(description: description)
        var poll: (() -> Void)?
        poll = {
            if condition() {
                settled.fulfill()
                poll = nil
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    poll?()
                }
            }
        }
        poll?()
        wait(for: [settled], timeout: timeout)
        poll = nil
    }

    private func assertCustomButtonTransitionAnimations(
        on view: UIView,
        appearing: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let pulse = view.layer.animation(
            forKey: "aether.navigationButtonOverspringPulse"
        ) as? CAKeyframeAnimation else {
            XCTFail("Expected a custom navbar button pulse", file: file, line: line)
            return
        }
        XCTAssertEqual(
            pulse.duration,
            appearing
                ? AetherMotion.navigationChrome.contentAppearanceDuration
                : AetherMotion.navigationChrome.contentDisappearanceDuration,
            accuracy: 0.001,
            file: file,
            line: line
        )

        let pulseScales = (pulse.values ?? []).compactMap { value -> CGFloat? in
            guard let value = value as? NSValue else { return nil }
            return value.caTransform3DValue.m11
        }
        XCTAssertEqual(pulseScales.count, 4, file: file, line: line)
        if let minimum = pulseScales.min(), let maximum = pulseScales.max() {
            XCTAssertGreaterThan(maximum - minimum, 0.09, file: file, line: line)
            let minimumIndex = pulseScales.firstIndex(of: minimum)
            let maximumIndex = pulseScales.firstIndex(of: maximum)
            if appearing {
                XCTAssertLessThan(maximumIndex ?? .max, minimumIndex ?? .max, file: file, line: line)
            } else {
                XCTAssertLessThan(minimumIndex ?? .max, maximumIndex ?? .max, file: file, line: line)
            }
        }

        let propertyAnimations = (view.layer.animationKeys() ?? []).compactMap {
            view.layer.animation(forKey: $0) as? CAPropertyAnimation
        }
        guard let opacity = propertyAnimations.first(where: { $0.keyPath == "opacity" }) else {
            XCTFail("Expected a custom navbar button opacity fade", file: file, line: line)
            return
        }
        XCTAssertEqual(pulse.duration, opacity.duration, accuracy: 0.001, file: file, line: line)

        #if !APPSTORE_SAFE
        guard let blur = propertyAnimations.first(where: {
            $0.keyPath?.contains(ObfuscatedSymbols.gaussianBlur) == true
        }) as? CABasicAnimation else {
            XCTFail("Expected a custom navbar button blur fade", file: file, line: line)
            return
        }
        XCTAssertEqual(pulse.duration, blur.duration, accuracy: 0.001, file: file, line: line)
        guard let blurFrom = blur.fromValue as? NSNumber,
              let blurTo = blur.toValue as? NSNumber else {
            XCTFail("Expected explicit custom navbar button blur endpoints", file: file, line: line)
            return
        }
        XCTAssertEqual(
            blurFrom.doubleValue,
            Double(appearing ? AetherMotion.navigationChrome.contentBlurRadius : 0.0),
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            blurTo.doubleValue,
            Double(appearing ? 0.0 : AetherMotion.navigationChrome.contentBlurRadius),
            accuracy: 0.001,
            file: file,
            line: line
        )
        #endif
    }

    func testIncomingPushReceivesControllerSpecificLayoutAtTransitionStart() {
        let source = LayoutProbeController()
        let target = LayoutProbeController()
        let container = NavigationContainer(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let baseLayout = ContainerViewLayout(
            size: CGSize(width: 320.0, height: 640.0),
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            additionalInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: 69.0, right: 0.0),
            statusBarHeight: 47.0
        )

        container.layoutForController = { controller, layout in
            var additionalInsets = layout.additionalInsets
            if controller === target {
                additionalInsets.bottom = 0.0
            }
            return layout.withUpdatedAdditionalInsets(additionalInsets)
        }

        container.setControllers([source], animated: false)
        container.containerLayoutUpdated(baseLayout, transition: .immediate)
        target.receivedLayouts.removeAll()

        container.setControllers([source, target], animated: true)

        guard let firstTargetLayout = target.receivedLayouts.first else {
            XCTFail("Incoming controller did not receive an initial layout")
            return
        }
        XCTAssertEqual(firstTargetLayout.additionalInsets.bottom, 0.0, accuracy: 0.5)
        XCTAssertEqual(target.view.frame.minX, baseLayout.size.width, accuracy: 0.5)
    }

    func testNonInteractivePushUsesTargetBottomBarSafeAreaImmediately() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let root = LayoutProbeController()
        root.displayNavigationBar = false
        let navigationController = AetherNavigationController(rootViewController: root)
        let tabBarController = AetherTabBarController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        window.rootViewController = tabBarController
        window.isHidden = false
        tabBarController.loadViewIfNeeded()
        tabBarController.view.frame = window.bounds
        tabBarController.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )

        XCTAssertGreaterThan(tabBarController.additionalSafeAreaInsets.bottom, 60.0)

        let target = LayoutProbeController()
        target.displayNavigationBar = false
        target.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(target, animated: true)

        XCTAssertEqual(tabBarController.additionalSafeAreaInsets.bottom, 0.0, accuracy: 0.5)
        XCTAssertEqual(target.receivedLayouts.first?.additionalInsets.bottom ?? -1.0, 0.0, accuracy: 0.5)
        XCTAssertFalse(target.receivedLayouts.contains { $0.additionalInsets.bottom > 0.5 })

        window.isHidden = true
    }

    func testKeyboardOnlyLayoutDoesNotAnimateSharedNavigationBarChrome() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let root = LayoutProbeController()
        let accessory = TransitionProbeAccessoryView()
        root.topBarAccessory = accessory
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds

        let baseLayout = ContainerViewLayout(
            size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            statusBarHeight: 47.0
        )
        navigationController.containerLayoutUpdated(baseLayout, transition: .immediate)
        accessory.receivedTransitions.removeAll()

        let keyboardLayout = ContainerViewLayout(
            size: baseLayout.size,
            safeInsets: baseLayout.safeInsets,
            statusBarHeight: baseLayout.statusBarHeight,
            inputHeight: 291.0
        )
        navigationController.containerLayoutUpdated(
            keyboardLayout,
            transition: .animated(duration: 0.25, curve: .spring)
        )

        XCTAssertEqual(root.receivedLayouts.last?.inputHeight ?? -1.0, 291.0, accuracy: 0.5)
        XCTAssertFalse(accessory.receivedTransitions.last?.isAnimated ?? true)

        window.isHidden = true
    }

    func testBottomInsetOnlyLayoutDoesNotAnimateSharedNavigationBarChrome() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let root = LayoutProbeController()
        let accessory = TransitionProbeAccessoryView()
        root.topBarAccessory = accessory
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds

        let baseLayout = ContainerViewLayout(
            size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            additionalInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: 69.0, right: 0.0),
            statusBarHeight: 47.0
        )
        navigationController.containerLayoutUpdated(baseLayout, transition: .immediate)
        accessory.receivedTransitions.removeAll()

        let bottomAccessoryLayout = baseLayout.withUpdatedAdditionalInsets(
            UIEdgeInsets(top: 0.0, left: 0.0, bottom: 133.0, right: 0.0)
        )
        navigationController.containerLayoutUpdated(
            bottomAccessoryLayout,
            transition: .animated(duration: 0.32, curve: .easeInOut)
        )

        XCTAssertEqual(root.receivedLayouts.last?.additionalInsets.bottom ?? -1.0, 133.0, accuracy: 0.5)
        XCTAssertFalse(accessory.receivedTransitions.last?.isAnimated ?? true)

        window.isHidden = true
    }

    func testInteractivePopGestureDirectionsIncludeFullWidthRightPan() {
        let container = NavigationContainer(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        container.setControllers([AetherViewController(), AetherViewController()], animated: false)

        let directions = container.interactivePopGestureDirections(at: CGPoint(x: 160.0, y: 320.0))

        XCTAssertTrue(directions.contains(.right))
        XCTAssertTrue(directions.contains(.leftEdge))
    }

    func testInteractivePopGestureDirectionsRespectZeroWidthOptOut() {
        let container = NavigationContainer(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        container.setControllers([AetherViewController(), InteractivePopDisabledController()], animated: false)

        let directions = container.interactivePopGestureDirections(at: CGPoint(x: 1.0, y: 320.0))

        XCTAssertTrue(directions.isEmpty)
    }

    private static func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var result: [T] = []
        if let root = root as? T {
            result.append(root)
        }
        for subview in root.subviews {
            result.append(contentsOf: descendants(of: type, in: subview))
        }
        return result
    }
}
