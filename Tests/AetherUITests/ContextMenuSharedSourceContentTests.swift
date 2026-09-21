import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class ContextMenuSharedSourceContentTests: XCTestCase {
    func testSnapshotsUseOccupiedPixelsAndPreserveIndependentOpacity() throws {
        let snapshots = contextMenuSharedSourceSnapshots(image: markerImage(), regions: regions)
        XCTAssertEqual(snapshots.count, 2)
        let first = try XCTUnwrap(snapshots.first)
        let second = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(first.frame, CGRect(x: 0, y: 0, width: 44, height: 44))
        XCTAssertEqual(second.frame, CGRect(x: 44, y: 0, width: 44, height: 44))
        XCTAssertEqual(first.alphaBounds, CGRect(x: 15, y: 9, width: 10, height: 16))
        XCTAssertEqual(second.alphaBounds, CGRect(x: 60, y: 15, width: 12, height: 6))
        XCTAssertEqual(try maximumAlpha(first.image), 102, accuracy: 1)
        XCTAssertEqual(try maximumAlpha(second.image), 204, accuracy: 1)
        XCTAssertEqual(first.image.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(second.image.size, CGSize(width: 44, height: 44))
    }

    func testOnlySharedIconGroupsPublishRegionsAndLeaseKeepsWholeSource() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let group = GlassControlGroup(appearanceStyle: .liquidGlassV1)
        root.addSubview(group)
        // An original-colour solid glyph has a known opaque interior. System
        // symbols inherit the group's translucent foreground tint, which is
        // independent of the disabled/group opacity this test measures.
        let iconFormat = UIGraphicsImageRendererFormat()
        iconFormat.scale = 1
        iconFormat.opaque = false
        let icon = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18), format: iconFormat).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 3, y: 3, width: 12, height: 12))
        }.withRenderingMode(.alwaysOriginal)
        XCTAssertEqual(try maximumAlpha(icon), 255)
        _ = group.update(items: [
            .init(id: "first", content: .icon(icon), action: nil),
            .init(id: "second", content: .icon(icon), action: {})
        ], transition: .immediate)
        group.frame.origin = CGPoint(x: 280, y: 70)
        group.alpha = 0.8
        group.layoutIfNeeded()
        let button = try XCTUnwrap(group.itemButton(id: "second"))
        let descriptor = try XCTUnwrap(ContextMenuSourceDescriptor(sourceID: "second", hitView: button,
            visualView: group, overlayView: root, sourceCornerRadius: 22, sourceMode: .leasedGlassSource))
        let lease = try XCTUnwrap(SourcePresentationLease(sourceID: "second", descriptor: descriptor, overlayView: root))
        XCTAssertEqual(lease.sourceFrameInOverlay, group.frame)
        XCTAssertEqual(lease.sourceContentRegions.map(\.frame), regions.map(\.frame))
        let image = try XCTUnwrap(AetherContentMaterialization.captureContent(of: lease.proxyView, preservingRootOpacity: true))
        let snapshots = contextMenuSharedSourceSnapshots(image: image, regions: lease.sourceContentRegions)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(try maximumAlpha(snapshots[0].image), 102, accuracy: 2)
        XCTAssertEqual(try maximumAlpha(snapshots[1].image), 204, accuracy: 2)
        lease.acquire()
        XCTAssertEqual(group.alpha, 0)
        lease.release()
        XCTAssertEqual(group.alpha, 0.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(group.itemButton(id: "first")).alpha, 0.5)

        for items: [GlassControlGroup.Item] in [
            [.init(id: "single", content: .icon(icon), action: {})],
            [.init(id: "text", content: .text("A long caption"), action: {})],
            [.init(id: "icon", content: .icon(icon), action: {}),
             .init(id: "text", content: .text("Caption"), action: {})],
            [.init(id: "icon", content: .icon(icon), action: {}),
             .init(id: "custom", content: .customView(UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))), action: {})]
        ] {
            _ = group.update(items: items, transition: .immediate)
            XCTAssertTrue(group.contextMenuPresentationContentRegions.isEmpty)
        }
    }

    func testRegionClockHasGradualStaggerAndFocusesBeforeEndOfClose() {
        let first = contextMenuSharedSourceMaterializationSample(elapsed: 0.30, regionIndex: 0, reduceMotion: false)
        let second = contextMenuSharedSourceMaterializationSample(elapsed: 0.30, regionIndex: 1, reduceMotion: false)
        XCTAssertGreaterThan(first.opacity, second.opacity)
        XCTAssertGreaterThan(second.opacity, 0)
        XCTAssertLessThan(first.opacity, 1)
        XCTAssertLessThan(first.blurRadius, second.blurRadius)
        for index in 0...1 {
            var previous = contextMenuSharedSourceMaterializationSample(elapsed: 0, regionIndex: index, reduceMotion: false)
            var intermediateFrames = 0
            for frame in 1...120 {
                let sample = contextMenuSharedSourceMaterializationSample(elapsed: CGFloat(frame) / 120,
                    regionIndex: index, reduceMotion: false)
                XCTAssertGreaterThanOrEqual(sample.opacity, previous.opacity)
                XCTAssertLessThanOrEqual(sample.blurRadius, previous.blurRadius)
                XCTAssertLessThan(sample.opacity - previous.opacity, 0.09)
                if sample.opacity > 0.05 && sample.opacity < 0.95 { intermediateFrames += 1 }
                previous = sample
            }
            XCTAssertGreaterThan(intermediateFrames, 10)
            let focused = contextMenuSharedSourceMaterializationSample(elapsed: 0.5, regionIndex: index, reduceMotion: false)
            XCTAssertEqual(focused.opacity, 1)
            XCTAssertEqual(focused.blurRadius, 0)
        }
    }

    func testReduceMotionRemovesRegionalDelayAndBlur() {
        for frame in 0...120 {
            let first = contextMenuSharedSourceMaterializationSample(elapsed: CGFloat(frame) / 120,
                regionIndex: 0, reduceMotion: true)
            let last = contextMenuSharedSourceMaterializationSample(elapsed: CGFloat(frame) / 120,
                regionIndex: 4, reduceMotion: true)
            XCTAssertEqual(first, last)
            XCTAssertEqual(first.blurRadius, 0)
        }
    }

    func testCoverageUsesDisplayedSourceTranslationAndHeadRotation() {
        let bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        let ink = CGRect(x: 3, y: 12, width: 38, height: 20)
        let head = CGRect(x: 100, y: 200, width: 80, height: 30)
        let center = CGPoint(x: head.midX, y: head.midY)
        let rotation = CGFloat.pi / 3
        func coverage(_ transform: CGAffineTransform, _ angle: CGFloat) -> CGFloat {
            contextMenuSharedSourceCoverage(alphaBounds: ink, sourceBounds: bounds, sourceCenter: center,
                sourceTransform: transform, headFrame: head, headRadius: 12, headRotation: angle)
        }
        XCTAssertEqual(coverage(.identity, 0), 1)
        XCTAssertGreaterThan(coverage(.identity, rotation), 0)
        XCTAssertLessThan(coverage(.identity, rotation), 1)
        XCTAssertEqual(coverage(CGAffineTransform(rotationAngle: rotation), rotation), 1)
        XCTAssertEqual(coverage(CGAffineTransform(translationX: 80, y: 0), 0), 0)
        XCTAssertEqual(contextMenuSharedSourceCoverage(alphaBounds: ink, sourceBounds: bounds,
            sourceCenter: CGPoint(x: center.x + 12, y: center.y - 7),
            sourceTransform: CGAffineTransform(translationX: -12, y: 7),
            headFrame: head, headRadius: 12, headRotation: 0), 1)
    }

    func testCoverageGraduallyRevealsPartialOverlapWithoutAnAllCornersGate() {
        let bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        let ink = CGRect(x: 1, y: 10, width: 42, height: 20)
        func coverage(_ x: CGFloat) -> CGFloat {
            contextMenuSharedSourceCoverage(alphaBounds: ink, sourceBounds: bounds,
                sourceCenter: CGPoint(x: 22, y: 22), sourceTransform: CGAffineTransform(translationX: x, y: 0),
                headFrame: bounds, headRadius: 0, headRotation: 0)
        }
        XCTAssertEqual(coverage(0), 1)
        XCTAssertGreaterThan(coverage(20), 0.25)
        XCTAssertLessThan(coverage(20), 0.75)
        XCTAssertEqual(coverage(44), 0)
        var previous = coverage(0)
        for step in 1...440 {
            let value = coverage(CGFloat(step) / 10)
            XCTAssertLessThanOrEqual(value, previous)
            XCTAssertLessThan(previous - value, 0.025)
            previous = value
        }
    }

    func testHostKeepsGlyphSizeFixedWhileClosingSpacingContractsAndOrderMirrors() throws {
        for trailing in [false, true] {
            let fixture = try makeHost(trailing: trailing)
            defer { fixture.host.tearDownGlassEffects(); fixture.window.isHidden = true }
            let host = fixture.host
            XCTAssertTrue(host.hasSharedSourceContent)
            let original = host.sharedSourceContentForTesting
            XCTAssertEqual(original.count, 2)
            XCTAssertEqual(original[0].frame.minX, trailing ? 0 : 44)
            var minimumClosingSpacing: CGFloat = 44
            for direction in [ContextMenuBloomDirection.opening, .closing] {
                for frame in 0...60 {
                    host.setProgress(CGFloat(frame) / 60, direction: direction)
                    let current = host.sharedSourceContentForTesting
                    XCTAssertEqual(current.map { $0.bounds }, original.map { $0.bounds })
                    for (before, after) in zip(original, current) {
                        XCTAssertEqual(after.frame.size, before.frame.size)
                        XCTAssertEqual(after.alphaBounds.size, before.alphaBounds.size)
                    }
                    if direction == .opening {
                        XCTAssertEqual(current.map { $0.frame }, original.map { $0.frame })
                        XCTAssertEqual(current[0].opacity, current[1].opacity)
                        XCTAssertEqual(current[0].blurRadius, 0)
                        XCTAssertEqual(current[1].blurRadius, 0)
                    } else {
                        let spacing = abs(current[0].frame.midX - current[1].frame.midX)
                        XCTAssertLessThanOrEqual(spacing, 44.000001)
                        minimumClosingSpacing = min(minimumClosingSpacing, spacing)
                    }
                }
            }
            if #available(iOS 26.0, *) {
                XCTAssertLessThan(minimumClosingSpacing, 43)
            }
            host.setProgress(0, direction: .closing)
            XCTAssertEqual(host.sharedSourceContentForTesting.map { $0.frame }, original.map { $0.frame })
        }
    }

    func testPartiallyRevealedClosingGlyphsKeepTheActualGlassMask() throws {
        guard #available(iOS 26.0, *) else { return }
        for trailing in [false, true] {
            let fixture = try makeHost(trailing: trailing)
            defer { fixture.host.tearDownGlassEffects(); fixture.window.isHidden = true }
            let host = fixture.host
            var visibleFrames = 0
            var partiallyClippedFrames = 0
            for frame in 0...120 {
                host.setProgress(1 - CGFloat(frame) / 120, direction: .closing)
                let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
                let paths = (mask.sublayers ?? []).filter { !$0.isHidden }.compactMap { ($0 as? CAShapeLayer)?.path }
                for region in host.sharedSourceContentForTesting where region.opacity > 0.01 {
                    visibleFrames += 1
                    var inside = 0
                    for column in 0..<7 {
                        for row in 0..<7 {
                            let x = region.alphaBounds.minX + (CGFloat(column) + 0.5) * region.alphaBounds.width / 7
                            let y = region.alphaBounds.minY + (CGFloat(row) + 0.5) * region.alphaBounds.height / 7
                            let point = host.sourceProxyContainer.convert(CGPoint(x: x, y: y), to: host)
                            if paths.contains(where: { $0.contains(point) }) { inside += 1 }
                        }
                    }
                    XCTAssertGreaterThan(inside, 0, "A visible glyph must intersect the actual glass")
                    if inside < 49 { partiallyClippedFrames += 1 }
                }
            }
            XCTAssertGreaterThan(visibleFrames, 0)
            XCTAssertGreaterThan(partiallyClippedFrames, 0,
                "Shared icons should emerge through the attached silhouette mask before their whole bounds fit")
            XCTAssertTrue(host.sharedSourceContentForTesting.allSatisfy { $0.opacity == 1 && $0.blurRadius == 0 })
        }
    }

    func testLegacySharedSourceRetainsTheSinglePlatterAndReturnsGlyphsBeforeCleanup() throws {
        let fixture = try makeHost(trailing: true, appearance: .legacy)
        defer { fixture.host.tearDownGlassEffects(); fixture.window.isHidden = true }
        let host = fixture.host
        XCTAssertTrue(host.hasSharedSourceContent)
        XCTAssertFalse(host.supportsSharedSourceReturn)
        let source = host.sourceProxyContainer.frame
        let target = CGRect(x: 113, y: 70, width: 255, height: 378)
        let originalFrames = host.sharedSourceContentForTesting.map { $0.frame }
        for progress: CGFloat in [1, 0.8, 0.5, 0.3, 0.1, 0.02] {
            host.setProgress(progress, direction: .closing)
            let expected = contextMenuBloomGeometrySample(source: source, target: target,
                sourceRadius: 22, targetRadius: 27, anchor: .topTrailing, direction: .closing,
                rawProgress: progress, reduceMotion: false)
            let actual = host.finalMenuGlassSurfaceView.frame
            XCTAssertEqual(actual.minX, expected.frame.minX, accuracy: 0.000001)
            XCTAssertEqual(actual.minY, expected.frame.minY, accuracy: 0.000001)
            XCTAssertEqual(actual.width, expected.frame.width, accuracy: 0.000001)
            XCTAssertEqual(actual.height, expected.frame.height, accuracy: 0.000001)
            XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
            XCTAssertEqual(host.sharedSourceContentForTesting.map { $0.frame }, originalFrames)
        }
        // The host is still presented at a nonzero progress. A tiny body-only
        // mask previously withheld the returning source until final cleanup.
        XCTAssertNotNil(host.superview)
        XCTAssertFalse(host.sourceProxyContainer.isHidden)
        XCTAssertTrue(host.sharedSourceContentForTesting.allSatisfy { $0.opacity == 1 && $0.blurRadius == 0 })
        let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
        let paths = (mask.sublayers ?? []).filter { !$0.isHidden }.compactMap { ($0 as? CAShapeLayer)?.path }
        for region in host.sharedSourceContentForTesting {
            let center = CGPoint(x: region.alphaBounds.midX, y: region.alphaBounds.midY)
            let point = host.sourceProxyContainer.convert(center, to: host)
            XCTAssertTrue(paths.contains { $0.contains(point) })
        }
    }

    func testInterruptedClosingPreservesEachDisplayedGlyphAndInstantCloseRestoresPixels() throws {
        let fixture = try makeHost(trailing: true)
        defer { fixture.host.tearDownGlassEffects(); fixture.window.isHidden = true }
        let host = fixture.host
        for direction in [ContextMenuBloomDirection.opening, .closing] {
            for progress: CGFloat in [0.06, 0.13, 0.30, 0.55, 0.74, 0.93] {
                host.setProgress(progress, direction: direction)
                let previous = host.sharedSourceContentForTesting
                host.animateCollapse(duration: 0.54, damping: 0.9)
                let next = host.sharedSourceContentForTesting
                for (before, after) in zip(previous, next) {
                    XCTAssertEqual(after.opacity, before.opacity, accuracy: 0.000001)
                    XCTAssertEqual(after.blurRadius, before.blurRadius, accuracy: 0.000001)
                    XCTAssertEqual(after.frame, before.frame)
                }
                host.cancelOrDismiss()
                XCTAssertFalse(host.sourceProxyContainer.isHidden)
                XCTAssertTrue(host.sharedSourceContentForTesting.allSatisfy { $0.opacity == 1 && $0.blurRadius == 0 })
            }
        }
    }

    private var regions: [ContextMenuSourceContentRegion] {
        [ContextMenuSourceContentRegion(frame: CGRect(x: 0, y: 0, width: 44, height: 44)),
         ContextMenuSourceContentRegion(frame: CGRect(x: 44, y: 0, width: 44, height: 44))]
    }

    private func markerImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 88, height: 44), format: format).image { context in
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.4).cgColor)
            context.cgContext.fill(CGRect(x: 15, y: 9, width: 10, height: 16))
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.8).cgColor)
            context.cgContext.fill(CGRect(x: 60, y: 15, width: 12, height: 6))
        }
    }

    private func maximumAlpha(_ image: UIImage) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return Double(stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0)
    }

    private func makeHost(trailing: Bool, appearance: AetherAppearanceStyle = .liquidGlassV1) throws
        -> (window: UIWindow, host: ContextMenuGlassmorphicTransitionView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let source = CGRect(x: trailing ? 280 : 18, y: 70, width: 88, height: 44)
        let target = CGRect(x: trailing ? 113 : 18, y: 70, width: 255, height: 378)
        let host = ContextMenuGlassmorphicTransitionView(sourceFrameInOverlay: source, targetMenuFrameInOverlay: target,
            finalCornerRadius: 27, sourceCornerRadius: 22, sourceMode: .leasedGlassSource,
            isDark: false, appearanceStyle: appearance)
        host.frame = window.bounds
        window.rootViewController!.view.addSubview(host)
        host.layoutIfNeeded()
        let imageView = UIImageView(image: markerImage())
        imageView.frame = host.sourceProxyContainer.bounds
        host.sourceProxyContainer.addSubview(imageView)
        window.layoutIfNeeded()
        window.rootViewController!.view.layoutIfNeeded()
        // Commit the fixture's window/layout before inspecting animated masks.
        CATransaction.flush()
        host.prepareSourceContentSnapshots(regions: regions)
        _ = try XCTUnwrap(host.sharedSourceContentForTesting.count == 2 ? host : nil,
            "A shared source must capture both transparent glyph regions")
        return (window, host)
    }
}
