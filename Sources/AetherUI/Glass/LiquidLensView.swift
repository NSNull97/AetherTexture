import UIKit
import AsyncDisplayKit

private final class LiquidLensRestingBackgroundView: UIVisualEffectView {
    private var isDarkValue: Bool?

    private static func matrixValues(isDark: Bool) -> [Float32] {
        if isDark {
            return [
                1.082, -0.113, -0.011, 0.0, 0.135,
                -0.034, 1.003, -0.011, 0.0, 0.135,
                -0.034, -0.113, 1.105, 0.0, 0.135,
                0.0, 0.0, 0.0, 1.0, 0.0
            ]
        } else {
            return [
                1.185, -0.05, -0.005, 0.0, -0.2,
                -0.015, 1.15, -0.005, 0.0, -0.2,
                -0.015, -0.05, 1.195, 0.0, -0.2,
                0.0, 0.0, 0.0, 1.0, 0.0
            ]
        }
    }

    init() {
        super.init(effect: UIBlurEffect(style: .light))

        clipsToBounds = true
        #if !APPSTORE_SAFE
        for subview in subviews where String(describing: type(of: subview)).contains(ObfuscatedSymbols.visualEffectSubviewSuffix) {
            subview.isHidden = true
        }
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Once the owning component has supplied an explicit appearance,
        // a later system trait change must not silently replace it. This is
        // important for glass hosted on a per-screen dark surface while the
        // application itself is light (and vice versa).
        guard isDarkValue == nil else { return }
        update(isDark: traitCollection.userInterfaceStyle == .dark)
    }

    func update(isDark: Bool) {
        guard isDarkValue != isDark else {
            return
        }
        isDarkValue = isDark
        overrideUserInterfaceStyle = isDark ? .dark : .light

        #if APPSTORE_SAFE
        contentView.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.05)
        #else
        guard let filter = CALayer.aetherMatrixFilter() else {
            contentView.backgroundColor = isDark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.black.withAlphaComponent(0.05)
            return
        }

        var matrix = Self.matrixValues(isDark: isDark)
        let matrixValue = ObfuscatedSymbols.caColorMatrixObjCType.withCString {
            NSValue(bytes: &matrix, objCType: $0)
        }
        filter.setValue(matrixValue, forKey: ObfuscatedSymbols.inputColorMatrix)

        if let sublayer = layer.sublayers?.first {
            sublayer.filters = [filter]
            sublayer.isOpaque = false
            sublayer.backgroundColor = nil
            sublayer.setValue(1.0, forKey: ObfuscatedSymbols.scale)
        }
        #endif
    }
}

private final class LiquidLensDisplayLinkTarget: NSObject {
    var action: (() -> Void)?

    @objc func step() {
        action?()
    }
}

private final class LiquidLensDisplayLink {
    private let target: LiquidLensDisplayLinkTarget
    private let displayLink: CADisplayLink

    init(action: @escaping () -> Void) {
        let target = LiquidLensDisplayLinkTarget()
        target.action = action
        self.target = target
        self.displayLink = CADisplayLink(target: target, selector: #selector(LiquidLensDisplayLinkTarget.step))
        if #available(iOS 15.0, *) {
            self.displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 120.0, preferred: 120.0)
        }
        self.displayLink.add(to: .main, forMode: .common)
    }

    func invalidate() {
        displayLink.invalidate()
    }
}

public final class LiquidLensView: UIView, AetherAppearanceConsumer {
    public final class TransitionInfo {
        public let disableAnimationWorkarounds: Bool

        public init(disableAnimationWorkarounds: Bool) {
            self.disableAnimationWorkarounds = disableAnimationWorkarounds
        }
    }

    public enum Kind {
        case externalContainer
        case builtinContainer
        case noContainer
    }

    private struct Params: Equatable {
        let size: CGSize
        let cornerRadius: CGFloat?
        let selectionOrigin: CGPoint
        let selectionSize: CGSize
        let inset: CGFloat
        let liftedInset: CGFloat
        let isDark: Bool
        let isLifted: Bool
        let isCollapsed: Bool

        func with(isDark: Bool) -> Params {
            Params(
                size: size,
                cornerRadius: cornerRadius,
                selectionOrigin: selectionOrigin,
                selectionSize: selectionSize,
                inset: inset,
                liftedInset: liftedInset,
                isDark: isDark,
                isLifted: isLifted,
                isCollapsed: isCollapsed
            )
        }
    }

    private struct LensParams: Equatable {
        let baseFrame: CGRect
        let inset: CGFloat
        let liftedInset: CGFloat
        let isLifted: Bool
    }

    private let kind: Kind
    private let containerView = UIView()
    private var backgroundContainer: GlassBackgroundContainerView?
    private var genericBackgroundContainer: UIView?
    private var backgroundView: GlassBackgroundView?
    private var lensView: UIView?
    private let liftedContainerView = UIView()
    public let contentView = UIView()
    private var restingBackgroundView: LiquidLensRestingBackgroundView?

    // Classic Legacy renderer. UIKit's public chrome material supplies the
    // familiar pre-Liquid blur without entering the UIGlassEffect/private
    // lens pipeline. It never uses a private CAFilter, blob mask, native
    // liquid-lens object, or display-link-driven deformation.
    private var classicTrackView: UIVisualEffectView?
    private var classicSelectionView: UIVisualEffectView?
    private var classicSelectedClipView: UIView?

    private var legacySelectionView: GlassBackgroundView.ContentImageView?
    private var legacyContentMaskView: UIView?
    #if APPSTORE_SAFE
    private var safeLegacyContentMaskLayer: CAShapeLayer?
    #endif
    private var legacyContentMaskBlobNode: ASImageNode?
    private var legacyLiftedContentBlobMaskNode: ASImageNode?
    /// Explicit selection thumb for the legacy path. The original
    /// `legacySelectionView` is a template-tinted image surface with a
    /// stretchable image and a luminance mask — it works on iOS 26+
    /// where the native lens drives geometry, but on iOS 15 we observed
    /// the visual chrome staying anchored to the first slot while the
    /// underlying mask blob moved, so the user saw "selection text
    /// changes but the white pill stays put". A plain UIView with a
    /// resolvable solid colour and an explicit frame update side-steps
    /// image-surface caching entirely.
    private var legacyThumbView: UIView?

    public var selectedContentView: UIView {
        liftedContainerView
    }

    /// Enables hit testing for controls hosted inside `contentView`.
    /// Disabled by default because most lens users render visual-only
    /// content and keep their controls outside the punched-out layer.
    public var allowsContentInteraction: Bool = false {
        didSet {
            containerView.isUserInteractionEnabled = allowsContentInteraction
        }
    }

    public var glassStyle: GlassBackgroundView.Style = .regular {
        didSet {
            backgroundView?.updateStyle(glassStyle)
        }
    }

    /// Material tint used by the lens track. Defaults to the standard panel
    /// tone; floating chrome can opt into an untinted, backdrop-adaptive
    /// material without changing the selection content colors.
    public var glassTintColor = GlassBackgroundView.TintColor(kind: .panel) {
        didSet {
            guard glassTintColor != oldValue else { return }
            if let params {
                update(params: params, transition: .immediate)
            }
        }
    }

    /// Explicit override for the `isDark` flag. When non-`nil`, wins over
    /// the `isDark:` parameter passed to `update(...)` and pins the lens
    /// tint/tone regardless of caller or system theme. Set once on the
    /// outer component and the lens stays consistent across layout passes
    /// — avoids the subtle-mismatch issue where the lens reads one theme
    /// while its parent glass reads another.
    public var isDarkAppearance: Bool? {
        didSet {
            guard isDarkAppearance != oldValue else { return }
            if let last = params {
                let resolvedIsDark = isDarkAppearance ?? requestedIsDark ?? last.isDark
                update(params: last.with(isDark: resolvedIsDark), transition: .immediate)
            } else if let isDarkAppearance {
                applyInternalAppearance(isDark: isDarkAppearance)
            }
        }
    }

    public var selectionOrigin: CGPoint? {
        params?.selectionOrigin
    }

    public var selectionSize: CGSize? {
        params?.selectionSize
    }

    public private(set) var isAnimating: Bool = false {
        didSet {
            if isAnimating != oldValue {
                onUpdatedIsAnimating?(isAnimating)
            }
        }
    }

    public var onUpdatedIsAnimating: ((Bool) -> Void)?
    public var isLiftedAnimationCompleted: (() -> Void)?

    private var params: Params?
    /// The last appearance requested by the caller, before applying the
    /// optional per-view override. It lets clearing an override restore the
    /// caller's intended style rather than the previously resolved value.
    private var requestedIsDark: Bool?
    private var appliedLensParams: LensParams?
    /// Reentrancy guard + queued update. While a lifted-state native
    /// animation is in flight further `updateLens` calls stash their params
    /// here and the alongside-closure re-applies once the animation lands.
    /// Port of `isApplyingLensParams` / `pendingLensParams` from upstream.
    private var isApplyingLensParams: Bool = false
    private var pendingLensParams: LensParams?
    private var nativeLensLiftedState: Bool?
    private var liftedDisplayLink: LiquidLensDisplayLink?
    private var appliedAppearanceStyle: AetherAppearanceStyle
    /// A hidden lens must not retain blur/effect views. TabBar uses this in
    /// Legacy, where selection is rendered by ordinary tab item states and
    /// the lens has no visual role at all.
    private var isRendererSuspended: Bool
    private weak var explicitLiftedContainerView: UIView?

    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    public convenience init(
        kind: Kind,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.init(
            kind: kind,
            appearanceStyle: appearanceStyle,
            renderingSuspended: false
        )
    }

    internal init(
        kind: Kind,
        appearanceStyle: AetherAppearanceStyle? = nil,
        renderingSuspended: Bool
    ) {
        self.kind = kind
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        self.appearanceStyleOverride = appearanceStyle
        self.isRendererSuspended = renderingSuspended

        super.init(frame: .zero)

        containerView.isUserInteractionEnabled = false
        contentView.backgroundColor = .clear
        liftedContainerView.backgroundColor = .clear
        if !renderingSuspended {
            installRenderer(for: appliedAppearanceStyle)
        }
        AetherAppearanceConsumerRegistry.register(self)
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let style = appearanceStyleOverride ?? appearance.style
        guard style != appliedAppearanceStyle else {
            if !isRendererSuspended, style == .legacy, let params {
                updateClassicRenderer(params: params, transition: .immediate)
            }
            return
        }
        appliedAppearanceStyle = style
        guard !isRendererSuspended else { return }
        installRenderer(for: style)
        if let params {
            update(params: params, transition: .immediate)
        }
    }

    /// Removes every renderer-owned view while keeping geometry/content state
    /// cached for a later Liquid reactivation. This is stronger than
    /// `isHidden`: no hidden UIVisualEffectView or glass pipeline survives.
    internal func setRendererSuspended(_ suspended: Bool) {
        guard suspended != isRendererSuspended else { return }
        isRendererSuspended = suspended
        if suspended {
            tearDownRenderer()
        } else {
            installRenderer(for: appliedAppearanceStyle)
            if let params {
                update(params: params, transition: .immediate)
            }
        }
    }

    private func installRenderer(for style: AetherAppearanceStyle) {
        tearDownRenderer()
        if style.usesLiquidGlass {
            installLiquidRenderer(for: style)
        } else {
            installClassicRenderer()
        }
    }

    private func tearDownRenderer() {
        liftedDisplayLink?.invalidate()
        liftedDisplayLink = nil
        lensView?.layer.removeAllAnimations()
        lensView?.removeFromSuperview()
        lensView = nil
        isApplyingLensParams = false
        pendingLensParams = nil
        appliedLensParams = nil
        nativeLensLiftedState = nil
        isAnimating = false

        restingBackgroundView?.effect = nil
        restingBackgroundView?.removeFromSuperview()
        restingBackgroundView = nil

        contentView.mask = nil
        contentView.layer.mask = nil
        liftedContainerView.mask = nil
        liftedContainerView.layer.mask = nil
        legacyContentMaskView?.layer.filters = nil
        legacyContentMaskView?.removeFromSuperview()
        legacyContentMaskView = nil
        #if APPSTORE_SAFE
        safeLegacyContentMaskLayer = nil
        #endif
        legacySelectionView?.removeFromSuperview()
        legacySelectionView = nil
        legacyThumbView?.removeFromSuperview()
        legacyThumbView = nil
        legacyContentMaskBlobNode?.view.removeFromSuperview()
        legacyContentMaskBlobNode = nil
        legacyLiftedContentBlobMaskNode?.view.removeFromSuperview()
        legacyLiftedContentBlobMaskNode = nil

        classicTrackView?.effect = nil
        classicTrackView?.removeFromSuperview()
        classicTrackView = nil
        classicSelectionView?.effect = nil
        classicSelectionView?.removeFromSuperview()
        classicSelectionView = nil
        classicSelectedClipView?.removeFromSuperview()
        classicSelectedClipView = nil

        contentView.removeFromSuperview()
        liftedContainerView.removeFromSuperview()
        containerView.removeFromSuperview()
        contentView.clipsToBounds = false
        liftedContainerView.clipsToBounds = false
        liftedContainerView.transform = .identity
        liftedContainerView.alpha = 1.0

        // Ask the reusable glass hosts to release native effects before their
        // last strong reference goes away. This also clears legacy backdrop
        // filters when switching from a Liquid fallback to true Legacy.
        backgroundView?.appearanceStyleOverride = .legacy
        backgroundContainer?.appearanceStyleOverride = .legacy
        backgroundView?.removeFromSuperview()
        backgroundContainer?.removeFromSuperview()
        genericBackgroundContainer?.removeFromSuperview()
        backgroundView = nil
        backgroundContainer = nil
        genericBackgroundContainer = nil
    }

    private func installClassicRenderer() {
        addSubview(containerView)

        if case .noContainer = kind {
            classicTrackView = nil
        } else {
            let track = UIVisualEffectView(
                effect: UIBlurEffect(style: .systemChromeMaterial)
            )
            track.isUserInteractionEnabled = false
            track.clipsToBounds = true
            track.layer.cornerCurve = .continuous
            containerView.addSubview(track)
            classicTrackView = track
        }

        let selection = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemChromeMaterial)
        )
        selection.isUserInteractionEnabled = false
        selection.clipsToBounds = true
        selection.layer.cornerCurve = .continuous
        containerView.addSubview(selection)
        classicSelectionView = selection

        contentView.clipsToBounds = true
        containerView.addSubview(contentView)

        let selectedClip = UIView()
        selectedClip.isUserInteractionEnabled = false
        selectedClip.clipsToBounds = true
        selectedClip.layer.cornerCurve = .continuous
        containerView.addSubview(selectedClip)
        selectedClip.addSubview(liftedContainerView)
        classicSelectedClipView = selectedClip
    }

    private func installLiquidRenderer(for style: AetherAppearanceStyle) {
        switch kind {
        case .builtinContainer:
            let container = GlassBackgroundContainerView()
            container.appearanceStyleOverride = style
            addSubview(container)
            backgroundContainer = container

            let background = GlassBackgroundView()
            background.appearanceStyleOverride = style
            background.updateStyle(glassStyle)
            container.contentView.addSubview(background)
            background.contentView.addSubview(containerView)
            backgroundView = background

        case .externalContainer:
            let host = UIView()
            addSubview(host)
            genericBackgroundContainer = host

            let background = GlassBackgroundView()
            background.appearanceStyleOverride = style
            background.updateStyle(glassStyle)
            host.addSubview(background)
            background.contentView.addSubview(containerView)
            backgroundView = background

        case .noContainer:
            let host = UIView()
            addSubview(host)
            host.addSubview(containerView)
            genericBackgroundContainer = host
        }

        lensView = makeNativeLensViewIfAvailable()
        if let lensView {
            installNativeLensRenderer(lensView)
        } else {
            installLiquidFallbackRenderer()
        }
    }

    private func makeNativeLensViewIfAvailable() -> UIView? {
        #if APPSTORE_SAFE
        return nil
        #else
        guard GlassCompatibility.isLiquidDesignAvailable,
              !GlassBackgroundView.useCustomGlassImpl,
              #available(iOS 26.0, *),
              let viewClass = NSClassFromString(ObfuscatedSymbols.uiLiquidLensView) as AnyObject? else {
            return nil
        }
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString(ObfuscatedSymbols.initWithRestingBackground)
        guard let allocated = viewClass.perform(allocSelector)?.takeUnretainedValue() as AnyObject? else {
            return nil
        }
        return allocated.perform(initSelector, with: UIView())?.takeUnretainedValue() as? UIView
        #endif
    }

    private func installNativeLensRenderer(_ lensView: UIView) {
        #if APPSTORE_SAFE
        // `makeNativeLensViewIfAvailable()` is compile-time disabled in safe
        // builds, so this branch is unreachable. Keep the symbol available to
        // the shared caller without exposing any private selector constants.
        _ = lensView
        return
        #else
        if let backgroundContainer {
            backgroundContainer.layer.zPosition = 1.0
        } else if let genericBackgroundContainer {
            genericBackgroundContainer.layer.zPosition = 1.0
        }
        lensView.layer.zPosition = 10.0

        let restingBackground = LiquidLensRestingBackgroundView()
        restingBackgroundView = restingBackground
        liftedContainerView.addSubview(restingBackground)
        containerView.addSubview(liftedContainerView)
        containerView.addSubview(lensView)
        containerView.addSubview(contentView)

        if let explicitLiftedContainerView {
            setNativeContainer(
                on: lensView,
                selectorName: ObfuscatedSymbols.setLiftedContainerView,
                view: explicitLiftedContainerView
            )
        } else if let backgroundContainer {
            setNativeContainer(
                on: lensView,
                selectorName: ObfuscatedSymbols.setLiftedContainerView,
                view: backgroundContainer.contentView
            )
        } else if let genericBackgroundContainer {
            setNativeContainer(
                on: lensView,
                selectorName: ObfuscatedSymbols.setLiftedContainerView,
                view: genericBackgroundContainer
            )
        }
        setNativeContainer(on: lensView, selectorName: ObfuscatedSymbols.setLiftedContentView, view: liftedContainerView)
        setNativeContainer(on: lensView, selectorName: ObfuscatedSymbols.setOverridePunchoutView, view: contentView)
        setNativeInt(on: lensView, selectorName: ObfuscatedSymbols.setLiftedContentMode, value: 1)
        setNativeInt(on: lensView, selectorName: ObfuscatedSymbols.setStyle, value: 1)
        setNativeBool(on: lensView, selectorName: ObfuscatedSymbols.setWarpsContentBelow, value: true)
        lensView.setValue(UIColor(white: 0.0, alpha: 0.1), forKey: ObfuscatedSymbols.restingBackgroundColor)
        #endif
    }

    /// Liquid Glass fallback for OS versions where the native lens is not
    /// available. It intentionally retains the existing mask/blob behavior;
    /// true Legacy never calls this method.
    private func installLiquidFallbackRenderer() {

        let selectionView = GlassBackgroundView.ContentImageView()
        selectionView.alpha = 0
        legacySelectionView = selectionView

        let thumb = UIView()
        thumb.clipsToBounds = true
        thumb.layer.cornerCurve = .continuous
        legacyThumbView = thumb
        if let backgroundView {
            backgroundView.contentView.insertSubview(thumb, at: 0)
        } else {
            containerView.insertSubview(thumb, at: 0)
        }

        let contentMask = UIView()
        #if APPSTORE_SAFE
        contentMask.backgroundColor = .clear
        let maskLayer = CAShapeLayer()
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.white.cgColor
        safeLegacyContentMaskLayer = maskLayer
        contentView.layer.mask = maskLayer
        #else
        contentMask.backgroundColor = .white
        if let filter = CALayer.aetherAlphaMaskFilter() {
            contentMask.layer.filters = [filter]
        }
        contentView.mask = contentMask
        #endif
        legacyContentMaskView = contentMask

        let maskBlob = ASImageNode()
        maskBlob.contentMode = .scaleToFill
        legacyContentMaskBlobNode = maskBlob
        contentMask.addSubview(maskBlob.view)

        let liftedMaskBlob = ASImageNode()
        liftedMaskBlob.contentMode = .scaleToFill
        legacyLiftedContentBlobMaskNode = liftedMaskBlob
        liftedContainerView.mask = liftedMaskBlob.view

        containerView.addSubview(contentView)
        containerView.addSubview(liftedContainerView)
    }

    deinit {
        liftedDisplayLink?.invalidate()
        restingBackgroundView?.effect = nil
        legacyContentMaskView?.layer.filters = nil
        legacySelectionView?.removeFromSuperview()
        legacyContentMaskBlobNode?.view.removeFromSuperview()
        legacyLiftedContentBlobMaskNode?.view.removeFromSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true
                || previousTraitCollection?.accessibilityContrast != traitCollection.accessibilityContrast else {
            return
        }
        if let params {
            if appliedAppearanceStyle == .legacy {
                updateClassicRenderer(params: params, transition: .immediate)
            } else {
                applyInternalAppearance(isDark: params.isDark)
            }
        }
    }

    public func setLiftedContainer(view: UIView) {
        explicitLiftedContainerView = view
        #if !APPSTORE_SAFE
        if let lensView {
            setNativeContainer(on: lensView, selectorName: ObfuscatedSymbols.setLiftedContainerView, view: view)
        }
        #endif
    }

    public func update(
        size: CGSize,
        cornerRadius: CGFloat? = nil,
        selectionOrigin: CGPoint,
        selectionSize: CGSize,
        inset: CGFloat,
        liftedInset: CGFloat = 4.0,
        isDark: Bool,
        isLifted: Bool,
        isCollapsed: Bool = false,
        transition: ContainedViewLayoutTransition
    ) {
        requestedIsDark = isDark
        // `isDarkAppearance` wins over the caller-supplied `isDark` so a
        // consumer can pin the lens theme once and not worry about every
        // call site threading the same value through.
        let resolvedIsDark = isDarkAppearance ?? isDark
        let params = Params(
            size: size,
            cornerRadius: cornerRadius,
            selectionOrigin: selectionOrigin,
            selectionSize: selectionSize,
            inset: inset,
            liftedInset: liftedInset,
            isDark: resolvedIsDark,
            isLifted: isLifted,
            isCollapsed: isCollapsed
        )
        if self.params == params {
            return
        }
        update(params: params, transition: transition)
    }

    private func update(params: Params, transition: ContainedViewLayoutTransition) {
        self.params = params
        applyInternalAppearance(isDark: params.isDark)

        let frame = CGRect(origin: .zero, size: params.size)
        transition.updateFrame(view: self, frame: frame)
        transition.updateFrame(view: containerView, frame: frame)

        if appliedAppearanceStyle == .legacy {
            updateClassicRenderer(params: params, transition: transition)
            liftedDisplayLink?.invalidate()
            liftedDisplayLink = nil
            return
        }

        if let backgroundContainer {
            transition.updateFrame(view: backgroundContainer, frame: frame)
            backgroundContainer.update(size: params.size, isDark: params.isDark, transition: transition)
        } else if let genericBackgroundContainer {
            transition.updateFrame(view: genericBackgroundContainer, frame: frame)
        }

        if let backgroundView {
            transition.updateFrame(view: backgroundView, frame: frame)
            backgroundView.update(
                size: params.size,
                cornerRadius: params.cornerRadius ?? (params.size.height * 0.5),
                isDark: params.isDark,
                tintColor: glassTintColor,
                isInteractive: true,
                isVisible: true,
                transition: transition
            )
        }

        let contentCornerRadius = params.cornerRadius ?? (params.size.height * 0.5)
        transition.updateFrame(view: contentView, frame: frame)
        transition.updateCornerRadius(layer: contentView.layer, cornerRadius: contentCornerRadius)
        transition.updateFrame(view: liftedContainerView, frame: frame)
        transition.updateCornerRadius(layer: liftedContainerView.layer, cornerRadius: contentCornerRadius)

        let lensParams = LensParams(
            baseFrame: CGRect(origin: params.selectionOrigin, size: params.selectionSize),
            inset: params.inset,
            liftedInset: params.liftedInset,
            isLifted: params.isLifted
        )
        updateLens(params: lensParams, transition: transition)
        updateLiquidFallbackMasks(params: params, lensParams: lensParams, transition: transition)

        if let restingBackgroundView {
            transition.updateFrame(view: restingBackgroundView, frame: frame)
            restingBackgroundView.update(isDark: params.isDark)
            transition.updateAlpha(
                view: restingBackgroundView,
                alpha: (params.isLifted || params.isCollapsed) ? 0.0 : 1.0
            )
        }

        if params.isLifted, appliedAppearanceStyle.usesLiquidGlass, lensView != nil {
            if liftedDisplayLink == nil {
                liftedDisplayLink = LiquidLensDisplayLink { [weak self] in
                    self?.updateLiftedLensPosition()
                }
            }
        } else {
            liftedDisplayLink?.invalidate()
            liftedDisplayLink = nil
        }
    }

    private func updateClassicRenderer(
        params: Params,
        transition: ContainedViewLayoutTransition
    ) {
        guard let selectionView = classicSelectionView,
              let selectedClipView = classicSelectedClipView else {
            return
        }

        let interfaceStyle: UIUserInterfaceStyle = params.isDark ? .dark : .light
        let colorTraits = UITraitCollection(traitsFrom: [
            traitCollection,
            UITraitCollection(userInterfaceStyle: interfaceStyle)
        ])
        let trackTokens = AetherLegacySurfaceTokens.resolve(
            role: .input,
            traitCollection: colorTraits
        )
        let selectionTokens = AetherLegacySurfaceTokens.resolve(
            role: .selectionIndicator,
            traitCollection: colorTraits
        )

        let fullFrame = CGRect(origin: .zero, size: params.size)
        let trackCornerRadius = params.cornerRadius ?? (params.size.height * 0.5)
        if let trackView = classicTrackView {
            trackView.overrideUserInterfaceStyle = interfaceStyle
            trackView.contentView.backgroundColor = UIAccessibility.isReduceTransparencyEnabled
                ? trackTokens.surfaceColor
                : .clear
            trackView.layer.cornerCurve = trackTokens.cornerCurve
            trackView.layer.borderColor = trackTokens.borderColor
                .resolvedColor(with: colorTraits)
                .cgColor
            trackView.layer.borderWidth = trackTokens.borderWidth
            transition.updateFrame(view: trackView, frame: fullFrame)
            transition.updateCornerRadius(
                layer: trackView.layer,
                cornerRadius: trackCornerRadius
            )
        }

        let rawSelectionFrame = CGRect(
            origin: params.selectionOrigin,
            size: params.selectionSize
        ).insetBy(dx: params.inset, dy: params.inset)
        let selectionFrame = CGRect(
            x: rawSelectionFrame.minX,
            y: rawSelectionFrame.minY,
            width: max(0, rawSelectionFrame.width),
            height: max(0, rawSelectionFrame.height)
        )
        let selectionCornerRadius = min(
            max(0, selectionFrame.height * 0.5),
            max(0, trackCornerRadius)
        )

        selectionView.overrideUserInterfaceStyle = interfaceStyle
        selectionView.contentView.backgroundColor = UIAccessibility.isReduceTransparencyEnabled
            ? selectionTokens.secondarySurfaceColor
            : selectionTokens.secondarySurfaceColor.withAlphaComponent(0.22)
        selectionView.layer.cornerCurve = selectionTokens.cornerCurve
        selectionView.layer.borderColor = selectionTokens.borderColor
            .resolvedColor(with: colorTraits)
            .cgColor
        selectionView.layer.borderWidth = selectionTokens.borderWidth
        selectionView.layer.shadowColor = selectionTokens.shadowColor
            .resolvedColor(with: colorTraits)
            .cgColor
        selectionView.layer.shadowOpacity = selectionTokens.shadowOpacity
        selectionView.layer.shadowRadius = selectionTokens.shadowRadius
        selectionView.layer.shadowOffset = selectionTokens.shadowOffset
        selectionView.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: selectionFrame.size),
            cornerRadius: selectionCornerRadius
        ).cgPath
        transition.updateFrame(view: selectionView, frame: selectionFrame)
        transition.updateCornerRadius(
            layer: selectionView.layer,
            cornerRadius: selectionCornerRadius
        )

        contentView.overrideUserInterfaceStyle = interfaceStyle
        transition.updateFrame(view: contentView, frame: fullFrame)
        transition.updateCornerRadius(
            layer: contentView.layer,
            cornerRadius: trackCornerRadius
        )

        selectedClipView.overrideUserInterfaceStyle = interfaceStyle
        selectedClipView.layer.cornerCurve = selectionTokens.cornerCurve
        transition.updateFrame(view: selectedClipView, frame: selectionFrame)
        transition.updateCornerRadius(
            layer: selectedClipView.layer,
            cornerRadius: selectionCornerRadius
        )
        transition.updateFrame(
            view: liftedContainerView,
            frame: CGRect(
                x: -selectionFrame.minX,
                y: -selectionFrame.minY,
                width: params.size.width,
                height: params.size.height
            )
        )
        liftedContainerView.overrideUserInterfaceStyle = interfaceStyle

        let pressedTransform = params.isLifted
            ? CGAffineTransform(
                scaleX: selectionTokens.pressedScale,
                y: selectionTokens.pressedScale
            )
            : .identity
        let pressedAlpha = params.isLifted ? selectionTokens.pressedAlpha : 1.0
        transition.updateTransform(view: selectionView, transform: pressedTransform)
        transition.updateTransform(view: selectedClipView, transform: pressedTransform)
        transition.updateAlpha(view: selectionView, alpha: pressedAlpha)
        transition.updateAlpha(view: selectedClipView, alpha: pressedAlpha)
    }

    private func updateLens(params: LensParams, transition: ContainedViewLayoutTransition) {
        #if APPSTORE_SAFE
        return
        #else
        guard let lensView else {
            return
        }

        // Queue updates that arrive while a previous lifted-state animation
        // is still in flight — otherwise a fast tap-retap would trample the
        // first animation's callback and leave isApplyingLensParams stuck
        // true. Port of Telegram-iOS LiquidLensView.updateLens (§316-406).
        if isApplyingLensParams {
            pendingLensParams = params
            return
        }
        isApplyingLensParams = true
        let previousParams = appliedLensParams
        appliedLensParams = params

        let liftedInset = params.isLifted ? params.liftedInset : (-params.inset)
        let lensBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: params.baseFrame.width + liftedInset * 2.0,
                height: params.baseFrame.height + liftedInset * 2.0
            )
        )
        let lensCenter = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)

        if previousParams?.isLifted != params.isLifted {
            isAnimating = transition.isAnimated

            // Go through the private `setLifted:animated:alongsideAnimations:completion:`
            // selector ourselves rather than through the simple wrapper, so
            // the bounds update runs INSIDE the same native animation block
            // as the lift — no desync.
            let selector = NSSelectorFromString(ObfuscatedSymbols.setLiftedAnimatedAlongsideAnimationsCompletion)
            var didProcessUpdate = false
            var shouldScheduleUpdate = false
            pendingLensParams = params

            if let method = lensView.method(for: selector) {
                typealias Function = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, (() -> Void)?) -> Void
                let function = unsafeBitCast(method, to: Function.self)
                function(lensView, selector, params.isLifted, transition.isAnimated, { [weak self, weak lensView] in
                    // Alongside closure: resize bounds in lockstep with the
                    // native lift animation. No additive position fix here —
                    // setLifted path lands the center where the native
                    // animation ends anyway.
                    guard let self, let lensView, self.lensView === lensView else { return }
                    lensView.bounds = lensBounds
                    didProcessUpdate = true
                    if shouldScheduleUpdate {
                        DispatchQueue.main.async { [weak self, weak lensView] in
                            guard let self,
                                  let lensView,
                                  self.lensView === lensView,
                                  let pending = self.pendingLensParams else { return }
                            self.isApplyingLensParams = false
                            self.pendingLensParams = nil
                            self.updateLens(params: pending, transition: transition)
                        }
                    }
                }, { [weak self, weak lensView] in
                    guard let self, let lensView, self.lensView === lensView else { return }
                    if !self.isApplyingLensParams {
                        self.isAnimating = false
                    }
                    self.isLiftedAnimationCompleted?()
                })
            } else {
                // Fallback for older iOS / when setLifted isn't available —
                // just set the bounds directly. Matches setNativeLifted's
                // simple-selector path.
                lensView.bounds = lensBounds
                setNativeLifted(on: lensView, value: params.isLifted, animated: transition.isAnimated)
                didProcessUpdate = true
            }

            if didProcessUpdate {
                transition.updatePosition(view: lensView, position: lensCenter)
                pendingLensParams = nil
                isApplyingLensParams = false
            } else {
                // Native method invoked the alongside closure asynchronously —
                // the closure will clear these when it runs.
                shouldScheduleUpdate = true
            }
        } else {
            // Bounds and center share one semantic transition. Removing every
            // layer animation after `updateBounds` used to delete the animation
            // we had just created; the model jumped while `isAnimating` stayed
            // true forever. `beginFromCurrentState` in the transition keeps
            // rapid retargets continuous without destructive cleanup.
            isAnimating = transition.isAnimated
            transition.updateBounds(view: lensView, bounds: lensBounds)
            transition.updatePosition(view: lensView, position: lensCenter) { [weak self, weak lensView] _ in
                guard let self,
                      let lensView,
                      self.lensView === lensView,
                      self.appliedLensParams == params else { return }
                self.isAnimating = false
            }
            if !transition.isAnimated {
                isAnimating = false
            }
            isApplyingLensParams = false
        }
        #endif
    }

    private func updateLiftedLensPosition() {
        #if !APPSTORE_SAFE
        // Skip while a native-lift animation is mid-flight; the alongside
        // closure owns the lens transform for the duration and our per-frame
        // center write would fight it.
        if isApplyingLensParams { return }
        guard let lensView, let params = appliedLensParams else {
            return
        }
        lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
        #endif
    }

    private func updateLiquidFallbackMasks(params: Params, lensParams: LensParams, transition: ContainedViewLayoutTransition) {
        if let legacyContentMaskView {
            transition.updateFrame(view: legacyContentMaskView, frame: CGRect(origin: .zero, size: params.size))
        }

        guard let legacyContentMaskBlobNode,
              let legacyLiftedContentBlobMaskNode,
              let legacySelectionView else {
            return
        }

        let lensFrame = lensParams.baseFrame.insetBy(dx: lensParams.inset, dy: lensParams.inset)
        let effectiveLensFrame = lensFrame.insetBy(dx: lensParams.isLifted ? -2.0 : 0.0, dy: lensParams.isLifted ? -2.0 : 0.0)

        #if APPSTORE_SAFE
        if let maskLayer = safeLegacyContentMaskLayer {
            let path = UIBezierPath(rect: CGRect(origin: .zero, size: params.size))
            path.append(UIBezierPath(
                roundedRect: effectiveLensFrame,
                cornerRadius: effectiveLensFrame.height * 0.5
            ))
            path.usesEvenOddFillRule = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            maskLayer.frame = CGRect(origin: .zero, size: params.size)
            maskLayer.path = path.cgPath
            CATransaction.commit()
        }
        #endif

        if legacyContentMaskBlobNode.image?.size.height != lensFrame.height {
            let blobImage = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .black)
            legacyContentMaskBlobNode.image = blobImage
            legacyLiftedContentBlobMaskNode.image = blobImage
            legacySelectionView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .white)?.withRenderingMode(.alwaysTemplate)
        }

        transition.updateFrame(view: legacyContentMaskBlobNode.view, frame: effectiveLensFrame)
        transition.updateFrame(view: legacyLiftedContentBlobMaskNode.view, frame: effectiveLensFrame)
        transition.updateFrame(view: legacySelectionView, frame: effectiveLensFrame)

        // Plain UIView thumb — no image-view stretching, no template
        // re-tinting — just a coloured rounded rect that reliably moves
        // with the selection. `systemGray3` adapts per appearance so the
        // thumb reads as a neutral pill against any backdrop (white,
        // dark, busy). Alpha 0.55 keeps it visibly glass-like rather
        // than fully opaque chrome.
        if let legacyThumbView {
            transition.updateFrame(view: legacyThumbView, frame: effectiveLensFrame)
            legacyThumbView.backgroundColor = Self.legacyThumbColor(isDark: params.isDark)
            let cornerRadius = effectiveLensFrame.height * 0.5
            transition.updateCornerRadius(layer: legacyThumbView.layer, cornerRadius: cornerRadius)
        }
    }

    private static func legacyThumbColor(isDark: Bool) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        return UIColor.systemGray3.resolvedColor(with: traits).withAlphaComponent(0.55)
    }

    /// Pins every internal glass participant to the same resolved
    /// appearance. UIKit does not reliably propagate a view-local override
    /// through private/native visual-effect hosts, so forwarding only the
    /// boolean to `update(...)` leaves the container and thumb out of sync.
    private func applyInternalAppearance(isDark: Bool) {
        let interfaceStyle: UIUserInterfaceStyle = isDark ? .dark : .light
        backgroundContainer?.isDarkOverride = isDark
        backgroundView?.isDarkOverride = isDark
        genericBackgroundContainer?.overrideUserInterfaceStyle = interfaceStyle
        lensView?.overrideUserInterfaceStyle = interfaceStyle
        legacyThumbView?.overrideUserInterfaceStyle = interfaceStyle
        legacyThumbView?.backgroundColor = Self.legacyThumbColor(isDark: isDark)
        classicTrackView?.overrideUserInterfaceStyle = interfaceStyle
        classicSelectionView?.overrideUserInterfaceStyle = interfaceStyle
        classicSelectedClipView?.overrideUserInterfaceStyle = interfaceStyle
        restingBackgroundView?.update(isDark: isDark)
    }

    #if DEBUG
    internal var resolvedIsDarkForTesting: Bool? { params?.isDark }
    internal var legacyThumbColorForTesting: UIColor? { legacyThumbView?.backgroundColor }
    internal var legacyThumbInterfaceStyleForTesting: UIUserInterfaceStyle? {
        legacyThumbView?.overrideUserInterfaceStyle
    }
    internal var internalBackgroundDarkOverrideForTesting: Bool? {
        backgroundView?.isDarkOverride ?? backgroundContainer?.isDarkOverride
    }
    internal var usesClassicRendererForTesting: Bool {
        classicSelectionView != nil
            && lensView == nil
            && backgroundView == nil
            && backgroundContainer == nil
            && genericBackgroundContainer == nil
            && restingBackgroundView == nil
            && legacySelectionView == nil
            && legacyThumbView == nil
            && legacyContentMaskView == nil
            && legacyContentMaskBlobNode == nil
            && legacyLiftedContentBlobMaskNode == nil
            && liftedDisplayLink == nil
    }
    internal var classicSelectionFrameForTesting: CGRect? {
        classicSelectionView?.frame
    }
    internal var classicTrackBlurStyleForTesting: UIBlurEffect.Style? {
        classicTrackView?.effect is UIBlurEffect ? .systemChromeMaterial : nil
    }
    internal var classicSelectionBlurStyleForTesting: UIBlurEffect.Style? {
        classicSelectionView?.effect is UIBlurEffect ? .systemChromeMaterial : nil
    }
    internal var hasLiquidMaskForTesting: Bool {
        contentView.mask != nil
            || contentView.layer.mask != nil
            || liftedContainerView.mask != nil
            || liftedContainerView.layer.mask != nil
    }
    internal var rendererOwnedSubviewCountForTesting: Int {
        subviews.count + containerView.subviews.count
    }
    internal var isRendererSuspendedForTesting: Bool { isRendererSuspended }
    internal var hasInstalledRendererForTesting: Bool {
        classicTrackView != nil
            || classicSelectionView != nil
            || lensView != nil
            || backgroundView != nil
            || backgroundContainer != nil
            || genericBackgroundContainer != nil
            || restingBackgroundView != nil
            || legacySelectionView != nil
            || legacyThumbView != nil
            || legacyContentMaskView != nil
            || legacyContentMaskBlobNode != nil
            || legacyLiftedContentBlobMaskNode != nil
            || liftedDisplayLink != nil
    }
    #endif

    private func setNativeLifted(on view: UIView, value: Bool, animated: Bool) {
        #if !APPSTORE_SAFE
        let complexSelector = NSSelectorFromString(ObfuscatedSymbols.setLiftedAnimatedAlongsideAnimationsCompletion)
        if let method = view.method(for: complexSelector) {
            typealias Function = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, (() -> Void)?) -> Void
            let function = unsafeBitCast(method, to: Function.self)
            function(view, complexSelector, value, animated, {}, nil)
            return
        }

        let simpleSelector = NSSelectorFromString(ObfuscatedSymbols.setLifted)
        if let method = view.method(for: simpleSelector) {
            typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Void
            let function = unsafeBitCast(method, to: Function.self)
            function(view, simpleSelector, value)
        }
        #endif
    }

    private func setNativeContainer(on view: UIView, selectorName: String, view targetView: UIView) {
        #if !APPSTORE_SAFE
        let selector = NSSelectorFromString(selectorName)
        guard view.responds(to: selector) else {
            return
        }
        _ = view.perform(selector, with: targetView)
        #endif
    }

    private func setNativeBool(on view: UIView, selectorName: String, value: Bool) {
        #if !APPSTORE_SAFE
        let selector = NSSelectorFromString(selectorName)
        guard let method = view.method(for: selector) else {
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Void
        let function = unsafeBitCast(method, to: Function.self)
        function(view, selector, value)
        #endif
    }

    private func setNativeInt(on view: UIView, selectorName: String, value: Int32) {
        #if !APPSTORE_SAFE
        let selector = NSSelectorFromString(selectorName)
        guard let method = view.method(for: selector) else {
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Int32) -> Void
        let function = unsafeBitCast(method, to: Function.self)
        function(view, selector, value)
        #endif
    }
}

public typealias LiquidGlassView = LiquidLensView
