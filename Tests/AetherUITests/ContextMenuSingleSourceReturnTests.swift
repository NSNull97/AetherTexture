import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class ContextMenuSingleSourceReturnTests: XCTestCase {
    func testSingleReturnHasOneMirroredPeakAndNoDownwardPreDip() {
        let anchor = ContextMenuBloomAnchor.topTrailing
        var previous: CGFloat = 0
        for index in 0...1000 {
            let fraction = CGFloat(index) / 1000
            let offset = ContextMenuSingleSourceReturn.sourceOffset(fraction: fraction, height: 44, anchor: anchor)
            XCTAssertLessThanOrEqual(offset, 0)
            XCTAssertGreaterThanOrEqual(offset, -7.040001)
            if fraction <= 0.14 { XCTAssertEqual(offset, 0) }
            if fraction <= 0.5 {
                XCTAssertLessThanOrEqual(offset, previous + 0.000001)
            } else {
                XCTAssertGreaterThanOrEqual(offset, previous - 0.000001)
            }
            let mirrored = ContextMenuSingleSourceReturn.sourceOffset(fraction: fraction, height: 44,
                anchor: .init(unitPoint: CGPoint(x: 1, y: 1)))
            XCTAssertEqual(mirrored, -offset, accuracy: 0.000001)
            previous = offset
        }
        XCTAssertEqual(ContextMenuSingleSourceReturn.sourceOffset(fraction: 0.5, height: 44, anchor: anchor),
            -7.04, accuracy: 0.000001)
        XCTAssertEqual(previous, 0)
    }

    func testSingleReturnBoundsSpeedAndAccelerationWithoutDwellingAtItsPeak() {
        let duration: CGFloat = 0.44
        let h: CGFloat = 0.00001
        func offset(_ time: CGFloat) -> CGFloat {
            ContextMenuSingleSourceReturn.sourceOffset(fraction: time / duration, height: 44, anchor: .topTrailing)
        }
        func velocity(_ time: CGFloat) -> CGFloat { (offset(time + h) - offset(time - h)) / (2 * h) }
        func acceleration(_ time: CGFloat) -> CGFloat {
            (offset(time + h) - 2 * offset(time) + offset(time - h)) / (h * h)
        }
        for index in 0...1000 {
            let time = duration * CGFloat(index) / 1000
            XCTAssertLessThan(abs(velocity(time)), 85, "A compact return must not snap through several pixels per frame")
            XCTAssertLessThan(abs(acceleration(time)), 1700)
        }
        for time in [duration * 0.14, duration] {
            XCTAssertEqual(velocity(time), 0, accuracy: 0.05)
            XCTAssertEqual(acceleration(time), 0, accuracy: 2)
        }
        XCTAssertEqual(velocity(duration * 0.5), 0, accuracy: 0.05)
        XCTAssertGreaterThan(acceleration(duration * 0.5), 1000,
            "A spring turn needs restoring acceleration; joining two eased halves would pause at the peak")
    }

    func testRoundAndCaptionSourcesRecoilOnBothEdgesAndFinishAtTheirOriginalPixels() throws {
        try requireNativeMotion()
        for width: CGFloat in [44, 160] {
            for bottom in [false, true] {
                let fixture = makeHost(width: width, bottom: bottom)
                let host = fixture.host
                defer { host.tearDownGlassEffects() }
                XCTAssertTrue(host.supportsSingleSourceReturn)
                let originalMarker = fixture.marker.convert(fixture.marker.bounds, to: host)
                var completions = 0
                host.setProgress(1)
                host.animateCollapse(duration: 0.44, damping: 0.9) { completions += 1 }
                host.advanceAnimation(to: 1)
                for frame in 1...101 {
                    host.advanceAnimation(to: 1 + 0.44 * Double(frame) / 100)
                    let source = host.sourceProxyContainer
                    XCTAssertEqual(source.bounds.size, fixture.source.size)
                    XCTAssertEqual(source.transform.a, 1)
                    XCTAssertEqual(source.transform.d, 1)
                    XCTAssertEqual(source.transform.b, 0)
                    XCTAssertEqual(source.transform.c, 0)
                    let marker = fixture.marker.convert(fixture.marker.bounds, to: host)
                    assertRect(marker, equals: originalMarker.offsetBy(dx: 0, dy: source.transform.ty))
                    if frame == 43 {
                        XCTAssertGreaterThan(source.transform.ty * (bottom ? 1 : -1), 5,
                            "The single source must visibly recoil, including a caption and a bottom anchor")
                        XCTAssertEqual(completions, 0)
                    }
                }
                XCTAssertEqual(completions, 1)
                XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
                assertRect(host.sourceProxyContainer.frame, equals: fixture.source)
                assertRect(fixture.marker.convert(fixture.marker.bounds, to: host), equals: originalMarker)
                XCTAssertFalse(host.sourceProxyContainer.isHidden)
                XCTAssertEqual(host.sourceProxyContainer.alpha, 1)
            }
        }
    }

    func testReturningGlassMaskAndNativeSizeContentShareTheSameTranslation() throws {
        try requireNativeMotion()
        for width: CGFloat in [44, 160] {
            for bottom in [false, true] {
                let fixture = makeHost(width: width, bottom: bottom)
                let host = fixture.host
                defer { host.tearDownGlassEffects() }
                for raw: CGFloat in [0.15, 0.08, 0.025] {
                    host.setProgress(raw, direction: .closing)
                    let base = geometry(source: fixture.source, target: fixture.target, raw: raw)
                    let fraction = contextMenuLiquidTime(forProgress: 1 - raw)
                    let anchor = ContextMenuBloomAnchor.detect(source: fixture.source, target: fixture.target)
                    let contentOffset = ContextMenuSingleSourceReturn.sourceOffset(
                        fraction: fraction, height: fixture.source.height, anchor: anchor)
                    let surfaceOffset = ContextMenuSingleSourceReturn.surfaceOffset(
                        fraction: fraction, source: fixture.source, head: base.headFrame, anchor: anchor)
                    XCTAssertGreaterThan(fraction, 0.42)
                    XCTAssertGreaterThan(abs(contentOffset), 0.01)
                    XCTAssertEqual(host.sourceProxyContainer.frame.midY - fixture.source.midY,
                        contentOffset, accuracy: 0.000001)
                    let paths = try maskPaths(in: host)
                    let head = try XCTUnwrap(paths.first).boundingBoxOfPath
                    XCTAssertEqual(head.midX, base.headFrame.midX, accuracy: 0.000001)
                    XCTAssertEqual(head.midY - base.headFrame.midY, surfaceOffset, accuracy: 0.000001)
                    XCTAssertEqual(head.midY, host.sourceProxyContainer.frame.midY, accuracy: 0.000001,
                        "The returning head and its caption must move together")
                    XCTAssertEqual(host.finalMenuGlassSurfaceView.center.x, base.bodyFrame.midX, accuracy: 0.000001)
                    XCTAssertEqual(host.finalMenuGlassSurfaceView.center.y - base.bodyFrame.midY, surfaceOffset, accuracy: 0.000001)
                    XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds.width, base.bodyFrame.width, accuracy: 0.000001,
                        "Translation must preserve the single-source closing silhouette")
                    XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds.height, base.bodyFrame.height, accuracy: 0.000001)
                    XCTAssertGreaterThan(host.sourceProxyContainer.alpha, 0.01)
                    let ink = fixture.marker.convert(fixture.marker.bounds, to: host).insetBy(dx: 0.5, dy: 0.5)
                    for x in [ink.minX, ink.midX, ink.maxX] {
                        for y in [ink.minY, ink.midY, ink.maxY] {
                            XCTAssertTrue(paths.contains { $0.contains(CGPoint(x: x, y: y)) },
                                "A returning glyph pixel must remain inside the translated glass mask")
                        }
                    }
                }
            }
        }
    }

    func testOpeningFallbackAndPersistentSourcesKeepTheirExistingGeometry() throws {
        try requireNativeMotion()
        for (appearance, mode, direction): (AetherAppearanceStyle, ContextMenuSourceVisualMode, ContextMenuBloomDirection) in [
            (.liquidGlassV1, .leasedGlassSource, .opening),
            (.legacy, .leasedGlassSource, .closing),
            (.liquidGlassV1, .persistentSource, .closing)
        ] {
            let fixture = makeHost(width: 160, appearance: appearance, mode: mode)
            let host = fixture.host
            defer { host.tearDownGlassEffects() }
            let effectiveSource = host.sourceProxyContainer.frame
            if mode == .persistentSource || appearance == .legacy {
                XCTAssertFalse(host.supportsSingleSourceReturn)
            }
            for raw: CGFloat in [0, 0.15, 0.4, 0.7, 1] {
                host.setProgress(raw, direction: direction)
                XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
                assertRect(host.sourceProxyContainer.frame, equals: effectiveSource)
                let expected: CGRect
                if appearance == .legacy {
                    expected = contextMenuBloomGeometrySample(source: effectiveSource, target: fixture.target,
                        sourceRadius: effectiveSource.height / 2, targetRadius: 27,
                        anchor: .detect(source: effectiveSource, target: fixture.target),
                        direction: direction, rawProgress: raw, reduceMotion: false).frame
                } else {
                    expected = geometry(source: effectiveSource, target: fixture.target,
                        raw: raw, direction: direction).bodyFrame
                }
                XCTAssertEqual(host.finalMenuGlassSurfaceView.center.x, expected.midX, accuracy: 0.000001)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.center.y, expected.midY, accuracy: 0.000001)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds.width, expected.width, accuracy: 0.000001)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds.height, expected.height, accuracy: 0.000001)
                if mode == .persistentSource { XCTAssertTrue(host.sourceProxyContainer.isHidden) }
            }
        }
    }

    func testReversingOpeningOrRestartingClosePreservesDisplayedGlassAndSource() throws {
        try requireNativeMotion()
        for width: CGFloat in [44, 160] {
            let fixture = makeHost(width: width)
            let host = fixture.host
            defer { host.tearDownGlassEffects() }
            for direction in [ContextMenuBloomDirection.opening, .closing] {
                for raw: CGFloat in [0.15, 0.4, 0.75] {
                    host.setProgress(raw, direction: direction)
                    let sourceFrame = host.sourceProxyContainer.frame
                    let sourceTransform = host.sourceProxyContainer.transform
                    let sourceAlpha = host.sourceProxyContainer.alpha
                    let glassFrame = host.finalMenuGlassSurfaceView.frame
                    let maskFrames = try maskPaths(in: host).map(\.boundingBoxOfPath)
                    var completions = 0
                    host.animateCollapse(duration: 0.44, damping: 0.9) { completions += 1 }
                    assertRect(host.sourceProxyContainer.frame, equals: sourceFrame)
                    XCTAssertEqual(host.sourceProxyContainer.transform, sourceTransform)
                    XCTAssertEqual(host.sourceProxyContainer.alpha, sourceAlpha, accuracy: 0.000001)
                    assertRect(host.finalMenuGlassSurfaceView.frame, equals: glassFrame)
                    let nextMaskFrames = try maskPaths(in: host).map(\.boundingBoxOfPath)
                    XCTAssertEqual(nextMaskFrames.count, maskFrames.count)
                    for (actual, expected) in zip(nextMaskFrames, maskFrames) { assertRect(actual, equals: expected) }
                    host.advanceAnimation(to: 1)
                    for frame in 1...54 { host.advanceAnimation(to: 1 + Double(frame) / 120) }
                    XCTAssertEqual(completions, 1)
                    XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
                    assertRect(host.sourceProxyContainer.frame, equals: fixture.source)
                }
            }
        }
    }

    private func requireNativeMotion() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native glass requires iOS 26") }
        guard !UIAccessibility.isReduceMotionEnabled else { throw XCTSkip("This test exercises the optional source recoil") }
    }

    private func geometry(source: CGRect, target: CGRect, raw: CGFloat,
                          direction: ContextMenuBloomDirection = .closing) -> ContextMenuGlassmorphicGeometrySample {
        contextMenuGlassmorphicGeometrySample(source: source, target: target,
            outerFrame: target, outerCornerRadii: .uniform(27), sourceRadius: source.height / 2,
            targetRadius: 27, anchor: .detect(source: source, target: target),
            direction: direction, rawProgress: raw, reduceMotion: false)
    }

    private func maskPaths(in host: ContextMenuGlassmorphicTransitionView) throws -> [CGPath] {
        let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
        return (mask.sublayers ?? []).filter { !$0.isHidden }.compactMap { ($0 as? CAShapeLayer)?.path }
    }

    private func assertRect(_ actual: CGRect, equals expected: CGRect,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000001, file: file, line: line)
    }

    private func makeHost(width: CGFloat, bottom: Bool = false,
                          appearance: AetherAppearanceStyle = .liquidGlassV1,
                          mode: ContextMenuSourceVisualMode = .leasedGlassSource)
        -> (host: ContextMenuGlassmorphicTransitionView, source: CGRect, target: CGRect, marker: UIView) {
        let source = CGRect(x: 380 - width, y: 450, width: width, height: 44)
        let target = CGRect(x: 125, y: bottom ? 114 : 450, width: 255, height: 380)
        let host = ContextMenuGlassmorphicTransitionView(sourceFrameInOverlay: source,
            targetMenuFrameInOverlay: target, finalCornerRadius: 27, sourceCornerRadius: 22,
            sourceMode: mode, isDark: false, appearanceStyle: appearance)
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 950)
        host.layoutIfNeeded()
        let carrier = UIView(frame: host.sourceProxyContainer.bounds)
        let marker = UIView(frame: carrier.bounds.insetBy(dx: 12, dy: 12))
        marker.backgroundColor = .black
        carrier.addSubview(marker)
        host.sourceProxyContainer.addSubview(carrier)
        return (host, source, target, marker)
    }
}
