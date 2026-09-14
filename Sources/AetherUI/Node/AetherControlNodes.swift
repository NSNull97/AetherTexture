import UIKit
import AsyncDisplayKit

public final class AetherButtonNode: ASButtonNode, AetherAnimatableNode {
    public let animationIdentity = AetherAnimationIdentity(UUID().uuidString)

    public var action: (() -> Void)?

    public override init() {
        super.init()
        addTarget(self, action: #selector(pressed), forControlEvents: .touchUpInside)
    }

    public convenience init(title: String, image: UIImage? = nil) {
        self.init()
        setTitle(
            title,
            with: UIFont.aetherScaledSystemFont(ofSize: 17.0, weight: .semibold),
            with: UIColor.label,
            for: .normal
        )
        setImage(image, for: .normal)
    }

    @objc private func pressed() {
        action?()
    }
}

public final class AetherGlassButtonNode: AetherControlNode, AetherAppearanceConsumer {
    public var title: String? {
        didSet {
            titleNode.attributedText = attributedTitle()
            setNeedsLayout()
        }
    }

    public var image: UIImage? {
        didSet {
            imageNode.image = image
            imageNode.isHidden = image == nil
            setNeedsLayout()
        }
    }

    public var action: (() -> Void)?

    /// `nil` follows the application runtime. Texture-native buttons keep
    /// their passive-node renderer, while their colors and interaction state
    /// resolve through the same Legacy/Liquid appearance contract as UIKit.
    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    public override var isHighlighted: Bool {
        didSet { updateAppearance(animated: true) }
    }

    public override var isEnabled: Bool {
        didSet { updateAppearance(animated: true) }
    }

    private let backgroundNode = ASDisplayNode()
    private let titleNode = ASTextNode()
    private let imageNode = ASImageNode()
    private var appliedAppearanceStyle: AetherAppearanceStyle

    public init(
        title: String? = nil,
        image: UIImage? = nil,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.title = title
        self.image = image
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        super.init()
        addSubnode(backgroundNode)
        addSubnode(imageNode)
        addSubnode(titleNode)
        addTarget(self, action: #selector(pressed), forControlEvents: .touchUpInside)
        titleNode.maximumNumberOfLines = 1
        titleNode.attributedText = attributedTitle()
        imageNode.image = image
        imageNode.isHidden = image == nil
        clipsToBounds = false
        AetherAppearanceConsumerRegistry.register(self)
        updateAppearance(animated: false)
    }

    public override func layout() {
        super.layout()
        backgroundNode.frame = bounds
        backgroundNode.cornerRadius = min(bounds.height / 2.0, 18.0)

        let spacing: CGFloat = image == nil || title == nil ? 0.0 : 8.0
        let maxTextWidth = max(0.0, bounds.width - 24.0)
        let titleSize = titleNode.layoutThatFits(
            ASSizeRange(min: .zero, max: CGSize(width: maxTextWidth, height: bounds.height))
        ).size
        let imageSize = image?.size ?? .zero
        let scaledImageSize = image == nil
            ? .zero
            : CGSize(width: min(22.0, imageSize.width), height: min(22.0, imageSize.height))
        let contentWidth = scaledImageSize.width + spacing + titleSize.width
        var cursorX = floor((bounds.width - contentWidth) / 2.0)

        if image != nil {
            imageNode.frame = CGRect(
                x: cursorX,
                y: floor((bounds.height - scaledImageSize.height) / 2.0),
                width: scaledImageSize.width,
                height: scaledImageSize.height
            )
            cursorX += scaledImageSize.width + spacing
        }
        titleNode.frame = CGRect(
            x: cursorX,
            y: floor((bounds.height - titleSize.height) / 2.0),
            width: titleSize.width,
            height: titleSize.height
        )
    }

    private func attributedTitle() -> NSAttributedString? {
        guard let title else { return nil }
        return NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 15.0, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
        )
    }

    private func updateAppearance(animated: Bool) {
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .button,
            traitCollection: isNodeLoaded ? view.traitCollection : .current
        )
        let usesLiquidGlass = appliedAppearanceStyle.usesLiquidGlass
        let changes = {
            if usesLiquidGlass {
                self.backgroundNode.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(self.isHighlighted ? 0.86 : 0.72)
                self.backgroundNode.borderColor = UIColor.separator.withAlphaComponent(self.isHighlighted ? 0.42 : 0.28).cgColor
                self.backgroundNode.borderWidth = 1.0 / UIScreen.main.scale
            } else {
                self.backgroundNode.backgroundColor = tokens.surfaceColor.withAlphaComponent(tokens.backgroundOpacity)
                self.backgroundNode.borderColor = tokens.borderColor.cgColor
                self.backgroundNode.borderWidth = tokens.borderWidth
            }
            self.alpha = self.isEnabled
                ? (self.isHighlighted ? (usesLiquidGlass ? 0.86 : tokens.pressedAlpha) : 1.0)
                : (usesLiquidGlass ? 0.45 : tokens.disabledAlpha)
            self.transform = self.isHighlighted
                ? CATransform3DMakeScale(
                    usesLiquidGlass ? 0.97 : tokens.pressedScale,
                    usesLiquidGlass ? 0.97 : tokens.pressedScale,
                    1.0
                )
                : CATransform3DIdentity
        }
        if animated {
            AetherAnimationEngine.shared.animate(
                AetherNodeAnimation(duration: 0.16, curve: .spring(damping: 0.85, initialVelocity: 0.15)),
                changes: changes
            )
        } else {
            changes()
        }
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        appliedAppearanceStyle = appearanceStyleOverride ?? appearance.style
        updateAppearance(animated: animated)
    }

    internal var appliedAppearanceStyleForTesting: AetherAppearanceStyle {
        appliedAppearanceStyle
    }

    @objc private func pressed() {
        action?()
    }
}

public final class AetherSegmentedControlNode: AetherDisplayNode, AetherAppearanceConsumer {
    public var items: [AetherSegmentedControl.Item] {
        didSet {
            selectedIndex = clampedIndex(selectedIndex)
            rebuildSegments()
        }
    }

    public var selectedIndex: Int {
        get { _selectedIndex }
        set {
            setSelectedIndex(newValue, animated: false, notify: false)
        }
    }

    public var selectionChanged: ((Int) -> Void)?
    public var selectedIndexShouldChange: (Int, @escaping (Bool) -> Void) -> Void = { _, commit in
        commit(true)
    }

    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    public var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            updateSegmentStates()
            applySurfaceAppearance(animated: true)
        }
    }

    private let trackNode = ASDisplayNode()
    private let selectionNode = ASDisplayNode()
    private var segmentNodes: [AetherSegmentNode] = []
    private var _selectedIndex: Int
    private var appliedAppearanceStyle: AetherAppearanceStyle

    public init(
        items: [AetherSegmentedControl.Item],
        selectedIndex: Int = 0,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.items = items
        self._selectedIndex = items.isEmpty ? 0 : min(max(0, selectedIndex), items.count - 1)
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        super.init()
        addSubnode(trackNode)
        addSubnode(selectionNode)
        rebuildSegments()
        AetherAppearanceConsumerRegistry.register(self)
        applySurfaceAppearance(animated: false)
    }

    public override func layout() {
        super.layout()
        trackNode.frame = bounds
        trackNode.cornerRadius = bounds.height / 2.0
        layoutSelectionNode(animated: false)

        guard !segmentNodes.isEmpty else { return }
        let segmentWidth = bounds.width / CGFloat(segmentNodes.count)
        for (index, node) in segmentNodes.enumerated() {
            node.frame = CGRect(
                x: floor(CGFloat(index) * segmentWidth),
                y: 0.0,
                width: ceil(segmentWidth),
                height: bounds.height
            )
        }
    }

    public func setSelectedIndex(_ index: Int, animated: Bool) {
        setSelectedIndex(index, animated: animated, notify: false)
    }

    private func rebuildSegments() {
        for node in segmentNodes {
            node.removeFromSupernode()
        }
        segmentNodes = items.enumerated().map { index, item in
            let node = AetherSegmentNode(item: item)
            node.isSelected = index == selectedIndex
            node.isEnabled = isEnabled
            node.action = { [weak self] in
                self?.requestSelection(at: index)
            }
            addSubnode(node)
            return node
        }
        updateSegmentStates()
        setNeedsLayout()
    }

    private func requestSelection(at index: Int) {
        guard isEnabled else { return }
        let targetIndex = clampedIndex(index)
        guard targetIndex != selectedIndex else { return }
        selectedIndexShouldChange(targetIndex) { [weak self] shouldCommit in
            guard shouldCommit else { return }
            self?.setSelectedIndex(targetIndex, animated: true, notify: true)
        }
    }

    private func setSelectedIndex(_ index: Int, animated: Bool, notify: Bool) {
        let clampedIndex = clampedIndex(index)
        guard clampedIndex != _selectedIndex else { return }
        _selectedIndex = clampedIndex
        for (segmentIndex, node) in segmentNodes.enumerated() {
            node.isSelected = segmentIndex == clampedIndex
        }
        updateSegmentStates()
        layoutSelectionNode(animated: animated)
        if notify {
            selectionChanged?(clampedIndex)
        }
    }

    private func layoutSelectionNode(animated: Bool) {
        guard !items.isEmpty, bounds.width > 0.0, bounds.height > 0.0 else {
            selectionNode.frame = .zero
            return
        }
        let inset: CGFloat = 2.0
        let segmentWidth = bounds.width / CGFloat(items.count)
        let targetFrame = CGRect(
            x: CGFloat(selectedIndex) * segmentWidth + inset,
            y: inset,
            width: max(0.0, segmentWidth - inset * 2.0),
            height: max(0.0, bounds.height - inset * 2.0)
        )
        selectionNode.cornerRadius = targetFrame.height / 2.0
        let changes = {
            self.selectionNode.frame = targetFrame
        }
        if animated {
            AetherAnimationEngine.shared.animate(
                AetherNodeAnimation(duration: 0.22, curve: .spring(damping: 0.82, initialVelocity: 0.2)),
                changes: changes
            )
        } else {
            changes()
        }
    }

    private func clampedIndex(_ index: Int) -> Int {
        guard !items.isEmpty else { return 0 }
        return min(max(0, index), items.count - 1)
    }

    private func updateSegmentStates() {
        for (index, node) in segmentNodes.enumerated() {
            node.isEnabled = isEnabled
            node.isSelected = index == _selectedIndex
        }
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        appliedAppearanceStyle = appearanceStyleOverride ?? appearance.style
        applySurfaceAppearance(animated: animated)
    }

    private func applySurfaceAppearance(animated: Bool) {
        let trackTokens = AetherLegacySurfaceTokens.resolve(
            role: .input,
            traitCollection: isNodeLoaded ? view.traitCollection : .current
        )
        let selectionTokens = AetherLegacySurfaceTokens.resolve(
            role: .selectionIndicator,
            traitCollection: isNodeLoaded ? view.traitCollection : .current
        )
        let usesLiquidGlass = appliedAppearanceStyle.usesLiquidGlass
        let changes = {
            if usesLiquidGlass {
                self.trackNode.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.68)
                self.selectionNode.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
                self.selectionNode.shadowColor = UIColor.black.cgColor
                self.selectionNode.shadowOpacity = 0.08
                self.selectionNode.shadowRadius = 8.0
                self.selectionNode.shadowOffset = CGSize(width: 0.0, height: 2.0)
            } else {
                self.trackNode.backgroundColor = trackTokens.surfaceColor.withAlphaComponent(trackTokens.backgroundOpacity)
                self.selectionNode.backgroundColor = selectionTokens.surfaceColor.withAlphaComponent(selectionTokens.backgroundOpacity)
                self.selectionNode.shadowOpacity = 0.0
                self.selectionNode.shadowRadius = 0.0
                self.selectionNode.shadowOffset = .zero
            }
            self.alpha = self.isEnabled
                ? 1.0
                : (usesLiquidGlass ? 0.45 : selectionTokens.disabledAlpha)
        }
        if animated {
            AetherAnimationEngine.shared.animate(
                AetherNodeAnimation(duration: 0.2, curve: .easeInOut),
                changes: changes
            )
        } else {
            changes()
        }
    }

    internal var appliedAppearanceStyleForTesting: AetherAppearanceStyle {
        appliedAppearanceStyle
    }

    internal func badgeFrameForTesting(at index: Int) -> CGRect? {
        guard segmentNodes.indices.contains(index) else { return nil }
        return segmentNodes[index].badgeFrameForTesting
    }
}

private final class AetherSegmentNode: AetherControlNode {
    var action: (() -> Void)?

    override var isSelected: Bool {
        didSet {
            updateText()
            updateAccessibilityState()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateText()
            updateAccessibilityState()
        }
    }

    private let item: AetherSegmentedControl.Item
    private let titleNode = ASTextNode()
    private let badgeBackgroundNode = ASDisplayNode()
    private let badgeNode = ASTextNode()

    var badgeFrameForTesting: CGRect {
        badgeBackgroundNode.isHidden ? .zero : badgeBackgroundNode.frame
    }

    init(item: AetherSegmentedControl.Item) {
        self.item = item
        super.init()
        addSubnode(titleNode)
        addSubnode(badgeBackgroundNode)
        addSubnode(badgeNode)
        titleNode.maximumNumberOfLines = 1
        badgeNode.maximumNumberOfLines = 1
        badgeBackgroundNode.backgroundColor = .systemRed
        badgeBackgroundNode.borderColor = UIColor.white.cgColor
        badgeBackgroundNode.borderWidth = 1.0
        badgeBackgroundNode.cornerRadius = 9.0
        isAccessibilityElement = true
        accessibilityLabel = item.badgeValue.map { "\(item.title), \($0)" } ?? item.title
        addTarget(self, action: #selector(pressed), forControlEvents: .touchUpInside)
        updateText()
        updateAccessibilityState()
    }

    override func layout() {
        super.layout()
        let titleSize = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: bounds.size)).size
        let hasBadge = item.badgeValue?.isEmpty == false
        let rawBadgeSize = badgeNode.layoutThatFits(ASSizeRange(min: .zero, max: bounds.size)).size
        let badgeSize = hasBadge
            ? CGSize(width: max(18.0, ceil(rawBadgeSize.width) + 10.0), height: 18.0)
            : .zero
        let spacing: CGFloat = hasBadge ? 4.0 : 0.0
        let contentWidth = titleSize.width + spacing + badgeSize.width
        var x = floor((bounds.width - contentWidth) / 2.0)

        titleNode.frame = CGRect(
            x: x,
            y: floor((bounds.height - titleSize.height) / 2.0),
            width: titleSize.width,
            height: titleSize.height
        )
        x += titleSize.width + spacing
        let badgeFrame = CGRect(
            x: x,
            y: floor((bounds.height - badgeSize.height) / 2.0),
            width: badgeSize.width,
            height: badgeSize.height
        )
        badgeBackgroundNode.frame = badgeFrame
        badgeNode.frame = badgeFrame
        badgeBackgroundNode.isHidden = !hasBadge
        badgeNode.isHidden = !hasBadge
    }

    private func updateText() {
        titleNode.attributedText = NSAttributedString(
            string: item.title,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 14.0, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isEnabled
                    ? (isSelected ? UIColor.label : UIColor.secondaryLabel)
                    : UIColor.tertiaryLabel
            ]
        )
        if let badgeValue = item.badgeValue {
            badgeNode.attributedText = NSAttributedString(
                string: badgeValue,
                attributes: [
                    .font: UIFont.aetherScaledSystemFont(ofSize: 13.0, weight: .medium, maximumPointSize: 13.0),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: Self.badgeParagraphStyle
                ]
            )
        } else {
            badgeNode.attributedText = nil
        }
        setNeedsLayout()
    }

    private func updateAccessibilityState() {
        var traits: UIAccessibilityTraits = [.button]
        if isSelected {
            traits.insert(.selected)
        }
        if !isEnabled {
            traits.insert(.notEnabled)
        }
        accessibilityTraits = traits
    }

    private static let badgeParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    @objc private func pressed() {
        action?()
    }
}
