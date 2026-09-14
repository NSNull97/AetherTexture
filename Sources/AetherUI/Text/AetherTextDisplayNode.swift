import UIKit
import AsyncDisplayKit

/// Texture-native text renderer used by `TextNode`.
///
/// TextKit still acts as the geometry engine for hit testing, link rects, and
/// invisible ink until those APIs move to node-native equivalents.
public final class AetherTextDisplayNode: ASDisplayNode {
    public let textNode = ASTextNode()

    public var attributedText: NSAttributedString? {
        didSet {
            textNode.attributedText = attributedText
            setNeedsLayout()
        }
    }

    public var maximumNumberOfLines: Int = 0 {
        didSet {
            textNode.maximumNumberOfLines = UInt(max(0, maximumNumberOfLines))
            setNeedsLayout()
        }
    }

    public var truncationMode: NSLineBreakMode = .byTruncatingTail {
        didSet {
            textNode.truncationMode = truncationMode
            setNeedsLayout()
        }
    }

    public override init() {
        super.init()
        backgroundColor = .clear
        isOpaque = false
        addSubnode(textNode)
    }

    public func update(
        attributedText: NSAttributedString?,
        maximumNumberOfLines: Int,
        truncationMode: NSLineBreakMode
    ) {
        self.attributedText = attributedText
        self.maximumNumberOfLines = maximumNumberOfLines
        self.truncationMode = truncationMode
    }

    public func updateTextFrame(_ frame: CGRect) {
        textNode.frame = frame
    }
}
