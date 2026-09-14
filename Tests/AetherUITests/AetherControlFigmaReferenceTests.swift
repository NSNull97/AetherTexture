import XCTest
import UIKit
@testable import AetherUI

final class AetherControlFigmaReferenceTests: XCTestCase {
    @MainActor
    func testLegacySliderUsesIOS18ReferenceGeometry() {
        let slider = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherSlider(value: 0.5, appearanceStyle: .legacy)
        }

        XCTAssertEqual(slider.intrinsicContentSize.height, 44.0)
        slider.frame = CGRect(x: 0.0, y: 0.0, width: 370.0, height: 44.0)
        slider.layoutIfNeeded()

        XCTAssertEqual(slider.trackFrameForTesting.height, 4.0)
        XCTAssertEqual(slider.thumbFrameForTesting.size, CGSize(width: 28.0, height: 28.0))
        XCTAssertEqual(slider.thumbFrameForTesting.midY, slider.bounds.midY)
    }

    @MainActor
    func testLegacySliderEndpointImagesUseReferenceBoxesAndSpacing() throws {
        let slider = AetherSlider(value: 0.5, appearanceStyle: .legacy)
        slider.minimumValueImage = try XCTUnwrap(UIImage(systemName: "tortoise.fill"))
        slider.maximumValueImage = try XCTUnwrap(UIImage(systemName: "hare.fill"))
        slider.frame = CGRect(x: 0.0, y: 0.0, width: 370.0, height: 44.0)
        slider.layoutIfNeeded()

        XCTAssertEqual(slider.minimumValueImageFrameForTesting.size, CGSize(width: 24.0, height: 24.0))
        XCTAssertEqual(slider.maximumValueImageFrameForTesting.size, CGSize(width: 24.0, height: 24.0))
        XCTAssertEqual(
            slider.trackFrameForTesting.minX - slider.minimumValueImageFrameForTesting.maxX,
            8.0
        )
        XCTAssertEqual(
            slider.maximumValueImageFrameForTesting.minX - slider.trackFrameForTesting.maxX,
            8.0
        )
    }

    @MainActor
    func testLiquidSliderDefaultsRemainUnchanged() {
        for style in [AetherAppearanceStyle.liquidGlassV1, .liquidGlassV2] {
            let slider = AetherSlider(value: 0.5, appearanceStyle: style)
            XCTAssertEqual(slider.intrinsicContentSize.height, 50.0)
            slider.frame = CGRect(x: 0.0, y: 0.0, width: 370.0, height: 50.0)
            slider.layoutIfNeeded()

            XCTAssertEqual(slider.trackFrameForTesting.height, 32.0)
            XCTAssertEqual(slider.thumbFrameForTesting.size, CGSize(width: 44.0, height: 38.0))
        }
    }

    @MainActor
    func testExplicitSliderGeometrySurvivesAppearanceChanges() {
        let slider = AetherSlider(appearanceStyle: .legacy)
        slider.preferredHeight = 61.0
        slider.trackHeight = 11.0
        slider.thumbSize = CGSize(width: 31.0, height: 29.0)

        slider.appearanceStyleOverride = .liquidGlassV2

        XCTAssertEqual(slider.preferredHeight, 61.0)
        XCTAssertEqual(slider.trackHeight, 11.0)
        XCTAssertEqual(slider.thumbSize, CGSize(width: 31.0, height: 29.0))
    }

    @MainActor
    func testNilStyleControlsFollowLiveRuntimeAppearance() {
        defer {
            AetherAppearanceConsumerRegistry.apply(.liquidGlassV1, animated: false)
        }
        let controls = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            (
                AetherSlider(),
                AetherSegmentedControl(items: [.init(title: "One"), .init(title: "Two")]),
                AetherGlassButtonNode(title: "Add"),
                AetherSegmentedControlNode(items: [.init(title: "One"), .init(title: "Two")])
            )
        }
        let (slider, segmented, buttonNode, segmentedNode) = controls

        XCTAssertNil(slider.appearanceStyleOverride)
        XCTAssertNil(segmented.appearanceStyleOverride)
        XCTAssertNil(buttonNode.appearanceStyleOverride)
        XCTAssertNil(segmentedNode.appearanceStyleOverride)
        XCTAssertEqual(slider.trackHeight, 32.0)
        XCTAssertEqual(slider.thumbSize, CGSize(width: 44.0, height: 38.0))

        AetherAppearanceConsumerRegistry.apply(.legacy, animated: false)

        XCTAssertEqual(slider.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(slider.intrinsicContentSize.height, 44.0)
        XCTAssertEqual(slider.trackHeight, 4.0)
        XCTAssertEqual(slider.thumbSize, CGSize(width: 28.0, height: 28.0))
        XCTAssertEqual(segmented.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(buttonNode.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(segmentedNode.appliedAppearanceStyleForTesting, .legacy)
    }

    @MainActor
    func testSliderNodeSeedsLegacyAndForwardsEndpointImagesBeforeLoad() throws {
        let node = AetherSliderNode(value: 0.25, appearanceStyle: .legacy)
        node.minimumValueImage = try XCTUnwrap(UIImage(systemName: "tortoise.fill"))
        node.maximumValueImage = try XCTUnwrap(UIImage(systemName: "hare.fill"))
        _ = node.view

        let slider = try XCTUnwrap(node.sliderViewForTesting)
        XCTAssertEqual(slider.appearanceStyleOverride, .legacy)
        XCTAssertEqual(slider.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(slider.preferredHeight, 44.0)
        XCTAssertEqual(slider.trackHeight, 4.0)
        XCTAssertEqual(slider.thumbSize, CGSize(width: 28.0, height: 28.0))
        XCTAssertNotNil(slider.minimumValueImage)
        XCTAssertNotNil(slider.maximumValueImage)
        XCTAssertFalse(slider.backingUsesAnyGlassRendererForTesting)
    }

    @MainActor
    func testSegmentedControlExplicitLegacyUsesClassicLensAndAccessibleStates() {
        let control = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherSegmentedControl(
                items: [
                    .init(title: "One"),
                    .init(title: "Two", badgeValue: "3")
                ],
                selectedIndex: 0,
                appearanceStyle: .legacy
            )
        }
        control.frame = CGRect(x: 0.0, y: 0.0, width: 240.0, height: 36.0)
        control.layoutIfNeeded()

        XCTAssertEqual(control.appliedAppearanceStyleForTesting, .legacy)
        #if DEBUG
        XCTAssertTrue(control.backingUsesClassicRendererForTesting)
        XCTAssertEqual(
            control.backingClassicBlurStylesForTesting,
            [.systemChromeMaterial, .systemChromeMaterial]
        )
        XCTAssertFalse(control.backingHasLiquidMaskForTesting)
        #endif
        XCTAssertTrue(control.debugAccessibilityTraits(at: 0)?.contains(.selected) == true)
        XCTAssertFalse(control.debugAccessibilityTraits(at: 1)?.contains(.selected) == true)

        control.selectedIndex = 1
        XCTAssertFalse(control.debugAccessibilityTraits(at: 0)?.contains(.selected) == true)
        XCTAssertTrue(control.debugAccessibilityTraits(at: 1)?.contains(.selected) == true)

        control.isEnabled = false
        XCTAssertTrue(control.debugAccessibilityTraits(at: 0)?.contains(.notEnabled) == true)
        XCTAssertTrue(control.debugAccessibilityTraits(at: 1)?.contains(.notEnabled) == true)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV2, animated: false)
        XCTAssertEqual(control.appliedAppearanceStyleForTesting, .legacy)
        #if DEBUG
        XCTAssertTrue(control.backingUsesClassicRendererForTesting)
        #endif
    }

    @MainActor
    func testGlassButtonViewSeedsExplicitLegacyBeforeBackingAllocation() throws {
        let button = GlassButtonView(
            icon: try XCTUnwrap(UIImage(systemName: "plus")),
            appearanceStyle: .legacy
        )

        XCTAssertEqual(button.appearanceStyleOverride, .legacy)
        XCTAssertFalse(button.backingUsesLiquidGlassAppearanceForTesting)
        XCTAssertFalse(button.backingUsesAnyGlassRendererForTesting)
        XCTAssertEqual(button.backingLegacyBlurStyleForTesting, .systemChromeMaterial)
    }

    @MainActor
    func testTextureControlWrappersPinAppearanceAndMatchBadgePillMetrics() {
        let button = AetherGlassButtonNode(title: "Add", appearanceStyle: .legacy)
        let segmented = AetherSegmentedControlNode(
            items: [
                .init(title: "One"),
                .init(title: "Two", badgeValue: "3")
            ],
            appearanceStyle: .legacy
        )
        segmented.frame = CGRect(x: 0.0, y: 0.0, width: 240.0, height: 36.0)
        segmented.view.layoutIfNeeded()

        XCTAssertEqual(button.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(segmented.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(segmented.badgeFrameForTesting(at: 1)?.height, 18.0)
        XCTAssertGreaterThanOrEqual(segmented.badgeFrameForTesting(at: 1)?.width ?? 0.0, 18.0)

        AetherAppearanceConsumerRegistry.apply(.liquidGlassV2, animated: false)
        XCTAssertEqual(button.appliedAppearanceStyleForTesting, .legacy)
        XCTAssertEqual(segmented.appliedAppearanceStyleForTesting, .legacy)
    }

}
