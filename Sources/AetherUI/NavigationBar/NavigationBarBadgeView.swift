import UIKit
import AsyncDisplayKit

/// Badge view displayed on navigation bar items.
public final class NavigationBarBadgeView: UIView {
    private let badgeNode: NavigationBarBadgeNode

    public var contentNode: ASDisplayNode {
        badgeNode
    }

    public var text: String = "" {
        didSet {
            badgeNode.text = text
            isHidden = text.isEmpty
            setNeedsLayout()
        }
    }

    public var badgeColor: UIColor = .systemRed {
        didSet {
            badgeNode.badgeColor = badgeColor
        }
    }

    public var textColor: UIColor = .white {
        didSet {
            badgeNode.textColor = textColor
        }
    }

    public var strokeColor: UIColor = .white {
        didSet {
            badgeNode.strokeColor = strokeColor
        }
    }

    override init(frame: CGRect) {
        self.badgeNode = NavigationBarBadgeNode()

        super.init(frame: frame)

        badgeNode.view.isUserInteractionEnabled = false
        addSubview(badgeNode.view)

        isHidden = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        badgeNode.view.removeFromSuperview()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        badgeNode.frame = bounds
        badgeNode.setNeedsLayout()
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        NavigationBarBadgeNode.preferredSize(for: text)
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        badgeNode.refreshFont(compatibleWith: traitCollection)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

private final class NavigationBarBadgeNode: ASDisplayNode {
    private var font = UIFont.aetherScaledSystemFont(ofSize: 13.0, weight: .medium, maximumPointSize: 13.0)
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private let backgroundNode = ASDisplayNode()
    private let textNode = ASTextNode()

    var text: String = "" {
        didSet { updateText() }
    }

    var badgeColor: UIColor = .systemRed {
        didSet { backgroundNode.backgroundColor = badgeColor }
    }

    var textColor: UIColor = .white {
        didSet { updateText() }
    }

    var strokeColor: UIColor = .white {
        didSet { backgroundNode.borderColor = strokeColor.cgColor }
    }

    override init() {
        super.init()

        isUserInteractionEnabled = false
        // This passive fill must be available to a synchronous content
        // snapshot. UIKit can defer a view-backed node's background color
        // until compositing, leaving its CALayer transparent during capture.
        backgroundNode.isLayerBacked = true
        backgroundNode.backgroundColor = badgeColor
        backgroundNode.borderWidth = 1.0
        backgroundNode.borderColor = strokeColor.cgColor
        addSubnode(backgroundNode)

        textNode.maximumNumberOfLines = 1
        textNode.truncationMode = .byTruncatingTail
        addSubnode(textNode)

        updateText()
    }

    override func layout() {
        super.layout()

        backgroundNode.frame = bounds
        backgroundNode.cornerRadius = bounds.height / 2.0
        textNode.frame = bounds
    }

    static func preferredSize(for text: String) -> CGSize {
        let font = UIFont.aetherScaledSystemFont(ofSize: 13.0, weight: .medium, maximumPointSize: 13.0)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: max(18.0, ceil(textSize.width) + 10.0), height: 18.0)
    }

    func refreshFont(compatibleWith traitCollection: UITraitCollection) {
        font = UIFont.aetherScaledSystemFont(
            ofSize: 13.0,
            weight: .medium,
            maximumPointSize: 13.0,
            compatibleWith: traitCollection
        )
        updateText()
    }

    private func updateText() {
        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: Self.paragraphStyle
            ]
        )
        setNeedsLayout()
    }
}
