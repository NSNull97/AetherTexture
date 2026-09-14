import XCTest
@testable import AetherUI

final class NavigationChromeTimingTests: XCTestCase {
    func testProductionPushChromeUsesFullScreenClockWithoutDelay() {
        let timing = AetherNavigationController.navigationChromeTransitionTiming(
            direction: .push,
            isInteractive: false
        )

        XCTAssertEqual(timing.duration, 0.34, accuracy: 0.001)
        XCTAssertEqual(timing.delay, 0.0, accuracy: 0.001)
        XCTAssertEqual(timing.delay + timing.duration, AetherMotion.navigation.duration, accuracy: 0.001)
    }

    func testProductionPopChromeUsesFullScreenClockWithoutDelay() {
        let timing = AetherNavigationController.navigationChromeTransitionTiming(
            direction: .pop,
            isInteractive: false
        )

        XCTAssertEqual(timing.delay, 0.0, accuracy: 0.001)
        XCTAssertEqual(timing.duration, AetherMotion.navigation.duration, accuracy: 0.001)
    }

    func testInteractivePopUsesFixedChromeClockWithoutDelay() {
        let timing = AetherNavigationController.navigationChromeTransitionTiming(
            direction: .pop,
            isInteractive: true
        )

        XCTAssertEqual(timing.duration, AetherMotion.navigationChrome.geometry.duration, accuracy: 0.001)
        XCTAssertEqual(timing.delay, 0.0, accuracy: 0.001)
    }
}
