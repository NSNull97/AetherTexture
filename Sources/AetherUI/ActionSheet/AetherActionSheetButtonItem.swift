import UIKit
import AsyncDisplayKit

public enum AetherActionSheetButtonColor {
    case accent
    case destructive
    case disabled
}

public enum AetherActionSheetButtonFont {
    case `default`
    case bold
}

public final class AetherActionSheetButtonItem: AetherActionSheetItem {
    public let title: String
    public let color: AetherActionSheetButtonColor
    public let font: AetherActionSheetButtonFont
    public let enabled: Bool
    public let action: () -> Void

    public init(
        title: String,
        color: AetherActionSheetButtonColor = .accent,
        font: AetherActionSheetButtonFont = .default,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.font = font
        self.enabled = enabled
        self.action = action
    }

    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        let view = AetherActionSheetButtonItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? AetherActionSheetButtonItemView else { return }
        view.setItem(self)
    }
}

final class AetherActionSheetButtonItemView: AetherActionSheetItemView {
    private var buttonNode: AetherActionSheetButtonItemNode {
        contentNode as! AetherActionSheetButtonItemNode
    }

    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme, contentNode: AetherActionSheetButtonItemNode(theme: theme))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: AetherActionSheetButtonItem) {
        buttonNode.setItem(item)
    }
}

final class AetherActionSheetButtonItemNode: AetherActionSheetItemNode {
    private let titleNode = ASTextNode()
    private var item: AetherActionSheetButtonItem?

    override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme)
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isUserInteractionEnabled = false
        addSubnode(titleNode)
    }

    func setItem(_ item: AetherActionSheetButtonItem) {
        self.item = item

        let fontSize = floor(theme.baseFontSize * 20.0 / 17.0)
        let font: UIFont
        switch item.font {
        case .default: font = .aetherScaledSystemFont(ofSize: fontSize)
        case .bold:    font = .aetherScaledSystemFont(ofSize: fontSize, weight: .medium)
        }

        let color: UIColor
        switch item.color {
        case .accent:      color = theme.standardActionTextColor
        case .destructive: color = theme.destructiveActionTextColor
        case .disabled:    color = theme.disabledActionTextColor
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        titleNode.attributedText = NSAttributedString(
            string: item.title,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )

        isEnabled = item.enabled
        accessibilityLabel = item.title
        accessibilityTraits = item.enabled ? .button : [.button, .notEnabled]
        isAccessibilityElement = true
        setNeedsLayout()
    }

    override func performAction() {
        guard item?.enabled == true else { return }
        item?.action()
    }

    override func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        let maxSize = CGSize(width: max(1.0, constrainedWidth - 16.0), height: .greatestFiniteMagnitude)
        let titleHeight = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: maxSize)).size.height
        return max(Self.defaultItemHeight, titleHeight + 24.0)
    }

    override func layout() {
        super.layout()
        let maxSize = CGSize(width: max(1.0, bounds.width - 16.0), height: bounds.height)
        let titleSize = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: maxSize)).size
        titleNode.frame = CGRect(
            x: floor((bounds.width - titleSize.width) / 2.0),
            y: floor((bounds.height - titleSize.height) / 2.0),
            width: titleSize.width,
            height: titleSize.height
        )
    }
}
