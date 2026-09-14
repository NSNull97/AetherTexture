import XCTest
import UIKit
@testable import AetherUI

final class AetherGooeyContextMenuTransitionTests: XCTestCase {
    func testDefaultConfigurationTracksAppearance() {
        let legacy = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .legacy)
        XCTAssertEqual(legacy.appearanceStyle, .legacy)
        XCTAssertFalse(legacy.usesLiquidGlassTransition)
        XCTAssertFalse(legacy.allowsLensingApproximation)
        XCTAssertEqual(legacy.blurIntensity, 0.0, accuracy: 0.001)
        XCTAssertEqual(legacy.highlightAlpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(legacy.connectorMaximumThickness, 0.0, accuracy: 0.001)

        let liquidGlassV1 = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .liquidGlassV1)
        XCTAssertEqual(liquidGlassV1.appearanceStyle, .liquidGlassV1)
        XCTAssertTrue(liquidGlassV1.usesLiquidGlassTransition)
        XCTAssertEqual(liquidGlassV1.glassStyle, .regular)
        XCTAssertEqual(liquidGlassV1.durationOpen, 0.58, accuracy: 0.001)
        XCTAssertEqual(liquidGlassV1.durationClose, 0.48, accuracy: 0.001)

        let liquidGlassV2 = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .liquidGlassV2)
        XCTAssertEqual(liquidGlassV2.glassStyle, .strong)
        XCTAssertGreaterThan(liquidGlassV2.strokeAlpha, liquidGlassV1.strokeAlpha)
        XCTAssertGreaterThan(liquidGlassV2.connectorMaximumThickness, liquidGlassV1.connectorMaximumThickness)
    }

    func testConfigurationPinsExplicitStyleAndSnapshotsRuntimeDefault() {
        let inherited = AetherAppearance.withRuntimeCurrent(.legacy) {
            makeConfiguration(appearanceStyle: nil)
        }
        let explicitlyPinned = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            makeConfiguration(appearanceStyle: .legacy)
        }

        XCTAssertEqual(inherited.appearanceStyle, .legacy)
        XCTAssertFalse(inherited.usesLiquidGlassTransition)
        XCTAssertEqual(explicitlyPinned.appearanceStyle, .legacy)
        XCTAssertFalse(explicitlyPinned.usesLiquidGlassTransition)

        AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            XCTAssertEqual(inherited.appearanceStyle, .legacy)
            XCTAssertFalse(inherited.usesLiquidGlassTransition)
        }
    }

    @MainActor
    func testDirectLegacyOpenAllocatesOnlyClassicUIKitAnimatorAndCancelRestoresState() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 24.0, y: 64.0, width: 44.0, height: 44.0))
        let menu = UIView(frame: CGRect(x: 96.0, y: 124.0, width: 260.0, height: 176.0))
        menu.alpha = 0.0
        menu.isUserInteractionEnabled = false
        container.addSubview(source)
        container.addSubview(menu)

        var configuration = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .legacy)
        configuration.durationOpen = 1.0
        let transition = AetherGooeyContextMenuTransition(configuration: configuration)
        var completionResult: Bool?

        AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            transition.animateOpen(
                sourceView: source,
                menuView: menu,
                containerView: container,
                placement: .below,
                completion: { completionResult = $0 }
            )
        }

        XCTAssertEqual(transition.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(transition.hasClassicAnimatorForTesting)
        XCTAssertFalse(transition.hasLiquidTransitionResourcesForTesting)
        XCTAssertFalse(transition.hasGooeyDisplayLinkForTesting)
        XCTAssertFalse(containsLiquidTransitionView(in: container))

        transition.cancel()

        XCTAssertEqual(completionResult, false)
        XCTAssertFalse(transition.hasClassicAnimatorForTesting)
        XCTAssertFalse(transition.hasLiquidTransitionResourcesForTesting)
        XCTAssertFalse(containsLiquidTransitionView(in: container))
        XCTAssertEqual(container.subviews.count, 2)
        XCTAssertEqual(source.alpha, 1.0, accuracy: 0.001)
        XCTAssertTrue(source.isUserInteractionEnabled)
        XCTAssertEqual(menu.alpha, 0.0, accuracy: 0.001)
        XCTAssertFalse(menu.isUserInteractionEnabled)
        XCTAssertEqual(menu.transform, .identity)
    }

    @MainActor
    func testDirectLegacyOpenAndCloseCompleteWithoutLiquidResources() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 24.0, y: 64.0, width: 44.0, height: 44.0))
        let menu = UIView(frame: CGRect(x: 96.0, y: 124.0, width: 260.0, height: 176.0))
        menu.alpha = 0.0
        menu.isUserInteractionEnabled = false
        container.addSubview(source)
        container.addSubview(menu)

        var configuration = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .legacy)
        configuration.durationOpen = 0.01
        configuration.durationClose = 0.01
        configuration.respectsReduceMotion = false
        let transition = AetherGooeyContextMenuTransition(configuration: configuration)

        let openExpectation = expectation(description: "classic open completes")
        transition.animateOpen(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below,
            completion: { finished in
                XCTAssertTrue(finished)
                openExpectation.fulfill()
            }
        )
        wait(for: [openExpectation], timeout: 1.0)

        XCTAssertFalse(transition.hasClassicAnimatorForTesting)
        XCTAssertFalse(transition.hasLiquidTransitionResourcesForTesting)
        XCTAssertFalse(transition.hasGooeyDisplayLinkForTesting)
        XCTAssertFalse(containsLiquidTransitionView(in: container))
        XCTAssertEqual(source.alpha, 0.0, accuracy: 0.001)
        XCTAssertFalse(source.isUserInteractionEnabled)
        XCTAssertEqual(menu.alpha, 1.0, accuracy: 0.001)
        XCTAssertTrue(menu.isUserInteractionEnabled)
        XCTAssertEqual(menu.transform, .identity)

        let closeExpectation = expectation(description: "classic close completes")
        transition.animateClose(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below,
            completion: { finished in
                XCTAssertTrue(finished)
                closeExpectation.fulfill()
            }
        )
        wait(for: [closeExpectation], timeout: 1.0)

        XCTAssertFalse(transition.hasClassicAnimatorForTesting)
        XCTAssertFalse(transition.hasLiquidTransitionResourcesForTesting)
        XCTAssertFalse(transition.hasGooeyDisplayLinkForTesting)
        XCTAssertFalse(containsLiquidTransitionView(in: container))
        XCTAssertEqual(container.subviews.count, 2)
        XCTAssertEqual(source.alpha, 1.0, accuracy: 0.001)
        XCTAssertTrue(source.isUserInteractionEnabled)
        XCTAssertEqual(menu.alpha, 0.0, accuracy: 0.001)
        XCTAssertFalse(menu.isUserInteractionEnabled)
        XCTAssertEqual(menu.transform, .identity)
    }

    @MainActor
    func testExplicitLegacyControllerSelectsClassicPathBeforeLiquidAllocation() {
        let (window, source) = makeContextMenuWindow()
        defer { window.isHidden = true }

        let controller = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            ContextMenuController(
                source: .init(view: source, cornerRadius: 22),
                items: [.action(ContextMenuActionItem(title: "Legacy action"))],
                presentationStyle: .gooey(),
                appearanceStyle: .legacy,
                hasHapticFeedback: false
            )
        }

        AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            controller.present()
        }

        XCTAssertTrue(controller.isPresentedForTesting)
        XCTAssertEqual(controller.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(controller.hasPresentationOverlayForTesting)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertTrue(controller.menuUsesLegacySurfaceForTesting)
        XCTAssertEqual(controller.menuLegacyBlurStyleForTesting, .systemChromeMaterial)

        controller.dismiss(animated: false)
        XCTAssertFalse(controller.hasPresentationOverlayForTesting)
    }

    @MainActor
    func testInheritedLiquidControllerCleansAllTransitionResourcesOnLegacySwitch() {
        let (window, source) = makeContextMenuWindow()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            window.isHidden = true
        }

        let controller = ContextMenuController(
            source: .init(view: source, cornerRadius: 22),
            items: [.action(ContextMenuActionItem(title: "Liquid action"))],
            presentationStyle: .gooey(),
            hasHapticFeedback: false
        )

        AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            controller.present()
        }

        XCTAssertTrue(controller.isPresentedForTesting)
        XCTAssertEqual(controller.resolvedAppearanceStyleForTesting, .liquidGlassV1)
        XCTAssertTrue(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertEqual(source.alpha, 0, accuracy: 0.001)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: true)

        XCTAssertFalse(controller.isPresentedForTesting)
        XCTAssertFalse(controller.hasPresentationOverlayForTesting)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertEqual(source.alpha, 1, accuracy: 0.001)
        XCTAssertTrue(source.isUserInteractionEnabled)
    }

    @MainActor
    func testLegacySwitchFinishesAnInFlightLiquidDismissalSynchronously() {
        let (window, source) = makeContextMenuWindow()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            window.isHidden = true
        }

        let controller = ContextMenuController(
            source: .init(view: source, cornerRadius: 22),
            items: [.action(ContextMenuActionItem(title: "Morph action"))],
            presentationStyle: .morph,
            hasHapticFeedback: false
        )

        AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            controller.present()
        }
        controller.dismiss(animated: true)

        XCTAssertFalse(controller.isPresentedForTesting)
        XCTAssertTrue(controller.hasPresentationOverlayForTesting)
        XCTAssertTrue(controller.hasLiquidTransitionResourcesForTesting)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: true)

        XCTAssertFalse(controller.hasPresentationOverlayForTesting)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertEqual(source.alpha, 1, accuracy: 0.001)
    }

    func testGooeyTimingBezierMatchesRequestedCurveShape() {
        let early = AetherGooeyMath.cubicBezierProgress(
            0.20,
            x1: 0.2,
            y1: 0.8,
            x2: 0.2,
            y2: 1.0
        )
        let middle = AetherGooeyMath.cubicBezierProgress(
            0.50,
            x1: 0.2,
            y1: 0.8,
            x2: 0.2,
            y2: 1.0
        )

        XCTAssertGreaterThan(early, 0.55)
        XCTAssertGreaterThan(middle, 0.88)
        XCTAssertEqual(AetherGooeyMath.cubicBezierProgress(0.0, x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0), 0.0)
        XCTAssertEqual(AetherGooeyMath.cubicBezierProgress(1.0, x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0), 1.0)
    }

    func testCaptureGeometryBelowPlacement() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 160.0, y: 90.0, width: 44.0, height: 44.0))
        source.layer.cornerRadius = 22.0
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        menu.layer.cornerRadius = 27.0
        container.addSubview(source)
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below
        )

        XCTAssertEqual(geometry.sourceFrameInContainer, source.frame)
        XCTAssertEqual(geometry.menuFrameInContainer, menu.frame)
        XCTAssertEqual(geometry.sourceCornerRadius, 22.0)
        XCTAssertEqual(geometry.menuCornerRadius, 27.0)
        XCTAssertEqual(geometry.placement, .below)
        XCTAssertEqual(geometry.distance, 26.0, accuracy: 0.001)
        XCTAssertEqual(geometry.connectorStartPoint.y, source.frame.maxY)
        XCTAssertEqual(geometry.connectorEndPoint.y, menu.frame.minY)
    }

    func testCaptureGeometryFallsBackWhenSourceIsNil() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: nil,
            menuView: menu,
            containerView: container,
            placement: .below
        )

        XCTAssertFalse(geometry.sourceFrameInContainer.isNull)
        XCTAssertGreaterThan(geometry.sourceFrameInContainer.width, 0.0)
        XCTAssertGreaterThan(geometry.sourceFrameInContainer.height, 0.0)
        XCTAssertEqual(geometry.connectorEndPoint.y, menu.frame.minY)
    }

    func testCaptureGeometryUsesCapsuleFallbackForSmallZeroRadiusSource() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 300.0, y: 64.0, width: 52.0, height: 52.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(source)
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below
        )

        XCTAssertEqual(geometry.sourceCornerRadius, 26.0, accuracy: 0.001)
    }

    func testCaptureGeometryHonorsExplicitFixedZeroSourceRadius() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 300.0, y: 64.0, width: 52.0, height: 52.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(source)
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below,
            sourceCornerRadiusPolicy: .fixed(0.0),
            menuCornerRadiusPolicy: .fixed(27.0)
        )

        XCTAssertEqual(geometry.sourceCornerRadius, 0.0, accuracy: 0.001)
    }

    func testConnectorPathForSeparatedRectsIsNonEmpty() {
        let source = CGRect(x: 160.0, y: 90.0, width: 44.0, height: 44.0)
        let menu = CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0)

        let path = AetherGooeyConnectorView.makeConnectorPath(
            source: source,
            menu: menu,
            placement: .below,
            progress: 0.5,
            minThickness: 8.0,
            maxThickness: 28.0,
            maxConnectorLength: 96.0
        )

        XCTAssertFalse(path.boundingBoxOfPath.isNull)
        XCTAssertGreaterThan(path.boundingBoxOfPath.height, 0.0)
        XCTAssertGreaterThan(path.boundingBoxOfPath.width, 0.0)
    }

    func testConnectorPathAtZeroProgressIsEmpty() {
        let path = AetherGooeyConnectorView.makeConnectorPath(
            source: CGRect(x: 10.0, y: 10.0, width: 44.0, height: 44.0),
            menu: CGRect(x: 10.0, y: 90.0, width: 260.0, height: 220.0),
            placement: .below,
            progress: 0.0,
            minThickness: 8.0,
            maxThickness: 28.0,
            maxConnectorLength: 96.0
        )

        XCTAssertTrue(path.isEmpty)
    }

    func testMatureOpeningMaskNoLongerExtendsBackToSourceTail() throws {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 312.0, y: 72.0, width: 44.0, height: 44.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(source)
        container.addSubview(menu)
        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0)
        )
        let morphView = AetherGooeyMorphSurfaceView(frame: container.bounds)
        let configuration = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .liquidGlassV1)

        morphView.update(
            geometry: geometry,
            progress: 0.80,
            phase: .opening,
            configuration: configuration,
            accessibilitySettings: AetherGooeyAccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increasedContrast: false
            )
        )

        let bounds = try XCTUnwrap(morphView.currentPath?.boundingBoxOfPath)
        XCTAssertGreaterThan(bounds.minY, source.frame.maxY)
        XCTAssertLessThan(bounds.maxX, source.frame.maxX - 6.0)
    }

    @MainActor
    func testOpenFromPrestagedHiddenMenuFinishesVisibleAndInteractive() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 24.0, y: 64.0, width: 44.0, height: 44.0))
        let menu = MenuGlassSurfaceView(isDark: false, effectsEnabled: false)
        menu.frame = CGRect(x: 96.0, y: 124.0, width: 260.0, height: 176.0)
        menu.alpha = 0.0
        menu.isUserInteractionEnabled = false
        container.addSubview(source)
        container.addSubview(menu)

        let configuration = AetherGooeyContextMenuTransitionConfiguration(
            durationOpen: 0.01,
            durationClose: 0.01,
            springDamping: 1.0,
            springResponse: 0.2,
            connectorMaximumLength: 96.0,
            connectorMinimumThickness: 8.0,
            connectorMaximumThickness: 24.0,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0),
            glassStyle: .regular,
            blurIntensity: 0.0,
            tintAlpha: 0.0,
            strokeAlpha: 0.0,
            shadowAlpha: 0.0,
            highlightAlpha: 0.0,
            allowsLensingApproximation: false,
            respectsReduceMotion: false,
            respectsReduceTransparency: false,
            debugShowsControlPoints: false,
            appearanceStyle: .liquidGlassV1
        )
        let transition = AetherGooeyContextMenuTransition(configuration: configuration)
        let expectation = expectation(description: "gooey open completes")

        transition.animateOpen(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .trailing,
            completion: { finished in
                XCTAssertTrue(finished)
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(menu.alpha, 1.0, accuracy: 0.001)
        XCTAssertTrue(menu.isUserInteractionEnabled)
        XCTAssertEqual(source.alpha, 0.0, accuracy: 0.001)
    }

    @MainActor
    func testOpenDoesNotScaleRealMenuSurface() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 312.0, y: 72.0, width: 44.0, height: 44.0))
        let menu = MenuGlassSurfaceView(isDark: false, effectsEnabled: false)
        menu.frame = CGRect(x: 96.0, y: 124.0, width: 260.0, height: 176.0)
        menu.alpha = 0.0
        container.addSubview(source)
        container.addSubview(menu)

        let configuration = AetherGooeyContextMenuTransitionConfiguration(
            durationOpen: 1.0,
            durationClose: 0.01,
            springDamping: 1.0,
            springResponse: 0.2,
            connectorMaximumLength: 96.0,
            connectorMinimumThickness: 8.0,
            connectorMaximumThickness: 24.0,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0),
            glassStyle: .regular,
            blurIntensity: 0.0,
            tintAlpha: 0.0,
            strokeAlpha: 0.0,
            shadowAlpha: 0.0,
            highlightAlpha: 0.0,
            allowsLensingApproximation: false,
            respectsReduceMotion: false,
            respectsReduceTransparency: false,
            debugShowsControlPoints: false,
            appearanceStyle: .liquidGlassV1
        )
        let transition = AetherGooeyContextMenuTransition(configuration: configuration)

        transition.animateOpen(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .trailing,
            completion: { _ in }
        )

        XCTAssertTrue(transition.hasLiquidTransitionResourcesForTesting)
        XCTAssertTrue(transition.hasGooeyDisplayLinkForTesting)
        XCTAssertTrue(containsLiquidTransitionView(in: container))
        XCTAssertFalse(transition.hasClassicAnimatorForTesting)
        XCTAssertEqual(menu.transform.a, 1.0, accuracy: 0.001)
        XCTAssertEqual(menu.transform.d, 1.0, accuracy: 0.001)
        XCTAssertEqual(menu.transform.tx, 0.0, accuracy: 0.001)
        XCTAssertEqual(menu.transform.ty, 0.0, accuracy: 0.001)
        XCTAssertNil(menu.layer.mask)
        transition.cancel()
    }

    private func makeConfiguration(
        appearanceStyle: AetherAppearanceStyle?
    ) -> AetherGooeyContextMenuTransitionConfiguration {
        AetherGooeyContextMenuTransitionConfiguration(
            durationOpen: 0.2,
            durationClose: 0.18,
            springDamping: 1.0,
            springResponse: 0.2,
            connectorMaximumLength: 96.0,
            connectorMinimumThickness: 8.0,
            connectorMaximumThickness: 24.0,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0),
            glassStyle: .regular,
            blurIntensity: 0.0,
            tintAlpha: 0.0,
            strokeAlpha: 0.0,
            shadowAlpha: 0.0,
            highlightAlpha: 0.0,
            allowsLensingApproximation: false,
            respectsReduceMotion: false,
            respectsReduceTransparency: false,
            debugShowsControlPoints: false,
            appearanceStyle: appearanceStyle
        )
    }

    private func containsLiquidTransitionView(in root: UIView) -> Bool {
        if root is AetherGooeyTransitionOverlayView
            || root is AetherGooeyMorphSurfaceView
            || root is AetherGooeySDFSurfaceView
            || root is AetherGooeyMetaballShaderView {
            return true
        }
        return root.subviews.contains(where: containsLiquidTransitionView(in:))
    }

    @MainActor
    private func makeContextMenuWindow() -> (UIWindow, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        root.view.frame = window.bounds
        window.rootViewController = root
        window.makeKeyAndVisible()

        let source = UIView(frame: CGRect(x: 24, y: 72, width: 44, height: 44))
        source.layer.cornerRadius = 22
        source.backgroundColor = .systemBlue
        root.view.addSubview(source)
        root.view.layoutIfNeeded()
        return (window, source)
    }
}
