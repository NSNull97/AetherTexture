//
//  ExperimentalGlassView.swift
//  ExperimentalGlassMaterial
//
//  Created by Alexey Demin on 2025-12-05.
//

import UIKit
import simd
import MetalKit
import MetalPerformanceShaders

struct ExperimentalGlassMaterial {

    /// Maximum number of rectangles supported in the shader.
    static let maxRectangles = 16

    /// Mirror the Metal 'ShaderUniforms' exactly for buffer binding.
    struct ShaderUniforms {
        var resolution: SIMD2<Float> = .zero        // Frame size in pixels.
        var contentsScale: Float = .zero            // Scale factor. 2 for Retina; 3 for Super Retina.
        var touchPoint: SIMD2<Float> = .zero        // Touch position in points (upper-left origin).
        var shapeMergeSmoothness: Float = .zero     // Specifies the distance between elements at which they begin to merge (spacing).
        var cornerRadius: Float = .zero             // Base rounding (e.g., 24 for subtle chamfer). Circle if half the side.
        var cornerRoundnessExponent: Float = 2      // 1 = diamond; 2 = circle; 4 = squircle.
        var materialTint: SIMD4<Float> = .zero      // RGBA; e.g., subtle cyan (0.2, 0.8, 1.0, 1.0)
        var glassThickness: Float                   // Fake parallax depth (e.g., 8-16 px)
        var refractiveIndex: Float                  // 1.45-1.52 for borosilicate glass feel
        var dispersionStrength: Float               // 0.0-0.02; prismatic color split on edges
        var fresnelDistanceRange: Float             // px falloff from silhouette (e.g., 32)
        var fresnelIntensity: Float                 // 0.0-1.0; rim lighting boost
        var fresnelEdgeSharpness: Float             // Power 1.0=linear, 8.0=crisp
        var glareDistanceRange: Float               // Similar to fresnel, but for specular streaks
        var glareAngleConvergence: Float            // 0.0-π; focuses rays toward light dir
        var glareOppositeSideBias: Float            // >1.0 amplifies back-side highlights
        var glareIntensity: Float                   // 1.0-4.0; bloom-like edge fire
        var glareEdgeSharpness: Float               // Matches fresnel for consistency
        var glareDirectionOffset: Float             // Radians; tilts streak asymmetry
        var edgeRefractionBoost: Float = 0
        var rectangleCount: Int32 = .zero           // Number of active rectangles
        var rectangles: (                           // Array of rectangles (x, y, width, height) in points, upper-left origin.
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
        ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
             .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    }

    let shaderUniforms: ShaderUniforms
    let backgroundTextureSizeCoefficient: Double
    let backgroundTextureScaleCoefficient: Double
    var backgroundTextureBlurRadius: Double
    var tintColor: UIColor?
    var shadowOverlay: Bool = false

    static func thumb(magnification: Double = 1) -> Self {
        .init(
            shaderUniforms: .init(
                materialTint: .init(x: 0.9, y: 0.95, z: 1.0, w: 0.15), // Near-clear with cool bias.
                glassThickness: 10,
                refractiveIndex: 1.11,
                dispersionStrength: 5,
                fresnelDistanceRange: 70,
                fresnelIntensity: 0,
                fresnelEdgeSharpness: 0,
                glareDistanceRange: 30,
                glareAngleConvergence: 0,
                glareOppositeSideBias: 0,
                glareIntensity: 0.01,
                glareEdgeSharpness: -0.2,
                glareDirectionOffset: .pi * 0.9,
            ),
            backgroundTextureSizeCoefficient: 1 / magnification,
            backgroundTextureScaleCoefficient: magnification,
            backgroundTextureBlurRadius: 0,
            shadowOverlay: true,
        )
    }

    static let lens = Self.init(
        shaderUniforms: .init(
            glassThickness: 6,
            refractiveIndex: 1.1,
            dispersionStrength: 15,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.1,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.1,
        backgroundTextureScaleCoefficient: 0.8,
        backgroundTextureBlurRadius: 0,
        shadowOverlay: true,
    )

    static let regular = Self.init(
        shaderUniforms: .init(
            glassThickness: 10,
            refractiveIndex: 1.5,
            dispersionStrength: 5,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.15,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1,
        backgroundTextureScaleCoefficient: 0.2,
        backgroundTextureBlurRadius: 0.3,
        tintColor: UIColor { $0.userInterfaceStyle == .dark ? #colorLiteral(red: 0, green: 0.04958364581, blue: 0.09951775161, alpha: 0.7981493615) : #colorLiteral(red: 0.9023525731, green: 0.9509486998, blue: 1, alpha: 0.8002892298) }//.systemBackground.withAlphaComponent(0.8),
    )
}

final class ExperimentalGlassRenderer {
    @MainActor static let shared = ExperimentalGlassRenderer()

    let device: MTLDevice
    let pipelineState: MTLRenderPipelineState
    let commandQueue: MTLCommandQueue

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "aetherExperimentalGlassVertex"),
              let fragment = library.makeFunction(name: "aetherExperimentalGlassFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.commandQueue = queue
        self.pipelineState = pipeline
    }

}

final class ExperimentalGlassView: MTKView {

    var liquidGlass: ExperimentalGlassMaterial
    private let renderer: ExperimentalGlassRenderer
    weak var backgroundOwner: UIView?
    var edgeRefractionBoost: Float = 0
    private var tintAnimation: (from: SIMD4<Float>, to: SIMD4<Float>, start: CFTimeInterval,
                                duration: Double, curve: ContainedViewLayoutTransitionCurve)?

    func setMaterial(_ material: ExperimentalGlassMaterial, transition: ContainedViewLayoutTransition) {
        let previousTint = currentTint()
        let targetTint = material.tintColor?.resolvedColor(with: traitCollection).experimentalGlassRGBA
            ?? material.shaderUniforms.materialTint
        let existingTarget = liquidGlass.tintColor?.resolvedColor(with: traitCollection).experimentalGlassRGBA
            ?? liquidGlass.shaderUniforms.materialTint
        liquidGlass = material
        guard existingTarget != targetTint else { return }
        if case let .animated(duration, curve) = transition, duration > 0,
           !UIAccessibility.isReduceMotionEnabled {
            tintAnimation = (previousTint, targetTint, CACurrentMediaTime(), duration, curve)
        } else { tintAnimation = nil }
    }

    private func currentTint() -> SIMD4<Float> {
        if let animation = tintAnimation {
            let progress = min(1, max(0, (CACurrentMediaTime() - animation.start) / animation.duration))
            if progress < 1 {
                let value = Float(animation.curve.value(at: CGFloat(progress)))
                return animation.from + (animation.to - animation.from) * value
            }
            tintAnimation = nil
        }
        return liquidGlass.tintColor?.resolvedColor(with: traitCollection).experimentalGlassRGBA
            ?? liquidGlass.shaderUniforms.materialTint
    }


    var captureScaleCoefficient: Double {
        edgeRefractionBoost > 0 ? max(0.5, liquidGlass.backgroundTextureScaleCoefficient)
            : liquidGlass.backgroundTextureScaleCoefficient
    }

    private var frameResources: [ExperimentalGlassFrameResources] = []
    private var cachedFrame: ExperimentalGlassFrameResources?
    private var backgroundTexture: MTLTexture?
    private var unfilteredBackgroundTexture: MTLTexture?
    private var uniforms: ExperimentalGlassMaterial.ShaderUniforms?
    private var captureRequested = false
    private var blurKernel: MPSImageGaussianBlur?
    private var blurSigma: Float = 0

    /// Whether to automatically capture superview on each frame. 
    /// Set to false for manual control via `captureBackground()`.
    var autoCapture: Bool = true

    var touchPoint: CGPoint? = nil

    var frames: [CGRect] = []

    init?(_ liquidGlass: ExperimentalGlassMaterial) {
        guard let renderer = ExperimentalGlassRenderer.shared else { return nil }
        self.renderer = renderer
        self.liquidGlass = liquidGlass
        super.init(frame: .zero, device: renderer.device)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = min(60, UIScreen.main.maximumFramesPerSecond)
        setupMetal()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setupMetal() {
        guard let device else { return }

        frameResources = (0..<3).map { _ in ExperimentalGlassFrameResources(device: device) }

        // Make view transparent so we can see the effect
        isOpaque = false
        layer.isOpaque = false

        // One display link drives every surface. Independent MTKView timers can
        // cross run-loop boundaries and invalidate a supposedly shared capture.
        isPaused = true
        enableSetNeedsDisplay = false
    }

    // MARK: - Background Capture

    /// Request a fresh capture on the next draw, including in manual mode.
    func captureBackground() {
        captureRequested = true
    }

    private func captureBackground(using bridge: ExperimentalGlassCaptureBuffer) -> MTLTexture? {
        return ExperimentalGlassBackgroundCapture.render(
            owner: backgroundOwner ?? self, glass: self, bridge: bridge,
            sizeCoefficient: liquidGlass.backgroundTextureSizeCoefficient,
            scaleCoefficient: captureScaleCoefficient
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        isPaused = true
        ExperimentalGlassFrameScheduler.shared.update(self)
    }

    private func encodeBlur(source: MTLTexture, frame: ExperimentalGlassFrameResources,
                            commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard liquidGlass.backgroundTextureBlurRadius > 0 else { return source }
        guard let device, let destination = frame.blurDestination(for: source) else { return nil }
        let sigma = Float(liquidGlass.backgroundTextureBlurRadius * layer.contentsScale * captureScaleCoefficient / liquidGlass.backgroundTextureScaleCoefficient)
        if blurKernel == nil || blurSigma != sigma {
            blurKernel = MPSImageGaussianBlur(device: device, sigma: sigma)
            blurKernel?.edgeMode = .clamp
            blurSigma = sigma
        }
        blurKernel?.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
        return destination
    }

    func updateUniforms() {
        var uniforms = liquidGlass.shaderUniforms
        uniforms.edgeRefractionBoost = edgeRefractionBoost
        let scaleFactor = layer.contentsScale

        uniforms.resolution = .init(x: Float(bounds.width * scaleFactor),
                                    y: Float(bounds.height * scaleFactor))
        uniforms.contentsScale = Float(scaleFactor)

        uniforms.shapeMergeSmoothness = 0.2

        // Populate the fixed-size uniform tuple without allocating a Swift
        // array for every frame. Unused entries start at zero in the preset.
        let rectangleCount = frames.isEmpty ? 1 : min(frames.count, ExperimentalGlassMaterial.maxRectangles)
        uniforms.rectangleCount = Int32(rectangleCount)
        withUnsafeMutableBytes(of: &uniforms.rectangles) { bytes in
            let rectangles = bytes.bindMemory(to: SIMD4<Float>.self)
            for i in 0..<rectangleCount {
                let frame = frames.isEmpty ? bounds : frames[i]
                rectangles[i] = SIMD4<Float>(Float(frame.origin.x), Float(frame.origin.y),
                                            Float(frame.width), Float(frame.height))
            }
        }

        if let touchPoint {
            uniforms.touchPoint = .init(x: Float(touchPoint.x), y: Float(touchPoint.y))
        }

        uniforms.cornerRadius = Float(min(max(0, layer.cornerRadius), min(bounds.width, bounds.height) / 2))

        uniforms.materialTint = currentTint()

        self.uniforms = uniforms
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        updateUniforms()
    }

    var isEffectivelyVisible: Bool {
        guard let window, !UIAccessibility.isReduceTransparencyEnabled else { return false }
        var visibleRect = convert(bounds, to: window)
        guard !visibleRect.isEmpty, visibleRect.intersects(window.bounds) else { return false }
        var current: UIView? = self
        while let view = current {
            if view.isHidden || view.alpha <= 0.001 { return false }
            if view.clipsToBounds {
                visibleRect = visibleRect.intersection(view.convert(view.bounds, to: window))
                if visibleRect.isNull || visibleRect.isEmpty { return false }
            }
            current = view.superview
        }
        return true
    }

    override func draw(_ rect: CGRect) {
        guard window != nil, isEffectivelyVisible, bounds.width > 0, bounds.height > 0 else { return }
        let needsCapture = autoCapture || captureRequested
        let frame: ExperimentalGlassFrameResources
        if needsCapture {
            // Never overwrite the retained manual snapshot or a surface still
            // consumed by the GPU. Under load, skip a frame instead of blocking UI.
            guard let available = frameResources.first(where: {
                $0 !== cachedFrame && $0.tryAcquireForWriting()
            }) else {
                if ExperimentalGlassDiagnostics.enabled { ExperimentalGlassDiagnostics.skipped += 1 }
                return
            }
            frame = available
        } else {
            guard let cachedFrame, backgroundTexture != nil else { return }
            frame = cachedFrame
            frame.acquireForReading()
        }
        var submitted = false
        defer { if !submitted { frame.release() } }
        let drawableStarted = ExperimentalGlassDiagnostics.enabled ? CACurrentMediaTime() : 0
        let nextDrawable = currentDrawable
        if ExperimentalGlassDiagnostics.enabled {
            ExperimentalGlassDiagnostics.drawableMS += (CACurrentMediaTime() - drawableStarted) * 1000
        }
        guard let drawable = nextDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }

        let texture: MTLTexture
        let unfilteredTexture: MTLTexture
        if needsCapture {
            let scale = layer.contentsScale * liquidGlass.backgroundTextureSizeCoefficient * captureScaleCoefficient
            guard scale.isFinite, scale > 0,
                  frame.capture.setupBuffer(width: Int(bounds.width * scale), height: Int(bounds.height * scale)),
                  let captured = captureBackground(using: frame.capture),
                  let filtered = encodeBlur(source: captured, frame: frame, commandBuffer: commandBuffer) else { return }
            texture = filtered
            unfilteredTexture = captured
        } else {
            guard let backgroundTexture, let unfilteredBackgroundTexture else { return }
            texture = backgroundTexture
            unfilteredTexture = unfilteredBackgroundTexture
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }
        updateUniforms()
        guard var uniforms else { encoder.endEncoding(); return }
        encoder.setRenderPipelineState(renderer.pipelineState)
        // Metal copies this small value, so the next layout cannot mutate
        // uniforms already submitted to the GPU.
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ExperimentalGlassMaterial.ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(unfilteredTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { _ in frame.release() }
        submitted = true
        if needsCapture {
            cachedFrame = frame
            backgroundTexture = texture
            unfilteredBackgroundTexture = unfilteredTexture
            captureRequested = false
        }
        commandBuffer.commit()
    }

}

extension UIColor {
    fileprivate var experimentalGlassRGBA: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
