import UIKit
import AsyncDisplayKit

public enum AetherActionSheetCheckboxStyle {
    case `default`
    case alignRight
}

public final class AetherActionSheetCheckboxItem: AetherActionSheetItem {
    public let title: String
    public let label: String
    public let value: Bool
    public let style: AetherActionSheetCheckboxStyle
    public let action: (Bool) -> Void

    public init(
        title: String,
        label: String = "",
        value: Bool,
        style: AetherActionSheetCheckboxStyle = .default,
        action: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.label = label
        self.value = value
        self.style = style
        self.action = action
    }

    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        let view = AetherActionSheetCheckboxItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? AetherActionSheetCheckboxItemView else { return }
        view.setItem(self)
    }
}

final class AetherActionSheetCheckboxItemView: AetherActionSheetItemView {
    private var checkboxNode: AetherActionSheetCheckboxItemNode {
        contentNode as! AetherActionSheetCheckboxItemNode
    }

    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme, contentNode: AetherActionSheetCheckboxItemNode(theme: theme))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: AetherActionSheetCheckboxItem) {
        checkboxNode.setItem(item)
    }
}

final class AetherActionSheetCheckboxItemNode: AetherActionSheetItemNode {
    private let titleNode = ASTextNode()
    private let trailingNode = ASTextNode()
    private let checkImageNode = ASImageNode()
    private var item: AetherActionSheetCheckboxItem?

    override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme)
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isUserInteractionEnabled = false
        trailingNode.maximumNumberOfLines = 1
        trailingNode.truncationMode = .byTruncatingTail
        trailingNode.isUserInteractionEnabled = false
        checkImageNode.isUserInteractionEnabled = false
        checkImageNode.image = Self.makeCheckImage(color: theme.controlAccentColor)

        addSubnode(titleNode)
        addSubnode(trailingNode)
        addSubnode(checkImageNode)
    }

    func setItem(_ item: AetherActionSheetCheckboxItem) {
        self.item = item

        let font = UIFont.aetherScaledSystemFont(ofSize: floor(theme.baseFontSize * 20.0 / 17.0))
        titleNode.attributedText = NSAttributedString(
            string: item.title,
            attributes: [
                .font: font,
                .foregroundColor: theme.primaryTextColor
            ]
        )
        let trailingParagraph = NSMutableParagraphStyle()
        trailingParagraph.alignment = .right
        trailingNode.attributedText = NSAttributedString(
            string: item.label,
            attributes: [
                .font: font,
                .foregroundColor: theme.secondaryTextColor,
                .paragraphStyle: trailingParagraph
            ]
        )
        checkImageNode.isHidden = !item.value

        accessibilityLabel = item.title
        accessibilityTraits = item.value ? [.button, .selected] : .button
        isAccessibilityElement = true
        setNeedsLayout()
    }

    override func performAction() {
        guard let item else { return }
        item.action(!item.value)
    }

    override func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        let height = max(
            titleNode.attributedText?.size().height ?? 0.0,
            trailingNode.attributedText?.size().height ?? 0.0
        )
        return max(Self.defaultItemHeight, ceil(height) + 24.0)
    }

    override func layout() {
        super.layout()

        let size = bounds.size
        let titleOriginX: CGFloat
        let checkOriginX: CGFloat
        if item?.style == .alignRight {
            titleOriginX = 24.0
            checkOriginX = size.width - 22.0
        } else {
            titleOriginX = 50.0
            checkOriginX = 27.0
        }

        let trailingFits = trailingNode.layoutThatFits(
            ASSizeRange(
                min: .zero,
                max: CGSize(width: max(1.0, size.width - 44.0 - 15.0 - 8.0), height: size.height)
            )
        ).size
        let titleFits = titleNode.layoutThatFits(
            ASSizeRange(
                min: .zero,
                max: CGSize(width: max(1.0, size.width - 44.0 - trailingFits.width - 15.0 - 8.0), height: size.height)
            )
        ).size

        titleNode.frame = CGRect(
            x: titleOriginX,
            y: floor((size.height - titleFits.height) / 2.0),
            width: titleFits.width,
            height: titleFits.height
        )
        trailingNode.frame = CGRect(
            x: size.width - 15.0 - trailingFits.width,
            y: floor((size.height - trailingFits.height) / 2.0),
            width: trailingFits.width,
            height: trailingFits.height
        )
        if let image = checkImageNode.image {
            checkImageNode.frame = CGRect(
                x: floor(checkOriginX - image.size.width / 2.0),
                y: floor((size.height - image.size.height) / 2.0),
                width: image.size.width,
                height: image.size.height
            )
        } else {
            checkImageNode.frame = .zero
        }
    }

    /// Checkmark — same geometry as Telegram-iOS ActionSheetCheckboxItem:
    /// 14×12 pt stroke path with 2pt rounded-cap line.
    private static func makeCheckImage(color: UIColor) -> UIImage? {
        let size = CGSize(width: 14.0, height: 12.0)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(2.0 - 1.0 / UIScreen.main.scale)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.move(to: CGPoint(x: 13.0, y: 1.0))
            cg.addLine(to: CGPoint(x: 5.0, y: 11.0))
            cg.addLine(to: CGPoint(x: 1.0, y: 7.0))
            cg.strokePath()
        }
    }
}
