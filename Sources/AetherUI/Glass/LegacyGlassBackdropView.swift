import UIKit

#if !APPSTORE_SAFE
private let backdropLayerClass: NSObject? = {
    return NSClassFromString(ObfuscatedSymbols.caBackdropClass) as AnyObject as? NSObject
}()

private func getMethod<T>(object: NSObject, selector: String) -> T? {
    guard let method = object.method(for: NSSelectorFromString(selector)) else {
        return nil
    }
    return unsafeBitCast(method, to: T.self)
}

private typealias BackdropLayerObjectMethod =
    @convention(c) (AnyObject, Selector) -> Unmanaged<NSObject>?

private var cachedBackdropLayerAllocMethod: (BackdropLayerObjectMethod, Selector)?
private func createBackdropLayerObject() -> Unmanaged<NSObject>? {
    guard let backdropLayerClass else {
        return nil
    }
    if let cachedBackdropLayerAllocMethod {
        return cachedBackdropLayerAllocMethod.0(backdropLayerClass, cachedBackdropLayerAllocMethod.1)
    }
    let selector = NSSelectorFromString("alloc")
    guard let method: BackdropLayerObjectMethod = getMethod(object: backdropLayerClass, selector: "alloc") else {
        return nil
    }
    cachedBackdropLayerAllocMethod = (method, selector)
    return method(backdropLayerClass, selector)
}

private var cachedBackdropLayerInitMethod: (BackdropLayerObjectMethod, Selector)?
private func initializeBackdropLayerObject(_ object: NSObject) -> Unmanaged<NSObject>? {
    if let cachedBackdropLayerInitMethod {
        return cachedBackdropLayerInitMethod.0(object, cachedBackdropLayerInitMethod.1)
    }
    let selector = NSSelectorFromString("init")
    guard let method: BackdropLayerObjectMethod = getMethod(object: object, selector: "init") else {
        return nil
    }
    cachedBackdropLayerInitMethod = (method, selector)
    return method(object, selector)
}

private func makeBackdropLayerObject() -> CALayer? {
    // `alloc/init` returns a +1 Objective-C object. Transfer that ownership to
    // ARC exactly once; treating both results as unretained leaks the layer and
    // every render/filter resource hanging off it.
    guard
        let allocated = createBackdropLayerObject()?.takeUnretainedValue(),
        let initialized = initializeBackdropLayerObject(allocated)?.takeRetainedValue()
    else {
        return nil
    }
    return initialized as? CALayer
}

private var cachedBackdropLayerSetScaleMethod: (@convention(c) (NSObject, Selector, Double) -> Void, Selector)?
private func setBackdropLayerScale(object: NSObject, scale: Double) {
    if let cachedBackdropLayerSetScaleMethod {
        cachedBackdropLayerSetScaleMethod.0(object, cachedBackdropLayerSetScaleMethod.1, scale)
        return
    }
    let selectorName = ObfuscatedSymbols.setScale
    let selector = NSSelectorFromString(selectorName)
    guard let method: (@convention(c) (AnyObject, Selector, Double) -> Void) = getMethod(object: object, selector: selectorName) else {
        return
    }
    cachedBackdropLayerSetScaleMethod = (method, selector)
    method(object, selector, scale)
}
#endif

private final class LegacyGlassNullAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
    }
}

private final class LegacyGlassBackdropDelegate: NSObject, CALayerDelegate {
    private let nullAction = LegacyGlassNullAction()

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nullAction
    }
}

public final class LegacyGlassBackdropView: UIView {
    public enum Style: Equatable {
        case normal
        case clear
    }

    private struct Params: Equatable {
        let size: CGSize
        let cornerRadius: CGFloat
        let style: Style
    }

    /// Resolved backend at init time. Snapshotting the global config
    /// here means an in-flight glass surface keeps the backend it was
    /// born with even if `AetherGlassConfig.current` is mutated later.
    private let backend: LegacyBlurBackend

    /// Custom (CABackdropLayer) backend state. Non-nil iff `backend == .custom`.
    private let backdropLayer: CALayer?
    private let backdropLayerDelegate = LegacyGlassBackdropDelegate()

    /// VisualEffectView backend state. Non-nil iff `backend == .visualEffectView`.
    private let visualEffectView: VisualEffectView?

    private var params: Params?

    var hasBackdropLayer: Bool {
        return backdropLayer != nil
    }

    public override init(frame: CGRect) {
        let configuredBackend = AetherGlassConfig.current.legacyBlurBackend
        #if !APPSTORE_SAFE
        let backend = configuredBackend
        #else
        let backend: LegacyBlurBackend
        switch configuredBackend {
        case .custom:
            backend = .visualEffectView()
        case .visualEffectView:
            backend = configuredBackend
        }
        #endif
        self.backend = backend

        switch backend {
        case .custom:
            #if !APPSTORE_SAFE
            self.backdropLayer = makeBackdropLayerObject()
            self.visualEffectView = nil
            #else
            self.backdropLayer = nil
            self.visualEffectView = VisualEffectView()
            #endif
        case let .visualEffectView(blurRadius, tintColor, tintColorAlpha, saturation):
            self.backdropLayer = nil
            let v = VisualEffectView()
            v.style = .customBlur
            v.colorTint = tintColor
            v.colorTintAlpha = tintColorAlpha
            v.blurRadius = blurRadius
            v.saturation = saturation
            v.scale = 1.0
            self.visualEffectView = v
        }

        super.init(frame: frame)

        clipsToBounds = true
        layer.cornerCurve = .continuous

        if let backdropLayer {
            layer.addSublayer(backdropLayer)
            backdropLayer.delegate = backdropLayerDelegate
            #if !APPSTORE_SAFE
            setBackdropLayerScale(object: backdropLayer, scale: Double(UIScreen.main.scale))
            #endif
            backdropLayer.rasterizationScale = UIScreen.main.scale
        }

        if let visualEffectView {
            visualEffectView.frame = bounds
            visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(visualEffectView)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        backdropLayer?.delegate = nil
        backdropLayer?.filters = nil
        backdropLayer?.removeFromSuperlayer()
    }

    func update(size: CGSize, cornerRadius: CGFloat, style: Style, transition: ContainedViewLayoutTransition) {
        let params = Params(size: size, cornerRadius: cornerRadius, style: style)
        let previousStyle = self.params?.style
        self.params = params

        transition.updateCornerRadius(layer: layer, cornerRadius: cornerRadius)

        // VisualEffectView backend has nothing per-style to do —
        // `blurRadius`/`saturation` were set at init from the
        // AetherGlassConfig snapshot. The host view's `clipsToBounds`
        // + `layer.cornerRadius` (set above) shapes the round pill,
        // and `autoresizingMask` keeps the effect view filling the
        // bounds.
        if visualEffectView != nil {
            return
        }

        guard let backdropLayer else {
            return
        }

        #if !APPSTORE_SAFE
        if previousStyle != style {
            if let blurFilter = CALayer.blur(), let colorMatrixFilter = CALayer.aetherMatrixFilter() {
                // Bigger radius = more pixel mixing = less of any single
                // colour dominating the blur. With the previous 8pt
                // radius and a saturated backdrop (chips, photos) the
                // blur looked like "vivid colour swatches" instead of
                // softened glass. 14pt brings it closer to UIBlurEffect's
                // own kernel and reads as proper material.
                switch style {
                case .clear:
                    blurFilter.setValue(10.0 as NSNumber, forKey: ObfuscatedSymbols.filterRadiusKey)
                case .normal:
                    blurFilter.setValue(14.0 as NSNumber, forKey: ObfuscatedSymbols.filterRadiusKey)
                }

                // Original saturation+brightness boost matrix —
                // diagonal coefficients ~2.7, sum-of-row ~1.5. Approximates
                // Apple's stock material vibrancy. Bumps colour saturation
                // and brightness so the blur reads as "lit" frosted
                // material rather than a flat veil. Now that the
                // legacy-only underlay (in MenuGlassSurfaceView) and
                // tint floor (in the modal) flatten the backdrop sample
                // before it hits this filter, the boost no longer "burns"
                // saturated photos through — the underlay tames the
                // input and the matrix takes care of the look on top.
                var matrix: [Float32] = [
                    2.6705, -1.1087999, -0.1117, 0.0, 0.049999997,
                    -0.3295, 1.8914, -0.111899994, 0.0, 0.049999997,
                    -0.3297, -1.1084, 2.8881, 0.0, 0.049999997,
                    0.0, 0.0, 0.0, 1.0, 0.0
                ]
                let matrixValue = ObfuscatedSymbols.caColorMatrixObjCType.withCString {
                    NSValue(bytes: &matrix, objCType: $0)
                }
                colorMatrixFilter.setValue(matrixValue, forKey: ObfuscatedSymbols.inputColorMatrix)
                colorMatrixFilter.setValue(true as NSNumber, forKey: ObfuscatedSymbols.inputBackdropAware)

                switch style {
                case .clear:
                    backdropLayer.filters = [blurFilter]
                case .normal:
                    backdropLayer.filters = [colorMatrixFilter, blurFilter]
                }
            }
        }
        #endif

        transition.updateFrame(layer: backdropLayer, frame: CGRect(origin: .zero, size: size))
    }

    /// Geometry-only path used by interruptible chrome transitions.
    ///
    /// The regular `update` method may rebuild filters when style changes.
    /// During a gesture the style is stable, so touching only the bounds and
    /// mask shape avoids rebuilding the legacy material at display-link rate.
    func updateInteractiveGeometry(size: CGSize, cornerRadius: CGFloat) {
        let style = params?.style ?? .normal
        params = Params(size: size, cornerRadius: cornerRadius, style: style)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(origin: .zero, size: size)
        layer.cornerRadius = cornerRadius
        backdropLayer?.frame = CGRect(origin: .zero, size: size)
        visualEffectView?.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()
    }
}
