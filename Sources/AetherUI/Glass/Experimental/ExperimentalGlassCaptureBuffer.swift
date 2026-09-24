import CoreVideo
import CoreGraphics
import Metal

final class ExperimentalGlassCaptureBuffer {
    let device: MTLDevice
    private var textureCache: CVMetalTextureCache?
    private(set) var pixelBuffer: CVPixelBuffer?
    private var cvTexture: CVMetalTexture?
    private var context: CGContext?

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    /// Call only while this frame's GPU lease is free.
    @discardableResult
    func setupBuffer(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, let cache = textureCache else { return false }
        if let buffer = pixelBuffer,
           CVPixelBufferGetWidth(buffer) == width,
           CVPixelBufferGetHeight(buffer) == height, context != nil, cvTexture != nil {
            return true
        }
        let attrs = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        var newBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attrs, &newBuffer) == kCVReturnSuccess,
              let buffer = newBuffer else { return false }
        var newTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
            .bgra8Unorm, width, height, 0, &newTexture) == kCVReturnSuccess,
              let texture = newTexture else { return false }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
        let newContext = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard let newContext else { return false }
        // Release the context before releasing the memory that backs it.
        context = nil
        cvTexture = texture
        pixelBuffer = buffer
        context = newContext
        return true
    }

    func render(actions: (CGContext) -> Void) -> MTLTexture? {
        guard let buffer = pixelBuffer, let context, let cvTexture,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        context.saveGState()
        defer { context.restoreGState() }
        // Reused surfaces must not retain pixels from a previous transparent capture.
        context.clear(CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
        actions(context)
        return CVMetalTextureGetTexture(cvTexture)
    }
}
