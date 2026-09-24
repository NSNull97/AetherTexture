import UIKit

/// All surfaces consume the same capture epoch, including during scroll tracking.
/// Weak membership avoids retaining screens through a display link.
@MainActor
final class ExperimentalGlassFrameScheduler: NSObject {
    static let shared = ExperimentalGlassFrameScheduler()
    private let views = NSHashTable<ExperimentalGlassView>.weakObjects()
    private var displayLink: CADisplayLink?

    func update(_ view: ExperimentalGlassView) {
        if view.window != nil { views.add(view) }
        else { views.remove(view) }
        if views.allObjects.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
        } else if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func tick() {
        let surfaces = views.allObjects
        if surfaces.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
            return
        }
        renderFrame(surfaces)
    }

    func renderFrame(_ surfaces: [ExperimentalGlassView]) {
        let started = ExperimentalGlassDiagnostics.beginFrame()
        let visible = surfaces.filter(\.isEffectivelyVisible)
        defer { ExperimentalGlassDiagnostics.endFrame(start: started, visible: visible.count) }
        ExperimentalGlassBackgroundCapture.prepareFrame(visible)
        defer { ExperimentalGlassBackgroundCapture.finishFrame() }
        for surface in visible {
            surface.draw()
        }
    }
}
