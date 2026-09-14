import UIKit
import AsyncDisplayKit

final class AetherTextNodeOverlayView: UIView {
    enum VerticalTextAlignment {
        case top
        case center
    }

    private let textNode = ASTextNode()

    var text: String? {
        didSet { updateText() }
    }

    var font: UIFont = .aetherScaledSystemFont(ofSize: 13.0) {
        didSet { updateText() }
    }

    var textColor: UIColor = .label {
        didSet { updateText() }
    }

    var textAlignment: NSTextAlignment = .natural {
        didSet { updateText() }
    }

    var lineBreakMode: NSLineBreakMode = .byWordWrapping {
        didSet {
            textNode.truncationMode = lineBreakMode
            updateText()
        }
    }

    var maximumNumberOfLines: UInt = 0 {
        didSet {
            textNode.maximumNumberOfLines = maximumNumberOfLines
            setNeedsLayout()
        }
    }

    var textInsets: UIEdgeInsets = .zero {
        didSet { setNeedsLayout() }
    }

    var verticalTextAlignment: VerticalTextAlignment = .top {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        textNode.view.isUserInteractionEnabled = false
        textNode.maximumNumberOfLines = maximumNumberOfLines
        textNode.truncationMode = lineBreakMode
        addSubview(textNode.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let contentRect = bounds.inset(by: textInsets)
        guard contentRect.width > 0.0, contentRect.height > 0.0 else {
            textNode.frame = .zero
            return
        }

        let measuredSize = textNode.layoutThatFits(
            ASSizeRange(min: .zero, max: contentRect.size)
        ).size
        let textHeight: CGFloat
        switch verticalTextAlignment {
        case .top:
            textHeight = contentRect.height
        case .center:
            textHeight = min(contentRect.height, ceil(measuredSize.height))
        }

        let y: CGFloat
        switch verticalTextAlignment {
        case .top:
            y = contentRect.minY
        case .center:
            y = contentRect.minY + floor((contentRect.height - textHeight) / 2.0)
        }

        textNode.frame = CGRect(
            x: contentRect.minX,
            y: y,
            width: contentRect.width,
            height: textHeight
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let maxTextSize = CGSize(
            width: size.width > 0.0 ? max(0.0, size.width - textInsets.left - textInsets.right) : .greatestFiniteMagnitude,
            height: size.height > 0.0 ? max(0.0, size.height - textInsets.top - textInsets.bottom) : .greatestFiniteMagnitude
        )
        let measuredSize = textNode.layoutThatFits(
            ASSizeRange(min: .zero, max: maxTextSize)
        ).size
        return CGSize(
            width: ceil(measuredSize.width) + textInsets.left + textInsets.right,
            height: ceil(measuredSize.height) + textInsets.top + textInsets.bottom
        )
    }

    private func updateText() {
        guard let text else {
            textNode.attributedText = nil
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = lineBreakMode

        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        setNeedsLayout()
    }
}
