import UIKit
import AsyncDisplayKit

// MARK: - GlassButton

/// Generic glass-styled control with optional title, optional leading icon,
/// loading state and native liquid-glass interaction.
///
/// The control keeps its visible content inside `GlassBackgroundView.contentView`
/// so native `UIGlassEffect` deformation affects the surface and content as
/// one unit. Touch tracking is driven by a non-cancelling gesture recognizer:
/// this lets the inner visual-effect view keep receiving touches for native
/// glass feedback while `GlassButton` still exposes normal `UIControl` events.
public final class GlassButton: UIControl, AetherAppearanceConsumer {
    private enum Constants {
        static let defaultHeight: CGFloat = 36.0
        static let iconOnlySize = CGSize(width: 36.0, height: 36.0)
        static let minIconSide: CGFloat = 20.0
        static let maxIconSide: CGFloat = 28.0
        static let fallbackIconSide: CGFloat = 22.0
        static let maxMeasuredTextWidth: CGFloat = 240.0
        static let loadingFadeDuration: TimeInterval = 0.18
    }

    // MARK: Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer = UIView()
    private var iconNode: ASImageNode?
    private var titleNode: ASTextNode?
    private var titleFont: UIFont = .aetherScaledSystemFont(ofSize: 15.0, weight: .medium)
    private var loadingIndicator: UIActivityIndicatorView?
    private var pressRecognizer: GlassButtonPressGestureRecognizer?
    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    // MARK: Public API

    /// Back-compat closure for existing call sites. Standard `UIControl`
    /// target/action users can also subscribe to `.touchUpInside` or
    /// `.primaryActionTriggered`.
    public var action: ((GlassButton) -> Void)?

    /// Optional per-control style. `nil` follows its container/application.
    public var appearanceStyleOverride: AetherAppearanceStyle? = nil {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            glassBackground.appearanceStyleOverride = appearanceStyleOverride
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    /// Minimum content size used when the image/title do not provide one.
    public var minimumSize: CGSize = Constants.iconOnlySize {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    /// Corner radius. `nil` means capsule (`bounds.height / 2`).
    public var cornerRadius: CGFloat? {
        didSet { setNeedsLayout() }
    }

    /// Horizontal padding around title/icon content.
    public var contentPadding: CGFloat = 14.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    public var tint: GlassBackgroundView.TintColor = .init(kind: .panel) {
        didSet { setNeedsLayout() }
    }

    public var font: UIFont? {
        get { titleFont }
        set {
            titleFont = newValue ?? .aetherScaledSystemFont(ofSize: 15.0, weight: .medium)
            updateTitleNodeText()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// Spacing between icon and title when both are visible.
    public var iconTitleSpacing: CGFloat = 8.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    /// Tint color for icon, title and loading indicator.
    public var contentColor: UIColor = .label {
        didSet { applyContentColor() }
    }

    /// Override for the `isDark` flag passed to the glass background.
    /// `nil` follows `traitCollection.userInterfaceStyle`.
    public var isDarkAppearance: Bool? {
        didSet {
            glassBackground.isDarkOverride = isDarkAppearance
            setNeedsLayout()
        }
    }

    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            updateTitleView()
        }
    }

    public var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            updateIconView()
        }
    }

    public override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            updateInteractionState()
        }
    }

    public override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateClassicPressFeedback(animated: true)
        }
    }

    /// Waiting/loading state. Swaps title/icon content for a centered spinner
    /// and blocks primary actions without applying the disabled alpha.
    public var isLoading: Bool = false {
        didSet {
            guard isLoading != oldValue else { return }
            updateInteractionState()
            updateLoadingState(animated: true)
        }
    }

    // MARK: Init

    public init(
        title: String? = nil,
        image: UIImage? = nil,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.appearanceStyleOverride = appearanceStyle
        self.glassBackground = GlassBackgroundView(
            style: .regular,
            appearanceStyle: appearanceStyle
        )
        super.init(frame: .zero)

        glassBackground.surfaceRole = .button

        updateAccessibilityState()

        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        contentContainer.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(contentContainer)

        self.title = title
        self.image = image
        updateTitleView()
        updateIconView()

        let press = GlassButtonPressGestureRecognizer(target: self, action: #selector(handlePressGesture(_:)))
        addGestureRecognizer(press)
        self.pressRecognizer = press

        updateInteractionState()
        AetherAppearanceConsumerRegistry.register(self)
    }

    internal var backingUsesLiquidGlassAppearanceForTesting: Bool {
        glassBackground.usesLiquidGlassAppearance
    }

    internal var backingUsesAnyGlassRendererForTesting: Bool {
        glassBackground.usesAnyGlassRendererForTesting
    }

    internal var backingLegacyBlurStyleForTesting: UIBlurEffect.Style? {
        glassBackground.legacyBlurStyleForTesting
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let resolvedCorner = cornerRadius ?? bounds.height / 2.0
        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)

        glassBackground.frame = bounds
        if #available(iOS 26.0, *) {
            glassBackground.setNativeUniformCornerRadius(resolvedCorner)
        }
        glassBackground.update(
            size: bounds.size,
            cornerRadius: resolvedCorner,
            isDark: resolvedDark,
            tintColor: tint,
            isInteractive: isInteractionAvailable,
            isVisible: true,
            transition: .immediate
        )

        contentContainer.frame = bounds
        layoutContent()
        layoutLoadingIndicator()
    }

    @discardableResult
    public func update(
        cornerRadius: CGFloat,
        tintColor: GlassBackgroundView.TintColor,
        isInteractive: Bool = true,
        isVisible: Bool = true
    ) -> Self {
        self.tint = tintColor
        self.cornerRadius = cornerRadius

        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)
        if #available(iOS 26.0, *) {
            glassBackground.setNativeUniformCornerRadius(cornerRadius)
        }
        glassBackground.update(
            size: bounds.size,
            cornerRadius: cornerRadius,
            isDark: resolvedDark,
            tintColor: tintColor,
            isInteractive: isInteractive && isInteractionAvailable,
            isVisible: isVisible,
            transition: .immediate
        )

        return self
    }

    public override var intrinsicContentSize: CGSize {
        let hasIcon = image != nil
        let hasTitle = title?.isEmpty == false

        switch (hasIcon, hasTitle) {
        case (true, true):
            let width = Constants.fallbackIconSide + iconTitleSpacing + measuredTitleWidth + 2.0 * contentPadding
            return CGSize(width: max(minimumSize.width, ceil(width)), height: max(minimumSize.height, Constants.defaultHeight))
        case (true, false):
            return CGSize(
                width: max(minimumSize.width, Constants.iconOnlySize.width),
                height: max(minimumSize.height, Constants.iconOnlySize.height)
            )
        case (false, true):
            let width = measuredTitleWidth + 2.0 * contentPadding
            return CGSize(width: max(minimumSize.width, ceil(width)), height: max(minimumSize.height, Constants.defaultHeight))
        case (false, false):
            return minimumSize
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyContentColor()
        setNeedsLayout()
    }

    // MARK: Content

    private var measuredTitleWidth: CGFloat {
        titleSize(constrainedTo: CGSize(width: Constants.maxMeasuredTextWidth, height: Constants.defaultHeight)).width
    }

    private var resolvedIconSide: CGFloat {
        guard let image else { return 0.0 }
        let side = max(image.size.width, image.size.height)
        guard side > 0.0 else { return Constants.fallbackIconSide }
        return max(Constants.minIconSide, min(Constants.maxIconSide, side))
    }

    private var isInteractionAvailable: Bool {
        isEnabled && !isLoading
    }

    private func updateTitleView() {
        if title?.isEmpty == false {
            let node = titleNode ?? makeTitleNode()
            updateTitleNodeText()
            node.isHidden = false
        } else {
            titleNode?.attributedText = nil
            titleNode?.isHidden = true
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func updateIconView() {
        if let image {
            let node = iconNode ?? makeIconNode()
            node.image = image.withRenderingMode(.alwaysTemplate)
            node.isHidden = false
        } else {
            iconNode?.image = nil
            iconNode?.isHidden = true
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func makeTitleNode() -> ASTextNode {
        let node = ASTextNode()
        node.maximumNumberOfLines = 1
        node.truncationMode = .byTruncatingTail
        node.view.isUserInteractionEnabled = false
        contentContainer.addSubview(node.view)
        titleNode = node
        return node
    }

    private func makeIconNode() -> ASImageNode {
        let node = ASImageNode()
        node.contentMode = .center
        node.tintColor = contentColor
        node.view.setMonochromaticEffect(tintColor: contentColor)
        node.view.isUserInteractionEnabled = false
        contentContainer.addSubview(node.view)
        iconNode = node
        return node
    }

    private func applyContentColor() {
        iconNode?.tintColor = contentColor
        iconNode?.view.setMonochromaticEffect(tintColor: contentColor)
        updateTitleNodeText()
        loadingIndicator?.color = contentColor
    }

    private func updateTitleNodeText() {
        guard let titleNode, let title, !title.isEmpty else { return }
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: titleFont,
                .foregroundColor: contentColor,
                .paragraphStyle: Self.centeredParagraphStyle
            ]
        )
        titleNode.view.accessibilityLabel = title
    }

    private func titleSize(constrainedTo size: CGSize) -> CGSize {
        guard let title, !title.isEmpty else { return .zero }
        let rect = (title as NSString).boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func layoutContent() {
        let hasIcon = image != nil
        let hasTitle = title?.isEmpty == false
        let iconSide = resolvedIconSide
        let maxTitleWidth = max(0.0, bounds.width - 2.0 * contentPadding)
        let titleSize = titleSize(constrainedTo: CGSize(width: maxTitleWidth, height: bounds.height))

        switch (hasIcon, hasTitle) {
        case (true, true):
            let titleWidth = min(titleSize.width, max(0.0, bounds.width - 2.0 * contentPadding - iconSide - iconTitleSpacing))
            let totalWidth = iconSide + iconTitleSpacing + titleWidth
            let startX = floor((bounds.width - totalWidth) / 2.0)
            let titleHeight = min(bounds.height, max(1.0, titleSize.height))
            iconNode?.frame = CGRect(
                x: startX,
                y: floor((bounds.height - iconSide) / 2.0),
                width: iconSide,
                height: iconSide
            )
            titleNode?.frame = CGRect(
                x: startX + iconSide + iconTitleSpacing,
                y: floor((bounds.height - titleHeight) / 2.0),
                width: titleWidth,
                height: titleHeight
            )

        case (true, false):
            iconNode?.frame = CGRect(
                x: floor((bounds.width - iconSide) / 2.0),
                y: floor((bounds.height - iconSide) / 2.0),
                width: iconSide,
                height: iconSide
            )

        case (false, true):
            let titleHeight = min(bounds.height, max(1.0, titleSize.height))
            titleNode?.frame = CGRect(
                x: contentPadding,
                y: floor((bounds.height - titleHeight) / 2.0),
                width: maxTitleWidth,
                height: titleHeight
            )

        case (false, false):
            break
        }
    }

    private static let centeredParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    // MARK: Loading

    private func configureLoadingIndicatorIfNeeded() {
        guard loadingIndicator == nil else { return }
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = false
        indicator.color = contentColor
        indicator.alpha = 0.0
        glassBackground.contentView.addSubview(indicator)
        loadingIndicator = indicator
        setNeedsLayout()
    }

    private func layoutLoadingIndicator() {
        guard let indicator = loadingIndicator else { return }
        let size = indicator.intrinsicContentSize
        indicator.frame = CGRect(
            x: floor((bounds.width - size.width) / 2.0),
            y: floor((bounds.height - size.height) / 2.0),
            width: size.width,
            height: size.height
        )
    }

    private func updateLoadingState(animated: Bool) {
        if isLoading {
            configureLoadingIndicatorIfNeeded()
            loadingIndicator?.startAnimating()
        }

        let contentTargetAlpha: CGFloat = isLoading ? 0.0 : 1.0
        let indicatorTargetAlpha: CGFloat = isLoading ? 1.0 : 0.0

        let changes = {
            self.contentContainer.alpha = contentTargetAlpha
            self.loadingIndicator?.alpha = indicatorTargetAlpha
        }
        let completion = { [weak self] in
            guard let self else { return }
            if !self.isLoading {
                self.loadingIndicator?.stopAnimating()
            }
        }

        if animated {
            UIView.animate(
                withDuration: Constants.loadingFadeDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: changes,
                completion: { _ in completion() }
            )
        } else {
            changes()
            completion()
        }
    }

    // MARK: Interaction

    private func updateInteractionState(style explicitStyle: AetherAppearanceStyle? = nil) {
        let enabled = isInteractionAvailable
        let style = explicitStyle
            ?? appearanceStyleOverride
            ?? AetherAppearance.runtimeCurrent.style
        let tokens = AetherLegacySurfaceTokens.resolve(role: .button, traitCollection: traitCollection)
        updateElasticPressRenderer(for: style)
        alpha = isEnabled ? 1.0 : (style.usesLiquidGlass ? 0.4 : tokens.disabledAlpha)
        pressRecognizer?.isEnabled = enabled
        elasticRecognizer?.isEnabled = enabled
        if !enabled {
            isHighlighted = false
        }
        updateAccessibilityState()
        updateClassicPressFeedback(animated: false)
        setNeedsLayout()
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let style = appearanceStyleOverride ?? appearance.style
        updateInteractionState(style: style)
        updateClassicPressFeedback(animated: animated)
    }

    private func updateElasticPressRenderer(for style: AetherAppearanceStyle) {
        guard #unavailable(iOS 26.0) else { return }
        if style.usesLiquidGlass {
            guard elasticRecognizer == nil else { return }
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.motionProfile = AetherMotion.standaloneButtonPress
            elastic.touchEffectView = self
            elastic.highlightContainerView = glassBackground.contentView
            addGestureRecognizer(elastic)
            elasticRecognizer = elastic
        } else if let elasticRecognizer {
            elasticRecognizer.resetVisualState()
            removeGestureRecognizer(elasticRecognizer)
            self.elasticRecognizer = nil
        }
    }

    private func updateClassicPressFeedback(animated: Bool) {
        let style = appearanceStyleOverride ?? AetherAppearance.runtimeCurrent.style
        let tokens = AetherLegacySurfaceTokens.resolve(role: .button, traitCollection: traitCollection)
        let changes = {
            if style.usesLiquidGlass {
                self.glassBackground.alpha = 1
                self.glassBackground.transform = .identity
            } else {
                self.glassBackground.alpha = self.isHighlighted ? tokens.pressedAlpha : 1
                let scale = self.isHighlighted ? tokens.pressedScale : 1
                self.glassBackground.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
        if animated, tokens.animationDuration > 0 {
            UIView.animate(
                withDuration: tokens.animationDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func updateAccessibilityState() {
        var traits = accessibilityTraits
        traits.insert(.button)
        if isEnabled {
            traits.remove(.notEnabled)
        } else {
            traits.insert(.notEnabled)
        }
        accessibilityTraits = traits
    }

    @objc private func handlePressGesture(_ recognizer: GlassButtonPressGestureRecognizer) {
        guard isInteractionAvailable else { return }

        let location = recognizer.location(in: self)
        let isInside = bounds.contains(location)

        switch recognizer.state {
        case .began:
            isHighlighted = isInside
            if isInside {
                sendActions(for: .touchDown)
            }

        case .changed:
            if isInside != isHighlighted {
                sendActions(for: isInside ? .touchDragEnter : .touchDragExit)
            }
            isHighlighted = isInside
            sendActions(for: isInside ? .touchDragInside : .touchDragOutside)

        case .ended:
            isHighlighted = false
            if isInside {
                sendActions(for: .touchUpInside)
                action?(self)
                sendActions(for: .primaryActionTriggered)
            } else {
                sendActions(for: .touchUpOutside)
            }

        case .cancelled, .failed:
            isHighlighted = false
            sendActions(for: .touchCancel)

        default:
            break
        }
    }
}

private final class GlassButtonPressGestureRecognizer: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1 else {
            state = .failed
            return
        }
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else {
            state = .failed
            return
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
}
