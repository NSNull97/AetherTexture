import UIKit
import AsyncDisplayKit

public final class AetherActionSheetSwitchItem: AetherActionSheetItem {
    public let title: String
    public let isOn: Bool
    public let action: (Bool) -> Void

    public init(title: String, isOn: Bool, action: @escaping (Bool) -> Void) {
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        let view = AetherActionSheetSwitchItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? AetherActionSheetSwitchItemView else { return }
        view.setItem(self)
    }
}

final class AetherActionSheetSwitchItemView: AetherActionSheetItemView {
    private var switchItemNode: AetherActionSheetSwitchItemNode {
        contentNode as! AetherActionSheetSwitchItemNode
    }

    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme, contentNode: AetherActionSheetSwitchItemNode(theme: theme))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: AetherActionSheetSwitchItem) {
        switchItemNode.setItem(item)
    }
}

final class AetherActionSheetSwitchItemNode: AetherActionSheetItemNode {
    private let titleNode = ASTextNode()
    private let switchNode: ASDisplayNode
    private var item: AetherActionSheetSwitchItem?

    private var switchControl: UISwitch? {
        switchNode.isNodeLoaded ? (switchNode.view as? UISwitch) : nil
    }

    override init(theme: AetherActionSheetTheme) {
        self.switchNode = ASDisplayNode(viewBlock: {
            let control = UISwitch()
            control.onTintColor = theme.controlAccentColor
            return control
        })
        super.init(theme: theme)
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isUserInteractionEnabled = false
        addSubnode(titleNode)
        addSubnode(switchNode)
    }

    override func didLoad() {
        super.didLoad()
        if let switchControl {
            switchControl.onTintColor = theme.controlAccentColor
            switchControl.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            if let item {
                switchControl.setOn(item.isOn, animated: false)
            }
        }
    }

    func setItem(_ item: AetherActionSheetSwitchItem) {
        self.item = item
        let font = UIFont.aetherScaledSystemFont(ofSize: floor(theme.baseFontSize * 20.0 / 17.0))
        titleNode.attributedText = NSAttributedString(
            string: item.title,
            attributes: [
                .font: font,
                .foregroundColor: theme.primaryTextColor
            ]
        )
        switchControl?.setOn(item.isOn, animated: false)
        accessibilityLabel = item.title
        accessibilityTraits = item.isOn ? [.button, .selected] : .button
        isAccessibilityElement = true
        setNeedsLayout()
    }

    override func performAction() {
        let value = !(switchControl?.isOn ?? item?.isOn ?? false)
        switchControl?.setOn(value, animated: true)
        item?.action(value)
    }

    override func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        let titleHeight = titleNode.attributedText?.size().height ?? 0.0
        return max(Self.defaultItemHeight, ceil(titleHeight) + 24.0)
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        let switchSize = switchControl?.bounds.size.width.isZero == false
            ? switchControl?.bounds.size ?? CGSize(width: 51.0, height: 31.0)
            : CGSize(width: 51.0, height: 31.0)
        let switchFrame = CGRect(
            x: size.width - 16.0 - switchSize.width,
            y: floor((size.height - switchSize.height) / 2.0),
            width: switchSize.width,
            height: switchSize.height
        )
        switchNode.frame = switchFrame

        let titleFits = titleNode.layoutThatFits(
            ASSizeRange(
                min: .zero,
                max: CGSize(width: max(1.0, switchFrame.minX - 24.0), height: size.height)
            )
        ).size
        titleNode.frame = CGRect(
            x: 16.0,
            y: floor((size.height - titleFits.height) / 2.0),
            width: titleFits.width,
            height: titleFits.height
        )
    }

    @objc private func switchChanged() {
        item?.action(switchControl?.isOn ?? false)
    }
}
