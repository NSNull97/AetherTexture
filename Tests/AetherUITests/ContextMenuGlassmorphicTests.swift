import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class ContextMenuGlassmorphicTests: XCTestCase {
    func testAppearanceSelectsInternalRouteAndBothRoutesLeaseTheSource() {
        for appearance in AetherAppearanceStyle.allCases {
            let fixture = makeFixture()
            defer { fixture.window.isHidden = true }
            let menu = makeMenu(source: fixture.source, appearance: appearance)
            menu.present()

            XCTAssertTrue(menu.isPresentedForTesting)
            XCTAssertEqual(menu.resolvedAppearanceStyleForTesting, appearance)
            XCTAssertEqual(menu.resolvedPresentationStyleForTesting, appearance == .legacy ? .legacy : .glassmorphic)
            XCTAssertTrue(menu.hasGlassmorphicTransitionForTesting)
            XCTAssertTrue(menu.usesSourcePresentationLeaseForTesting)
            XCTAssertEqual(fixture.source.alpha, 0, accuracy: 0.001)
            XCTAssertFalse(fixture.source.isUserInteractionEnabled)
            if appearance == .legacy {
                XCTAssertTrue(menu.menuUsesLegacySurfaceForTesting)
                XCTAssertFalse(menu.hasLiquidTransitionResourcesForTesting)
            }

            menu.dismiss(animated: false)
            assertRestored(menu, source: fixture.source)
        }
    }

    func testClearLiquidBackgroundStillReceivesOutsideTaps() throws {
        for appearance in [AetherAppearanceStyle.liquidGlassV1, .liquidGlassV2] {
            let fixture = makeFixture()
            defer { fixture.window.isHidden = true }
            let menu = makeMenu(source: fixture.source, appearance: appearance)
            menu.present()
            defer { menu.dismiss(animated: false) }

            let hit = try XCTUnwrap(fixture.window.hitTest(CGPoint(x: 300, y: 740), with: nil))
            XCTAssertEqual(hit.backgroundColor?.cgColor.alpha, 0)
            XCTAssertEqual(hit.alpha, 1)
            let recognizer = try XCTUnwrap(hit.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first,
                "The clear background must be hit-testable, not the inert overlay host")
            menu.handleBackgroundTap(recognizer)
            XCTAssertFalse(menu.isPresentedForTesting)
        }
    }

    func testOutsideTapOptOutDoesNotInstallADismissRecognizer() throws {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        let menu = ContextMenuController(source: .init(view: fixture.source),
            items: [.action(.init(id: "action", title: "Action"))],
            appearanceStyle: .liquidGlassV2, catchTapsOutside: false, hasHapticFeedback: false)
        menu.present()
        defer { menu.dismiss(animated: false) }
        let hit = try XCTUnwrap(fixture.window.hitTest(CGPoint(x: 300, y: 740), with: nil))
        XCTAssertFalse(hit.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } ?? false)
        XCTAssertTrue(menu.isPresentedForTesting)
    }

    func testDefaultSourceHidesItsOriginalDuringPresentation() {
        XCTAssertTrue(ContextMenuController.Source(view: UIView()).hidesDuringPresentation)
    }

    func testRuntimeAppearanceIsResolvedWhenPresented() {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        let menu = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            makeMenu(source: fixture.source)
        }
        AetherAppearance.withRuntimeCurrent(.legacy) { menu.present() }
        XCTAssertEqual(menu.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(menu.hasGlassmorphicTransitionForTesting)
        menu.dismiss(animated: false)
        assertRestored(menu, source: fixture.source)
    }

    func testImmediateDismissDuringOpeningRestoresOriginalStateExactlyOnce() {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        fixture.source.alpha = 0.63
        fixture.source.transform = CGAffineTransform(scaleX: 0.96, y: 0.98)
        fixture.source.isUserInteractionEnabled = false
        let originalTransform = fixture.source.transform
        var dismissCount = 0
        let menu = makeMenu(source: fixture.source, appearance: .liquidGlassV1) { dismissCount += 1 }
        menu.present()
        menu.dismiss(animated: false)
        menu.dismiss(animated: false)

        XCTAssertEqual(dismissCount, 1)
        XCTAssertFalse(menu.hasPresentationOverlayForTesting)
        XCTAssertFalse(menu.hasGlassmorphicTransitionForTesting)
        XCTAssertFalse(menu.usesSourcePresentationLeaseForTesting)
        XCTAssertEqual(fixture.source.alpha, 0.63, accuracy: 0.001)
        XCTAssertEqual(fixture.source.transform, originalTransform)
        XCTAssertFalse(fixture.source.isUserInteractionEnabled)
        XCTAssertFalse(fixture.source.isHidden)
    }

    func testImmediateDismissFinishesPendingAnimatedCloseOnce() {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        var dismissCount = 0
        let menu = makeMenu(source: fixture.source, appearance: .liquidGlassV1) { dismissCount += 1 }
        menu.present()
        menu.dismiss(animated: true)
        menu.dismiss(animated: false)
        menu.dismiss(animated: false)
        assertRestored(menu, source: fixture.source)
        XCTAssertEqual(dismissCount, 1)
    }

    func testAppearanceChangeCancelsInheritedPresentationAndRestoresSource() {
        let fixture = makeFixture()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            fixture.window.isHidden = true
        }
        let menu = makeMenu(source: fixture.source)
        AetherAppearance.withRuntimeCurrent(.liquidGlassV1) { menu.present() }
        AetherAppearanceConsumerRegistry.apply(.legacy, animated: true)
        assertRestored(menu, source: fixture.source)
    }

    func testExplicitAppearanceSurvivesRuntimeChange() {
        let fixture = makeFixture()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            fixture.window.isHidden = true
        }
        let menu = makeMenu(source: fixture.source, appearance: .legacy)
        menu.present()
        AetherAppearanceConsumerRegistry.apply(.liquidGlassV2, animated: false)
        XCTAssertTrue(menu.isPresentedForTesting)
        XCTAssertEqual(menu.resolvedAppearanceStyleForTesting, .legacy)
        menu.dismiss(animated: false)
        assertRestored(menu, source: fixture.source)
    }

    func testRepeatedPresentAndDismissDoesNotAccumulateOverlaysOrCallbacks() {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        let initialCount = fixture.window.subviews.count
        var dismissCount = 0
        let menu = makeMenu(source: fixture.source, appearance: .liquidGlassV1) { dismissCount += 1 }
        for iteration in 1...3 {
            menu.present()
            let countWhilePresented = fixture.window.subviews.count
            menu.present()
            XCTAssertEqual(fixture.window.subviews.count, countWhilePresented)
            menu.dismiss(animated: false)
            assertRestored(menu, source: fixture.source)
            XCTAssertEqual(fixture.window.subviews.count, initialCount)
            XCTAssertEqual(dismissCount, iteration)
        }
    }

    func testOptionalPreviewPreservesSeparateLiftedContentPresentation() {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        let menu = ContextMenuController(
            source: .init(view: fixture.source),
            items: [.action(.init(id: "preview-action", title: "Action"))],
            preview: .init(verticalSpacing: 8, lift: 1.04),
            appearanceStyle: .liquidGlassV1,
            hasHapticFeedback: false
        )
        menu.present()
        XCTAssertTrue(menu.isPresentedForTesting)
        XCTAssertFalse(menu.hasGlassmorphicTransitionForTesting)
        XCTAssertFalse(menu.usesSourcePresentationLeaseForTesting)
        menu.dismiss(animated: false)
        assertRestored(menu, source: fixture.source)
    }

    func testSourceWithoutWindowDoesNotAcquirePresentationResources() {
        let source = UIView(frame: CGRect(x: 20, y: 60, width: 44, height: 44))
        let menu = makeMenu(source: source)
        menu.present()
        assertRestored(menu, source: source)
    }

    private func makeMenu(
        source: UIView,
        appearance: AetherAppearanceStyle? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> ContextMenuController {
        ContextMenuController(
            source: .init(view: source, cornerRadius: 22),
            items: [.action(.init(id: "action", title: "Action", icon: UIImage(systemName: "checkmark")))],
            appearanceStyle: appearance,
            hasHapticFeedback: false,
            onDismiss: onDismiss
        )
    }

    private func makeFixture() -> (window: UIWindow, source: UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.backgroundColor = .systemBackground
        let source = UIView(frame: CGRect(x: 24, y: 64, width: 88, height: 44))
        source.backgroundColor = .systemBlue
        source.layer.cornerRadius = 22
        root.view.addSubview(source)
        root.view.layoutIfNeeded()
        return (window, source)
    }

    private func assertRestored(_ menu: ContextMenuController, source: UIView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(menu.isPresentedForTesting, file: file, line: line)
        XCTAssertFalse(menu.hasPresentationOverlayForTesting, file: file, line: line)
        XCTAssertFalse(menu.hasGlassmorphicTransitionForTesting, file: file, line: line)
        XCTAssertFalse(menu.usesSourcePresentationLeaseForTesting, file: file, line: line)
        XCTAssertEqual(source.alpha, 1, accuracy: 0.001, file: file, line: line)
        XCTAssertTrue(source.isUserInteractionEnabled, file: file, line: line)
    }
}
