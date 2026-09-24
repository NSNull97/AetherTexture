import XCTest
import UIKit
import Metal
@testable import AetherUI

@MainActor
final class ExperimentalGlassTests: XCTestCase {
    func testOpaqueCoverSkipsLowerScreenButTranslucentCoverRetainsIt() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let window = ExperimentalCaptureProbeWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let lower = UIView(frame: window.bounds)
        lower.backgroundColor = .red
        window.addSubview(lower)
        let upper = UIView(frame: window.bounds)
        upper.backgroundColor = .blue
        window.addSubview(upper)
        let owner = UIView(frame: CGRect(x: 50, y: 30, width: 20, height: 20))
        window.addSubview(owner)
        let glass = UIView(frame: owner.bounds)
        glass.layer.contentsScale = 1
        owner.addSubview(glass)
        let probe = try XCTUnwrap(window.layer as? ExperimentalCaptureProbeLayer)
        var expectsHidden = true
        probe.beforeRender = { XCTAssertEqual(lower.isHidden, expectsHidden) }
        defer { probe.beforeRender = nil }
        let bridge = ExperimentalGlassCaptureBuffer(device: device)
        XCTAssertTrue(bridge.setupBuffer(width: 20, height: 20))
        func pixel() throws -> [UInt8] {
            ExperimentalGlassBackgroundCapture.invalidateSnapshots()
            let texture = try XCTUnwrap(ExperimentalGlassBackgroundCapture.render(
                owner: owner, glass: glass, bridge: bridge, sizeCoefficient: 1, scaleCoefficient: 1))
            var bytes = [UInt8](repeating: 0, count: 4)
            texture.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(10, 10, 1, 1), mipmapLevel: 0)
            return bytes
        }
        XCTAssertEqual(try pixel(), [255, 0, 0, 255])
        XCTAssertFalse(lower.isHidden)
        expectsHidden = false
        upper.alpha = 0.5
        let blended = try pixel()
        XCTAssertGreaterThan(blended[0], 100)
        XCTAssertGreaterThan(blended[2], 100)
        XCTAssertFalse(lower.isHidden)
    }

    func testFingerprintTracksModelChangesAndRejectsAnimations() throws {
        let root = CALayer()
        let text = CATextLayer()
        text.string = "first"
        root.addSublayer(text)
        let first = try XCTUnwrap(ExperimentalGlassLayerFingerprint.make(root))
        XCTAssertEqual(first, ExperimentalGlassLayerFingerprint.make(root))
        text.string = "second"
        XCTAssertNotEqual(first, ExperimentalGlassLayerFingerprint.make(root))
        let second = ExperimentalGlassLayerFingerprint.make(root)
        root.bounds.origin.y = 20
        XCTAssertNotEqual(second, ExperimentalGlassLayerFingerprint.make(root))
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = 10
        root.add(animation, forKey: "test")
        XCTAssertNil(ExperimentalGlassLayerFingerprint.make(root))
    }

    func testCapturePrunesOffscreenBranchesButRetainsOverflowAndRestoresLayers() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let window = ExperimentalCaptureProbeWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let outside = UIView(frame: CGRect(x: 300, y: 0, width: 30, height: 30))
        window.addSubview(outside)
        let overflow = UIView(frame: CGRect(x: 300, y: 0, width: 30, height: 30))
        window.addSubview(overflow)
        let visibleChild = UIView(frame: CGRect(x: -290, y: 10, width: 20, height: 20))
        visibleChild.backgroundColor = .green
        overflow.addSubview(visibleChild)
        let clipped = UIView(frame: overflow.frame)
        clipped.clipsToBounds = true
        let clippedChild = UIView(frame: visibleChild.frame)
        clippedChild.backgroundColor = .red
        clipped.addSubview(clippedChild)
        window.addSubview(clipped)
        let owner = UIView(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        window.addSubview(owner)
        let glass = UIView(frame: owner.bounds)
        glass.layer.contentsScale = 1
        owner.addSubview(glass)
        let probe = try XCTUnwrap(window.layer as? ExperimentalCaptureProbeLayer)
        var inspected = false
        probe.beforeRender = {
            inspected = true
            XCTAssertTrue(outside.isHidden)
            XCTAssertTrue(clipped.isHidden)
            XCTAssertFalse(overflow.isHidden)
            XCTAssertFalse(visibleChild.isHidden)
        }
        defer { probe.beforeRender = nil }
        let bridge = ExperimentalGlassCaptureBuffer(device: device)
        XCTAssertTrue(bridge.setupBuffer(width: 20, height: 20))
        let texture = try XCTUnwrap(ExperimentalGlassBackgroundCapture.render(
            owner: owner, glass: glass, bridge: bridge, sizeCoefficient: 1, scaleCoefficient: 1))
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(10, 10, 1, 1), mipmapLevel: 0)
        XCTAssertEqual(pixel, [0, 255, 0, 255])
        XCTAssertTrue(inspected)
        XCTAssertFalse(outside.isHidden)
        XCTAssertFalse(clipped.isHidden)
        XCTAssertFalse(owner.isHidden)
    }

    func testDirectCaptureTracksMovementAndExcludesForeground() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let background = UIView(frame: window.bounds)
        background.backgroundColor = .red
        window.addSubview(background)
        let blue = UIView(frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        blue.backgroundColor = .blue
        background.addSubview(blue)
        let owner = UIView(frame: CGRect(x: 10, y: 20, width: 20, height: 20))
        owner.backgroundColor = .green
        window.addSubview(owner)
        let glass = UIView(frame: owner.bounds)
        glass.layer.contentsScale = 1
        owner.addSubview(glass)
        let front = UIView(frame: window.bounds)
        front.backgroundColor = .yellow
        window.addSubview(front)
        let bridge = ExperimentalGlassCaptureBuffer(device: device)
        XCTAssertTrue(bridge.setupBuffer(width: 20, height: 20))

        func pixel() throws -> [UInt8] {
            let texture = try XCTUnwrap(ExperimentalGlassBackgroundCapture.render(
                owner: owner, glass: glass, bridge: bridge, sizeCoefficient: 1, scaleCoefficient: 1))
            var bytes = [UInt8](repeating: 0, count: 4)
            texture.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(10, 10, 1, 1), mipmapLevel: 0)
            return bytes
        }
        XCTAssertEqual(try pixel(), [0, 0, 255, 255])
        XCTAssertFalse(owner.isHidden)
        XCTAssertFalse(front.isHidden)
        window.experimentalGlassBackgroundSource = background
        owner.frame.origin.x = 130
        XCTAssertEqual(try pixel(), [255, 0, 0, 255])
        background.bounds.origin.x = 100
        owner.frame.origin.x = 10
        XCTAssertEqual(try pixel(), [255, 0, 0, 255])
    }

    func testMetalRendersDirectSourceAfterResize() throws {
        let renderer = try XCTUnwrap(ExperimentalGlassRenderer.shared)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let source = UIView(frame: window.bounds)
        source.backgroundColor = .blue
        window.addSubview(source)
        window.experimentalGlassBackgroundSource = source
        let glass = try XCTUnwrap(ExperimentalGlassView(.regular))
        glass.edgeRefractionBoost = 1.65
        window.addSubview(glass)
        glass.isPaused = true
        glass.framebufferOnly = false
        for width in [100, 140, 180] {
            glass.frame = CGRect(x: 20, y: 20, width: width, height: 48)
            glass.layer.cornerRadius = 24
            glass.layoutIfNeeded()
            glass.draw()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let texture = try XCTUnwrap(glass.currentDrawable?.texture)
        glass.draw()
        let rowBytes = ((texture.width * 4 + 255) / 256) * 256
        let buffer = try XCTUnwrap(renderer.device.makeBuffer(length: rowBytes * texture.height,
                                                             options: .storageModeShared))
        let command = try XCTUnwrap(renderer.commandQueue.makeCommandBuffer())
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes,
                  destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        let pixels = buffer.contents().assumingMemoryBound(to: UInt8.self)
        let center = (texture.height / 2) * rowBytes + (texture.width / 2) * 4
        XCTAssertGreaterThan(pixels[center + 3], 0)
        XCTAssertGreaterThan(pixels[center], pixels[center + 2])
    }

    func testPanelSharesOneCaptureAcrossTwentySurfacesAndInvalidatesNextFrame() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 140))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let source = UIView(frame: window.bounds)
        source.backgroundColor = .red
        window.addSubview(source)
        let bottom = UIView(frame: CGRect(x: 0, y: 70, width: 300, height: 70))
        bottom.backgroundColor = .blue
        source.addSubview(bottom)
        let panel = GlassControlGroup(appearanceStyle: .legacy)
        panel.frame = window.bounds
        window.addSubview(panel)
        let bridge = ExperimentalGlassCaptureBuffer(device: device)
        XCTAssertTrue(bridge.setupBuffer(width: 20, height: 20))
        ExperimentalGlassBackgroundCapture.invalidateSnapshots()
        let before = ExperimentalGlassBackgroundCapture.treeRenderCount
        let started = CACurrentMediaTime()
        var owners: [UIView] = []
        for i in 0..<20 {
            let owner = UIView(frame: CGRect(x: 20 + i * 5, y: i % 2 == 0 ? 20 : 90, width: 20, height: 20))
            panel.addSubview(owner)
            owners.append(owner)
            let glass = UIView(frame: owner.bounds)
            glass.layer.contentsScale = 1
            owner.addSubview(glass)
            let texture = try XCTUnwrap(ExperimentalGlassBackgroundCapture.render(
                owner: owner, glass: glass, bridge: bridge, sizeCoefficient: 1, scaleCoefficient: 1))
            var pixel = [UInt8](repeating: 0, count: 4)
            texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(10, 10, 1, 1), mipmapLevel: 0)
            XCTAssertEqual(pixel, i % 2 == 0 ? [0, 0, 255, 255] : [255, 0, 0, 255])
        }
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 1)
        print("SHARED_CAPTURE surfaces=20 tree_renders=1 elapsed_ms=\((CACurrentMediaTime() - started) * 1000)")
        ExperimentalGlassBackgroundCapture.invalidateSnapshots()
        let owner = try XCTUnwrap(owners.first)
        let glass = try XCTUnwrap(owner.subviews.first)
        _ = ExperimentalGlassBackgroundCapture.render(owner: owner, glass: glass, bridge: bridge,
                                                      sizeCoefficient: 1, scaleCoefficient: 1)
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 1)
        source.backgroundColor = .green
        ExperimentalGlassBackgroundCapture.invalidateSnapshots()
        _ = ExperimentalGlassBackgroundCapture.render(owner: owner, glass: glass, bridge: bridge,
                                                      sizeCoefficient: 1, scaleCoefficient: 1)
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 2)
    }

    func testSourceIsInheritedAndWeak() {
        let parent = UIView()
        let child = UIView()
        parent.addSubview(child)
        var source: UIView? = UIView()
        parent.experimentalGlassBackgroundSource = source
        XCTAssertTrue(ExperimentalGlassBackgroundCapture.source(for: child) === source)
        source = nil
        XCTAssertNil(ExperimentalGlassBackgroundCapture.source(for: child))
    }

    func testScheduledMetalSurfacesShareCaptureAndSkipClippedViews() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 140))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.backgroundColor = .blue
        let panel = GlassControlGroup(appearanceStyle: .legacy)
        panel.frame = window.bounds
        panel.clipsToBounds = true
        window.addSubview(panel)
        var surfaces: [ExperimentalGlassView] = []
        for x in [10, 100, 400] {
            let surface = try XCTUnwrap(ExperimentalGlassView(.regular))
            surface.frame = CGRect(x: x, y: 20, width: 60, height: 40)
            panel.addSubview(surface)
            surface.layoutIfNeeded()
            XCTAssertTrue(surface.isPaused, "MTKView must not own a second frame timer")
            surfaces.append(surface)
        }
        XCTAssertTrue(surfaces[0].isEffectivelyVisible)
        XCTAssertFalse(surfaces[2].isEffectivelyVisible)
        let before = ExperimentalGlassBackgroundCapture.treeRenderCount
        ExperimentalGlassFrameScheduler.shared.renderFrame(surfaces)
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 1)
        ExperimentalGlassFrameScheduler.shared.renderFrame(surfaces)
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 1)
        window.backgroundColor = .red
        ExperimentalGlassFrameScheduler.shared.renderFrame(surfaces)
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 2)
        panel.isHidden = true
        ExperimentalGlassFrameScheduler.shared.renderFrame(surfaces)
        XCTAssertEqual(ExperimentalGlassBackgroundCapture.treeRenderCount - before, 2)
    }

    func testMaterialUpdatesAndInteractiveGeometryRetainRenderer() throws {
        let previous = AetherGlassConfig.current
        defer { AetherGlassConfig.current = previous }
        AetherGlassConfig.current.legacyBlurBackend = .experimentalGlass
        let backdrop = LegacyGlassBackdropView()
        let renderer = try XCTUnwrap(backdrop.experimentalView)
        let owner = GlassBackgroundView(appearanceStyle: .liquidGlassV1)
        backdrop.updateMaterial(owner: owner, style: .clear,
                                tint: .init(kind: .custom(style: .clear, color: .red)),
                                isDark: true, isInteractive: false)
        XCTAssertEqual(renderer.liquidGlass.tintColor, .red)
        XCTAssertEqual(renderer.liquidGlass.backgroundTextureBlurRadius, 0)
        XCTAssertEqual(renderer.overrideUserInterfaceStyle, .dark)
        XCTAssertFalse(backdrop.experimentalInteractionEnabled)
        backdrop.updateMaterial(owner: owner, style: .prominent, tint: .init(kind: .panel),
                                isDark: false, isInteractive: true)
        XCTAssertGreaterThan(renderer.liquidGlass.backgroundTextureBlurRadius, 0)
        XCTAssertTrue(backdrop.experimentalInteractionEnabled)
        backdrop.updateInteractiveGeometry(size: CGSize(width: 180, height: 48), cornerRadius: 24)
        XCTAssertTrue(backdrop.experimentalView === renderer)
        XCTAssertEqual(renderer.bounds.size, CGSize(width: 180, height: 48))
        XCTAssertEqual(renderer.layer.cornerRadius, 24)
    }

    func testBackgroundBackendSelectionPreservesNativeAndClassicPaths() {
        let previous = AetherGlassConfig.current
        let previousForce = GlassBackgroundView.useCustomGlassImpl
        defer {
            AetherGlassConfig.current = previous
            GlassBackgroundView.useCustomGlassImpl = previousForce
        }
        AetherGlassConfig.current.legacyBlurBackend = .experimentalGlass
        GlassBackgroundView.useCustomGlassImpl = false
        let surface = GlassBackgroundView(appearanceStyle: .liquidGlassV1)
        func containsMetal(_ view: UIView) -> Bool {
            view is ExperimentalGlassView || view.subviews.contains(where: containsMetal)
        }
        if #available(iOS 26, *) {
            XCTAssertFalse(containsMetal(surface))
            XCTAssertTrue(surface.usesNativeGlassRendererForTesting)
        } else {
            XCTAssertTrue(containsMetal(surface))
        }
        surface.appearanceStyleOverride = .legacy
        XCTAssertFalse(containsMetal(surface))
        XCTAssertTrue(surface.usesLegacySurfaceRendererForTesting)
    }

    func testLensUsesBackportOnlyForLiquidAppearanceBelow26() throws {
        let lens = LiquidLensView(kind: .noContainer, appearanceStyle: .liquidGlassV1)
        if #available(iOS 26, *) {
            XCTAssertFalse(lens.usesExperimentalLensForTesting)
        } else {
            XCTAssertTrue(lens.usesExperimentalLensForTesting)
        }
        lens.update(size: CGSize(width: 200, height: 56), selectionOrigin: CGPoint(x: 90, y: 0),
                    selectionSize: CGSize(width: 100, height: 56), inset: 4, liftedInset: 6,
                    isDark: true, isLifted: true, transition: .immediate)
        lens.appearanceStyleOverride = .legacy
        XCTAssertTrue(lens.usesClassicRendererForTesting)
        XCTAssertFalse(lens.usesExperimentalLensForTesting)
        lens.appearanceStyleOverride = .liquidGlassV1
        if #unavailable(iOS 26) { XCTAssertTrue(lens.usesExperimentalLensForTesting) }
    }
}

private final class ExperimentalCaptureProbeLayer: CALayer {
    var beforeRender: (() -> Void)?
    override func render(in ctx: CGContext) {
        beforeRender?()
        super.render(in: ctx)
    }
}

private final class ExperimentalCaptureProbeWindow: UIWindow {
    override class var layerClass: AnyClass { ExperimentalCaptureProbeLayer.self }
}
