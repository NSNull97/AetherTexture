import UIKit
import AsyncDisplayKit

/// Glass slider that follows the native iOS 26 glass interaction model:
/// touches are delivered to real `GlassBackgroundView` surfaces, while
/// pan/tap gestures on the host only drive value changes.
public final class AetherSlider: UIControl, UIGestureRecognizerDelegate, AetherAppearanceConsumer {
    private enum Metrics {
        static let liquidPreferredHeight: CGFloat = 50.0
        static let legacyPreferredHeight: CGFloat = 44.0
        static let liquidTrackHeight: CGFloat = 32.0
        static let legacyTrackHeight: CGFloat = 4.0
        static let liquidThumbSize = CGSize(width: 44.0, height: 38.0)
        static let legacyThumbSize = CGSize(width: 28.0, height: 28.0)
        static let endpointImageSide: CGFloat = 24.0
        static let endpointImageSpacing: CGFloat = 8.0
    }

    public struct Theme: Equatable {
        public var minimumTrackTintColor: UIColor
        public var minimumTrackAlpha: CGFloat
        public var maximumTrackTint: GlassBackgroundView.TintColor
        public var thumbTint: GlassBackgroundView.TintColor

        public init(
            minimumTrackTintColor: UIColor = .systemBlue,
            minimumTrackAlpha: CGFloat = 0.82,
            maximumTrackTint: GlassBackgroundView.TintColor = .init(kind: .panel),
            thumbTint: GlassBackgroundView.TintColor = .init(kind: .panel)
        ) {
            self.minimumTrackTintColor = minimumTrackTintColor
            self.minimumTrackAlpha = minimumTrackAlpha
            self.maximumTrackTint = maximumTrackTint
            self.thumbTint = thumbTint
        }

        public static let system = Theme()
    }

    public var theme: Theme {
        didSet {
            guard theme != oldValue else { return }
            applyTheme()
            setNeedsLayout()
        }
    }

    public var minimumValue: Float = 0.0 {
        didSet {
            if maximumValue < minimumValue {
                maximumValue = minimumValue
            }
            setValue(_value, animated: false)
            updateLayout(transition: .immediate)
        }
    }

    public var maximumValue: Float = 1.0 {
        didSet {
            if minimumValue > maximumValue {
                minimumValue = maximumValue
            }
            setValue(_value, animated: false)
            updateLayout(transition: .immediate)
        }
    }

    public var value: Float {
        get { _value }
        set { setValue(newValue, animated: false) }
    }

    public var isContinuous: Bool = true
    public var valueChanged: (Float) -> Void = { _ in }

    /// Preferred height. Until explicitly set, the value follows the active
    /// appearance: 44pt for the iOS 18-compatible Legacy control and 50pt for
    /// Aether's Liquid Glass control.
    public var preferredHeight: CGFloat {
        get { preferredHeightOverride ?? defaultPreferredHeight }
        set {
            preferredHeightOverride = newValue
            invalidateIntrinsicContentSize()
        }
    }

    /// Track height. Its appearance-specific default can still be replaced by
    /// callers that need a custom slider geometry.
    public var trackHeight: CGFloat {
        get { trackHeightOverride ?? defaultTrackHeight }
        set {
            trackHeightOverride = newValue
            setNeedsLayout()
        }
    }

    /// Thumb size. Legacy defaults to the 28pt circular iOS 18 thumb.
    public var thumbSize: CGSize {
        get { thumbSizeOverride ?? defaultThumbSize }
        set {
            thumbSizeOverride = newValue
            setNeedsLayout()
        }
    }

    public var contentInsets: UIEdgeInsets = UIEdgeInsets(top: 6.0, left: 0.0, bottom: 6.0, right: 0.0) {
        didSet { setNeedsLayout() }
    }

    /// Optional system-style images shown at the minimum and maximum ends.
    /// Aether doesn't choose the symbols so product-specific semantics remain
    /// under the caller's control (for example, tortoise and hare).
    public var minimumValueImage: UIImage? {
        didSet {
            updateEndpointImages()
            setNeedsLayout()
        }
    }

    public var maximumValueImage: UIImage? {
        didSet {
            updateEndpointImages()
            setNeedsLayout()
        }
    }

    public var valueImageTintColor: UIColor = .secondaryLabel {
        didSet { updateEndpointImages() }
    }

    public var accessibilityStep: Float = 0.1

    public var appearanceStyleOverride: AetherAppearanceStyle? = nil {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            glassContainer.appearanceStyleOverride = appearanceStyleOverride
            trackGlass.appearanceStyleOverride = appearanceStyleOverride
            thumbGlass.appearanceStyleOverride = appearanceStyleOverride
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    public var isDarkAppearance: Bool? {
        didSet {
            glassContainer.isDarkOverride = isDarkAppearance
            trackGlass.isDarkOverride = isDarkAppearance
            thumbGlass.isDarkOverride = isDarkAppearance
            setNeedsLayout()
        }
    }

    public override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            panGestureRecognizer.isEnabled = isEnabled
            tapGestureRecognizer.isEnabled = isEnabled
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    private let glassContainer: GlassBackgroundContainerView
    private let trackGlass: GlassBackgroundView
    private let minimumFillView = GlassBackgroundView.ContentColorView()
    private let thumbGlass: GlassBackgroundView
    private let minimumValueImageNode = ASImageNode()
    private let maximumValueImageNode = ASImageNode()

    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var tapGestureRecognizer: UITapGestureRecognizer!
    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    private var _value: Float
    private var gestureThumbOffset: CGFloat = 0.0
    private var lastTrackFrame: CGRect = .zero
    private var lastThumbFrame: CGRect = .zero
    private var lastMinimumValueImageFrame: CGRect = .zero
    private var lastMaximumValueImageFrame: CGRect = .zero
    private var appliedAppearanceStyle: AetherAppearanceStyle
    private var preferredHeightOverride: CGFloat?
    private var trackHeightOverride: CGFloat?
    private var thumbSizeOverride: CGSize?

    public init(
        value: Float = 0.0,
        theme: Theme = .system,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.theme = theme
        self._value = min(max(value, 0.0), 1.0)
        self.minimumValueImage = nil
        self.maximumValueImage = nil
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        self.appearanceStyleOverride = appearanceStyle
        self.glassContainer = GlassBackgroundContainerView(
            spacing: 5.0,
            appearanceStyle: appearanceStyle
        )
        self.trackGlass = GlassBackgroundView(
            style: .regular,
            appearanceStyle: appearanceStyle
        )
        self.thumbGlass = GlassBackgroundView(
            style: .regular,
            appearanceStyle: appearanceStyle
        )
        super.init(frame: .zero)

        trackGlass.surfaceRole = .input
        thumbGlass.surfaceRole = .selectionIndicator

        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        accessibilityValue = formattedAccessibilityValue()

        addSubview(glassContainer)

        for imageNode in [minimumValueImageNode, maximumValueImageNode] {
            imageNode.contentMode = .scaleAspectFit
            imageNode.isUserInteractionEnabled = false
            imageNode.isAccessibilityElement = false
            addSubview(imageNode.view)
        }

        trackGlass.isUserInteractionEnabled = true
        thumbGlass.isUserInteractionEnabled = true
        glassContainer.contentView.addSubview(trackGlass)
        glassContainer.contentView.addSubview(thumbGlass)

        minimumFillView.isUserInteractionEnabled = false
        minimumFillView.clipsToBounds = true
        trackGlass.contentView.addSubview(minimumFillView)

        applyTheme()
        updateEndpointImages()
        installGestures()
        AetherAppearanceConsumerRegistry.register(self)
        aetherApplyAppearance(.runtimeCurrent, animated: false)
    }

    internal var backingUsesLiquidGlassAppearanceForTesting: Bool {
        trackGlass.usesLiquidGlassAppearance || thumbGlass.usesLiquidGlassAppearance
    }

    internal var backingUsesAnyGlassRendererForTesting: Bool {
        glassContainer.isUsingAnyGlassContainerEffect
            || trackGlass.usesAnyGlassRendererForTesting
            || thumbGlass.usesAnyGlassRendererForTesting
    }

    internal var backingLegacyBlurStylesForTesting: [UIBlurEffect.Style] {
        [trackGlass.legacyBlurStyleForTesting, thumbGlass.legacyBlurStyleForTesting]
            .compactMap { $0 }
    }

    internal var appliedAppearanceStyleForTesting: AetherAppearanceStyle {
        appliedAppearanceStyle
    }

    internal var trackFrameForTesting: CGRect { lastTrackFrame }
    internal var thumbFrameForTesting: CGRect { lastThumbFrame }
    internal var minimumValueImageFrameForTesting: CGRect { lastMinimumValueImageFrame }
    internal var maximumValueImageFrameForTesting: CGRect { lastMaximumValueImageFrame }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    public func setValue(_ value: Float, animated: Bool) {
        let clamped = clampedValue(value)
        guard clamped != _value else {
            return
        }
        _value = clamped
        accessibilityValue = formattedAccessibilityValue()
        updateLayout(transition: animated ? .animated(duration: 0.34, curve: .spring) : .immediate)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout(transition: .immediate)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
            updateEndpointImages()
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }
        if let result = glassContainer.hitTest(convert(point, to: glassContainer), with: event) {
            return result
        }
        if bounds.insetBy(dx: -8.0, dy: -10.0).contains(point) {
            return self
        }
        return nil
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return true
        }
        let velocity = panGestureRecognizer.velocity(in: self)
        if abs(velocity.y) > abs(velocity.x), !lastThumbFrame.insetBy(dx: -18.0, dy: -18.0).contains(panGestureRecognizer.location(in: self)) {
            return false
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    public override func accessibilityIncrement() {
        setValue(_value + resolvedAccessibilityStep(), animated: true)
        notifyValueChanged()
    }

    public override func accessibilityDecrement() {
        setValue(_value - resolvedAccessibilityStep(), animated: true)
        notifyValueChanged()
    }

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        addGestureRecognizer(pan)
        panGestureRecognizer = pan

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.require(toFail: pan)
        addGestureRecognizer(tap)
        tapGestureRecognizer = tap

    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let style = appearanceStyleOverride ?? appearance.style
        let geometryChanged = style != appliedAppearanceStyle
        appliedAppearanceStyle = style
        updateElasticPressRenderer(for: style)
        elasticRecognizer?.isEnabled = isEnabled
        let tokens = AetherLegacySurfaceTokens.resolve(role: .selectionIndicator, traitCollection: traitCollection)
        alpha = isEnabled ? 1 : (style.usesLiquidGlass ? 0.45 : tokens.disabledAlpha)
        if geometryChanged {
            invalidateIntrinsicContentSize()
        }
        setNeedsLayout()
    }

    private var defaultPreferredHeight: CGFloat {
        appliedAppearanceStyle.usesLiquidGlass ? Metrics.liquidPreferredHeight : Metrics.legacyPreferredHeight
    }

    private var defaultTrackHeight: CGFloat {
        appliedAppearanceStyle.usesLiquidGlass ? Metrics.liquidTrackHeight : Metrics.legacyTrackHeight
    }

    private var defaultThumbSize: CGSize {
        appliedAppearanceStyle.usesLiquidGlass ? Metrics.liquidThumbSize : Metrics.legacyThumbSize
    }

    private func updateElasticPressRenderer(for style: AetherAppearanceStyle) {
        guard #unavailable(iOS 26.0) else { return }
        if style.usesLiquidGlass {
            guard elasticRecognizer == nil else { return }
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.motionProfile = AetherMotion.standaloneButtonPress
            elastic.touchEffectView = thumbGlass
            elastic.highlightContainerView = thumbGlass.contentView
            addGestureRecognizer(elastic)
            elasticRecognizer = elastic
        } else if let elasticRecognizer {
            elasticRecognizer.resetVisualState()
            removeGestureRecognizer(elasticRecognizer)
            self.elasticRecognizer = nil
        }
    }

    private func applyTheme() {
        let alpha = max(0.0, min(1.0, theme.minimumTrackAlpha))
        minimumFillView.backgroundColor = theme.minimumTrackTintColor.withAlphaComponent(alpha)
        minimumFillView.tintColor = theme.minimumTrackTintColor
        tintColor = theme.minimumTrackTintColor
    }

    private func updateEndpointImages() {
        let resolvedTint = valueImageTintColor.resolvedColor(with: traitCollection)
        minimumValueImageNode.image = minimumValueImage?.withTintColor(resolvedTint, renderingMode: .alwaysOriginal)
        maximumValueImageNode.image = maximumValueImage?.withTintColor(resolvedTint, renderingMode: .alwaysOriginal)
        minimumValueImageNode.isHidden = minimumValueImage == nil
        maximumValueImageNode.isHidden = maximumValueImage == nil
    }

    private func updateLayout(transition: ContainedViewLayoutTransition) {
        let size = bounds.size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }

        let effectiveDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)
        let contentFrame = bounds.inset(by: contentInsets)
        var trackContentFrame = contentFrame

        if minimumValueImage != nil {
            let imageFrame = CGRect(
                x: contentFrame.minX,
                y: floor(contentFrame.midY - Metrics.endpointImageSide / 2.0),
                width: Metrics.endpointImageSide,
                height: Metrics.endpointImageSide
            )
            lastMinimumValueImageFrame = imageFrame
            transition.updateFrame(node: minimumValueImageNode, frame: imageFrame)
            let reservedWidth = Metrics.endpointImageSide + Metrics.endpointImageSpacing
            trackContentFrame.origin.x += reservedWidth
            trackContentFrame.size.width = max(0.0, trackContentFrame.width - reservedWidth)
        } else {
            lastMinimumValueImageFrame = .zero
            transition.updateFrame(node: minimumValueImageNode, frame: .zero)
        }

        if maximumValueImage != nil {
            let imageFrame = CGRect(
                x: contentFrame.maxX - Metrics.endpointImageSide,
                y: floor(contentFrame.midY - Metrics.endpointImageSide / 2.0),
                width: Metrics.endpointImageSide,
                height: Metrics.endpointImageSide
            )
            lastMaximumValueImageFrame = imageFrame
            transition.updateFrame(node: maximumValueImageNode, frame: imageFrame)
            trackContentFrame.size.width = max(
                0.0,
                trackContentFrame.width - Metrics.endpointImageSide - Metrics.endpointImageSpacing
            )
        } else {
            lastMaximumValueImageFrame = .zero
            transition.updateFrame(node: maximumValueImageNode, frame: .zero)
        }

        let resolvedTrackHeight = min(max(1.0, trackHeight), max(1.0, contentFrame.height))
        let resolvedThumbSize = CGSize(
            width: min(max(1.0, thumbSize.width), max(1.0, trackContentFrame.width)),
            height: min(max(1.0, thumbSize.height), max(1.0, contentFrame.height))
        )

        let trackFrame = CGRect(
            x: trackContentFrame.minX,
            y: floor(contentFrame.midY - resolvedTrackHeight / 2.0),
            width: trackContentFrame.width,
            height: resolvedTrackHeight
        )
        let travel = max(0.0, trackFrame.width - resolvedThumbSize.width)
        let progress = CGFloat(normalizedValue())
        let thumbFrame = CGRect(
            x: trackFrame.minX + travel * progress,
            y: floor(contentFrame.midY - resolvedThumbSize.height / 2.0),
            width: resolvedThumbSize.width,
            height: resolvedThumbSize.height
        )

        lastTrackFrame = trackFrame
        lastThumbFrame = thumbFrame

        transition.updateFrame(view: glassContainer, frame: bounds)
        glassContainer.update(size: size, isDark: effectiveDark, transition: transition)

        transition.updateFrame(view: trackGlass, frame: trackFrame)
        trackGlass.update(
            size: trackFrame.size,
            cornerRadius: resolvedTrackHeight / 2.0,
            isDark: effectiveDark,
            tintColor: theme.maximumTrackTint,
            isInteractive: true,
            isVisible: true,
            transition: transition
        )

        let fillWidth = max(0.0, min(trackFrame.width, thumbFrame.midX - trackFrame.minX))
        let fillFrame = CGRect(x: 0.0, y: 0.0, width: fillWidth, height: resolvedTrackHeight)
        transition.updateFrame(view: minimumFillView, frame: fillFrame)
        minimumFillView.layer.cornerRadius = min(resolvedTrackHeight / 2.0, fillWidth / 2.0)
        minimumFillView.layer.masksToBounds = true

        transition.updateFrame(view: thumbGlass, frame: thumbFrame)
        thumbGlass.update(
            size: thumbFrame.size,
            cornerRadius: resolvedThumbSize.height / 2.0,
            isDark: effectiveDark,
            tintColor: theme.thumbTint,
            isInteractive: true,
            isVisible: true,
            transition: transition
        )
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        setValue(value(at: location.x), animated: true)
        notifyValueChanged()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .began:
            if lastThumbFrame.insetBy(dx: -18.0, dy: -18.0).contains(location) {
                gestureThumbOffset = location.x - lastThumbFrame.midX
            } else {
                gestureThumbOffset = 0.0
                setValue(value(at: location.x), animated: false)
                if isContinuous {
                    notifyValueChanged()
                }
            }
        case .changed:
            setValue(value(at: location.x - gestureThumbOffset), animated: false)
            if isContinuous {
                notifyValueChanged()
            }
        case .ended, .cancelled, .failed:
            gestureThumbOffset = 0.0
            if !isContinuous {
                notifyValueChanged()
            }
            updateLayout(transition: .animated(duration: 0.26, curve: .spring))
        default:
            break
        }
    }

    private func value(at x: CGFloat) -> Float {
        guard lastTrackFrame.width > 0.0 else {
            return _value
        }
        let travel = max(1.0, lastTrackFrame.width - lastThumbFrame.width)
        let progress = max(0.0, min(1.0, (x - lastTrackFrame.minX - lastThumbFrame.width / 2.0) / travel))
        return minimumValue + Float(progress) * (maximumValue - minimumValue)
    }

    private func clampedValue(_ value: Float) -> Float {
        min(max(value, minimumValue), maximumValue)
    }

    private func normalizedValue() -> Float {
        let range = maximumValue - minimumValue
        guard range > 0.0 else {
            return 0.0
        }
        return (_value - minimumValue) / range
    }

    private func notifyValueChanged() {
        valueChanged(_value)
        sendActions(for: .valueChanged)
        accessibilityValue = formattedAccessibilityValue()
    }

    private func resolvedAccessibilityStep() -> Float {
        let range = maximumValue - minimumValue
        guard range > 0.0 else {
            return 0.0
        }
        return max(range * 0.01, min(range, accessibilityStep))
    }

    private func formattedAccessibilityValue() -> String {
        let percent = Int(round(normalizedValue() * 100.0))
        return "\(percent)%"
    }
}
