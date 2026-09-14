import XCTest
import UIKit
@testable import AetherUI

final class AetherTabBarControllerTests: XCTestCase {
    func testLegacyTabBarHeightIncludesOnlyContentAndBottomSafeArea() {
        XCTAssertEqual(
            TabBarView.LegacyLayout.totalHeight(bottomSafeAreaInset: 0.0),
            49.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TabBarView.LegacyLayout.totalHeight(bottomSafeAreaInset: 34.0),
            83.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TabBarView.LegacyLayout.totalHeight(bottomSafeAreaInset: 20.0),
            83.0,
            accuracy: 0.001
        )
    }

    func testLegacyTabItemUsesFortyPointRowAtSevenPointTopInset() {
        let frame = TabBarView.LegacyLayout.itemFrame(index: 1, count: 4, width: 400.0)
        XCTAssertEqual(frame, CGRect(x: 100.0, y: 7.0, width: 100.0, height: 40.0))

        let content = TabBarView.LegacyLayout.itemContentFrames(
            bounds: CGRect(x: 0.0, y: 0.0, width: 100.0, height: 40.0),
            titleLineHeight: 12.0
        )
        XCTAssertEqual(content.icon.minY, 0.0, accuracy: 0.001)
        XCTAssertEqual(content.title.maxY, 40.0, accuracy: 0.001)
    }

    func testLegacyScrollEdgeLongContentHidesAtEndAndShowsAboveIt() {
        let atEnd = LegacyTabBarScrollMetrics(
            contentOffsetY: 583.0,
            contentHeight: 1_200.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )
        XCTAssertFalse(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: atEnd,
                previouslyVisible: true
            )
        )

        let aboveEnd = LegacyTabBarScrollMetrics(
            contentOffsetY: 575.0,
            contentHeight: 1_200.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )
        XCTAssertTrue(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: aboveEnd,
                previouslyVisible: false
            )
        )

        let halfPointBeforeEnd = LegacyTabBarScrollMetrics(
            contentOffsetY: 582.5,
            contentHeight: 1_200.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )
        XCTAssertTrue(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: halfPointBeforeEnd,
                previouslyVisible: false
            )
        )
    }

    func testLegacyScrollEdgeClassifiesContentAtExactViewportBoundary() {
        func metrics(contentHeight: CGFloat, contentOffsetY: CGFloat = 0.0) -> LegacyTabBarScrollMetrics {
            LegacyTabBarScrollMetrics(
                contentOffsetY: contentOffsetY,
                contentHeight: contentHeight,
                boundsHeight: 700.0,
                adjustedTopInset: 0.0,
                adjustedBottomInset: 83.0
            )
        }

        let viewportHeightWithoutTabBar: CGFloat = 666.0
        XCTAssertFalse(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: metrics(contentHeight: viewportHeightWithoutTabBar - 0.25),
                previouslyVisible: false
            )
        )
        XCTAssertTrue(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: metrics(contentHeight: viewportHeightWithoutTabBar),
                previouslyVisible: false
            )
        )
        XCTAssertTrue(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: metrics(contentHeight: viewportHeightWithoutTabBar + 0.25),
                previouslyVisible: false
            )
        )
        XCTAssertFalse(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: metrics(
                    contentHeight: viewportHeightWithoutTabBar,
                    contentOffsetY: 49.0
                ),
                previouslyVisible: true
            )
        )
    }

    @MainActor
    func testLegacyTabDoesNotRetainHiddenLensEffectViews() {
        let bar = AetherAppearance.withRuntimeCurrent(.legacy) {
            TabBarView()
        }

        XCTAssertTrue(bar.isLiquidLensRendererSuspendedForTesting)
        XCTAssertFalse(bar.hasInstalledLiquidLensRendererForTesting)
        XCTAssertEqual(
            bar.attachedBackgroundBlurStyleForTesting.rawValue,
            UIBlurEffect.Style.systemChromeMaterial.rawValue
        )
        if UIAccessibility.isReduceTransparencyEnabled {
            XCTAssertFalse(bar.attachedBackgroundUsesPublicBlurForTesting)
        } else {
            XCTAssertTrue(bar.attachedBackgroundUsesPublicBlurForTesting)
        }

        bar.aetherApplyAppearance(.liquidGlassV2, animated: false)
        XCTAssertFalse(bar.isLiquidLensRendererSuspendedForTesting)
        XCTAssertTrue(bar.hasInstalledLiquidLensRendererForTesting)

        bar.aetherApplyAppearance(.legacy, animated: false)
        XCTAssertTrue(bar.isLiquidLensRendererSuspendedForTesting)
        XCTAssertFalse(bar.hasInstalledLiquidLensRendererForTesting)
    }

    func testLegacyScrollEdgeShortContentStaysHiddenDuringOrdinaryBounce() {
        let metrics = LegacyTabBarScrollMetrics(
            contentOffsetY: -32.0,
            contentHeight: 620.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )

        XCTAssertFalse(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: metrics,
                previouslyVisible: false
            )
        )
    }

    func testLegacyScrollEdgeShortContentUsesStableStrongTopOverscrollThreshold() {
        let strongOverscroll = LegacyTabBarScrollMetrics(
            contentOffsetY: -51.0,
            contentHeight: 620.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )
        XCTAssertTrue(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: strongOverscroll,
                previouslyVisible: false
            )
        )

        let hysteresisBand = LegacyTabBarScrollMetrics(
            contentOffsetY: -32.0,
            contentHeight: 620.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )
        XCTAssertTrue(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: hysteresisBand,
                previouslyVisible: true
            )
        )

        let reset = LegacyTabBarScrollMetrics(
            contentOffsetY: -20.0,
            contentHeight: 620.0,
            boundsHeight: 700.0,
            adjustedTopInset: 0.0,
            adjustedBottomInset: 83.0
        )
        XCTAssertFalse(
            LegacyTabBarScrollEdgeResolver.isChromeVisible(
                metrics: reset,
                previouslyVisible: true
            )
        )
    }

    @MainActor
    func testLegacyDisablesMinimizerAndLiveSwitchExpandsImmediately() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        fixture.tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        fixture.tabs.setTabBarMinimized(true, transition: .immediate)
        XCTAssertTrue(fixture.tabs.isTabBarMinimized)

        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))

        XCTAssertFalse(fixture.tabs.isTabBarMinimized)
        let tabBarView = try XCTUnwrap(fixture.tabs.view.firstDescendant(of: TabBarView.self))
        XCTAssertFalse(tabBarView.isMinimized)

        fixture.tabs.setTabBarMinimized(true, transition: .immediate)
        XCTAssertFalse(fixture.tabs.isTabBarMinimized)
        XCTAssertFalse(tabBarView.isMinimized)
    }

    @MainActor
    func testLegacyAccessoryUsesTapOnlyAndNeverInstallsPressFeedback() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))
        fixture.tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56.0)
        fixture.tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(fixture.tabs.view.directGlassSubviews.first)
        let tap = try XCTUnwrap(
            wrapper.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first
        )
        XCTAssertFalse(tap.cancelsTouchesInView)
        XCTAssertFalse(tap.delaysTouchesBegan)
        XCTAssertFalse(tap.delaysTouchesEnded)
        XCTAssertTrue(
            wrapper.gestureRecognizers?.compactMap { $0 as? GlassHighlightGestureRecognizer }.isEmpty ?? true
        )
        XCTAssertTrue(
            wrapper.gestureRecognizers?.compactMap { $0 as? AetherClassicPressGestureRecognizer }.isEmpty ?? true
        )
        XCTAssertEqual(wrapper.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(wrapper.transform, .identity)
        XCTAssertTrue(CATransform3DIsIdentity(wrapper.layer.sublayerTransform))

        fixture.tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))

        XCTAssertTrue(
            wrapper.gestureRecognizers?.compactMap { $0 as? AetherClassicPressGestureRecognizer }.isEmpty ?? true
        )
        let glass = wrapper.gestureRecognizers?.compactMap {
            $0 as? GlassHighlightGestureRecognizer
        } ?? []
        XCTAssertEqual(glass.count, 1)
        XCTAssertTrue(glass[0].isEnabled)

        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))

        XCTAssertTrue(
            wrapper.gestureRecognizers?.compactMap { $0 as? GlassHighlightGestureRecognizer }.isEmpty ?? true
        )
        XCTAssertTrue(
            wrapper.gestureRecognizers?.compactMap { $0 as? AetherClassicPressGestureRecognizer }.isEmpty ?? true
        )
        XCTAssertEqual(wrapper.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(wrapper.transform, .identity)
        XCTAssertTrue(CATransform3DIsIdentity(wrapper.layer.sublayerTransform))
    }

    @MainActor
    func testLegacyAccessorySurfaceTapYieldsToInteractiveDescendantsAndStillOpens() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .legacy))

        let accessory = FixedBottomAccessoryView(height: 56.0)
        let button = UIButton(type: .system)
        let buttonContent = UIView()
        button.addSubview(buttonContent)
        accessory.addSubview(button)

        let scrollView = UIScrollView()
        let scrollContent = UIView()
        scrollView.addSubview(scrollContent)
        accessory.addSubview(scrollView)

        let gestureHost = UIView()
        gestureHost.addGestureRecognizer(
            UITapGestureRecognizer(target: nil, action: nil)
        )
        accessory.addSubview(gestureHost)

        let freeSurface = UIView()
        accessory.addSubview(freeSurface)

        let expanded = UIViewController()
        var providerInvocationCount = 0
        accessory.expandedViewControllerProvider = {
            providerInvocationCount += 1
            return expanded
        }
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        XCTAssertFalse(
            tabs.shouldReceiveBottomBarAccessorySurfaceTouch(in: buttonContent),
            "a control's descendants must keep their touch"
        )
        XCTAssertFalse(
            tabs.shouldReceiveBottomBarAccessorySurfaceTouch(in: scrollContent),
            "scroll-view content must not also open the accessory"
        )
        XCTAssertFalse(
            tabs.shouldReceiveBottomBarAccessorySurfaceTouch(in: gestureHost),
            "a child-owned gesture must take precedence over the wrapper tap"
        )
        XCTAssertTrue(
            tabs.shouldReceiveBottomBarAccessorySurfaceTouch(in: freeSurface),
            "an unclaimed point on the accessory must keep opening the player"
        )

        let tapSelector = NSSelectorFromString("handleAccessoryTap:")
        XCTAssertTrue(tabs.responds(to: tapSelector))
        _ = tabs.perform(tapSelector, with: EndedTapGestureRecognizer())
        XCTAssertEqual(providerInvocationCount, 1)
        XCTAssertTrue(tabs.expandedAccessoryViewController === expanded)
    }

    @MainActor
    func testLegacyAnimatedAccessoryInstallIsAlphaOnlyAndFilterFree() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))

        let accessory = FixedBottomAccessoryView(height: 56.0)
        fixture.tabs.setBottomBarAccessory(
            accessory,
            animated: true
        )
        fixture.tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(fixture.tabs.view.directGlassSubviews.first)
        XCTAssertEqual(wrapper.alpha, 1.0, accuracy: 0.001)
        XCTAssertNil(
            wrapper.layer.animation(forKey: "opacity"),
            "The Legacy material plane must not fade across its chrome cutout"
        )
        XCTAssertNotNil(
            accessory.layer.animation(forKey: "opacity"),
            "Only compact accessory content should perform the alpha fade"
        )
        XCTAssertNil(wrapper.layer.filters)
        #if !APPSTORE_SAFE
        XCTAssertFalse((wrapper.layer.animationKeys() ?? []).contains { key in
            (wrapper.layer.animation(forKey: key) as? CAPropertyAnimation)?
                .keyPath?.contains(ObfuscatedSymbols.gaussianBlur) == true
        })
        #endif
    }

    @MainActor
    func testLegacyTabBarVisibilityUsesUIKitAlphaClockWithoutBlurDisplayLink() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))
        fixture.tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56.0)
        fixture.tabs.view.layoutIfNeeded()
        let wrapper = try XCTUnwrap(fixture.tabs.view.directGlassSubviews.first)

        fixture.tabs.updateIsTabBarHidden(
            true,
            transition: .animated(duration: 0.28, curve: .easeInOut)
        )

        XCTAssertFalse(fixture.tabs.isTabBarVisibilityDisplayLinkActiveForTesting)
        XCTAssertFalse(fixture.tabs.hasOwnedTabBarVisibilityBlurFilterForTesting)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityBlurRadiusForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityAlphaForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityTransformForTesting, .identity)
        XCTAssertNil(wrapper.layer.filters)
    }

    @MainActor
    func testLiveSwitchToLegacyReroutesVisibilityAndClearsOwnedFilters() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        fixture.tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56.0)
        fixture.tabs.view.layoutIfNeeded()
        let wrapper = try XCTUnwrap(fixture.tabs.view.directGlassSubviews.first)
        let duration = AetherMotion.navigationChrome.contentAppearanceDuration

        fixture.tabs.updateIsTabBarHidden(
            true,
            transition: .animated(duration: duration, curve: .easeInOut)
        )
        fixture.tabs.advanceTabBarVisibilityContentAnimationForTesting(
            by: duration * 0.5
        )
        XCTAssertTrue(fixture.tabs.isTabBarVisibilityDisplayLinkActiveForTesting)
        XCTAssertGreaterThan(fixture.tabs.tabBarVisibilityBlurRadiusForTesting, 0.0)

        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))

        XCTAssertFalse(fixture.tabs.isTabBarVisibilityDisplayLinkActiveForTesting)
        XCTAssertFalse(fixture.tabs.hasOwnedTabBarVisibilityBlurFilterForTesting)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityBlurRadiusForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityAlphaForTesting, 0.0, accuracy: 0.001)
        XCTAssertNil(wrapper.layer.filters)
    }

    #if DEBUG
    @MainActor
    func testLegacySearchItemUsesAnEqualWidthTabSlot() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))
        fixture.tabs.view.layoutIfNeeded()

        let tabBarView = try XCTUnwrap(fixture.tabs.view.firstDescendant(of: TabBarView.self))
        let searchFrame = try XCTUnwrap(tabBarView.legacySearchItemFrameForTesting)
        XCTAssertEqual(searchFrame.minX, 260.0, accuracy: 0.5)
        XCTAssertEqual(searchFrame.minY, 7.0, accuracy: 0.001)
        XCTAssertEqual(searchFrame.width, 130.0, accuracy: 0.5)
        XCTAssertEqual(searchFrame.height, 40.0, accuracy: 0.001)
    }
    #endif

    @MainActor
    func testAccessoryDefaultInvalidationUsesDedicatedSizeSpring() throws {
        let accessory = TabBarAccessoryView()
        var capturedTransition: ContainedViewLayoutTransition?
        accessory.requestLayout = { transition in
            capturedTransition = transition
        }

        accessory.invalidateLayout()

        guard case let .animated(duration, curve)? = capturedTransition else {
            return XCTFail("Expected the default accessory resize to animate")
        }
        guard case let .customSpring(damping, initialVelocity) = curve else {
            return XCTFail("Expected the default accessory resize to use its semantic spring")
        }
        XCTAssertEqual(duration, AetherMotion.bottomBarAccessoryResize.duration, accuracy: 0.001)
        XCTAssertEqual(damping, AetherMotion.bottomBarAccessoryResize.dampingRatio, accuracy: 0.001)
        XCTAssertEqual(initialVelocity, AetherMotion.bottomBarAccessoryResize.initialVelocity, accuracy: 0.001)
    }

    @MainActor
    func testDefaultAccessoryKeepsTheCompactLiquidRequestedHeight() {
        let accessory = TabBarAccessoryView()

        XCTAssertEqual(accessory.nominalHeight, 48.0, accuracy: 0.001)
        XCTAssertEqual(accessory.height, 48.0, accuracy: 0.001)
        XCTAssertEqual(accessory.height, TabBarView.minimizedButtonSize)
    }

    @MainActor
    func testAccessoryMaterialIsLimitedToCompactMorphGeometry() {
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator.expandedContentPlaneAlpha(
                presentationProgress: 0
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator.expandedContentPlaneAlpha(
                presentationProgress: 0.04
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator.expandedContentPlaneAlpha(
                presentationProgress: 0.08
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator.expandedContentPlaneAlpha(
                presentationProgress: 1
            ),
            1,
            accuracy: 0.001
        )

        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0.08
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0.24
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0.40
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 1
            ),
            0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testBottomAccessoryIsDirectChildOfTheSingleGlassContentView() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        XCTAssertEqual(tabs.view.directGlassSubviews.count, 1)
        XCTAssertEqual(wrapper.allGlassDescendants.count, 1)
        XCTAssertTrue(
            accessory.superview === wrapper.contentView,
            "bottomBarAccessory must be installed directly in GlassBackgroundView.contentView"
        )
        if wrapper.usesNativeGlassRendererForTesting {
            XCTAssertFalse(
                wrapper.contentView.clipsToBounds,
                "Native Liquid Glass may inscribe contentView to a zero-height capsule; direct accessory content must remain unclipped while the glass layer owns the shape clip"
            )
        }
        assertAccessoryIsInteractive(accessory, in: tabs)
    }

    @MainActor
    func testExpandedAccessoryHidesGlassMaterialWithoutHidingFullContent() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let glassCount = tabs.view.allGlassDescendants.count
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertEqual(wrapper.transitionMaterialAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(
            wrapper.transitionMaterialPresentationAlphaForTesting,
            1,
            accuracy: 0.001
        )

        tabs.presentExpandedAccessory(expanded, animated: false)

        assertFrame(wrapper.frame, equals: tabs.view.bounds)
        XCTAssertEqual(wrapper.transitionMaterialAlpha, 0, accuracy: 0.001)
        XCTAssertEqual(
            wrapper.transitionMaterialPresentationAlphaForTesting,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(expanded.view.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(expanded.view.superview?.alpha ?? -1, 1, accuracy: 0.001)
        XCTAssertTrue(expanded.view.isDescendant(of: wrapper.transitionContentView))
        if wrapper.usesNativeGlassRendererForTesting {
            XCTAssertFalse(
                expanded.view.isDescendant(of: wrapper.contentView),
                "Native Full content must stay on the transition overlay"
            )
        }
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertEqual(tabs.view.allGlassDescendants.count, glassCount)

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertEqual(wrapper.transitionMaterialAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(
            wrapper.transitionMaterialPresentationAlphaForTesting,
            1,
            accuracy: 0.001
        )
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertEqual(tabs.view.allGlassDescendants.count, glassCount)
    }

    @MainActor
    func testLiveStyleSwitchWhileExpandedKeepsMaterialHiddenAndRetargetsDock() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.view.layoutIfNeeded()
        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear

        tabs.presentExpandedAccessory(expanded, animated: false)
        tabs.updateAppearance(AetherAppearance(style: .legacy))
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(wrapper.transitionMaterialAlpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(
            wrapper.transitionMaterialPresentationAlphaForTesting,
            0.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            wrapper.legacyBlurStyleForTesting,
            .systemUltraThinMaterial
        )
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        let legacyFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)
        XCTAssertEqual(legacyFrame.minX, 16.0, accuracy: 0.001)
        XCTAssertEqual(legacyFrame.width, 358.0, accuracy: 0.001)
        XCTAssertEqual(legacyFrame.height, 58.0, accuracy: 0.001)

        tabs.presentExpandedAccessory(expanded, animated: false)
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(wrapper.transitionMaterialAlpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(
            wrapper.transitionMaterialPresentationAlphaForTesting,
            0.0,
            accuracy: 0.001
        )
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        let liquidFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)
        XCTAssertEqual(liquidFrame.minX, 25.0, accuracy: 0.001)
        XCTAssertEqual(liquidFrame.width, 340.0, accuracy: 0.001)
        XCTAssertEqual(liquidFrame.height, 48.0, accuracy: 0.001)
    }

    @MainActor
    func testFullPlayerPresentedMidCompactMorphDismissesToCanonicalDockWithoutStaleTarget() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.bottomBarAccessoryReduceMotionStatusProvider = { false }
        let accessory = FixedBottomAccessoryView(height: 56.0)
        let expanded = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()
        let delegate = RecordingTabBarMinimizationDelegate()
        tabs.minimizationDelegate = delegate

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let expandedFrame = CGRect(x: 25.0, y: 699.0, width: 340.0, height: 56.0)
        let minimizedFrame = CGRect(x: 89.0, y: 775.0, width: 212.0, height: 48.0)
        assertFrame(wrapper.frame, equals: expandedFrame)

        let compactMorph: ContainedViewLayoutTransition = .animated(
            duration: 0.50,
            curve: .linear
        )
        tabs.setTabBarMinimized(true, transition: compactMorph)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let minimizeIntermediateFrame = wrapper.frame
        XCTAssertFalse(
            minimizeIntermediateFrame.isApproximatelyEqual(to: expandedFrame, accuracy: 0.5)
        )
        XCTAssertFalse(
            minimizeIntermediateFrame.isApproximatelyEqual(to: minimizedFrame, accuracy: 0.5)
        )
        XCTAssertGreaterThan(tabs.tabBarMinimizationProgress, 0.0)
        XCTAssertLessThan(tabs.tabBarMinimizationProgress, 1.0)

        tabs.presentExpandedAccessory(expanded, animated: false)

        XCTAssertTrue(tabs.expandedAccessoryViewController === expanded)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertNil(delegate.updates.last?.bottomBarAccessoryFrame)

        // The original compact clock continues as a progress-only timeline.
        // Full Player owns the reusable glass, so its fullscreen geometry must
        // never leak through the compact accessory callback.
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertEqual(delegate.updates.last?.progress ?? -1.0, 1.0, accuracy: 0.001)
        XCTAssertNil(delegate.updates.last?.bottomBarAccessoryFrame)
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 1.0, accuracy: 0.001)

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        assertFrame(
            wrapper.frame,
            equals: minimizedFrame,
            message: "A mid-minimize visual source became the collapse target"
        )
        XCTAssertEqual(delegate.updates.last?.progress ?? -1.0, 1.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(delegate.updates.last?.bottomBarAccessoryFrame),
            equals: minimizedFrame,
            message: "Dismiss did not restore compact accessory geometry publication"
        )

        // The retired compact display link must not regain geometry ownership.
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        assertFrame(
            wrapper.frame,
            equals: minimizedFrame,
            message: "A stale minimize sample overwrote the canonical dock"
        )

        tabs.setTabBarMinimized(false, transition: compactMorph)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let expandIntermediateFrame = wrapper.frame
        XCTAssertFalse(
            expandIntermediateFrame.isApproximatelyEqual(to: minimizedFrame, accuracy: 0.5)
        )
        XCTAssertFalse(
            expandIntermediateFrame.isApproximatelyEqual(to: expandedFrame, accuracy: 0.5)
        )
        XCTAssertGreaterThan(tabs.tabBarMinimizationProgress, 0.0)
        XCTAssertLessThan(tabs.tabBarMinimizationProgress, 1.0)

        tabs.presentExpandedAccessory(expanded, animated: false)

        XCTAssertTrue(tabs.expandedAccessoryViewController === expanded)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertNil(delegate.updates.last?.bottomBarAccessoryFrame)

        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertEqual(delegate.updates.last?.progress ?? -1.0, 0.0, accuracy: 0.001)
        XCTAssertNil(delegate.updates.last?.bottomBarAccessoryFrame)
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 0.0, accuracy: 0.001)

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        assertFrame(
            wrapper.frame,
            equals: expandedFrame,
            message: "A mid-expand visual source became the collapse target"
        )
        XCTAssertEqual(delegate.updates.last?.progress ?? -1.0, 0.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(delegate.updates.last?.bottomBarAccessoryFrame),
            equals: expandedFrame,
            message: "Dismiss did not restore regular accessory geometry publication"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        assertFrame(
            wrapper.frame,
            equals: expandedFrame,
            message: "A stale expand sample overwrote the canonical dock"
        )
    }

    @MainActor
    func testPresentExpandedAccessoryRejectsCurrentTabWithoutDetachingItsView() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56.0)
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let current = try XCTUnwrap(tabs.currentController)
        let originalSuperview = try XCTUnwrap(current.view.superview)
        let originalFrame = current.view.frame
        let originalWindow = current.view.window
        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let accessoryFrame = wrapper.frame
        XCTAssertTrue(current.parent === tabs)

        tabs.presentExpandedAccessory(current, animated: false)

        XCTAssertNil(tabs.expandedAccessoryViewController)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertTrue(current.parent === tabs)
        XCTAssertTrue(current.view.superview === originalSuperview)
        XCTAssertTrue(current.view.window === originalWindow)
        XCTAssertTrue(tabs.currentController === current)
        assertFrame(current.view.frame, equals: originalFrame)
        assertFrame(wrapper.frame, equals: accessoryFrame)
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertFalse(tabs.dismissExpandedAccessory(animated: false))
    }

    @MainActor
    func testNativeAccessorySettleSkipsDisplayLinkGlassWritesAndCapturesRetarget() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()
        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }

        tabs.presentExpandedAccessory(expanded, animated: true)
        XCTAssertTrue(wrapper.isTransitionCompositorSettleActive)
        let openingTrack = try XCTUnwrap(
            wrapper.transitionCompositorSettleTrackForTesting
        )
        XCTAssertEqual(openingTrack.keyTimes.count, 49)
        let directCountAfterInstall = wrapper
            .transitionDirectGeometryUpdateCountForTesting
        let openingEndpointAlpha = try XCTUnwrap(
            openingTrack.materialAlphaValues.last
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(
            wrapper.transitionDirectGeometryUpdateCountForTesting,
            directCountAfterInstall,
            "TabBar display-link publication must not rewrite native glass geometry"
        )
        XCTAssertEqual(
            wrapper.transitionMaterialPresentationAlphaForTesting,
            openingEndpointAlpha,
            accuracy: 0.001,
            "TabBar display-link publication must not overwrite the compositor material model"
        )
        XCTAssertNotNil(wrapper.transitionNativeParamsAnimationForTesting)

        let captureCount = wrapper.transitionCompositorCaptureCountForTesting
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        XCTAssertGreaterThan(
            wrapper.transitionCompositorCaptureCountForTesting,
            captureCount,
            "retarget must capture native material presentation before replacing its track"
        )
        XCTAssertTrue(wrapper.isTransitionCompositorSettleActive)
        let collapseTrack = try XCTUnwrap(
            wrapper.transitionCompositorSettleTrackForTesting
        )
        XCTAssertEqual(
            collapseTrack.keyTimes.count,
            max(31, Int(ceil(collapseTrack.duration * 120)) + 1)
        )
        XCTAssertEqual(try XCTUnwrap(collapseTrack.materialAlphaValues.last), 1, accuracy: 0.001)

        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertFalse(wrapper.isTransitionCompositorSettleActive)
        XCTAssertNil(wrapper.transitionNativeParamsAnimationForTesting)
        XCTAssertNil(wrapper.transitionNativeEffectAnimationForTesting)
        XCTAssertEqual(wrapper.transitionMaterialAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(wrapper.bounds.height, 56, accuracy: 0.5)
    }

    @MainActor
    func testRepeatedAnimatedAccessoryDismissRestoresNativeMiniMaterialOwnership() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let effectAssignmentCount = wrapper
            .nativeGlassEffectAssignmentCountForTesting

        for cycle in 0 ..< 3 {
            tabs.presentExpandedAccessory(expanded, animated: true)
            XCTAssertFalse(
                wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
                "expand cycle \(cycle) did not quarantine native press before the morph began"
            )
            XCTAssertFalse(
                wrapper.transitionMaterialInteractionEnabled,
                "expand cycle \(cycle) left the native material hit fallback armed during the morph"
            )
            RunLoop.main.run(until: Date().addingTimeInterval(0.60))
            XCTAssertEqual(
                tabs.bottomBarAccessoryPresentationState,
                .expanded,
                "expand cycle \(cycle) did not reach its endpoint"
            )
            XCTAssertFalse(
                wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
                "expand cycle \(cycle) left the hidden full-size native press surface armed"
            )
            XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)

            XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
            XCTAssertFalse(
                wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
                "dismiss cycle \(cycle) re-armed native stretch before collapse reached Mini"
            )
            XCTAssertFalse(
                wrapper.transitionMaterialInteractionEnabled,
                "dismiss cycle \(cycle) re-armed the moving native hit target"
            )
            RunLoop.main.run(until: Date().addingTimeInterval(0.70))

            try assertStableCollapsedNativeMiniMaterial(
                tabs: tabs,
                wrapper: wrapper,
                accessory: accessory,
                expectedEffectAssignmentCount: effectAssignmentCount,
                message: "after animated expand/dismiss cycle \(cycle)"
            )
        }
    }

    @MainActor
    func testExpandedAccessoryQuarantinesNativePressWithoutBreakingDismissGesturePath() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let nativeMaterial = try XCTUnwrap(
            wrapper.transitionMaterialHitTargetForTesting
        )

        XCTAssertFalse(
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
            "stable Mini must keep background touches out of native liquid deformation"
        )
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)

        tabs.presentExpandedAccessory(expanded, animated: true)
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
        let visibleFrame = wrapper.layer.presentation()?.frame ?? wrapper.frame
        let transientPoint = wrapper.layer.convert(
            CGPoint(x: visibleFrame.midX, y: visibleFrame.midY),
            from: wrapper.layer.superlayer
        )
        let transientHit = try XCTUnwrap(
            wrapper.hitTest(transientPoint, with: nil)
        )
        XCTAssertTrue(
            transientHit === wrapper,
            "when both endpoint hosts are quarantined, the moving wrapper—not native glass—must own the fallback touch"
        )
        XCTAssertFalse(
            transientHit === nativeMaterial
                || transientHit.isDescendant(of: nativeMaterial)
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.60))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertFalse(
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
            "Full Player must quarantine the invisible full-size material from press/pan input"
        )
        XCTAssertFalse(
            wrapper.transitionMaterialInteractionEnabled,
            "Full Player must not leave its invisible native material interactive"
        )

        let point = CGPoint(x: wrapper.bounds.midX, y: wrapper.bounds.midY)
        let hit = try XCTUnwrap(wrapper.hitTest(point, with: nil))
        XCTAssertFalse(
            hit === nativeMaterial || hit.isDescendant(of: nativeMaterial),
            "a Full Player background touch reached the hidden native glass and can leave elastic velocity in the reused Mini surface"
        )
        XCTAssertTrue(
            hit === expanded.view || hit.isDescendant(of: expanded.view),
            "plain Full Player touches must remain in the expanded content tree"
        )
        XCTAssertTrue(
            hit.isDescendant(of: wrapper),
            "the wrapper must remain an ancestor so its dismissal recognizer still receives the same touch"
        )
        XCTAssertTrue(
            wrapper.gestureRecognizers?.contains {
                $0 is InteractiveTransitionGestureRecognizer
            } == true,
            "quarantining native press feedback must not remove drag-to-dismiss"
        )

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertFalse(
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
            "stable Mini must remain on bounded framework press feedback"
        )
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
    }

    @MainActor
    func testRepeatedOpenCloseLeavesMiniPressSurfaceAtRestAndSinglyOwned() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let effectAssignmentCount = wrapper
            .nativeGlassEffectAssignmentCountForTesting

        for cycle in 0 ..< 4 {
            tabs.presentExpandedAccessory(expanded, animated: false)
            XCTAssertFalse(
                wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
                "cycle \(cycle): expanded endpoint leaked input to native glass"
            )
            XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
            XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))

            try assertStableCollapsedNativeMiniMaterial(
                tabs: tabs,
                wrapper: wrapper,
                accessory: accessory,
                expectedEffectAssignmentCount: effectAssignmentCount,
                message: "after immediate expand/dismiss cycle \(cycle)"
            )
            XCTAssertFalse(
                wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
                "cycle \(cycle): Mini re-enabled unbounded native deformation"
            )
            XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
            XCTAssertEqual(
                wrapper.gestureRecognizers?.filter {
                    $0 is UITapGestureRecognizer
                }.count,
                1,
                "cycle \(cycle): accessory tap recognizers accumulated"
            )
        }
    }

    /// A stable Mini must not hand its background touch to the system's
    /// unconstrained interactive `UIGlassEffect`. On a 48pt player capsule
    /// that effect can grow far beyond the compact dock (the oversized white
    /// pill captured in the device regression). Keep the optical native glass,
    /// but own press motion with one deliberately small Aether profile.
    @MainActor
    func testStableMiniUsesOneBoundedPressProfileInsteadOfNativeMaterialStretch() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let nativeMaterial = try XCTUnwrap(
            wrapper.transitionMaterialHitTargetForTesting
        )

        XCTAssertFalse(
            wrapper.glassIsInteractive,
            "stable Mini must not use UIGlassEffect's unbounded full-surface stretch"
        )
        if #available(iOS 26.0, *),
           let effectView = nativeMaterial as? UIVisualEffectView,
           let glassEffect = effectView.effect as? UIGlassEffect {
            XCTAssertFalse(
                glassEffect.isInteractive,
                "the installed native effect—not only its wrapper configuration—must be noninteractive"
            )
        } else {
            XCTFail("native Mini did not expose the installed UIGlassEffect")
        }
        let backgroundPoint = CGPoint(
            x: wrapper.bounds.midX,
            y: wrapper.bounds.midY
        )
        let backgroundHit = try XCTUnwrap(
            wrapper.hitTest(backgroundPoint, with: nil)
        )
        XCTAssertFalse(
            backgroundHit === nativeMaterial,
            "a Mini background press must resolve to compact content, not directly to the native material"
        )
        XCTAssertTrue(
            backgroundHit === accessory
                || backgroundHit.isDescendant(of: accessory),
            "bounded press routing must preserve Glass.contentView ownership"
        )

        let boundedPressRecognizers = wrapper.gestureRecognizers?.compactMap {
            $0 as? GlassHighlightGestureRecognizer
        } ?? []
        XCTAssertEqual(
            boundedPressRecognizers.count,
            1,
            "Mini needs exactly one framework-owned bounded press response"
        )
        if let profile = boundedPressRecognizers.first?.motionProfile {
            XCTAssertEqual(
                profile,
                AetherMotion.bottomBarAccessoryPress,
                "Mini must use the dedicated compact-player lifecycle profile"
            )
            XCTAssertGreaterThan(
                profile.pressedSizeIncrease,
                0,
                "Mini press feedback must remain alive"
            )
            XCTAssertLessThanOrEqual(
                profile.pressedSizeIncrease,
                2,
                "a 48pt Mini may grow by at most 2pt while pressed"
            )
            XCTAssertGreaterThan(
                profile.maximumTranslation,
                0,
                "Mini may follow the finger by a subtle amount"
            )
            XCTAssertLessThanOrEqual(
                profile.maximumTranslation,
                3,
                "Mini press translation must stay inside a 3pt micro-response"
            )
        }
    }

    @MainActor
    func testMiniPressIsResetBeforeExpansionAndRearmedOnlyAtCollapsedEndpoint() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let press = try XCTUnwrap(
            wrapper.gestureRecognizers?.compactMap {
                $0 as? GlassHighlightGestureRecognizer
            }.first
        )
        XCTAssertTrue(press.isEnabled)
        XCTAssertEqual(press.motionProfile, AetherMotion.bottomBarAccessoryPress)

        var leakedPressTransform = CATransform3DIdentity
        leakedPressTransform.m11 = 1.08
        leakedPressTransform.m22 = 1.08
        leakedPressTransform.m41 = 12
        leakedPressTransform.m42 = -9
        wrapper.layer.sublayerTransform = leakedPressTransform
        let leakedPressAnimation = CABasicAnimation(keyPath: "sublayerTransform")
        leakedPressAnimation.fromValue = NSValue(caTransform3D: leakedPressTransform)
        leakedPressAnimation.toValue = NSValue(caTransform3D: leakedPressTransform)
        leakedPressAnimation.duration = 1
        wrapper.layer.add(
            leakedPressAnimation,
            forKey: "aether.touchEffect.sublayerTransform"
        )

        tabs.presentExpandedAccessory(expanded, animated: true)

        XCTAssertFalse(
            press.isEnabled,
            "bounded Mini press must stop owning geometry before expansion starts"
        )
        XCTAssertTrue(
            CATransform3DIsIdentity(wrapper.layer.sublayerTransform),
            "expansion must synchronously commit the exact unpressed model state"
        )
        XCTAssertNil(
            wrapper.layer.animation(forKey: "aether.touchEffect.sublayerTransform"),
            "the press-release spring must not add onto the morph"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertFalse(press.isEnabled)
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        XCTAssertFalse(
            press.isEnabled,
            "bounded press must stay disabled while the surface is moving"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.75))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertTrue(
            press.isEnabled,
            "bounded press must return only after the exact Mini dock is stable"
        )
        XCTAssertTrue(CATransform3DIsIdentity(wrapper.layer.sublayerTransform))
        XCTAssertNil(
            wrapper.layer.animation(forKey: "aether.touchEffect.sublayerTransform")
        )
    }

    /// Exercises the real accessory tap handler rather than calling
    /// `presentExpandedAccessory` directly. Each physical tap must begin one
    /// presentation, and every animated round-trip must put both model and
    /// presentation geometry back on the exact pre-tap dock.
    @MainActor
    func testRepeatedMiniTapRoundTripsOpenOnceAndRestoreExactDockGeometry() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = RecordingExpandedAccessoryController()
        var providerInvocationCount = 0
        accessory.expandedViewControllerProvider = {
            providerInvocationCount += 1
            return expanded
        }
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let dockWrapperFrame = wrapper.frame
        let dockWrapperBounds = wrapper.bounds
        let dockAccessoryFrame = accessory.frame
        let endedTap = EndedTapGestureRecognizer()
        let tapSelector = NSSelectorFromString("handleAccessoryTap:")
        guard tabs.responds(to: tapSelector) else {
            XCTFail("the installed Mini tap must remain wired to the expansion handler")
            return
        }

        for cycle in 0 ..< 3 {
            _ = tabs.perform(tapSelector, with: endedTap)
            XCTAssertEqual(
                providerInvocationCount,
                cycle + 1,
                "cycle \(cycle): one Mini tap invoked its provider more than once"
            )
            RunLoop.main.run(until: Date().addingTimeInterval(0.65))
            XCTAssertEqual(
                tabs.bottomBarAccessoryPresentationState,
                .expanded,
                "cycle \(cycle): the one tap did not open the player"
            )
            XCTAssertTrue(
                tabs.expandedAccessoryViewController === expanded,
                "cycle \(cycle): the tap installed a different Full controller"
            )

            XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
            RunLoop.main.run(until: Date().addingTimeInterval(0.75))
            try assertExactCollapsedDockGeometry(
                tabs: tabs,
                wrapper: wrapper,
                accessory: accessory,
                expectedWrapperFrame: dockWrapperFrame,
                expectedWrapperBounds: dockWrapperBounds,
                expectedAccessoryFrame: dockAccessoryFrame,
                message: "after tapped Mini round-trip \(cycle)"
            )
        }

        XCTAssertEqual(
            providerInvocationCount,
            3,
            "three physical Mini taps must produce exactly three provider calls"
        )
    }

    /// The tap recognizer lives as long as the Mini installation, while Full's
    /// dismiss recognizer is recreated on every presentation. Failure ordering
    /// must therefore follow only the currently active pair; a permanent
    /// `require(toFail:)` edge would make later Mini taps wait on every retired
    /// dismiss recognizer and eventually feel delayed or nonresponsive.
    @MainActor
    func testMiniTapRequiresOnlyCurrentDismissRecognizerAcrossRepeatedCycles() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let tap = try XCTUnwrap(
            wrapper.gestureRecognizers?.compactMap {
                $0 as? UITapGestureRecognizer
            }.first
        )
        var retiredDismissRecognizers: [InteractiveTransitionGestureRecognizer] = []

        for cycle in 0 ..< 5 {
            tabs.presentExpandedAccessory(expanded, animated: false)
            let currentDismiss = try XCTUnwrap(
                wrapper.gestureRecognizers?.compactMap {
                    $0 as? InteractiveTransitionGestureRecognizer
                }.first,
                "cycle \(cycle): Full did not install its current dismiss recognizer"
            )
            XCTAssertTrue(
                tabs.gestureRecognizer(
                    tap,
                    shouldRequireFailureOf: currentDismiss
                ),
                "cycle \(cycle): Mini tap must yield to the active dismiss recognizer"
            )
            for retired in retiredDismissRecognizers {
                XCTAssertFalse(
                    tabs.gestureRecognizer(
                        tap,
                        shouldRequireFailureOf: retired
                    ),
                    "cycle \(cycle): Mini tap still depended on a retired dismiss recognizer"
                )
            }

            XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
            XCTAssertFalse(
                tabs.gestureRecognizer(
                    tap,
                    shouldRequireFailureOf: currentDismiss
                ),
                "cycle \(cycle): collapse left a permanent tap failure dependency"
            )
            XCTAssertNil(
                currentDismiss.view,
                "cycle \(cycle): retired dismiss recognizer remained attached to Mini"
            )
            XCTAssertEqual(
                wrapper.gestureRecognizers?.compactMap {
                    $0 as? UITapGestureRecognizer
                }.count,
                1,
                "cycle \(cycle): the stable Mini tap recognizer was replaced or duplicated"
            )
            retiredDismissRecognizers.append(currentDismiss)
        }

        XCTAssertEqual(
            Set(retiredDismissRecognizers.map { ObjectIdentifier($0) }).count,
            retiredDismissRecognizers.count,
            "each Full session must own one fresh dismiss recognizer"
        )
    }

    @MainActor
    func testRapidAccessoryRetargetEndingCollapsedRestoresNativeMiniMaterialOwnership() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let effectAssignmentCount = wrapper
            .nativeGlassEffectAssignmentCountForTesting

        tabs.presentExpandedAccessory(expanded, animated: true)
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.045))
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.035))
        tabs.presentExpandedAccessory(expanded, animated: true)
        XCTAssertFalse(
            wrapper.transitionMaterialInteractionEnabled,
            "retargeting collapse back to expansion must not arm native material input"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.030))
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        tabs.presentExpandedAccessory(expanded, animated: true)
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.020))
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        XCTAssertFalse(wrapper.transitionMaterialInteractionEnabled)

        RunLoop.main.run(until: Date().addingTimeInterval(0.80))
        try assertStableCollapsedNativeMiniMaterial(
            tabs: tabs,
            wrapper: wrapper,
            accessory: accessory,
            expectedEffectAssignmentCount: effectAssignmentCount,
            message: "after rapid expand/dismiss retarget chain"
        )
    }

    @MainActor
    func testDismissCompletionReentrancyDoesNotLetRetiredCoordinatorCancelNewNativeMaterialTrack() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let effectAssignmentCount = wrapper
            .nativeGlassEffectAssignmentCountForTesting

        tabs.presentExpandedAccessory(expanded, animated: false)
        var didReopenFromDismissCompletion = false
        XCTAssertTrue(
            tabs.dismissExpandedAccessory(animated: true) {
                tabs.presentExpandedAccessory(expanded, animated: true)
                didReopenFromDismissCompletion = true
                XCTAssertTrue(
                    wrapper.isTransitionCompositorSettleActive,
                    "the reentrant expansion must install its native material track"
                )
                XCTAssertFalse(
                    wrapper.transitionMaterialInteractionEnabled,
                    "reentrant expansion must take material interaction ownership away from Mini"
                )
            }
        )

        let completionDeadline = Date().addingTimeInterval(0.80)
        while !didReopenFromDismissCompletion, Date() < completionDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.010))
        }
        XCTAssertTrue(
            didReopenFromDismissCompletion,
            "animated dismiss completion was not delivered"
        )

        // Let the retired collapse coordinator return from its completion and
        // deinitialize. It must not capture/remove a compositor track that the
        // reentrant expansion coordinator has just installed on the same Glass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.020))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanding)
        XCTAssertTrue(
            wrapper.isTransitionCompositorSettleActive,
            "a retired coordinator deinit stole the new coordinator's native material ownership"
        )
        XCTAssertNotNil(wrapper.transitionNativeParamsAnimationForTesting)
        XCTAssertNotNil(wrapper.transitionCompositorSettleTrackForTesting)

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        try assertStableCollapsedNativeMiniMaterial(
            tabs: tabs,
            wrapper: wrapper,
            accessory: accessory,
            expectedEffectAssignmentCount: effectAssignmentCount,
            message: "after reentrant dismiss-completion expansion cleanup"
        )
    }

    @MainActor
    func testReduceMotionInterruptionsDuringDismissRestoreNativeMiniMaterialOwnership() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        var reduceMotionEnabled = false
        tabs.bottomBarAccessoryReduceMotionStatusProvider = {
            reduceMotionEnabled
        }
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        expanded.view.backgroundColor = .clear
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        guard wrapper.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let effectAssignmentCount = wrapper
            .nativeGlassEffectAssignmentCountForTesting

        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        RunLoop.main.run(until: Date().addingTimeInterval(0.045))

        reduceMotionEnabled = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.040))
        reduceMotionEnabled = false
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.035))
        reduceMotionEnabled = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.85))
        try assertStableCollapsedNativeMiniMaterial(
            tabs: tabs,
            wrapper: wrapper,
            accessory: accessory,
            expectedEffectAssignmentCount: effectAssignmentCount,
            message: "after normal/Reduce Motion dismiss interruptions"
        )
    }

    @MainActor
    func testReduceMotionAndLegacyAccessorySettlesRemainDirect() throws {
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        defer { GlassBackgroundView.useCustomGlassImpl = previousRendererOverride }

        GlassBackgroundView.useCustomGlassImpl = false
        let nativeFixture = makeTabBarFixture()
        defer { nativeFixture.window.isHidden = true }
        nativeFixture.tabs.bottomBarAccessoryReduceMotionStatusProvider = { true }
        nativeFixture.tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56)
        nativeFixture.tabs.view.layoutIfNeeded()
        let nativeWrapper = try XCTUnwrap(
            nativeFixture.tabs.view.directGlassSubviews.first
        )
        if nativeWrapper.usesNativeGlassRendererForTesting {
            let before = nativeWrapper.transitionDirectGeometryUpdateCountForTesting
            nativeFixture.tabs.presentExpandedAccessory(
                UIViewController(),
                animated: true
            )
            XCTAssertFalse(nativeWrapper.isTransitionCompositorSettleActive)
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            XCTAssertGreaterThan(
                nativeWrapper.transitionDirectGeometryUpdateCountForTesting,
                before,
                "Reduce Motion must retain the direct geometry handoff"
            )
            XCTAssertTrue(
                nativeFixture.tabs.dismissExpandedAccessory(animated: false)
            )
        }

        nativeFixture.window.isHidden = true
        GlassBackgroundView.useCustomGlassImpl = true
        let legacyFixture = makeTabBarFixture()
        defer { legacyFixture.window.isHidden = true }
        legacyFixture.tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56)
        legacyFixture.tabs.view.layoutIfNeeded()
        let legacyWrapper = try XCTUnwrap(
            legacyFixture.tabs.view.directGlassSubviews.first
        )
        XCTAssertFalse(legacyWrapper.usesNativeGlassRendererForTesting)
        let legacyBefore = legacyWrapper.transitionDirectGeometryUpdateCountForTesting
        legacyFixture.tabs.presentExpandedAccessory(
            UIViewController(),
            animated: true
        )
        XCTAssertFalse(legacyWrapper.isTransitionCompositorSettleActive)
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertGreaterThan(
            legacyWrapper.transitionDirectGeometryUpdateCountForTesting,
            legacyBefore,
            "legacy glass must retain direct geometry updates"
        )
        XCTAssertTrue(legacyFixture.tabs.dismissExpandedAccessory(animated: false))
    }

    @MainActor
    func testAccessoryDismissHandoffSkipsHorizontalPagerForScrolledVerticalAncestor() {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 600)
        )
        let verticalScroll = UIScrollView(frame: container.bounds)
        verticalScroll.contentSize = CGSize(width: 320, height: 1_200)
        verticalScroll.contentOffset = CGPoint(x: 0, y: 200)

        let horizontalPager = UIScrollView(
            frame: CGRect(x: 0, y: 200, width: 320, height: 100)
        )
        horizontalPager.contentSize = CGSize(width: 640, height: 100)
        horizontalPager.alwaysBounceVertical = false
        verticalScroll.addSubview(horizontalPager)
        container.addSubview(verticalScroll)

        let handoff = BottomBarAccessoryDismissScrollHandoff()
        handoff.captureCandidate(
            at: CGPoint(x: 100, y: 50),
            in: container
        )

        XCTAssertTrue(handoff.pendingScrollView === verticalScroll)
        XCTAssertFalse(handoff.pendingScrollView === horizontalPager)
        XCTAssertEqual(
            handoff.decision(translationY: 30, velocityY: 300),
            .wait
        )
    }

    @MainActor
    func testAccessoryDismissHandoffKeepsOwnerUntilTopAndRebasesWithoutJump() {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let verticalScroll = UIScrollView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 800)
        )
        verticalScroll.contentSize = CGSize(width: 390, height: 1_600)
        verticalScroll.contentOffset = CGPoint(x: 0, y: 180)
        container.addSubview(verticalScroll)

        let handoff = BottomBarAccessoryDismissScrollHandoff()
        handoff.captureCandidate(
            at: CGPoint(x: 120, y: 120),
            in: container
        )
        XCTAssertTrue(handoff.pendingScrollView === verticalScroll)
        XCTAssertEqual(
            handoff.decision(translationY: 40, velocityY: 300),
            .wait
        )

        // The recognizer can leave the scroll view's visible bounds while the
        // same touch is still active. Ownership is captured once, so no new
        // hit test may replace the pending scroll before it reaches the top.
        verticalScroll.frame.origin.x = 500
        XCTAssertTrue(handoff.pendingScrollView === verticalScroll)
        XCTAssertEqual(
            handoff.decision(translationY: 63, velocityY: 300),
            .wait
        )

        verticalScroll.contentOffset.y = 0
        XCTAssertEqual(
            handoff.decision(translationY: 64, velocityY: 300),
            .begin(translationOriginY: 64)
        )

        let geometry = BottomBarAccessoryTransitionGeometry(
            collapsedFrame: CGRect(x: 20, y: 720, width: 350, height: 60),
            expandedFrame: CGRect(x: 0, y: 0, width: 390, height: 800),
            collapsedCornerRadius: 28,
            expandedCornerRadius: 8,
            safeInsets: .zero,
            layoutSize: container.bounds.size
        )
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)
        XCTAssertTrue(coordinator.beginDrag(translationOriginY: 64))
        handoff.commitHandoff()

        coordinator.updateDrag(translationY: 64)
        XCTAssertEqual(
            surface.frame.minY,
            geometry.expandedFrame.minY,
            accuracy: 0.001,
            "The accumulated scroll translation must not replay at handoff"
        )

        coordinator.updateDrag(translationY: 65)
        XCTAssertEqual(
            surface.frame.minY,
            geometry.expandedFrame.minY + 1,
            accuracy: 0.001,
            "The first post-top point must track the finger 1:1"
        )
        XCTAssertTrue(handoff.committedScrollView === verticalScroll)

        verticalScroll.contentOffset.y = 12
        handoff.pinCommittedScrollToTop()
        XCTAssertEqual(verticalScroll.contentOffset.y, 0, accuracy: 0.001)
        coordinator.reset(to: .expanded)
    }

    func testLiquidGlassThemeDefaultsMatchTheAcceptedExpandedAndMinimizedGrid() {
        let theme = TabBarView.Theme()

        XCTAssertEqual(theme.pillHeight, 60.0, accuracy: 0.001)
        XCTAssertEqual(theme.sideInset, 25.0, accuracy: 0.001)
        XCTAssertEqual(theme.minimizedSideInset, 28.0, accuracy: 0.001)
        XCTAssertEqual(theme.minimizedInterItemSpacing, 13.0, accuracy: 0.001)
    }

    func testLiquidGlassPillGrowsByTabCountAndCapsAtReferenceWidth() {
        let cases: [(count: Int, x: CGFloat, width: CGFloat, itemWidth: CGFloat)] = [
            (2, 118.0, 196.0, 88.0),
            (3, 74.0, 284.0, 88.0),
            (4, 25.0, 382.0, 90.5),
            (5, 25.0, 382.0, 72.4),
            (6, 25.0, 382.0, 60.333_333)
        ]

        for testCase in cases {
            let controllers = (0..<testCase.count).map {
                makeController(title: "Tab \($0 + 1)", image: "circle")
            }
            let fixture = makeTabBarFixture(
                controllers: controllers,
                size: CGSize(width: 432.0, height: 844.0)
            )

            guard let pillFrame = fixture.tabs.pillFrame(in: fixture.tabs.view) else {
                XCTFail("Expected pill frame for \(testCase.count) tabs")
                fixture.window.isHidden = true
                continue
            }
            XCTAssertEqual(pillFrame.minX, testCase.x, accuracy: 0.01)
            XCTAssertEqual(pillFrame.width, testCase.width, accuracy: 0.01)
            XCTAssertEqual(pillFrame.height, 60.0, accuracy: 0.01)

            guard let firstTabFrame = fixture.tabs.frameForControllerTab(controller: controllers[0]) else {
                XCTFail("Expected first tab frame for \(testCase.count) tabs")
                fixture.window.isHidden = true
                continue
            }
            XCTAssertEqual(firstTabFrame.width, testCase.itemWidth, accuracy: 0.01)
            fixture.window.isHidden = true
        }
    }

    func testExpandedSearchUsesTheFinalMateriallessSlotInsideTheFullWidthPill() {
        let cases: [(count: Int, itemWidth: CGFloat, searchX: CGFloat)] = [
            (1, 181.0, 216.0),
            (2, 120.666_667, 276.333_333),
            (3, 90.5, 306.5),
            (4, 72.4, 324.6)
        ]

        for testCase in cases {
            let regularControllers = (0..<testCase.count).map {
                makeController(title: "Tab \($0 + 1)", image: "circle")
            }
            let fixture = makeTabBarFixture(
                controllers: regularControllers + [makeSearchController()],
                size: CGSize(width: 432.0, height: 844.0)
            )

            guard let pillFrame = fixture.tabs.pillFrame(in: fixture.tabs.view) else {
                XCTFail("Expected pill frame for \(testCase.count) tabs with search")
                fixture.window.isHidden = true
                continue
            }
            XCTAssertEqual(pillFrame.minX, 25.0, accuracy: 0.01)
            XCTAssertEqual(pillFrame.width, 382.0, accuracy: 0.01)
            XCTAssertEqual(pillFrame.height, 60.0, accuracy: 0.01)

            guard let expandedSearchSlot = fixture.tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            ) else {
                XCTFail("Expected expanded Search slot for \(testCase.count) tabs")
                fixture.window.isHidden = true
                continue
            }
            let searchFrame = expandedSearchSlot.convert(
                expandedSearchSlot.bounds,
                to: fixture.tabs.view
            )
            XCTAssertEqual(searchFrame.minX, testCase.searchX, accuracy: 0.01)
            XCTAssertEqual(searchFrame.minY, pillFrame.minY, accuracy: 0.01)
            XCTAssertEqual(searchFrame.width, testCase.itemWidth, accuracy: 0.01)
            XCTAssertEqual(searchFrame.height, 60.0, accuracy: 0.01)
            XCTAssertEqual(expandedSearchSlot.alpha, 1.0, accuracy: 0.001)
            XCTAssertFalse(expandedSearchSlot.isUserInteractionEnabled)
            XCTAssertTrue(expandedSearchSlot.accessibilityElementsHidden)

            guard let minimizedSearchMaterial = fixture.tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView else {
                XCTFail("Expected the stable minimized Search representation")
                fixture.window.isHidden = true
                continue
            }
            let materialFrame = minimizedSearchMaterial.convert(
                minimizedSearchMaterial.bounds,
                to: fixture.tabs.view
            )
            assertFrame(materialFrame, equals: searchFrame)
            XCTAssertEqual(minimizedSearchMaterial.alpha, 1.0, accuracy: 0.001)
            let searchGlassContainer = minimizedSearchMaterial.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
            XCTAssertEqual(
                minimizedSearchMaterial.chromeMorphMaterialAlpha,
                searchGlassContainer?.isUsingNativeContainerEffect == true ? 1.0 : 0.0,
                accuracy: 0.001
            )
            XCTAssertEqual(
                minimizedSearchMaterial.chromeMorphContentAlpha,
                1.0,
                accuracy: 0.001
            )
            XCTAssertTrue(minimizedSearchMaterial.isUserInteractionEnabled)
            XCTAssertFalse(minimizedSearchMaterial.accessibilityElementsHidden)

            guard let firstTabFrame = fixture.tabs.frameForControllerTab(controller: regularControllers[0]) else {
                XCTFail("Expected first tab frame for \(testCase.count) tabs with search")
                fixture.window.isHidden = true
                continue
            }
            XCTAssertEqual(firstTabFrame.width, testCase.itemWidth, accuracy: 0.01)

            guard let lens = fixture.tabs.view.firstDescendant(of: LiquidLensView.self) else {
                XCTFail("Expected selection lens for \(testCase.count) tabs with search")
                fixture.window.isHidden = true
                continue
            }
            XCTAssertNotNil(searchGlassContainer)
            XCTAssertTrue(
                searchGlassContainer === lens.firstAncestor(
                    of: GlassBackgroundContainerView.self
                ),
                "The pill and moving Search surface must share one glass grouping host"
            )
            XCTAssertEqual(lens.selectionOrigin?.x ?? -1.0, 0.0, accuracy: 0.01)
            XCTAssertEqual(
                lens.selectionSize?.width ?? -1.0,
                testCase.itemWidth + 20.0,
                accuracy: 0.01
            )
            fixture.window.isHidden = true
        }
    }

    func testLiquidGlassPillAndSearchUseSystemBackgroundTint() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let lens = try XCTUnwrap(fixture.tabs.view.firstDescendant(of: LiquidLensView.self))
        let searchButton = try XCTUnwrap(
            fixture.tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )
        let searchTint = try XCTUnwrap(searchButton.glassTintColor)

        guard case let .custom(lensStyle, lensColor) = lens.glassTintColor.kind,
              case let .custom(searchStyle, searchColor) = searchTint.kind else {
            XCTFail("Expected matching custom glass tints for the tab pill and search button")
            return
        }

        let interfaceStyle: UIUserInterfaceStyle = fixture.tabs.traitCollection.userInterfaceStyle == .dark
            ? .dark
            : .light
        let expectedColor = UIColor.systemBackground
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: interfaceStyle))
            .withAlphaComponent(0.20)

        XCTAssertEqual(lensStyle, .clear)
        XCTAssertEqual(searchStyle, .clear)
        XCTAssertTrue(lensColor.isEqual(expectedColor))
        XCTAssertTrue(searchColor.isEqual(expectedColor))
    }

    func testAccessorySharesTheTabPillGlassRecipe() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.bottomBarAccessory = TabBarAccessoryView()
        fixture.tabs.view.layoutIfNeeded()

        let lens = try XCTUnwrap(fixture.tabs.view.firstDescendant(of: LiquidLensView.self))
        let searchButton = try XCTUnwrap(
            fixture.tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )
        let accessoryGlass = try XCTUnwrap(fixture.tabs.view.directGlassSubviews.first)
        let searchTint = try XCTUnwrap(searchButton.glassTintColor)

        XCTAssertEqual(accessoryGlass.styleForTesting, lens.glassStyle)
        XCTAssertEqual(searchButton.glassStyle, lens.glassStyle)
        XCTAssertEqual(accessoryGlass.isDarkOverride, lens.isDarkAppearance)
        XCTAssertEqual(searchButton.isDarkAppearance, lens.isDarkAppearance)

        guard case let .custom(lensStyle, lensColor) = lens.glassTintColor.kind,
              case let .custom(accessoryStyle, accessoryColor) = accessoryGlass.glassTintColor.kind,
              case let .custom(searchStyle, searchColor) = searchTint.kind else {
            XCTFail(
                "Expected one custom glass recipe across compact bottom chrome; "
                    + "lens=\(lens.glassTintColor.kind), "
                    + "accessory=\(accessoryGlass.glassTintColor.kind), "
                    + "search=\(searchTint.kind)"
            )
            return
        }
        XCTAssertEqual(accessoryStyle, lensStyle)
        XCTAssertEqual(searchStyle, lensStyle)
        XCTAssertTrue(accessoryColor.isEqual(lensColor))
        XCTAssertTrue(searchColor.isEqual(lensColor))
    }

    func testLegacyAccessoryUsesGroupedUltraThinMaterialWithClassicShadowGeometry() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))
        fixture.tabs.bottomBarAccessory = TabBarAccessoryView()
        fixture.tabs.view.layoutIfNeeded()

        let accessoryGlass = try XCTUnwrap(
            fixture.tabs.view.directGlassSubviews.first
        )
        XCTAssertTrue(accessoryGlass.usesLegacySurfaceRendererForTesting)
        XCTAssertFalse(accessoryGlass.usesAnyGlassRendererForTesting)
        XCTAssertEqual(
            accessoryGlass.legacyBlurStyleForTesting,
            .systemUltraThinMaterial
        )
        XCTAssertFalse(
            accessoryGlass.legacyUsesExternalBlurMaterialForTesting
        )
        XCTAssertEqual(
            try XCTUnwrap(accessoryGlass.legacySurfaceCornerRadiusForTesting),
            12.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(accessoryGlass.legacySurfaceShadowOpacityForTesting),
            0.26,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(accessoryGlass.legacySurfaceShadowRadiusForTesting),
            8.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(accessoryGlass.legacySurfaceShadowOffsetForTesting),
            CGSize(width: 0.0, height: 2.0)
        )
        XCTAssertEqual(
            try XCTUnwrap(accessoryGlass.legacySurfaceBorderWidthForTesting),
            0.0,
            accuracy: 0.001
        )
        let accessorySurfaceColor = try XCTUnwrap(
            accessoryGlass.legacyPlainSurfaceBackgroundColorForTesting
        )
        XCTAssertLessThanOrEqual(
            accessorySurfaceColor.cgColor.alpha,
            0.001
        )
        let materialContentColor = try XCTUnwrap(
            accessoryGlass.legacyMaterialContentBackgroundColorForTesting
        )
        XCTAssertEqual(
            materialContentColor.cgColor.alpha,
            UIAccessibility.isReduceTransparencyEnabled ? 1.0 : 0.0,
            accuracy: 0.001
        )
        let transparencyRefreshCount =
            accessoryGlass.reduceTransparencyRefreshCountForTesting
        NotificationCenter.default.post(
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        XCTAssertEqual(
            accessoryGlass.reduceTransparencyRefreshCountForTesting,
            transparencyRefreshCount + 1
        )

        let tabBar = try XCTUnwrap(
            fixture.tabs.view.firstDescendant(of: TabBarView.self)
        )
        #if !APPSTORE_SAFE
        XCTAssertEqual(
            try XCTUnwrap(
                accessoryGlass.legacyBackdropGroupingIdentifierForTesting
            ),
            try XCTUnwrap(tabBar.legacyBackdropGroupingIdentifierForTesting)
        )
        #endif
        tabBar.setLegacyScrollEdgeChromeVisible(true, transition: .immediate)
        tabBar.layoutIfNeeded()
        let accessorySurfaceHeight =
            TabBarView.LegacyLayout.minimumAccessoryHeight
        let reservedHeight = accessorySurfaceHeight
            + TabBarView.LegacyLayout.accessoryBottomGap
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialFrameForTesting),
            CGRect(
                x: 0.0,
                y: -reservedHeight,
                width: tabBar.bounds.width,
                height: tabBar.bounds.height + reservedHeight
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                tabBar.legacyUnifiedBottomMaterialMaskFrameForTesting
            ),
            CGRect(
                origin: .zero,
                size: CGSize(
                    width: tabBar.bounds.width,
                    height: tabBar.bounds.height + reservedHeight
                )
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                tabBar.legacyUnifiedBottomMaterialCutoutFrameForTesting
            ),
            CGRect(
                x: TabBarView.LegacyLayout.accessorySideInset,
                y: 0.0,
                width: tabBar.bounds.width
                    - TabBarView.LegacyLayout.accessorySideInset * 2.0,
                height: accessorySurfaceHeight
            )
        )
        XCTAssertEqual(
            tabBar.legacyUnifiedBottomMaterialUsesPublicBlurForTesting,
            !UIAccessibility.isReduceTransparencyEnabled
        )
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialAlphaForTesting),
            1.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedAttachedChromeAlphaForTesting),
            1.0,
            accuracy: 0.001
        )
        XCTAssertTrue(tabBar.legacySeparatorIsHiddenForTesting)

        tabBar.updateBackgroundAlpha(0.42, transition: .immediate)
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialAlphaForTesting),
            0.42,
            accuracy: 0.001
        )

        let accessoryFrame = try XCTUnwrap(
            fixture.tabs.bottomBarAccessoryFrame
        )
        XCTAssertEqual(accessoryFrame.minX, 16.0, accuracy: 0.001)
        XCTAssertEqual(accessoryFrame.width, 358.0, accuracy: 0.001)
        XCTAssertEqual(
            accessoryFrame.height,
            accessorySurfaceHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(
            tabBar.frame.minY - accessoryFrame.maxY,
            TabBarView.LegacyLayout.accessoryBottomGap,
            accuracy: 0.001
        )
        let inheritedSafeBottom = max(
            0.0,
            fixture.tabs.view.safeAreaInsets.bottom
                - fixture.tabs.additionalSafeAreaInsets.bottom
        )
        XCTAssertEqual(
            fixture.tabs.additionalSafeAreaInsets.bottom,
            max(
                0.0,
                TabBarView.LegacyLayout.totalHeight(
                    bottomSafeAreaInset: inheritedSafeBottom
                ) - inheritedSafeBottom
            ) + reservedHeight,
            accuracy: 0.01
        )

        tabBar.setLegacyScrollEdgeChromeVisible(false, transition: .immediate)
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialAlphaForTesting),
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedAttachedChromeAlphaForTesting),
            0.0,
            accuracy: 0.001
        )

        fixture.tabs.bottomBarAccessory = nil
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertNil(tabBar.legacyUnifiedBottomMaterialFrameForTesting)
        XCTAssertFalse(tabBar.legacySeparatorIsHiddenForTesting)
        XCTAssertEqual(
            tabBar.legacyBackgroundAlphaForTesting,
            0.0,
            accuracy: 0.001
        )

        fixture.tabs.bottomBarAccessory = TabBarAccessoryView()
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertTrue(tabBar.legacySeparatorIsHiddenForTesting)
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialAlphaForTesting),
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedAttachedChromeAlphaForTesting),
            0.0,
            accuracy: 0.001
        )

        tabBar.setLegacyScrollEdgeChromeVisible(true, transition: .immediate)
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialAlphaForTesting),
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedAttachedChromeAlphaForTesting),
            1.0,
            accuracy: 0.001
        )

        fixture.tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertNil(tabBar.legacyUnifiedBottomMaterialFrameForTesting)
        XCTAssertNil(tabBar.legacyUnifiedBottomMaterialMaskFrameForTesting)
        XCTAssertFalse(tabBar.legacySeparatorIsHiddenForTesting)

        fixture.tabs.updateAppearance(AetherAppearance(style: .legacy))
        fixture.tabs.view.layoutIfNeeded()
        XCTAssertTrue(tabBar.legacySeparatorIsHiddenForTesting)
    }

    func testSearchTintRefreshesWhenStyleAndAppearanceChangeTogether() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let tabBar = try XCTUnwrap(fixture.tabs.view.firstDescendant(of: TabBarView.self))
        let searchButton = try XCTUnwrap(
            fixture.tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )

        tabBar.updateTheme(TabBarView.Theme(
            appearanceStyle: .liquidGlassV2,
            isDark: true,
            isDarkAppearanceExplicit: true,
            style: .liquidGlass,
            glassEffectStyle: .strong
        ))

        let searchTint = try XCTUnwrap(searchButton.glassTintColor)
        guard case let .custom(style, color) = searchTint.kind else {
            XCTFail("Expected a custom search-button tint after the theme change")
            return
        }
        let expectedColor = UIColor.systemBackground
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            .withAlphaComponent(0.20)

        XCTAssertEqual(style, .clear)
        XCTAssertTrue(color.isEqual(expectedColor))
    }

    func testLiquidGlassReferenceWidthFallsBackToSideInsetsOnCompactBounds() {
        let controllers = (0..<4).map {
            makeController(title: "Tab \($0 + 1)", image: "circle")
        }
        let fixture = makeTabBarFixture(
            controllers: controllers,
            size: CGSize(width: 320.0, height: 568.0)
        )

        guard let pillFrame = fixture.tabs.pillFrame(in: fixture.tabs.view) else {
            XCTFail("Expected pill frame on compact bounds")
            fixture.window.isHidden = true
            return
        }
        XCTAssertEqual(pillFrame.minX, 25.0, accuracy: 0.01)
        XCTAssertEqual(pillFrame.width, 270.0, accuracy: 0.01)
        XCTAssertEqual(pillFrame.height, 60.0, accuracy: 0.01)
        fixture.window.isHidden = true
    }

    @MainActor
    func testMinimizationDelegateIsWeak() {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        var delegate: RecordingTabBarMinimizationDelegate? = .init()
        weak var weakDelegate = delegate
        fixture.tabs.minimizationDelegate = delegate

        XCTAssertTrue(fixture.tabs.minimizationDelegate === delegate)

        delegate = nil

        XCTAssertNil(weakDelegate)
        XCTAssertNil(fixture.tabs.minimizationDelegate)
    }

    @MainActor
    func testAssigningMinimizationDelegateImmediatelyPublishesCurrentSnapshot() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.view.layoutIfNeeded()

        let delegate = RecordingTabBarMinimizationDelegate()
        XCTAssertTrue(delegate.updates.isEmpty)

        tabs.minimizationDelegate = delegate

        XCTAssertEqual(delegate.updates.count, 1)
        let snapshot = try XCTUnwrap(delegate.updates.first)
        XCTAssertTrue(snapshot.wasDeliveredOnMainThread)
        XCTAssertEqual(snapshot.progress, 1.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(snapshot.bottomBarAccessoryFrame),
            equals: CGRect(x: 89.0, y: 775.0, width: 212.0, height: 48.0)
        )
    }

    @MainActor
    func testImmediateMinimizationPublishesExactProgressAndAccessoryFrameEndpoints() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.view.layoutIfNeeded()

        let delegate = RecordingTabBarMinimizationDelegate()
        tabs.minimizationDelegate = delegate

        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.view.layoutIfNeeded()

        let minimizedUpdate = try XCTUnwrap(delegate.updates.last)
        XCTAssertTrue(minimizedUpdate.wasDeliveredOnMainThread)
        XCTAssertEqual(minimizedUpdate.progress, 1.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(minimizedUpdate.bottomBarAccessoryFrame),
            equals: CGRect(x: 89.0, y: 775.0, width: 212.0, height: 48.0)
        )
        assertFrame(
            try XCTUnwrap(tabs.bottomBarAccessoryFrame),
            equals: try XCTUnwrap(minimizedUpdate.bottomBarAccessoryFrame)
        )

        delegate.updates.removeAll()
        tabs.setTabBarMinimized(false, transition: .immediate)
        tabs.view.layoutIfNeeded()

        let expandedUpdate = try XCTUnwrap(delegate.updates.last)
        XCTAssertTrue(expandedUpdate.wasDeliveredOnMainThread)
        XCTAssertEqual(expandedUpdate.progress, 0.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(expandedUpdate.bottomBarAccessoryFrame),
            equals: CGRect(x: 25.0, y: 707.0, width: 340.0, height: 48.0)
        )
        assertFrame(
            try XCTUnwrap(tabs.bottomBarAccessoryFrame),
            equals: try XCTUnwrap(expandedUpdate.bottomBarAccessoryFrame)
        )
    }

    @MainActor
    func testAnimatedMinimizationPublishesIntermediateProgressWithoutAccessory() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let delegate = RecordingTabBarMinimizationDelegate()
        tabs.minimizationDelegate = delegate

        tabs.setTabBarMinimized(
            true,
            transition: .animated(duration: 0.12, curve: .linear)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        XCTAssertGreaterThanOrEqual(delegate.updates.count, 2)
        XCTAssertTrue(
            delegate.updates.contains { $0.progress > 0.0 && $0.progress < 1.0 },
            "The delegate must receive at least one rendered in-flight progress sample"
        )
        XCTAssertTrue(delegate.updates.allSatisfy { $0.bottomBarAccessoryFrame == nil })
        XCTAssertTrue(delegate.updates.allSatisfy(\.wasDeliveredOnMainThread))
        for (previous, current) in zip(delegate.updates, delegate.updates.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                current.progress + 0.0001,
                previous.progress,
                "A linear minimize must not publish progress in reverse"
            )
        }
        let endpoint = try XCTUnwrap(delegate.updates.last)
        XCTAssertEqual(endpoint.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 1.0, accuracy: 0.001)
    }

    @MainActor
    func testAnimatedMinimizationReversePreservesProgressAndAccessoryFrameContinuity() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.bottomBarAccessoryReduceMotionStatusProvider = { false }
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.view.layoutIfNeeded()
        let delegate = RecordingTabBarMinimizationDelegate()
        tabs.minimizationDelegate = delegate

        let transition: ContainedViewLayoutTransition = .animated(
            duration: 0.30,
            curve: .linear
        )
        var didReverse = false
        var sampleBeforeReverse: RecordingTabBarMinimizationDelegate.Update?
        var frameImmediatelyAfterReverseRequest: CGRect?
        var firstSampleAfterReverse: RecordingTabBarMinimizationDelegate.Update?

        delegate.onUpdate = { update in
            if !didReverse, update.progress > 0.0, update.progress < 1.0 {
                didReverse = true
                sampleBeforeReverse = update
                tabs.setTabBarMinimized(false, transition: transition)
                frameImmediatelyAfterReverseRequest = tabs.bottomBarAccessoryFrame
            } else if didReverse,
                      firstSampleAfterReverse == nil,
                      update.progress > 0.0 {
                firstSampleAfterReverse = update
            }
        }

        tabs.setTabBarMinimized(true, transition: transition)
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))

        XCTAssertTrue(didReverse)
        let before = try XCTUnwrap(sampleBeforeReverse)
        let beforeFrame = try XCTUnwrap(before.bottomBarAccessoryFrame)
        assertFrame(
            try XCTUnwrap(frameImmediatelyAfterReverseRequest),
            equals: beforeFrame,
            accuracy: 0.75,
            message: "Requesting an animated reverse synchronously jumped accessory geometry"
        )
        let firstReverse = try XCTUnwrap(firstSampleAfterReverse)
        XCTAssertLessThanOrEqual(
            abs(firstReverse.progress - before.progress),
            0.12,
            "The first reverse sample did not continue from the rendered progress"
        )
        XCTAssertTrue(
            try XCTUnwrap(firstReverse.bottomBarAccessoryFrame)
                .isApproximatelyEqual(to: beforeFrame, accuracy: 16.0),
            "The first reverse frame jumped away from the rendered accessory geometry"
        )
        XCTAssertFalse(
            delegate.updates.contains { $0.progress >= 0.999 },
            "An interrupted minimize published its stale target endpoint"
        )
        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 0.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(delegate.updates.last).progress, 0.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(delegate.updates.last?.bottomBarAccessoryFrame),
            equals: CGRect(x: 25.0, y: 707.0, width: 340.0, height: 48.0)
        )
    }

    @MainActor
    func testAnimatedAccessoryCallbacksMatchRenderedWrapperFrameOnEverySample() {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.bottomBarAccessoryReduceMotionStatusProvider = { false }
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.view.layoutIfNeeded()
        let delegate = RecordingTabBarMinimizationDelegate()
        var intermediateSamples: [(published: CGRect, rendered: CGRect?)] = []
        delegate.onUpdate = { update in
            guard update.progress > 0.0,
                  update.progress < 1.0,
                  let published = update.bottomBarAccessoryFrame else {
                return
            }
            intermediateSamples.append((
                published: published,
                rendered: tabs.bottomBarAccessoryFrame
            ))
        }
        tabs.minimizationDelegate = delegate

        tabs.setTabBarMinimized(
            true,
            transition: .animated(duration: 0.20, curve: .linear)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        XCTAssertFalse(intermediateSamples.isEmpty)
        for sample in intermediateSamples {
            guard let rendered = sample.rendered else {
                XCTFail("The installed accessory had no rendered frame during its callback")
                continue
            }
            XCTAssertTrue(
                sample.published.isApproximatelyEqual(to: rendered, accuracy: 0.75),
                "Published frame \(sample.published) did not match rendered frame \(rendered)"
            )
        }
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 1.0, accuracy: 0.001)
    }

    @MainActor
    func testAccessoryInstallResizeAndRemovalPublishCurrentGeometry() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let delegate = RecordingTabBarMinimizationDelegate()
        tabs.minimizationDelegate = delegate
        let accessory = ResizableBottomAccessoryView(height: 48.0)

        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let installed = try XCTUnwrap(delegate.updates.last)
        XCTAssertEqual(installed.progress, 0.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(installed.bottomBarAccessoryFrame),
            equals: CGRect(x: 25.0, y: 707.0, width: 340.0, height: 48.0)
        )

        delegate.updates.removeAll()
        accessory.requestedHeight = 72.0
        accessory.invalidateLayout(transition: .immediate)
        tabs.view.layoutIfNeeded()

        let resized = try XCTUnwrap(delegate.updates.last)
        XCTAssertEqual(resized.progress, 0.0, accuracy: 0.001)
        assertFrame(
            try XCTUnwrap(resized.bottomBarAccessoryFrame),
            equals: CGRect(x: 25.0, y: 683.0, width: 340.0, height: 72.0)
        )

        delegate.updates.removeAll()
        tabs.setBottomBarAccessory(nil, animated: false)

        let removed = try XCTUnwrap(delegate.updates.last)
        XCTAssertEqual(removed.progress, 0.0, accuracy: 0.001)
        XCTAssertNil(removed.bottomBarAccessoryFrame)
        XCTAssertNil(tabs.bottomBarAccessoryFrame)
    }

    @MainActor
    func testAccessoryInstallResizeAndRemovalPreserveAetherListContentOffset() {
        let content = AccessoryOffsetListController()
        content.tabBarItem = UITabBarItem(
            title: "List",
            image: UIImage(systemName: "list.bullet"),
            selectedImage: UIImage(systemName: "list.bullet")
        )
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        content.installItems()
        tabs.view.layoutIfNeeded()
        content.view.layoutIfNeeded()
        content.listNode.view.layoutIfNeeded()
        content.listNode.scrollToBottom(animated: false)

        let scrollView = content.listNode.scroller
        let baseBottomInset = scrollView.contentInset.bottom
        let offsetBeforeInstall = scrollView.contentOffset
        let accessory = ResizableBottomAccessoryView(height: 48.0)

        tabs.setBottomBarAccessory(
            accessory,
            animated: true
        )
        XCTAssertEqual(
            scrollView.contentInset.bottom - baseBottomInset,
            56.0,
            accuracy: 0.01,
            "The fixture must exercise the accessory height plus its 8pt gap"
        )
        XCTAssertEqual(
            scrollView.contentOffset,
            offsetBeforeInstall,
            "Installing an accessory must not move the visible list position"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.40))
        XCTAssertEqual(
            scrollView.contentOffset,
            offsetBeforeInstall,
            "The accessory crossfade completion must not re-anchor the list"
        )

        content.listNode.scrollToBottom(animated: false)
        let offsetBeforeResize = scrollView.contentOffset
        accessory.requestedHeight = 72.0
        accessory.invalidateLayout(transition: .immediate)
        XCTAssertEqual(
            scrollView.contentInset.bottom - baseBottomInset,
            80.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            scrollView.contentOffset,
            offsetBeforeResize,
            "Resizing an accessory must not move the visible list position"
        )

        // Stay just inside the post-removal scroll range while still landing
        // within AetherList's bottom-anchor tolerance after the 80pt release.
        // Without the tab controller's raw-offset transaction the list snaps
        // these final four points to its new maximum.
        let expandedMaximumOffsetY = max(
            -scrollView.contentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.contentInset.bottom
        )
        let offsetBeforeRemoval = CGPoint(
            x: scrollView.contentOffset.x,
            y: expandedMaximumOffsetY - 84.0
        )
        scrollView.setContentOffset(offsetBeforeRemoval, animated: false)

        tabs.setBottomBarAccessory(nil, animated: true)
        XCTAssertEqual(scrollView.contentInset.bottom, baseBottomInset, accuracy: 0.01)
        XCTAssertEqual(
            scrollView.contentOffset,
            offsetBeforeRemoval,
            "Removing an accessory must not move the visible list position"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.40))
        XCTAssertEqual(
            scrollView.contentOffset,
            offsetBeforeRemoval,
            "The accessory retirement must not apply a delayed offset correction"
        )
    }

    @MainActor
    func testMinimizationDelegateCanSynchronouslyReverseWithoutLosingEndpoint() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let delegate = RecordingTabBarMinimizationDelegate()
        var didReverse = false
        delegate.onUpdate = { update in
            guard !didReverse, update.progress == 1.0 else { return }
            didReverse = true
            tabs.setTabBarMinimized(false, transition: .immediate)
        }
        tabs.minimizationDelegate = delegate

        tabs.setTabBarMinimized(true, transition: .immediate)

        XCTAssertTrue(didReverse)
        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 0.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(delegate.updates.last).progress, 0.0, accuracy: 0.001)
    }

    func testDefaultAccessoryUsesExactExpandedAndMinimizedEndpoints() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = TabBarAccessoryView()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let expandedSearchSlot = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            )
        )
        let minimizedSearchMaterial = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )
        let lens = try XCTUnwrap(tabs.view.firstDescendant(of: LiquidLensView.self))
        let searchGlassContainer = try XCTUnwrap(
            minimizedSearchMaterial.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
        )
        XCTAssertTrue(
            searchGlassContainer === lens.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
        )
        let expandedPill = try XCTUnwrap(tabs.pillFrame(in: tabs.view))

        assertFrame(
            expandedPill,
            equals: CGRect(x: 25.0, y: 763.0, width: 340.0, height: 60.0)
        )
        assertFrame(
            wrapper.frame,
            equals: CGRect(x: 25.0, y: 707.0, width: 340.0, height: 48.0)
        )
        XCTAssertEqual(expandedPill.minY - wrapper.frame.maxY, 8.0, accuracy: 0.001)
        let expandedInheritedSafeBottom = max(
            0.0,
            tabs.view.safeAreaInsets.bottom - tabs.additionalSafeAreaInsets.bottom
        )
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            max(0.0, TabBarView.defaultHeight - expandedInheritedSafeBottom) + 48.0 + 8.0,
            accuracy: 0.01
        )
        XCTAssertEqual(expandedSearchSlot.alpha, 1.0, accuracy: 0.001)
        XCTAssertFalse(expandedSearchSlot.isUserInteractionEnabled)
        XCTAssertEqual(minimizedSearchMaterial.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(
            minimizedSearchMaterial.chromeMorphMaterialAlpha,
            searchGlassContainer.isUsingNativeContainerEffect ? 1.0 : 0.0,
            accuracy: 0.001
        )
        XCTAssertEqual(minimizedSearchMaterial.chromeMorphContentAlpha, 1.0, accuracy: 0.001)
        XCTAssertTrue(minimizedSearchMaterial.isUserInteractionEnabled)

        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.view.layoutIfNeeded()

        let minimizedPill = try XCTUnwrap(tabs.pillFrame(in: tabs.view))
        let minimizedSearchFrame = minimizedSearchMaterial.convert(
            minimizedSearchMaterial.bounds,
            to: tabs.view
        )
        assertFrame(
            minimizedPill,
            equals: CGRect(x: 28.0, y: 775.0, width: 48.0, height: 48.0)
        )
        assertFrame(
            wrapper.frame,
            equals: CGRect(x: 89.0, y: 775.0, width: 212.0, height: 48.0)
        )
        assertFrame(
            minimizedSearchFrame,
            equals: CGRect(x: 314.0, y: 775.0, width: 48.0, height: 48.0)
        )
        XCTAssertEqual(wrapper.frame.minX - minimizedPill.maxX, 13.0, accuracy: 0.001)
        XCTAssertEqual(minimizedSearchFrame.minX - wrapper.frame.maxX, 13.0, accuracy: 0.001)
        XCTAssertEqual(minimizedPill.minX, 28.0, accuracy: 0.001)
        XCTAssertEqual(tabs.view.bounds.width - minimizedSearchFrame.maxX, 28.0, accuracy: 0.001)
        let minimizedInheritedSafeBottom = max(
            0.0,
            tabs.view.safeAreaInsets.bottom - tabs.additionalSafeAreaInsets.bottom
        )
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            max(0.0, TabBarView.defaultHeight - minimizedInheritedSafeBottom),
            accuracy: 0.01
        )
        XCTAssertEqual(expandedSearchSlot.alpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(minimizedSearchMaterial.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(minimizedSearchMaterial.chromeMorphMaterialAlpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(minimizedSearchMaterial.chromeMorphContentAlpha, 1.0, accuracy: 0.001)
        XCTAssertFalse(expandedSearchSlot.isUserInteractionEnabled)
        XCTAssertTrue(minimizedSearchMaterial.isUserInteractionEnabled)
    }

    func testAnimatedMinimizeHandsSearchToTheMovingGlassWithoutATransparentGap() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let expandedSearchSlot = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            )
        )
        let movingSearch = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )
        let lens = try XCTUnwrap(tabs.view.firstDescendant(of: LiquidLensView.self))
        let searchGlassContainer = try XCTUnwrap(
            movingSearch.firstAncestor(of: GlassBackgroundContainerView.self)
        )
        XCTAssertTrue(
            searchGlassContainer === lens.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
        )

        tabs.setTabBarMinimized(
            true,
            transition: .animated(duration: 0.12, curve: .linear)
        )

        // Search has one moving icon/interaction owner from sample zero. On
        // native glass its material stays fully alive inside the common group;
        // only fallback rendering fades the material as geometry separates.
        XCTAssertEqual(expandedSearchSlot.alpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(movingSearch.alpha, 1.0, accuracy: 0.001)
        if searchGlassContainer.isUsingNativeContainerEffect {
            XCTAssertEqual(movingSearch.chromeMorphMaterialAlpha, 1.0, accuracy: 0.001)
        } else {
            XCTAssertGreaterThan(movingSearch.chromeMorphMaterialAlpha, 0.0)
        }
        XCTAssertEqual(movingSearch.chromeMorphContentAlpha, 1.0, accuracy: 0.001)

        RunLoop.main.run(until: Date().addingTimeInterval(0.20))
    }

    @MainActor
    func testSearchGlyphOwnershipNeverLeavesBothRepresentationsInvisibleDuringCompactMorph() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let expandedSearch = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            )
        )
        let movingSearch = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )
        let lens = try XCTUnwrap(tabs.view.firstDescendant(of: LiquidLensView.self))
        let searchGlassContainer = try XCTUnwrap(
            movingSearch.firstAncestor(of: GlassBackgroundContainerView.self)
        )
        XCTAssertTrue(
            searchGlassContainer === lens.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
        )
        let delegate = RecordingTabBarMinimizationDelegate()
        var samples: [(
            expanded: CGFloat,
            moving: CGFloat,
            content: CGFloat,
            material: CGFloat
        )] = []
        let captureGlyphOwnership = {
            let expandedAlpha = CGFloat(
                expandedSearch.layer.presentation()?.opacity
                    ?? Float(expandedSearch.alpha)
            )
            let movingHostAlpha = CGFloat(
                movingSearch.layer.presentation()?.opacity
                    ?? Float(movingSearch.alpha)
            )
            samples.append((
                expanded: expandedAlpha,
                moving: movingHostAlpha * movingSearch.chromeMorphContentAlpha,
                content: movingSearch.chromeMorphContentAlpha,
                material: movingSearch.chromeMorphMaterialAlpha
            ))
        }
        delegate.onUpdate = { _ in captureGlyphOwnership() }
        tabs.minimizationDelegate = delegate

        let transition: ContainedViewLayoutTransition = .animated(
            duration: 0.24,
            curve: .linear
        )
        captureGlyphOwnership()
        tabs.setTabBarMinimized(true, transition: transition)
        captureGlyphOwnership()
        RunLoop.main.run(until: Date().addingTimeInterval(0.32))
        captureGlyphOwnership()

        tabs.setTabBarMinimized(false, transition: transition)
        captureGlyphOwnership()
        RunLoop.main.run(until: Date().addingTimeInterval(0.32))
        captureGlyphOwnership()

        XCTAssertGreaterThan(samples.count, 6)
        for sample in samples {
            XCTAssertGreaterThan(
                sample.moving,
                0.50,
                "The stable moving Search icon became invisible: \(sample)"
            )
            XCTAssertEqual(sample.content, 1.0, accuracy: 0.001)
            if searchGlassContainer.isUsingNativeContainerEffect {
                XCTAssertEqual(sample.material, 1.0, accuracy: 0.001)
            }
        }
        XCTAssertEqual(expandedSearch.alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(movingSearch.chromeMorphContentAlpha, 1.0, accuracy: 0.001)
    }

    @MainActor
    func testSearchGlassMergeAndSeparationPreserveSurfaceAndMaterialContinuity() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let movingSearch = try XCTUnwrap(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.moving"
            ) as? GlassBarButtonView
        )
        let searchGlass = try XCTUnwrap(
            movingSearch.firstDescendant(of: GlassBackgroundView.self)
        )
        let lens = try XCTUnwrap(tabs.view.firstDescendant(of: LiquidLensView.self))
        let searchGlassContainer = try XCTUnwrap(
            movingSearch.firstAncestor(of: GlassBackgroundContainerView.self)
        )
        XCTAssertTrue(
            searchGlassContainer === lens.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
        )
        let initialGlassIdentity = ObjectIdentifier(searchGlass)
        let initialStyle = searchGlass.styleForTesting
        let initialDarkOverride = searchGlass.isDarkOverride
        let delegate = RecordingTabBarMinimizationDelegate()
        var isSeparating = true
        var separationMaterial: [CGFloat] = []
        var mergeMaterial: [CGFloat] = []
        var movingContent: [CGFloat] = []
        delegate.onUpdate = { update in
            guard update.progress > 0.0, update.progress < 1.0 else { return }
            let opacity = movingSearch.chromeMorphMaterialAlpha
            movingContent.append(movingSearch.chromeMorphContentAlpha)
            if isSeparating {
                separationMaterial.append(opacity)
            } else {
                mergeMaterial.append(opacity)
            }
        }
        tabs.minimizationDelegate = delegate

        let transition: ContainedViewLayoutTransition = .animated(
            duration: 0.24,
            curve: .linear
        )
        tabs.setTabBarMinimized(true, transition: transition)
        RunLoop.main.run(until: Date().addingTimeInterval(0.32))
        XCTAssertEqual(movingSearch.chromeMorphMaterialAlpha, 1.0, accuracy: 0.001)

        isSeparating = false
        tabs.setTabBarMinimized(false, transition: transition)
        RunLoop.main.run(until: Date().addingTimeInterval(0.32))

        XCTAssertGreaterThan(separationMaterial.count, 2)
        XCTAssertGreaterThan(mergeMaterial.count, 2)
        if searchGlassContainer.isUsingNativeContainerEffect {
            for material in separationMaterial + mergeMaterial {
                XCTAssertEqual(
                    material,
                    1.0,
                    accuracy: 0.001,
                    "Native Search material must stay alive while its common glass group merges"
                )
            }
        } else {
            for (previous, current) in zip(
                separationMaterial,
                separationMaterial.dropFirst()
            ) {
                XCTAssertGreaterThanOrEqual(
                    current + 0.03,
                    previous,
                    "Fallback Search material stepped backward while separating"
                )
            }
            for (previous, current) in zip(mergeMaterial, mergeMaterial.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    current,
                    previous + 0.03,
                    "Fallback Search material stepped forward while merging"
                )
            }
        }
        XCTAssertTrue(
            separationMaterial.allSatisfy { $0 >= 0.0 && $0 <= 1.001 }
        )
        XCTAssertTrue(mergeMaterial.allSatisfy { $0 >= 0.0 && $0 <= 1.001 })
        XCTAssertTrue(movingContent.allSatisfy { abs($0 - 1.0) <= 0.001 })
        XCTAssertEqual(ObjectIdentifier(searchGlass), initialGlassIdentity)
        XCTAssertEqual(searchGlass.styleForTesting, initialStyle)
        XCTAssertEqual(searchGlass.isDarkOverride, initialDarkOverride)
        XCTAssertEqual(
            movingSearch.chromeMorphMaterialAlpha,
            searchGlassContainer.isUsingNativeContainerEffect ? 1.0 : 0.0,
            accuracy: 0.001
        )
        XCTAssertEqual(movingSearch.chromeMorphContentAlpha, 1.0, accuracy: 0.001)
    }

    @MainActor
    func testAccessoryInsetOffsetCompensationDoesNotReverseCommittedMinimize() {
        let content = ChromeScrollFixtureController()
        content.tabBarItem = UITabBarItem(
            title: "List",
            image: UIImage(systemName: "list.bullet"),
            selectedImage: UIImage(systemName: "list.bullet")
        )
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()
        content.chromeScrollView.simulatesUserDrivenScroll = true

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Crossing the full 56pt spatial threshold must commit immediately"
        )

        // Model UIKit preserving the visible content position while the 48pt
        // accessory + 8pt gap reservation changes. The real scroll view can
        // still report `isDragging` during these paired KVO mutations.
        let compensation: CGFloat = 48.0 + 8.0
        content.chromeScrollView.contentInset.top = compensation
        content.chromeScrollView.contentOffset = CGPoint(
            x: 0.0,
            y: 256.0 - compensation
        )

        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Accessory inset compensation was mistaken for a genuine upward intent"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        content.chromeScrollView.contentOffset = CGPoint(
            x: 0.0,
            y: 236.0 - compensation
        )
        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "A subsequent genuine upward threshold must still expand"
        )
    }

    @MainActor
    func testScrollDrivenMinimizedStateSurvivesAetherNavigationPopWithAccessory() {
        let root = ChromeScrollFixtureController()
        root.tabBarItem = UITabBarItem(
            title: "Root",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 320.0)
        let detail = ChromeScrollFixtureController()
        detail.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let navigation = AetherNavigationController(mode: .single)
        navigation.setViewControllers([root], animated: false)
        let fixture = makeTabBarFixture(controllers: [
            navigation,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let rootOffset = root.chromeScrollView.contentOffset
        navigation.pushViewController(detail, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === detail.chromeScrollView)

        detail.chromeScrollView.simulatesUserDrivenScroll = true
        detail.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "The detail screen did not commit the 56pt scroll-driven minimize"
        )
        detail.chromeScrollView.simulatesUserDrivenScroll = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        _ = navigation.popViewController(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        tabs.view.layoutIfNeeded()

        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === root.chromeScrollView)
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Returning to the previous screen reset the shared minimized endpoint"
        )
        XCTAssertEqual(
            root.chromeScrollView.contentOffset,
            rootOffset,
            "Returning with an inline accessory moved the previous list"
        )

        tabs.setTabBarMinimized(false, transition: .immediate)
        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertEqual(root.chromeScrollView.contentOffset, rootOffset)

        navigation.pushViewController(detail, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "Re-entering detail restored a stale per-screen minimized endpoint"
        )
    }

    @MainActor
    func testShortContentKeepsSharedMinimizedStateAndPopPreservesOffset() throws {
        let root = ChromeScrollFixtureController()
        root.tabBarItem = UITabBarItem(
            title: "Root",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        root.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 320.0)

        let shortDetail = ChromeScrollFixtureController()
        shortDetail.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        shortDetail.chromeScrollView.contentSize = CGSize(
            width: 390.0,
            height: 120.0
        )

        let navigation = AetherNavigationController(mode: .single)
        navigation.setViewControllers([root], animated: false)
        let fixture = makeTabBarFixture(controllers: [
            navigation,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        root.chromeScrollView.simulatesUserDrivenScroll = true
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 376.0)
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "The long root did not commit the scroll-driven minimize"
        )
        root.chromeScrollView.simulatesUserDrivenScroll = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        tabs.view.layoutIfNeeded()

        let rootOffsetBeforePush = root.chromeScrollView.contentOffset
        let rootBottomInsetBeforePush = root.chromeScrollView.adjustedContentInset.bottom
        let reservationBeforePush = tabs.additionalSafeAreaInsets.bottom
        XCTAssertEqual(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)).width,
            TabBarView.minimizedButtonSize,
            accuracy: 0.5
        )

        navigation.pushViewController(shortDetail, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        tabs.view.layoutIfNeeded()

        XCTAssertTrue(
            tabs.observedChromeScrollViewForTesting === shortDetail.chromeScrollView
        )
        let shortMinimumY = -shortDetail.chromeScrollView.adjustedContentInset.top
        let shortMaximumY = max(
            shortMinimumY,
            shortDetail.chromeScrollView.contentSize.height
                - shortDetail.chromeScrollView.bounds.height
                + shortDetail.chromeScrollView.adjustedContentInset.bottom
        )
        XCTAssertLessThanOrEqual(
            shortMaximumY - shortMinimumY,
            0.5,
            "The detail fixture must not have a usable vertical scroll range"
        )
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "A short scroll source reset the controller-wide minimized endpoint"
        )
        XCTAssertEqual(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)).width,
            TabBarView.minimizedButtonSize,
            accuracy: 0.5,
            "The short screen expanded only the rendered tab bar"
        )
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            reservationBeforePush,
            accuracy: 0.5,
            "The short screen changed the shared bottom reservation"
        )

        _ = navigation.popViewController(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        tabs.view.layoutIfNeeded()

        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === root.chromeScrollView)
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Returning from short content replayed a stale minimized endpoint"
        )
        XCTAssertEqual(
            root.chromeScrollView.adjustedContentInset.bottom,
            rootBottomInsetBeforePush,
            accuracy: 0.5,
            "Returning from short content changed the root bottom inset"
        )
        XCTAssertEqual(
            root.chromeScrollView.contentOffset,
            rootOffsetBeforePush,
            "Returning from short content moved the root list"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(
            root.chromeScrollView.contentOffset,
            rootOffsetBeforePush,
            "A delayed layout pass moved the root list after returning"
        )
    }

    @MainActor
    func testDeferredAccessoryReservationStaysWithOriginThroughAnimatedShortPush() {
        let root = ChromeScrollFixtureController()
        root.tabBarItem = UITabBarItem(
            title: "Root",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        root.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)

        let shortDetail = ChromeScrollFixtureController()
        shortDetail.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        shortDetail.chromeScrollView.contentSize = CGSize(width: 390.0, height: 120.0)

        let navigation = AetherNavigationController(mode: .single)
        navigation.setViewControllers([root], animated: false)
        let fixture = makeTabBarFixture(controllers: [
            navigation,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let expandedReservation = tabs.additionalSafeAreaInsets.bottom
        root.chromeScrollView.simulatesUserDrivenScroll = true
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)
        XCTAssertTrue(tabs.isTabBarMinimized)
        XCTAssertEqual(tabs.additionalSafeAreaInsets.bottom, expandedReservation, accuracy: 0.01)

        // Keep the originating list in deceleration while navigation rebinds
        // observation to a short, stationary destination. The held reservation
        // must remain owned by the root instead of being released from the new
        // source's idle metrics in the middle of the push.
        root.chromeScrollView.simulatesUserDrivenScroll = false
        root.chromeScrollView.simulatesDeceleration = true
        let rootOffsetBeforePush = root.chromeScrollView.contentOffset
        navigation.pushViewController(shortDetail, animated: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        XCTAssertTrue(navigation.isTransitioning)
        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === shortDetail.chromeScrollView)
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01,
            "Rebinding to idle short content released the origin's reservation during push"
        )

        root.chromeScrollView.simulatesDeceleration = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertTrue(navigation.isTransitioning)
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01,
            "The reservation changed before the navigation transition completed"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.50))
        tabs.view.layoutIfNeeded()
        XCTAssertFalse(navigation.isTransitioning)
        XCTAssertEqual(
            expandedReservation - tabs.additionalSafeAreaInsets.bottom,
            56.0,
            accuracy: 0.01
        )
        XCTAssertTrue(tabs.isTabBarMinimized)
        XCTAssertEqual(
            root.chromeScrollView.contentOffset,
            rootOffsetBeforePush,
            "Deferred release moved the originating list after observer rebind"
        )
    }

    @MainActor
    func testDeferredAccessoryReleaseWaitsForAndPreservesReboundDestination() {
        let root = ChromeScrollFixtureController()
        root.tabBarItem = UITabBarItem(
            title: "Root",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        root.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)

        let detail = ChromeScrollFixtureController()
        detail.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        detail.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 320.0)

        let navigation = AetherNavigationController(mode: .single)
        navigation.setViewControllers([root], animated: false)
        let fixture = makeTabBarFixture(controllers: [
            navigation,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let expandedReservation = tabs.additionalSafeAreaInsets.bottom
        root.chromeScrollView.simulatesUserDrivenScroll = true
        root.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)
        root.chromeScrollView.simulatesUserDrivenScroll = false
        root.chromeScrollView.simulatesDeceleration = true
        let rootOffsetBeforePush = root.chromeScrollView.contentOffset

        navigation.pushViewController(detail, animated: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.50))
        XCTAssertFalse(navigation.isTransitioning)
        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === detail.chromeScrollView)
        XCTAssertEqual(tabs.additionalSafeAreaInsets.bottom, expandedReservation, accuracy: 0.01)

        detail.chromeScrollView.simulatesUserDrivenScroll = true
        detail.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 376.0)
        let detailOffsetBeforeRelease = detail.chromeScrollView.contentOffset
        root.chromeScrollView.simulatesDeceleration = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01,
            "The origin stopped, but the active destination still owned its drag"
        )

        detail.chromeScrollView.simulatesUserDrivenScroll = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(
            expandedReservation - tabs.additionalSafeAreaInsets.bottom,
            56.0,
            accuracy: 0.01
        )
        XCTAssertEqual(root.chromeScrollView.contentOffset, rootOffsetBeforePush)
        XCTAssertEqual(
            detail.chromeScrollView.contentOffset,
            detailOffsetBeforeRelease,
            "Deferred release moved the active destination after observer rebind"
        )
    }

    @MainActor
    func testAnimatedAetherListShortDetailRoundTripKeepsCompactAccessoryAndRootOffset() throws {
        let root = NavigationLifecycleListController(itemCount: 40)
        root.tabBarItem = UITabBarItem(
            title: "Root",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        let shortDetail = NavigationLifecycleListController(itemCount: 3)
        let navigation = AetherNavigationController(mode: .single)
        navigation.setViewControllers([root], animated: false)
        let fixture = makeTabBarFixture(controllers: [
            navigation,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown

        root.installItems()
        shortDetail.loadViewIfNeeded()
        shortDetail.installItems()
        tabs.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        root.listNode.view.layoutIfNeeded()
        root.listNode.scrollToBottom(animated: false)

        // Match the recording's starting endpoint: the long root is parked at
        // its bottom with the accessory already inline in compact chrome.
        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        root.listNode.view.layoutIfNeeded()

        let rootScroller = root.listNode.scroller
        let rootOffsetBeforePush = rootScroller.contentOffset
        let rootBottomInsetBeforePush = rootScroller.contentInset.bottom
        let compactReservation = tabs.additionalSafeAreaInsets.bottom
        XCTAssertTrue(tabs.isTabBarMinimized)

        XCTAssertLessThanOrEqual(
            abs(root.listNode.visibleBottomContentOffset()),
            0.5,
            "The root must exercise the near-bottom anchor visible in the recording"
        )
        XCTAssertEqual(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)).width,
            TabBarView.minimizedButtonSize,
            accuracy: 0.5
        )

        func observeAnimatedLifecycle(
            duration: TimeInterval
        ) -> (expandedSampleCount: Int, maximumReservationDelta: CGFloat, maximumRootOffsetDelta: CGFloat) {
            let deadline = Date().addingTimeInterval(duration)
            var expandedSampleCount = 0
            var maximumReservationDelta: CGFloat = 0.0
            var maximumRootOffsetDelta: CGFloat = 0.0
            repeat {
                RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120.0))
                tabs.view.layoutIfNeeded()
                if !tabs.isTabBarMinimized {
                    expandedSampleCount += 1
                }
                maximumReservationDelta = max(
                    maximumReservationDelta,
                    abs(tabs.additionalSafeAreaInsets.bottom - compactReservation)
                )
                maximumRootOffsetDelta = max(
                    maximumRootOffsetDelta,
                    abs(rootScroller.contentOffset.y - rootOffsetBeforePush.y)
                )
            } while Date() < deadline
            return (
                expandedSampleCount,
                maximumReservationDelta,
                maximumRootOffsetDelta
            )
        }

        navigation.pushViewController(shortDetail, animated: true)
        let pushSamples = observeAnimatedLifecycle(duration: 0.75)
        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === shortDetail.listNode.scroller)
        let shortMinimumY = -shortDetail.listNode.scroller.adjustedContentInset.top
        let shortMaximumY = max(
            shortMinimumY,
            shortDetail.listNode.scroller.contentSize.height
                - shortDetail.listNode.scroller.bounds.height
                + shortDetail.listNode.scroller.adjustedContentInset.bottom
        )
        XCTAssertLessThanOrEqual(
            shortMaximumY - shortMinimumY,
            0.5,
            "The pushed detail must be too short to derive a new scroll intent"
        )
        XCTAssertEqual(
            pushSamples.expandedSampleCount,
            0,
            "The short detail transiently restored full chrome during the animated push"
        )
        XCTAssertEqual(pushSamples.maximumReservationDelta, 0.0, accuracy: 0.5)
        XCTAssertEqual(pushSamples.maximumRootOffsetDelta, 0.0, accuracy: 0.5)

        _ = navigation.popViewController(animated: true)
        let popSamples = observeAnimatedLifecycle(duration: 0.75)
        XCTAssertTrue(tabs.observedChromeScrollViewForTesting === rootScroller)
        XCTAssertTrue(tabs.isTabBarMinimized)
        XCTAssertEqual(
            popSamples.expandedSampleCount,
            0,
            "The root entered the pop with full chrome before restoring compact state"
        )
        XCTAssertEqual(
            popSamples.maximumReservationDelta,
            0.0,
            accuracy: 0.5,
            "The accessory left and re-entered the inline row during the pop"
        )
        XCTAssertEqual(
            popSamples.maximumRootOffsetDelta,
            0.0,
            accuracy: 0.5,
            "The compact/full reservation round-trip visibly moved the root list"
        )
        XCTAssertEqual(rootScroller.contentInset.bottom, rootBottomInsetBeforePush, accuracy: 0.5)
        XCTAssertEqual(rootScroller.contentOffset, rootOffsetBeforePush)

        RunLoop.main.run(until: Date().addingTimeInterval(0.20))
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(
            rootScroller.contentOffset,
            rootOffsetBeforePush,
            "A delayed post-pop layout moved the root list"
        )
    }

    @MainActor
    func testCommittedMinimizeAllowsImmediateIntentionalOppositeScroll() {
        let content = ChromeScrollFixtureController()
        content.tabBarItem = UITabBarItem(
            title: "List",
            image: UIImage(systemName: "list.bullet"),
            selectedImage: UIImage(systemName: "list.bullet")
        )
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.tabBarMinimizeBehavior = .onScrollDown
        content.chromeScrollView.simulatesUserDrivenScroll = true

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Crossing the full 56pt spatial threshold must commit immediately"
        )

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 236.0)
        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "After commit, a fresh intentional upward threshold may expand immediately"
        )
    }

    @MainActor
    func testScrollDownPreviewProgressesSpatiallyUntilImmediateFullThresholdCommit() throws {
        let content = ChromeScrollFixtureController()
        let listItem = UITabBarItem()
        listItem.title = "List"
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.selectedImage = UIImage(systemName: "list.bullet")
        content.tabBarItem = listItem
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        let accessory = FixedBottomAccessoryView(height: 48.0)
        tabs.bottomBarAccessory = accessory
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let pillLens = try XCTUnwrap(
            tabs.view.firstDescendant(of: LiquidLensView.self)
        )
        let pill = try XCTUnwrap(pillLens.superview)
        let accessoryWrapper = try XCTUnwrap(
            accessory.firstAncestor(of: GlassBackgroundView.self)
        )
        let expandedPillBounds = pill.bounds
        let expandedAccessoryBounds = accessoryWrapper.bounds
        let expandedAccessoryFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)
        var accessoryFrames = [expandedAccessoryFrame]
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))

        content.chromeScrollView.simulatesUserDrivenScroll = true
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 208.0)

        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
        XCTAssertEqual(pill.bounds, expandedPillBounds)
        XCTAssertEqual(accessoryWrapper.bounds, expandedAccessoryBounds)
        accessoryFrames.append(try XCTUnwrap(tabs.bottomBarAccessoryFrame))

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 216.0)
        XCTAssertEqual(pill.layer.sublayerTransform.m11, 0.9975, accuracy: 0.001)
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            0.9975,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pill.bounds.width,
            expandedPillBounds.width - 8.0 / 6.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 8.0 / 6.0,
            accuracy: 0.01
        )
        accessoryFrames.append(try XCTUnwrap(tabs.bottomBarAccessoryFrame))

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 224.0)

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "A partial downward preview must not commit the compact endpoint"
        )
        XCTAssertLessThan(pill.layer.sublayerTransform.m11, 1.0)
        XCTAssertGreaterThan(pill.layer.sublayerTransform.m11, 0.985)
        XCTAssertLessThan(accessoryWrapper.layer.sublayerTransform.m11, 1.0)
        XCTAssertGreaterThan(accessoryWrapper.layer.sublayerTransform.m11, 0.985)
        XCTAssertLessThan(pill.bounds.width, expandedPillBounds.width)
        XCTAssertGreaterThan(pill.bounds.width, expandedPillBounds.width - 8.0)
        XCTAssertLessThan(accessoryWrapper.bounds.width, expandedAccessoryBounds.width)
        XCTAssertGreaterThan(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 8.0
        )
        XCTAssertEqual(pill.layer.sublayerTransform.m11, 0.995, accuracy: 0.001)
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            0.995,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pill.bounds.width,
            expandedPillBounds.width - 8.0 / 3.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 8.0 / 3.0,
            accuracy: 0.01
        )
        accessoryFrames.append(try XCTUnwrap(tabs.bottomBarAccessoryFrame))

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 240.0)
        XCTAssertEqual(pill.layer.sublayerTransform.m11, 0.990, accuracy: 0.001)
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            0.990,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pill.bounds.width,
            expandedPillBounds.width - 16.0 / 3.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 16.0 / 3.0,
            accuracy: 0.01
        )
        accessoryFrames.append(try XCTUnwrap(tabs.bottomBarAccessoryFrame))

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 255.0)

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "A near-full spatial preview must remain expanded until it crosses 56pt"
        )
        XCTAssertEqual(pill.layer.sublayerTransform.m11, 0.9853125, accuracy: 0.001)
        XCTAssertEqual(pill.layer.sublayerTransform.m22, 0.9853125, accuracy: 0.001)
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            0.9853125,
            accuracy: 0.001
        )
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m22,
            0.9853125,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pill.bounds.width,
            expandedPillBounds.width - 47.0 / 6.0,
            accuracy: 0.01,
            "Near-full preview must approach the 4pt outer inset continuously"
        )
        XCTAssertEqual(pill.bounds.height, expandedPillBounds.height, accuracy: 0.01)
        XCTAssertEqual(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 47.0 / 6.0,
            accuracy: 0.01,
            "Accessory preview must approach the pill inset continuously"
        )
        XCTAssertEqual(
            accessoryWrapper.bounds.height,
            expandedAccessoryBounds.height,
            accuracy: 0.01
        )
        accessoryFrames.append(try XCTUnwrap(tabs.bottomBarAccessoryFrame))
        let distinctAccessoryWidths = Set(
            accessoryFrames.map { Int(($0.width * 1_000.0).rounded()) }
        )
        XCTAssertGreaterThanOrEqual(
            distinctAccessoryWidths.count,
            5,
            "Accessory geometry must move through real intermediate frames, not jump to full preview"
        )

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)

        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "The full 56pt spatial threshold must commit without a time dwell"
        )
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
    }

    @MainActor
    func testPartialPreviewCancelsOnFingerUpAndDecelerationCannotLateCommit() throws {
        let content = ChromeScrollFixtureController()
        let listItem = UITabBarItem()
        listItem.title = "List"
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.selectedImage = UIImage(systemName: "list.bullet")
        content.tabBarItem = listItem
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        let accessory = FixedBottomAccessoryView(height: 48.0)
        tabs.bottomBarAccessory = accessory
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let pillLens = try XCTUnwrap(
            tabs.view.firstDescendant(of: LiquidLensView.self)
        )
        let pill = try XCTUnwrap(pillLens.superview)
        let accessoryWrapper = try XCTUnwrap(
            accessory.firstAncestor(of: GlassBackgroundView.self)
        )
        let expandedPillBounds = pill.bounds
        let expandedAccessoryBounds = accessoryWrapper.bounds
        let expandedAccessoryCenter = accessoryWrapper.center
        let expandedPillFrame = try XCTUnwrap(tabs.pillFrame(in: tabs.view))
        let expandedAccessoryFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)

        content.chromeScrollView.simulatesUserDrivenScroll = true
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 224.0)
        let partialPillScale = pill.layer.sublayerTransform.m11
        let partialAccessoryScale = accessoryWrapper.layer.sublayerTransform.m11
        XCTAssertGreaterThan(partialPillScale, 0.985)
        XCTAssertLessThan(partialPillScale, 1.0)
        XCTAssertGreaterThan(partialAccessoryScale, 0.985)
        XCTAssertLessThan(partialAccessoryScale, 1.0)

        tabs.advanceTabBarMinimizeArmingForTesting(by: 1.0)

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "Time alone must not commit a partial spatial preview while the finger is active"
        )
        XCTAssertEqual(
            pill.layer.sublayerTransform.m11,
            partialPillScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            partialAccessoryScale,
            accuracy: 0.001
        )

        let partialContentOffset = content.chromeScrollView.contentOffset
        let childLayoutUpdateCountBeforeCancel = content.containerLayoutUpdateCount
        content.chromeScrollView.simulatesUserDrivenScroll = false
        content.chromeScrollView.simulatesDeceleration = true
        tabs.endTabBarMinimizeScrollInteractionForTesting()

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "Finger-up below the full threshold must cancel the preview"
        )
        XCTAssertEqual(
            content.chromeScrollView.contentOffset,
            partialContentOffset,
            "Cancelling a visual preview must preserve the exact content offset"
        )
        XCTAssertEqual(
            content.containerLayoutUpdateCount,
            childLayoutUpdateCountBeforeCancel,
            "Cancelling a visual preview must not run a full child container layout"
        )
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
        XCTAssertEqual(pill.bounds, expandedPillBounds)
        XCTAssertEqual(accessoryWrapper.bounds, expandedAccessoryBounds)
        XCTAssertEqual(accessoryWrapper.center, expandedAccessoryCenter)

        RunLoop.main.run(until: Date().addingTimeInterval(0.30))

        assertFrame(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)),
            equals: expandedPillFrame
        )
        assertFrame(
            try XCTUnwrap(tabs.bottomBarAccessoryFrame),
            equals: expandedAccessoryFrame
        )

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 280.0)
        tabs.advanceTabBarMinimizeArmingForTesting(by: 2.0)

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "Deceleration, additional offset, and elapsed time must not late-commit a cancelled preview"
        )
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
        XCTAssertEqual(pill.bounds, expandedPillBounds)
        XCTAssertEqual(accessoryWrapper.bounds, expandedAccessoryBounds)
        assertFrame(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)),
            equals: expandedPillFrame
        )
        assertFrame(
            try XCTUnwrap(tabs.bottomBarAccessoryFrame),
            equals: expandedAccessoryFrame
        )
    }

    @MainActor
    func testAutoMinimizeDefersAccessorySafeAreaReservationUntilScrollingStops() {
        let content = ChromeScrollFixtureController()
        let listItem = UITabBarItem()
        listItem.title = "List"
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.selectedImage = UIImage(systemName: "list.bullet")
        content.tabBarItem = listItem
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let expandedReservation = tabs.additionalSafeAreaInsets.bottom
        let minimizedReservation = expandedReservation - (48.0 + 8.0)
        XCTAssertGreaterThan(expandedReservation, minimizedReservation)

        content.chromeScrollView.simulatesUserDrivenScroll = true
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 256.0)

        XCTAssertTrue(tabs.isTabBarMinimized)
        let contentOffsetBeforeStopping = content.chromeScrollView.contentOffset
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01,
            "Auto minimize changed child safe area while the drag still owned content position"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01
        )
        XCTAssertEqual(content.chromeScrollView.contentOffset, contentOffsetBeforeStopping)
        XCTAssertTrue(tabs.isTabBarMinimized)

        content.chromeScrollView.simulatesUserDrivenScroll = false
        content.chromeScrollView.simulatesDeceleration = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01,
            "Accessory reservation must remain held throughout deceleration"
        )
        XCTAssertEqual(content.chromeScrollView.contentOffset, contentOffsetBeforeStopping)
        XCTAssertTrue(tabs.isTabBarMinimized)

        content.chromeScrollView.simulatesDeceleration = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            minimizedReservation,
            accuracy: 0.01,
            "The deferred minimized reservation was not applied after scrolling stopped"
        )
        XCTAssertEqual(
            content.chromeScrollView.contentOffset,
            contentOffsetBeforeStopping,
            "Applying deferred accessory safe area must preserve the exact visible scroll position"
        )
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Deferred safe-area application must not feed back into auto-expand"
        )
    }

    @MainActor
    func testDeferredAccessorySafeAreaReleasePreservesNearBottomOffset() {
        let content = ChromeScrollFixtureController()
        let listItem = UITabBarItem()
        listItem.title = "List"
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.selectedImage = UIImage(systemName: "list.bullet")
        content.tabBarItem = listItem
        content.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let scrollView = content.chromeScrollView
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.view.layoutIfNeeded()
        content.view.layoutIfNeeded()

        let expandedReservation = tabs.additionalSafeAreaInsets.bottom
        let minimizedReservation = expandedReservation - (48.0 + 8.0)
        let expandedAdjustedBottom = scrollView.adjustedContentInset.bottom
        let expandedMaximumOffsetY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + expandedAdjustedBottom
        )
        XCTAssertGreaterThan(expandedMaximumOffsetY, 56.0)

        let expandedBottomGap: CGFloat = 24.0
        scrollView.contentOffset = CGPoint(
            x: 0.0,
            y: expandedMaximumOffsetY - expandedBottomGap - 56.0
        )
        tabs.tabBarMinimizeBehavior = .onScrollDown
        scrollView.simulatesUserDrivenScroll = true
        scrollView.contentOffset = CGPoint(
            x: 0.0,
            y: expandedMaximumOffsetY - expandedBottomGap
        )

        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "The full near-bottom 56pt gesture must commit immediately"
        )
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01
        )
        XCTAssertLessThanOrEqual(scrollView.contentOffset.y, expandedMaximumOffsetY)
        XCTAssertEqual(
            expandedMaximumOffsetY - scrollView.contentOffset.y,
            expandedBottomGap,
            accuracy: 0.01,
            "The fixture must begin inside the scroll range, without overscroll"
        )

        scrollView.simulatesUserDrivenScroll = false
        scrollView.simulatesDeceleration = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let contentOffsetBeforeStopping = scrollView.contentOffset
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01
        )

        scrollView.simulatesDeceleration = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        tabs.view.layoutIfNeeded()
        content.view.layoutIfNeeded()

        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            minimizedReservation,
            accuracy: 0.01
        )
        let minimizedMaximumOffsetY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        XCTAssertEqual(
            expandedAdjustedBottom - scrollView.adjustedContentInset.bottom,
            56.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            expandedMaximumOffsetY - minimizedMaximumOffsetY,
            56.0,
            accuracy: 0.01,
            "The fixture must exercise a real 56pt reduction in maximum scroll offset"
        )
        let bottomGapBeforeRelease = expandedMaximumOffsetY
            - contentOffsetBeforeStopping.y
        XCTAssertEqual(bottomGapBeforeRelease, expandedBottomGap, accuracy: 0.01)
        let expectedReleasedOffset = CGPoint(
            x: contentOffsetBeforeStopping.x,
            y: minimizedMaximumOffsetY - bottomGapBeforeRelease
        )
        XCTAssertEqual(
            scrollView.contentOffset.x,
            expectedReleasedOffset.x,
            accuracy: 0.001
        )
        XCTAssertEqual(
            scrollView.contentOffset.y,
            expectedReleasedOffset.y,
            accuracy: 0.01,
            "Near the bottom, safe-area release must preserve the bottom gap instead of the stale raw offset"
        )
        XCTAssertLessThanOrEqual(scrollView.contentOffset.y, minimizedMaximumOffsetY)
        XCTAssertEqual(
            minimizedMaximumOffsetY - scrollView.contentOffset.y,
            bottomGapBeforeRelease,
            accuracy: 0.01
        )
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "The reservation release must not be interpreted as upward user intent"
        )
    }

    @MainActor
    func testDeferredAccessorySafeAreaReleasePreservesMiddleAutomaticInsetOffset() {
        let content = ChromeScrollFixtureController()
        let listItem = UITabBarItem()
        listItem.title = "List"
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.selectedImage = UIImage(systemName: "list.bullet")
        content.tabBarItem = listItem
        content.chromeScrollView.contentInsetAdjustmentBehavior = .automatic
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let scrollView = content.chromeScrollView
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 48.0)
        tabs.view.layoutIfNeeded()
        content.view.layoutIfNeeded()

        let expandedReservation = tabs.additionalSafeAreaInsets.bottom
        let minimizedReservation = expandedReservation - (48.0 + 8.0)
        let expandedAdjustedBottom = scrollView.adjustedContentInset.bottom
        scrollView.contentOffset = CGPoint(x: 0.0, y: 400.0)
        tabs.tabBarMinimizeBehavior = .onScrollDown
        scrollView.simulatesUserDrivenScroll = true
        scrollView.contentOffset = CGPoint(x: 0.0, y: 456.0)

        XCTAssertTrue(tabs.isTabBarMinimized)
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            expandedReservation,
            accuracy: 0.01
        )

        scrollView.simulatesUserDrivenScroll = false
        scrollView.simulatesDeceleration = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let rawOffsetBeforeStopping = scrollView.contentOffset
        let expandedMaximumNormalizedOffset = max(
            0.0,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        let normalizedOffsetBeforeStopping = min(
            expandedMaximumNormalizedOffset,
            max(
                0.0,
                rawOffsetBeforeStopping.y + scrollView.adjustedContentInset.top
            )
        )

        scrollView.simulatesDeceleration = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        tabs.view.layoutIfNeeded()
        content.view.layoutIfNeeded()

        let minimizedMaximumNormalizedOffset = max(
            0.0,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        let normalizedOffsetAfterRelease = min(
            minimizedMaximumNormalizedOffset,
            max(
                0.0,
                scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            )
        )
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            minimizedReservation,
            accuracy: 0.01
        )
        XCTAssertEqual(
            expandedAdjustedBottom - scrollView.adjustedContentInset.bottom,
            56.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            scrollView.contentOffset,
            rawOffsetBeforeStopping,
            "In the middle of content, releasing bottom safe area must preserve raw contentOffset"
        )
        XCTAssertEqual(
            normalizedOffsetAfterRelease,
            normalizedOffsetBeforeStopping,
            accuracy: 0.01,
            "In the middle of content, releasing bottom safe area must preserve the normalized visible position"
        )
        XCTAssertTrue(
            tabs.isTabBarMinimized,
            "Middle-content safe-area release must not feed back into auto-expand"
        )
    }

    @MainActor
    func testCommittedMinimizeAndExpandShareUnderdampedIntermediateOvershoot() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Reduce Motion intentionally removes compact spring overshoot")
        }
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        let accessory = FixedBottomAccessoryView(height: 48.0)
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let pillLens = try XCTUnwrap(
            tabs.view.firstDescendant(of: LiquidLensView.self)
        )
        let pill = try XCTUnwrap(pillLens.superview)
        let expandedPillFrame = try XCTUnwrap(tabs.pillFrame(in: tabs.view))
        let expandedAccessoryFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)

        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.view.layoutIfNeeded()
        let minimizedPillFrame = try XCTUnwrap(tabs.pillFrame(in: tabs.view))
        let minimizedAccessoryFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)
        tabs.setTabBarMinimized(false, transition: .immediate)
        tabs.view.layoutIfNeeded()

        let delegate = RecordingTabBarMinimizationDelegate()
        var isMinimizing = true
        var minimizingPillWidths: [CGFloat] = []
        var minimizingAccessoryWidths: [CGFloat] = []
        var expandingPillWidths: [CGFloat] = []
        var expandingAccessoryWidths: [CGFloat] = []
        delegate.onUpdate = { update in
            let pillWidth = pill.layer.presentation()?.frame.width
                ?? pill.frame.width
            if isMinimizing {
                minimizingPillWidths.append(pillWidth)
                if let width = update.bottomBarAccessoryFrame?.width {
                    minimizingAccessoryWidths.append(width)
                }
            } else {
                expandingPillWidths.append(pillWidth)
                if let width = update.bottomBarAccessoryFrame?.width {
                    expandingAccessoryWidths.append(width)
                }
            }
        }
        tabs.minimizationDelegate = delegate

        let motion = AetherMotion.tabBarMorph
        XCTAssertLessThan(motion.dampingRatio, 1.0)
        let transition: ContainedViewLayoutTransition = .animated(
            duration: motion.duration,
            curve: .customSpring(
                damping: motion.dampingRatio,
                initialVelocity: motion.initialVelocity
            )
        )

        tabs.setTabBarMinimized(true, transition: transition)
        RunLoop.main.run(until: Date().addingTimeInterval(motion.duration + 0.15))

        isMinimizing = false
        tabs.setTabBarMinimized(false, transition: transition)
        RunLoop.main.run(until: Date().addingTimeInterval(motion.duration + 0.15))

        XCTAssertGreaterThan(minimizingPillWidths.count, 4)
        XCTAssertGreaterThan(minimizingAccessoryWidths.count, 4)
        XCTAssertGreaterThan(expandingPillWidths.count, 4)
        XCTAssertGreaterThan(expandingAccessoryWidths.count, 4)
        XCTAssertTrue(
            minimizingPillWidths.contains {
                $0 < expandedPillFrame.width - 1.0
                    && $0 > minimizedPillFrame.width + 1.0
            },
            "Minimize must publish real intermediate pill geometry"
        )
        XCTAssertTrue(
            expandingPillWidths.contains {
                $0 < expandedPillFrame.width - 1.0
                    && $0 > minimizedPillFrame.width + 1.0
            },
            "Expand must publish real intermediate pill geometry"
        )
        XCTAssertTrue(
            minimizingPillWidths.contains {
                $0 < minimizedPillFrame.width - 0.10
            },
            "Minimize spring never crossed its compact pill endpoint"
        )
        XCTAssertTrue(
            expandingPillWidths.contains {
                $0 > expandedPillFrame.width + 0.10
            },
            "Expand spring never crossed its expanded pill endpoint"
        )
        XCTAssertTrue(
            minimizingAccessoryWidths.contains {
                $0 < minimizedAccessoryFrame.width - 0.10
            },
            "Minimize spring never crossed its inline accessory endpoint"
        )
        XCTAssertTrue(
            expandingAccessoryWidths.contains {
                $0 > expandedAccessoryFrame.width + 0.10
            },
            "Expand spring never crossed its regular accessory endpoint"
        )
        assertFrame(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)),
            equals: expandedPillFrame
        )
        assertFrame(
            try XCTUnwrap(tabs.bottomBarAccessoryFrame),
            equals: expandedAccessoryFrame
        )
    }

    @MainActor
    func testReverseScrollRewindsPreviewContinuouslyToDeadZoneWithoutLayoutSideEffects() throws {
        let content = ChromeScrollFixtureController()
        let listItem = UITabBarItem()
        listItem.title = "List"
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.selectedImage = UIImage(systemName: "list.bullet")
        content.tabBarItem = listItem
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 200.0)
        let fixture = makeTabBarFixture(controllers: [
            content,
            makeSearchController()
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .liquidGlassV1))
        let accessory = FixedBottomAccessoryView(height: 48.0)
        tabs.bottomBarAccessory = accessory
        tabs.tabBarMinimizeBehavior = .onScrollDown
        tabs.view.layoutIfNeeded()

        let pillLens = try XCTUnwrap(
            tabs.view.firstDescendant(of: LiquidLensView.self)
        )
        let pill = try XCTUnwrap(pillLens.superview)
        let accessoryWrapper = try XCTUnwrap(
            accessory.firstAncestor(of: GlassBackgroundView.self)
        )
        let expandedPillBounds = pill.bounds
        let expandedPillCenter = pill.center
        let expandedAccessoryBounds = accessoryWrapper.bounds
        let expandedAccessoryCenter = accessoryWrapper.center
        let expandedPillFrame = try XCTUnwrap(tabs.pillFrame(in: tabs.view))
        let expandedAccessoryFrame = try XCTUnwrap(tabs.bottomBarAccessoryFrame)

        content.chromeScrollView.simulatesUserDrivenScroll = true
        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 224.0)
        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertEqual(pill.layer.sublayerTransform.m11, 0.995, accuracy: 0.001)
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            0.995,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pill.bounds.width,
            expandedPillBounds.width - 8.0 / 3.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 8.0 / 3.0,
            accuracy: 0.01
        )
        let childLayoutUpdateCountBeforeReverse = content.containerLayoutUpdateCount

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 212.0)

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "Reversing within the preview must not commit the compact endpoint"
        )
        XCTAssertFalse(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertFalse(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
        XCTAssertEqual(pill.layer.sublayerTransform.m11, 0.99875, accuracy: 0.001)
        XCTAssertEqual(
            accessoryWrapper.layer.sublayerTransform.m11,
            0.99875,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pill.bounds.width,
            expandedPillBounds.width - 2.0 / 3.0,
            accuracy: 0.01,
            "A +12pt offset must rewind preview progress to 1/12, not cancel it"
        )
        XCTAssertEqual(
            accessoryWrapper.bounds.width,
            expandedAccessoryBounds.width - 2.0 / 3.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            content.chromeScrollView.contentOffset,
            CGPoint(x: 0.0, y: 212.0),
            "Rewinding preview must not rewrite the scroll position"
        )
        XCTAssertEqual(
            content.containerLayoutUpdateCount,
            childLayoutUpdateCountBeforeReverse,
            "Rewinding preview must not trigger a full child container layout"
        )

        content.chromeScrollView.contentOffset = CGPoint(x: 0.0, y: 208.0)

        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
        XCTAssertEqual(pill.bounds, expandedPillBounds)
        XCTAssertEqual(pill.center, expandedPillCenter)
        XCTAssertEqual(accessoryWrapper.bounds, expandedAccessoryBounds)
        XCTAssertEqual(accessoryWrapper.center, expandedAccessoryCenter)
        XCTAssertEqual(
            content.chromeScrollView.contentOffset,
            CGPoint(x: 0.0, y: 208.0),
            "Returning to the 8pt dead-zone edge must preserve contentOffset"
        )
        XCTAssertEqual(
            content.containerLayoutUpdateCount,
            childLayoutUpdateCountBeforeReverse,
            "Returning preview to zero must remain a local chrome layout"
        )
        assertFrame(
            try XCTUnwrap(tabs.pillFrame(in: tabs.view)),
            equals: expandedPillFrame
        )
        assertFrame(
            try XCTUnwrap(tabs.bottomBarAccessoryFrame),
            equals: expandedAccessoryFrame
        )

        tabs.advanceTabBarMinimizeArmingForTesting(by: 1.0)

        XCTAssertFalse(
            tabs.isTabBarMinimized,
            "A preview rewound to zero must prevent any later non-spatial commit"
        )
        XCTAssertTrue(CATransform3DIsIdentity(pill.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(accessoryWrapper.layer.sublayerTransform))
    }

    func testBottomBarVisibilityUsesFixedProductionTimeline() {
        let push = AetherTabBarController.tabBarVisibilityContentTiming(
            direction: .push,
            isInteractive: false
        )
        let pop = AetherTabBarController.tabBarVisibilityContentTiming(
            direction: .pop,
            isInteractive: false
        )
        let interactivePop = AetherTabBarController.tabBarVisibilityContentTiming(
            direction: .pop,
            isInteractive: true
        )

        XCTAssertEqual(push.duration, 0.28, accuracy: 0.001)
        XCTAssertEqual(push.delay, 0.06, accuracy: 0.001)
        XCTAssertEqual(pop.duration, 0.28, accuracy: 0.001)
        XCTAssertEqual(pop.delay, 0.0, accuracy: 0.001)
        XCTAssertEqual(interactivePop.duration, 0.28, accuracy: 0.001)
        XCTAssertEqual(interactivePop.delay, 0.0, accuracy: 0.001)
    }

    func testBottomBarVisibilityCrossblursAndFadesWithoutTransform() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let duration = AetherMotion.navigationChrome.contentAppearanceDuration
        let transition: ContainedViewLayoutTransition = .animated(
            duration: duration,
            curve: .easeInOut
        )

        tabs.updateIsTabBarHidden(true, transition: transition)
        XCTAssertTrue(tabs.isTabBarVisibilityContentAnimatingForTesting)
        XCTAssertEqual(tabs.tabBarVisibilityVisualHiddenProgressForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityAlphaForTesting, 1.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityBlurRadiusForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityTransformForTesting, .identity)
        XCTAssertEqual(tabs.additionalSafeAreaInsets.bottom, 0.0, accuracy: 0.5)

        tabs.advanceTabBarVisibilityContentAnimationForTesting(by: duration * 0.5)
        XCTAssertEqual(tabs.tabBarVisibilityVisualHiddenProgressForTesting, 0.5, accuracy: 0.01)
        XCTAssertEqual(tabs.tabBarVisibilityAlphaForTesting, 0.5, accuracy: 0.01)
        XCTAssertEqual(
            tabs.tabBarVisibilityBlurRadiusForTesting,
            AetherMotion.navigationChrome.contentBlurRadius * 0.5,
            accuracy: 0.05
        )
        XCTAssertEqual(tabs.tabBarVisibilityTransformForTesting, .identity)

        tabs.advanceTabBarVisibilityContentAnimationForTesting(by: duration * 0.5)
        XCTAssertFalse(tabs.isTabBarVisibilityContentAnimatingForTesting)
        XCTAssertEqual(tabs.tabBarVisibilityVisualHiddenProgressForTesting, 1.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityAlphaForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(
            tabs.tabBarVisibilityBlurRadiusForTesting,
            AetherMotion.navigationChrome.contentBlurRadius,
            accuracy: 0.001
        )
        XCTAssertEqual(tabs.tabBarVisibilityTransformForTesting, .identity)

        tabs.updateIsTabBarHidden(false, transition: transition)
        tabs.advanceTabBarVisibilityContentAnimationForTesting(by: duration)
        XCTAssertFalse(tabs.isTabBarVisibilityContentAnimatingForTesting)
        XCTAssertEqual(tabs.tabBarVisibilityVisualHiddenProgressForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityAlphaForTesting, 1.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityBlurRadiusForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(tabs.tabBarVisibilityTransformForTesting, .identity)

        fixture.window.isHidden = true
    }

    func testAnimatedLegacyTabBarHideKeepsSharedAccessoryMaterialUntilFadeEnds() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .legacy))
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.view.layoutIfNeeded()
        let tabBar = try XCTUnwrap(
            tabs.view.firstDescendant(of: TabBarView.self)
        )

        tabs.updateIsTabBarHidden(
            true,
            transition: .animated(duration: 0.10, curve: .easeInOut)
        )
        tabs.view.layoutIfNeeded()

        XCTAssertTrue(tabs.isTabBarVisibilityContentAnimatingForTesting)
        XCTAssertEqual(
            tabBar.bottomAccessoryReservedHeight,
            TabBarView.LegacyLayout.minimumAccessoryHeight
                + TabBarView.LegacyLayout.accessoryBottomGap,
            accuracy: 0.001
        )
        XCTAssertTrue(tabBar.legacySeparatorIsHiddenForTesting)
        XCTAssertNotNil(tabBar.legacyUnifiedBottomMaterialFrameForTesting)

        RunLoop.main.run(until: Date().addingTimeInterval(0.20))
        tabs.view.layoutIfNeeded()

        XCTAssertFalse(tabs.isTabBarVisibilityContentAnimatingForTesting)
        XCTAssertEqual(
            tabBar.bottomAccessoryReservedHeight,
            0.0,
            accuracy: 0.001
        )
        XCTAssertFalse(tabBar.legacySeparatorIsHiddenForTesting)
        XCTAssertNil(tabBar.legacyUnifiedBottomMaterialFrameForTesting)
    }

    func testHidesBottomBarPushDelaysOnlyTheFixedVisualClock() {
        let root = AetherViewController()
        root.tabBarItem = UITabBarItem(
            title: "Root",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        let navigationController = AetherNavigationController(rootViewController: root)
        let fixture = makeTabBarFixture(controllers: [navigationController])

        let detail = AetherViewController()
        detail.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(detail, animated: true)

        let timing = tabsTiming(fixture.tabs)
        XCTAssertEqual(timing.duration, 0.28, accuracy: 0.001)
        XCTAssertEqual(timing.delay, 0.06, accuracy: 0.001)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityContentDirectionForTesting, .push)
        XCTAssertFalse(fixture.tabs.tabBarVisibilityContentIsInteractiveForTesting)
        XCTAssertEqual(
            fixture.tabs.tabBarVisibilityVisualHiddenProgressForTesting,
            0.0,
            accuracy: 0.001
        )
        XCTAssertEqual(fixture.tabs.additionalSafeAreaInsets.bottom, 0.0, accuracy: 0.5)

        fixture.tabs.advanceTabBarVisibilityContentAnimationForTesting(by: 0.04)
        XCTAssertEqual(
            fixture.tabs.tabBarVisibilityVisualHiddenProgressForTesting,
            0.0,
            accuracy: 0.001,
            "The push delay must hold both alpha and blur at their source values"
        )
        XCTAssertEqual(fixture.tabs.tabBarVisibilityBlurRadiusForTesting, 0.0, accuracy: 0.001)
        XCTAssertEqual(fixture.tabs.tabBarVisibilityTransformForTesting, .identity)

        fixture.window.isHidden = true
    }

    func testActivateSearchMinimizesTabBarWithoutFocusingInput() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        XCTAssertFalse(tabs.isTabBarMinimized)

        tabs.activateSearch()

        XCTAssertTrue(tabs.isTabBarMinimized)
        let textField = tabs.view.firstDescendant(of: UITextField.self)
        XCTAssertNotNil(textField)
        XCTAssertFalse(textField?.isFirstResponder ?? true)

        fixture.window.isHidden = true
    }

    func testSearchCloseButtonRemainsVisibleWithoutKeyboardFocus() {
        let fixture = makeTabBarFixture()

        fixture.tabs.activateSearch()

        guard let close = fixture.tabs.view.firstDescendant(identifier: "aether.search.close") else {
            XCTFail("Expected an always-visible search close button")
            fixture.window.isHidden = true
            return
        }
        XCTAssertEqual(close.alpha, 1.0, accuracy: 0.001)

        let textField = fixture.tabs.view.firstDescendant(of: UITextField.self)
        textField?.becomeFirstResponder()
        textField?.resignFirstResponder()
        XCTAssertEqual(close.alpha, 1.0, accuracy: 0.001)

        fixture.window.isHidden = true
    }

    func testBottomAccessoryInstallDoesNotAnimateTrailingSearchButton() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        guard let searchButton = tabs.view.firstDescendant(
            identifier: "aether.tabbar.search.moving"
        ) as? GlassBarButtonView else {
            XCTFail("Expected search tab item button")
            return
        }
        let initialFrame = searchButton.frame
        searchButton.layer.removeAllAnimations()

        tabs.setBottomBarAccessory(FixedBottomAccessoryView(height: 56.0), animated: true)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(searchButton.frame.minX, initialFrame.minX, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.width, initialFrame.width, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.height, initialFrame.height, accuracy: 0.5)
        XCTAssertTrue(searchButton.layer.animationKeys()?.isEmpty ?? true)

        fixture.window.isHidden = true
    }

    func testBottomAccessoryRemovalDoesNotAnimateTrailingSearchButton() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56.0)
        tabs.view.layoutIfNeeded()
        guard let searchButton = tabs.view.firstDescendant(
            identifier: "aether.tabbar.search.moving"
        ) as? GlassBarButtonView else {
            XCTFail("Expected search tab item button")
            return
        }
        let initialFrame = searchButton.frame
        searchButton.layer.removeAllAnimations()

        tabs.setBottomBarAccessory(nil, animated: true)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(searchButton.frame.minX, initialFrame.minX, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.width, initialFrame.width, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.height, initialFrame.height, accuracy: 0.5)
        XCTAssertTrue(searchButton.layer.animationKeys()?.isEmpty ?? true)

        fixture.window.isHidden = true
    }

    func testAnimatedLegacyAccessoryRemovalKeepsMaterialAndSeparatorUntilFadeEnds() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        tabs.updateAppearance(AetherAppearance(style: .legacy))
        tabs.bottomBarAccessory = TabBarAccessoryView()
        tabs.view.layoutIfNeeded()

        let tabBar = try XCTUnwrap(
            tabs.view.firstDescendant(of: TabBarView.self)
        )
        tabs.setBottomBarAccessory(nil, animated: true)
        tabs.view.layoutIfNeeded()

        let outgoingWrapper = try XCTUnwrap(
            tabs.view.directGlassSubviews.first
        )
        XCTAssertEqual(outgoingWrapper.alpha, 1.0, accuracy: 0.001)
        XCTAssertNil(outgoingWrapper.layer.animation(forKey: "opacity"))
        XCTAssertEqual(
            tabBar.bottomAccessoryReservedHeight,
            TabBarView.LegacyLayout.minimumAccessoryHeight
                + TabBarView.LegacyLayout.accessoryBottomGap,
            accuracy: 0.001
        )
        XCTAssertTrue(tabBar.legacySeparatorIsHiddenForTesting)
        XCTAssertNotNil(tabBar.legacyUnifiedBottomMaterialFrameForTesting)

        RunLoop.main.run(until: Date().addingTimeInterval(0.60))
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(
            tabBar.bottomAccessoryReservedHeight,
            0.0,
            accuracy: 0.001
        )
        XCTAssertFalse(tabBar.legacySeparatorIsHiddenForTesting)
        XCTAssertNil(tabBar.legacyUnifiedBottomMaterialFrameForTesting)
    }

    func testRapidAnimatedAccessoryRemovalAndReinstallKeepsOneGlassSurface() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56.0)
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(tabs.view.directGlassSubviews.count, 1)

        tabs.setBottomBarAccessory(nil, animated: true)
        XCTAssertEqual(
            tabs.view.directGlassSubviews.count,
            1,
            "The outgoing accessory glass may remain only for its own fade-out"
        )

        // Model the playback stop -> immediate play race before the first
        // crossfade completion has fired. The previous glass must be cancelled
        // before the replacement is installed.
        tabs.setBottomBarAccessory(accessory, animated: true)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(tabs.view.directGlassSubviews.count, 1)
        XCTAssertTrue(
            accessory.superview === tabs.view.directGlassSubviews[0].contentView
        )

        fixture.window.isHidden = true
    }

    func testImmediateAccessoryReplacementReusesGlassAndInstallsInteractiveContent() throws {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let first = InteractiveBottomAccessoryView()
        let second = InteractiveBottomAccessoryView()
        tabs.bottomBarAccessory = first
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let glassCount = tabs.view.allGlassDescendants.count

        tabs.setBottomBarAccessory(second, animated: false)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(tabs.view.allGlassDescendants.count, glassCount)
        XCTAssertTrue(tabs.view.directGlassSubviews.first === wrapper)
        XCTAssertNil(first.superview)
        XCTAssertTrue(second.superview === wrapper.contentView)
        assertAccessoryIsInteractive(second, in: tabs)

        fixture.window.isHidden = true
    }

    func testAnimatedAccessoryReplacementKeepsOneGlassThroughoutCrossfade() throws {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let first = InteractiveBottomAccessoryView()
        let second = InteractiveBottomAccessoryView()
        tabs.bottomBarAccessory = first
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let glassCount = tabs.view.allGlassDescendants.count

        tabs.setBottomBarAccessory(second, animated: true)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(
            tabs.view.allGlassDescendants.count,
            glassCount,
            "A -> B crossfade must not create an outgoing glass surface"
        )
        XCTAssertTrue(tabs.view.directGlassSubviews.first === wrapper)
        XCTAssertTrue(first.superview === wrapper.contentView)
        XCTAssertTrue(second.superview === wrapper.contentView)
        XCTAssertTrue(first.accessibilityElementsHidden)
        XCTAssertFalse(first.isUserInteractionEnabled)

        let settled = expectation(description: "content-only accessory crossfade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.5)

        XCTAssertEqual(tabs.view.allGlassDescendants.count, glassCount)
        XCTAssertNil(first.superview)
        XCTAssertTrue(second.superview === wrapper.contentView)
        assertAccessoryIsInteractive(second, in: tabs)

        fixture.window.isHidden = true
    }

    func testCollapsedAccessibilityHasOnePlayerEndpointAndCurrentTabFallback() throws {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertTrue(
            tabs.collapsedAccessoryAccessibilityFocusTargetForTesting === accessory
        )
        XCTAssertFalse(accessory.accessibilityElementsHidden)

        tabs.presentExpandedAccessory(expanded, animated: false)
        let expandedHost = try XCTUnwrap(expanded.view.superview)
        XCTAssertTrue(accessory.accessibilityElementsHidden)
        XCTAssertFalse(expandedHost.accessibilityElementsHidden)

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertFalse(accessory.accessibilityElementsHidden)
        XCTAssertTrue(expandedHost.accessibilityElementsHidden)

        tabs.setBottomBarAccessory(nil, animated: false)
        XCTAssertTrue(
            tabs.collapsedAccessoryAccessibilityFocusTargetForTesting
                === tabs.controllers[tabs.selectedIndex].view
        )

        fixture.window.isHidden = true
    }

    func testAccessoryAccessibilityOwnershipPolicyHasNoTransientEndpoint() {
        typealias Ownership = AetherTabBarController
            .BottomBarAccessoryAccessibilityOwnership
        let cases: [(
            state: BottomBarAccessoryPresentationState,
            expected: Ownership
        )] = [
            (.collapsed, .collapsed),
            (.expanding, .transition),
            (.dragging, .transition),
            (.settlingToExpanded, .transition),
            (.expanded, .expanded),
            (.settlingToCollapsed, .transition),
        ]

        for testCase in cases {
            XCTAssertEqual(
                AetherTabBarController
                    .bottomBarAccessoryAccessibilityOwnership(for: testCase.state),
                testCase.expected,
                "Unexpected VoiceOver owner for \(testCase.state)"
            )
        }
    }

    func testTransientAccessoryStatesHideBothEndpointsAndUnderlyingScreen() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let tabs = fixture.tabs
        let accessory = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertEqual(tabs.view.directGlassSubviews.count, 1)
        XCTAssertEqual(wrapper.allGlassDescendants.count, 1)
        let tabBar = try XCTUnwrap(
            tabs.view.firstDescendant(of: TabBarView.self)
        )
        let underlyingContent = try XCTUnwrap(tabs.currentController?.view)

        XCTAssertFalse(accessory.accessibilityElementsHidden)
        XCTAssertFalse(tabBar.accessibilityElementsHidden)
        XCTAssertFalse(underlyingContent.accessibilityElementsHidden)

        tabs.presentExpandedAccessory(expanded, animated: true)
        let expandedHost = try XCTUnwrap(expanded.view.superview)
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        if wrapper.usesNativeGlassRendererForTesting {
            XCTAssertFalse(expanded.view.isDescendant(of: wrapper.contentView))
        }
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanding)
        assertTransientAccessibilityOwnership(
            collapsedEndpoint: accessory,
            expandedHost: expandedHost,
            tabBar: tabBar,
            underlyingContent: underlyingContent
        )

        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertTrue(accessory.accessibilityElementsHidden)
        XCTAssertFalse(expandedHost.accessibilityElementsHidden)
        XCTAssertTrue(tabBar.accessibilityElementsHidden)
        XCTAssertTrue(underlyingContent.accessibilityElementsHidden)

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: true))
        XCTAssertEqual(
            tabs.bottomBarAccessoryPresentationState,
            .settlingToCollapsed
        )
        assertTransientAccessibilityOwnership(
            collapsedEndpoint: accessory,
            expandedHost: expandedHost,
            tabBar: tabBar,
            underlyingContent: underlyingContent
        )

        // Let the collapse acquire a real presentation-frame delta before
        // reversing it. A same-run-loop reversal is already visually at the
        // expanded endpoint and is now completed immediately by design.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        tabs.presentExpandedAccessory(expanded, animated: true)
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        if wrapper.usesNativeGlassRendererForTesting {
            XCTAssertFalse(expanded.view.isDescendant(of: wrapper.contentView))
        }
        XCTAssertEqual(tabs.view.directGlassSubviews.count, 1)
        XCTAssertEqual(wrapper.allGlassDescendants.count, 1)
        XCTAssertEqual(
            tabs.bottomBarAccessoryPresentationState,
            .settlingToExpanded
        )
        assertTransientAccessibilityOwnership(
            collapsedEndpoint: accessory,
            expandedHost: expandedHost,
            tabBar: tabBar,
            underlyingContent: underlyingContent
        )

        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertTrue(accessory.superview === wrapper.contentView)
        XCTAssertEqual(tabs.view.directGlassSubviews.count, 1)
        XCTAssertEqual(wrapper.allGlassDescendants.count, 1)
        XCTAssertFalse(accessory.accessibilityElementsHidden)
        XCTAssertTrue(expandedHost.accessibilityElementsHidden)
        XCTAssertFalse(tabBar.accessibilityElementsHidden)
        XCTAssertFalse(underlyingContent.accessibilityElementsHidden)
        assertAccessoryIsInteractive(accessory, in: tabs)
    }

    func testReduceMotionNotificationUpdatesStableFullPlayerOffToOn() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let tabs = fixture.tabs
        var reduceMotionEnabled = false
        tabs.bottomBarAccessoryReduceMotionStatusProvider = {
            reduceMotionEnabled
        }
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = RecordingExpandedAccessoryController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        tabs.presentExpandedAccessory(expanded, animated: false)
        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let stableFrame = wrapper.frame
        let stableOpacity = wrapper.layer.opacity
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertEqual(expanded.contexts.last?.isReduceMotionEnabled, false)

        reduceMotionEnabled = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertEqual(expanded.contexts.last?.isReduceMotionEnabled, true)
        assertFrame(wrapper.frame, equals: stableFrame)
        XCTAssertEqual(wrapper.layer.opacity, stableOpacity, accuracy: 0.001)
    }

    func testReduceMotionNotificationUpdatesStableFullPlayerOnToOff() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }

        let tabs = fixture.tabs
        var reduceMotionEnabled = true
        tabs.bottomBarAccessoryReduceMotionStatusProvider = {
            reduceMotionEnabled
        }
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = RecordingExpandedAccessoryController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        tabs.presentExpandedAccessory(expanded, animated: false)
        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let stableFrame = wrapper.frame
        let stableOpacity = wrapper.layer.opacity
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertEqual(expanded.contexts.last?.isReduceMotionEnabled, true)

        reduceMotionEnabled = false
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertEqual(expanded.contexts.last?.isReduceMotionEnabled, false)
        assertFrame(wrapper.frame, equals: stableFrame)
        XCTAssertEqual(wrapper.layer.opacity, stableOpacity, accuracy: 0.001)
    }

    @MainActor
    func testReduceMotionToggleWhileFullKeepsCompactProgressFrameUnavailable() throws {
        let fixture = makeTabBarFixture()
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        var reduceMotionEnabled = false
        tabs.bottomBarAccessoryReduceMotionStatusProvider = {
            reduceMotionEnabled
        }
        let accessory = FixedBottomAccessoryView(height: 56.0)
        let expanded = RecordingExpandedAccessoryController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()
        let delegate = RecordingTabBarMinimizationDelegate()
        tabs.minimizationDelegate = delegate

        tabs.setTabBarMinimized(
            true,
            transition: .animated(duration: 0.50, curve: .linear)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertGreaterThan(tabs.tabBarMinimizationProgress, 0.0)
        XCTAssertLessThan(tabs.tabBarMinimizationProgress, 1.0)

        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertNil(delegate.updates.last?.bottomBarAccessoryFrame)

        reduceMotionEnabled = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        XCTAssertEqual(expanded.contexts.last?.isReduceMotionEnabled, true)

        RunLoop.main.run(until: Date().addingTimeInterval(0.55))

        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)
        XCTAssertEqual(tabs.tabBarMinimizationProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(delegate.updates.last?.progress ?? -1.0, 1.0, accuracy: 0.001)
        XCTAssertNil(
            delegate.updates.last?.bottomBarAccessoryFrame,
            "Full Player geometry leaked into the compact callback after Reduce Motion changed"
        )

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        assertFrame(
            try XCTUnwrap(delegate.updates.last?.bottomBarAccessoryFrame),
            equals: CGRect(x: 89.0, y: 775.0, width: 212.0, height: 48.0)
        )
    }

    func testRemovingAccessoryWhileExpandedDetachesExpandedController() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56.0)
        let expanded = UIViewController()
        accessory.expandedViewControllerProvider = { expanded }
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertTrue(expanded.parent === tabs)
        XCTAssertTrue(tabs.expandedAccessoryViewController === expanded)

        tabs.setBottomBarAccessory(nil, animated: false)

        XCTAssertNil(expanded.parent)
        XCTAssertNil(expanded.view.superview)
        XCTAssertNil(tabs.expandedAccessoryViewController)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertTrue(tabs.view.directGlassSubviews.isEmpty)

        fixture.window.isHidden = true
    }

    func testReplacingAccessoryWhileExpandedReusesGlassAndCleansExpandedController() throws {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let first = InteractiveBottomAccessoryView()
        let second = InteractiveBottomAccessoryView()
        let expanded = UIViewController()
        first.expandedViewControllerProvider = { expanded }
        tabs.bottomBarAccessory = first
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let glassCount = tabs.view.allGlassDescendants.count
        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertTrue(expanded.parent === tabs)

        tabs.setBottomBarAccessory(second, animated: false)
        tabs.view.layoutIfNeeded()

        XCTAssertNil(expanded.parent)
        XCTAssertNil(expanded.view.superview)
        XCTAssertNil(tabs.expandedAccessoryViewController)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertTrue(tabs.view.directGlassSubviews.first === wrapper)
        XCTAssertEqual(tabs.view.allGlassDescendants.count, glassCount)
        XCTAssertTrue(second.superview === wrapper.contentView)
        assertAccessoryIsInteractive(second, in: tabs)

        fixture.window.isHidden = true
    }

    func testExpandedAccessoryRestoresExactRegularDockingSnapshot() throws {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = RecordingExpandedAccessoryController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let sourceFrame = wrapper.frame
        assertFrame(
            sourceFrame,
            equals: CGRect(x: 25.0, y: 699.0, width: 340.0, height: 56.0)
        )
        let inheritedSafeBottom = max(
            0.0,
            tabs.view.safeAreaInsets.bottom - tabs.additionalSafeAreaInsets.bottom
        )
        XCTAssertEqual(
            tabs.additionalSafeAreaInsets.bottom,
            max(0.0, TabBarView.defaultHeight - inheritedSafeBottom) + 56.0 + 8.0,
            accuracy: 0.01
        )

        tabs.presentExpandedAccessory(expanded, animated: false)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .expanded)

        // All three live chrome entry points are intentionally ignored for the
        // duration of this session. None may replace the regular attraction
        // point captured above.
        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.activateSearch()
        tabs.updateIsTabBarHidden(true, transition: .immediate)
        tabs.containerLayoutUpdated(
            ContainerViewLayout(
                size: tabs.view.bounds.size,
                safeInsets: .zero,
                additionalInsets: .zero
            ),
            transition: .immediate
        )

        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertEqual(
            tabs.tabBarVisibilityVisualHiddenProgressForTesting,
            0,
            accuracy: 0.001
        )
        XCTAssertFalse(expanded.contexts.isEmpty)
        for context in expanded.contexts {
            XCTAssertEqual(context.dockingContext.mode, .regular)
            XCTAssertTrue(context.dockingContext.isTabBarVisible)
            XCTAssertFalse(context.dockingContext.isSearchActive)
            assertFrame(
                context.geometry.collapsedFrame,
                equals: sourceFrame,
                message: "A same-size chrome callback changed the regular target"
            )
        }

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        assertFrame(wrapper.frame, equals: sourceFrame)
        XCTAssertFalse(wrapper.isHidden)
        XCTAssertFalse(tabs.isTabBarMinimized)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)

        fixture.window.isHidden = true
    }

    func testExpandedAccessoryRotationKeepsInlineTargetWithoutRegularJump() throws {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56)
        let expanded = RecordingExpandedAccessoryController()
        tabs.bottomBarAccessory = accessory
        tabs.setTabBarMinimized(true, transition: .immediate)
        tabs.view.layoutIfNeeded()

        let wrapper = try XCTUnwrap(tabs.view.directGlassSubviews.first)
        let sourceFrame = wrapper.frame
        let expectedSourceFrame = CGRect(
            x: 89.0,
            y: 775.0,
            width: 212.0,
            height: TabBarView.minimizedButtonSize
        )
        assertFrame(sourceFrame, equals: expectedSourceFrame)

        tabs.presentExpandedAccessory(expanded, animated: false)
        tabs.setTabBarMinimized(false, transition: .immediate)
        tabs.activateSearch()
        tabs.updateIsTabBarHidden(true, transition: .immediate)

        let rotatedSize = CGSize(width: 844, height: 390)
        fixture.window.frame = CGRect(origin: .zero, size: rotatedSize)
        tabs.view.frame = fixture.window.bounds
        tabs.containerLayoutUpdated(
            ContainerViewLayout(
                size: rotatedSize,
                safeInsets: .zero,
                additionalInsets: .zero
            ),
            transition: .immediate
        )
        tabs.view.layoutIfNeeded()

        let minimizedPill = try XCTUnwrap(tabs.pillFrame(in: tabs.view))
        assertFrame(
            minimizedPill,
            equals: CGRect(x: 28.0, y: 321.0, width: 48.0, height: 48.0)
        )
        let expectedInlineFrame = CGRect(
            x: 89.0,
            y: 321.0,
            width: 666.0,
            height: TabBarView.minimizedButtonSize
        )

        XCTAssertTrue(tabs.dismissExpandedAccessory(animated: false))
        assertFrame(wrapper.frame, equals: expectedInlineFrame)
        XCTAssertTrue(tabs.isTabBarMinimized)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)

        XCTAssertFalse(expanded.contexts.isEmpty)
        for context in expanded.contexts {
            XCTAssertEqual(context.dockingContext.mode, .inline)
            XCTAssertTrue(context.dockingContext.isTabBarVisible)
            XCTAssertFalse(context.dockingContext.isSearchActive)
            XCTAssertEqual(
                context.geometry.collapsedFrame.height,
                TabBarView.minimizedButtonSize,
                accuracy: 0.01,
                "Inline collapse must never pass through the 56pt regular slot"
            )
            let frame = context.geometry.collapsedFrame
            let isSource = frame.isApproximatelyEqual(to: sourceFrame)
            let isRotated = frame.isApproximatelyEqual(to: expectedInlineFrame)
            XCTAssertTrue(
                isSource || isRotated,
                "Unexpected intermediate collapse target: \(frame)"
            )
        }

        fixture.window.isHidden = true
    }

    func testSearchTabItemOnNavigationRootRendersAsFinalExpandedSlot() {
        let searchTab = makeNavigationSearchController()
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            makeController(title: "Two", image: "person"),
            searchTab
        ])
        let tabs = fixture.tabs

        XCTAssertEqual(tabs.controllers.count, 2)
        XCTAssertFalse(tabs.controllers.contains { $0 === searchTab })
        let expandedSlot = tabs.view.firstDescendant(
            identifier: "aether.tabbar.search.expandedVisual"
        )
        let minimizedMaterial = tabs.view.firstDescendant(
            identifier: "aether.tabbar.search.moving"
        ) as? GlassBarButtonView
        let lens = tabs.view.firstDescendant(of: LiquidLensView.self)
        let searchGlassContainer = minimizedMaterial?.firstAncestor(
            of: GlassBackgroundContainerView.self
        )
        XCTAssertNotNil(expandedSlot)
        XCTAssertEqual(expandedSlot?.alpha ?? -1.0, 1.0, accuracy: 0.001)
        XCTAssertTrue(expandedSlot?.isUserInteractionEnabled == false)
        XCTAssertNotNil(minimizedMaterial)
        XCTAssertEqual(minimizedMaterial?.alpha ?? -1.0, 1.0, accuracy: 0.001)
        XCTAssertEqual(
            minimizedMaterial?.chromeMorphMaterialAlpha ?? -1.0,
            searchGlassContainer?.isUsingNativeContainerEffect == true ? 1.0 : 0.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            minimizedMaterial?.chromeMorphContentAlpha ?? -1.0,
            1.0,
            accuracy: 0.001
        )
        XCTAssertTrue(minimizedMaterial?.isUserInteractionEnabled == true)
        XCTAssertNotNil(searchGlassContainer)
        XCTAssertTrue(
            searchGlassContainer === lens?.firstAncestor(
                of: GlassBackgroundContainerView.self
            )
        )

        fixture.window.isHidden = true
    }

    func testReplacingControllersSynchronouslyRetiresPresentedSearchOwner() {
        let searchController = SearchLifecycleViewController()
        searchController.tabBarItem = SearchTabItem(
            image: UIImage(systemName: "magnifyingglass")
        )
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            searchController
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs

        tabs.activateSearch()
        XCTAssertTrue(searchController.parent === tabs)
        XCTAssertNotNil(searchController.view.superview)
        XCTAssertEqual(searchController.activationCount, 1)

        tabs.setControllers([], selectedIndex: nil)

        XCTAssertNil(searchController.parent)
        XCTAssertNil(searchController.view.superview)
        XCTAssertEqual(searchController.deactivationCount, 1)
        XCTAssertTrue(tabs.controllers.isEmpty)
    }

    @MainActor
    func testSearchDeactivationLifecycleCanSynchronouslyClearControllersWithoutRecursion() {
        let searchController = SearchLifecycleViewController()
        searchController.tabBarItem = SearchTabItem(
            image: UIImage(systemName: "magnifyingglass")
        )
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            searchController
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs

        tabs.activateSearch()
        XCTAssertTrue(searchController.parent === tabs)
        XCTAssertTrue(searchController.view.superview === tabs.view)
        XCTAssertEqual(searchController.activationCount, 1)

        searchController.onDeactivate = {
            tabs.setControllers([], selectedIndex: nil)
        }
        tabs.deactivateSearch()

        XCTAssertEqual(
            searchController.deactivationCount,
            1,
            "Nested controller replacement must not redeliver the lifecycle hook"
        )
        XCTAssertTrue(tabs.controllers.isEmpty)
        XCTAssertNil(tabs.currentController)
        XCTAssertNil(searchController.parent)
        XCTAssertNil(searchController.view.superview)
        XCTAssertNil(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            )
        )
        XCTAssertNil(
            tabs.view.firstDescendant(identifier: "aether.tabbar.search.moving")
        )

        // A stale outer dismissal must have no owner left to notify again.
        tabs.deactivateSearch()
        XCTAssertEqual(searchController.deactivationCount, 1)
    }

    @MainActor
    func testControllerReplacementDuringSearchDismissalDoesNotRedeliverDeactivation() {
        let searchController = SearchLifecycleViewController()
        searchController.tabBarItem = SearchTabItem(
            image: UIImage(systemName: "magnifyingglass")
        )
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            searchController
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs

        tabs.activateSearch()
        XCTAssertEqual(searchController.activationCount, 1)

        tabs.deactivateSearch()
        XCTAssertEqual(searchController.deactivationCount, 1)
        XCTAssertTrue(
            searchController.parent === tabs,
            "The animated dismissal should still own Search before completion"
        )

        tabs.setControllers([], selectedIndex: nil)

        XCTAssertEqual(
            searchController.deactivationCount,
            1,
            "Controller replacement must not redeliver an already-fired session hook"
        )
        XCTAssertTrue(tabs.controllers.isEmpty)
        XCTAssertNil(tabs.currentController)
        XCTAssertNil(searchController.parent)
        XCTAssertNil(searchController.view.superview)

        // The retired animation completion must neither notify nor reattach.
        RunLoop.main.run(
            until: Date().addingTimeInterval(AetherMotion.search.dismissal.duration + 0.10)
        )
        XCTAssertEqual(searchController.deactivationCount, 1)
        XCTAssertNil(searchController.parent)
        XCTAssertNil(searchController.view.superview)
    }

    func testRefreshingCurrentControllersPreservesSearchTabItem() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        tabs.setControllers(tabs.controllers, selectedIndex: tabs.selectedIndex)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(tabs.controllers.count, 2)
        XCTAssertNotNil(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            )
        )
        XCTAssertNotNil(
            tabs.view.firstDescendant(identifier: "aether.tabbar.search.moving")
        )

        fixture.window.isHidden = true
    }

    func testSearchPresentationAttachesContentAndCallsLifecycleHooks() {
        let searchController = SearchLifecycleViewController()
        searchController.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass"))
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            makeController(title: "Two", image: "person"),
            searchController
        ])

        fixture.tabs.activateSearch()

        XCTAssertTrue(searchController.parent === fixture.tabs)
        XCTAssertTrue(searchController.view.superview === fixture.tabs.view)
        XCTAssertEqual(searchController.activationCount, 1)

        fixture.tabs.deactivateSearch()
        XCTAssertEqual(searchController.deactivationCount, 1)

        let settled = expectation(description: "search dismissal settles")
        let dismissalSettleDelay = AetherMotion.search.dismissal.duration + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissalSettleDelay) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: dismissalSettleDelay + 1.0)
        XCTAssertNil(searchController.parent)
        XCTAssertNil(searchController.view.superview)

        fixture.window.isHidden = true
    }

    @MainActor
    func testPresentExpandedAccessoryIsNoOpWhileSearchIsActive() throws {
        let searchController = SearchLifecycleViewController()
        searchController.tabBarItem = SearchTabItem(
            image: UIImage(systemName: "magnifyingglass")
        )
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            searchController
        ])
        defer { fixture.window.isHidden = true }
        let tabs = fixture.tabs
        let accessory = FixedBottomAccessoryView(height: 56.0)
        let attemptedFull = UIViewController()
        tabs.bottomBarAccessory = accessory
        tabs.view.layoutIfNeeded()
        let tabBar = try XCTUnwrap(tabs.view.firstDescendant(of: TabBarView.self))

        tabs.activateSearch()
        XCTAssertTrue(tabBar.isSearchActive)
        XCTAssertTrue(searchController.parent === tabs)
        XCTAssertTrue(searchController.view.superview === tabs.view)
        XCTAssertEqual(searchController.activationCount, 1)
        XCTAssertEqual(searchController.deactivationCount, 0)

        tabs.presentExpandedAccessory(attemptedFull, animated: false)

        XCTAssertNil(tabs.expandedAccessoryViewController)
        XCTAssertEqual(tabs.bottomBarAccessoryPresentationState, .collapsed)
        XCTAssertNil(attemptedFull.parent)
        XCTAssertNil(attemptedFull.viewIfLoaded?.superview)
        XCTAssertTrue(tabBar.isSearchActive)
        XCTAssertTrue(searchController.parent === tabs)
        XCTAssertTrue(searchController.view.superview === tabs.view)
        XCTAssertEqual(searchController.activationCount, 1)
        XCTAssertEqual(searchController.deactivationCount, 0)

        tabs.deactivateSearch()
        XCTAssertEqual(searchController.deactivationCount, 1)
        RunLoop.main.run(
            until: Date().addingTimeInterval(AetherMotion.search.dismissal.duration + 0.10)
        )

        XCTAssertFalse(tabBar.isSearchActive)
        XCTAssertNil(tabs.expandedAccessoryViewController)
        XCTAssertNil(searchController.parent)
        XCTAssertNil(searchController.view.superview)
        XCTAssertEqual(searchController.deactivationCount, 1)
    }

    func testWrappedSearchControllerKeepsItsNavigationOwnership() {
        let searchRoot = SearchLifecycleViewController()
        searchRoot.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass"))
        let searchNavigation = AetherNavigationController(mode: .single)
        searchNavigation.setViewControllers([searchRoot], animated: false)
        let fixture = makeTabBarFixture(controllers: [
            makeController(title: "One", image: "house"),
            searchNavigation
        ])

        fixture.tabs.activateSearch()

        XCTAssertTrue(searchNavigation.parent === fixture.tabs)
        XCTAssertTrue(searchRoot.parent === searchNavigation)
        XCTAssertEqual(searchRoot.activationCount, 1)

        fixture.tabs.deactivateSearch()
        fixture.window.isHidden = true
    }

    func testClearingControllersRemovesSearchTabItem() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        tabs.setControllers([], selectedIndex: nil)
        tabs.view.layoutIfNeeded()

        XCTAssertTrue(tabs.controllers.isEmpty)
        XCTAssertNil(
            tabs.view.firstDescendant(
                identifier: "aether.tabbar.search.expandedVisual"
            )
        )
        XCTAssertNil(
            tabs.view.firstDescendant(identifier: "aether.tabbar.search.moving")
        )

        fixture.window.isHidden = true
    }

    #if DEBUG
    func testTapMinimizedActiveTabClosesSearchAndRestoresExpandedState() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        tabs.activateSearch()
        XCTAssertTrue(tabs.isTabBarMinimized)

        tabs.simulateMinimizedActiveTabTapForTests()

        XCTAssertFalse(tabs.isTabBarMinimized)

        fixture.window.isHidden = true
    }

    func testTapMinimizedActiveTabClosesSearchAndKeepsPreviouslyMinimizedState() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        tabs.setTabBarMinimized(true, transition: .immediate)
        XCTAssertTrue(tabs.isTabBarMinimized)

        tabs.activateSearch()
        tabs.simulateMinimizedActiveTabTapForTests()

        XCTAssertTrue(tabs.isTabBarMinimized)

        fixture.window.isHidden = true
    }
    #endif

    private func makeTabBarFixture(
        controllers: [UIViewController]? = nil,
        size: CGSize = CGSize(width: 390.0, height: 844.0)
    ) -> (window: UIWindow, tabs: AetherTabBarController) {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let tabs = AetherTabBarController()
        tabs.setControllers(controllers ?? [
            makeController(title: "One", image: "house"),
            makeController(title: "Two", image: "person"),
            makeSearchController()
        ], selectedIndex: 0)

        window.rootViewController = tabs
        window.isHidden = false
        tabs.loadViewIfNeeded()
        tabs.view.frame = window.bounds
        tabs.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )
        tabs.view.layoutIfNeeded()
        return (window, tabs)
    }

    private func assertFrame(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.01,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, message, file: file, line: line)
    }

    @MainActor
    private func assertStableCollapsedNativeMiniMaterial(
        tabs: AetherTabBarController,
        wrapper: GlassBackgroundView,
        accessory: TabBarAccessoryView,
        expectedEffectAssignmentCount: Int,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.020))

        let nativeEffect = try XCTUnwrap(
            wrapper.transitionMaterialHitTargetForTesting,
            "\(message): missing native material view",
            file: file,
            line: line
        )
        let nativeParams = try XCTUnwrap(
            nativeEffect.superview,
            "\(message): missing native material parameters host",
            file: file,
            line: line
        )
        let presentedParams = nativeParams.layer.presentation()

        XCTAssertEqual(
            tabs.bottomBarAccessoryPresentationState,
            .collapsed,
            message,
            file: file,
            line: line
        )
        XCTAssertTrue(
            accessory.superview === wrapper.contentView,
            "\(message): Mini must remain direct native glass content",
            file: file,
            line: line
        )
        XCTAssertFalse(wrapper.isHidden, message, file: file, line: line)
        XCTAssertEqual(wrapper.alpha, 1, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(wrapper.layer.opacity, 1, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(
            wrapper.transitionMaterialAlpha,
            1,
            accuracy: 0.001,
            "\(message): collapsed material model state must be visible",
            file: file,
            line: line
        )
        XCTAssertEqual(
            nativeParams.layer.opacity,
            1,
            accuracy: 0.001,
            "\(message): native material model layer remained transparent",
            file: file,
            line: line
        )
        XCTAssertEqual(
            presentedParams?.opacity ?? nativeParams.layer.opacity,
            1,
            accuracy: 0.01,
            "\(message): native material presentation remained transparent",
            file: file,
            line: line
        )
        XCTAssertEqual(nativeEffect.alpha, 1, accuracy: 0.001, message, file: file, line: line)
        XCTAssertFalse(nativeEffect.isHidden, message, file: file, line: line)
        XCTAssertFalse(
            wrapper.isTransitionCompositorSettleActive,
            "\(message): native compositor ownership leaked past collapse",
            file: file,
            line: line
        )
        XCTAssertFalse(
            wrapper.hasPendingTransitionCompositorPresentation,
            "\(message): captured native presentation leaked past collapse",
            file: file,
            line: line
        )
        XCTAssertNil(wrapper.transitionCompositorSettleTrackForTesting, message, file: file, line: line)
        XCTAssertEqual(
            wrapper.transitionCompositorTrackedLayerCountForTesting,
            0,
            message,
            file: file,
            line: line
        )
        XCTAssertNil(wrapper.transitionNativeParamsAnimationForTesting, message, file: file, line: line)
        XCTAssertNil(wrapper.transitionNativeEffectAnimationForTesting, message, file: file, line: line)
        XCTAssertNil(wrapper.transitionContentContainerAnimationForTesting, message, file: file, line: line)
        XCTAssertTrue(
            CATransform3DIsIdentity(wrapper.layer.transform),
            "\(message): wrapper retained a transition transform",
            file: file,
            line: line
        )
        XCTAssertTrue(
            CATransform3DIsIdentity(wrapper.layer.sublayerTransform),
            "\(message): wrapper retained elastic sublayer stretch",
            file: file,
            line: line
        )
        XCTAssertTrue(
            CATransform3DIsIdentity(nativeParams.layer.transform),
            "\(message): native parameters host retained a transition transform",
            file: file,
            line: line
        )
        XCTAssertTrue(
            CATransform3DIsIdentity(nativeParams.layer.sublayerTransform),
            "\(message): native parameters host retained elastic sublayer stretch",
            file: file,
            line: line
        )
        XCTAssertTrue(
            CATransform3DIsIdentity(nativeEffect.layer.transform),
            "\(message): native material retained a transition transform",
            file: file,
            line: line
        )
        XCTAssertTrue(
            CATransform3DIsIdentity(nativeEffect.layer.sublayerTransform),
            "\(message): native material retained elastic sublayer stretch",
            file: file,
            line: line
        )
        XCTAssertNil(
            wrapper.layer.animation(forKey: "aether.touchEffect.sublayerTransform"),
            "\(message): a press animator leaked onto the wrapper",
            file: file,
            line: line
        )
        XCTAssertNil(
            nativeParams.layer.animation(forKey: "aether.touchEffect.sublayerTransform"),
            "\(message): a press animator leaked onto the native parameters host",
            file: file,
            line: line
        )
        XCTAssertNil(
            nativeEffect.layer.animation(forKey: "aether.touchEffect.sublayerTransform"),
            "\(message): a press animator leaked onto the native material",
            file: file,
            line: line
        )
        XCTAssertNil(
            wrapper.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator.surfaceGeometryAnimationKey
            ),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            wrapper.nativeGlassEffectAssignmentCountForTesting,
            expectedEffectAssignmentCount,
            "\(message): transition recreated/reassigned the native glass effect",
            file: file,
            line: line
        )
        XCTAssertTrue(accessory.isUserInteractionEnabled, message, file: file, line: line)
        XCTAssertFalse(accessory.accessibilityElementsHidden, message, file: file, line: line)
        XCTAssertFalse(
            wrapper.gestureRecognizers?.contains {
                $0 is InteractiveTransitionGestureRecognizer
            } == true,
            "\(message): drag-to-dismiss recognizer leaked onto stable Mini",
            file: file,
            line: line
        )
        XCTAssertEqual(
            wrapper.gestureRecognizers?.filter {
                $0 is UITapGestureRecognizer
            }.count,
            1,
            "\(message): stable Mini must have exactly one tap owner",
            file: file,
            line: line
        )
        XCTAssertFalse(
            wrapper.transitionContentPassesUnclaimedTouchesToMaterial,
            "\(message): stable Mini passed background input into native glass",
            file: file,
            line: line
        )
        XCTAssertFalse(
            wrapper.transitionMaterialInteractionEnabled,
            "\(message): stable Mini returned with native material interaction enabled",
            file: file,
            line: line
        )
        XCTAssertFalse(
            wrapper.glassIsInteractive,
            "\(message): stable Mini recreated an unconstrained interactive UIGlassEffect",
            file: file,
            line: line
        )
        let boundedPressRecognizers = wrapper.gestureRecognizers?.compactMap {
            $0 as? GlassHighlightGestureRecognizer
        } ?? []
        XCTAssertEqual(
            boundedPressRecognizers.count,
            1,
            "\(message): stable Mini must have exactly one bounded press owner",
            file: file,
            line: line
        )
        XCTAssertEqual(
            boundedPressRecognizers.first?.motionProfile,
            AetherMotion.bottomBarAccessoryPress,
            "\(message): stable Mini restored the wrong press profile",
            file: file,
            line: line
        )
        XCTAssertEqual(
            boundedPressRecognizers.first?.isEnabled,
            true,
            "\(message): stable Mini returned with bounded press feedback disabled",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertExactCollapsedDockGeometry(
        tabs: AetherTabBarController,
        wrapper: GlassBackgroundView,
        accessory: TabBarAccessoryView,
        expectedWrapperFrame: CGRect,
        expectedWrapperBounds: CGRect,
        expectedAccessoryFrame: CGRect,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.020))

        XCTAssertEqual(
            tabs.bottomBarAccessoryPresentationState,
            .collapsed,
            message,
            file: file,
            line: line
        )
        assertFrame(
            wrapper.frame,
            equals: expectedWrapperFrame,
            accuracy: 0.01,
            message: "\(message): wrapper model frame missed the dock",
            file: file,
            line: line
        )
        assertFrame(
            wrapper.bounds,
            equals: expectedWrapperBounds,
            accuracy: 0.01,
            message: "\(message): wrapper model bounds retained press stretch",
            file: file,
            line: line
        )
        assertFrame(
            accessory.frame,
            equals: expectedAccessoryFrame,
            accuracy: 0.01,
            message: "\(message): accessory model frame missed the local dock",
            file: file,
            line: line
        )

        if let presentation = wrapper.layer.presentation() {
            assertFrame(
                presentation.frame,
                equals: expectedWrapperFrame,
                accuracy: 0.10,
                message: "\(message): wrapper presentation frame retained a tap deformation",
                file: file,
                line: line
            )
            assertFrame(
                presentation.bounds,
                equals: expectedWrapperBounds,
                accuracy: 0.10,
                message: "\(message): wrapper presentation bounds retained a tap deformation",
                file: file,
                line: line
            )
            XCTAssertTrue(
                CATransform3DIsIdentity(presentation.transform),
                "\(message): wrapper presentation transform retained press motion",
                file: file,
                line: line
            )
            XCTAssertTrue(
                CATransform3DIsIdentity(presentation.sublayerTransform),
                "\(message): wrapper presentation subtree retained press stretch",
                file: file,
                line: line
            )
        }
        if let presentation = accessory.layer.presentation() {
            assertFrame(
                presentation.frame,
                equals: expectedAccessoryFrame,
                accuracy: 0.10,
                message: "\(message): accessory presentation frame missed the local dock",
                file: file,
                line: line
            )
            XCTAssertTrue(
                CATransform3DIsIdentity(presentation.transform),
                "\(message): accessory presentation transform retained press motion",
                file: file,
                line: line
            )
            XCTAssertTrue(
                CATransform3DIsIdentity(presentation.sublayerTransform),
                "\(message): accessory presentation subtree retained press stretch",
                file: file,
                line: line
            )
        }
    }

    private func assertAccessoryIsInteractive(
        _ accessory: InteractiveBottomAccessoryView,
        in tabs: AetherTabBarController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(accessory.isUserInteractionEnabled, file: file, line: line)
        XCTAssertFalse(accessory.accessibilityElementsHidden, file: file, line: line)
        let point = accessory.actionButton.convert(
            CGPoint(
                x: accessory.actionButton.bounds.midX,
                y: accessory.actionButton.bounds.midY
            ),
            to: tabs.view
        )
        let hit = tabs.view.hitTest(point, with: nil)
        var ancestor = accessory.superview
        var wrapper: GlassBackgroundView?
        while let candidate = ancestor {
            if let glass = candidate as? GlassBackgroundView {
                wrapper = glass
                break
            }
            ancestor = candidate.superview
        }
        let wrapperHit = wrapper?.hitTest(
            tabs.view.convert(point, to: wrapper),
            with: nil
        )
        let contentHit = wrapper?.contentView.hitTest(
            tabs.view.convert(point, to: wrapper?.contentView),
            with: nil
        )
        func describe(_ view: UIView?) -> String {
            guard let view else { return "nil" }
            let frameInTabs = view.superview?.convert(view.frame, to: tabs.view)
                ?? view.frame
            return "\(type(of: view))@\(ObjectIdentifier(view))"
                + " frame=\(view.frame) frameInTabs=\(frameInTabs)"
                + " bounds=\(view.bounds) alpha=\(view.alpha)"
                + " hidden=\(view.isHidden) interaction=\(view.isUserInteractionEnabled)"
        }
        let renderer = wrapper?.usesNativeGlassRendererForTesting == true
            ? "native"
            : "legacy"
        XCTAssertTrue(
            hit === accessory.actionButton
                || hit?.isDescendant(of: accessory.actionButton) == true,
            "Accessory button must receive touches through the reused glass;"
                + " renderer=\(renderer);"
                + " rootHit={\(describe(hit))}; wrapperHit={\(describe(wrapperHit))};"
                + " contentHit={\(describe(contentHit))}; wrapper={\(describe(wrapper))};"
                + " contentView={\(describe(wrapper?.contentView))};"
                + " accessory={\(describe(accessory))};"
                + " button={\(describe(accessory.actionButton))}",
            file: file,
            line: line
        )
    }

    private func assertTransientAccessibilityOwnership(
        collapsedEndpoint: UIView,
        expandedHost: UIView,
        tabBar: UIView,
        underlyingContent: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            collapsedEndpoint.accessibilityElementsHidden,
            "Mini must not own VoiceOver during a transition",
            file: file,
            line: line
        )
        XCTAssertTrue(
            expandedHost.accessibilityElementsHidden,
            "Full must not own VoiceOver during a transition",
            file: file,
            line: line
        )
        XCTAssertTrue(
            tabBar.accessibilityElementsHidden,
            "The tab bar must stay behind the transient/full surface",
            file: file,
            line: line
        )
        XCTAssertTrue(
            underlyingContent.accessibilityElementsHidden,
            "The tab screen must stay behind the transient/full surface",
            file: file,
            line: line
        )
    }

    private func tabsTiming(_ tabs: AetherTabBarController) -> AetherTabBarController.TabBarVisibilityContentTiming {
        guard let timing = tabs.tabBarVisibilityContentTimingForTesting else {
            XCTFail("Expected a bottom-bar content animation")
            return .init(duration: 0.0, delay: 0.0)
        }
        return timing
    }

    private func makeController(title: String, image: String) -> AetherViewController {
        let controller = AetherViewController()
        let icon = UIImage(systemName: image)
        controller.tabBarItem = UITabBarItem(title: title, image: icon, selectedImage: icon)
        return controller
    }

    private func makeSearchController() -> UIViewController {
        let controller = UIViewController()
        controller.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass"))
        return controller
    }

    private func makeNavigationSearchController() -> AetherNavigationController {
        let root = AetherViewController()
        root.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass"))
        let navigationController = AetherNavigationController(mode: .single)
        navigationController.setViewControllers([root], animated: false)
        return navigationController
    }
}

private final class UserDrivenChromeScrollView: UIScrollView {
    var simulatesUserDrivenScroll = false
    var simulatesDeceleration = false

    override var isTracking: Bool {
        simulatesUserDrivenScroll
    }

    override var isDragging: Bool {
        simulatesUserDrivenScroll
    }

    override var isDecelerating: Bool {
        simulatesDeceleration
    }
}

@MainActor
private final class AccessoryOffsetListController: AetherViewController {
    let listNode = AetherListNode()
    private var didInstallItems = false

    init() {
        super.init(navigationBarPresentationData: nil)
        listNode.stackFromBottom = true
        listNode.automaticInsetEdges = [.bottom]
        contentNode = listNode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var primaryScrollViewForChrome: UIScrollView? {
        listNode.scroller
    }

    func installItems() {
        guard !didInstallItems else { return }
        didInstallItems = true
        let items: [AetherListItem] = (0..<40).map {
            AccessoryOffsetListItem(id: $0, height: 44.0)
        }
        listNode.transaction(
            insertIndicesAndItems: items.enumerated().map {
                AetherListInsertItem(index: $0.offset, item: $0.element)
            },
            options: [.synchronous]
        )
    }
}

@MainActor
private final class NavigationLifecycleListController: AetherViewController {
    let listNode = AetherListNode()
    private let itemCount: Int
    private var didInstallItems = false

    init(itemCount: Int) {
        self.itemCount = itemCount
        super.init(navigationBarPresentationData: nil)
        listNode.automaticInsetEdges = [.bottom]
        contentNode = listNode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var primaryScrollViewForChrome: UIScrollView? {
        listNode.scroller
    }

    func installItems() {
        guard !didInstallItems else { return }
        didInstallItems = true
        let items: [AetherListItem] = (0..<itemCount).map {
            AccessoryOffsetListItem(id: $0, height: 44.0)
        }
        listNode.transaction(
            insertIndicesAndItems: items.enumerated().map {
                AetherListInsertItem(index: $0.offset, item: $0.element)
            },
            options: [.synchronous]
        )
    }
}

private final class AccessoryOffsetListItem: AetherListItem {
    let id: Int
    let height: CGFloat

    init(id: Int, height: CGFloat) {
        self.id = id
        self.height = height
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { height }
    var estimatedHeight: CGFloat { height }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        (
            AccessoryOffsetListItemNode(),
            AetherListItemNodeLayout(
                contentSize: CGSize(width: params.width, height: height)
            )
        )
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: height)
        )
    }
}

private final class AccessoryOffsetListItemNode: AetherListItemNode {}

private final class ChromeScrollFixtureController: AetherViewController {
    private(set) var containerLayoutUpdateCount = 0

    let chromeScrollView: UserDrivenChromeScrollView = {
        let scrollView = UserDrivenChromeScrollView()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentSize = CGSize(width: 390.0, height: 2_000.0)
        return scrollView
    }()

    override var primaryScrollViewForChrome: UIScrollView? {
        chromeScrollView
    }

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        containerLayoutUpdateCount += 1
        super.containerLayoutUpdated(layout, transition: transition)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(chromeScrollView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        chromeScrollView.frame = view.bounds
    }
}

private final class SearchLifecycleViewController: AetherViewController {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    var onDeactivate: (() -> Void)?

    override func tabBarActivateSearch() {
        activationCount += 1
    }

    override func tabBarDeactivateSearch() {
        deactivationCount += 1
        onDeactivate?()
    }
}

private final class FixedBottomAccessoryView: TabBarAccessoryView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        self.fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var nominalHeight: CGFloat {
        fixedHeight
    }
}

private final class ResizableBottomAccessoryView: TabBarAccessoryView {
    var requestedHeight: CGFloat

    init(height: CGFloat) {
        requestedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var nominalHeight: CGFloat {
        requestedHeight
    }
}

private final class RecordingTabBarMinimizationDelegate:
    AetherTabBarControllerMinimizationDelegate {
    struct Update {
        let progress: CGFloat
        let bottomBarAccessoryFrame: CGRect?
        let wasDeliveredOnMainThread: Bool
    }

    var updates: [Update] = []
    var onUpdate: ((Update) -> Void)?

    func tabBarController(
        _ controller: AetherTabBarController,
        didUpdateMinimizationProgress progress: CGFloat,
        bottomBarAccessoryFrame: CGRect?
    ) {
        let update = Update(
            progress: progress,
            bottomBarAccessoryFrame: bottomBarAccessoryFrame,
            wasDeliveredOnMainThread: Thread.isMainThread
        )
        updates.append(update)
        onUpdate?(update)
    }
}

private final class InteractiveBottomAccessoryView: TabBarAccessoryView {
    let actionButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        actionButton.setTitle("Action", for: .normal)
        addSubview(actionButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayout(
        size: CGSize,
        transition: ContainedViewLayoutTransition
    ) {
        transition.updateFrame(
            view: actionButton,
            frame: CGRect(origin: .zero, size: size)
        )
    }
}

/// Deterministic sender for the private Objective-C tap action. UIKit exposes
/// recognizer state read-only, so overriding the getter lets the test exercise
/// the exact production handler without fabricating `UITouch` instances.
private final class EndedTapGestureRecognizer: UITapGestureRecognizer {
    override var state: UIGestureRecognizer.State {
        get { .ended }
        set { /* deterministic test sender intentionally ignores resets */ }
    }
}

private final class RecordingExpandedAccessoryController: UIViewController,
    BottomBarAccessoryTransitionParticipant {
    private(set) var contexts: [BottomBarAccessoryTransitionContext] = []

    func prepareBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    ) {
        contexts.append(context)
    }

    func updateBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    ) {
        contexts.append(context)
    }

    func completeBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    ) {
        contexts.append(context)
    }
}

private extension CGRect {
    func isApproximatelyEqual(
        to other: CGRect,
        accuracy: CGFloat = 0.01
    ) -> Bool {
        abs(minX - other.minX) <= accuracy
            && abs(minY - other.minY) <= accuracy
            && abs(width - other.width) <= accuracy
            && abs(height - other.height) <= accuracy
    }
}

private extension UIView {
    var directGlassSubviews: [GlassBackgroundView] {
        subviews.compactMap { $0 as? GlassBackgroundView }
    }

    var allGlassDescendants: [GlassBackgroundView] {
        var result = (self as? GlassBackgroundView).map { [$0] } ?? []
        for subview in subviews {
            result.append(contentsOf: subview.allGlassDescendants)
        }
        return result
    }

    func firstDescendant(identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.firstDescendant(identifier: identifier) {
                return match
            }
        }
        return nil
    }

    func firstDescendant(accessibilityLabel label: String) -> UIView? {
        if accessibilityLabel == label { return self }
        for subview in subviews {
            if let match = subview.firstDescendant(accessibilityLabel: label) {
                return match
            }
        }
        return nil
    }

    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }

    func firstAncestor<T: UIView>(of type: T.Type) -> T? {
        var candidate = superview
        while let view = candidate {
            if let match = view as? T {
                return match
            }
            candidate = view.superview
        }
        return nil
    }
}
