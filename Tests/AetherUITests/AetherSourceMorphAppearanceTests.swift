import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherSourceMorphAppearanceTests: XCTestCase {
    func testExplicitLegacyPopupResolvesBeforeLiquidResourcesAreAllocated() {
        let fixture = makeWindowFixture()
        defer { fixture.window.isHidden = true }

        fixture.source.alpha = 0.72
        fixture.source.isUserInteractionEnabled = false
        let content = UIView()
        let controller = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherSourceMorphController(
                contentView: content,
                targetSize: CGSize(width: 260, height: 220),
                configuration: .init(openDuration: 10, closeDuration: 10),
                appearanceStyle: .legacy
            )
        }

        controller.present(from: fixture.source, in: fixture.host)

        XCTAssertEqual(controller.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(controller.isPresentedForTesting)
        XCTAssertTrue(controller.hasPresentationOverlayForTesting)
        XCTAssertEqual(controller.legacyBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertFalse(controller.hasActiveDisplayLinkForTesting)
        XCTAssertFalse(controller.hasSourceSnapshotForTesting)
        XCTAssertTrue(controller.contentViewForTesting === content)
        XCTAssertEqual(fixture.source.alpha, 0.72, accuracy: 0.001)
        XCTAssertFalse(fixture.source.isUserInteractionEnabled)

        controller.dismiss(animated: false)
        XCTAssertFalse(controller.hasPresentationOverlayForTesting)
        XCTAssertTrue(controller.contentViewForTesting === content)
    }

    func testInheritedLiquidPopupCleansDriverAndSnapshotSynchronouslyOnLegacySwitch() {
        let fixture = makeWindowFixture()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            fixture.window.isHidden = true
        }

        let content = UIView()
        var dismissCount = 0
        let controller = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            AetherSourceMorphController(
                contentView: content,
                targetSize: CGSize(width: 260, height: 220),
                configuration: .init(openDuration: 10, closeDuration: 10)
            )
        }
        controller.onDismiss = { dismissCount += 1 }
        controller.present(from: fixture.source, in: fixture.host)

        XCTAssertTrue(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertTrue(controller.hasSourceSnapshotForTesting)
        XCTAssertEqual(fixture.source.alpha, 0, accuracy: 0.001)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: true)

        XCTAssertEqual(controller.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(controller.isPresentedForTesting)
        XCTAssertFalse(controller.hasPresentationOverlayForTesting)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertFalse(controller.hasActiveDisplayLinkForTesting)
        XCTAssertFalse(controller.hasSourceSnapshotForTesting)
        XCTAssertEqual(fixture.source.alpha, 1, accuracy: 0.001)
        XCTAssertTrue(fixture.source.isUserInteractionEnabled)
        XCTAssertTrue(controller.contentViewForTesting === content)
        XCTAssertEqual(dismissCount, 1)
    }

    func testAttachmentMenuUsesItsLatestInheritedSeedWithoutPinningChild() {
        let fixture = makeWindowFixture()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            fixture.window.isHidden = true
        }

        let controller = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            AetherAttachmentMenuController(items: [.init(title: "Photo")])
        }
        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)
        controller.present(from: fixture.source, in: fixture.host)

        XCTAssertEqual(controller.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(controller.hasActivePresentationForTesting)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertEqual(controller.legacyBlurStyleForTesting, .systemChromeMaterial)

        controller.dismiss()
    }

    func testLegacyAttachmentMenuClampsRowGeometryInNarrowHost() {
        let fixture = makeWindowFixture(size: CGSize(width: 120, height: 300))
        defer { fixture.window.isHidden = true }

        let controller = AetherAttachmentMenuController(
            items: [.init(title: "A title that must truncate safely")],
            appearanceStyle: .legacy
        )
        controller.present(from: fixture.source, in: fixture.host)

        XCTAssertTrue(controller.hasActivePresentationForTesting)
        XCTAssertFalse(controller.hasLiquidTransitionResourcesForTesting)
        XCTAssertEqual(controller.legacyBlurStyleForTesting, .systemChromeMaterial)

        controller.dismiss()
    }

    func testSurfaceControllerRebuildsInheritedRendererAndPreservesContent() {
        let fixture = makeWindowFixture()
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
            fixture.window.isHidden = true
        }

        let state = AetherSourceMorphSurfaceController.State(rawValue: "open")
        let contentIdentity: UIView
        let controller = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            AetherSourceMorphSurfaceController(
                sourceFrame: fixture.source.frame,
                sourceView: fixture.source,
                initialState: state,
                stateConfigurations: [
                    state: .init(cornerRadius: 28) { _ in
                        CGRect(x: 40, y: 180, width: 310, height: 420)
                    }
                ],
                configuration: .init(presentationDuration: 10, dismissalDuration: 10)
            )
        }
        contentIdentity = controller.contentView
        controller.install(in: fixture.host)
        controller.present(animated: true)

        XCTAssertTrue(controller.hasLiquidSurfaceForTesting)
        XCTAssertTrue(controller.isPresentedForTesting)
        XCTAssertEqual(fixture.source.alpha, 0, accuracy: 0.001)

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: true)

        XCTAssertEqual(controller.resolvedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(controller.isPresentedForTesting)
        XCTAssertFalse(controller.hasInstalledSurfaceForTesting)
        XCTAssertFalse(controller.hasLiquidSurfaceForTesting)
        XCTAssertEqual(controller.legacyBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertTrue(controller.contentView === contentIdentity)
        XCTAssertEqual(fixture.source.alpha, 1, accuracy: 0.001)
        XCTAssertTrue(fixture.source.isUserInteractionEnabled)
    }

    private func makeWindowFixture(
        size: CGSize = CGSize(width: 390, height: 844)
    ) -> (window: UIWindow, host: UIView, source: UIView) {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let root = UIViewController()
        root.view.frame = window.bounds
        window.rootViewController = root
        window.makeKeyAndVisible()

        let source = UIView(frame: CGRect(x: 24, y: 72, width: 44, height: 44))
        source.layer.cornerRadius = 22
        root.view.addSubview(source)
        return (window, root.view, source)
    }
}
