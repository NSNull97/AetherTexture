import XCTest
import UIKit
@testable import AetherUI

final class ContextMenuSourcePresentationLeaseTests: XCTestCase {
    func testDisabledCaptionLeasePreservesSourceAndAncestorOpacity() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let group = GlassControlGroup()
        _ = group.update(items: [.init(id: "menu", content: .text("A very long menu title"), action: nil)], transition: .immediate)
        root.addSubview(group)
        group.layoutIfNeeded()
        group.alpha = 0.8
        let button = try XCTUnwrap(group.itemButton(id: "menu"))
        XCTAssertEqual(button.alpha, 0.5)
        let descriptor = try XCTUnwrap(ContextMenuSourceDescriptor(
            sourceID: "menu", hitView: button, visualView: group, overlayView: root,
            sourceCornerRadius: 22, sourceMode: .leasedGlassSource))
        let proxy = descriptor.makeProxyView()
        let imageView = try XCTUnwrap(proxy.subviews.first as? UIImageView)
        XCTAssertEqual(imageView.alpha, 0.8, accuracy: 0.001)
        let image = try XCTUnwrap(imageView.image?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let maximumAlpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
        XCTAssertEqual(Double(maximumAlpha), 127.5, accuracy: 1)
        XCTAssertEqual(button.alpha, 0.5)
        XCTAssertEqual(group.alpha, 0.8, accuracy: 0.001)
    }

    func testSingleItemGlassGroupKeepsWholeSourceGeometryButProxiesOnlyItemContent() throws {
        let rootView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let overlayView = UIView(frame: rootView.bounds)
        let group = GlassControlGroup()
        let image = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        let itemID: AnyHashable = "menu"

        _ = group.update(
            items: [.init(id: itemID, content: .icon(image), action: {})],
            transition: .immediate
        )
        group.frame.origin = CGPoint(x: 320.0, y: 54.0)
        rootView.addSubview(group)
        rootView.addSubview(overlayView)
        rootView.layoutIfNeeded()
        group.layoutIfNeeded()

        let itemButton = try XCTUnwrap(group.itemButton(id: itemID))
        XCTAssertTrue(group.itemVisualSourceView(id: itemID) === group)
        XCTAssertTrue(group.singleItemPresentationProxyContentView === itemButton)

        let descriptor = try XCTUnwrap(ContextMenuSourceDescriptor(
            sourceID: itemID,
            hitView: itemButton,
            visualView: group,
            overlayView: overlayView,
            sourceCornerRadius: 22.0,
            sourceMode: .leasedGlassSource
        ))
        XCTAssertTrue(descriptor.visualView === group)
        assertEqual(
            descriptor.sourceFrameInOverlay,
            group.convert(group.bounds, to: overlayView),
            accuracy: 0.001
        )

        let proxy = descriptor.makeProxyView()
        XCTAssertEqual(proxy.bounds.size, group.bounds.size)
        let contentSnapshot = try XCTUnwrap(proxy.subviews.first)
        XCTAssertEqual(proxy.subviews.count, 1)
        assertEqual(
            contentSnapshot.frame,
            itemButton.convert(itemButton.bounds, to: group),
            accuracy: 0.001
        )
    }

    func testMultiItemGlassGroupKeepsPerItemVisualSourceBehavior() throws {
        let group = GlassControlGroup()
        let firstImage = try XCTUnwrap(UIImage(systemName: "camera"))
        let secondImage = try XCTUnwrap(UIImage(systemName: "ellipsis"))

        _ = group.update(
            items: [
                .init(id: "first", content: .icon(firstImage), action: {}),
                .init(id: "second", content: .icon(secondImage), action: {})
            ],
            transition: .immediate
        )

        let firstButton = try XCTUnwrap(group.itemButton(id: "first"))
        XCTAssertNil(group.singleItemPresentationProxyContentView)
        XCTAssertTrue(group.itemVisualSourceView(id: "first") === firstButton)
    }
}

private extension XCTestCase {
    func assertEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.origin.x, rhs.origin.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.origin.y, rhs.origin.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.size.width, rhs.size.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.size.height, rhs.size.height, accuracy: accuracy, file: file, line: line)
    }
}
