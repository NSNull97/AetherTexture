import XCTest
import UIKit
@testable import AetherUI

final class LegacyNavigationSearchFigmaTests: XCTestCase {
    @MainActor
    func testLegacyNavigationUsesFigmaChromeMetricsAndColors() {
        let context = AetherAppearanceResolutionContext(
            appearance: .legacy,
            surface: .navigation,
            placement: .navigation,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context)

        guard case let .visible(separatorColor, separatorOpacity) = resolved.separator else {
            return XCTFail("Legacy navigation must expose the classic bottom divider")
        }
        XCTAssertEqual(separatorOpacity, 0.3, accuracy: 0.001)
        XCTAssertEqual(resolved.buttonColor, .systemBlue)
        assertRGBA(
            separatorColor ?? .clear,
            equals: .black,
            traits: UITraitCollection(userInterfaceStyle: .light)
        )
        assertRGBA(
            separatorColor ?? .clear,
            equals: .white,
            traits: UITraitCollection(userInterfaceStyle: .dark)
        )

        let theme = NavigationBarTheme(aetherResolvedAppearance: resolved)
        XCTAssertTrue(theme.enableBackgroundBlur)
        assertRGBA(
            theme.separatorColor,
            equals: UIColor.black.withAlphaComponent(0.3),
            traits: context.traitCollection ?? .current
        )
        assertRGBA(
            theme.separatorColor,
            equals: UIColor.white.withAlphaComponent(0.3),
            traits: UITraitCollection(userInterfaceStyle: .dark)
        )

        let bar = NavigationBarImpl(
            presentationData: NavigationBarPresentationData(theme: theme)
        )
        let width: CGFloat = 402.0
        bar.updateLayout(
            size: CGSize(width: width, height: 44.0),
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            additionalCutout: nil,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: .immediate
        )

        XCTAssertEqual(bar.contentHeight(defaultHeight: 60.0), 44.0, accuracy: 0.001)
        XCTAssertEqual(bar.debugLegacyBackArrowFrame.minX, 8.0, accuracy: 0.001)
        XCTAssertEqual(bar.debugLegacyLeftButtonContainerFrame.minX, 16.0, accuracy: 0.001)
        XCTAssertEqual(bar.debugLegacyRightButtonContainerFrame.maxX, width - 16.0, accuracy: 0.001)
        XCTAssertEqual(
            bar.stripeNode.frame.height,
            1.0 / max(bar.traitCollection.displayScale, 1.0),
            accuracy: 0.001
        )
    }

    @MainActor
    func testLegacyNavigationSearchMatchesFigmaFieldAndWrapperMetrics() throws {
        let search = AetherSearchBarContent(appearanceStyle: .legacy)
        let size = CGSize(width: 402.0, height: AetherLegacySearchFieldMetrics.wrapperHeight)
        search.frame = CGRect(origin: .zero, size: size)

        _ = search.updateLayout(
            size: size,
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        XCTAssertEqual(search.nominalHeight, 52.0, accuracy: 0.001)
        XCTAssertEqual(search.pillHeight, 36.0, accuracy: 0.001)
        XCTAssertEqual(
            search.pillView.frame,
            CGRect(x: 16.0, y: 1.0, width: 370.0, height: 36.0)
        )
        XCTAssertEqual(
            search.pillView.params?.shape,
            .roundedRect(cornerRadius: 10.0)
        )
        XCTAssertNil(search.backingLegacyBlurStyleForTesting)
        XCTAssertTrue(search.pillView.usesLegacySurfaceRendererForTesting)
        assertRGBA(
            try XCTUnwrap(search.pillView.legacyPlainSurfaceBackgroundColorForTesting),
            equals: .tertiarySystemFill,
            traits: UITraitCollection(userInterfaceStyle: .light)
        )

        XCTAssertEqual(
            search.iconFrameForTesting,
            CGRect(x: 24.0, y: 8.0, width: 22.0, height: 22.0)
        )
        XCTAssertEqual(
            search.placeholderFrameForTesting,
            CGRect(x: 46.0, y: 8.0, width: 332.0, height: 22.0)
        )
    }

    @MainActor
    func testLiquidNavigationSearchRetainsExistingCapsuleMetrics() {
        let search = AetherSearchBarContent(appearanceStyle: .liquidGlassV1)
        XCTAssertEqual(search.pillHeight, 44.0, accuracy: 0.001)
        XCTAssertEqual(search.nominalHeight, 56.0, accuracy: 0.001)
    }

    @MainActor
    func testLegacyActiveSearchUsesOrdinaryFilledSurface() {
        let search = AetherAppearance.withRuntimeCurrent(.legacy) {
            AetherActiveSearchBar()
        }
        XCTAssertNil(search.backingLegacyBlurStyleForTesting)
    }

    private func assertRGBA(
        _ actual: UIColor,
        equals expected: UIColor,
        traits: UITraitCollection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = actual.resolvedColor(with: traits)
        let expected = expected.resolvedColor(with: traits)
        var actualRed = CGFloat.zero
        var actualGreen = CGFloat.zero
        var actualBlue = CGFloat.zero
        var actualAlpha = CGFloat.zero
        var expectedRed = CGFloat.zero
        var expectedGreen = CGFloat.zero
        var expectedBlue = CGFloat.zero
        var expectedAlpha = CGFloat.zero
        XCTAssertTrue(
            actual.getRed(
                &actualRed,
                green: &actualGreen,
                blue: &actualBlue,
                alpha: &actualAlpha
            ),
            file: file,
            line: line
        )
        XCTAssertTrue(
            expected.getRed(
                &expectedRed,
                green: &expectedGreen,
                blue: &expectedBlue,
                alpha: &expectedAlpha
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
