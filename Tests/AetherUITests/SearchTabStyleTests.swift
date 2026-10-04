import XCTest
import UIKit
import AsyncDisplayKit
@testable import AetherUI

@MainActor
final class SearchTabStyleTests: XCTestCase {
    private let appearances: [AetherAppearanceStyle] = [.liquidGlassV1, .liquidGlassV2]

    func testSearchStyleDefaultsToSeparate() {
        XCTAssertEqual(SearchTabItem().style, .separate)
    }

    func testSearchStyleSurvivesCoding() throws {
        for style in [SearchTabItem.Style.inside, .separate] {
            let item = SearchTabItem(style: style, image: nil)
            item.title = "Find"
            // UITabBarItem supports NSCoding, not NSSecureCoding.
            let data = try NSKeyedArchiver.archivedData(withRootObject: item, requiringSecureCoding: false)
            let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
            decoder.requiresSecureCoding = false
            let decoded = try XCTUnwrap(decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? SearchTabItem)
            decoder.finishDecoding()
            XCTAssertEqual(decoded.style, style)
            XCTAssertEqual(decoded.title, "Find")
        }
    }

    func testReloadInsideItemUpdatesSelectedContentWithoutReplacingMovingGlass() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .inside, appearance: appearance)
            defer { fixture.window.isHidden = true }
            fixture.tabs.activateSearch()
            let bar = try tabBar(in: fixture)
            let moving = try movingSearch(in: fixture)
            bar.updateTheme(TabBarView.Theme(
                appearanceStyle: appearance,
                tabBarIconColor: .gray,
                tabBarSelectedIconColor: .red,
                tabBarTextColor: .gray,
                tabBarSelectedTextColor: .red
            ))
            let normal = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
            }
            let selected = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            fixture.item.title = "Discover"
            fixture.item.badgeValue = "7"
            fixture.item.image = normal
            fixture.item.selectedImage = selected

            fixture.tabs.reloadTabBarItems()
            fixture.tabs.view.layoutIfNeeded()

            XCTAssertEqual(bar.selectedIndex, 1, "Reload must refresh content even when the selection did not change")
            XCTAssertTrue(moving === (try movingSearch(in: fixture)))
            XCTAssertEqual(moving.accessibilityLabel, "Discover")
            XCTAssertTrue(moving.accessibilityTraits.contains(.selected))
            let lens = try XCTUnwrap(descendants(in: bar).compactMap { $0 as? LiquidLensView }.first)
            for (container, expectedImage, expectedColor) in [
                (lens.contentView, normal, UIColor.gray),
                (lens.selectedContentView, selected, UIColor.red)
            ] {
                let itemView = try XCTUnwrap(container.subviews.first { $0.tag == 1 })
                let title = try XCTUnwrap(descendants(in: itemView).compactMap { ASViewToDisplayNode($0) as? ASTextNode }
                    .first { $0.attributedText?.string == "Discover" })
                let badge = try XCTUnwrap(descendants(in: itemView).compactMap { $0 as? NavigationBarBadgeView }.first)
                let icon = try XCTUnwrap(descendants(in: itemView).compactMap { ASViewToDisplayNode($0) as? ASImageNode }.first)
                XCTAssertFalse(itemView.isHidden)
                XCTAssertEqual(badge.text, "7")
                XCTAssertFalse(badge.isHidden)
                XCTAssertEqual(icon.image?.size, expectedImage.size)
                XCTAssertEqual(icon.alpha, 1.0, accuracy: 0.001)
                XCTAssertEqual(title.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, expectedColor)
            }
            let icon = try XCTUnwrap(descendants(in: moving).compactMap { ASViewToDisplayNode($0) as? ASImageNode }.first)
            XCTAssertEqual(icon.image?.size, selected.size)
            XCTAssertEqual(moving.contentTintColor, .red)

            bar.selectedIndex = 0
            bar.layoutIfNeeded()

            XCTAssertTrue(moving === (try movingSearch(in: fixture)))
            XCTAssertFalse(moving.accessibilityTraits.contains(.selected))
            XCTAssertEqual(icon.image?.size, normal.size)
            XCTAssertEqual(moving.contentTintColor, .gray)
        }
    }

    func testExpandedInsideSearchUsesTheSamePillPressSurfaceAsOtherTabs() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .inside, appearance: appearance)
            defer { fixture.window.isHidden = true }
            try assertInsideUsesPillSurface(fixture)

            fixture.tabs.activateSearch()
            fixture.tabs.view.layoutIfNeeded()
            try assertInsideUsesPillSurface(fixture)

            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            fixture.tabs.setTabBarMinimized(false, transition: .immediate)
            fixture.tabs.view.layoutIfNeeded()
            try assertInsideUsesPillSurface(fixture)
        }
    }

    func testInsideReturnsToPillAfterAnimatedMinimizeReversalAndAppearanceChange() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .inside, appearance: appearance)
            defer { fixture.window.isHidden = true }
            let moving = try movingSearch(in: fixture)
            fixture.tabs.setTabBarMinimized(true, transition: .animated(duration: 0.4, curve: .easeInOut))
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            fixture.tabs.setTabBarMinimized(false, transition: .animated(duration: 0.4, curve: .easeInOut))
            fixture.tabs.updateAppearance(AetherAppearance(
                style: appearance == .liquidGlassV1 ? .liquidGlassV2 : .liquidGlassV1
            ))
            RunLoop.main.run(until: Date().addingTimeInterval(0.65))
            fixture.tabs.view.layoutIfNeeded()

            XCTAssertTrue(moving === (try movingSearch(in: fixture)))
            try assertInsideUsesPillSurface(fixture)

            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            let bar = try tabBar(in: fixture)
            let point = moving.convert(CGPoint(x: moving.bounds.midX, y: moving.bounds.midY), to: bar)
            let hit = try XCTUnwrap(bar.hitTest(point, with: nil))
            XCTAssertTrue(hit.isDescendant(of: moving))
            XCTAssertTrue(moving.isUserInteractionEnabled)
            XCTAssertFalse(moving.accessibilityElementsHidden)
            try XCTUnwrap(moving.action)(moving)
            XCTAssertTrue(fixture.tabs.currentController === fixture.searchTab)
        }
    }

    func testMinimizedInsideSearchReturnsToLastOrdinaryTabAfterReloadAndReorder() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .inside, appearance: appearance, wrapSearch: true)
            defer { fixture.window.isHidden = true }
            let normal = UIGraphicsImageRenderer(size: CGSize(width: 13, height: 13)).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 13, height: 13))
            }
            let selected = UIGraphicsImageRenderer(size: CGSize(width: 25, height: 25)).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 25, height: 25))
            }
            fixture.library.tabBarItem.image = normal
            fixture.library.tabBarItem.selectedImage = selected
            fixture.tabs.reloadTabBarItems()
            fixture.tabs.selectedIndex = 2
            fixture.tabs.activateSearch()
            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            let bar = try tabBar(in: fixture)
            XCTAssertEqual(bar.minimizedPrimaryIndex, 2)
            XCTAssertEqual(try minimizedPrimaryIcon(in: fixture).image?.size, normal.size)

            fixture.tabs.reloadTabBarItems()
            XCTAssertEqual(bar.minimizedPrimaryIndex, 2)
            fixture.tabs.setControllers([fixture.library, fixture.searchTab, fixture.home], selectedIndex: 1)
            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            XCTAssertEqual(bar.minimizedPrimaryIndex, 0, "The primary target must follow controller identity after reorder")
            XCTAssertEqual(try minimizedPrimaryIcon(in: fixture).image?.size, normal.size)

            bar.simulateMinimizedActiveTabTapForTests()

            XCTAssertTrue(fixture.tabs.currentController === fixture.library)
            XCTAssertEqual(fixture.tabs.selectedIndex, 0)
            XCTAssertEqual(try minimizedPrimaryIcon(in: fixture).image?.size, selected.size)
            fixture.item.style = .separate
            fixture.item.style = .inside
            fixture.tabs.activateSearch()
            XCTAssertEqual(bar.minimizedPrimaryIndex, 0)
        }
    }

    func testMinimizedInsideUsesFirstOrdinaryTabWhenThereIsNoPreviousTarget() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .inside, appearance: appearance, initialSelectedIndex: 1)
            defer { fixture.window.isHidden = true }
            let bar = try tabBar(in: fixture)
            XCTAssertNil(bar.minimizedPrimaryIndex, "Starting on Search must not invent a previous ordinary selection")
            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            XCTAssertEqual(try minimizedPrimaryIcon(in: fixture).image?.size, fixture.home.tabBarItem.image?.size)
            bar.simulateMinimizedActiveTabTapForTests()
            XCTAssertTrue(fixture.tabs.currentController === fixture.home)

            fixture.tabs.selectedIndex = 2
            fixture.tabs.activateSearch()
            fixture.tabs.setControllers([fixture.searchTab, fixture.home], selectedIndex: 0)
            fixture.tabs.setTabBarMinimized(true, transition: .immediate)
            XCTAssertNil(bar.minimizedPrimaryIndex, "A removed previous tab must not leave a stale target index")
            XCTAssertEqual(try minimizedPrimaryIcon(in: fixture).image?.size, fixture.home.tabBarItem.image?.size)
            bar.simulateMinimizedActiveTabTapForTests()
            XCTAssertTrue(fixture.tabs.currentController === fixture.home)
            XCTAssertEqual(fixture.tabs.selectedIndex, 1)
        }
    }

    func testSearchGeometryAndGlassFollowItemStyleAcrossLiquidGenerations() throws {
        for appearance in appearances {
            for style in [SearchTabItem.Style.inside, .separate] {
                let fixture = makeFixture(style: style, appearance: appearance)
                defer { fixture.window.isHidden = true }
                let bar = try tabBar(in: fixture)
                let moving = try movingSearch(in: fixture)
                try assertExpandedGeometry(style: style, fixture: fixture)
                try assertMatchingGlass(moving, fixture: fixture)

                fixture.tabs.setTabBarMinimized(true, transition: .immediate)
                fixture.tabs.view.layoutIfNeeded()

                XCTAssertTrue(moving === (try movingSearch(in: fixture)))
                let pill = try XCTUnwrap(fixture.tabs.pillFrame(in: fixture.tabs.view))
                let compact = moving.convert(moving.bounds, to: fixture.tabs.view)
                XCTAssertGreaterThan(compact.minX, pill.maxX)
                XCTAssertEqual(compact.width, TabBarView.minimizedButtonSize, accuracy: 0.01)
                XCTAssertEqual(compact.height, TabBarView.minimizedButtonSize, accuracy: 0.01)
                XCTAssertEqual(moving.chromeMorphMaterialAlpha, 1.0, accuracy: 0.001)
                XCTAssertEqual(moving.chromeMorphContentAlpha, 1.0, accuracy: 0.001)
                XCTAssertTrue(moving.isUserInteractionEnabled)
                XCTAssertFalse(moving.accessibilityElementsHidden)
                XCTAssertFalse(bar.isSearchActive)
                try assertMatchingGlass(moving, fixture: fixture)

                fixture.tabs.setTabBarMinimized(false, transition: .immediate)
                fixture.tabs.updateAppearance(AetherAppearance(
                    style: appearance == .liquidGlassV1 ? .liquidGlassV2 : .liquidGlassV1
                ))
                fixture.tabs.view.layoutIfNeeded()
                XCTAssertEqual(fixture.item.style, style)
                try assertExpandedGeometry(style: style, fixture: fixture)
                try assertMatchingGlass(try movingSearch(in: fixture), fixture: fixture)
            }
        }
    }

    func testInsideActivationSelectsOriginalSlotAndCreatesNavSearchWithoutFocus() throws {
        for appearance in appearances {
            for wrapped in [false, true] {
                let fixture = makeFixture(style: .inside, appearance: appearance, wrapSearch: wrapped)
                defer { fixture.window.isHidden = true }
                let bar = try tabBar(in: fixture)
                XCTAssertEqual(fixture.tabs.controllers.count, 3)
                XCTAssertTrue(fixture.tabs.controllers[1] === fixture.searchTab)
                XCTAssertEqual(bar.items.count, 3)
                XCTAssertEqual(bar.items[1].title, "Find")
                fixture.tabs.activateSearch()
                fixture.tabs.view.layoutIfNeeded()

                XCTAssertEqual(fixture.tabs.selectedIndex, 1)
                XCTAssertEqual(bar.selectedIndex, 1)
                XCTAssertTrue(fixture.tabs.currentController === fixture.searchTab)
                XCTAssertFalse(bar.isSearchActive)
                XCTAssertFalse(fixture.tabs.isTabBarMinimized)
                let search = try XCTUnwrap(fixture.searchOwner.searchController)
                try assertNavSearch(search, owner: fixture.searchOwner)
                XCTAssertFalse(descendants(in: fixture.tabs.view).compactMap { $0 as? UITextField }
                    .contains(where: { $0.isFirstResponder }))

                let frame = try XCTUnwrap(bar.frameForTab(at: 1))
                let lens = try XCTUnwrap(descendants(in: bar).compactMap { $0 as? LiquidLensView }.first)
                let selection = CGRect(
                    origin: try XCTUnwrap(lens.selectionOrigin),
                    size: try XCTUnwrap(lens.selectionSize)
                )
                XCTAssertEqual(lens.convert(selection, to: bar).midX, frame.midX, accuracy: 0.01)

                fixture.tabs.selectedIndex = 0
                fixture.tabs.setTabBarMinimized(true, transition: .immediate)
                let moving = try movingSearch(in: fixture)
                try XCTUnwrap(moving.action)(moving)
                XCTAssertTrue(fixture.tabs.currentController === fixture.searchTab)
                XCTAssertEqual(fixture.tabs.selectedIndex, 1)
                XCTAssertFalse(bar.isSearchActive, "The detached inside control still selects a normal tab")
            }
        }
    }

    func testInsidePreservesExistingSearchAndOverridesBottomPreference() throws {
        for appearance in appearances {
            let existing = AetherSearchController()
            existing.prefersBottomPlacement = true
            let fixture = makeFixture(style: .inside, appearance: appearance, existingSearch: existing)
            defer { fixture.window.isHidden = true }

            fixture.tabs.activateSearch()
            fixture.tabs.view.layoutIfNeeded()

            XCTAssertTrue(fixture.searchOwner.searchController === existing)
            XCTAssertTrue(existing.prefersBottomPlacement)
            try assertNavSearch(existing, owner: fixture.searchOwner)
            XCTAssertFalse(try tabBar(in: fixture).isSearchActive)
        }
    }

    func testLeavingInsideStyleDeactivatesAndPreservesCallerOwnedNavSearch() throws {
        for appearance in appearances {
            let search = AetherSearchController()
            search.prefersBottomPlacement = false
            let delegate = SearchActivationRecorder()
            search.delegate = delegate
            let fixture = makeFixture(style: .inside, appearance: appearance, existingSearch: search)
            defer { fixture.window.isHidden = true }
            fixture.tabs.activateSearch()
            search.activate()
            XCTAssertTrue(search.isActive)

            fixture.item.style = .separate

            XCTAssertTrue(fixture.searchOwner.searchController === search)
            XCTAssertTrue(search.delegate === delegate)
            XCTAssertFalse(search.isActive, "Leaving inside must end active search even when its preferred placement stays navbar")
            XCTAssertTrue(descendants(in: search.searchBar).compactMap { $0 as? UITextField }.isEmpty)
            guard case .navBar = search.placement else {
                return XCTFail("Caller-owned navbar placement must be preserved")
            }
        }
    }

    func testRevisitingInsideNavigationTabKeepsSearchOnItsRootInsteadOfPushedDetail() throws {
        for appearance in appearances {
            for markerOnWrapper in [false, true] {
                let fixture = makeFixture(style: .inside, appearance: appearance, wrapSearch: true)
                defer { fixture.window.isHidden = true }
                let navigation = try XCTUnwrap(fixture.searchTab as? AetherNavigationController)
                if markerOnWrapper {
                    fixture.searchOwner.tabBarItem = UITabBarItem()
                    navigation.tabBarItem = fixture.item
                    fixture.tabs.setControllers([fixture.home, navigation, fixture.library], selectedIndex: 0)
                }
                fixture.tabs.activateSearch()
                let search = try XCTUnwrap(fixture.searchOwner.searchController)
                let detail = AetherViewController()
                navigation.pushViewController(detail, animated: false)

                fixture.tabs.selectedIndex = 0
                fixture.tabs.activateSearch()

                XCTAssertTrue(fixture.tabs.currentController === navigation)
                XCTAssertTrue(navigation.topController === detail)
                XCTAssertTrue(fixture.searchOwner.searchController === search)
                XCTAssertNil(detail.searchController, "Returning to a search tab must not install search on its current detail")
            }
        }
    }

    func testSeparateActivationKeepsOverlayMorphAndUnderlyingSelection() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .separate, appearance: appearance)
            defer { fixture.window.isHidden = true }
            let bar = try tabBar(in: fixture)
            XCTAssertEqual(fixture.tabs.controllers.count, 2)
            XCTAssertFalse(fixture.tabs.controllers.contains { $0 === fixture.searchTab })

            fixture.tabs.activateSearch()

            XCTAssertTrue(bar.isSearchActive)
            XCTAssertTrue(fixture.tabs.isTabBarMinimized)
            XCTAssertTrue(fixture.tabs.currentController === fixture.home)
            XCTAssertEqual(fixture.tabs.selectedIndex, 0)
            XCTAssertTrue(fixture.searchOwner.parent === fixture.tabs)
            XCTAssertEqual(fixture.searchOwner.activationCount, 1)
            XCTAssertFalse(descendants(in: fixture.tabs.view).compactMap { $0 as? UITextField }
                .contains(where: { $0.isFirstResponder }))

            // The minimize completion runs after activation hides the moving
            // control; it must not reveal the old search glyph behind Close.
            RunLoop.main.run(until: Date().addingTimeInterval(0.75))
            let moving = try movingSearch(in: fixture)
            XCTAssertEqual(moving.alpha, 0.0, accuracy: 0.001)
            XCTAssertTrue(moving.accessibilityElementsHidden)
            XCTAssertFalse(moving.isUserInteractionEnabled)
            let close = try XCTUnwrap(descendants(in: bar).first {
                $0.accessibilityIdentifier == "aether.search.close"
            })
            XCTAssertFalse(close.isHidden)
            XCTAssertGreaterThan(close.alpha, 0.99)

            fixture.tabs.deactivateSearch()
            XCTAssertFalse(bar.isSearchActive)
            XCTAssertEqual(fixture.searchOwner.deactivationCount, 1)
        }
    }

    func testRuntimeStyleChangesRetireActiveSearchAndPreserveOriginalControllerOrder() throws {
        for appearance in appearances {
            let fixture = makeFixture(style: .separate, appearance: appearance)
            defer { fixture.window.isHidden = true }
            fixture.tabs.activateSearch()
            XCTAssertTrue(try tabBar(in: fixture).isSearchActive)

            fixture.item.style = .inside
            fixture.tabs.view.layoutIfNeeded()

            XCTAssertFalse(try tabBar(in: fixture).isSearchActive)
            XCTAssertEqual(fixture.searchOwner.deactivationCount, 1)
            XCTAssertEqual(fixture.tabs.controllers.count, 3)
            XCTAssertTrue(fixture.tabs.controllers[0] === fixture.home)
            XCTAssertTrue(fixture.tabs.controllers[1] === fixture.searchTab)
            XCTAssertTrue(fixture.tabs.controllers[2] === fixture.library)
            XCTAssertTrue(fixture.tabs.currentController === fixture.home)
            try assertExpandedGeometry(style: .inside, fixture: fixture)

            fixture.tabs.activateSearch()
            XCTAssertTrue(fixture.tabs.currentController === fixture.searchTab)
            fixture.item.style = .separate
            fixture.tabs.view.layoutIfNeeded()

            XCTAssertEqual(fixture.tabs.controllers.count, 2)
            XCTAssertFalse(fixture.tabs.controllers.contains { $0 === fixture.searchTab })
            XCTAssertFalse(fixture.tabs.currentController === fixture.searchTab)
            XCTAssertFalse(try tabBar(in: fixture).isSearchActive)
            fixture.tabs.setControllers(fixture.tabs.controllers, selectedIndex: fixture.tabs.selectedIndex)
            XCTAssertNotNil(try movingSearch(in: fixture))

            fixture.tabs.setControllers([], selectedIndex: nil)
            fixture.item.style = .inside
            XCTAssertTrue(fixture.tabs.controllers.isEmpty, "Retired items must not rebuild the previous tab tree")
            XCTAssertNil(descendants(in: fixture.tabs.view).first {
                $0.accessibilityIdentifier == "aether.tabbar.search.moving"
            })
        }
    }

    func testChangingInsideToSeparateCancelsActiveNavSearchAndItsDelayedCompletion() async throws {
        guard UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Requires an in-flight navbar search animation")
        }
        for appearance in appearances {
            let fixture = makeFixture(style: .inside, appearance: appearance)
            defer { fixture.window.isHidden = true }
            fixture.tabs.activateSearch()
            let search = try XCTUnwrap(fixture.searchOwner.searchController)
            let delegate = SearchActivationRecorder()
            search.delegate = delegate
            search.activate()
            XCTAssertTrue(search.isActive)
            XCTAssertEqual(delegate.willActivateCount, 1)
            XCTAssertFalse(descendants(in: search.searchBar).compactMap { $0 as? UITextField }.isEmpty)
            let close = try XCTUnwrap(search.searchBar.superview?.subviews.compactMap {
                $0 as? GlassBarButtonView
            }.first)

            fixture.item.style = .separate

            XCTAssertNil(fixture.searchOwner.searchController)
            XCTAssertFalse(search.isActive)
            XCTAssertTrue(descendants(in: search.searchBar).compactMap { $0 as? UITextField }.isEmpty)
            XCTAssertNil(close.superview)
            XCTAssertEqual(search.searchBar.rightExtraInset, 0)
            XCTAssertFalse(try tabBar(in: fixture).isSearchActive)

            // Reusing the retained auto-created search outside the tab tree
            // must resolve placement anew, without the former inside override.
            let standalone = AetherViewController()
            let standaloneWindow = UIWindow(frame: fixture.window.bounds)
            standaloneWindow.rootViewController = standalone
            standaloneWindow.isHidden = false
            defer { standaloneWindow.isHidden = true }
            standalone.loadViewIfNeeded()
            standalone.view.frame = standaloneWindow.bounds
            standalone.searchController = search
            guard case .bottom = search.placement else {
                XCTFail("The inside placement override survived uninstall")
                continue
            }
            XCTAssertNotNil(search.bottomPillForTesting)

            let settled = expectation(description: "Retired navbar search animations settled")
            let delay = max(AetherMotion.search.presentation.duration, AetherMotion.search.dismissal.duration) + 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { settled.fulfill() }
            await fulfillment(of: [settled], timeout: delay + 1.0)

            XCTAssertEqual(delegate.didActivateCount, 0, "A retired activation must not notify the reused search")
            XCTAssertFalse(search.isActive)
            XCTAssertNil(close.superview)
            XCTAssertTrue(descendants(in: search.searchBar).compactMap { $0 as? UITextField }.isEmpty)
            XCTAssertTrue(descendants(in: standalone.view).compactMap { $0 as? UITextField }.isEmpty)
            XCTAssertTrue(search.bottomPillForTesting?.superview === standalone.view)
        }
    }

    private struct Fixture {
        let window: UIWindow
        let tabs: AetherTabBarController
        let home: AetherViewController
        let library: AetherViewController
        let searchOwner: StyleSearchOwner
        let searchTab: UIViewController
        let item: SearchTabItem
    }

    private func makeFixture(
        style: SearchTabItem.Style,
        appearance: AetherAppearanceStyle,
        wrapSearch: Bool = false,
        existingSearch: AetherSearchController? = nil,
        initialSelectedIndex: Int = 0
    ) -> Fixture {
        let appearance = AetherAppearance(style: appearance)
        let data = AetherAppearance.withRuntimeCurrent(appearance) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let home = AetherViewController(navigationBarPresentationData: data)
        home.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)
        let library = AetherViewController(navigationBarPresentationData: data)
        library.tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "books.vertical"), tag: 2)
        let owner = StyleSearchOwner(navigationBarPresentationData: data)
        owner.searchController = existingSearch
        let item = SearchTabItem(style: style, image: UIImage(systemName: "magnifyingglass"))
        item.title = "Find"
        owner.tabBarItem = item
        let searchTab: UIViewController = wrapSearch
            ? AetherNavigationController(rootViewController: owner) : owner
        let tabs = AetherAppearance.withRuntimeCurrent(appearance) { AetherTabBarController() }
        tabs.setControllers([home, searchTab, library], selectedIndex: initialSelectedIndex)
        tabs.updateAppearance(appearance)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.isHidden = false
        tabs.loadViewIfNeeded()
        tabs.view.frame = window.bounds
        tabs.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )
        tabs.view.layoutIfNeeded()
        return Fixture(window: window, tabs: tabs, home: home, library: library,
                       searchOwner: owner, searchTab: searchTab, item: item)
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(in: $0) }
    }

    private func tabBar(in fixture: Fixture) throws -> TabBarView {
        try XCTUnwrap(descendants(in: fixture.tabs.view).compactMap { $0 as? TabBarView }.first)
    }

    private func movingSearch(in fixture: Fixture) throws -> GlassBarButtonView {
        try XCTUnwrap(descendants(in: fixture.tabs.view).first {
            $0.accessibilityIdentifier == "aether.tabbar.search.moving"
        } as? GlassBarButtonView)
    }

    private func minimizedPrimaryIcon(in fixture: Fixture) throws -> ASImageNode {
        let bar = try tabBar(in: fixture)
        let lens = try XCTUnwrap(descendants(in: bar).compactMap { $0 as? LiquidLensView }.first)
        return try XCTUnwrap(lens.superview?.subviews.compactMap { ASViewToDisplayNode($0) as? ASImageNode }.first)
    }

    private func assertInsideUsesPillSurface(_ fixture: Fixture) throws {
        let bar = try tabBar(in: fixture)
        let moving = try movingSearch(in: fixture)
        let lens = try XCTUnwrap(descendants(in: bar).compactMap { $0 as? LiquidLensView }.first)
        XCTAssertFalse(moving.isUserInteractionEnabled)
        XCTAssertTrue(moving.accessibilityElementsHidden)
        XCTAssertEqual(moving.chromeMorphMaterialAlpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(moving.chromeMorphContentAlpha, 0.0, accuracy: 0.001)
        for index in [0, 1] {
            let slot = try XCTUnwrap(bar.frameForTab(at: index))
            let hit = try XCTUnwrap(bar.hitTest(CGPoint(x: slot.midX, y: slot.midY), with: nil))
            XCTAssertTrue(hit.isDescendant(of: lens), "Every expanded slot must deliver press to the shared pill surface")
            XCTAssertFalse(hit.isDescendant(of: moving))
        }
        for container in [lens.contentView, lens.selectedContentView] {
            let item = try XCTUnwrap(container.subviews.first { $0.tag == 1 })
            XCTAssertFalse(item.isHidden)
            XCTAssertEqual(item.alpha, 1.0, accuracy: 0.001)
            let icon = try XCTUnwrap(descendants(in: item).compactMap { ASViewToDisplayNode($0) as? ASImageNode }.first)
            let title = try XCTUnwrap(descendants(in: item).compactMap { ASViewToDisplayNode($0) as? ASTextNode }
                .first { $0.attributedText?.string == fixture.item.title })
            XCTAssertEqual(icon.alpha, 1.0, accuracy: 0.001)
            XCTAssertEqual(title.alpha, 1.0, accuracy: 0.001)
        }
    }

    private func assertExpandedGeometry(style: SearchTabItem.Style, fixture: Fixture) throws {
        let bar = try tabBar(in: fixture)
        let moving = try movingSearch(in: fixture)
        let pill = try XCTUnwrap(fixture.tabs.pillFrame(in: fixture.tabs.view))
        let frame = moving.convert(moving.bounds, to: fixture.tabs.view)
        if style == .inside {
            XCTAssertEqual(bar.items.count, 3, "Inside occupies one real tab slot, not an extra fourth slot")
            XCTAssertGreaterThanOrEqual(frame.minX, pill.minX)
            XCTAssertLessThanOrEqual(frame.maxX, pill.maxX)
            let slot = try XCTUnwrap(bar.frameForTab(at: 1))
            XCTAssertEqual(frame.midX, bar.convert(slot, to: fixture.tabs.view).midX, accuracy: 0.01)
        } else {
            XCTAssertEqual(bar.items.count, 2)
            XCTAssertGreaterThan(frame.minX, pill.maxX)
            XCTAssertEqual(frame.width, frame.height, accuracy: 0.01)
        }
    }

    private func assertMatchingGlass(_ moving: GlassBarButtonView, fixture: Fixture) throws {
        let lens = try XCTUnwrap(descendants(in: fixture.tabs.view).compactMap { $0 as? LiquidLensView }.first)
        XCTAssertEqual(moving.glassStyle, lens.glassStyle)
        XCTAssertEqual(moving.glassTintColor, lens.glassTintColor)
        XCTAssertEqual(moving.isDarkAppearance, lens.isDarkAppearance)
    }

    private func assertNavSearch(_ search: AetherSearchController, owner: AetherViewController) throws {
        guard case .navBar = search.placement else {
            return XCTFail("Inside search must use the owner's navbar")
        }
        let bar = try XCTUnwrap(owner.navigationBarView)
        XCTAssertTrue(search.searchBar.isDescendant(of: bar))
        XCTAssertFalse(search.isActive)
    }
}

@MainActor
private final class StyleSearchOwner: AetherViewController {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    override func tabBarActivateSearch() { activationCount += 1 }
    override func tabBarDeactivateSearch() { deactivationCount += 1 }
}

private final class SearchActivationRecorder: AetherSearchControllerDelegate {
    private(set) var willActivateCount = 0
    private(set) var didActivateCount = 0

    func searchControllerWillActivate(_ controller: AetherSearchController) { willActivateCount += 1 }
    func searchControllerDidActivate(_ controller: AetherSearchController) { didActivateCount += 1 }
}
