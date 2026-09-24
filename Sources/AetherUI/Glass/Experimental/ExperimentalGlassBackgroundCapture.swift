import UIKit
import Metal
import ObjectiveC

private var experimentalBackgroundKey: UInt8 = 0
private final class ExperimentalWeakBackground: NSObject {
    weak var view: UIView?
    init(_ view: UIView?) { self.view = view }
}

extension UIView {
    /// Background-only UIKit content used by the experimental glass backend.
    /// Inherited by descendant glass surfaces; retained weakly. Set this on
    /// a screen/chrome host to keep moving lenses in sync with scrolling.
    /// The source must not contain the glass itself. Metal, video and system
    /// visual-effect layers cannot be reproduced by this direct capture path.
    /// Nil uses automatic capture of UIKit layers behind the glass.
    public var experimentalGlassBackgroundSource: UIView? {
        get { (objc_getAssociatedObject(self, &experimentalBackgroundKey) as? ExperimentalWeakBackground)?.view }
        set { objc_setAssociatedObject(self, &experimentalBackgroundKey, ExperimentalWeakBackground(newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

@MainActor
enum ExperimentalGlassBackgroundCapture {
    private static var frameScales: [ObjectIdentifier: CGFloat] = [:]
    private static var frameRects: [ObjectIdentifier: CGRect] = [:]

    /// Render the shared bitmap at the highest resolution actually consumed by
    /// this frame's surfaces, instead of drawing Retina pixels only to discard
    /// them immediately in every surface's downsampled capture buffer.
    static func prepareFrame(_ surfaces: [ExperimentalGlassView]) {
        invalidateSnapshots()
        frameScales.removeAll(keepingCapacity: true)
        frameRects.removeAll(keepingCapacity: true)
        for glass in surfaces {
            guard let window = glass.window else { continue }
            let owner = glass.backgroundOwner ?? glass
            let explicit = validSource(for: owner, in: window)
            let source = explicit ?? window
            let key = explicit ?? captureBoundary(for: owner)
            let scale = glass.layer.contentsScale * glass.captureScaleCoefficient
            let id = ObjectIdentifier(key)
            let region = glass.layer.convert(glass.layer.bounds, to: source.layer)
            guard region.width > 0, region.height > 0 else { continue }
            let requiredScale = ceil(scale * 64) / 64
            frameScales[id] = max(frameScales[id] ?? 0, requiredScale)
            let coefficient = glass.liquidGlass.backgroundTextureSizeCoefficient
            let capture = region.insetBy(dx: region.width * (1 - coefficient) / 2,
                                        dy: region.height * (1 - coefficient) / 2)
            // Large sheet/menu backgrounds need a stable source coordinate
            // extent while they move. Reuse the unchanged backdrop and crop it
            // at the current glass position, instead of recapturing on resize.
            let largeSurface = glass.bounds.width * glass.bounds.height > window.bounds.width * window.bounds.height * 0.2
            let requestedRect = largeSurface
                ? source.layer.convert(window.layer.bounds, from: window.layer) : capture
            frameRects[id] = frameRects[id].map { $0.union(requestedRect) } ?? requestedRect
        }
    }

    static func finishFrame() {
        frameScales.removeAll(keepingCapacity: true)
        frameRects.removeAll(keepingCapacity: true)
    }

    private static func validSource(for owner: UIView, in window: UIWindow) -> UIView? {
        guard let source = source(for: owner), source.window === window, source !== owner,
              !owner.isDescendant(of: source), !source.isDescendant(of: owner) else { return nil }
        return source
    }

    static func source(for owner: UIView) -> UIView? {
        var view: UIView? = owner
        while let candidate = view {
            if let source = candidate.experimentalGlassBackgroundSource { return source }
            view = candidate.superview
        }
        return nil
    }

    static func render(owner: UIView, glass: UIView, bridge: ExperimentalGlassCaptureBuffer,
                       sizeCoefficient: Double, scaleCoefficient: Double) -> MTLTexture? {
        let started = ExperimentalGlassDiagnostics.enabled ? CACurrentMediaTime() : 0
        defer {
            ExperimentalGlassDiagnostics.captureFinished(start: started,
                description: "owner=\(type(of: owner)) boundary=\(type(of: captureBoundary(for: owner))) size=\(glass.bounds.size)")
        }
        guard let window = glass.window else { return nil }
        let validSource = validSource(for: owner, in: window)
        let source = validSource ?? window
        let region = glass.layer.convert(glass.layer.bounds, to: source.layer)
        let width = region.width * sizeCoefficient
        let height = region.height * sizeCoefficient
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let origin = CGPoint(x: region.midX - width / 2, y: region.midY - height / 2)
        let scale = glass.layer.contentsScale * scaleCoefficient * sizeCoefficient

        let boundary = captureBoundary(for: owner)
        let snapshot: Snapshot?
        do {
            let sourceVisibleRect = source.layer.convert(window.layer.bounds, from: window.layer)
            let key = validSource ?? boundary
            let fallbackRect = validSource != nil ? source.bounds.intersection(sourceVisibleRect)
                : boundary.layer.convert(boundary.layer.bounds, to: source.layer)
                    .insetBy(dx: -32, dy: -32).intersection(sourceVisibleRect)
            let desiredRect = frameRects[ObjectIdentifier(key)]?.insetBy(dx: -1, dy: -1)
                .intersection(sourceVisibleRect) ?? fallbackRect
            let requestedScale = glass.layer.contentsScale * scaleCoefficient
            // Transformed surfaces may need more source pixels per point.
            let transformScale = max(glass.bounds.width / region.width, glass.bounds.height / region.height)
            let snapshotScale = frameScales[ObjectIdentifier(key)]
                ?? ceil(max(requestedScale, requestedScale * transformScale) * 64) / 64
            snapshot = sharedSnapshot(source: source, boundary: validSource == nil ? boundary : nil,
                                      rect: desiredRect, scale: snapshotScale)
        }

        if let snapshot {
            return bridge.render { context in
                context.scaleBy(x: glass.bounds.width * scale / width,
                                y: glass.bounds.height * scale / height)
                context.translateBy(x: -origin.x, y: -origin.y)
                context.draw(snapshot.image, in: snapshot.rect)
            }
        }
        return withForegroundExcluded(owner: validSource == nil ? owner : nil, source: source,
                                      captureRect: CGRect(origin: origin, size: CGSize(width: width, height: height))) {
            treeRenderCount += 1
            return bridge.render { context in
                context.scaleBy(x: glass.bounds.width * scale / width,
                                y: glass.bounds.height * scale / height)
                context.translateBy(x: -origin.x, y: -origin.y)
                source.layer.render(in: context)
            }
        }
    }

    /// All optical elements of a chrome panel share its backdrop. The panel's
    /// foreground content is excluded as a unit, rather than captured again
    /// for every button, selection lens and material surface.
    static func captureBoundary(for owner: UIView) -> UIView {
        var boundary = owner
        var current = owner.superview
        while let view = current {
            if view is NavigationBarView || view is TabBarView || view is GlassControlGroup {
                boundary = view
            }
            current = view.superview
        }
        return boundary
    }

    private struct Snapshot { let image: CGImage; let rect: CGRect }
    private final class Entry {
        var epoch: UInt64 = .max
        var sourceID: ObjectIdentifier?
        var sourceBounds = CGRect.zero
        var rect = CGRect.zero
        var scale: CGFloat = 0
        var context: CGContext?
        var image: CGImage?
        var fingerprint: Int?
    }
    private static let entries = NSMapTable<UIView, Entry>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private static var epoch: UInt64 = 0
    private static var observer: CFRunLoopObserver?
    static private(set) var treeRenderCount = 0

    static func invalidateSnapshots() { epoch &+= 1 }

    private static func sharedSnapshot(source: UIView, boundary: UIView?, rect: CGRect, scale: CGFloat) -> Snapshot? {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        if observer == nil {
            observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
                MainActor.assumeIsolated { invalidateSnapshots() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        let key = boundary ?? source
        let entry: Entry
        if let existing = entries.object(forKey: key) { entry = existing }
        else {
            // Bound retained snapshot memory for screens with many transient panels.
            if entries.count >= 16 { entries.removeAllObjects() }
            entry = Entry()
            entries.setObject(entry, forKey: key)
        }
        let width = Int(ceil(rect.width * scale))
        let height = Int(ceil(rect.height * scale))
        guard width > 0, height > 0 else { return nil }
        if entry.epoch == epoch, entry.sourceID == ObjectIdentifier(source),
           entry.sourceBounds == source.bounds, entry.rect == rect, entry.scale == scale,
           let image = entry.image { return Snapshot(image: image, rect: rect) }
        let sameGeometry = entry.sourceID == ObjectIdentifier(source)
            && entry.sourceBounds == source.bounds && entry.rect == rect && entry.scale == scale
        if entry.context?.width != width || entry.context?.height != height {
            entry.context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: ((width * 4 + 63) / 64) * 64,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        }
        guard let context = entry.context else { return nil }
        withForegroundExcluded(owner: boundary, source: source, captureRect: rect) {
            let fingerprint = ExperimentalGlassLayerFingerprint.make(source.layer)
            if sameGeometry, let fingerprint, fingerprint == entry.fingerprint, entry.image != nil {
                return
            }
            // Drop the previous image before writing its backing bitmap (COW).
            entry.image = nil
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.saveGState()
            context.scaleBy(x: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            treeRenderCount += 1
            source.layer.render(in: context)
            context.restoreGState()
            entry.image = context.makeImage()
            entry.fingerprint = fingerprint
        }
        guard let image = entry.image else { return nil }
        entry.epoch = epoch
        entry.sourceID = ObjectIdentifier(source)
        entry.sourceBounds = source.bounds
        entry.rect = rect
        entry.scale = scale
        return Snapshot(image: image, rect: rect)
    }

    private static func withForegroundExcluded<T>(owner: UIView?, source: UIView, captureRect: CGRect,
                                                  body: () -> T) -> T {
        // Prune foreground branches in the model tree for the duration of
        // render(in:). Restore before the transaction commits: no visible hide,
        // no feedback from this glass or the content drawn above it.
        var excluded: [(CALayer, Bool)] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let owner {
            var branch: CALayer? = owner.layer
            while let current = branch, current !== source.layer, let parent = current.superlayer {
                let siblings = parent.sublayers ?? []
                if let index = siblings.firstIndex(where: { $0 === current }) {
                    for (position, sibling) in siblings.enumerated() where sibling === current && current === owner.layer
                        || sibling.zPosition > current.zPosition
                        || (sibling.zPosition == current.zPosition && position > index) {
                        excluded.append((sibling, sibling.isHidden))
                        sibling.isHidden = true
                    }
                }
                branch = parent
            }
        }
        // CGContext clipping alone does not prevent CALayer.render from
        // preparing offscreen subtrees (including masks and visual effects).
        // Prune branches which cannot contribute any pixels to this capture.
        // Do not assume a non-clipping parent's bounds enclose its children.
        func covers(_ layer: CALayer, region: CGRect) -> Bool {
            guard !layer.isHidden, layer.opacity == 1, layer.mask == nil,
                  layer.compositingFilter == nil,
                  (layer.filters ?? []).isEmpty, (layer.backgroundFilters ?? []).isEmpty,
                  CATransform3DIsAffine(layer.transform), CATransform3DIsAffine(layer.sublayerTransform),
                  !region.isEmpty, !region.isNull else { return false }
            let interior = layer.bounds.insetBy(dx: layer.cornerRadius, dy: layer.cornerRadius)
            if layer.masksToBounds && !interior.contains(region) { return false }
            if layer.backgroundColor?.alpha == 1 && interior.contains(region) { return true }
            return (layer.sublayers ?? []).contains { covers($0, region: $0.convert(region, from: layer)) }
        }
        func orderedChildren(_ layer: CALayer) -> [CALayer] {
            (layer.sublayers ?? []).enumerated().sorted {
                $0.element.zPosition == $1.element.zPosition ? $0.offset < $1.offset
                    : $0.element.zPosition < $1.element.zPosition
            }.map(\.element)
        }
        func pruneChildren(_ layer: CALayer, region: CGRect) -> Bool {
            var covered = false
            var hasVisibleChild = false
            for child in orderedChildren(layer).reversed() {
                if child.isHidden { continue }
                if covered {
                    excluded.append((child, false))
                    child.isHidden = true
                    continue
                }
                let childRegion = child.convert(region, from: layer)
                if prune(child, region: childRegion) {
                    hasVisibleChild = true
                    if layer.opacity == 1 && CATransform3DIsAffine(layer.sublayerTransform) {
                        covered = covers(child, region: childRegion)
                    }
                }
            }
            return hasVisibleChild
        }
        func prune(_ layer: CALayer, region: CGRect) -> Bool {
            if layer.isHidden || layer.opacity == 0 { return false }
            guard CATransform3DIsAffine(layer.sublayerTransform),
                  CATransform3DIsAffine(layer.transform) else { return true }
            let intersects = layer.bounds.intersects(region)
            if layer.masksToBounds && !intersects && layer.shadowOpacity == 0 {
                excluded.append((layer, false))
                layer.isHidden = true
                return false
            }
            let childRegion = layer.masksToBounds ? region.intersection(layer.bounds) : region
            let hasVisibleChild = pruneChildren(layer, region: childRegion)
            // Shapes, emitters and replicators may draw outside their bounds.
            // Shadows/filter output are also retained conservatively.
            let hasUnboundedOutput = layer is CAShapeLayer || layer is CAEmitterLayer
                || layer is CAReplicatorLayer || layer is CATransformLayer
                || layer.shadowOpacity > 0 || !(layer.filters ?? []).isEmpty
            // A plain empty wrapper contributes no pixels. Its transform or
            // animation must not invalidate the background after its entire
            // menu/sheet foreground has been excluded.
            let emptyWrapper = layer.isMember(of: CALayer.self) && layer.contents == nil
                && (layer.backgroundColor?.alpha ?? 0) == 0 && layer.borderWidth == 0
                && layer.compositingFilter == nil && (layer.backgroundFilters ?? []).isEmpty
            if !hasVisibleChild && !hasUnboundedOutput && emptyWrapper {
                excluded.append((layer, false))
                layer.isHidden = true
                return false
            }
            if !intersects && !hasVisibleChild && !hasUnboundedOutput {
                excluded.append((layer, false))
                layer.isHidden = true
                return false
            }
            return true
        }
        _ = pruneChildren(source.layer, region: captureRect)
        defer {
            for (layer, hidden) in excluded.reversed() { layer.isHidden = hidden }
            CATransaction.commit()
        }
        return body()
    }
}
