import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class ContextMenuInterruptionTests: XCTestCase {
    func testDisplayClockDoesNotSkipLiquidPhaseAfterStallAndCompletesOnce() {
        let host = makeHost(appearance: .legacy)
        defer { host.tearDownGlassEffects() }
        var completions = 0
        host.animateExpand(duration: 0.42, damping: 0.86) { completions += 1 }
        host.advanceAnimation(to: 1)
        host.advanceAnimation(to: 2)
        XCTAssertEqual(completions, 0, "A delayed callback must not jump straight to the menu")
        for frame in 1...60 { host.advanceAnimation(to: 2 + Double(frame) / 120) }
        XCTAssertEqual(completions, 1)
        host.advanceAnimation(to: 4)
        XCTAssertEqual(completions, 1)
    }

    func testWideButtonCollapseKeepsConnectedDropAndRetractsUnderSource() {
        let source = CGRect(x: 220, y: 70, width: 160, height: 44)
        let target = CGRect(x: 125, y: 70, width: 255, height: 470)
        let anchor = ContextMenuBloomAnchor.detect(source: source, target: target)
        var previous: CGRect?
        for step in 1..<420 {
            let t = CGFloat(step) / 420
            let outer = contextMenuBloomGeometrySample(source: source, target: target,
                sourceRadius: 22, targetRadius: 27, anchor: anchor, direction: .closing,
                rawProgress: 1-t, reduceMotion: false)
            let sample = contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: outer.frame, outerCornerRadii: outer.cornerRadii,
                sourceRadius: 22, targetRadius: 27, anchor: anchor, direction: .closing,
                rawProgress: 1-t, reduceMotion: false)
            if sample.headAlpha > 0.001 {
                XCTAssertTrue(sample.headFrame.intersects(sample.bodyFrame), "The returning shoulder must stay joined to the drop")
            }
            XCTAssertEqual(sample.bridgeRadius, 0)
            XCTAssertEqual(sample.bodyAlpha, 1)
            if let previous {
                XCTAssertLessThan(abs(sample.bodyFrame.minY-previous.minY), 6)
                XCTAssertLessThan(abs(sample.bodyFrame.height-previous.height), 8)
            }
            if t > 0.98 {
                XCTAssertEqual(sample.headFrame, source)
                XCTAssertTrue(source.contains(sample.bodyFrame))
            }
            previous = sample.bodyFrame
        }
    }

    func testOpeningReversesClosingForEverySurfaceAndAnchor() {
        for width: CGFloat in [44, 106, 160, 240] {
            for height: CGFloat in [160, 470] {
                for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 1)] {
                    let anchor = ContextMenuBloomAnchor(unitPoint: unit)
                    let source = CGRect(x: 40, y: 70, width: width, height: 44)
                    let target = CGRect(x: 40 - (255-width)*unit.x,
                        y: 70 - (height-44)*unit.y, width: 255, height: height)
                    for frame in 0...120 {
                        let raw = CGFloat(frame) / 120
                        func sample(_ direction: ContextMenuBloomDirection) -> ContextMenuGlassmorphicGeometrySample {
                            let outer = contextMenuBloomGeometrySample(source: source, target: target,
                                sourceRadius: 22, targetRadius: 27, anchor: anchor,
                                direction: direction, rawProgress: raw, reduceMotion: false)
                            return contextMenuGlassmorphicGeometrySample(source: source, target: target,
                                outerFrame: outer.frame, outerCornerRadii: outer.cornerRadii,
                                sourceRadius: 22, targetRadius: 27, anchor: anchor,
                                direction: direction, rawProgress: raw, reduceMotion: false)
                        }
                        XCTAssertEqual(sample(.opening), sample(.closing))
                    }
                }
            }
        }
    }

    func testOpeningReversesRenderedContentWithoutIndependentGlyphZoom() throws {
        for appearance in AetherAppearanceStyle.allCases {
            let host = makeHost(appearance: appearance)
            defer { host.tearDownGlassEffects() }
            for frame in 0...60 {
                let raw = CGFloat(frame) / 60
                host.setProgress(raw, direction: .opening)
                let views = try menuContentViews(in: host) + [host.sourceProxyContainer, host.finalMenuGlassSurfaceView]
                let opening = views.map(ViewRendering.init)
                host.setProgress(raw, direction: .closing)
                for (view, expected) in zip(views, opening) { assertRendering(view, equals: expected) }
            }
        }
    }

    func testClosingContractionStartsOnTheFirstReferenceFrameAndReboundsFromSourceSizedEgg() {
        let source = CGRect(x: 18, y: 70, width: 106, height: 44)
        let target = CGRect(x: 18, y: 70, width: 230, height: 160)
        func sample(_ milliseconds: CGFloat) -> ContextMenuBloomGeometrySample {
            contextMenuBloomGeometrySample(
                source: source, target: target, sourceRadius: 22, targetRadius: 27,
                anchor: .detect(source: source, target: target), direction: .closing,
                rawProgress: 1.0 - milliseconds / 320.0, reduceMotion: false
            )
        }

        // Tolerances describe the measured silhouette, not exact spline knots.
        XCTAssertEqual(sample(17).frame.width / target.width, 0.85, accuracy: 0.025)
        XCTAssertEqual(sample(42).frame.width / target.width, 0.78, accuracy: 0.025)
        XCTAssertEqual(sample(75).frame.width / target.width, 0.66, accuracy: 0.025)
        XCTAssertEqual(sample(109).frame.width / target.width, 0.43, accuracy: 0.025)
        XCTAssertEqual(sample(142).frame.width / target.width, 0.35, accuracy: 0.025)
        XCTAssertLessThan(sample(17).frame.height, target.height)
        XCTAssertGreaterThan(sample(109).frame.height, source.height)
        XCTAssertLessThan(sample(175).frame.width, source.width)
        XCTAssertGreaterThan(sample(242).frame.width, sample(175).frame.width)
        XCTAssertEqual(sample(320).frame, source)

        for sourceWidth: CGFloat in [32, 44, 94, 150] {
            for frame in 0...38 {
                let geometry = contextMenuBloomGeometrySample(
                    source: CGRect(x: 18, y: 70, width: sourceWidth, height: 44),
                    target: target, sourceRadius: 22, targetRadius: 27,
                    anchor: .init(unitPoint: CGPoint(x: 0, y: 0)), direction: .closing,
                    rawProgress: 1 - CGFloat(frame) / 38, reduceMotion: false
                )
                XCTAssertGreaterThanOrEqual(geometry.frame.width, sourceWidth * 0.70)
                XCTAssertGreaterThanOrEqual(geometry.frame.height, 44)
            }
        }
    }

    func testClosingStartsFromTheRenderedOpeningContentAtEveryHandoff() throws {
        // Exercise invisible rows, the compressed blurred snapshot, the
        // sharp/live handoff and a nearly completed opening. A direction
        // change must preserve the actual views, not resample another curve.
        for appearance in AetherAppearanceStyle.allCases {
            for progress: CGFloat in [0.12, 0.40, 0.64, 0.78, 0.95] {
                let host = makeHost(appearance: appearance)
                defer { host.tearDownGlassEffects() }
                var reveal: CGFloat = 0
                host.contentRevealProgressChanged = { reveal = $0 }
                host.setProgress(progress)
                let contentViews = try menuContentViews(in: host)
                let before = contentViews.map(ViewRendering.init)
                let source = ViewRendering(host.sourceProxyContainer)
                let surfaceBounds = host.finalMenuGlassSurfaceView.bounds
                let surfaceCenter = host.finalMenuGlassSurfaceView.center
                let initialReveal = reveal

                host.animateCollapse(duration: 100, damping: 1)
                // Re-layout synchronously before the driver advances: this
                // is the first rendered close frame at exactly the reversal.
                host.layoutSubviews()

                for (view, rendering) in zip(contentViews, before) {
                    assertRendering(view, equals: rendering)
                }
                assertRendering(host.sourceProxyContainer, equals: source)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds, surfaceBounds)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.center, surfaceCenter)
                XCTAssertEqual(reveal, initialReveal, accuracy: 0.000001)
            }
        }
    }

    func testTallMenuKeepsItsMeasuredRoundedBodyAndDownwardTravelWhileClosing() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        // Raw reference: source68px, menu378×577px. Body measurements are
        // separate from the head/neck envelope once those become visible.
        let reference: [(elapsed: CGFloat, width: CGFloat, height: CGFloat, drop: CGFloat)] = [
            (0.156, 312, 454, 88), (0.260, 249, 339, 96),
            (0.363, 185, 240, 81), (0.469, 132, 165, 58),
            (0.572, 89, 108, 45), (0.675, 58, 59, 43)
        ]
        for frame in reference {
            let outer = contextMenuBloomGeometrySample(
                source: source, target: target, sourceRadius: 22.5, targetRadius: 27,
                anchor: .topTrailing, direction: .closing,
                rawProgress: 1 - frame.elapsed, reduceMotion: false
            )
            let shape = contextMenuGlassmorphicGeometrySample(
                source: source, target: target, outerFrame: outer.frame, outerCornerRadii: outer.cornerRadii,
                sourceRadius: 22.5, targetRadius: 27, anchor: .topTrailing, direction: .closing,
                rawProgress: 1 - frame.elapsed, reduceMotion: false
            )
            let measuredBody = shape.bodyFrame
            XCTAssertEqual(measuredBody.width, frame.width * 255 / 378, accuracy: 3)
            XCTAssertEqual(measuredBody.height, frame.height * 378 / 577, accuracy: 3)
            XCTAssertEqual(measuredBody.minY - source.minY, frame.drop * 378 / 577, accuracy: 3)
            XCTAssertLessThan(shape.bodyFrame.height / shape.bodyFrame.width, 2,
                              "The filter menu collapsed into a tall narrow pillar")
        }
    }

    func testInterruptedClosingOnlyDissolvesAlreadyVisibleRowsAndCompletesOnce() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let host = makeHost(appearance: .legacy)
        window.rootViewController?.view.addSubview(host)
        defer {
            host.tearDownGlassEffects()
            window.isHidden = true
        }
        var samples: [CGFloat] = []
        host.contentRevealProgressChanged = { samples.append($0) }
        host.setProgress(0.68)
        let originalReveal = try XCTUnwrap(samples.last)
        XCTAssertGreaterThan(originalReveal, 0)
        XCTAssertLessThan(originalReveal, 1)

        let completion = expectation(description: "Interrupted collapse finishes")
        var completionCount = 0
        host.animateCollapse(duration: 0.12, damping: 1) {
            completionCount += 1
            completion.fulfill()
        }
        wait(for: [completion], timeout: 2)

        for (previous, next) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(next, previous + 0.000001)
        }
        XCTAssertEqual(try XCTUnwrap(samples.last), 0, accuracy: 0.000001)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(host.sourceProxyContainer.alpha, 1, accuracy: 0.000001)
        XCTAssertFalse(host.sourceProxyContainer.isHidden)
        XCTAssertEqual(host.liveMenuContentView.alpha, 0, accuracy: 0.000001)
        let snapshots = try menuContentViews(in: host).dropLast()
        XCTAssertTrue(snapshots.allSatisfy { $0.alpha == 0 })
    }

    func testRepeatedLayoutDoesNotResizeTransformedSnapshotContents() throws {
        let host = makeHost(appearance: .legacy)
        defer { host.tearDownGlassEffects() }
        host.setProgress(0.68)
        let views = try menuContentViews(in: host)
        let before = views.map(ViewRendering.init)

        for _ in 0..<4 { host.layoutSubviews() }

        for (view, rendering) in zip(views, before) {
            assertRendering(view, equals: rendering)
        }
    }

    func testReturningSourceMaskHasNoHolesWhereNativeLobesOverlap() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native merged glass requires iOS 26") }
        let host = makeHost(appearance: .liquidGlassV1, sourceWidth: 44)
        defer { host.tearDownGlassEffects() }
        var checkedPixels = 0
        var mismatchedPixels = 0
        var firstMismatch: CGPoint?
        for progress: CGFloat in [0.60, 0.50, 0.40, 0.30, 0.20] {
            host.setProgress(progress, direction: .closing)
            let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
            let paths = (mask.sublayers ?? []).compactMap { ($0 as? CAShapeLayer)?.path }
            let width = Int(ceil(mask.bounds.width))
            let height = Int(ceil(mask.bounds.height))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                // CALayer renders in Quartz's bottom-left bitmap coordinates;
                // sample the result in the host's UIKit top-left coordinates.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                mask.render(in: context)
            }
            let glyphArea = host.sourceProxyContainer.frame.insetBy(dx: 12, dy: 12)
            for y in stride(from: Int(glyphArea.minY), to: Int(glyphArea.maxY), by: 2) {
                for x in stride(from: Int(glyphArea.minX), to: Int(glyphArea.maxX), by: 2) {
                    let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    let interior = [
                        CGPoint(x: point.x - 1, y: point.y), CGPoint(x: point.x + 1, y: point.y),
                        CGPoint(x: point.x, y: point.y - 1), CGPoint(x: point.x, y: point.y + 1)
                    ]
                    guard paths.filter({ path in interior.allSatisfy { path.contains($0) } }).count >= 2 else { continue }
                    checkedPixels += 1
                    if pixels[(y * width + x) * 4 + 3] <= 240 {
                        mismatchedPixels += 1
                        firstMismatch = firstMismatch ?? point
                    }
                }
            }
        }
        XCTAssertGreaterThan(checkedPixels, 0, "The native close must exercise the source/body overlap")
        XCTAssertEqual(mismatchedPixels, 0,
                       "Mask holes: \(mismatchedPixels)/\(checkedPixels) pixels, first \(String(describing: firstMismatch))")
    }

    func testFallbackSourceMaskMatchesTheRenderedPlatter() throws {
        let host = makeHost(appearance: .legacy)
        defer { host.tearDownGlassEffects() }
        host.setProgress(0.60, direction: .closing)
        let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
        let path = try XCTUnwrap((mask.sublayers?.first as? CAShapeLayer)?.path)
        let surface = host.finalMenuGlassSurfaceView
        let renderedFrame = surface.convert(surface.bounds, to: host)
        let maskFrame = path.boundingBoxOfPath
        XCTAssertEqual(maskFrame.minX, renderedFrame.minX, accuracy: 0.000001)
        XCTAssertEqual(maskFrame.minY, renderedFrame.minY, accuracy: 0.000001)
        XCTAssertEqual(maskFrame.width, renderedFrame.width, accuracy: 0.000001)
        XCTAssertEqual(maskFrame.height, renderedFrame.height, accuracy: 0.000001)
    }

    func testSourceCaptionKeepsItsNaturalSizeInBothDirections() {
        for appearance in AetherAppearanceStyle.allCases {
            for width: CGFloat in [94, 160, 240] {
                let host = makeHost(appearance: appearance, menuHeight: 160, sourceWidth: width)
                defer { host.tearDownGlassEffects() }
                for direction in [ContextMenuBloomDirection.opening, .closing] {
                    for frame in 0...120 {
                        host.setProgress(CGFloat(frame) / 120, direction: direction)
                        let source = host.sourceProxyContainer
                        XCTAssertEqual(source.transform.a, 1)
                        XCTAssertEqual(source.transform.d, 1)
                        XCTAssertEqual(source.transform.b, 0)
                        XCTAssertEqual(source.transform.c, 0)
                        XCTAssertEqual(source.bounds.size, CGSize(width: width, height: 44))
                    }
                }
            }
        }
    }

    func testFluidClockSettlesWithoutReversingMaterialization() {
        var previous: CGFloat = 0
        var previousOverscale: CGFloat = 0
        var maximum: CGFloat = 0
        for frame in 0...1000 {
            let t = CGFloat(frame) / 1000
            let sample = contextMenuLiquidAnimationSample(fraction: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(sample.progress, previous)
            XCTAssertLessThanOrEqual(sample.progress, 1)
            XCTAssertLessThan(abs(sample.rebound), 0.025)
            if t <= 0.66 || t == 1 { XCTAssertEqual(sample.rebound, 0) }
            XCTAssertGreaterThanOrEqual(sample.rebound, 0)
            if t <= 0.80 {
                XCTAssertGreaterThanOrEqual(sample.rebound, previousOverscale)
            } else {
                XCTAssertLessThanOrEqual(sample.rebound, previousOverscale)
            }
            previousOverscale = sample.rebound
            maximum = max(maximum, sample.rebound)
            previous = sample.progress
            XCTAssertEqual(contextMenuLiquidAnimationSample(fraction: t, reduceMotion: true).rebound, 0)
        }
        XCTAssertGreaterThan(maximum, 0.015)
        // No velocity jump when the main travel hands off to the spring.
        let epsilon: CGFloat = 0.0001
        XCTAssertLessThan(contextMenuLiquidAnimationSample(fraction: epsilon, reduceMotion: false).progress / epsilon, 0.001)
        XCTAssertLessThan((1 - contextMenuLiquidAnimationSample(fraction: 0.80 - epsilon, reduceMotion: false).progress) / epsilon, 0.001)
        XCTAssertLessThan(abs(contextMenuLiquidAnimationSample(fraction: 1 - epsilon, reduceMotion: false).rebound) / epsilon, 0.001)
    }

    func testDisplayClockOverspringsOnlyGlassAndKeepsTheLastFrameOnReversal() throws {
        for appearance in AetherAppearanceStyle.allCases {
            let host = makeHost(appearance: appearance, menuHeight: 160, sourceWidth: 160)
            defer { host.tearDownGlassEffects() }
            host.animateExpand(duration: 0.52, damping: 0.86)
            host.advanceAnimation(to: 1)
            // 425 ms is in the terminal recoil, after the content has arrived.
            for frame in 1...51 { host.advanceAnimation(to: 1 + Double(frame) / 120) }
            XCTAssertGreaterThan(host.finalMenuGlassSurfaceView.bounds.height, 160)
            XCTAssertLessThan(host.finalMenuGlassSurfaceView.bounds.height, 164)
            XCTAssertEqual(host.liveMenuContentView.transform, .identity)
            XCTAssertEqual(host.sourceProxyContainer.transform.a, 1)
            let views = try menuContentViews(in: host) + [host.sourceProxyContainer, host.finalMenuGlassSurfaceView]
            let before = views.map(ViewRendering.init)
            var completions = 0
            host.animateCollapse(duration: 0.52, damping: 0.90) { completions += 1 }
            for (view, expected) in zip(views, before) { assertRendering(view, equals: expected) }
            host.advanceAnimation(to: 2)
            for frame in 1...64 {
                host.advanceAnimation(to: 2 + Double(frame) / 120)
                XCTAssertEqual(host.sourceProxyContainer.transform.a, 1)
                XCTAssertEqual(host.sourceProxyContainer.transform.d, 1)
                if frame == 51 {
                    let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
                    let paths = (mask.sublayers ?? []).filter { !$0.isHidden }
                        .compactMap { ($0 as? CAShapeLayer)?.path }
                    let outline = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
                    XCTAssertGreaterThan(outline.width, 160)
                    XCTAssertGreaterThan(outline.height, 44)
                    XCTAssertLessThan(outline.height, 45)
                    XCTAssertEqual(outline.width / 160, outline.height / 44, accuracy: 0.000001)
                }
            }
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
            XCTAssertEqual(host.sourceProxyContainer.frame, CGRect(x: 18, y: 70, width: 160, height: 44))
            host.advanceAnimation(to: 4)
            XCTAssertEqual(completions, 1)
        }
    }

    private func makeHost(appearance: AetherAppearanceStyle, menuHeight: CGFloat = 380, sourceWidth: CGFloat = 94) -> ContextMenuGlassmorphicTransitionView {
        let host = ContextMenuGlassmorphicTransitionView(
            sourceFrameInOverlay: CGRect(x: 18, y: 70, width: sourceWidth, height: 44),
            targetMenuFrameInOverlay: CGRect(x: 18, y: 70, width: 255, height: menuHeight),
            finalCornerRadius: 27, sourceCornerRadius: 22,
            sourceMode: .leasedGlassSource, isDark: false, appearanceStyle: appearance
        )
        host.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.layoutIfNeeded()
        return host
    }

    private func menuContentViews(in host: ContextMenuGlassmorphicTransitionView) throws -> [UIView] {
        let snapshots = try XCTUnwrap(host.finalMenuGlassSurfaceView.contentView.subviews.first {
            $0.subviews.filter { $0 is UIImageView }.count == 2
        })
        return [snapshots] + snapshots.subviews.filter { $0 is UIImageView } + [host.liveMenuContentView]
    }

    private struct ViewRendering {
        let alpha: CGFloat
        let transform: CGAffineTransform
        let bounds: CGRect
        let center: CGPoint

        init(_ view: UIView) {
            alpha = view.alpha
            transform = view.transform
            bounds = view.bounds
            center = view.center
        }
    }

    private func assertRendering(_ view: UIView, equals expected: ViewRendering, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(view.alpha, expected.alpha, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(view.transform, expected.transform, file: file, line: line)
        XCTAssertEqual(view.bounds, expected.bounds, file: file, line: line)
        XCTAssertEqual(view.center, expected.center, file: file, line: line)
    }
}
