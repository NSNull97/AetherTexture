import Foundation
import QuartzCore

/// Opt-in instrumentation for device builds; no logging in normal builds.
@MainActor
enum ExperimentalGlassDiagnostics {
    #if AETHER_GLASS_PROFILE
    static let enabled = true
    #else
    static let enabled = false
    #endif
    static var captureMS = 0.0
    static var drawableMS = 0.0
    static var skipped = 0
    private static var started = 0.0
    private static var frames = 0
    private static var totalCPU = 0.0
    private static var maxCPU = 0.0
    private static var surfaces = 0
    private static var captures = 0
    private static var previousCaptureCount = 0
    private static var slowestCapture = 0.0
    private static var slowestDescription = ""

    static func beginFrame() -> CFTimeInterval {
        guard enabled else { return 0 }
        let now = CACurrentMediaTime()
        if started == 0 { started = now }
        previousCaptureCount = ExperimentalGlassBackgroundCapture.treeRenderCount
        return now
    }

    static func captureFinished(start: CFTimeInterval, description: @autoclosure () -> String) {
        guard enabled else { return }
        let ms = (CACurrentMediaTime() - start) * 1000
        captureMS += ms
        if ms > slowestCapture {
            slowestCapture = ms
            slowestDescription = description()
        }
    }

    static func endFrame(start: CFTimeInterval, visible: Int) {
        guard enabled else { return }
        let now = CACurrentMediaTime()
        let ms = (now - start) * 1000
        frames += 1
        surfaces += visible
        captures += ExperimentalGlassBackgroundCapture.treeRenderCount - previousCaptureCount
        totalCPU += ms
        maxCPU = max(maxCPU, ms)
        let duration = now - started
        guard duration >= 2 else { return }
        let n = Double(frames)
        NSLog("AETHER_GLASS cadence=%.1f callbacks/s cpu=%.2f max=%.2f capture=%.2f drawable=%.2f ms/frame surfaces=%.1f trees=%.1f skipped=%d worstCapture=%.2f %@ bypass=%@",
              n / duration, totalCPU / n, maxCPU, captureMS / n, drawableMS / n,
              Double(surfaces) / n, Double(captures) / n, skipped, slowestCapture, slowestDescription,
              ExperimentalGlassLayerFingerprint.lastBypass)
        frames = 0; totalCPU = 0; maxCPU = 0; captureMS = 0; drawableMS = 0
        surfaces = 0; captures = 0; skipped = 0; slowestCapture = 0
        slowestDescription = ""; started = now
    }
}
