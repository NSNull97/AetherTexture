import UIKit
import AsyncDisplayKit
import SnapKit

public struct AetherToolbarAction: Equatable {
    public enum Color: Equatable {
        case accent
        case destructive
        case custom(UIColor)
    }

    public let title: String
    public let isEnabled: Bool
    public let color: Color

    public init(title: String, isEnabled: Bool = true, color: Color = .accent) {
        self.title = title
        self.isEnabled = isEnabled
        self.color = color
    }
}

public struct AetherToolbar: Equatable {
    public let leftAction: AetherToolbarAction?
    public let middleAction: AetherToolbarAction?
    public let rightAction: AetherToolbarAction?

    public init(
        leftAction: AetherToolbarAction? = nil,
        middleAction: AetherToolbarAction? = nil,
        rightAction: AetherToolbarAction? = nil
    ) {
        self.leftAction = leftAction
        self.middleAction = middleAction
        self.rightAction = rightAction
    }
}

public struct AetherToolbarTheme: Equatable {
    public let backgroundColor: UIColor
    public let separatorColor: UIColor
    public let textColor: UIColor
    public let accentColor: UIColor
    public let destructiveColor: UIColor
    public let disabledColor: UIColor
    public let font: UIFont

    public init(
        backgroundColor: UIColor,
        separatorColor: UIColor,
        textColor: UIColor,
        accentColor: UIColor,
        destructiveColor: UIColor,
        disabledColor: UIColor,
        font: UIFont = .aetherScaledSystemFont(ofSize: 17.0)
    ) {
        self.backgroundColor = backgroundColor
        self.separatorColor = separatorColor
        self.textColor = textColor
        self.accentColor = accentColor
        self.destructiveColor = destructiveColor
        self.disabledColor = disabledColor
        self.font = font
    }

    public static let light = AetherToolbarTheme(
        backgroundColor: UIColor.white.withAlphaComponent(0.82),
        separatorColor: UIColor(white: 0.0, alpha: 0.12),
        textColor: .black,
        accentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),
        disabledColor: UIColor(white: 0.6, alpha: 1.0)
    )

    public static let dark = AetherToolbarTheme(
        backgroundColor: UIColor(white: 0.1, alpha: 0.82),
        separatorColor: UIColor(white: 1.0, alpha: 0.12),
        textColor: .white,
        accentColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0),
        disabledColor: UIColor(white: 0.5, alpha: 1.0)
    )
}

/// Bottom-anchored toolbar with up to three text buttons (left, middle,
/// right). Its surface follows the application appearance at runtime.
public final class AetherToolbarView: UIView {
    private static let contentHeight: CGFloat = 44.0
    private static let horizontalInset: CGFloat = 16.0

    public var theme: AetherToolbarTheme {
        didSet { applyTheme() }
    }

    public var toolbar: AetherToolbar {
        didSet {
            if toolbar != oldValue {
                updateButtons()
            }
        }
    }

    /// Hairline at the top of the toolbar. Match `NavigationBar`'s default —
    /// visible on most backgrounds.
    public var displayTopSeparator: Bool = true {
        didSet { separatorNode.isHidden = !displayTopSeparator }
    }

    public var leftTapped: () -> Void = {}
    public var middleTapped: () -> Void = {}
    public var rightTapped: () -> Void = {}

    private let blurView: GlassBackgroundView
    private let tintNode = ASDisplayNode()
    private let separatorNode = ASDisplayNode()
    private let leftButton = AetherToolbarViewButtonNode(alignment: .left)
    private let middleButton = AetherToolbarViewButtonNode(alignment: .center)
    private let rightButton = AetherToolbarViewButtonNode(alignment: .right)

    public init(theme: AetherToolbarTheme = .light, toolbar: AetherToolbar = AetherToolbar()) {
        self.theme = theme
        self.toolbar = toolbar
        self.blurView = GlassBackgroundView(style: .regular)
        super.init(frame: .zero)

        blurView.surfaceRole = .attachedBar
        blurView.glassIsInteractive = false
        blurView.isDarkOverride = theme.textColor == .white
        blurView.legacySurfaceColorOverride = theme.backgroundColor

        addSubview(blurView)
        addSubview(tintNode.view)
        addSubview(separatorNode.view)
        [leftButton, middleButton, rightButton].forEach { addSubview($0.view) }

        leftButton.action = { [weak self] in self?.leftTapped() }
        middleButton.action = { [weak self] in self?.middleTapped() }
        rightButton.action = { [weak self] in self?.rightTapped() }

        setupConstraints()

        applyTheme()
        updateButtons()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        tintNode.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        separatorNode.view.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }

        // Three equal-width columns across the horizontal safe-area guide.
        // Height pinned to the 44pt content band; the remaining space below
        // (home indicator, extra bottom inset) is owned by the toolbar view
        // itself and left empty on purpose.
        leftButton.view.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(safeAreaLayoutGuide).offset(Self.horizontalInset)
            make.height.equalTo(Self.contentHeight)
        }
        middleButton.view.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(leftButton.view.snp.trailing)
            make.width.equalTo(leftButton.view)
            make.height.equalTo(Self.contentHeight)
        }
        rightButton.view.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(middleButton.view.snp.trailing)
            make.trailing.equalTo(safeAreaLayoutGuide).offset(-Self.horizontalInset)
            make.width.equalTo(leftButton.view)
            make.height.equalTo(Self.contentHeight)
        }
    }

    private func applyTheme() {
        blurView.isDarkOverride = theme.textColor == .white
        blurView.legacySurfaceColorOverride = theme.backgroundColor
        tintNode.backgroundColor = .clear
        separatorNode.backgroundColor = theme.separatorColor
        separatorNode.isHidden = !displayTopSeparator
        updateButtons()
    }

    private func updateButtons() {
        configure(button: leftButton, action: toolbar.leftAction)
        configure(button: middleButton, action: toolbar.middleAction)
        configure(button: rightButton, action: toolbar.rightAction)
    }

    private func configure(button: AetherToolbarViewButtonNode, action: AetherToolbarAction?) {
        button.configure(action: action, theme: theme)
    }

    /// Standard content height: 44pt + bottom safe area. Call in parent's
    /// layout to size the toolbar correctly.
    public static func preferredHeight(bottomSafeInset: CGFloat) -> CGFloat {
        return contentHeight + bottomSafeInset
    }

}

private final class AetherToolbarViewButtonNode: AetherControlNode {
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

        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        addSubnode(titleNode)
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
        let titleWidth = min(bounds.width, ceil(measured.width))
        let titleHeight = min(bounds.height, ceil(measured.height))
        let x: CGFloat
        switch alignment {
        case .left:
            x = 0.0
        case .center:
            x = floor((bounds.width - titleWidth) / 2.0)
        case .right:
            x = max(0.0, bounds.width - titleWidth)
        }

        titleNode.frame = CGRect(
            x: x,
            y: floor((bounds.height - titleHeight) / 2.0),
            width: titleWidth,
            height: titleHeight
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
