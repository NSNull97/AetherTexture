import UIKit
import AsyncDisplayKit

/// Liquid Glass v1-style alert dialog: title + message + optional text field + one
/// or more pill-shaped action buttons (primary blue CTA, grey secondary,
/// grey/red destructive). Two-button pairs lay out side-by-side; 3+
/// actions stack vertically.
open class AetherAlertController: ASDKViewController<ASDisplayNode>, UIViewControllerTransitioningDelegate {
    public var theme: AetherAlertTheme {
        didSet { rootView?.applyTheme(theme) }
    }

    public let alertTitle: String?
    public let alertMessage: String?
    public let actions: [AetherAlertAction]
    public let textFieldConfigs: [AetherAlertTextField]
    public let customContentView: UIView?
    public let customContentNode: ASDisplayNode?

    /// Tap outside the card dismisses. Default `true` — matches the
    /// AetherUI interactive-dim expectation (UIKit's UIAlertController
    /// is `false`, but that's because UIKit forces the user to answer
    /// the alert; our alerts are more toast-like).
    public var dismissOnOutsideTap: Bool = true

    public var dismissed: ((Bool) -> Void)?
    public var willDismiss: ((Bool) -> Void)?

    /// Current text of the Nth text field, or nil if index out of range.
    /// Useful for reading input from action handlers.
    public func textFieldValue(at index: Int) -> String? {
        return rootView?.textFieldValue(at: index)
    }

    private var isDismissed: Bool = false
    private var rootView: AetherAlertRootView? {
        return isViewLoaded ? (view as? AetherAlertRootView) : nil
    }

    public init(
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textFields: [AetherAlertTextField] = [],
        customContentView: UIView? = nil,
        customContentNode: ASDisplayNode? = nil,
        theme: AetherAlertTheme = .system
    ) {
        self.alertTitle = title
        self.alertMessage = message
        self.actions = actions
        self.textFieldConfigs = textFields
        self.customContentView = customContentNode?.view ?? customContentView
        self.customContentNode = customContentNode
        self.theme = theme
        let rootTheme = theme
        let rootTitle = title
        let rootMessage = message
        let rootActions = actions
        let rootTextFields = textFields
        let rootCustomContentView = customContentNode?.view ?? customContentView
        super.init(node: ASDisplayNode(viewBlock: {
            AetherAlertRootView(
                theme: rootTheme,
                title: rootTitle,
                message: rootMessage,
                actions: rootActions,
                textFields: rootTextFields,
                customContentView: rootCustomContentView
            )
        }))
        modalPresentationStyle = .overFullScreen
        // No crossDissolve — the root view runs its own fade + spring in
        // animateIn(). A UIKit transition on top would render the alert
        // once (via system dissolve) and then again via our animation,
        // producing the "double appearance" flicker.
        modalTransitionStyle = .coverVertical
        // Call sites may continue to use `present(..., animated: true)`, but
        // the alert owns its visible animation. An effectively immediate
        // UIKit hand-off prevents the stock cover transition from delaying
        // `viewDidAppear` (and therefore the first visible alert frame).
        transitioningDelegate = self
    }

    /// Back-compat single-text-field overload.
    public convenience init(
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textField: AetherAlertTextField?,
        theme: AetherAlertTheme = .system
    ) {
        self.init(
            title: title,
            message: message,
            actions: actions,
            textFields: textField.map { [$0] } ?? [],
            customContentView: nil,
            customContentNode: nil,
            theme: theme
        )
    }

    public convenience init(
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textFields: [AetherAlertTextField] = [],
        customContentNode: ASDisplayNode,
        theme: AetherAlertTheme = .system
    ) {
        self.init(
            title: title,
            message: message,
            actions: actions,
            textFields: textFields,
            customContentView: nil,
            customContentNode: customContentNode,
            theme: theme
        )
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        guard let root = rootView else { return }
        root.actionTriggered = { [weak self] action in
            guard let self, !self.isDismissed else { return }
            self.isDismissed = true
            self.willDismiss?(false)
            self.dismissed?(false)
            action.handler()
            self.dismissAnimated(fromOutside: false)
        }
        root.outsideTap = { [weak self] in
            guard let self, self.dismissOnOutsideTap, !self.isDismissed else { return }
            self.isDismissed = true
            self.willDismiss?(true)
            self.dismissed?(true)
            self.dismissAnimated(fromOutside: true)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootView?.animateIn()
    }

    public func dismissAnimated() {
        guard !isDismissed else { return }
        isDismissed = true
        willDismiss?(false)
        dismissed?(false)
        dismissAnimated(fromOutside: false)
    }

    private func dismissAnimated(fromOutside: Bool) {
        rootView?.animateOut { [weak self] in
            self?.presentingViewController?.dismiss(animated: false)
        }
    }

    open override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(action: #selector(escapePressed), input: UIKeyCommand.inputEscape),
            UIKeyCommand(action: #selector(escapePressed), input: "W", modifierFlags: .command)
        ]
        if actions.contains(where: { $0.style == .primary }) {
            commands.append(UIKeyCommand(action: #selector(enterPressed), input: "\r"))
        }
        return commands
    }

    @objc private func escapePressed() {
        dismissAnimated()
    }

    @objc private func enterPressed() {
        guard let focused = actions.first(where: { $0.style == .primary && $0.enabled }) else { return }
        rootView?.triggerAction(focused)
    }

    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        AetherAlertAttachmentAnimator()
    }
}

private final class AetherAlertAttachmentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.001
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let targetController = transitionContext.viewController(forKey: .to),
              let target = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        target.frame = transitionContext.finalFrame(for: targetController)
        transitionContext.containerView.addSubview(target)
        target.layoutIfNeeded()
        transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
    }
}

// MARK: - Root view

final class AetherAlertRootView: UIView, AetherAppearanceConsumer {
    var actionTriggered: (AetherAlertAction) -> Void = { _ in }
    var outsideTap: () -> Void = {}

    private var theme: AetherAlertTheme
    private let title: String?
    private let message: String?
    private let actions: [AetherAlertAction]
    private let textFieldConfigs: [AetherAlertTextField]
    private let customContentView: UIView?

    private let dimView = UIView()
    /// Interactive liquid-glass card on iOS 26+. `glassIsInteractive = true`
    /// opts into the native elastic deform / specular shimmer under touch.
    /// All content is hosted inside `card.contentView`.
    private let card: GlassBackgroundView
    private let tintOverlay = UIView()
    private let scrollView = UIScrollView()
    private let contentContainerView = UIView()

    private let titleNode = ASTextNode()
    private let messageNode = ASTextNode()
    /// One `FieldRow` per configured text field — a 52pt pill-shaped input.
    /// Optional caption label renders *above* the pill, not inside it, so
    /// the pill itself is exactly the requested 52pt.
    private struct FieldRow {
        let captionNode: ASTextNode?
        let container: UIView
        let input: UITextField
    }
    private var fieldRows: [FieldRow] = []
    private var buttonViews: [AetherAlertPillButton] = []

    /// Tuning constants — match the iOS 26 system alert proportions from
    /// the design reference the caller provided.
    private static let cardWidth: CGFloat = 300.0
    private static let cardCornerRadius: CGFloat = 28.0
    private static let horizontalPadding: CGFloat = 16.0
    private static let topPadding: CGFloat = 18.0
    private static let titleToMessageSpacing: CGFloat = 4.0
    private static let messageToFieldSpacing: CGFloat = 16.0
    private static let fieldToButtonsSpacing: CGFloat = 16.0
    private static let messageToButtonsSpacing: CGFloat = 18.0
    private static let bottomPadding: CGFloat = 12.0
    private static let buttonHeight: CGFloat = 50.0
    private static let buttonSpacing: CGFloat = 8.0
    /// Per-field pill height. User-requested 52pt (was 62pt).
    private static let fieldHeight: CGFloat = 52.0
    private static let fieldSpacing: CGFloat = 8.0

    init(
        theme: AetherAlertTheme,
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textFields: [AetherAlertTextField],
        customContentView: UIView?
    ) {
        self.theme = theme
        self.title = title
        self.message = message
        self.actions = actions
        self.textFieldConfigs = textFields
        self.customContentView = customContentView

        self.card = GlassBackgroundView(style: .regular)
        self.card.glassIsInteractive = true
        self.card.glassCornerRadius = Self.cardCornerRadius

        super.init(frame: .zero)

        card.surfaceRole = .card
        card.legacySurfaceColorOverride = theme.backgroundColor

        // Start everything hidden so the first frame after present is
        // already invisible — animateIn() then animates into view. This
        // fixes the "double-appearance" flicker that a UIKit crossDissolve
        // + our own fade were causing together.
        dimView.alpha = 0.0
        card.alpha = 0.0
        card.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)

        dimView.backgroundColor = theme.dimColor
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(tap)
        addSubview(dimView)

        // GlassBackgroundView clips content to its rounded shape via the
        // native UIGlassEffect pipeline (iOS 26) / legacy layer mask
        // fallback — we don't need to set masksToBounds manually.
        addSubview(card)

        updateTintOverlay(for: AetherAppearance.runtimeCurrent.style)
        card.contentView.addSubview(tintOverlay)
        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = true
        card.contentView.addSubview(scrollView)
        scrollView.addSubview(contentContainerView)

        titleNode.maximumNumberOfLines = 0
        titleNode.isUserInteractionEnabled = false
        titleNode.attributedText = Self.attributedAlertText(
            title,
            font: .aetherScaledSystemFont(ofSize: floor(theme.baseFontSize), weight: .semibold),
            color: theme.primaryColor
        )
        contentContainerView.addSubview(titleNode.view)

        messageNode.maximumNumberOfLines = 0
        messageNode.isUserInteractionEnabled = false
        messageNode.attributedText = Self.attributedAlertText(
            message,
            font: .aetherScaledSystemFont(ofSize: floor(theme.baseFontSize * 15.0 / 17.0)),
            color: theme.primaryColor
        )
        contentContainerView.addSubview(messageNode.view)

        for config in textFields {
            fieldRows.append(installFieldRow(config: config))
        }

        if let customContentView {
            contentContainerView.addSubview(customContentView)
        }

        for action in actions {
            let button = AetherAlertPillButton(action: action, theme: theme)
            button.tapped = { [weak self] a in self?.actionTriggered(a) }
            buttonViews.append(button)
            contentContainerView.addSubview(button)
        }

        AetherAppearanceConsumerRegistry.register(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        applyTheme(theme)
        fieldRows.forEach { $0.input.font = .aetherScaledSystemFont(ofSize: 17.0, compatibleWith: traitCollection) }
        setNeedsLayout()
    }

    private func installFieldRow(config: AetherAlertTextField) -> FieldRow {
        var captionNode: ASTextNode?
        if let labelText = config.label, !labelText.isEmpty {
            let node = ASTextNode()
            node.maximumNumberOfLines = 1
            node.truncationMode = .byTruncatingTail
            node.isUserInteractionEnabled = false
            node.attributedText = Self.attributedAlertText(
                labelText,
                font: .aetherScaledSystemFont(ofSize: 13.0, weight: .semibold),
                color: theme.primaryColor
            )
            contentContainerView.addSubview(node.view)
            captionNode = node
        }

        let container = UIView()
        container.backgroundColor = theme.pillFillColor
        container.applyCornerRadius(12.0)
        contentContainerView.addSubview(container)

        let field = UITextField()
        field.placeholder = config.placeholder
        field.text = config.initialText
        field.isSecureTextEntry = config.isSecureTextEntry
        field.keyboardType = config.keyboardType
        field.textColor = theme.primaryColor
        field.font = .aetherScaledSystemFont(ofSize: 17.0)
        field.borderStyle = .none
        field.addTarget(self, action: #selector(fieldEditingChanged(_:)), for: .editingChanged)
        container.addSubview(field)

        return FieldRow(captionNode: captionNode, container: container, input: field)
    }

    func textFieldValue(at index: Int) -> String? {
        guard fieldRows.indices.contains(index) else { return nil }
        return fieldRows[index].input.text
    }

    func applyTheme(_ theme: AetherAlertTheme) {
        self.theme = theme
        dimView.backgroundColor = theme.dimColor
        card.legacySurfaceColorOverride = theme.backgroundColor
        updateTintOverlay(for: AetherAppearance.runtimeCurrent.style)
        titleNode.attributedText = Self.attributedAlertText(
            title,
            font: .aetherScaledSystemFont(ofSize: floor(theme.baseFontSize), weight: .semibold),
            color: theme.primaryColor
        )
        messageNode.attributedText = Self.attributedAlertText(
            message,
            font: .aetherScaledSystemFont(ofSize: floor(theme.baseFontSize * 15.0 / 17.0)),
            color: theme.primaryColor
        )
        for row in fieldRows {
            row.container.backgroundColor = theme.pillFillColor
            if let caption = row.captionNode, let text = caption.attributedText?.string {
                caption.attributedText = Self.attributedAlertText(
                    text,
                    font: .aetherScaledSystemFont(ofSize: 13.0, weight: .semibold),
                    color: theme.primaryColor
                )
            }
            row.input.textColor = theme.primaryColor
        }
        buttonViews.forEach { $0.applyTheme(theme) }
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        updateTintOverlay(for: appearance.style)
    }

    private func updateTintOverlay(for style: AetherAppearanceStyle) {
        // Legacy tint is applied by GlassBackgroundView above its public
        // systemChromeMaterial renderer. A second solid overlay would turn
        // that real blur into an opaque card on pre-iOS-26 systems.
        if style == .legacy || GlassCompatibility.isLiquidDesignAvailable {
            tintOverlay.backgroundColor = .clear
        } else {
            tintOverlay.backgroundColor = theme.backgroundColor
        }
    }

    func triggerAction(_ action: AetherAlertAction) {
        actionTriggered(action)
    }

    private static func attributedAlertText(_ text: String?, font: UIFont, color: UIColor) -> NSAttributedString? {
        guard let text else { return nil }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        dimView.frame = bounds
        let size = bounds.size

        let horizontalMargin: CGFloat = 12.0
        let cardWidth = max(
            0.0,
            min(
                Self.cardWidth,
                size.width - safeAreaInsets.left - safeAreaInsets.right - horizontalMargin * 2.0
            )
        )
        let innerWidth = max(0.0, cardWidth - Self.horizontalPadding * 2)

        var y: CGFloat = Self.topPadding
        let fieldHeight = max(
            Self.fieldHeight,
            UIFont.aetherScaledSystemFont(ofSize: 17.0, compatibleWith: traitCollection).lineHeight + 20.0
        )
        let buttonHeight = max(
            Self.buttonHeight,
            UIFont.aetherScaledSystemFont(
                ofSize: floor(theme.baseFontSize),
                weight: .semibold,
                compatibleWith: traitCollection
            ).lineHeight + 20.0
        )

        if let title, !title.isEmpty {
            let fit = titleNode.layoutThatFits(
                ASSizeRange(
                    min: .zero,
                    max: CGSize(width: innerWidth, height: .greatestFiniteMagnitude)
                )
            ).size
            titleNode.frame = CGRect(x: Self.horizontalPadding, y: y, width: innerWidth, height: fit.height)
            y += fit.height
        } else {
            titleNode.frame = .zero
        }

        if let message, !message.isEmpty {
            if title?.isEmpty == false { y += Self.titleToMessageSpacing }
            let fit = messageNode.layoutThatFits(
                ASSizeRange(
                    min: .zero,
                    max: CGSize(width: innerWidth, height: .greatestFiniteMagnitude)
                )
            ).size
            messageNode.frame = CGRect(x: Self.horizontalPadding, y: y + 4, width: innerWidth, height: fit.height)
            y += fit.height
        } else {
            messageNode.frame = .zero
        }

        if let customContentView {
            y += Self.messageToFieldSpacing
            var customSize = customContentView.sizeThatFits(CGSize(width: innerWidth, height: .greatestFiniteMagnitude))
            if customSize.width <= 0.0 || customSize.height <= 0.0 {
                customSize = customContentView.intrinsicContentSize
            }
            if customSize.width <= 0.0 || customSize.width == UIView.noIntrinsicMetric {
                customSize.width = innerWidth
            }
            if customSize.height <= 0.0 || customSize.height == UIView.noIntrinsicMetric {
                customSize.height = customContentView.bounds.height > 0.0 ? customContentView.bounds.height : 44.0
            }
            customContentView.frame = CGRect(
                x: Self.horizontalPadding,
                y: y,
                width: innerWidth,
                height: customSize.height
            )
            y += customSize.height
        }

        if !fieldRows.isEmpty {
            y += Self.messageToFieldSpacing
            let hInset: CGFloat = 14.0
            let captionHeight = max(
                18.0,
                UIFont.aetherScaledSystemFont(
                    ofSize: 13.0,
                    weight: .semibold,
                    compatibleWith: traitCollection
                ).lineHeight
            )
            let captionGap: CGFloat = 4.0

            for (index, row) in fieldRows.enumerated() {
                // Optional caption label above the pill. Rendered at card
                // content level (not inside the pill) so the pill stays
                // exactly 52pt tall.
                if let caption = row.captionNode {
                    caption.frame = CGRect(
                        x: Self.horizontalPadding,
                        y: y,
                        width: innerWidth,
                        height: captionHeight
                    )
                    y += captionHeight + captionGap
                }

                row.container.frame = CGRect(
                    x: Self.horizontalPadding,
                    y: y,
                    width: innerWidth,
                    height: fieldHeight
                )
                row.input.frame = CGRect(
                    x: hInset,
                    y: 0,
                    width: innerWidth - hInset * 2,
                    height: fieldHeight
                )

                y += fieldHeight
                if index < fieldRows.count - 1 {
                    y += Self.fieldSpacing
                }
            }
            if !buttonViews.isEmpty {
                y += Self.fieldToButtonsSpacing
            }
        } else if !buttonViews.isEmpty {
            y += Self.messageToButtonsSpacing
        }

        // Buttons: 2 actions lay out side-by-side; 3+ stack vertically. Each
        // button is its own pill with an 8pt gap.
        let buttonCount = buttonViews.count
        if buttonCount == 2 {
            let halfWidth = floor((innerWidth - Self.buttonSpacing) / 2)
            buttonViews[0].frame = CGRect(x: Self.horizontalPadding, y: y, width: halfWidth, height: buttonHeight)
            buttonViews[1].frame = CGRect(
                x: Self.horizontalPadding + halfWidth + Self.buttonSpacing,
                y: y,
                width: innerWidth - halfWidth - Self.buttonSpacing,
                height: buttonHeight
            )
            y += buttonHeight
        } else {
            for (index, button) in buttonViews.enumerated() {
                button.frame = CGRect(x: Self.horizontalPadding, y: y, width: innerWidth, height: buttonHeight)
                y += buttonHeight
                if index < buttonViews.count - 1 {
                    y += Self.buttonSpacing
                }
            }
        }
        y += Self.bottomPadding
        let contentHeight = y
        let verticalMargin: CGFloat = 16.0
        let availableHeight = max(
            0.0,
            size.height - safeAreaInsets.top - safeAreaInsets.bottom - verticalMargin * 2.0
        )
        let cardHeight = min(contentHeight, availableHeight)
        let availableRect = CGRect(
            x: safeAreaInsets.left,
            y: safeAreaInsets.top,
            width: max(0.0, size.width - safeAreaInsets.left - safeAreaInsets.right),
            height: max(0.0, size.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )

        card.frame = CGRect(
            x: floor(availableRect.midX - cardWidth / 2.0),
            y: floor(availableRect.midY - cardHeight / 2.0),
            width: cardWidth,
            height: cardHeight
        )
        card.update(size: card.bounds.size, cornerRadius: Self.cardCornerRadius, transition: .immediate)
        tintOverlay.frame = card.bounds
        scrollView.frame = card.bounds
        contentContainerView.frame = CGRect(x: 0.0, y: 0.0, width: cardWidth, height: contentHeight)
        scrollView.contentSize = contentContainerView.bounds.size
        scrollView.alwaysBounceVertical = contentHeight > cardHeight + 0.5
    }

    // MARK: Animation

    func animateIn() {
        // Initial hidden state was set in init() so the very first frame
        // after attach is invisible — no flicker. Here we only play forward.
        layoutIfNeeded()
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.dimView.alpha = 1.0
            self.card.alpha = 1.0
            self.card.transform = .identity
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 0.0
            self.card.alpha = 0.0
        } completion: { _ in completion() }
    }

    @objc private func dimTapped() {
        outsideTap()
    }

    @objc private func fieldEditingChanged(_ sender: UITextField) {
        guard let index = fieldRows.firstIndex(where: { $0.input === sender }) else { return }
        textFieldConfigs[index].onChanged(sender.text ?? "")
    }
}

// MARK: - Pill button

final class AetherAlertPillButton: UIControl {
    var tapped: (AetherAlertAction) -> Void = { _ in }

    private let action: AetherAlertAction
    private let contentNode: AetherAlertPillButtonNode

    init(action: AetherAlertAction, theme: AetherAlertTheme) {
        self.action = action
        self.contentNode = AetherAlertPillButtonNode(action: action, theme: theme)
        super.init(frame: .zero)

        backgroundColor = .clear
        contentNode.view.isUserInteractionEnabled = false
        addSubview(contentNode.view)

        applyTheme(theme)
        isEnabled = action.enabled
        isAccessibilityElement = true
        accessibilityLabel = action.title
        accessibilityTraits = action.enabled ? .button : [.button, .notEnabled]
        addTarget(self, action: #selector(tapAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(_ theme: AetherAlertTheme) {
        contentNode.applyTheme(theme)
    }

    override var isHighlighted: Bool {
        didSet {
            contentNode.setHighlighted(isHighlighted && action.enabled)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentNode.frame = bounds
    }

    @objc private func tapAction() {
        tapped(action)
    }
}

private final class AetherAlertPillButtonNode: ASDisplayNode {
    private let action: AetherAlertAction
    private let titleNode = ASTextNode()
    private var theme: AetherAlertTheme
    private var highlighted = false

    init(action: AetherAlertAction, theme: AetherAlertTheme) {
        self.action = action
        self.theme = theme
        super.init()
        clipsToBounds = true
        layer.cornerCurve = .continuous
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isUserInteractionEnabled = false
        addSubnode(titleNode)
        applyTheme(theme)
    }

    func applyTheme(_ theme: AetherAlertTheme) {
        self.theme = theme
        let textColor: UIColor
        if !action.enabled {
            textColor = theme.disabledColor
        } else {
            switch action.style {
            case .primary:     textColor = theme.primaryTextColor
            case .secondary:   textColor = theme.primaryColor
            case .destructive: textColor = theme.destructiveColor
            }
        }
        titleNode.attributedText = NSAttributedString(
            string: action.title,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: floor(theme.baseFontSize), weight: .semibold),
                .foregroundColor: textColor
            ]
        )
        updateBackground()
        setNeedsLayout()
    }

    func setHighlighted(_ highlighted: Bool) {
        guard self.highlighted != highlighted else { return }
        self.highlighted = highlighted
        updateBackground()
    }

    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2.0
        layer.cornerRadius = bounds.height / 2.0
        let maxSize = CGSize(width: max(1.0, bounds.width - 16.0), height: bounds.height)
        let titleSize = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: maxSize)).size
        titleNode.frame = CGRect(
            x: floor((bounds.width - titleSize.width) / 2.0),
            y: floor((bounds.height - titleSize.height) / 2.0),
            width: titleSize.width,
            height: titleSize.height
        )
    }

    private func updateBackground() {
        let idle: UIColor
        switch action.style {
        case .primary:      idle = theme.primaryFillColor
        case .secondary:    idle = theme.pillFillColor
        case .destructive:  idle = theme.pillFillColor
        }
        if highlighted {
            backgroundColor = action.style == .primary
                ? idle.withAlphaComponent(0.8)
                : theme.highlightedItemColor
        } else {
            backgroundColor = idle
        }
    }
}
