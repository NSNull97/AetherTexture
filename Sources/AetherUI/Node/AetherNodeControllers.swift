import UIKit
import AsyncDisplayKit

open class AetherScreenController: AetherViewController {
    public let screenNode: AetherScreenNode
    private var navigationItemObservation: AetherNavigationItemNodeObservation?

    public init(
        screenNode: AetherScreenNode,
        navigationBarPresentationData: NavigationBarPresentationData? = nil
    ) {
        self.screenNode = screenNode
        super.init(navigationBarPresentationData: navigationBarPresentationData)
        contentNode = screenNode
        bindNavigationItem()
        syncNavigationItem()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        syncNavigationItem()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        screenNode.screenWillAppear()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        screenNode.screenDidAppear()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        screenNode.screenWillDisappear()
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        screenNode.screenDidDisappear()
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        switch screenNode.preferredStatusBarStyle {
        case .default:
            return .default
        case .lightContent:
            return .lightContent
        case .darkContent:
            return .darkContent
        }
    }

    public func syncNavigationItem() {
        navigationBarItem.title = screenNode.navigationItemNode.title
        navigationItem.title = screenNode.navigationItemNode.title
    }

    private func bindNavigationItem() {
        navigationItemObservation = screenNode.navigationItemNode.addChangeObserver { [weak self] in
            self?.syncNavigationItem()
        }
    }
}

open class AetherNodeNavigationController: AetherViewController {
    public let navigationNode: AetherNavigationNode
    private var topNavigationItemObservation: AetherNavigationItemNodeObservation?

    public init(
        rootNode: AetherScreenNode? = nil,
        navigationBarPresentationData: NavigationBarPresentationData? = nil
    ) {
        self.navigationNode = AetherNavigationNode()
        super.init(navigationBarPresentationData: navigationBarPresentationData)
        contentNode = navigationNode
        if let rootNode {
            navigationNode.setStack([rootNode], animated: false)
            bindTopNavigationItem()
            syncNavigationItem(with: rootNode)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        switch navigationNode.topNode?.preferredStatusBarStyle ?? .default {
        case .default:
            return .default
        case .lightContent:
            return .lightContent
        case .darkContent:
            return .darkContent
        }
    }

    open override func push(_ node: AetherScreenNode, animated: Bool) {
        navigationNode.push(node, animated: animated)
        bindTopNavigationItem()
        syncNavigationItem(with: node)
        setNeedsStatusBarAppearanceUpdate()
    }

    @discardableResult
    public func popNode(animated: Bool) -> AetherScreenNode? {
        let popped = navigationNode.pop(animated: animated)
        bindTopNavigationItem()
        syncNavigationItem(with: navigationNode.topNode)
        setNeedsStatusBarAppearanceUpdate()
        return popped
    }

    public func setStack(_ nodes: [AetherScreenNode], animated: Bool) {
        navigationNode.setStack(nodes, animated: animated)
        bindTopNavigationItem()
        syncNavigationItem(with: nodes.last)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func bindTopNavigationItem() {
        topNavigationItemObservation?.cancel()
        topNavigationItemObservation = navigationNode.topNode?.navigationItemNode.addChangeObserver { [weak self] in
            self?.syncNavigationItem(with: self?.navigationNode.topNode)
        }
    }

    private func syncNavigationItem(with node: AetherScreenNode?) {
        navigationBarItem.title = node?.navigationItemNode.title
        navigationItem.title = node?.navigationItemNode.title
    }
}

open class AetherNodeTabContainerController: AetherViewController {
    public let tabContainerNode: AetherTabContainerNode
    private var selectedNavigationItemObservation: AetherNavigationItemNodeObservation?

    public init(
        tabs: [AetherTabItemNode] = [],
        selectedIndex: Int = 0,
        navigationBarPresentationData: NavigationBarPresentationData? = nil
    ) {
        self.tabContainerNode = AetherTabContainerNode(tabs: tabs, selectedIndex: selectedIndex)
        super.init(navigationBarPresentationData: navigationBarPresentationData)
        contentNode = tabContainerNode
        tabContainerNode.selectedIndexChanged = { [weak self] _ in
            self?.bindSelectedNavigationItem()
            self?.syncNavigationItem()
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        bindSelectedNavigationItem()
        syncNavigationItem()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var selectedIndex: Int {
        tabContainerNode.selectedIndex
    }

    public func setTabs(_ tabs: [AetherTabItemNode], selectedIndex: Int = 0) {
        tabContainerNode.tabs = tabs
        tabContainerNode.selectTab(at: selectedIndex, animated: false)
        bindSelectedNavigationItem()
        syncNavigationItem()
        setNeedsStatusBarAppearanceUpdate()
    }

    public func selectTab(at index: Int, animated: Bool) {
        tabContainerNode.selectTab(at: index, animated: animated)
        bindSelectedNavigationItem()
        syncNavigationItem()
        setNeedsStatusBarAppearanceUpdate()
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        switch tabContainerNode.tabs[safe: tabContainerNode.selectedIndex]?.contentNode.preferredStatusBarStyle ?? .default {
        case .default:
            return .default
        case .lightContent:
            return .lightContent
        case .darkContent:
            return .darkContent
        }
    }

    private func syncNavigationItem() {
        let selectedNode = tabContainerNode.tabs[safe: tabContainerNode.selectedIndex]?.contentNode
        navigationBarItem.title = selectedNode?.navigationItemNode.title
        navigationItem.title = selectedNode?.navigationItemNode.title
    }

    private func bindSelectedNavigationItem() {
        selectedNavigationItemObservation?.cancel()
        let selectedNode = tabContainerNode.tabs[safe: tabContainerNode.selectedIndex]?.contentNode
        selectedNavigationItemObservation = selectedNode?.navigationItemNode.addChangeObserver { [weak self] in
            self?.syncNavigationItem()
        }
    }
}

open class AetherNodePageController: AetherViewController {
    public let pageContainerNode: AetherPageContainerNode

    public init(
        pages: [AetherPageItemNode] = [],
        selectedIndex: Int = 0,
        navigationBarPresentationData: NavigationBarPresentationData? = nil
    ) {
        self.pageContainerNode = AetherPageContainerNode(pages: pages, selectedIndex: selectedIndex)
        super.init(navigationBarPresentationData: navigationBarPresentationData)
        contentNode = pageContainerNode
        pageContainerNode.selectedIndexChanged = { [weak self] _ in
            self?.syncNavigationItem()
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        syncNavigationItem()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var selectedIndex: Int {
        pageContainerNode.selectedIndex
    }

    public func setPages(_ pages: [AetherPageItemNode], selectedIndex: Int = 0) {
        pageContainerNode.setPages(pages, selectedIndex: selectedIndex)
        syncNavigationItem()
        setNeedsStatusBarAppearanceUpdate()
    }

    public func selectPage(at index: Int, animated: Bool) {
        pageContainerNode.selectPage(at: index, animated: animated)
        syncNavigationItem()
        setNeedsStatusBarAppearanceUpdate()
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        switch pageContainerNode.pages[safe: pageContainerNode.selectedIndex]?.contentNode.preferredStatusBarStyle ?? .default {
        case .default:
            return .default
        case .lightContent:
            return .lightContent
        case .darkContent:
            return .darkContent
        }
    }

    private func syncNavigationItem() {
        let selectedNode = pageContainerNode.pages[safe: pageContainerNode.selectedIndex]?.contentNode
        navigationBarItem.title = selectedNode?.navigationItemNode.title
        navigationItem.title = selectedNode?.navigationItemNode.title
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
