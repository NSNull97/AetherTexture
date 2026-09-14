import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class ContextMenuFigmaLegacyTests: XCTestCase {
    func testLegacyActionMenuMatchesFigmaReferenceMetrics() {
        let view = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            ContextMenuActionsView(
                items: makeFourActions(),
                appearanceStyle: .legacy
            )
        }

        let metrics = view.metricsForTesting
        let itemMetrics = ContextMenuActionItemView.Metrics.resolve(for: .legacy)

        XCTAssertEqual(metrics.preferredWidth, 250.0, accuracy: 0.001)
        XCTAssertEqual(metrics.cornerRadius, 12.0, accuracy: 0.001)
        XCTAssertEqual(metrics.contentInset, .zero)
        XCTAssertTrue(metrics.automaticallySeparatesActionRows)
        XCTAssertEqual(view.preferredSize(maxWidth: 1_000), CGSize(width: 250, height: 176))
        XCTAssertEqual(view.automaticActionSeparatorCountForTesting, 3)

        XCTAssertEqual(itemMetrics.horizontalInset, 16.0, accuracy: 0.001)
        XCTAssertEqual(itemMetrics.titleFontSize, 17.0, accuracy: 0.001)
        XCTAssertEqual(itemMetrics.trailingIconSize, 20.0, accuracy: 0.001)
        XCTAssertEqual(itemMetrics.separatorHeight, 0.5, accuracy: 0.001)
    }

    func testLiquidActionMenuMetricsRemainUnchanged() {
        for style in [AetherAppearanceStyle.liquidGlassV1, .liquidGlassV2] {
            let view = ContextMenuActionsView(
                items: makeFourActions(),
                appearanceStyle: style
            )
            let metrics = view.metricsForTesting
            let itemMetrics = ContextMenuActionItemView.Metrics.resolve(for: style)

            XCTAssertEqual(metrics.preferredWidth, 260.0, accuracy: 0.001)
            XCTAssertEqual(metrics.cornerRadius, 27.0, accuracy: 0.001)
            XCTAssertEqual(metrics.contentInset, UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
            XCTAssertFalse(metrics.automaticallySeparatesActionRows)
            XCTAssertEqual(view.preferredSize(maxWidth: 1_000), CGSize(width: 260, height: 208))
            XCTAssertEqual(view.automaticActionSeparatorCountForTesting, 0)

            XCTAssertEqual(itemMetrics.horizontalInset, 8.0, accuracy: 0.001)
            XCTAssertEqual(itemMetrics.titleFontSize, 16.0, accuracy: 0.001)
            XCTAssertEqual(itemMetrics.trailingIconSize, 22.0, accuracy: 0.001)
        }
    }

    func testLegacyDimmingUsesOnlyClassicChromeMaterial() {
        let dim = ContextMenuLegacyDimView(
            tintColor: UIColor(
                red: 24.0 / 255.0,
                green: 19.0 / 255.0,
                blue: 43.0 / 255.0,
                alpha: 0.21
            )
        )

        XCTAssertEqual(dim.blurStyle, .systemChromeMaterial)
        XCTAssertTrue(dim.effect is UIBlurEffect)
        if #available(iOS 26.0, *) {
            XCTAssertFalse(dim.effect is UIGlassEffect)
        }
    }

    private func makeFourActions() -> [ContextMenuItem] {
        [
            .action(ContextMenuActionItem(title: "Copy", icon: UIImage(systemName: "document.on.document"))),
            .action(ContextMenuActionItem(title: "Share", icon: UIImage(systemName: "square.and.arrow.up"))),
            .action(ContextMenuActionItem(title: "Favorite", icon: UIImage(systemName: "heart"))),
            .action(ContextMenuActionItem(title: "Delete", icon: UIImage(systemName: "trash"), textColor: .destructive))
        ]
    }
}
