import XCTest
import UIKit
@testable import AetherUI

final class NavigationBarButtonLayerTests: XCTestCase {
    override func tearDown() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        super.tearDown()
    }

    func testLegacyUsesFortyFourPointBaseContentHeight() {
        let bar = makeBar(style: .legacy)

        XCTAssertEqual(bar.contentHeight(defaultHeight: 60.0), 44.0, accuracy: 0.001)
    }

    func testLiquidGlassKeepsConfiguredBaseContentHeight() {
        let bar = makeBar(style: .glass)

        XCTAssertEqual(bar.contentHeight(defaultHeight: 60.0), 60.0, accuracy: 0.001)
    }

    func testLegacyAnimatedContentSwapUsesAlphaWithoutPrivateBlurFilter() {
        let bar = makeBar(style: .legacy)
        let first = FixedExpansionContentView(height: 30.0)
        let replacement = FixedExpansionContentView(height: 36.0)
        bar.setContentView(first, animated: false)
        layout(bar)

        bar.setContentView(replacement, animated: true)

        XCTAssertEqual(replacement.alpha, 0.0, accuracy: 0.001)
        XCTAssertNil(replacement.layer.filters)
        layout(bar, transition: .animated(duration: 0.28, curve: .easeInOut))
        XCTAssertEqual(replacement.alpha, 1.0, accuracy: 0.001)
        XCTAssertNil(replacement.layer.filters)
    }

    func testLegacyButtonTransitionRetainsAlphaAndScaleWithoutPrivateBlurFilter() throws {
        let bar = makeBar(style: .legacy)
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 32.0)
        let item = NavigationBarItem()
        item.rightBarButtonItems = [UIBarButtonItem(customView: customView)]
        bar.item = item
        layout(bar)

        bar.setButtonTransitionEffects(
            alpha: 0.42,
            blurRadius: 12.0,
            scale: 0.91,
            transition: .immediate
        )

        XCTAssertEqual(customView.alpha, 0.42, accuracy: 0.001)
        XCTAssertEqual(customView.transform.a, 0.91, accuracy: 0.001)
        XCTAssertEqual(customView.transform.d, 0.91, accuracy: 0.001)
        XCTAssertNil(customView.layer.filters)
    }

    func testLiveSwitchToLegacyClearsOnlyOwnedTransitionBlurAndKeepsVisualEndpoint() {
        let bar = makeBar(style: .glass)
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 32.0)
        let item = NavigationBarItem()
        item.rightBarButtonItems = [UIBarButtonItem(customView: customView)]
        bar.item = item
        layout(bar)

        bar.setButtonTransitionEffects(
            alpha: 0.55,
            blurRadius: 9.0,
            scale: 0.94,
            transition: .immediate
        )
        let expectedAlpha = customView.alpha
        let expectedTransform = customView.transform

        bar.updatePresentationData(
            NavigationBarPresentationData(theme: NavigationBarTheme(style: .legacy)),
            transition: .immediate
        )

        XCTAssertEqual(customView.alpha, expectedAlpha, accuracy: 0.001)
        XCTAssertEqual(customView.transform, expectedTransform)
        XCTAssertNil(customView.layer.filters)
        #if !APPSTORE_SAFE
        XCTAssertFalse((customView.layer.animationKeys() ?? []).contains { key in
            (customView.layer.animation(forKey: key) as? CAPropertyAnimation)?
                .keyPath?.contains(ObfuscatedSymbols.gaussianBlur) == true
        })
        #endif
    }

    func testLegacyBackButtonNeverAllocatesHiddenGlassRenderer() {
        let backButton = NavigationBackButtonView(appearanceStyle: .legacy)
        backButton.usesGlassStyle = true
        backButton.frame = CGRect(x: 0.0, y: 0.0, width: 96.0, height: 44.0)
        backButton.layoutIfNeeded()

        XCTAssertNil(backButton.glassBackgroundForTesting)
        XCTAssertIdentical(backButton.contentContainerForTesting.superview, backButton)
        XCTAssertTrue(backButton.descendants(ofType: UIVisualEffectView.self).isEmpty)
    }

    func testBackButtonLiveAppearanceSwitchKeepsContentAndPersistentGesturesStable() throws {
        let backButton = NavigationBackButtonView(appearanceStyle: .liquidGlassV1)
        backButton.text = "Back"
        backButton.icon = UIImage(systemName: "chevron.left")
        backButton.frame = CGRect(x: 0.0, y: 0.0, width: 96.0, height: 44.0)
        let contentContainer = backButton.contentContainerForTesting
        let tapRecognizer = try XCTUnwrap(
            backButton.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer })
        )
        let classicRecognizer = try XCTUnwrap(
            backButton.gestureRecognizers?.first(where: { $0 is AetherClassicPressGestureRecognizer })
        )

        backButton.usesGlassStyle = true
        let initialGlass = try XCTUnwrap(backButton.glassBackgroundForTesting)
        backButton.layoutIfNeeded()

        XCTAssertTrue(contentContainer.isDescendant(of: initialGlass.contentView))
        XCTAssertTrue(backButton.gestureRecognizers?.contains(where: { $0 === tapRecognizer }) == true)
        XCTAssertTrue(backButton.gestureRecognizers?.contains(where: { $0 === classicRecognizer }) == true)
        XCTAssertFalse(classicRecognizer.isEnabled)

        backButton.appearanceStyleOverride = .legacy

        XCTAssertNil(backButton.glassBackgroundForTesting)
        XCTAssertIdentical(contentContainer.superview, backButton)
        XCTAssertTrue(backButton.gestureRecognizers?.contains(where: { $0 === tapRecognizer }) == true)
        XCTAssertTrue(backButton.gestureRecognizers?.contains(where: { $0 === classicRecognizer }) == true)
        XCTAssertTrue(classicRecognizer.isEnabled)
        XCTAssertFalse(backButton.gestureRecognizers?.contains(where: { $0 is GlassHighlightGestureRecognizer }) == true)

        backButton.appearanceStyleOverride = .liquidGlassV1

        let rebuiltGlass = try XCTUnwrap(backButton.glassBackgroundForTesting)
        XCTAssertFalse(rebuiltGlass === initialGlass)
        XCTAssertTrue(contentContainer.isDescendant(of: rebuiltGlass.contentView))
        XCTAssertTrue(backButton.gestureRecognizers?.contains(where: { $0 === tapRecognizer }) == true)
        XCTAssertTrue(backButton.gestureRecognizers?.contains(where: { $0 === classicRecognizer }) == true)
    }

    func testLiveSwitchToLegacyCancelsSeparatedGlueAndDropsAnimatorGroupReferences() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let first = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: nil, action: nil)
        let second = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        first.separatesSharedBackground = true
        second.separatesSharedBackground = true
        let item = NavigationBarItem()
        item.rightBarButtonItems = [first, second]
        bar.item = item
        layout(bar)

        let chromeLayout = bar.buttonChromeLayout()
        bar.setButtonChromeLayout(
            chromeLayout,
            transition: morphTransition(),
            appearing: true
        )
        let animator = try XCTUnwrap(bar.debugRightSeparatedButtonGlueAnimator)
        XCTAssertTrue(animator.hasActiveDisplayLinkForTesting)
        XCTAssertEqual(animator.retainedGroupCountForTesting, 2)

        bar.updatePresentationData(
            NavigationBarPresentationData(theme: NavigationBarTheme(style: .legacy)),
            transition: .immediate
        )

        XCTAssertNil(bar.debugRightSeparatedButtonGlueAnimator)
        XCTAssertFalse(animator.hasActiveDisplayLinkForTesting)
        XCTAssertEqual(animator.retainedGroupCountForTesting, 0)
    }

    func testSeparatedButtonLayerHostsCustomButtonOutsideContentHierarchy() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 32.0)

        let item = NavigationBarItem()
        item.leftBarButtonItems = [UIBarButtonItem(customView: customView)]

        bar.item = item
        layout(bar)

        XCTAssertIdentical(bar.debugButtonLayer.superview, hostView)
        XCTAssertFalse(bar.debugButtonLayer.isDescendant(of: bar))
        XCTAssertTrue(customView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(customView.isDescendant(of: bar.debugButtonsContainerView))
        XCTAssertIdentical(customView, item.leftBarButtonItems?.first?.customView)
    }

    func testLegacyInlineModeStillAvailableForComparison() {
        NavigationBarImpl.defaultButtonHostingMode = .legacyInline

        let bar = makeBar()
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 32.0)

        let item = NavigationBarItem()
        item.leftBarButtonItems = [UIBarButtonItem(customView: customView)]

        bar.item = item
        layout(bar)

        XCTAssertFalse(customView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(customView.isDescendant(of: bar.debugButtonsContainerView))
    }

    func testCustomButtonViewIdentitySurvivesRelayoutAndIsRemovedWithItem() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 32.0)

        let item = NavigationBarItem()
        item.rightBarButtonItems = [UIBarButtonItem(customView: customView)]

        bar.item = item
        layout(bar)
        let firstSuperview = customView.superview

        layout(bar)

        XCTAssertIdentical(customView, item.rightBarButtonItems?.first?.customView)
        XCTAssertIdentical(customView.superview, firstSuperview)
        XCTAssertTrue(customView.isDescendant(of: bar.debugButtonLayer))

        let replacement = NavigationBarItem()
        bar.item = replacement
        layout(bar)

        XCTAssertNil(customView.superview)
    }

    func testCustomTitleViewMovesToButtonLayerButPlainTitleStaysInline() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let titleView = UILabel()
        titleView.text = "Custom"
        titleView.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 24.0)

        let customTitleItem = NavigationBarItem()
        customTitleItem.titleView = titleView

        bar.item = customTitleItem
        layout(bar)

        XCTAssertTrue(titleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(titleView.isDescendant(of: bar.debugButtonsContainerView))
        XCTAssertIdentical(titleView, customTitleItem.titleView)

        let plainTitleItem = NavigationBarItem()
        plainTitleItem.title = "Plain"
        plainTitleItem.subtitle = "Subtitle"

        bar.item = plainTitleItem
        layout(bar)

        XCTAssertNil(titleView.superview)
        XCTAssertNil(bar.debugButtonLayer.descendantTextView(text: "Plain"))
        XCTAssertNil(bar.debugButtonLayer.descendantTextView(text: "Subtitle"))
        XCTAssertNotNil(bar.debugButtonsContainerView.descendantTextView(text: "Plain"))
        XCTAssertNotNil(bar.debugButtonsContainerView.descendantTextView(text: "Subtitle"))
    }

    func testLegacyRightButtonMorphAppearsAnchoredAtFinalRightEdge() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [UIBarButtonItem(title: "Old", style: .plain, target: nil, action: nil)]
        bar.item = sourceItem
        layout(bar)

        let oldButton = bar.debugButtonLayer.descendantControl(title: "Old")
        XCTAssertNotNil(oldButton)

        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [UIBarButtonItem(title: "New", style: .plain, target: nil, action: nil)]

        bar.withButtonMorphTransition(morphTransition()) {
            bar.item = targetItem
            layout(bar, transition: morphTransition())
        }

        let newButton = bar.debugButtonLayer.descendantControl(title: "New")
        XCTAssertNotNil(newButton)
        XCTAssertNotNil(oldButton?.superview)

        guard let newButton, let container = newButton.superview else {
            return
        }
        XCTAssertEqual(container.frame.maxX, 312.0, accuracy: 0.5)
        XCTAssertEqual(newButton.frame.maxX, container.bounds.width, accuracy: 0.5)
    }

    func testCustomTitleViewMorphUsesButtonLayerForOutgoingAndIncomingViews() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let sourceTitleView = UILabel()
        sourceTitleView.text = "Source Custom"
        sourceTitleView.frame = CGRect(x: 0.0, y: 0.0, width: 110.0, height: 24.0)

        let sourceItem = NavigationBarItem()
        sourceItem.titleView = sourceTitleView
        bar.item = sourceItem
        layout(bar)

        let targetTitleView = UILabel()
        targetTitleView.text = "Target Custom"
        targetTitleView.frame = CGRect(x: 0.0, y: 0.0, width: 110.0, height: 24.0)
        let targetItem = NavigationBarItem()
        targetItem.titleView = targetTitleView

        bar.withButtonMorphTransition(morphTransition()) {
            bar.item = targetItem
            layout(bar)
        }

        XCTAssertTrue(sourceTitleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(targetTitleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(targetTitleView.isDescendant(of: bar.debugButtonsContainerView))
    }

    func testCustomTitleViewIsHiddenInTitleTransitionMode() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let titleView = UILabel()
        titleView.text = "Custom"
        titleView.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 24.0)

        let item = NavigationBarItem()
        item.titleView = titleView

        bar.item = item
        layout(bar)
        bar.setTitleTransitionMode(true)
        layout(bar)

        XCTAssertTrue(titleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(titleView.alpha, 0.0, accuracy: 0.001)
    }

    func testTransitionTitleBarDoesNotStealCustomTitleViewFromButtonLayer() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let sharedHostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let sharedBar = makeBar(hostView: sharedHostView)
        let titleView = UILabel()
        titleView.text = "Custom"
        titleView.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 24.0)

        let item = NavigationBarItem()
        item.titleView = titleView

        sharedBar.item = item
        layout(sharedBar)

        let transitionHostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let transitionBar = makeBar(hostView: transitionHostView)
        transitionBar.hostsNavigationItemTitleView = false
        transitionBar.setTitleTransitionMode(true)
        transitionBar.item = item
        layout(transitionBar)

        XCTAssertTrue(titleView.isDescendant(of: sharedBar.debugButtonLayer))
        XCTAssertFalse(titleView.isDescendant(of: transitionBar.debugButtonLayer))
        XCTAssertFalse(titleView.isDescendant(of: transitionBar.debugButtonsContainerView))
        XCTAssertIdentical(titleView, item.titleView)
    }

    func testTallCustomTitleHeightIsAvailableBeforeFirstLayoutAndIncludesAccessory() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let titleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        let item = NavigationBarItem()
        item.titleView = titleView

        let bar = makeBar()
        bar.item = item
        bar.setContentView(FixedExpansionContentView(height: 34.0), animated: false)
        bar.updateMeasuredTitleHeight(
            titleView: item.titleView,
            size: CGSize(width: 320.0, height: 104.0),
            defaultHeight: 60.0,
            leftInset: 0.0,
            rightInset: 0.0,
            requestLayoutIfNeeded: false
        )

        XCTAssertEqual(bar.contentHeight(defaultHeight: 60.0), 126.0, accuracy: 0.5)

        let transitionBar = makeBar()
        transitionBar.hostsNavigationItemTitleView = false
        transitionBar.item = item
        transitionBar.setContentView(FixedExpansionContentView(height: 34.0), animated: false)
        transitionBar.updateMeasuredTitleHeight(
            titleView: item.titleView,
            size: CGSize(width: 320.0, height: 104.0),
            defaultHeight: 60.0,
            leftInset: 0.0,
            rightInset: 0.0,
            requestLayoutIfNeeded: false
        )

        XCTAssertEqual(transitionBar.contentHeight(defaultHeight: 60.0), 126.0, accuracy: 0.5)
        XCTAssertIdentical(titleView, item.titleView)
        XCTAssertFalse(titleView.isDescendant(of: transitionBar.debugButtonLayer))
    }

    func testAppearingTallCustomTitleKeepsFinalBoundsDuringMorphSetup() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 140.0))
        let bar = makeBar(hostView: hostView)

        let sourceItem = NavigationBarItem()
        sourceItem.titleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        bar.item = sourceItem
        layout(bar, height: 140.0)

        let targetTitleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        let targetItem = NavigationBarItem()
        targetItem.titleView = targetTitleView

        bar.withButtonMorphTransition(morphTransition()) {
            bar.item = targetItem
            layout(bar, height: 140.0, transition: morphTransition())
        }

        XCTAssertTrue(targetTitleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(targetTitleView.bounds.width, 120.0, accuracy: 0.5)
        XCTAssertEqual(targetTitleView.bounds.height, 92.0, accuracy: 0.5)
        XCTAssertEqual(targetTitleView.center.y, 46.0, accuracy: 0.5)
    }

    func testButtonOnlyHeightOverrideKeepsTallCustomTitleInTitleRow() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 180.0))
        let bar = makeBar(hostView: hostView)
        let titleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        let item = NavigationBarItem()
        item.titleView = titleView

        bar.item = item
        bar.setContentHeightOverride(126.0)
        bar.updateMeasuredTitleHeight(
            titleView: item.titleView,
            size: CGSize(width: 320.0, height: 180.0),
            defaultHeight: 60.0,
            leftInset: 0.0,
            rightInset: 0.0,
            requestLayoutIfNeeded: false
        )
        layout(bar, height: 180.0)

        XCTAssertTrue(titleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(titleView.bounds.height, 92.0, accuracy: 0.5)
        XCTAssertEqual(titleView.center.y, 46.0, accuracy: 0.5)
    }

    func testURLImageCustomButtonKeepsExplicitSizeAfterLargeImageLoads() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let target = BarButtonActionTarget()
        let barButtonItem = UIBarButtonItem(
            imageURL: nil,
            placeholderImage: makeImage(size: CGSize(width: 180.0, height: 180.0)),
            target: target,
            action: #selector(BarButtonActionTarget.invoke(_:))
        )
        guard let button = barButtonItem.customView as? UIButton else {
            XCTFail("URL image bar button should be backed by a UIButton custom view")
            return
        }

        let item = NavigationBarItem()
        item.rightBarButtonItems = [barButtonItem]
        bar.item = item
        layout(bar)

        button.setImage(makeImage(size: CGSize(width: 180.0, height: 180.0)), for: .normal)
        layout(bar)
        button.layoutIfNeeded()

        let glassGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self)
        XCTAssertTrue(button.isDescendant(of: bar.debugButtonLayer))
        XCTAssertNotNil(glassGroup)
        XCTAssertTrue(glassGroup.map { button.isDescendant(of: $0) } ?? false)
        XCTAssertTrue(glassGroup?.isUserInteractionEnabled ?? false)
        XCTAssertTrue(button.superview?.isUserInteractionEnabled ?? false)
        XCTAssertIdentical(button, barButtonItem.customView)
        XCTAssertEqual(button.bounds.width, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.bounds.height, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.frame.width, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.frame.height, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.imageView?.frame.width ?? 0.0, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.imageView?.frame.height ?? 0.0, 38.0, accuracy: 0.5)
        button.isHighlighted = true
        button.configurationUpdateHandler?(button)
        XCTAssertEqual(button.alpha, 1.0)
        XCTAssertEqual(button.imageView?.alpha ?? 0.0, 1.0)
        button.isHighlighted = false
        XCTAssertEqual(
            button.actions(forTarget: target, forControlEvent: .touchUpInside),
            ["invoke:"]
        )
    }

    func testTargetActionStillWiredFromBarButtonItem() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let target = BarButtonActionTarget()

        let item = NavigationBarItem()
        item.rightBarButtonItems = [
            UIBarButtonItem(
                title: "Tap",
                style: .plain,
                target: target,
                action: #selector(BarButtonActionTarget.invoke(_:))
            )
        ]

        bar.item = item
        layout(bar)

        let button = bar.debugButtonLayer.descendantControl(title: "Tap")
        XCTAssertNotNil(button)

        XCTAssertEqual(
            button?.actions(forTarget: target, forControlEvent: .touchUpInside),
            ["invoke:"]
        )
    }

    @available(iOS 14.0, *)
    func testLateContextMenuProviderRewiresExistingGlassButtonWithoutRelayout() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let barButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: nil,
            action: nil
        )
        let item = NavigationBarItem()
        item.rightBarButtonItems = [barButtonItem]
        bar.item = item
        layout(bar)

        let group = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        let itemID = try XCTUnwrap(group.items.first?.id)
        let button = try XCTUnwrap(group.itemButton(id: itemID) as? UIControl)

        XCTAssertFalse(group.isUserInteractionEnabled)
        XCTAssertFalse(button.isUserInteractionEnabled)
        XCTAssertFalse(button.allControlEvents.contains(.touchDown))

        barButtonItem.contextMenuItemsProvider = {
            [.action(ContextMenuActionItem(title: "Action"))]
        }

        XCTAssertIdentical(
            bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self),
            group,
            "Provider invalidation should reuse the existing chrome group"
        )
        XCTAssertIdentical(group.itemButton(id: itemID), button)
        XCTAssertTrue(group.isUserInteractionEnabled)
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertTrue(button.allControlEvents.contains(.touchDown))
        let highlight = try XCTUnwrap(group.gestureRecognizers?.compactMap { $0 as? GlassHighlightGestureRecognizer }.first)
        XCTAssertFalse(highlight.allowsHighlight(from: button), "Menu touch-down must not also scale the group caption")
        XCTAssertFalse(highlight.beginHighlight(at: .zero, from: button))
        XCTAssertTrue(CATransform3DIsIdentity(group.layer.sublayerTransform))


        barButtonItem.contextMenuItemsProvider = nil

        XCTAssertIdentical(group.itemButton(id: itemID), button)
        XCTAssertFalse(group.isUserInteractionEnabled)
        XCTAssertFalse(button.isUserInteractionEnabled)
        XCTAssertFalse(button.allControlEvents.contains(.touchDown))
        XCTAssertTrue(highlight.allowsHighlight(from: button))
    }

    func testRepeatedAnimatedSameExpansionContentDoesNotAnimateRightChrome() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 138.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let target = BarButtonActionTarget()
        let rightItem = UIBarButtonItem(
            title: "Done",
            style: .plain,
            target: target,
            action: #selector(BarButtonActionTarget.invoke(_:))
        )

        let item = NavigationBarItem()
        item.rightBarButtonItems = [rightItem]
        bar.item = item
        layout(bar)

        let rightGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self)
        guard let rightGroup,
              let rightItemID = rightGroup.items.first?.id,
              let rightButton = rightGroup.itemButton(id: rightItemID) else {
            XCTFail("Expected right glass button to be hosted in the separated button layer")
            return
        }

        let chromeChain = rightButton.ancestorChain(until: bar.debugButtonLayer)
        chromeChain.forEach { $0.layer.removeAllAnimations() }

        let contentView = FixedExpansionContentView(height: 34.0)
        bar.setContentView(contentView, animated: true)
        bar.setContentView(contentView, animated: true)
        layout(bar, height: 138.0, transition: .animated(duration: 0.32, curve: .easeInOut))

        let animatedChromeViews = chromeChain.filter { !($0.layer.animationKeys() ?? []).isEmpty }
        XCTAssertTrue(animatedChromeViews.isEmpty, "Right button chrome should stay static during accessory-only crossfade")
    }

    func testNavigationButtonGlassStrokeIsHostedByNativeEffectView() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(
            hostView: hostView,
            style: .glass,
            appearanceStyle: .liquidGlassV2
        )

        let item = NavigationBarItem()
        item.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        ]
        bar.item = item
        layout(bar)

        guard let sourceGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self),
              let glassContainer = sourceGroup.ancestor(ofType: GlassBackgroundContainerView.self),
              let glassBackground = sourceGroup.descendant(ofType: GlassBackgroundView.self)
        else {
            XCTFail("Expected right glass stack to be hosted in a glass container")
            return
        }

        XCTAssertTrue(glassContainer.isUsingNativeContainerEffect)
        XCTAssertTrue(glassBackground.isSyntheticStrokeVisible)
        XCTAssertTrue(glassBackground.isSyntheticStrokeHostedByNativeEffectView)
    }

    func testGlassRightButtonStackAnimatesWidthWhenExpandingFromOneToMultipleItems() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let trailingItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [trailingItem]
        bar.item = sourceItem
        layout(bar)

        guard let sourceGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self),
              let chromeContainer = sourceGroup.ancestor(before: bar.debugButtonLayer),
              let glassContainer = sourceGroup.ancestor(ofType: GlassBackgroundContainerView.self)
        else {
            XCTFail("Expected right glass stack to be hosted in the separated button layer")
            return
        }

        let sourceWidth = sourceGroup.bounds.width
        let sourceChromeWidth = chromeContainer.bounds.width
        let leadingItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [leadingItem, trailingItem]

        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        XCTAssertGreaterThan(sourceGroup.bounds.width, sourceWidth + 0.5)
        XCTAssertGreaterThan(chromeContainer.bounds.width, sourceChromeWidth + 0.5)
        XCTAssertEqual(chromeContainer.frame.maxX, 304.0, accuracy: 0.5)
        XCTAssertEqual(sourceGroup.frame, CGRect(origin: .zero, size: sourceGroup.bounds.size))
        XCTAssertEqual(glassContainer.bounds.width, chromeContainer.bounds.width, accuracy: 0.5)
        XCTAssertEqual(glassContainer.bounds.height, chromeContainer.bounds.height, accuracy: 0.5)
        let sizePulse = sourceGroup.sizeMorphPulseAnimationForTesting
        XCTAssertEqual(sizePulse?.keyPath, "transform")
        XCTAssertEqual(
            sizePulse?.duration ?? 0.0,
            AetherMotion.navigationChrome.sizeMorphPulseDuration,
            accuracy: 0.001
        )
    }

    func testNavigationButtonGlassStrokeAnimatesWithWidthMorph() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(
            hostView: hostView,
            style: .glass,
            appearanceStyle: .liquidGlassV2
        )
        let trailingItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [trailingItem]
        bar.item = sourceItem
        layout(bar)

        guard let sourceGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self),
              let glassBackground = sourceGroup.descendant(ofType: GlassBackgroundView.self)
        else {
            XCTFail("Expected right glass stack to expose its glass background")
            return
        }
        XCTAssertTrue(glassBackground.isSyntheticStrokeVisible)
        let sourceStrokeWidth = glassBackground.bounds.width
        let sourceStrokePathUpdateCount = glassBackground.syntheticStrokePathUpdateCount

        let leadingItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [leadingItem, trailingItem]

        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        // The background view owns the width animation. Its layout pass moves
        // the synthetic stroke to the model endpoint synchronously, and the
        // stroke then follows the animated ancestor instead of running a
        // redundant child `path` / `bounds` track. Assert the visual contract:
        // the stroke stays installed and refreshes its cached geometry once.
        XCTAssertTrue(glassBackground.isSyntheticStrokeVisible)
        XCTAssertGreaterThan(glassBackground.bounds.width, sourceStrokeWidth + 0.5)
        XCTAssertEqual(
            glassBackground.syntheticStrokePathUpdateCount,
            sourceStrokePathUpdateCount + 1
        )
    }

    func testDistinctTitledBarButtonItemsReuseSemanticContentViewWithoutPulse() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Menu", style: .plain, target: nil, action: nil)
        ]
        bar.item = sourceItem
        layout(bar)

        let sourceGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        let semanticID = try XCTUnwrap(sourceGroup.items.first?.id)
        let sourceButton = try XCTUnwrap(sourceGroup.itemButton(id: semanticID))

        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Menu", style: .plain, target: nil, action: nil)
        ]
        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        let targetGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        XCTAssertIdentical(targetGroup, sourceGroup)
        XCTAssertIdentical(targetGroup.itemButton(id: semanticID), sourceButton)
        XCTAssertNil(targetGroup.sizeMorphPulseAnimationForTesting)
    }

    func testSeparatelyCreatedEquivalentImagesReuseSemanticButtonAndGroup() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let sourceImage = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        let targetImage = try XCTUnwrap(UIImage(systemName: "ellipsis"))

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [
            UIBarButtonItem(image: sourceImage, style: .plain, target: nil, action: nil)
        ]
        bar.item = sourceItem
        layout(bar)
        let sourceGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        let semanticID = try XCTUnwrap(sourceGroup.items.first?.id)
        let sourceButton = try XCTUnwrap(sourceGroup.itemButton(id: semanticID))

        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [
            UIBarButtonItem(image: targetImage, style: .plain, target: nil, action: nil)
        ]
        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        let targetGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        XCTAssertIdentical(targetGroup, sourceGroup)
        XCTAssertIdentical(targetGroup.itemButton(id: semanticID), sourceButton)
        XCTAssertNil(targetGroup.sizeMorphPulseAnimationForTesting)
    }

    func testAutomaticBackButtonKeepsOneSemanticElementAcrossItems() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        bar.previousItem = .item(NavigationBarItem())
        bar.item = NavigationBarItem()
        layout(bar)

        let sourceGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        let backID = try XCTUnwrap(sourceGroup.items.first?.id)
        let sourceButton = try XCTUnwrap(sourceGroup.itemButton(id: backID))

        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.previousItem = .item(NavigationBarItem())
            bar.item = NavigationBarItem()
            layout(bar, transition: transition)
        }

        let targetGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        XCTAssertIdentical(targetGroup, sourceGroup)
        XCTAssertIdentical(targetGroup.itemButton(id: backID), sourceButton)
        XCTAssertNil(targetGroup.sizeMorphPulseAnimationForTesting)
    }

    func testSeparatedGroupsFollowSemanticItemsWhenOrderChanges() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)

        let sourceCamera = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: nil, action: nil)
        sourceCamera.separatesSharedBackground = true
        let sourceMenu = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [sourceCamera, sourceMenu]
        bar.item = sourceItem
        layout(bar)

        let sourceGroups = bar.debugButtonLayer.descendants(ofType: GlassControlGroup.self)
        XCTAssertEqual(sourceGroups.count, 2)
        let sourceEntries = try sourceGroups.map { group -> (GlassControlGroup, AnyHashable, UIView) in
            let id = try XCTUnwrap(group.items.first?.id)
            return (group, id, try XCTUnwrap(group.itemButton(id: id)))
        }

        let targetMenu = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        targetMenu.separatesSharedBackground = true
        let targetCamera = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: nil, action: nil)
        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [targetMenu, targetCamera]
        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        for (group, id, button) in sourceEntries {
            XCTAssertIdentical(group.itemButton(id: id), button)
            XCTAssertNil(group.sizeMorphPulseAnimationForTesting)
        }
    }

    func testChangedSeparatedGroupDoesNotPulseUnchangedSibling() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Material pulses are intentionally disabled with Reduce Motion")
        }
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)

        let sourceCamera = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: nil, action: nil)
        sourceCamera.separatesSharedBackground = true
        let sourceMenu = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [sourceCamera, sourceMenu]
        bar.item = sourceItem
        layout(bar)
        let sourceGroups = bar.debugButtonLayer.descendants(ofType: GlassControlGroup.self)
        XCTAssertEqual(sourceGroups.count, 2)
        let unchangedGroup = sourceGroups[0]
        let changedGroup = sourceGroups[1]

        let targetCamera = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: nil, action: nil)
        targetCamera.separatesSharedBackground = true
        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [
            targetCamera,
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
        ]
        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        XCTAssertNil(unchangedGroup.sizeMorphPulseAnimationForTesting)
        XCTAssertNotNil(changedGroup.sizeMorphPulseAnimationForTesting)
        XCTAssertNotNil(changedGroup.materialPulseCounterAnimationForTesting)
    }

    func testAutomaticBackGlassButtonKeepsElasticStretchRecognizer() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        bar.previousItem = .item(NavigationBarItem())
        bar.item = NavigationBarItem()
        layout(bar)

        guard let sourceGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self) else {
            XCTFail("Expected automatic back button to be hosted in a glass group")
            return
        }

        XCTAssertTrue(bar.hasPureAutomaticBackButtonGroup)
        XCTAssertTrue(sourceGroup.gestureRecognizers?.contains(where: { $0 is GlassHighlightGestureRecognizer }) ?? false)
    }

    func testRightNavigationGlassButtonUsesUnifiedNavigationPressScale() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let item = NavigationBarItem()
        item.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        ]
        bar.item = item
        layout(bar)

        let rightGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        XCTAssertEqual(
            rightGroup.pressedSizeIncrease,
            AetherMotion.navigationButtonPress.pressedSizeIncrease,
            accuracy: 0.001
        )
    }

    func testNavigationGlassGroupDoesNotMaskNativeStretchSurface() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Native glass cornerConfiguration is only available on iOS 26+")
        }
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let item = NavigationBarItem()
        item.leftBarButtonItems = [
            UIBarButtonItem(title: "V4", style: .plain, target: nil, action: nil)
        ]
        bar.item = item
        layout(bar)

        let group = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        let glassBackground = try XCTUnwrap(group.descendant(ofType: GlassBackgroundView.self))
        guard let isMasked = glassBackground.isNativeGlassLayerMaskedForTesting else {
            throw XCTSkip("Native glass is unavailable in this runtime")
        }

        XCTAssertTrue(glassBackground.hasNativeCornerConfigurationForTesting)
        XCTAssertFalse(isMasked)
    }

    func testStandaloneGlassButtonDoesNotMaskNativeStretchSurface() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Native glass cornerConfiguration is only available on iOS 26+")
        }

        let button = GlassButton(title: "V4")
        button.frame = CGRect(x: 0.0, y: 0.0, width: 72.0, height: 72.0)
        button.layoutIfNeeded()

        let glassBackground = try XCTUnwrap(button.descendant(ofType: GlassBackgroundView.self))
        guard let isMasked = glassBackground.isNativeGlassLayerMaskedForTesting else {
            throw XCTSkip("Native glass is unavailable in this runtime")
        }

        XCTAssertTrue(glassBackground.hasNativeCornerConfigurationForTesting)
        XCTAssertFalse(isMasked)
    }

    func testGlassRightButtonStackAnimatesWidthWhenCollapsingFromMultipleToOneItem() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let leadingItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        let trailingItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [leadingItem, trailingItem]
        bar.item = sourceItem
        layout(bar)

        guard let sourceGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self),
              let chromeContainer = sourceGroup.ancestor(before: bar.debugButtonLayer),
              let glassContainer = sourceGroup.ancestor(ofType: GlassBackgroundContainerView.self)
        else {
            XCTFail("Expected right glass stack to be hosted in the separated button layer")
            return
        }

        let sourceWidth = sourceGroup.bounds.width
        let sourceChromeWidth = chromeContainer.bounds.width
        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [trailingItem]

        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        XCTAssertLessThan(sourceGroup.bounds.width, sourceWidth - 0.5)
        XCTAssertLessThan(chromeContainer.bounds.width, sourceChromeWidth - 0.5)
        XCTAssertEqual(chromeContainer.frame.maxX, 304.0, accuracy: 0.5)
        XCTAssertEqual(sourceGroup.frame, CGRect(origin: .zero, size: sourceGroup.bounds.size))
        XCTAssertEqual(glassContainer.bounds.width, chromeContainer.bounds.width, accuracy: 0.5)
        XCTAssertEqual(glassContainer.bounds.height, chromeContainer.bounds.height, accuracy: 0.5)
    }

    func testOutgoingSeparatedGlassGroupSurvivesCleanupDuringSlowFade() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let first = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: nil, action: nil)
        let second = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        first.separatesSharedBackground = true
        second.separatesSharedBackground = true

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [first, second]
        bar.item = sourceItem
        layout(bar)

        let sourceGroup = try XCTUnwrap(bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self))
        let glassContainer = try XCTUnwrap(sourceGroup.ancestor(ofType: GlassBackgroundContainerView.self))
        XCTAssertEqual(glassContainer.descendants(ofType: GlassControlGroup.self).count, 2)

        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [first]
        let transition = morphTransition()
        bar.withButtonMorphTransition(transition) {
            bar.item = targetItem
            layout(bar, transition: transition)
        }

        let groupsDuringFade = glassContainer.descendants(ofType: GlassControlGroup.self)
        XCTAssertEqual(groupsDuringFade.count, 2)
        XCTAssertEqual(groupsDuringFade.filter(\.isAwaitingAnimatedRemoval).count, 1)
    }

    func testTransitionMeasuredButtonChromeLayoutReadsChromeHiddenByTitleTransitionMode() throws {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let item = NavigationBarItem()
        item.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        ]
        bar.item = item
        layout(bar)

        let visibleFrame = try XCTUnwrap(bar.transitionMeasuredButtonChromeLayout().rightFrame)
        bar.setTitleTransitionMode(true)

        XCTAssertNil(bar.buttonChromeLayout().rightFrame)
        let hiddenMeasuredFrame = try XCTUnwrap(bar.transitionMeasuredButtonChromeLayout().rightFrame)
        XCTAssertEqual(hiddenMeasuredFrame.width, visibleFrame.width, accuracy: 0.1)
    }

    func testInteractivePopButtonPreviewExpandsToTargetAtFullProgress() throws {
        let source = NavigationBarImpl.ButtonChromeLayout(
            leftFrame: CGRect(x: 16.0, y: 10.0, width: 44.0, height: 44.0),
            rightFrame: CGRect(x: 260.0, y: 10.0, width: 44.0, height: 44.0)
        )
        let target = NavigationBarImpl.ButtonChromeLayout(
            leftFrame: CGRect(x: 16.0, y: 10.0, width: 100.0, height: 44.0),
            rightFrame: CGRect(x: 204.0, y: 10.0, width: 100.0, height: 44.0)
        )

        let preview = source.interactivePopPreviewLayout(towards: target, progress: 1.0)
        let leftFrame = try XCTUnwrap(preview.leftFrame)
        let rightFrame = try XCTUnwrap(preview.rightFrame)

        XCTAssertEqual(leftFrame.minX, 16.0, accuracy: 0.1)
        XCTAssertEqual(leftFrame.width, 100.0, accuracy: 0.1)
        XCTAssertEqual(rightFrame.maxX, 304.0, accuracy: 0.1)
        XCTAssertEqual(rightFrame.width, 100.0, accuracy: 0.1)
    }

    func testInteractivePopButtonPreviewShrinksToTargetAtFullProgress() throws {
        let source = NavigationBarImpl.ButtonChromeLayout(
            leftFrame: CGRect(x: 16.0, y: 10.0, width: 124.0, height: 44.0),
            rightFrame: CGRect(x: 180.0, y: 10.0, width: 124.0, height: 44.0)
        )
        let target = NavigationBarImpl.ButtonChromeLayout(
            leftFrame: CGRect(x: 16.0, y: 10.0, width: 44.0, height: 44.0),
            rightFrame: CGRect(x: 260.0, y: 10.0, width: 44.0, height: 44.0)
        )

        let preview = source.interactivePopPreviewLayout(towards: target, progress: 1.0)
        let leftFrame = try XCTUnwrap(preview.leftFrame)
        let rightFrame = try XCTUnwrap(preview.rightFrame)

        XCTAssertEqual(leftFrame.minX, 16.0, accuracy: 0.1)
        XCTAssertEqual(leftFrame.width, 44.0, accuracy: 0.1)
        XCTAssertEqual(rightFrame.maxX, 304.0, accuracy: 0.1)
        XCTAssertEqual(rightFrame.width, 44.0, accuracy: 0.1)
    }

    func testInteractivePopMissingTargetScalesCurrentButtonDownToPointSeven() {
        let source = NavigationBarImpl.ButtonChromeLayout(
            leftFrame: CGRect(x: 16.0, y: 10.0, width: 44.0, height: 44.0),
            rightFrame: CGRect(x: 260.0, y: 10.0, width: 44.0, height: 44.0)
        )
        let target = NavigationBarImpl.ButtonChromeLayout(
            leftFrame: nil,
            rightFrame: CGRect(x: 260.0, y: 10.0, width: 44.0, height: 44.0)
        )

        let preview = source.interactivePopPreviewLayout(towards: target, progress: 1.0)
        let scales = source.interactivePopMissingTargetScales(towards: target, progress: 1.0)

        XCTAssertEqual(preview.leftFrame, source.leftFrame)
        XCTAssertEqual(scales.left, 0.7, accuracy: 0.001)
        XCTAssertEqual(scales.right, 1.0, accuracy: 0.001)
    }

    func testButtonLayerHitTestingReturnsButtonsAndPassesThroughEmptySpace() {
        let layer = AetherNavigationBarButtonLayer(frame: CGRect(x: 0.0, y: 0.0, width: 240.0, height: 60.0))
        let button = UIButton(type: .system)

        layer.applyButtonPlacements(
            [
                AetherNavigationBarButtonPlacement(
                    id: "button",
                    view: button,
                    frame: CGRect(x: 12.0, y: 10.0, width: 44.0, height: 40.0),
                    hitTestInsets: UIEdgeInsets(top: 4.0, left: 4.0, bottom: 4.0, right: 4.0)
                )
            ],
            transition: .existing(.immediate)
        )

        XCTAssertIdentical(layer.hitTest(CGPoint(x: 20.0, y: 20.0), with: nil), button)
        XCTAssertIdentical(layer.hitTest(CGPoint(x: 9.0, y: 20.0), with: nil), button)
        XCTAssertNil(layer.hitTest(CGPoint(x: 120.0, y: 20.0), with: nil))
    }

    private func makeBar(
        hostView: UIView? = nil,
        style: NavigationBarStyle = .legacy,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) -> NavigationBarImpl {
        let resolvedAppearanceStyle = appearanceStyle
            ?? (style == .legacy ? .legacy : .liquidGlassV1)
        let bar = NavigationBarImpl(
            presentationData: NavigationBarPresentationData(
                theme: NavigationBarTheme(
                    style: style,
                    appearanceStyle: resolvedAppearanceStyle
                )
            )
        )
        bar.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0)
        if let hostView {
            hostView.addSubview(bar)
            bar.buttonLayerHostView = hostView
        }
        return bar
    }

    private func layout(_ bar: NavigationBarImpl, height: CGFloat = 104.0, transition: ContainedViewLayoutTransition = .immediate) {
        bar.updateLayout(
            size: CGSize(width: 320.0, height: height),
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: transition
        )
    }

    private func morphTransition() -> ContainedViewLayoutTransition {
        .animated(duration: 0.44, curve: .custom(0.16, 1.0, 0.30, 1.0))
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

}

private final class BarButtonActionTarget: NSObject {
    @objc func invoke(_ sender: Any?) {
    }
}

private final class FixedSizeView: UIView {
    let fixedSize: CGSize

    init(size: CGSize) {
        self.fixedSize = size
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        fixedSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        fixedSize
    }
}

private final class FixedExpansionContentView: NavigationBarContentView {
    let fixedHeight: CGFloat

    init(height: CGFloat) {
        self.fixedHeight = height
        super.init(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var nominalHeight: CGFloat {
        fixedHeight
    }

    override var mode: NavigationBarContentMode {
        .expansion
    }
}

private extension UIView {
    func descendant<T: UIView>(ofType type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let view = subview.descendant(ofType: type) {
                return view
            }
        }
        return nil
    }

    func descendants<T: UIView>(ofType type: T.Type) -> [T] {
        var result: [T] = []
        if let view = self as? T {
            result.append(view)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendants(ofType: type))
        }
        return result
    }

    func descendantControl(title: String) -> UIControl? {
        if let control = self as? UIControl, control.accessibilityLabel == title {
            return control
        }
        for subview in subviews {
            if let control = subview.descendantControl(title: title) {
                return control
            }
        }
        return nil
    }

    func descendantTextView(text: String) -> UIView? {
        if let label = self as? UILabel, label.text == text {
            return label
        }
        if accessibilityLabel == text {
            return self
        }
        for subview in subviews {
            if let view = subview.descendantTextView(text: text) {
                return view
            }
        }
        return nil
    }

    func ancestorChain(until stopView: UIView) -> [UIView] {
        var result: [UIView] = []
        var current: UIView? = self
        while let view = current {
            result.append(view)
            if view === stopView {
                break
            }
            current = view.superview
        }
        return result
    }

    func ancestor<T: UIView>(ofType type: T.Type) -> T? {
        var current = superview
        while let view = current {
            if let typed = view as? T {
                return typed
            }
            current = view.superview
        }
        return nil
    }

    func ancestor(before stopView: UIView) -> UIView? {
        var current: UIView? = self
        while let view = current, let parent = view.superview {
            if parent === stopView {
                return view
            }
            current = parent
        }
        return nil
    }
}
