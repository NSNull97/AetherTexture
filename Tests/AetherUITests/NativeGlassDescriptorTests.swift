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
        func filterTypes(_ layer: CALayer) -> [String] {
            let here = (layer.filters ?? []).compactMap { filter -> String? in
                guard let filter = filter as? NSObject,
                      filter.responds(to: NSSelectorFromString("type")) else { return nil }
                return filter.value(forKey: "type") as? String
            }
            return here + (layer.sublayers ?? []).flatMap(filterTypes)
        }
        XCTAssertTrue(filterTypes(window.layer.superlayer ?? window.layer).contains("glassForeground"),
            "A descriptor flag alone does not prove native foreground refraction was installed")
        #endif
    }
}
