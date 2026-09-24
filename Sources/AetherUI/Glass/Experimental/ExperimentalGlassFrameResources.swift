import Foundation
import Metal

/// Resource mutation is confined to the render/UI thread while exclusively
/// leased. GPU completion handlers only release a lease under the lock.
final class ExperimentalGlassFrameResources: @unchecked Sendable {
    let capture: ExperimentalGlassCaptureBuffer
    private(set) var blurredTexture: MTLTexture?
    private let lock = NSLock()
    private var readers = 0

    init(device: MTLDevice) {
        capture = ExperimentalGlassCaptureBuffer(device: device)
    }

    func tryAcquireForWriting() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard readers == 0 else { return false }
        readers = 1
        return true
    }

    func acquireForReading() {
        lock.lock()
        readers += 1
        lock.unlock()
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        precondition(readers > 0)
        readers -= 1
    }

    func blurDestination(for source: MTLTexture) -> MTLTexture? {
        if let blurredTexture, blurredTexture.width == source.width,
           blurredTexture.height == source.height, blurredTexture.pixelFormat == source.pixelFormat {
            return blurredTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat,
            width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        blurredTexture = source.device.makeTexture(descriptor: descriptor)
        return blurredTexture
    }
}
