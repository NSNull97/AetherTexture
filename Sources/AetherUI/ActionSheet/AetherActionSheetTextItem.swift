import UIKit
import AsyncDisplayKit

public final class AetherActionSheetTextItem: AetherActionSheetItem {
    public enum Font {
        case `default`
        case large
    }

    public let title: String
    public let font: Font
    public let parseMarkdown: Bool

    public init(title: String, font: Font = .default, parseMarkdown: Bool = false) {
        self.title = title
        self.font = font
        self.parseMarkdown = parseMarkdown
    }

    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        let view = AetherActionSheetTextItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? AetherActionSheetTextItemView else { return }
        view.setItem(self)
    }
}

final class AetherActionSheetTextItemView: AetherActionSheetItemView {
    private var textNode: AetherActionSheetTextItemNode {
        contentNode as! AetherActionSheetTextItemNode
    }

    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme, contentNode: AetherActionSheetTextItemNode(theme: theme))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: AetherActionSheetTextItem) {
        textNode.setItem(item)
    }

    override func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        textNode.preferredHeight(constrainedWidth: constrainedWidth)
    }

    // Text items don't highlight.
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {}
}

final class AetherActionSheetTextItemNode: AetherActionSheetItemNode {
    private let titleNode = ASTextNode()

    override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme)
        titleNode.maximumNumberOfLines = 0
        titleNode.isUserInteractionEnabled = false
        addSubnode(titleNode)
    }

    func setItem(_ item: AetherActionSheetTextItem) {
        let fontSize: CGFloat
        switch item.font {
        case .default: fontSize = 13.0
        case .large:   fontSize = 15.0
        }
        let font = UIFont.aetherScaledSystemFont(ofSize: floor(theme.baseFontSize * fontSize / 17.0))
        if item.parseMarkdown {
            titleNode.attributedText = Self.markdownAttributedString(
                item.title,
                font: font,
                color: theme.secondaryTextColor
            )
        } else {
            titleNode.attributedText = Self.attributedString(
                item.title,
                font: font,
                color: theme.secondaryTextColor
            )
        }
        setNeedsLayout()
    }

    override func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        let labelBox = CGSize(width: max(1.0, constrainedWidth - 20.0), height: .greatestFiniteMagnitude)
        let height = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: labelBox)).size.height
        return max(Self.defaultItemHeight, height + 32.0)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10.0
        let labelBox = CGSize(width: max(1.0, bounds.width - inset * 2.0), height: .greatestFiniteMagnitude)
        let titleSize = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: labelBox)).size
        titleNode.frame = CGRect(
            x: inset,
            y: floor((bounds.height - titleSize.height) / 2.0),
            width: labelBox.width,
            height: titleSize.height
        )
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {}

    private static func attributedString(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func markdownAttributedString(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString()
        var index = text.startIndex
        var isBold = false

        while index < text.endIndex {
            if text[index...].hasPrefix("**") {
                isBold.toggle()
                index = text.index(index, offsetBy: 2)
                continue
            }

            let next = text.index(after: index)
            let substring = String(text[index..<next])
            let attributes: [NSAttributedString.Key: Any] = [
                .font: isBold
                    ? UIFont(
                        descriptor: font.fontDescriptor.withSymbolicTraits(.traitBold) ?? font.fontDescriptor,
                        size: font.pointSize
                    )
                    : font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            result.append(NSAttributedString(string: substring, attributes: attributes))
            index = next
        }

        return result
    }
}
