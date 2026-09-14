import UIKit
import AsyncDisplayKit

public final class AetherToolbarNode: AetherDisplayNode {
    private static let contentHeight: CGFloat = 44.0
    private static let horizontalInset: CGFloat = 16.0

    public var theme: AetherToolbarTheme {
        didSet { applyTheme() }
    }

    public var toolbar: AetherToolbar {
        didSet {
            guard toolbar != oldValue else { return }
            updateButtons()
        }
    }

    public var displayTopSeparator: Bool = true {
        didSet { separatorNode.isHidden = !displayTopSeparator }
    }

    public var leftTapped: () -> Void = {}
    public var middleTapped: () -> Void = {}
    public var rightTapped: () -> Void = {}

    private let backgroundNode = ASDisplayNode()
    private let separatorNode = ASDisplayNode()
    private let leftButton = AetherToolbarButtonNode(alignment: .left)
    private let middleButton = AetherToolbarButtonNode(alignment: .center)
    private let rightButton = AetherToolbarButtonNode(alignment: .right)

    public init(theme: AetherToolbarTheme = .light, toolbar: AetherToolbar = AetherToolbar()) {
        self.theme = theme
        self.toolbar = toolbar
        super.init()
        addSubnode(backgroundNode)
        addSubnode(separatorNode)
        addSubnode(leftButton)
        addSubnode(middleButton)
        addSubnode(rightButton)

        leftButton.action = { [weak self] in self?.leftTapped() }
        middleButton.action = { [weak self] in self?.middleTapped() }
        rightButton.action = { [weak self] in self?.rightTapped() }

        applyTheme()
        updateButtons()
    }

    public override func layout() {
        super.layout()
        backgroundNode.frame = bounds
        separatorNode.frame = CGRect(x: 0.0, y: 0.0, width: bounds.width, height: 1.0 / UIScreen.main.scale)

        let contentWidth = max(0.0, bounds.width - Self.horizontalInset * 2.0)
        let columnWidth = contentWidth / 3.0
        let top: CGFloat = 0.0
        leftButton.frame = CGRect(x: Self.horizontalInset, y: top, width: columnWidth, height: Self.contentHeight)
        middleButton.frame = CGRect(x: Self.horizontalInset + columnWidth, y: top, width: columnWidth, height: Self.contentHeight)
        rightButton.frame = CGRect(x: Self.horizontalInset + columnWidth * 2.0, y: top, width: columnWidth, height: Self.contentHeight)
    }

    public static func preferredHeight(bottomSafeInset: CGFloat) -> CGFloat {
        contentHeight + bottomSafeInset
    }

    private func applyTheme() {
        backgroundNode.backgroundColor = theme.backgroundColor
        separatorNode.backgroundColor = theme.separatorColor
        separatorNode.isHidden = !displayTopSeparator
        updateButtons()
    }

    private func updateButtons() {
        leftButton.configure(action: toolbar.leftAction, theme: theme)
        middleButton.configure(action: toolbar.middleAction, theme: theme)
        rightButton.configure(action: toolbar.rightAction, theme: theme)
    }
}

private final class AetherToolbarButtonNode: AetherControlNode {
    enum Alignment {
        case left
        case center
        case right
    }

    var action: (() -> Void)?

    private let alignment: Alignment
    private let titleNode = ASTextNode()
    private var toolbarAction: AetherToolbarAction?
    private var theme: AetherToolbarTheme = .light

    init(alignment: Alignment) {
        self.alignment = alignment
        super.init()
        addSubnode(titleNode)
        titleNode.maximumNumberOfLines = 1
        addTarget(self, action: #selector(pressed), forControlEvents: .touchUpInside)
    }

    override var isHighlighted: Bool {
        didSet { updateHighlighted(animated: true) }
    }

    func configure(action: AetherToolbarAction?, theme: AetherToolbarTheme) {
        self.toolbarAction = action
        self.theme = theme
        isHidden = action == nil
        isEnabled = action?.isEnabled ?? false
        guard let action else {
            titleNode.attributedText = nil
            return
        }
        titleNode.attributedText = NSAttributedString(
            string: action.title,
            attributes: [
                .font: theme.font,
                .foregroundColor: color(for: action, theme: theme)
            ]
        )
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        let measured = titleNode.layoutThatFits(
            ASSizeRange(min: .zero, max: CGSize(width: bounds.width, height: bounds.height))
        ).size
        let x: CGFloat
        switch alignment {
        case .left:
            x = 0.0
        case .center:
            x = floor((bounds.width - measured.width) / 2.0)
        case .right:
            x = max(0.0, bounds.width - measured.width)
        }
        titleNode.frame = CGRect(
            x: x,
            y: floor((bounds.height - measured.height) / 2.0),
            width: min(bounds.width, measured.width),
            height: measured.height
        )
    }

    private func color(for action: AetherToolbarAction, theme: AetherToolbarTheme) -> UIColor {
        guard action.isEnabled else { return theme.disabledColor }
        switch action.color {
        case .accent:
            return theme.accentColor
        case .destructive:
            return theme.destructiveColor
        case let .custom(color):
            return color
        }
    }

    private func updateHighlighted(animated: Bool) {
        let changes = {
            self.alpha = self.isHighlighted ? 0.55 : 1.0
        }
        if animated {
            AetherAnimationEngine.shared.animate(
                AetherNodeAnimation(duration: 0.12, curve: .easeInOut),
                changes: changes
            )
        } else {
            changes()
        }
    }

    @objc private func pressed() {
        guard toolbarAction?.isEnabled == true else { return }
        action?()
    }
}
