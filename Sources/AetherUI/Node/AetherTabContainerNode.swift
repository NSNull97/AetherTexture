import UIKit
import AsyncDisplayKit

public final class AetherTabBarItemNode: AetherControlNode {
    public var title: String? {
        didSet { titleNode.attributedText = attributedTitle() }
    }

    public var badgeValue: String? {
        didSet { badgeNode.attributedText = attributedBadge(); setNeedsLayout() }
    }

    public override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            updateAppearance(animated: true)
        }
    }

    private let titleNode = ASTextNode()
    private let badgeNode = ASTextNode()

    public init(title: String? = nil, badgeValue: String? = nil) {
        self.title = title
        self.badgeValue = badgeValue
        super.init()
        addSubnode(titleNode)
        addSubnode(badgeNode)
        titleNode.maximumNumberOfLines = 1
        badgeNode.maximumNumberOfLines = 1
        titleNode.attributedText = attributedTitle()
        badgeNode.attributedText = attributedBadge()
        updateAppearance(animated: false)
    }

    public override func layout() {
        super.layout()
        let titleSize = measuredSize(for: titleNode, maxSize: bounds.size)
        titleNode.frame = CGRect(
            x: floor((bounds.width - titleSize.width) / 2.0),
            y: floor((bounds.height - titleSize.height) / 2.0),
            width: titleSize.width,
            height: titleSize.height
        )

        let badgeSize = measuredSize(for: badgeNode, maxSize: bounds.size)
        badgeNode.frame = CGRect(
            x: min(bounds.width - badgeSize.width - 6.0, titleNode.frame.maxX + 4.0),
            y: max(2.0, titleNode.frame.minY - badgeSize.height * 0.5),
            width: badgeSize.width,
            height: badgeSize.height
        )
        badgeNode.isHidden = badgeValue == nil
    }

    private func attributedTitle() -> NSAttributedString? {
        guard let title else { return nil }
        return NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 12.0, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? UIColor.label : UIColor.secondaryLabel
            ]
        )
    }

    private func attributedBadge() -> NSAttributedString? {
        guard let badgeValue else { return nil }
        return NSAttributedString(
            string: badgeValue,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 10.0, weight: .semibold),
                .foregroundColor: UIColor.systemRed
            ]
        )
    }

    private func updateAppearance(animated: Bool) {
        titleNode.attributedText = attributedTitle()
        let changes = {
            self.titleNode.alpha = self.isSelected ? 1.0 : 0.72
            self.transform = self.isSelected
                ? CATransform3DMakeScale(1.04, 1.04, 1.0)
                : CATransform3DIdentity
        }
        if animated {
            AetherAnimationEngine.shared.animate(
                AetherNodeAnimation(duration: 0.18, curve: .spring(damping: 0.82, initialVelocity: 0.2)),
                changes: changes
            )
        } else {
            changes()
        }
    }

    private func measuredSize(for node: ASDisplayNode, maxSize: CGSize) -> CGSize {
        node.layoutThatFits(ASSizeRange(min: .zero, max: maxSize)).size
    }
}

public final class AetherTabItemNode {
    public let contentNode: AetherScreenNode
    public let barItemNode: AetherTabBarItemNode

    public init(contentNode: AetherScreenNode, barItemNode: AetherTabBarItemNode) {
        self.contentNode = contentNode
        self.barItemNode = barItemNode
    }
}

public final class AetherTabContainerNode: AetherDisplayNode {
    public var tabs: [AetherTabItemNode] {
        didSet { reloadTabs(previous: oldValue) }
    }

    public private(set) var selectedIndex: Int
    public var selectedIndexChanged: ((Int) -> Void)?
    public var tabBarHeight: CGFloat = 56.0 {
        didSet { setNeedsLayout() }
    }

    private let contentContainerNode = ASDisplayNode()
    private let tabBarNode = ASDisplayNode()

    public init(tabs: [AetherTabItemNode] = [], selectedIndex: Int = 0) {
        self.tabs = tabs
        self.selectedIndex = min(max(0, selectedIndex), max(0, tabs.count - 1))
        super.init()
        addSubnode(contentContainerNode)
        addSubnode(tabBarNode)
        reloadTabs(previous: [])
    }

    public override func layout() {
        super.layout()
        let barHeight = min(tabBarHeight, bounds.height)
        contentContainerNode.frame = CGRect(x: 0.0, y: 0.0, width: bounds.width, height: bounds.height - barHeight)
        tabBarNode.frame = CGRect(x: 0.0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
        tabs[safe: selectedIndex]?.contentNode.frame = contentContainerNode.bounds

        guard !tabs.isEmpty else { return }
        let itemWidth = bounds.width / CGFloat(tabs.count)
        for (index, tab) in tabs.enumerated() {
            tab.barItemNode.frame = CGRect(
                x: floor(CGFloat(index) * itemWidth),
                y: 0.0,
                width: ceil(itemWidth),
                height: barHeight
            )
        }
    }

    public func selectTab(at index: Int, animated: Bool) {
        guard index >= 0, index < tabs.count, index != selectedIndex else { return }
        let previous = tabs[selectedIndex]
        let next = tabs[index]
        selectedIndex = index
        selectedIndexChanged?(selectedIndex)
        previous.barItemNode.isSelected = false
        next.barItemNode.isSelected = true

        if next.contentNode.supernode !== contentContainerNode {
            next.contentNode.frame = contentContainerNode.bounds
            contentContainerNode.addSubnode(next.contentNode)
        }
        previous.contentNode.screenWillDisappear()
        next.contentNode.screenWillAppear()
        // Publish only after the destination node is mounted. Consumers
        // resolve synchronously; notifying before this point made a fresh
        // Texture tab look like a stable screen with no scroll source.
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)

        let finish: (Bool) -> Void = { [weak previous, weak next] finished in
            previous?.contentNode.removeFromSupernode()
            previous?.contentNode.screenDidDisappear()
            if finished {
                next?.contentNode.screenDidAppear()
            }
        }

        guard animated else {
            finish(true)
            return
        }

        next.contentNode.alpha = 0.0
        AetherAnimationEngine.shared.animate(
            AetherNodeAnimation(duration: 0.2, curve: .easeInOut)
        ) {
            previous.contentNode.alpha = 0.0
            next.contentNode.alpha = 1.0
        } completion: { finished in
            previous.contentNode.alpha = 1.0
            next.contentNode.alpha = 1.0
            finish(finished)
        }
    }

    private func reloadTabs(previous: [AetherTabItemNode]) {
        let previousSelectedNode = previous[safe: selectedIndex]?.contentNode
        previousSelectedNode?.screenWillDisappear()
        for tab in previous {
            tab.barItemNode.removeTarget(self, action: #selector(tabItemPressed(_:)), forControlEvents: .touchUpInside)
            tab.contentNode.removeFromSupernode()
            tab.barItemNode.removeFromSupernode()
        }
        previousSelectedNode?.screenDidDisappear()

        guard !tabs.isEmpty else {
            selectedIndex = 0
            selectedIndexChanged?(selectedIndex)
            AetherChromeScrollSourceResolver.notifyDidChange(from: self)
            return
        }
        selectedIndex = min(max(0, selectedIndex), tabs.count - 1)
        selectedIndexChanged?(selectedIndex)
        for (index, tab) in tabs.enumerated() {
            tab.barItemNode.isSelected = index == selectedIndex
            tab.barItemNode.addTarget(self, action: #selector(tabItemPressed(_:)), forControlEvents: .touchUpInside)
            tabBarNode.addSubnode(tab.barItemNode)
        }
        let selected = tabs[selectedIndex].contentNode
        if selected.supernode !== contentContainerNode {
            contentContainerNode.addSubnode(selected)
            selected.screenWillAppear()
            selected.screenDidAppear()
        }
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
        setNeedsLayout()
    }

    @objc private func tabItemPressed(_ sender: AetherTabBarItemNode) {
        guard let index = tabs.firstIndex(where: { $0.barItemNode === sender }) else { return }
        selectTab(at: index, animated: true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
