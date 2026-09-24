import UIKit

/// Compare the model-layer inputs consumed by direct capture. Foreground and
/// off-region branches have already been excluded. A changing background is
/// recaptured; moving menu/sheet foreground does not invalidate its backdrop.
@MainActor
enum ExperimentalGlassLayerFingerprint {
    static var lastBypass = "none"
    static func make(_ root: CALayer) -> Int? {
        if ExperimentalGlassDiagnostics.enabled { lastBypass = "none" }
        var hash = Hasher()
        func object(_ value: Any?) {
            if let value { hash.combine(ObjectIdentifier(value as AnyObject)) }
            else { hash.combine(0) }
        }
        func color(_ value: CGColor?) {
            hash.combine(value?.components)
            hash.combine(value?.colorSpace?.name as String?)
        }
        func rect(_ value: CGRect) {
            hash.combine(value.origin.x); hash.combine(value.origin.y)
            hash.combine(value.width); hash.combine(value.height)
        }
        func visit(_ layer: CALayer) -> Bool {
            hash.combine(ObjectIdentifier(layer))
            hash.combine(layer.isHidden)
            if layer.isHidden { return true }
            hash.combine(layer.opacity)
            if layer.opacity == 0 { return true }
            // Do not retain captures across animations or procedural CA output.
            guard (layer.animationKeys() ?? []).isEmpty,
                  (layer.filters ?? []).isEmpty, (layer.backgroundFilters ?? []).isEmpty,
                  layer.compositingFilter == nil,
                  !(layer is CAEmitterLayer), !(layer is CAReplicatorLayer) else {
                if ExperimentalGlassDiagnostics.enabled {
                    lastBypass = "\(type(of: layer)) delegate=\(layer.delegate.map { String(describing: type(of: $0)) } ?? "nil") animations=\(layer.animationKeys() ?? []) filters=\(layer.filters ?? []) backgroundFilters=\(layer.backgroundFilters ?? [])"
                }
                return false
            }
            rect(layer.bounds); rect(layer.contentsRect); rect(layer.contentsCenter)
            hash.combine(layer.position.x); hash.combine(layer.position.y)
            hash.combine(layer.anchorPoint.x); hash.combine(layer.anchorPoint.y)
            hash.combine(layer.anchorPointZ); hash.combine(layer.zPosition)
            hash.combine(NSValue(caTransform3D: layer.transform))
            hash.combine(NSValue(caTransform3D: layer.sublayerTransform))
            hash.combine(layer.contentsScale); hash.combine(layer.contentsGravity.rawValue)
            hash.combine(layer.minificationFilter.rawValue); hash.combine(layer.magnificationFilter.rawValue)
            hash.combine(layer.minificationFilterBias)
            hash.combine(layer.masksToBounds); hash.combine(layer.cornerRadius)
            hash.combine(layer.maskedCorners.rawValue); hash.combine(layer.cornerCurve.rawValue)
            hash.combine(layer.borderWidth); color(layer.borderColor); color(layer.backgroundColor)
            hash.combine(layer.shadowOpacity); hash.combine(layer.shadowRadius)
            hash.combine(layer.shadowOffset.width); hash.combine(layer.shadowOffset.height)
            color(layer.shadowColor); object(layer.shadowPath)
            hash.combine(layer.isOpaque); hash.combine(layer.isDoubleSided)
            hash.combine(layer.allowsGroupOpacity); hash.combine(layer.shouldRasterize)
            hash.combine(layer.rasterizationScale); object(layer.contents)
            if let shape = layer as? CAShapeLayer {
                object(shape.path); color(shape.fillColor); color(shape.strokeColor)
                hash.combine(shape.fillRule.rawValue); hash.combine(shape.lineWidth)
                hash.combine(shape.lineCap.rawValue); hash.combine(shape.lineJoin.rawValue)
                hash.combine(shape.miterLimit); hash.combine(shape.lineDashPhase)
                hash.combine(shape.lineDashPattern); hash.combine(shape.strokeStart); hash.combine(shape.strokeEnd)
            }
            if let text = layer as? CATextLayer {
                // CATextLayer can contain a mutable attributed string.
                hash.combine(String(describing: text.string))
                object(text.font); hash.combine(text.fontSize); color(text.foregroundColor)
                hash.combine(text.isWrapped); hash.combine(text.alignmentMode.rawValue)
                hash.combine(text.truncationMode.rawValue)
            }
            if let gradient = layer as? CAGradientLayer {
                hash.combine(gradient.type.rawValue); hash.combine(gradient.locations)
                hash.combine(gradient.startPoint.x); hash.combine(gradient.startPoint.y)
                hash.combine(gradient.endPoint.x); hash.combine(gradient.endPoint.y)
                for value in gradient.colors ?? [] { color(value as! CGColor) }
            }
            if let mask = layer.mask, !visit(mask) { return false }
            hash.combine(layer.sublayers?.count ?? 0)
            for child in layer.sublayers ?? [] where !visit(child) { return false }
            return true
        }
        return visit(root) ? hash.finalize() : nil
    }
}
