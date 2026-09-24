import XCTest
import UIKit
@testable import AetherUI

final class ChatBackgroundTests: XCTestCase {
    @MainActor
    func testGradientMaskCompositePreservesPixelsAndInvalidates() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let mask = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image {
            UIColor.white.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        let node = ChatBackgroundGradientMaskNode()
        node.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        _ = node.view
        let color = UIColor { $0.userInterfaceStyle == .dark ? .blue : .red }
        func configure(_ style: UIUserInterfaceStyle) {
            node.configure(image: mask, mode: .fill, gradient: .init(baseColor: color, fields: []),
                           traits: UITraitCollection(userInterfaceStyle: style))
            node.setNeedsLayout()
            node.layoutIfNeeded()
        }
        func pixels() throws -> [UInt8] {
            let image = try XCTUnwrap(node.layer.contents) as! CGImage
            var bytes = [UInt8](repeating: 0, count: 20 * 20 * 4)
            try bytes.withUnsafeMutableBytes {
                let context = try XCTUnwrap(CGContext(data: $0.baseAddress, width: 20, height: 20,
                    bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            return bytes
        }
        configure(.light)
        let red = try pixels()
        let opaque = (5 * 20 + 10) * 4
        let transparent = (15 * 20 + 10) * 4
        XCTAssertEqual(Array(red[opaque..<opaque + 4]), [255, 0, 0, 255])
        XCTAssertEqual(red[transparent + 3], 0)
        let count = node.compositeRenderCount
        node.setNeedsLayout()
        node.layoutIfNeeded()
        XCTAssertEqual(node.compositeRenderCount, count)
        configure(.dark)
        let blue = try pixels()
        XCTAssertEqual(Array(blue[opaque..<opaque + 4]), [0, 0, 255, 255])
        XCTAssertGreaterThan(node.compositeRenderCount, count)
        let darkCount = node.compositeRenderCount
        node.frame.size.width = 40
        node.setNeedsLayout()
        node.layoutIfNeeded()
        XCTAssertGreaterThan(node.compositeRenderCount, darkCount)
        XCTAssertNil(node.layer.mask)
    }

    func testGradientVectorForCardinalAngles() {
        let horizontal = ChatBackgroundSettings.gradientVector(rotation: 0.0)
        XCTAssertEqual(horizontal.startPoint.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(horizontal.startPoint.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(horizontal.endPoint.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(horizontal.endPoint.y, 0.5, accuracy: 0.001)

        let vertical = ChatBackgroundSettings.gradientVector(rotation: 90.0)
        XCTAssertEqual(vertical.startPoint.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(vertical.startPoint.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(vertical.endPoint.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(vertical.endPoint.y, 1.0, accuracy: 0.001)
    }

    func testContentStatsClassifyDarkAndSaturatedColors() {
        let black = ChatBackgroundSettings.contentStats(for: [UIColor.black])
        XCTAssertTrue(black.isDark)
        XCTAssertFalse(black.isSaturated)

        let red = ChatBackgroundSettings.contentStats(for: [UIColor.red])
        XCTAssertFalse(red.isDark)
        XCTAssertTrue(red.isSaturated)
    }

    func testRadialGradientStatsIncludeBaseAndFields() {
        let settings = ChatBackgroundSettings(content: .radialGradient(.init(
            baseColor: .black,
            fields: [
                .init(
                    color: .systemTeal,
                    center: CGPoint(x: 0.8, y: 0.2),
                    radius: CGSize(width: 0.7, height: 0.6)
                )
            ]
        )))

        let traits = UITraitCollection(userInterfaceStyle: .dark)
        let stats = settings.estimatedContentStats(traitCollection: traits)
        let expected = ChatBackgroundSettings.contentStats(
            for: [.black, .systemTeal],
            traitCollection: traits
        )

        XCTAssertEqual(stats.brightness, expected.brightness, accuracy: 0.001)
        XCTAssertEqual(stats.saturation, expected.saturation, accuracy: 0.001)
        XCTAssertTrue(stats.isSaturated)
    }

    func testPatternClampsIntensityAndScale() {
        let pattern = ChatBackgroundSettings.Pattern(intensity: 3.0, scale: 0.01)
        XCTAssertEqual(pattern.clampedIntensity, 1.0)
        XCTAssertEqual(pattern.clampedScale, 0.15)
    }

    func testDefaultPatternImageHasRequestedSize() {
        let image = ChatBackgroundSettings.makeDefaultPatternImage(size: CGSize(width: 80.0, height: 60.0))
        XCTAssertEqual(image.size.width, 80.0, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 60.0, accuracy: 0.001)
    }
}
