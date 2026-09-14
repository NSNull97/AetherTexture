import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class LensTransitionAppearanceTests: XCTestCase {
    private final class StubEffectView: UIView, LensTransitionContainerEffectView {
        nonisolated func updateSize(duration: Double, keyframes: [CGSize]) {}
        nonisolated func updateSize(size: CGSize, transition: ContainedViewLayoutTransition) {}
        nonisolated func updatePosition(duration: Double, keyframes: [CGPoint]) {}
        nonisolated func updatePosition(position: CGPoint, transition: ContainedViewLayoutTransition) {}
        nonisolated func updateCornerRadius(duration: Double, keyframes: [CGFloat]) {}
        nonisolated func setTransitionFraction(value: CGFloat, duration: Double) {}
    }

    private func hasAnimationsRecursively(_ view: UIView) -> Bool {
        if hasAnimationsRecursively(view.layer) {
            return true
        }
        return view.subviews.contains(where: hasAnimationsRecursively)
    }

    private func hasAnimationsRecursively(_ layer: CALayer) -> Bool {
        if !(layer.animationKeys() ?? []).isEmpty {
            return true
        }
        return (layer.sublayers ?? []).contains(where: hasAnimationsRecursively)
    }

    func testExplicitLegacyLensEffectNeverAllocatesGlassOrBlurResources() {
        let contentView = UIView()
        let effectView = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            LensEffectView(
                contentView: contentView,
                appearanceStyle: .legacy
            )
        }

        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertFalse(effectView.hasVisualEffectForTesting)
        XCTAssertFalse(effectView.hasRendererFiltersForTesting)
        XCTAssertTrue(contentView.superview === effectView)

        effectView.updateAppearance(isDark: false)
        effectView.updateSize(
            size: CGSize(width: 80, height: 44),
            transition: .immediate
        )
        effectView.setTransitionFraction(value: 0, duration: 0.25)
        effectView.aetherApplyAppearance(.liquidGlassV1, animated: false)

        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertFalse(effectView.hasVisualEffectForTesting)
        XCTAssertFalse(effectView.hasRendererFiltersForTesting)
        XCTAssertTrue(contentView.superview === effectView)
    }

    func testExplicitLegacyContainerPinsLensBeforeRendererAllocation() {
        let contentView = UIView()
        let effectView = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            LensEffectView(
                contentView: contentView,
                appearanceStyle: .liquidGlassV2
            )
        }
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)

        let container = LensTransitionContainer(
            effectView: effectView,
            appearanceStyle: .legacy
        )

        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertFalse(effectView.hasVisualEffectForTesting)
        XCTAssertFalse(effectView.hasRendererFiltersForTesting)
        XCTAssertTrue(contentView.superview === effectView)
        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
    }

    func testInheritedLegacyLensUsesResolvedRuntimeUntilAppearanceUpdate() {
        let contentView = UIView()
        let effectView = AetherAppearance.withRuntimeCurrent(.legacy) {
            LensEffectView(contentView: contentView)
        }

        // `withRuntimeCurrent` is scoped to construction. Ordinary theme
        // updates must use the already-resolved style rather than silently
        // re-reading the process default after that scope has ended.
        effectView.updateAppearance(isDark: false)

        XCTAssertNil(effectView.appearanceStyle)
        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertTrue(contentView.superview === effectView)

        effectView.aetherApplyAppearance(.liquidGlassV1, animated: false)
        effectView.updateAppearance(isDark: false)

        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .liquidGlassV1)
        XCTAssertTrue(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertTrue(effectView.hasVisualEffectForTesting)

        effectView.aetherApplyAppearance(.legacy, animated: false)

        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertFalse(effectView.hasVisualEffectForTesting)
        XCTAssertFalse(effectView.hasRendererFiltersForTesting)
        XCTAssertTrue(contentView.superview === effectView)
    }

    func testInheritedLensLiquidToLegacyFullyCleansRendererState() throws {
        let contentView = UIView()
        let effectView = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            LensEffectView(contentView: contentView)
        }
        let container = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            LensTransitionContainer(effectView: effectView)
        }

        effectView.updateAppearance(isDark: false)
        effectView.setTransitionFraction(value: 0, duration: 0.25)
        let retainedGlassView = try XCTUnwrap(effectView.glassViewForTesting)
        retainedGlassView.layer.add(
            CABasicAnimation(keyPath: "opacity"),
            forKey: "test.lensCleanup"
        )
        retainedGlassView.contentView.layer.add(
            CABasicAnimation(keyPath: "opacity"),
            forKey: "test.lensContentCleanup"
        )

        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .liquidGlassV1)
        XCTAssertTrue(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertTrue(effectView.hasVisualEffectForTesting)
        XCTAssertTrue(contentView.superview === retainedGlassView.contentView)
        XCTAssertTrue(hasAnimationsRecursively(retainedGlassView))

        container.aetherApplyAppearance(.legacy, animated: false)

        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        XCTAssertEqual(effectView.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertFalse(effectView.hasAllocatedGlassViewForTesting)
        XCTAssertFalse(effectView.hasVisualEffectForTesting)
        XCTAssertFalse(effectView.hasRendererFiltersForTesting)
        XCTAssertNil(retainedGlassView.effect)
        XCTAssertNil(retainedGlassView.layer.filters)
        XCTAssertNil(retainedGlassView.contentView.layer.filters)
        XCTAssertFalse(hasAnimationsRecursively(retainedGlassView))
        XCTAssertNil(retainedGlassView.superview)
        XCTAssertTrue(contentView.superview === effectView)
    }

    func testExplicitLegacyResolvesBeforePrivateLensAllocation() {
        let container = LensTransitionContainer(
            effectView: StubEffectView(),
            appearanceStyle: .legacy
        )

        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        XCTAssertTrue(container.classicImplementationUsesLegacySurfaceForTesting)
        XCTAssertFalse(container.classicImplementationUsesAnyGlassRendererForTesting)
        XCTAssertEqual(
            container.classicImplementationBlurStyleForTesting,
            .systemChromeMaterial
        )
        XCTAssertNil(container.effectView)
    }

    func testExplicitAppearancePinsLensRendererGeneration() {
        let container = LensTransitionContainer(
            effectView: StubEffectView(),
            appearanceStyle: .legacy
        )

        container.aetherApplyAppearance(.liquidGlassV2, animated: false)

        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        XCTAssertTrue(container.classicImplementationUsesLegacySurfaceForTesting)
    }

    func testInheritedAppearanceRebuildsBackendAndKeepsStableContents() {
        let container = AetherAppearance.withRuntimeCurrent(.legacy) {
            // This also keeps the original one-argument source API covered.
            LensTransitionContainer(effectView: StubEffectView())
        }
        XCTAssertNil(container.appearanceStyle)
        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        container.frame = CGRect(x: 0, y: 0, width: 220, height: 180)
        container.update(
            size: CGSize(width: 180, height: 120),
            cornerRadius: 24,
            isDark: false,
            transition: .immediate
        )

        let stableContentsView = container.contentsView
        let marker = UIView(frame: CGRect(x: 4, y: 5, width: 20, height: 12))
        stableContentsView.addSubview(marker)
        let initialClassicImplementation = container.implementationViewForTesting

        container.aetherApplyAppearance(.liquidGlassV1, animated: false)

        XCTAssertFalse(container.implementationViewForTesting === initialClassicImplementation)
        XCTAssertNil(initialClassicImplementation.superview)
        XCTAssertFalse(hasAnimationsRecursively(initialClassicImplementation))
        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .liquidGlassV1)
        XCTAssertTrue(container.contentsView === stableContentsView)
        XCTAssertTrue(marker.superview === stableContentsView)
        #if APPSTORE_SAFE
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        #else
        if #available(iOS 26.0, *) {
            XCTAssertFalse(container.usesClassicImplementationForTesting)
            XCTAssertTrue(container.usesPrivateSDFImplementationForTesting)
        } else {
            XCTAssertTrue(container.usesClassicImplementationForTesting)
            XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        }
        #endif

        let liquidImplementation = container.implementationViewForTesting

        container.aetherApplyAppearance(.legacy, animated: false)

        XCTAssertFalse(container.implementationViewForTesting === liquidImplementation)
        XCTAssertNil(liquidImplementation.superview)
        XCTAssertFalse(hasAnimationsRecursively(liquidImplementation))
        XCTAssertEqual(container.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertTrue(container.usesClassicImplementationForTesting)
        XCTAssertFalse(container.usesPrivateSDFImplementationForTesting)
        XCTAssertTrue(container.classicImplementationUsesLegacySurfaceForTesting)
        XCTAssertFalse(container.classicImplementationUsesAnyGlassRendererForTesting)
        XCTAssertEqual(
            container.classicImplementationBlurStyleForTesting,
            .systemChromeMaterial
        )
        XCTAssertTrue(container.contentsView === stableContentsView)
        XCTAssertTrue(marker.superview === stableContentsView)
    }
}
