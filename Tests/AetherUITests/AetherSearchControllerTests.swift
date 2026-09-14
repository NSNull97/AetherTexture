import XCTest
import UIKit
@testable import AetherUI

final class AetherSearchControllerTests: XCTestCase {
    @MainActor
    func testLocalLegacyNavSearchSeedsPillBeforeFirstRendererAllocation() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let owner = LocalLegacyBottomSearchController()
        let tabs = AetherTabBarController()
        tabs.setControllers([owner], selectedIndex: 0)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.loadViewIfNeeded()
        owner.loadViewIfNeeded()

        let search = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherSearchController()
        }
        XCTAssertFalse(search.hasAllocatedSearchBarForTesting)

        AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            owner.searchController = search
        }
        defer {
            owner.searchController = nil
            window.isHidden = true
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }

        if case .navBar = search.placement {
        } else {
            XCTFail("Search owner inside AetherTabBarController must use nav-bar placement")
        }
        XCTAssertTrue(search.hasAllocatedSearchBarForTesting)
        XCTAssertFalse(search.searchBar.pillView.usesAnyGlassRendererForTesting)
        XCTAssertNil(search.searchBar.pillView.legacyBlurStyleForTesting)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        XCTAssertFalse(search.searchBar.pillView.usesAnyGlassRendererForTesting)
        XCTAssertEqual(search.resolvedAppearanceStyleForTesting, .legacy)
    }

    @MainActor
    func testLocalLegacyBottomSearchNeverAllocatesLiquidEdgeEffect() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let owner = LocalLegacyBottomSearchController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.loadViewIfNeeded()
        owner.view.frame = window.bounds

        let search = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherSearchController()
        }
        search.prefersBottomPlacement = true
        AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            owner.searchController = search
        }
        defer {
            owner.searchController = nil
            window.isHidden = true
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }

        XCTAssertEqual(search.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertNil(search.bottomEdgeEffectForTesting)
        XCTAssertEqual(search.bottomEdgeEffectAllocationCountForTesting, 0)
        XCTAssertNil(search.bottomPillForTesting?.legacyBlurStyleForTesting)
        XCTAssertFalse(owner.view.subviews.contains { $0 is EdgeEffectView })

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        XCTAssertEqual(search.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertNil(search.bottomEdgeEffectForTesting)
        XCTAssertEqual(search.bottomEdgeEffectAllocationCountForTesting, 0)
    }

    @MainActor
    func testInheritedBottomSearchRecreatesEdgeEffectAcrossLiveGenerationChanges() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let owner = AetherViewController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.loadViewIfNeeded()
        owner.view.frame = window.bounds

        let search = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            AetherSearchController()
        }
        search.prefersBottomPlacement = true
        AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            owner.searchController = search
        }
        defer {
            owner.searchController = nil
            window.isHidden = true
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }

        var firstEdge: EdgeEffectView? = try XCTUnwrap(search.bottomEdgeEffectForTesting)
        let firstIdentity = ObjectIdentifier(try XCTUnwrap(firstEdge))
        XCTAssertTrue(firstEdge?.superview === owner.view)
        XCTAssertEqual(search.bottomEdgeEffectAllocationCountForTesting, 1)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)

        XCTAssertEqual(search.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertNil(search.bottomEdgeEffectForTesting)
        XCTAssertNil(firstEdge?.superview)
        firstEdge = nil
        XCTAssertEqual(search.bottomEdgeEffectAllocationCountForTesting, 1)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV2, animated: false)

        let recreatedEdge = try XCTUnwrap(search.bottomEdgeEffectForTesting)
        XCTAssertEqual(search.resolvedAppearanceStyleForTesting, .liquidGlassV2)
        XCTAssertTrue(recreatedEdge.superview === owner.view)
        XCTAssertNotEqual(ObjectIdentifier(recreatedEdge), firstIdentity)
        XCTAssertEqual(search.bottomEdgeEffectAllocationCountForTesting, 2)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)
        XCTAssertNil(search.bottomEdgeEffectForTesting)
        XCTAssertNil(recreatedEdge.superview)
        XCTAssertEqual(search.bottomEdgeEffectAllocationCountForTesting, 2)
    }

    @MainActor
    func testInstallingSearchInDarkAppearanceDoesNotPinSearchBarDark() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        window.overrideUserInterfaceStyle = .dark
        let owner = AetherViewController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.loadViewIfNeeded()

        let search = AetherSearchController()
        search.prefersBottomPlacement = false
        owner.searchController = search

        XCTAssertFalse(search.searchBar.isDark)
        XCTAssertNil(search.searchBar.pillView.isDarkOverride)
        window.isHidden = true
    }

    @MainActor
    func testBottomSearchGlassTracksLightDarkLightAppearanceChanges() throws {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        window.overrideUserInterfaceStyle = .light
        let owner = AetherViewController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.loadViewIfNeeded()
        owner.view.frame = window.bounds

        let search = AetherSearchController()
        search.prefersBottomPlacement = true
        owner.searchController = search
        search.layoutBottomPill(in: owner.view)

        let pill = try XCTUnwrap(bottomSearchPill(in: owner.view))
        XCTAssertEqual(pill.params?.isDark, false)

        window.overrideUserInterfaceStyle = .dark
        drainAppearanceUpdates(in: owner.view)
        XCTAssertEqual(pill.params?.isDark, true)

        window.overrideUserInterfaceStyle = .light
        drainAppearanceUpdates(in: owner.view)
        XCTAssertEqual(pill.params?.isDark, false)
        window.isHidden = true
    }

    @MainActor
    func testGlassControlGroupIconTracksLightDarkLightAppearanceChanges() throws {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 120.0, height: 120.0))
        window.overrideUserInterfaceStyle = .light
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()

        let group = GlassControlGroup()
        group.frame = CGRect(x: 20.0, y: 20.0, width: 44.0, height: 44.0)
        host.view.addSubview(group)
        let icon = try XCTUnwrap(UIImage(systemName: "gearshape"))
        group.update(
            items: [.init(id: "settings", content: .icon(icon), action: nil)],
            foregroundColor: .label,
            isDark: false,
            transition: .immediate
        )
        host.view.layoutIfNeeded()

        let content = try XCTUnwrap(group.itemView(id: "settings"))
        XCTAssertFalse(content.subviews.isEmpty)
        XCTAssertEqual(
            group.itemResolvedForegroundColorForTesting(id: "settings"),
            UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        )

        window.overrideUserInterfaceStyle = .dark
        drainAppearanceUpdates(in: host.view)
        XCTAssertEqual(
            group.itemResolvedForegroundColorForTesting(id: "settings"),
            UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        )

        window.overrideUserInterfaceStyle = .light
        drainAppearanceUpdates(in: host.view)
        XCTAssertEqual(
            group.itemResolvedForegroundColorForTesting(id: "settings"),
            UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        )
        window.isHidden = true
    }

    @MainActor
    func testBottomSearchActivationFocusesImmediatelyAndManagesResultsController() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let owner = AetherViewController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.loadViewIfNeeded()
        owner.view.frame = window.bounds

        let search = AetherSearchController()
        search.prefersBottomPlacement = true
        let results = SearchResultsFixtureController()
        search.searchResultsController = results
        owner.searchController = search

        search.activate()

        XCTAssertTrue(results.parent === owner)
        XCTAssertTrue(results.view.isDescendant(of: owner.view))
        XCTAssertEqual(results.receivedTexts.last, "")
        let textField = owner.view.firstDescendant(of: UITextField.self)
        XCTAssertNotNil(textField)
        XCTAssertTrue(textField?.isFirstResponder ?? false)
        let (responder, accessoryHeight) = getFirstResponderAndAccessoryHeight(owner.view)
        XCTAssertTrue(responder === textField)
        XCTAssertEqual(accessoryHeight, 50.0, "Gesture height includes the 42pt pill and its 8pt keyboard gap")

        search.deactivate()

        XCTAssertNil(results.parent)
        XCTAssertEqual(search.bottomPillForTesting?.contentView.input_getInputAccessoryHeight(), 0.0)
        window.isHidden = true
    }

    @MainActor
    func testBottomSearchUsesKeyboardTransitionForPillAndCloseButton() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let owner = LocalLegacyBottomSearchController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.view.frame = window.bounds
        let search = AetherSearchController()
        owner.searchController = search
        defer {
            search.deactivate()
            owner.searchController = nil
            window.isHidden = true
        }
        owner.containerLayoutUpdated(ContainerViewLayout(size: window.bounds.size), transition: .immediate)
        UIView.performWithoutAnimation { search.activate() }
        let pill = try XCTUnwrap(search.bottomPillForTesting)
        let close = try XCTUnwrap(owner.view.subviews.compactMap { $0 as? GlassBarButtonView }.first)
        pill.layer.removeAllAnimations()
        close.layer.removeAllAnimations()
        let startY = pill.frame.minY

        owner.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, inputHeight: 300),
            transition: .animated(duration: 0.4, curve: .easeInOut)
        )
        CATransaction.flush()

        XCTAssertEqual(pill.frame.minY, 494, accuracy: 0.01)
        XCTAssertLessThan(pill.frame.minY, startY)
        XCTAssertEqual(close.center.y, pill.center.y, accuracy: 0.01)
        XCTAssertEqual(close.bounds.size, CGSize(width: 42, height: 42))
        for control in [pill as UIView, close as UIView] {
            let animation = try XCTUnwrap(control.layer.animation(forKey: "position"))
            XCTAssertEqual(animation.duration, 0.4, accuracy: 0.01)
        }
    }

    @MainActor
    func testBottomSearchPreservesKeyboardHeightAcrossAppearanceAndInteractiveLayouts() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let owner = LocalLegacyBottomSearchController()
        window.rootViewController = owner
        window.makeKeyAndVisible()
        owner.view.frame = window.bounds
        let search = AetherSearchController()
        owner.searchController = search
        defer {
            search.deactivate()
            owner.searchController = nil
            window.isHidden = true
        }
        // Keyboard may already be visible when search acquires focus.
        owner.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, inputHeight: 300),
            transition: .immediate
        )
        UIView.performWithoutAnimation { search.activate() }
        let pill = try XCTUnwrap(search.bottomPillForTesting)
        XCTAssertEqual(pill.frame.minY, 494, accuracy: 0.01)
        search.appearanceDidChange(in: owner.view)
        XCTAssertEqual(pill.frame.minY, 494, accuracy: 0.01)

        pill.layer.removeAllAnimations()
        owner.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, inputHeight: 160, inputHeightIsInteractivellyChanging: true),
            transition: .immediate
        )
        XCTAssertEqual(pill.frame.minY, 634, accuracy: 0.01)
        XCTAssertNil(pill.layer.animation(forKey: "position"))
        search.appearanceDidChange(in: owner.view)
        XCTAssertEqual(pill.frame.minY, 634, accuracy: 0.01)

        owner.containerLayoutUpdated(ContainerViewLayout(size: window.bounds.size), transition: .immediate)
        search.appearanceDidChange(in: owner.view)
        XCTAssertEqual(pill.frame.minY, 844 - max(25, owner.view.safeAreaInsets.bottom + 8) - 42, accuracy: 0.01)
    }

    func testActiveSearchBarDoesNotFocusUntilExplicitlyActivated() {
        let searchBar = AetherActiveSearchBar()
        XCTAssertFalse(searchBar.activatesOnAppear)
    }

    func testBottomSearchPillKeepsGlassInteractionEnabled() throws {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let owner = AetherViewController()
        window.rootViewController = owner
        window.isHidden = false
        owner.loadViewIfNeeded()
        owner.view.frame = window.bounds

        let search = AetherSearchController()
        search.prefersBottomPlacement = true
        owner.searchController = search
        search.layoutBottomPill(in: owner.view)

        let pill = try XCTUnwrap(owner.view.subviews
            .compactMap { $0 as? GlassBackgroundView }
            .first { abs($0.bounds.height - 42.0) < 0.5 })
        XCTAssertEqual(pill.params?.isInteractive, true)

        search.activate()
        search.layoutBottomSearchActive(in: owner.view)
        let close = try XCTUnwrap(owner.view.subviews.compactMap { $0 as? GlassBarButtonView }.first)
        XCTAssertEqual(close.bounds.size, CGSize(width: 42.0, height: 42.0))

        window.isHidden = true
    }

    @MainActor
    private func bottomSearchPill(in view: UIView) -> GlassBackgroundView? {
        view.subviews
            .compactMap { $0 as? GlassBackgroundView }
            .first { abs($0.bounds.height - 42.0) < 0.5 }
    }

    @MainActor
    private func drainAppearanceUpdates(in view: UIView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
}

@MainActor
private final class LocalLegacyBottomSearchController: AetherViewController,
    AetherControllerAppearanceProviding {
    nonisolated func aetherAppearanceOverride(
        for context: AetherAppearanceOverrideContext
    ) -> AetherAppearanceOverride? {
        switch context.surface {
        case .search, .bottomSearch:
            break
        default:
            return nil
        }
        return AetherAppearanceOverride(appearanceStyle: .legacy)
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}

private final class SearchResultsFixtureController: AetherSearchContentController {
    private(set) var receivedTexts: [String] = []

    override func searchTextUpdated(text: String) {
        receivedTexts.append(text)
    }
}
