import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class LegacyTabBarVibrancyAndAccessoryGapTests: XCTestCase {
    func testInactiveLegacyItemsUseUIKitVibrancyAndSelectionMovesIt() {
        let tabBar = makeLegacyTabBar()
        tabBar.items = [
            AetherTabBarItem(
                title: "Home",
                image: UIImage(systemName: "house")
            ),
            AetherTabBarItem(
                title: "Library",
                image: UIImage(systemName: "music.note")
            )
        ]
        let search = SearchTabItem(image: UIImage(systemName: "magnifyingglass"))
        search.title = "Search"
        tabBar.setSearchItem(search)

        let expectsVibrancy = !UIAccessibility.isReduceTransparencyEnabled
        XCTAssertEqual(
            tabBar.legacyItemVibrancyStatesForTesting,
            [false, expectsVibrancy]
        )
        XCTAssertEqual(
            tabBar.legacySearchItemUsesVibrancyForTesting,
            expectsVibrancy
        )

        tabBar.selectedIndex = 1

        XCTAssertEqual(
            tabBar.legacyItemVibrancyStatesForTesting,
            [expectsVibrancy, false]
        )
        XCTAssertEqual(
            tabBar.legacySearchItemUsesVibrancyForTesting,
            expectsVibrancy
        )
    }

    func testLegacyAccessoryReservationKeepsFourPointMaterialGapOutsideCutout() throws {
        let tabBar = makeLegacyTabBar()
        let surfaceHeight = TabBarView.LegacyLayout.minimumAccessoryHeight
        let reservedHeight = surfaceHeight
            + TabBarView.LegacyLayout.accessoryBottomGap
        tabBar.bottomAccessoryReservedHeight = reservedHeight
        tabBar.layoutIfNeeded()

        XCTAssertEqual(TabBarView.LegacyLayout.accessoryBottomGap, 4.0)
        XCTAssertEqual(
            try XCTUnwrap(
                tabBar.legacyUnifiedBottomMaterialCutoutFrameForTesting
            ),
            CGRect(
                x: TabBarView.LegacyLayout.accessorySideInset,
                y: 0.0,
                width: tabBar.bounds.width
                    - TabBarView.LegacyLayout.accessorySideInset * 2.0,
                height: surfaceHeight
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(tabBar.legacyUnifiedBottomMaterialFrameForTesting),
            CGRect(
                x: 0.0,
                y: -reservedHeight,
                width: tabBar.bounds.width,
                height: tabBar.bounds.height + reservedHeight
            )
        )
    }

    private func makeLegacyTabBar() -> TabBarView {
        let tabBar = TabBarView(
            theme: TabBarView.Theme(
                appearanceStyle: .legacy,
                style: .legacy
            )
        )
        tabBar.frame = CGRect(x: 0.0, y: 0.0, width: 390.0, height: 83.0)
        return tabBar
    }
}
