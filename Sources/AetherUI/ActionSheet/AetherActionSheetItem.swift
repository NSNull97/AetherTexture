import UIKit
import AsyncDisplayKit

public protocol AetherActionSheetItem {
    func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView
    func updateView(_ view: AetherActionSheetItemView)
}

public final class AetherActionSheetItemGroup {
    public let items: [AetherActionSheetItem]

    public init(items: [AetherActionSheetItem]) {
        self.items = items
    }
}

// MARK: - ItemNode

open class AetherActionSheetItemNode: ASControlNode {
    public static let defaultItemHeight: CGFloat = 57.0

    public let theme: AetherActionSheetTheme

    public let backgroundNode = ASDisplayNode()
    /// Hairline shown below this row when it is not the last row of its
    /// group. The group container toggles `hasSeparator` on each item.
    public let separatorNode = ASDisplayNode()

    public var hasSeparator: Bool = true {
        didSet { separatorNode.isHidden = !hasSeparator }
    }

    public init(theme: AetherActionSheetTheme) {
        self.theme = theme
        super.init()

        // The appearance-aware group surface owns both Liquid and classic
        // systemChromeMaterial rendering. Keeping idle rows transparent is
        // essential in Legacy; a per-row solid fill would hide the blur.
        backgroundNode.backgroundColor = .clear
        backgroundNode.isUserInteractionEnabled = false
        separatorNode.backgroundColor = theme.separatorColor
        separatorNode.isUserInteractionEnabled = false

        addSubnode(backgroundNode)
        addSubnode(separatorNode)
        addTarget(self, action: #selector(controlDown), forControlEvents: .touchDown)
        addTarget(self, action: #selector(controlUp), forControlEvents: [.touchUpInside, .touchUpOutside, .touchCancel])
        addTarget(self, action: #selector(controlTapped), forControlEvents: .touchUpInside)
    }

    /// Override in subclasses. Return preferred height for the given width.
    open func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        return Self.defaultItemHeight
    }

    open override func layout() {
        super.layout()
        backgroundNode.frame = bounds
        separatorNode.frame = CGRect(
            x: 0,
            y: bounds.height,
            width: bounds.width,
            height: 1.0 / UIScreen.main.scale
        )
    }

    /// Called by the controller when arrow-key/enter focus lands on the row.
    open func setHighlighted(_ highlighted: Bool, animated: Bool) {
        let idle: UIColor = .clear
        let color = highlighted ? theme.itemHighlightedBackgroundColor : idle
        if animated && !highlighted {
            UIView.animate(withDuration: 0.3) {
                self.backgroundNode.backgroundColor = color
            }
        } else {
            backgroundNode.backgroundColor = color
        }
    }

    /// Invoked when user activates the row via keyboard (Enter).
    open func performAction() {}

    @objc private func controlDown() {
        setHighlighted(true, animated: false)
    }

    @objc private func controlUp() {
        setHighlighted(false, animated: true)
    }

    @objc private func controlTapped() {
        performAction()
    }
}

// MARK: - ItemView

open class AetherActionSheetItemView: UIView {
    public typealias Node = AetherActionSheetItemNode
    public static let defaultItemHeight: CGFloat = AetherActionSheetItemNode.defaultItemHeight

    public let theme: AetherActionSheetTheme
    public let contentNode: AetherActionSheetItemNode

    public var backgroundView: UIView { contentNode.backgroundNode.view }
    public var separatorView: UIView { contentNode.separatorNode.view }

    public var hasSeparator: Bool {
        get { contentNode.hasSeparator }
        set { contentNode.hasSeparator = newValue }
    }

    public init(theme: AetherActionSheetTheme) {
        self.theme = theme
        self.contentNode = AetherActionSheetItemNode(theme: theme)
        super.init(frame: .zero)
        setupNodeHost()
    }

    init(theme: AetherActionSheetTheme, contentNode: AetherActionSheetItemNode) {
        self.theme = theme
        self.contentNode = contentNode
        super.init(frame: .zero)
        setupNodeHost()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        return contentNode.preferredHeight(constrainedWidth: constrainedWidth)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        contentNode.frame = bounds
    }

    open func setHighlighted(_ highlighted: Bool, animated: Bool) {
        contentNode.setHighlighted(highlighted, animated: animated)
    }

    open func performAction() {
        contentNode.performAction()
    }

    private func setupNodeHost() {
        addSubview(contentNode.view)
    }
}
