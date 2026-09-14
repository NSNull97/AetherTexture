import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class AetherContentMaterializationTests: XCTestCase {
    private func image(scale: CGFloat = 3) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 30, height: 24), format: format).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 12, y: 8, width: 6, height: 8))
        }
    }

    func testBlurPreservesPointSizeAndRetinaScaleAndChangesPixels() throws {
        let original = image()
        let blurred = AetherContentMaterialization.blurredImage(original, radius: 3)
        XCTAssertEqual(blurred.size, original.size)
        XCTAssertEqual(blurred.scale, 3)
        XCTAssertEqual(blurred.cgImage?.width, 90)
        XCTAssertEqual(blurred.cgImage?.height, 72)
        XCTAssertNotEqual(try pixels(blurred), try pixels(original))
        XCTAssertEqual(alpha(atX: 0, y: 0, in: try pixels(blurred), width: 90), 0, accuracy: 2)
    }

    func testImageViewHasExactSharpAndMaximumEndpointsWithoutRebuildingFrames() throws {
        let original = image(scale: 2)
        let view = AetherMaterializationImageView(image: original, maximumBlurRadius: 6)
        let count = view.preparedImageCountForTesting
        let sharp = try XCTUnwrap(view.displayedImageForTesting)
        XCTAssertEqual(view.bounds.size, original.size)
        XCTAssertEqual(view.imageSize, original.size)
        let paddingPixels = view.imagePaddingForTesting * original.scale
        let sharpContent = try XCTUnwrap(sharp.cgImage?.cropping(to: CGRect(
            x: paddingPixels, y: paddingPixels,
            width: original.size.width * original.scale, height: original.size.height * original.scale
        )))
        XCTAssertEqual(try pixels(UIImage(cgImage: sharpContent)), try pixels(original))
        view.setBlurRadius(100)
        XCTAssertEqual(view.blurRadius, 6)
        XCTAssertNotEqual(try pixels(try XCTUnwrap(view.displayedImageForTesting)), try pixels(sharp))
        for index in 0 ..< 60 { view.setBlurRadius(CGFloat(index) / 10) }
        XCTAssertEqual(view.preparedImageCountForTesting, count)
        view.setBlurRadius(-1)
        XCTAssertEqual(view.blurRadius, 0)
        XCTAssertEqual(try pixels(try XCTUnwrap(view.displayedImageForTesting)), try pixels(sharp))
    }

    func testBlurHaloExtendsPastTightGlyphBoundsWithoutMovingLogicalContent() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let glyph = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12), format: format).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        let view = AetherMaterializationImageView(image: glyph, maximumBlurRadius: 3)
        view.setBlurRadius(3)
        let blurred = try XCTUnwrap(view.displayedImageForTesting)
        let bitmap = try pixels(blurred)
        let bitmapWidth = try XCTUnwrap(blurred.cgImage).width
        let paddingPixels = Int(view.imagePaddingForTesting * blurred.scale)
        let centerY = paddingPixels + Int(glyph.size.height * blurred.scale / 2)
        // These pixels are outside the original content rectangle.
        XCTAssertGreaterThan(alpha(atX: paddingPixels - 3, y: centerY, in: bitmap, width: bitmapWidth), 0)
        XCTAssertEqual(alpha(atX: 0, y: 0, in: bitmap, width: bitmapWidth), 0, accuracy: 2)
        XCTAssertEqual(view.bounds.size, glyph.size)
        XCTAssertEqual(blurred.scale, glyph.scale)
        XCTAssertLessThan(view.imageFrameForTesting.minX, view.bounds.minX)

        // Expanding a snapshot keeps the same relative alignment, including
        // caller-owned views with a nonzero bounds origin.
        view.bounds = CGRect(x: 7, y: 9, width: 24, height: 18)
        view.layoutIfNeeded()
        XCTAssertEqual(view.imageFrameForTesting, view.bounds.insetBy(
            dx: -view.imagePaddingForTesting * 2,
            dy: -view.imagePaddingForTesting * 1.5
        ))
    }

    func testCancelIsIdempotentAndPreservesLayoutAndUnrelatedAnimation() throws {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let view = UIView(frame: CGRect(x: 40, y: 20, width: 30, height: 24))
        view.backgroundColor = .black
        view.transform = CGAffineTransform(rotationAngle: 0.15).scaledBy(x: 1.1, y: 0.9)
        parent.addSubview(view)
        let bounds = view.bounds
        let transform = view.transform
        let position = view.layer.position
        let unrelated = CABasicAnimation(keyPath: "cornerRadius")
        unrelated.duration = 10
        view.layer.add(unrelated, forKey: "unrelated")
        var completed = false
        let animation = try XCTUnwrap(AetherContentMaterialization.animate(
            view: view,
            samples: AetherMotion.navigationChromeMaterializationSamples(appearing: true),
            duration: 1,
            targetAlpha: 0.7,
            completion: { completed = true }
        ))
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: view))
        XCTAssertEqual(view.alpha, 0.7, accuracy: 0.001)
        XCTAssertTrue(animation.snapshotForTesting.superview === parent)
        XCTAssertTrue(AetherContentMaterialization.isSnapshotView(animation.snapshotForTesting))
        XCTAssertFalse(AetherContentMaterialization.isSnapshotView(view))
        XCTAssertEqual(view.bounds, bounds)
        XCTAssertEqual(view.transform, transform)
        XCTAssertEqual(view.layer.position, position)
        AetherContentMaterialization.cancel(view: view)
        animation.cancel()
        XCTAssertFalse(AetherContentMaterialization.isAnimating(view: view))
        XCTAssertNil(animation.snapshotForTesting.superview)
        XCTAssertEqual(parent.subviews.count, 1)
        XCTAssertEqual(view.alpha, 0.7, accuracy: 0.001)
        XCTAssertNotNil(view.layer.animation(forKey: "unrelated"))
        XCTAssertFalse(completed)
    }

    func testReplacementCancelsOldSnapshotAndCompletionRemovesNewSnapshot() throws {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        view.backgroundColor = .red
        parent.addSubview(view)
        let first = try XCTUnwrap(AetherContentMaterialization.animate(
            view: view,
            samples: AetherMotion.navigationChromeMaterializationSamples(appearing: true),
            duration: 10,
            targetAlpha: 1
        ))
        let finished = expectation(description: "materialization completes")
        let second = try XCTUnwrap(AetherContentMaterialization.animate(
            view: view,
            samples: AetherMotion.navigationChromeMaterializationSamples(appearing: false),
            duration: 0.02,
            targetAlpha: 0,
            completion: { finished.fulfill() }
        ))
        XCTAssertFalse(first.isActive)
        XCTAssertNil(first.snapshotForTesting.superview)
        XCTAssertEqual(parent.subviews.count, 2)
        wait(for: [finished], timeout: 2)
        XCTAssertFalse(AetherContentMaterialization.isAnimating(view: view))
        XCTAssertNil(second.snapshotForTesting.superview)
        XCTAssertEqual(parent.subviews.count, 1)
        XCTAssertEqual(view.alpha, 0)
    }

    func testReleasingCancelledHandleDoesNotRevealSourceDuringReplacement() throws {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        view.backgroundColor = .black
        parent.addSubview(view)
        var first = AetherContentMaterialization.animate(
            view: view,
            samples: AetherMotion.navigationChromeMaterializationSamples(appearing: true),
            duration: 10,
            targetAlpha: 1
        )
        weak var oldHandle = first
        XCTAssertNotNil(oldHandle)
        let replacement = try XCTUnwrap(AetherContentMaterialization.animate(
            view: view,
            samples: AetherMotion.navigationChromeMaterializationSamples(appearing: false),
            duration: 10,
            targetAlpha: 0
        ))
        let suppressionKey = try XCTUnwrap(view.layer.animationKeys()?.first {
            $0.hasPrefix("aether.contentMaterialization.suppression")
        })
        first = nil
        XCTAssertNil(oldHandle)
        XCTAssertNotNil(view.layer.animation(forKey: suppressionKey))
        XCTAssertTrue(replacement.isActive)
        XCTAssertTrue(replacement.snapshotForTesting.superview === parent)
        replacement.cancel()
        XCTAssertNil(view.layer.animation(forKey: suppressionKey))
        XCTAssertEqual(parent.subviews.count, 1)
    }

    func testCapturePreservesSourceAlphaAndHiddenState() throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        view.backgroundColor = .black
        view.alpha = 0.3
        view.layer.isHidden = true
        let image = try XCTUnwrap(AetherContentMaterialization.captureContent(of: view))
        XCTAssertEqual(view.alpha, 0.3, accuracy: 0.001)
        XCTAssertTrue(view.layer.isHidden)
        XCTAssertEqual(image.size, view.bounds.size)
    }

    func testActualCompoundBackAnimationSnapshotAlreadyContainsBadge() throws {
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        let content = NavigationAutomaticBackBadgeContentView(
            text: "165",
            chevron: try XCTUnwrap(UIImage(systemName: "chevron.left"))
        )
        _ = group.update(
            items: [.init(id: "back", content: .customView(content), action: {})],
            transition: .animated(duration: 0.34, curve: .navigationFluidMorph)
        )
        let button = try XCTUnwrap(group.itemButton(id: "back"))
        let captured = try XCTUnwrap(AetherContentMaterialization.capturedImageForTesting(of: button))
        // Do not call captureContent here: that second layout/display pass
        // would hide a missing badge in the actual animation's first image.
        XCTAssertTrue(try containsRedPixel(captured))
        AetherContentMaterialization.cancel(view: button)
    }

    func testAnimationSnapshotLaysOutNestedUIKitWrappersBeforeTextureDisplay() throws {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 60))
        let wrapper = PendingBadgeLayoutView(frame: CGRect(x: 5, y: 5, width: 80, height: 44))
        parent.addSubview(wrapper)
        XCTAssertEqual(wrapper.badge.bounds.size, .zero)
        let animation = try XCTUnwrap(AetherContentMaterialization.animate(
            view: wrapper,
            samples: AetherMotion.navigationChromeMaterializationSamples(appearing: true),
            duration: 1,
            targetAlpha: 1
        ))
        let captured = try XCTUnwrap(AetherContentMaterialization.capturedImageForTesting(of: wrapper))
        XCTAssertTrue(try containsRedPixel(captured))
        XCTAssertGreaterThan(wrapper.badge.bounds.width, 0)
        animation.cancel()
    }

    private func containsRedPixel(_ image: UIImage) throws -> Bool {
        let bytes = try pixels(image)
        return stride(from: 0, to: bytes.count, by: 4).contains { index in
            bytes[index] > 180 && bytes[index + 1] < 130
                && bytes[index + 2] < 130 && bytes[index + 3] > 160
        }
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func alpha(atX x: Int, y: Int, in pixels: [UInt8], width: Int) -> Double {
        Double(pixels[(y * width + x) * 4 + 3])
    }
}

private final class PendingBadgeLayoutView: UIView {
    let badge = NavigationBarBadgeView()
    private let wrapper = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        badge.text = "165"
        wrapper.addSubview(badge)
        addSubview(wrapper)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        wrapper.frame = bounds
        badge.frame = CGRect(origin: CGPoint(x: 30, y: 13), size: badge.sizeThatFits(bounds.size))
    }
}
