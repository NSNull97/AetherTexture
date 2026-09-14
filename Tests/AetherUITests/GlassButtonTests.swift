import XCTest
import UIKit
@testable import AetherUI

final class GlassButtonTests: XCTestCase {
    @MainActor
    func testExplicitLegacyControlsSeedBackingRenderersBeforeAllocation() {
        let controls = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            (
                GlassButton(title: "Legacy", appearanceStyle: .legacy),
                GlassBarButtonView(
                    icon: UIImage(systemName: "ellipsis"),
                    appearanceStyle: .legacy
                ),
                GlassControlGroup(appearanceStyle: .legacy),
                AetherSlider(value: 0.4, appearanceStyle: .legacy),
                AetherSearchBarContent(appearanceStyle: .legacy)
            )
        }
        let (button, barButton, group, slider, search) = controls

        XCTAssertEqual(button.appearanceStyleOverride, .legacy)
        XCTAssertFalse(button.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertFalse(button.backingUsesAnyGlassRendererForTesting)
        XCTAssertEqual(button.backingLegacyBlurStyleForTesting, .systemChromeMaterial)

        XCTAssertEqual(barButton.appearanceStyleOverride, .legacy)
        XCTAssertFalse(barButton.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertFalse(barButton.backingUsesAnyGlassRendererForTesting)
        XCTAssertEqual(barButton.backingLegacyBlurStyleForTesting, .systemChromeMaterial)

        XCTAssertEqual(group.appearanceStyleOverride, .legacy)
        XCTAssertFalse(group.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertFalse(group.backingUsesAnyGlassRendererForTesting)
        XCTAssertEqual(group.backingLegacyBlurStyleForTesting, .systemChromeMaterial)

        XCTAssertEqual(slider.appearanceStyleOverride, .legacy)
        XCTAssertFalse(slider.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertFalse(slider.backingUsesAnyGlassRendererForTesting)
        XCTAssertEqual(
            slider.backingLegacyBlurStylesForTesting,
            [.systemChromeMaterial, .systemChromeMaterial]
        )

        XCTAssertEqual(search.appearanceStyleOverride, .legacy)
        XCTAssertFalse(search.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertFalse(search.backingUsesAnyGlassRendererForTesting)
        XCTAssertNil(search.backingLegacyBlurStyleForTesting)

        for control in [button, barButton, group, slider, search] {
            XCTAssertEqual(
                control.gestureRecognizers?.filter { $0 is GlassHighlightGestureRecognizer }.count ?? 0,
                0
            )
        }
    }

    @MainActor
    func testExplicitLegacyControlPinsWinOverRuntimeUpdates() {
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }
        let button = GlassButton(appearanceStyle: .legacy)
        let barButton = GlassBarButtonView(appearanceStyle: .legacy)
        let group = GlassControlGroup(appearanceStyle: .legacy)
        let slider = AetherSlider(appearanceStyle: .legacy)
        let search = AetherSearchBarContent(appearanceStyle: .legacy)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV2, animated: true)

        XCTAssertFalse(button.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(barButton.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(group.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(slider.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(search.backingUsesAnyGlassRendererForTesting)
        XCTAssertEqual(button.backingLegacyBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertEqual(barButton.backingLegacyBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertEqual(group.backingLegacyBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertEqual(slider.backingLegacyBlurStylesForTesting.count, 2)
        XCTAssertNil(search.backingLegacyBlurStyleForTesting)
    }

    @MainActor
    func testNilStyleControlsFollowRuntimeAndReleaseLegacyRenderers() {
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }
        let controls = AetherAppearance.withRuntimeCurrent(.legacy) {
            (
                GlassButton(),
                GlassBarButtonView(),
                GlassControlGroup(),
                AetherSlider(),
                AetherSearchBarContent()
            )
        }
        let (button, barButton, group, slider, search) = controls

        XCTAssertNil(button.appearanceStyleOverride)
        XCTAssertNil(barButton.appearanceStyleOverride)
        XCTAssertNil(group.appearanceStyleOverride)
        XCTAssertNil(slider.appearanceStyleOverride)
        XCTAssertNil(search.appearanceStyleOverride)
        XCTAssertFalse(button.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(barButton.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(group.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(slider.backingUsesAnyGlassRendererForTesting)
        XCTAssertFalse(search.backingUsesAnyGlassRendererForTesting)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)

        XCTAssertTrue(button.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertTrue(barButton.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertTrue(group.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertTrue(slider.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertTrue(search.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertTrue(button.backingUsesAnyGlassRendererForTesting)
        XCTAssertTrue(barButton.backingUsesAnyGlassRendererForTesting)
        XCTAssertTrue(group.backingUsesAnyGlassRendererForTesting)
        XCTAssertTrue(slider.backingUsesAnyGlassRendererForTesting)
        XCTAssertTrue(search.backingUsesAnyGlassRendererForTesting)
        XCTAssertNil(button.backingLegacyBlurStyleForTesting)
        XCTAssertNil(barButton.backingLegacyBlurStyleForTesting)
        XCTAssertNil(group.backingLegacyBlurStyleForTesting)
        XCTAssertTrue(slider.backingLegacyBlurStylesForTesting.isEmpty)
        XCTAssertNil(search.backingLegacyBlurStyleForTesting)
    }

    @MainActor
    func testLegacyControlGroupRemovesLiquidPressRendererAcrossRepeatedSwaps() {
        let group = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            GlassControlGroup()
        }

        func elasticRecognizerCount() -> Int {
            group.gestureRecognizers?.filter {
                $0 is GlassHighlightGestureRecognizer
            }.count ?? 0
        }

        XCTAssertEqual(elasticRecognizerCount(), 1)
        for _ in 0 ..< 3 {
            group.appearanceStyleOverride = .legacy
            XCTAssertEqual(elasticRecognizerCount(), 0)

            group.appearanceStyleOverride = .liquidGlassV1
            XCTAssertEqual(elasticRecognizerCount(), 1)
        }
    }

    @MainActor
    func testTransitionOverlayForwardsOnlyUnclaimedTouchesToNativeMaterial() throws {
        let glass = GlassBackgroundView(style: .regular)
        glass.frame = CGRect(x: 0, y: 0, width: 240, height: 80)
        glass.update(
            size: glass.bounds.size,
            cornerRadius: 28,
            isDark: false,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )
        guard let material = glass.transitionMaterialHitTargetForTesting else {
            throw XCTSkip("native interactive glass is unavailable")
        }

        let endpointRoot = UIView(frame: glass.bounds)
        let button = UIButton(frame: CGRect(x: 170, y: 10, width: 60, height: 60))
        endpointRoot.addSubview(button)
        glass.transitionContentView.addSubview(endpointRoot)
        glass.transitionContentPassesUnclaimedTouchesToMaterial = true

        let freeHit = try XCTUnwrap(
            glass.hitTest(CGPoint(x: 40, y: 40), with: nil)
        )
        XCTAssertTrue(
            freeHit === material || freeHit.isDescendant(of: material),
            "blank endpoint content must keep native liquid interaction alive"
        )
        XCTAssertTrue(
            glass.hitTest(CGPoint(x: 200, y: 40), with: nil) === button,
            "a real endpoint control must retain touch ownership"
        )
    }

    @MainActor
    func testQuarantinedTransitionMaterialReturnsWrapperInsteadOfNativeFallback() throws {
        let glass = GlassBackgroundView(style: .regular)
        glass.frame = CGRect(x: 0, y: 0, width: 240, height: 80)
        glass.update(
            size: glass.bounds.size,
            cornerRadius: 28,
            isDark: false,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )
        guard let material = glass.transitionMaterialHitTargetForTesting else {
            throw XCTSkip("native interactive glass is unavailable")
        }

        // Models a transition sample where both endpoint subtrees are disabled:
        // unclaimed input must still reach the wrapper's ancestor gestures, but
        // must not enter the moving native material hierarchy.
        let disabledEndpoint = UIView(frame: glass.bounds)
        disabledEndpoint.isUserInteractionEnabled = false
        glass.transitionContentView.addSubview(disabledEndpoint)
        glass.transitionContentPassesUnclaimedTouchesToMaterial = false
        glass.transitionMaterialInteractionEnabled = false

        let hit = try XCTUnwrap(
            glass.hitTest(CGPoint(x: 40, y: 40), with: nil)
        )
        XCTAssertTrue(hit === glass)
        XCTAssertFalse(hit === material || hit.isDescendant(of: material))
    }

    @MainActor
    func testQuarantinedMidCollapseHitUsesVisiblePresentationBoundsOutsideCompactModel() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let glass = GlassBackgroundView(style: .regular)
        glass.frame = CGRect(x: 40, y: 560, width: 240, height: 48)
        root.view.addSubview(glass)
        glass.update(
            size: glass.bounds.size,
            cornerRadius: 24,
            isDark: false,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )
        guard let material = glass.transitionMaterialHitTargetForTesting else {
            throw XCTSkip("native interactive glass is unavailable")
        }

        // The collapse track has already committed compact model geometry, but
        // its presentation layer is still visibly much taller. No endpoint is
        // interactive during this phase and native material input is quarantined.
        glass.transitionContentPassesUnclaimedTouchesToMaterial = false
        glass.transitionMaterialInteractionEnabled = false
        let disabledEndpoint = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 400))
        disabledEndpoint.isUserInteractionEnabled = false
        glass.transitionContentView.addSubview(disabledEndpoint)

        let boundsAnimation = CABasicAnimation(keyPath: "bounds")
        boundsAnimation.fromValue = NSValue(
            cgRect: CGRect(x: 0, y: 0, width: 240, height: 400)
        )
        boundsAnimation.toValue = NSValue(cgRect: glass.layer.bounds)
        boundsAnimation.duration = 10
        boundsAnimation.beginTime = CACurrentMediaTime()
        boundsAnimation.isRemovedOnCompletion = false
        glass.layer.add(boundsAnimation, forKey: "test.midCollapse.presentationBounds")
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        let presentation = try XCTUnwrap(glass.layer.presentation())
        XCTAssertGreaterThan(presentation.bounds.height, glass.layer.bounds.height + 100)

        // This point is visible inside the presentation layer, but lies well
        // outside the already-compact 48pt model bounds. Convert it back to the
        // model-local input UIKit supplies to the moving view's hit-test path.
        let visiblePresentationPoint = CGPoint(
            x: presentation.bounds.midX,
            y: presentation.bounds.minY + 100
        )
        XCTAssertTrue(presentation.bounds.contains(visiblePresentationPoint))
        XCTAssertFalse(glass.layer.bounds.contains(visiblePresentationPoint))
        let pointInSuperlayer = presentation.convert(
            visiblePresentationPoint,
            to: presentation.superlayer
        )
        let modelLocalPoint = glass.layer.convert(
            pointInSuperlayer,
            from: glass.layer.superlayer
        )

        let hit = try XCTUnwrap(glass.hitTest(modelLocalPoint, with: nil))
        XCTAssertTrue(
            hit === glass,
            "a catch/reopen touch inside the visible collapse surface must remain owned by the wrapper"
        )
        XCTAssertFalse(
            hit === material || hit.isDescendant(of: material),
            "presentation-only collapse area leaked touch ownership into native glass"
        )
    }

    @MainActor
    func testHiddenFullscreenTransitionMaterialDoesNotCreateWhiteVeil() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let root = UIViewController()
        root.view.backgroundColor = UIColor(
            red: 0.08,
            green: 0.24,
            blue: 0.82,
            alpha: 1
        )
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        root.view.frame = window.bounds
        root.view.layoutIfNeeded()

        let baseline = try renderedPixels(of: root.view)
        let glass = GlassBackgroundView(style: .regular)
        glass.frame = root.view.bounds
        root.view.addSubview(glass)
        glass.layoutIfNeeded()

        let overlay = UIView(frame: CGRect(x: 40, y: 40, width: 40, height: 40))
        overlay.backgroundColor = .systemGreen
        glass.transitionContentView.addSubview(overlay)
        glass.transitionMaterialAlpha = 0
        glass.layoutIfNeeded()

        let withoutVeil = try renderedPixels(of: root.view)
        XCTAssertEqual(
            pixel(in: withoutVeil, at: CGPoint(x: 12, y: 12)),
            pixel(in: baseline, at: CGPoint(x: 12, y: 12)),
            "a hidden fullscreen material must render the untouched backdrop"
        )
        XCTAssertNotEqual(
            pixel(in: withoutVeil, at: CGPoint(x: 60, y: 60)),
            pixel(in: baseline, at: CGPoint(x: 60, y: 60)),
            "plain transition content must stay visible above hidden material"
        )
        XCTAssertEqual(overlay.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(
            glass.transitionMaterialPresentationAlphaForTesting,
            0,
            accuracy: 0.001
        )
    }

    func testGlassButtonAcceptsSymbolImagesWithoutCGImageBacking() throws {
        let symbol = try XCTUnwrap(UIImage(systemName: "sparkles"))
        let button = GlassButtonView(icon: symbol)

        XCTAssertEqual(button.intrinsicContentSize, CGSize(width: 60.0, height: 60.0))
    }

    func testGenerateImageRejectsInvalidAndUnboundedBitmapSizes() {
        XCTAssertNil(generateImage(.zero, rotatedContext: { _, _ in }))
        XCTAssertNil(generateImage(CGSize(width: .infinity, height: 10.0), rotatedContext: { _, _ in }))
        XCTAssertNil(generateImage(CGSize(width: 20_000.0, height: 20_000.0), scale: 1.0, rotatedContext: { _, _ in }))
        XCTAssertNotNil(generateImage(CGSize(width: 2.0, height: 2.0), scale: 1.0, rotatedContext: { _, _ in }))
    }

    func testGlassButtonIsUIControlAndDisablesGlassInteractionWhileLoading() throws {
        let button = GlassButton(title: "Done")
        button.frame = CGRect(x: 0.0, y: 0.0, width: 96.0, height: 40.0)
        button.layoutIfNeeded()

        let glass = try XCTUnwrap(button.descendant(ofType: GlassBackgroundView.self))
        XCTAssertEqual(glass.params?.isInteractive, true)

        button.isLoading = true
        button.layoutIfNeeded()
        XCTAssertEqual(glass.params?.isInteractive, false)

        button.isLoading = false
        button.isEnabled = false
        button.layoutIfNeeded()
        XCTAssertEqual(glass.params?.isInteractive, false)
    }

    func testGlassButtonTitleUsesItsNaturalHeightAndIsVerticallyCentered() throws {
        let button = GlassButton(title: "Add pair")
        button.frame = CGRect(x: 0.0, y: 0.0, width: 240.0, height: 48.0)
        button.layoutIfNeeded()

        let titleView = try XCTUnwrap(button.descendant(withAccessibilityLabel: "Add pair"))
        XCTAssertLessThan(titleView.frame.height, button.bounds.height)
        XCTAssertGreaterThan(titleView.frame.minY, 0)
        XCTAssertEqual(titleView.frame.midY, button.bounds.midY, accuracy: 0.5)
    }

    func testGlassBackgroundExplicitTintSurvivesLayoutPass() {
        let glass = GlassBackgroundView(style: .regular)
        let tint = GlassBackgroundView.TintColor(
            kind: .custom(style: .default, color: UIColor.systemTeal),
            innerColor: UIColor.systemBlue,
            innerInset: 2.0
        )

        glass.frame = CGRect(x: 0.0, y: 0.0, width: 120.0, height: 44.0)
        glass.update(
            size: glass.bounds.size,
            cornerRadius: 16.0,
            isDark: false,
            tintColor: tint,
            isInteractive: false,
            transition: .immediate
        )

        glass.setNeedsLayout()
        glass.layoutIfNeeded()

        XCTAssertEqual(glass.params?.tintColor, tint)
        XCTAssertEqual(glass.params?.isInteractive, false)
        XCTAssertEqual(glass.glassParams?.cornerRadius, 16.0)
    }

    func testGlassBackgroundCapsuleRadiusTracksBoundsInPropertyDrivenMode() {
        let glass = GlassBackgroundView(style: .regular)

        glass.frame = CGRect(x: 0.0, y: 0.0, width: 120.0, height: 40.0)
        glass.layoutIfNeeded()
        XCTAssertEqual(glass.glassParams?.cornerRadius, 20.0)

        glass.frame = CGRect(x: 0.0, y: 0.0, width: 120.0, height: 80.0)
        glass.layoutIfNeeded()
        XCTAssertEqual(glass.glassParams?.cornerRadius, 40.0)
    }

    @MainActor
    func testCollapsingGlassHitTestFollowsVisiblePresentationSurface() throws {
        let harness = makeAnimatedGlassHitTestHarness(
            initialFrame: CGRect(x: 0, y: 0, width: 320, height: 600),
            targetFrame: CGRect(x: 16, y: 500, width: 288, height: 56),
            fractionComplete: 0.2
        )
        defer { harness.animator.stopAnimation(true) }

        let presentationFrame = try XCTUnwrap(
            harness.glass.layer.presentation()?.frame
        )
        let probe = CGPoint(
            x: presentationFrame.midX,
            y: presentationFrame.minY + 24
        )
        XCTAssertTrue(presentationFrame.contains(probe))
        XCTAssertFalse(harness.glass.frame.contains(probe))

        let hit = try XCTUnwrap(harness.window.hitTest(probe, with: nil))
        XCTAssertTrue(
            hit === harness.hitTarget || hit.isDescendant(of: harness.hitTarget),
            "the dismiss recognizer's glass ancestor must receive a touch on the visible moving card"
        )
    }

    @MainActor
    func testExpandingGlassHitTestRejectsInvisibleCommittedModelRegion() throws {
        let harness = makeAnimatedGlassHitTestHarness(
            initialFrame: CGRect(x: 16, y: 500, width: 288, height: 56),
            targetFrame: CGRect(x: 0, y: 0, width: 320, height: 600),
            fractionComplete: 0.2
        )
        defer { harness.animator.stopAnimation(true) }

        let presentationFrame = try XCTUnwrap(
            harness.glass.layer.presentation()?.frame
        )
        let probe = CGPoint(x: harness.glass.frame.midX, y: 24)
        XCTAssertTrue(harness.glass.frame.contains(probe))
        XCTAssertFalse(presentationFrame.contains(probe))

        let hit = try XCTUnwrap(harness.window.hitTest(probe, with: nil))
        XCTAssertFalse(
            hit === harness.glass || hit.isDescendant(of: harness.glass),
            "the committed full-size model must not create a hit region ahead of its visible presentation"
        )
    }

    func testLiquidLensPinsExplicitAppearanceThroughItsInternalGlass() {
        let lens = LiquidLensView(kind: .builtinContainer)
        lens.isDarkAppearance = true
        lens.update(
            size: CGSize(width: 180.0, height: 62.0),
            selectionOrigin: .zero,
            selectionSize: CGSize(width: 60.0, height: 62.0),
            inset: 4.0,
            isDark: false,
            isLifted: false,
            transition: .immediate
        )

        XCTAssertEqual(lens.resolvedIsDarkForTesting, true)
        XCTAssertEqual(lens.internalBackgroundDarkOverrideForTesting, true)

        lens.isDarkAppearance = false
        XCTAssertEqual(lens.resolvedIsDarkForTesting, false)
        XCTAssertEqual(lens.internalBackgroundDarkOverrideForTesting, false)
    }

    @MainActor
    func testLiquidLensLegacyRendererSurvivesRepeatedRuntimeSwapsWithoutGlassResidue() {
        let lens = AetherAppearance.withRuntimeCurrent(.legacy) {
            LiquidLensView(kind: .builtinContainer)
        }
        let contentHost = lens.contentView
        let selectedContentHost = lens.selectedContentView
        let contentMarker = UIView()
        let selectedContentMarker = UIView()
        contentHost.addSubview(contentMarker)
        selectedContentHost.addSubview(selectedContentMarker)

        lens.update(
            size: CGSize(width: 180.0, height: 62.0),
            selectionOrigin: CGPoint(x: 18.0, y: 4.0),
            selectionSize: CGSize(width: 62.0, height: 54.0),
            inset: 4.0,
            isDark: false,
            isLifted: false,
            transition: .immediate
        )

        XCTAssertTrue(lens.usesClassicRendererForTesting)
        XCTAssertFalse(lens.hasLiquidMaskForTesting)
        XCTAssertEqual(lens.classicTrackBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertEqual(lens.classicSelectionBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertEqual(
            lens.classicSelectionFrameForTesting,
            CGRect(x: 22.0, y: 8.0, width: 54.0, height: 46.0)
        )
        let legacySubviewCount = lens.rendererOwnedSubviewCountForTesting

        for _ in 0 ..< 3 {
            lens.appearanceStyleOverride = .liquidGlassV1
            XCTAssertFalse(lens.usesClassicRendererForTesting)
            XCTAssertNil(lens.classicTrackBlurStyleForTesting)
            XCTAssertNil(lens.classicSelectionBlurStyleForTesting)

            lens.appearanceStyleOverride = .legacy
            XCTAssertTrue(lens.usesClassicRendererForTesting)
            XCTAssertFalse(lens.hasLiquidMaskForTesting)
            XCTAssertEqual(lens.classicTrackBlurStyleForTesting, .systemChromeMaterial)
            XCTAssertEqual(lens.classicSelectionBlurStyleForTesting, .systemChromeMaterial)
            XCTAssertEqual(lens.rendererOwnedSubviewCountForTesting, legacySubviewCount)
            XCTAssertTrue(lens.contentView === contentHost)
            XCTAssertTrue(lens.selectedContentView === selectedContentHost)
            XCTAssertTrue(contentMarker.superview === contentHost)
            XCTAssertTrue(selectedContentMarker.superview === selectedContentHost)
            XCTAssertEqual(lens.selectionOrigin, CGPoint(x: 18.0, y: 4.0))
            XCTAssertEqual(lens.selectionSize, CGSize(width: 62.0, height: 54.0))
        }
    }

    @MainActor
    private func makeAnimatedGlassHitTestHarness(
        initialFrame: CGRect,
        targetFrame: CGRect,
        fractionComplete: CGFloat
    ) -> (
        window: UIWindow,
        glass: GlassBackgroundView,
        hitTarget: UIView,
        animator: UIViewPropertyAnimator
    ) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let root = UIViewController()
        root.view.frame = window.bounds
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root

        let glass = GlassBackgroundView(style: .regular)
        glass.frame = initialFrame
        glass.update(
            size: initialFrame.size,
            cornerRadius: min(initialFrame.width, initialFrame.height) * 0.1,
            transition: .immediate
        )
        glass.beginInteractiveGeometryUpdates()

        let hitTarget = UIView(
            frame: CGRect(
                origin: .zero,
                size: CGSize(width: 320, height: 600)
            )
        )
        hitTarget.isUserInteractionEnabled = true
        glass.contentView.addSubview(hitTarget)
        root.view.addSubview(glass)
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()

        let targetGeometry = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: min(targetFrame.width, targetFrame.height) * 0.1
        )
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            glass.layer.position = targetGeometry.position
            glass.layer.bounds = targetGeometry.bounds
            glass.layer.cornerRadius = targetGeometry.cornerRadius
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.startAnimation()
        animator.pauseAnimation()
        animator.fractionComplete = fractionComplete
        CATransaction.flush()

        if let presentation = glass.layer.presentation() {
            glass.updateInteractiveGeometry(
                size: presentation.bounds.size,
                cornerRadius: presentation.cornerRadius
            )
        }
        return (window, glass, hitTarget, animator)
    }

    @MainActor
    private func renderedPixels(of view: UIView) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return try XCTUnwrap(
            UIGraphicsImageRenderer(
                bounds: view.bounds,
                format: format
            ).image { output in
                view.layer.render(in: output.cgContext)
            }.cgImage
        )
    }

    private func pixel(in image: CGImage, at point: CGPoint) -> [UInt8] {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }
        let x = min(max(Int(point.x), 0), image.width - 1)
        let y = min(max(Int(point.y), 0), image.height - 1)
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        return Array(UnsafeBufferPointer(
            start: bytes.advanced(by: offset),
            count: bytesPerPixel
        ))
    }
}

private extension UIView {
    func descendant<T: UIView>(ofType type: T.Type) -> T? {
        if let self = self as? T {
            return self
        }
        for subview in subviews {
            if let result = subview.descendant(ofType: type) {
                return result
            }
        }
        return nil
    }

    
    func descendant(withAccessibilityLabel label: String) -> UIView? {
        if accessibilityLabel == label {
            return self
        }
        for subview in subviews {
            if let result = subview.descendant(withAccessibilityLabel: label) {
                return result
            }
        }
        return nil
    }
}
