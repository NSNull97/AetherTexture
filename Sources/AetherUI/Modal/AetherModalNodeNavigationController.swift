import UIKit

open class AetherModalNodeNavigationController: AetherModalController {
    public let internalNavigationController: AetherNodeNavigationController

    public var rootNode: AetherScreenNode? {
        internalNavigationController.navigationNode.stack.first
    }

    public var topNode: AetherScreenNode? {
        internalNavigationController.navigationNode.topNode
    }

    public var nodes: [AetherScreenNode] {
        get { internalNavigationController.navigationNode.stack }
        set { internalNavigationController.setStack(newValue, animated: false) }
    }

    public init(
        rootNode: AetherScreenNode? = nil,
        config: Config = Config()
    ) {
        self.internalNavigationController = AetherNodeNavigationController(rootNode: rootNode)
        super.init(config: config)
        internalNavigationController.view.backgroundColor = .clear
    }


    public init(
        rootNode: AetherScreenNode? = nil,
        config: Config = Config(),
        appearanceStyle: AetherAppearanceStyle
    ) {
        self.internalNavigationController = AetherNodeNavigationController(rootNode: rootNode)
        super.init(config: config)
        self.appearanceStyle = appearanceStyle
        internalNavigationController.view.backgroundColor = .clear
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        embedContent(internalNavigationController)
    }

    public func push(_ node: AetherScreenNode, animated: Bool = true) {
        internalNavigationController.push(node, animated: animated)
    }

    @discardableResult
    public func popNode(animated: Bool = true) -> AetherScreenNode? {
        internalNavigationController.popNode(animated: animated)
    }

    public func popToRoot(animated: Bool = true) {
        guard let first = nodes.first else { return }
        internalNavigationController.setStack([first], animated: animated)
    }

    public func setNodes(_ nodes: [AetherScreenNode], animated: Bool = true) {
        internalNavigationController.setStack(nodes, animated: animated)
    }

    public func replaceTopNode(_ node: AetherScreenNode, animated: Bool = true) {
        var current = nodes
        if current.isEmpty {
            current = [node]
        } else {
            current[current.count - 1] = node
        }
        internalNavigationController.setStack(current, animated: animated)
    }
}
