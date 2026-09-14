import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NativeGlassDescriptorTests: XCTestCase {
    func testRegularClearSwitchWithIdenticalTintUpdatesEffectOnce() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires native glass") }
        let glass = GlassBackgroundView(style: .regular, appearanceStyle: .liquidGlassV2)
        defer { glass.tearDownLiquidRenderer() }
        func update(_ clear: Bool) {
            glass.update(size: CGSize(width: 200, height: 80), cornerRadius: 24,
                isDark: false, tintColor: .init(kind: .custom(style: clear ? .clear : .default, color: .red)),
                isInteractive: false, isVisible: true, transition: .immediate)
        }
        update(false)
        let baseline = glass.nativeGlassEffectAssignmentCountForTesting
        update(true)
        XCTAssertEqual(glass.nativeGlassEffectAssignmentCountForTesting, baseline + 1)
        update(true)
        XCTAssertEqual(glass.nativeGlassEffectAssignmentCountForTesting, baseline + 1)
        update(false)
        XCTAssertEqual(glass.nativeGlassEffectAssignmentCountForTesting, baseline + 2)
    }

    func testNativeMenuLensingIsInstalledAndSafeBuildUsesFallback() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires native glass") }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        let surface = MenuGlassSurfaceView(isDark: false, appearanceStyle: .liquidGlassV2)
        surface.frame = CGRect(x: 50, y: 100, width: 255, height: 170)
        controller.view.addSubview(surface)
        surface.configureTransitionOptics(contentLensing: true, excludesShadow: true)
        surface.setSurfaceCornerRadius(27)
        surface.layoutIfNeeded()
        defer { surface.tearDownGlassEffect(); window.isHidden = true }
        #if APPSTORE_SAFE
        XCTAssertFalse(surface.usesNativeContentLensing)
        XCTAssertNil(NativeGlassDescriptorAdapter.applying(.init(contentLensing: true), to: UIGlassEffect(style: .regular)))
        #else
        let settled = expectation(description: "UIKit installed its material layers")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertTrue(surface.usesNativeContentLensing)
        func nativeFilters(_ layer: CALayer) -> [NSObject] {
            let here = (layer.filters ?? []).compactMap { $0 as? NSObject }.filter {
                $0.responds(to: NSSelectorFromString("type"))
            }
            return here + (layer.sublayers ?? []).flatMap(nativeFilters)
        }
        let filters = nativeFilters(window.layer.superlayer ?? window.layer)
        XCTAssertTrue(filters.contains { $0.value(forKey: "type") as? String == "glassForeground" },
            "A descriptor flag alone does not prove native foreground refraction was installed")
        let backgrounds = filters.filter { $0.value(forKey: "type") as? String == "glassBackground" }
        XCTAssertFalse(backgrounds.isEmpty)
        for background in backgrounds {
            let shadow = try XCTUnwrap(background.value(forKey: "inputShadowOpacity") as? NSNumber)
            XCTAssertEqual(shadow.doubleValue, 0, accuracy: 0.0001)
            // The ring-shadow input is present on 27, but absent on 26.
            if let ring = background.value(forKey: "inputRingShadowOpacity") as? NSNumber {
                XCTAssertEqual(ring.doubleValue, 0, accuracy: 0.0001)
            }
        }
        #endif
    }
}
