import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherAppStoreSafeTests: XCTestCase {
    func testCompileTimePolicyMatchesRuntimeMarker() {
        #if APPSTORE_SAFE
        XCTAssertTrue(AetherPrivateRuntime.isAppStoreSafe)
        XCTAssertFalse(AetherPrivateRuntime.isEnabled)
        #else
        XCTAssertFalse(AetherPrivateRuntime.isAppStoreSafe)
        XCTAssertTrue(AetherPrivateRuntime.isEnabled)
        #endif
    }

    func testGlassBackendFollowsCompileTimePolicy() {
        let previous = AetherGlassConfig.current
        defer { AetherGlassConfig.current = previous }

        AetherGlassConfig.current = AetherGlassConfig(legacyBlurBackend: .experimentalGlass)
        let view = LegacyGlassBackdropView()

        XCTAssertFalse(view.hasBackdropLayer)
        // The experimental renderer uses public Metal + direct UIKit capture
        // in both build modes. Metal-unavailable environments keep a material.
        XCTAssertTrue(view.experimentalView != nil || view.subviews.contains { $0 is UIVisualEffectView })
    }

    func testSafeVariableBlurUsesPublicVisualEffectFallback() {
        #if APPSTORE_SAFE
        let view = VariableBlurView(maxBlurRadius: 18)
        view.update(
            size: CGSize(width: 200, height: 60),
            constantHeight: 20,
            isInverted: false,
            gradient: VariableBlurEffect.Gradient(
                height: 40,
                alpha: [1, 0],
                positions: [0, 1]
            ),
            transition: .immediate
        )

        XCTAssertTrue(view.subviews.contains { $0 is UIVisualEffectView })
        #endif
    }

    func testSafeSDFSelectsPublicMorphFallback() {
        #if APPSTORE_SAFE
        if #available(iOS 26.0, *) {
            XCTAssertNil(LensSDFFilter())
        }
        #endif
    }
}
