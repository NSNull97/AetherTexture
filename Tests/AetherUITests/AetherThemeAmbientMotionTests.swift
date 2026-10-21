import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherThemeAmbientMotionTests: XCTestCase {
    func testDetachedScenesDoNotRunAmbientAnimations() throws {
        for theme in [AetherThemePickerView.Theme.light, .dark] {
            let picker = AetherThemePickerView(theme: theme)
            picker.frame = CGRect(x: 0, y: 0, width: 320, height: 278)
            picker.layoutIfNeeded()

            let cloud = try XCTUnwrap(namedLayer("aether.theme.cloud", in: picker.layer))
            XCTAssertNil(cloud.animation(forKey: "aether.theme.cloudDrift"))
            for index in 0..<2 {
                let star = try XCTUnwrap(namedLayer("aether.theme.shootingStar.\(index)", in: picker.layer))
                XCTAssertNil(star.animation(forKey: "aether.theme.shootingStar"))
                XCTAssertEqual(star.opacity, 0)
            }
        }
    }

    func testDayCloudLoopsInTwoDirectionsWithoutRotatingOrRestartingOnPaletteRefresh() throws {
        try requireMotion()
        let (window, picker) = hostedPicker(theme: .light)
        defer { window.isHidden = true; picker.removeFromSuperview() }
        let cloud = try XCTUnwrap(namedLayer("aether.theme.cloud", in: picker.layer))
        let animation = try XCTUnwrap(cloud.animation(forKey: "aether.theme.cloudDrift") as? CAKeyframeAnimation)
        let points = try XCTUnwrap(animation.values as? [NSValue]).map(\.cgPointValue)

        XCTAssertEqual(points.first, points.last, "The cloud should loop without jumping at the end")
        XCTAssertGreaterThan((points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0), 10)
        XCTAssertGreaterThan((points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0), 2)
        XCTAssertTrue(CATransform3DIsIdentity(cloud.transform))
        XCTAssertGreaterThan(animation.duration, 10, "The cloud should drift gently")

        picker.setTheme(.system, animated: false)
        picker.setNeedsLayout()
        picker.layoutIfNeeded()

        let refreshed = try XCTUnwrap(cloud.animation(forKey: "aether.theme.cloudDrift"))
        XCTAssertEqual(refreshed.beginTime, animation.beginTime, "Refreshing the same daylight palette must retain the loop phase")
    }

    func testNightShootingStarsLeaveQuietIntervalsAndStopWhenDayReturns() throws {
        try requireMotion()
        let (window, picker) = hostedPicker(theme: .light)
        defer { window.isHidden = true; picker.removeFromSuperview() }
        let cloud = try XCTUnwrap(namedLayer("aether.theme.cloud", in: picker.layer))

        picker.setTheme(.dark, animated: true)

        XCTAssertNil(cloud.animation(forKey: "aether.theme.cloudDrift"))
        for index in 0..<2 {
            let star = try XCTUnwrap(namedLayer("aether.theme.shootingStar.\(index)", in: picker.layer))
            let group = try XCTUnwrap(star.animation(forKey: "aether.theme.shootingStar") as? CAAnimationGroup)
            let animations = try XCTUnwrap(group.animations)
            let travel = try XCTUnwrap(animations.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath == "position" })
            let fade = try XCTUnwrap(animations.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath == "opacity" })
            let times = try XCTUnwrap(travel.keyTimes)
            let points = try XCTUnwrap(travel.values as? [NSValue]).map(\.cgPointValue)
            let fadeValues = try XCTUnwrap(fade.values as? [NSNumber])
            XCTAssertGreaterThan(group.duration, 8)
            XCTAssertLessThan((times[2].doubleValue - times[1].doubleValue) * group.duration, 1)
            XCTAssertGreaterThan(points[2].x, points[1].x)
            XCTAssertGreaterThan(points[2].y, points[1].y)
            XCTAssertEqual(fadeValues.first?.doubleValue, 0)
            XCTAssertEqual(fadeValues.last?.doubleValue, 0)
            XCTAssertEqual(star.opacity, 0, "No static streak should remain between passes")
        }

        picker.setTheme(.light, animated: true)

        XCTAssertNotNil(cloud.animation(forKey: "aether.theme.cloudDrift"))
        for index in 0..<2 {
            let star = try XCTUnwrap(namedLayer("aether.theme.shootingStar.\(index)", in: picker.layer))
            XCTAssertNil(star.animation(forKey: "aether.theme.shootingStar"))
        }
    }

    func testAmbientMotionStopsInBackgroundAndWhenRemovedFromWindow() throws {
        try requireMotion()
        let (window, picker) = hostedPicker(theme: .dark)
        defer {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            window.isHidden = true
            picker.removeFromSuperview()
        }
        let star = try XCTUnwrap(namedLayer("aether.theme.shootingStar.0", in: picker.layer))
        XCTAssertNotNil(star.animation(forKey: "aether.theme.shootingStar"))

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(star.animation(forKey: "aether.theme.shootingStar"))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertNotNil(star.animation(forKey: "aether.theme.shootingStar"))

        picker.removeFromSuperview()
        XCTAssertNil(star.animation(forKey: "aether.theme.shootingStar"))
        picker.setTheme(.light, animated: false)
        let cloud = try XCTUnwrap(namedLayer("aether.theme.cloud", in: picker.layer))
        XCTAssertNil(cloud.animation(forKey: "aether.theme.cloudDrift"))
    }

    private func hostedPicker(theme: AetherThemePickerView.Theme) -> (UIWindow, AetherThemePickerView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.overrideUserInterfaceStyle = .light
        let controller = UIViewController()
        window.rootViewController = controller
        let picker = AetherThemePickerView(theme: theme)
        picker.frame = CGRect(x: 0, y: 0, width: 320, height: 278)
        controller.view.addSubview(picker)
        window.isHidden = false
        picker.layoutIfNeeded()
        return (window, picker)
    }

    private func requireMotion() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Ambient motion is intentionally disabled by Reduce Motion")
        }
    }

    private func namedLayer(_ name: String, in layer: CALayer) -> CALayer? {
        if layer.name == name { return layer }
        for child in layer.sublayers ?? [] {
            if let match = namedLayer(name, in: child) { return match }
        }
        return nil
    }
}
