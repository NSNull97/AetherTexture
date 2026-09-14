import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NavigationGlassMaterializationTests: XCTestCase {
    private let transition = ContainedViewLayoutTransition.animated(duration: 0.34, curve: .navigationFluidMorph)

    func testRealPopToEmptyRootRetainsOutgoingGroupsUntilDissolve() async throws {
        guard !UIAccessibility.isReduceMotionEnabled else { throw XCTSkip("Requires navigation animation") }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let data = NavigationBarPresentationData(theme: NavigationBarTheme(style: .glass))
        let root = AetherViewController(navigationBarPresentationData: data)
        let navigation = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        navigation.loadViewIfNeeded()
        let containerLayout = ContainerViewLayout(size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            additionalInsets: .zero, statusBarHeight: 47)
        navigation.containerLayoutUpdated(containerLayout, transition: .immediate)
        let detail = AetherViewController(navigationBarPresentationData: data)
        detail.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "A long menu title", style: .plain, target: nil, action: nil)
        navigation.pushViewController(detail, animated: false)
        navigation.containerLayoutUpdated(containerLayout, transition: .immediate)
        let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
        func groups(_ view: UIView) -> [GlassControlGroup] {
            (view as? GlassControlGroup).map { [$0] } ?? view.subviews.flatMap(groups)
        }
        let outgoing = groups(bar.debugButtonLayer).filter { !$0.items.isEmpty }
        XCTAssertEqual(outgoing.count, 2)
        navigation.popViewController(animated: true)
        let started = expectation(description: "Pop has begun dissolving both sides")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            navigation.containerLayoutUpdated(containerLayout, transition: .immediate)
            for group in outgoing {
                XCTAssertNotNil(group.superview)
                XCTAssertTrue(group.isFinishingContentRemoval)
                XCTAssertGreaterThan(group.bounds.width, 0)
            }
            started.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        let finished = expectation(description: "Exit owns cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for group in outgoing {
                XCTAssertFalse(group.isFinishingContentRemoval)
                XCTAssertEqual(group.bounds.size, .zero)
            }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testRealPopToHiddenRootKeepsOutgoingButtonsOnScreenWhileDissolving() async throws {
        guard !UIAccessibility.isReduceMotionEnabled else { throw XCTSkip("Requires navigation animation") }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let data = NavigationBarPresentationData(theme: NavigationBarTheme(style: .glass))
        let root = AetherViewController(navigationBarPresentationData: data)
        root.displayNavigationBar = false
        root.navigationBarItem.rightBarButtonItem = UIBarButtonItem(title: "Hidden action", style: .plain, target: nil, action: nil)
        let navigation = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        navigation.loadViewIfNeeded()
        let containerLayout = ContainerViewLayout(size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            additionalInsets: .zero, statusBarHeight: 47)
        navigation.containerLayoutUpdated(containerLayout, transition: .immediate)
        let detail = AetherViewController(navigationBarPresentationData: data)
        detail.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "A long menu title", style: .plain, target: nil, action: nil)
        navigation.pushViewController(detail, animated: false)
        navigation.containerLayoutUpdated(containerLayout, transition: .immediate)
        let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
        func groups(_ view: UIView) -> [GlassControlGroup] {
            (view as? GlassControlGroup).map { [$0] } ?? view.subviews.flatMap(groups)
        }
        let outgoing = groups(bar.debugButtonLayer).filter { !$0.items.isEmpty }
        XCTAssertEqual(outgoing.count, 2)
        let originalFrames = outgoing.map { $0.convert($0.bounds, to: window) }
        navigation.popViewController(animated: true)
        let started = expectation(description: "Pop has begun dissolving both sides")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            navigation.containerLayoutUpdated(containerLayout, transition: .immediate)
            for (index, group) in outgoing.enumerated() {
                XCTAssertEqual(group.convert(group.bounds, to: window), originalFrames[index])
                var ancestor: UIView? = group
                while let current = ancestor {
                    if current !== group { XCTAssertFalse(current.isHidden); XCTAssertGreaterThan(current.layer.presentation()?.opacity ?? current.layer.opacity, 0.01) }
                    ancestor = current.superview
                }
                XCTAssertNotNil(group.superview)
                XCTAssertTrue(group.isFinishingContentRemoval)
                XCTAssertGreaterThan(group.bounds.width, 0)
            }
            started.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        let finished = expectation(description: "Exit owns cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for group in outgoing {
                XCTAssertFalse(group.isFinishingContentRemoval)
                XCTAssertEqual(group.bounds.size, .zero)
            }
            XCTAssertEqual(bar.debugButtonLayer.alpha, 0)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testInteractiveHiddenRootExitOutlivesScreenSettleAndCancelsOnPush() async throws {
        guard !UIAccessibility.isReduceMotionEnabled else { throw XCTSkip("Requires navigation animation") }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let data = NavigationBarPresentationData(theme: NavigationBarTheme(style: .glass))
        let root = AetherViewController(navigationBarPresentationData: data)
        root.displayNavigationBar = false
        let navigation = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        let layout = ContainerViewLayout(size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            additionalInsets: .zero, statusBarHeight: 47)
        navigation.containerLayoutUpdated(layout, transition: .immediate)
        let detail = AetherViewController(navigationBarPresentationData: data)
        detail.navigationBarItem.rightBarButtonItem = UIBarButtonItem(title: "Menu", style: .plain, target: nil, action: nil)
        navigation.pushViewController(detail, animated: false)
        navigation.containerLayoutUpdated(layout, transition: .immediate)
        let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
        let container = try XCTUnwrap(descendant(NavigationContainer.self, in: navigation.view))
        let frame = bar.debugButtonLayer.frame
        // Exercise the same callbacks as the gesture recognizer, including a
        // cancelled drag and a screen settle shorter than the chrome clock.
        container.navigationBarTransitionBegan?(.pop, detail, root, layout, true)
        container.navigationBarTransitionProgress?(0.45, .immediate)
        XCTAssertEqual(bar.debugButtonLayer.frame, frame)
        XCTAssertEqual(bar.debugButtonLayer.alpha, 1)
        container.navigationBarTransitionResolutionBegan?(false, .immediate)
        container.navigationBarTransitionEnded?(false)
        XCTAssertEqual(bar.debugButtonLayer.frame, frame)
        XCTAssertEqual(bar.debugButtonLayer.alpha, 1)
        container.navigationBarTransitionBegan?(.pop, detail, root, layout, true)
        container.navigationBarTransitionResolutionBegan?(true, .animated(duration: 0.05, curve: .easeInOut))
        container.navigationBarTransitionEnded?(true)
        XCTAssertEqual(bar.debugButtonLayer.frame, frame)
        XCTAssertEqual(bar.debugButtonLayer.alpha, 1)
        let retained = expectation(description: "Chrome survives the short screen settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(bar.debugButtonLayer.frame, frame)
            XCTAssertEqual(bar.debugButtonLayer.alpha, 1)
            // Re-entry cancels the old hidden-bar cleanup.
            bar.prepareButtonLayerVisibility(visible: true, transition: self.transition)
            bar.alpha = 1
            retained.fulfill()
        }
        await fulfillment(of: [retained], timeout: 2)
        let restored = expectation(description: "Stale exit cannot hide new chrome")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(bar.debugButtonLayer.alpha, 1)
            restored.fulfill()
        }
        await fulfillment(of: [restored], timeout: 2)
    }

    func testEmptyTargetRelayoutPreservesWholeButtonDisappearance() throws {
        let bar = makeBar()
        let source = NavigationBarItem()
        source.rightBarButtonItem = UIBarButtonItem(title: "A long menu button", style: .plain, target: nil, action: nil)
        bar.item = source
        layout(bar)
        let group = try XCTUnwrap(descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        let originalFrame = group.convert(group.bounds, to: bar.debugButtonLayer)
        let surface = try XCTUnwrap(descendant(GlassBackgroundView.self, in: group))
        let target = NavigationBarItem()
        bar.withButtonMorphTransition(transition) {
            bar.item = target
            layout(bar, transition: transition)
        }
        XCTAssertTrue(group.isFinishingContentRemoval)
        layout(bar)
        layout(bar)
        XCTAssertTrue(group.isFinishingContentRemoval)
        XCTAssertFalse(surface.isHidden, "An empty-target layout must not erase the outgoing material")
        XCTAssertEqual(group.convert(group.bounds, to: bar.debugButtonLayer), originalFrame)
        XCTAssertGreaterThan(surface.bounds.width, 44)
    }

    func testReinsertionRevealsRestingSurfaceWithoutZeroBoundsGrowth() throws {
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        let icon = try XCTUnwrap(UIImage(systemName: "line.3.horizontal.decrease"))
        let button = GlassControlGroup.Item(id: "filter", content: .icon(icon), action: {})
        _ = group.update(items: [button], transition: .immediate)
        _ = group.update(items: [], transition: .immediate)
        XCTAssertEqual(group.surfaceFrameForTesting, .zero)

        let size = group.update(items: [button], transition: transition)

        XCTAssertEqual(group.surfaceFrameForTesting, CGRect(origin: .zero, size: size))
        let reveal = try XCTUnwrap(group.surfaceMaterializationAnimationForTesting)
        XCTAssertEqual((reveal.values?.first as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual((reveal.values?.last as? NSNumber)?.doubleValue, 1)
        let backdrop = try XCTUnwrap(descendant(GlassBackgroundView.self, in: group))
        XCTAssertNil(backdrop.layer.animation(forKey: "bounds"))
        XCTAssertNotNil(group.itemButton(id: "filter"))
    }

    func testContentReplacementKeepsExistingSurfaceFullyVisible() throws {
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        _ = group.update(items: [.init(id: "old", content: .text("Edit"), action: {})], transition: .immediate)
        let backdrop = try XCTUnwrap(descendant(GlassBackgroundView.self, in: group))

        _ = group.update(items: [.init(id: "new", content: .text("Done"), action: {})], transition: transition)

        XCTAssertIdentical(backdrop, descendant(GlassBackgroundView.self, in: group))
        XCTAssertNil(group.surfaceMaterializationAnimationForTesting)
        XCTAssertEqual(backdrop.alpha, 1.0)
    }

    func testRightSurfaceInsertionStartsAtFinalScreenPosition() throws {
        let bar = makeBar()
        bar.item = NavigationBarItem()
        layout(bar)
        let target = NavigationBarItem()
        target.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "video"), style: .plain, target: nil, action: nil)

        bar.withButtonMorphTransition(transition) {
            bar.item = target
            layout(bar, transition: transition)
        }

        let group = try XCTUnwrap(descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        XCTAssertEqual(group.convert(group.bounds, to: bar.debugButtonLayer).maxX, 304.0, accuracy: 0.001)
        XCTAssertEqual(group.bounds.width, 44.0, accuracy: 0.001)
        var ancestor: UIView? = group
        while let view = ancestor, view !== bar.debugButtonLayer {
            for key in view.layer.animationKeys() ?? [] {
                let property = view.layer.animation(forKey: key) as? CAPropertyAnimation
                XCTAssertFalse(property?.keyPath?.hasPrefix("position") == true, "New material moved from a provisional measurement position")
                XCTAssertFalse(property?.keyPath?.hasPrefix("bounds") == true, "New material grew from empty bounds")
            }
            ancestor = view.superview
        }
    }

    func testNewBackBadgeHasRenderedTextureContentBeforeMaterialization() throws {
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        let content = NavigationAutomaticBackBadgeContentView(text: "165", chevron: try XCTUnwrap(UIImage(systemName: "chevron.left")))
        _ = group.update(items: [.init(id: "back", content: .customView(content), action: {})], transition: transition)

        let badge = try XCTUnwrap(descendant(NavigationBarBadgeView.self, in: content))
        let nodes = try XCTUnwrap(badge.contentNode.subnodes)
        XCTAssertEqual(nodes.count, 2)
        for node in nodes {
            XCTAssertGreaterThan(node.bounds.width, 0.0)
            XCTAssertGreaterThan(node.bounds.height, 0.0)
        }
        XCTAssertNotNil(nodes.last?.layer.contents, "The unread count must be drawable in the first blurred frame")
        let button = try XCTUnwrap(group.itemButton(id: "back"))
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: button), "Custom composite content uses one materialization image on every build")
    }

    func testOriginalColorImageSurvivesGeneratedNavigationButtonRendering() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 86, height: 86)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 86, height: 86))
        }.withRenderingMode(.alwaysOriginal)
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        _ = group.update(items: [.init(id: "avatar", content: .icon(image), action: {})], foregroundColor: .black, transition: .immediate)
        let content = try XCTUnwrap(group.itemView(id: "avatar"))
        let rendered = try XCTUnwrap(AetherContentMaterialization.captureContent(of: content))
        XCTAssertTrue(try containsRedPixel(rendered), "Explicit original-color avatars must not be flattened to the navigation tint")

        _ = group.update(items: [.init(id: "avatar", content: .icon(image.withRenderingMode(.alwaysTemplate)), action: {})], foregroundColor: .black, transition: .immediate)
        let templatedContent = try XCTUnwrap(group.itemView(id: "avatar"))
        XCTAssertFalse(templatedContent === content, "Changing rendering intent must replace the visual content")
        let templatedImage = try XCTUnwrap(AetherContentMaterialization.captureContent(of: templatedContent))
        XCTAssertFalse(try containsRedPixel(templatedImage), "Template images must keep the navigation tint")
    }

    func testRealPushCapturesViewDidLoadBadgeBeforeNavigationCompletes() async throws {
        guard !UIAccessibility.isReduceMotionEnabled else { throw XCTSkip("Requires navigation animation") }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let presentationData = NavigationBarPresentationData(theme: NavigationBarTheme(style: .glass))
        let root = AetherViewController(navigationBarPresentationData: presentationData)
        root.displayNavigationBar = false
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
        let navigation = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        navigation.loadViewIfNeeded()
        navigation.view.frame = window.bounds
        navigation.containerLayoutUpdated(ContainerViewLayout(size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            additionalInsets: .zero, statusBarHeight: 47), transition: .immediate)
        let detail = BadgeInViewDidLoadController(navigationBarPresentationData: presentationData)
        XCTAssertFalse(detail.isViewLoaded)

        navigation.pushViewController(detail, animated: true)

        let chromeStarted = expectation(description: "Actual push captures the populated badge")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            defer { chromeStarted.fulfill() }
            do {
                let bar = try XCTUnwrap(navigation.navigationBar as? NavigationBarImpl)
                XCTAssertIdentical(bar.item, detail.navigationBarItem)
                XCTAssertEqual(bar.item?.backButtonBadgeText, "165")
                let compound = try XCTUnwrap(descendant(NavigationAutomaticBackBadgeContentView.self, in: bar.debugButtonLayer))
                XCTAssertEqual(compound.badgeText, "165")
                let button = try XCTUnwrap(compound.superview)
                XCTAssertTrue(AetherContentMaterialization.isAnimating(view: button))
                let actualCapturedImage = try XCTUnwrap(AetherContentMaterialization.capturedImageForTesting(of: button))
                XCTAssertTrue(try containsRedPixel(actualCapturedImage), "Inspect the image captured at animation start, not a newly rendered image")
            } catch { XCTFail("Push chrome was not ready: \(error)") }
        }
        await fulfillment(of: [chromeStarted], timeout: 2)
    }

    func testBackBadgeRemainsOneSemanticItemAndCanBeRemovedImmediately() throws {
        let bar = makeBar()
        let item = NavigationBarItem()
        bar.previousItem = .item(NavigationBarItem())
        item.backButtonBadgeText = "161"
        bar.item = item
        layout(bar)
        let group = try XCTUnwrap(descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        let backID = try XCTUnwrap(group.items.first?.id)
        let badge = try XCTUnwrap(group.itemView(id: backID) as? NavigationAutomaticBackBadgeContentView)
        XCTAssertEqual(group.items.count, 1)
        XCTAssertEqual(badge.badgeText, "161")
        XCTAssertGreaterThan(group.bounds.width, 44.0)
        XCTAssertTrue(bar.hasPureAutomaticBackButtonGroup)

        item.backButtonBadgeText = nil
        layout(bar)

        XCTAssertIdentical(group, descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        XCTAssertEqual(group.items.first?.id, backID)
        XCTAssertEqual(group.bounds.width, 44.0, accuracy: 0.001)
        XCTAssertFalse(group.itemView(id: backID) is NavigationAutomaticBackBadgeContentView)
        XCTAssertNil(group.sizeMorphPulseAnimationForTesting)
        XCTAssertNil(group.surfaceMaterializationAnimationForTesting)
    }

    func testBackBadgeModelNormalizesEmptyTextAndNotifiesChanges() {
        let item = NavigationBarItem()
        var changes = 0
        item.chromeContentDidChange = { changes += 1 }
        item.backButtonBadgeText = ""
        item.backButtonBadgeText = "165"
        item.backButtonBadgeText = "165"
        item.backButtonBadgeText = ""
        XCTAssertNil(item.backButtonBadgeText)
        XCTAssertEqual(changes, 2)
    }

    func testBackBadgeTransitionOverrideExistsOnlyDuringNotification() {
        let item = NavigationBarItem()
        var animatedNotifications: [Bool] = []
        item.chromeContentDidChange = { [weak item] in
            animatedNotifications.append(item?.contentTransitionOverride?.isAnimated == true)
        }
        item.backButtonBadgeText = "161"
        item.setBackButtonBadgeText("165", transition: transition)
        XCTAssertEqual(animatedNotifications, [false, true])
        XCTAssertNil(item.contentTransitionOverride)
    }

    func testPublicBlurFallbackStartsAfterLayoutAndCancelsOnImmediateRemoval() throws {
        guard CALayer.blur() == nil else {
            throw XCTSkip("Public fallback is selected when the private filter is unavailable")
        }
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        let item = GlassControlGroup.Item(id: "filter", content: .text("Filter"), action: {})
        _ = group.update(items: [item], transition: transition)
        let button = try XCTUnwrap(group.itemButton(id: "filter"))
        XCTAssertGreaterThan(button.bounds.width, 0)
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: button))
        _ = group.update(items: [item], transition: .immediate)
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: button))

        _ = group.update(items: [], transition: .immediate)

        XCTAssertFalse(AetherContentMaterialization.isAnimating(view: button))
        XCTAssertNil(button.superview)
    }

    func testCustomToGeneratedHandoffPreservesPositionAndEventuallyCleansUp() async throws {
        let bar = makeBar()
        let custom = FixedNavigationControl(size: CGSize(width: 60, height: 44))
        let source = NavigationBarItem()
        source.rightBarButtonItem = UIBarButtonItem(customView: custom)
        bar.item = source
        layout(bar)
        let sourceFrame = custom.convert(custom.bounds, to: bar.debugButtonLayer)
        let target = NavigationBarItem()
        target.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .plain, target: nil, action: nil)

        bar.withButtonMorphTransition(transition) {
            bar.item = target
            layout(bar, transition: transition)
        }

        XCTAssertIdentical(custom.superview, bar.debugButtonLayer)
        XCTAssertEqual(custom.frame, sourceFrame)
        XCTAssertFalse(custom.isUserInteractionEnabled)
        XCTAssertNotNil(descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        layout(bar)
        XCTAssertIdentical(custom.superview, bar.debugButtonLayer)

        let settled = expectation(description: "Outgoing custom visual retires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertNil(custom.superview)
        XCTAssertTrue(custom.isUserInteractionEnabled)
    }

    func testGeneratedToCustomHandoffPreservesOutgoingSurface() throws {
        let bar = makeBar()
        let source = NavigationBarItem()
        source.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
        bar.item = source
        layout(bar)
        let group = try XCTUnwrap(descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        let sourceFrame = group.convert(group.bounds, to: bar.debugButtonLayer)
        let custom = FixedNavigationControl(size: CGSize(width: 52, height: 44))
        let target = NavigationBarItem()
        target.rightBarButtonItem = UIBarButtonItem(customView: custom)

        bar.withButtonMorphTransition(transition) {
            bar.item = target
            layout(bar, transition: transition)
        }

        XCTAssertIdentical(group.superview, bar.debugButtonLayer)
        XCTAssertEqual(group.frame, sourceFrame)
        XCTAssertFalse(group.isUserInteractionEnabled)
        XCTAssertTrue(custom.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(custom.isDescendant(of: group))
    }

    func testReusedCustomViewKeepsIncomingOwnershipAcrossHostingModes() throws {
        let bar = makeBar()
        let custom = FixedNavigationControl(size: CGSize(width: 44, height: 44))
        let item = NavigationBarItem()
        item.leftBarButtonItem = UIBarButtonItem(customView: custom)
        bar.item = item
        layout(bar)

        bar.withButtonMorphTransition(transition) {
            bar.previousItem = .item(NavigationBarItem())
            layout(bar, transition: transition)
        }

        let group = try XCTUnwrap(descendant(GlassControlGroup.self, in: bar.debugButtonLayer))
        XCTAssertTrue(custom.isDescendant(of: group))
        XCTAssertEqual(group.items.count, 2)
        XCTAssertEqual(custom.alpha, 1.0)
    }

    private func makeBar() -> NavigationBarImpl {
        let bar = NavigationBarImpl(presentationData: NavigationBarPresentationData(theme: NavigationBarTheme(style: .glass)))
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 104)
        return bar
    }

    private func layout(_ bar: NavigationBarImpl, transition: ContainedViewLayoutTransition = .immediate) {
        bar.updateLayout(size: CGSize(width: 320, height: 104), defaultHeight: 60, additionalTopHeight: 0,
                         additionalContentHeight: 0, additionalBackgroundHeight: 0, additionalCutout: nil,
                         leftInset: 0, rightInset: 0, appearsHidden: false, isLandscape: false, transition: transition)
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(type, in: child) { return result }
        }
        return nil
    }

    private func containsRedPixel(_ image: UIImage) throws -> Bool {
        let image = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 0, to: pixels.count, by: 4).contains { index in
            pixels[index] > 150 && pixels[index + 1] < 120 && pixels[index + 2] < 120 && pixels[index + 3] > 150
        }
    }
}

private final class FixedNavigationControl: UIView {
    private let size: CGSize

    init(size: CGSize) {
        self.size = size
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = .systemBlue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func sizeThatFits(_ size: CGSize) -> CGSize { self.size }
}

private final class BadgeInViewDidLoadController: AetherViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationBarItem.backButtonBadgeText = "165"
    }
}
