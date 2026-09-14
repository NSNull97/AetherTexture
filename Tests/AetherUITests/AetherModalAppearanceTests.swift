import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherModalAppearanceTests: XCTestCase {
    func testExplicitLegacyResolvesBeforeSurfaceAndSourceAnimatorAllocation() throws {
        let modal = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherModalController(appearanceStyle: .legacy)
        }
        modal.loadViewIfNeeded()

        XCTAssertEqual(modal.appearanceStyleForTesting, .legacy)
        XCTAssertFalse(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertEqual(modal.legacyModalBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertFalse(containsNativeGlassEffect(in: modal.view))

        let source = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        let transition = AetherModalSourceTransition(sourceView: source)
        XCTAssertNil(transition.makePresentationAnimator(for: modal))
        XCTAssertNil(transition.makeDismissalAnimator(for: modal))
        XCTAssertFalse(transition.hasActiveLiquidTransitionStateForTesting)
    }

    func testControllerLocalLegacyOverrideIsResolvedBeforeViewLoading() {
        let modal = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            ModalLocalLegacyOverrideController()
        }

        XCTAssertFalse(modal.isViewLoaded)
        XCTAssertEqual(modal.appearanceStyleForTesting, .legacy)
        modal.loadViewIfNeeded()

        XCTAssertEqual(modal.appearanceStyleForTesting, .legacy)
        XCTAssertFalse(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertEqual(modal.legacyModalBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertFalse(containsNativeGlassEffect(in: modal.view))
    }

    func testExplicitLegacyNavigationModalPropagatesBeforeHostedNavigationLoads() {
        let modal = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherModalNavigationController(
                rootViewController: AetherViewController(),
                appearanceStyle: .legacy
            )
        }

        XCTAssertFalse(modal.internalNavigationController.isViewLoaded)
        modal.loadViewIfNeeded()

        XCTAssertEqual(modal.appearanceStyleForTesting, .legacy)
        XCTAssertFalse(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertTrue(modal.internalNavigationController.isViewLoaded)
        XCTAssertFalse(containsNativeGlassEffect(in: modal.view))
    }

    func testInheritedLiquidSurfaceSwitchesToLegacyWithoutRetainingGlassOrFooterEdge() {
        let modal = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            let modal = AetherModalController()
            modal.loadViewIfNeeded()
            return modal
        }
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }

        modal.view.frame = CGRect(x: 0, y: 0, width: 390, height: 640)
        modal.footerView = UIView()
        modal.footerHeight = 56
        modal.view.setNeedsLayout()
        modal.view.layoutIfNeeded()

        let contentIdentity = modal.contentView
        XCTAssertEqual(modal.appearanceStyleForTesting, .liquidGlassV1)
        XCTAssertTrue(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertTrue(modal.hasFooterLiquidEdgeEffectForTesting)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)

        XCTAssertEqual(modal.appearanceStyleForTesting, .legacy)
        XCTAssertFalse(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertEqual(modal.legacyModalBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertFalse(modal.hasFooterLiquidEdgeEffectForTesting)
        XCTAssertFalse(containsNativeGlassEffect(in: modal.view))
        XCTAssertTrue(modal.contentView === contentIdentity)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV2, animated: false)
        XCTAssertEqual(modal.appearanceStyleForTesting, .liquidGlassV2)
        XCTAssertTrue(modal.hasLiquidModalSurfaceForTesting)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)
        XCTAssertFalse(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertFalse(containsNativeGlassEffect(in: modal.view))
    }

    func testExplicitLiquidGenerationsRemainPinnedAcrossGlobalLegacyChange() {
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }

        for style in [AetherAppearanceStyle.liquidGlassV1, .liquidGlassV2] {
            let modal = AetherAppearance.withRuntimeCurrent(.legacy) {
                let modal = AetherModalController(appearanceStyle: style)
                modal.loadViewIfNeeded()
                return modal
            }
            let source = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
            let transition = AetherModalSourceTransition(sourceView: source)

            XCTAssertEqual(modal.appearanceStyleForTesting, style)
            XCTAssertTrue(modal.hasLiquidModalSurfaceForTesting)
            XCTAssertNotNil(transition.makePresentationAnimator(for: modal))
            XCTAssertNotNil(transition.makeDismissalAnimator(for: modal))

            AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)

            XCTAssertEqual(modal.appearanceStyleForTesting, style)
            XCTAssertTrue(modal.hasLiquidModalSurfaceForTesting)
        }
    }

    func testLiveLegacySwitchFinishesActiveSourceMorphAndReleasesItsDriver() throws {
        let (window, source, transitionContainer) = makeTransitionWindow()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            window.isHidden = true
        }

        let modal = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            let modal = AetherModalController()
            modal.loadViewIfNeeded()
            return modal
        }
        let transition = AetherModalSourceTransition(
            sourceView: source,
            configuration: .init(presentationDuration: 10)
        )
        modal.transitionAnimation = transition

        let context = ModalPresentationTransitionContext(
            containerView: transitionContainer,
            fromController: window.rootViewController!,
            toController: modal,
            finalFrame: CGRect(x: 8, y: 220, width: 374, height: 624)
        )
        let animator = try XCTUnwrap(transition.makePresentationAnimator(for: modal))
        animator.animateTransition(using: context)

        XCTAssertTrue(transition.hasActiveLiquidTransitionStateForTesting)
        XCTAssertEqual(source.alpha, 0, accuracy: 0.001)
        XCTAssertNil(context.completedTransition)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)

        XCTAssertFalse(transition.hasActiveLiquidTransitionStateForTesting)
        XCTAssertEqual(context.completedTransition, true)
        XCTAssertEqual(source.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(modal.view.alpha, 1, accuracy: 0.001)
        XCTAssertFalse(modal.hasLiquidModalSurfaceForTesting)
        XCTAssertFalse(containsNativeGlassEffect(in: transitionContainer))
    }

    private func containsNativeGlassEffect(in root: UIView) -> Bool {
        if #available(iOS 26.0, *) {
            if let effectView = root as? UIVisualEffectView,
               effectView.effect is UIGlassEffect {
                return true
            }
        }
        return root.subviews.contains(where: containsNativeGlassEffect(in:))
    }

    private func makeTransitionWindow() -> (UIWindow, UIView, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        root.view.frame = window.bounds
        window.rootViewController = root
        window.makeKeyAndVisible()

        let source = UIView(frame: CGRect(x: 24, y: 72, width: 44, height: 44))
        source.layer.cornerRadius = 22
        source.backgroundColor = .systemBlue
        root.view.addSubview(source)

        let transitionContainer = UIView(frame: root.view.bounds)
        transitionContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(transitionContainer)
        root.view.layoutIfNeeded()
        return (window, source, transitionContainer)
    }
}

@MainActor
private final class ModalLocalLegacyOverrideController: AetherModalController,
    AetherControllerAppearanceProviding {
    nonisolated func aetherAppearanceOverride(
        for context: AetherAppearanceOverrideContext
    ) -> AetherAppearanceOverride? {
        guard context.surface == .navigation else { return nil }
        return AetherAppearanceOverride(appearanceStyle: .legacy)
    }
}

@MainActor
private final class ModalPresentationTransitionContext: NSObject,
    UIViewControllerContextTransitioning {
    let containerView: UIView
    let fromController: UIViewController
    let toController: UIViewController
    let resolvedFinalFrame: CGRect

    private(set) var completedTransition: Bool?
    var transitionWasCancelled = false

    init(
        containerView: UIView,
        fromController: UIViewController,
        toController: UIViewController,
        finalFrame: CGRect
    ) {
        self.containerView = containerView
        self.fromController = fromController
        self.toController = toController
        self.resolvedFinalFrame = finalFrame
        super.init()
    }

    var isAnimated: Bool { true }
    var isInteractive: Bool { false }
    var presentationStyle: UIModalPresentationStyle { .custom }
    var targetTransform: CGAffineTransform { .identity }

    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() {
        transitionWasCancelled = true
    }
    func pauseInteractiveTransition() {}

    func completeTransition(_ didComplete: Bool) {
        completedTransition = didComplete
    }

    func viewController(
        forKey key: UITransitionContextViewControllerKey
    ) -> UIViewController? {
        switch key {
        case .from: return fromController
        case .to: return toController
        default: return nil
        }
    }

    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        switch key {
        case .from: return fromController.view
        case .to: return toController.view
        default: return nil
        }
    }

    func initialFrame(for viewController: UIViewController) -> CGRect {
        viewController === toController ? .zero : viewController.view.frame
    }

    func finalFrame(for viewController: UIViewController) -> CGRect {
        viewController === toController ? resolvedFinalFrame : viewController.view.frame
    }
}
