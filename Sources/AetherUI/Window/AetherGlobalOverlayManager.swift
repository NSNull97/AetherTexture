import UIKit

public final class AetherGlobalOverlayManager {
    public let presentationContext: AetherPresentationContext
    public let portalHost = AetherGlobalPortalHost()
    private var nodeControllers: [ObjectIdentifier: AetherScreenController] = [:]

    public init(parentController: UIViewController? = nil, containerView: UIView? = nil) {
        presentationContext = AetherPresentationContext(parentController: parentController, containerView: containerView)
        if let containerView {
            installPortalHost(in: containerView)
        }
    }

    public func attach(parentController: UIViewController?, containerView: UIView) {
        presentationContext.parentController = parentController
        presentationContext.containerView = containerView
        installPortalHost(in: containerView)
    }

    @discardableResult
    public func present(
        _ controller: AetherContainableController,
        blockInteraction: Bool = false,
        completion: @escaping () -> Void = {}
    ) -> AetherPresentedController {
        presentationContext.present(
            controller,
            on: .globalOverlay,
            blockInteraction: blockInteraction,
            completion: completion
        )
    }

    public func dismiss(_ controller: AetherContainableController, completion: (() -> Void)? = nil) {
        presentationContext.dismiss(controller, completion: completion)
    }

    @discardableResult
    public func present(
        _ node: AetherScreenNode,
        blockInteraction: Bool = false,
        completion: @escaping () -> Void = {}
    ) -> AetherScreenController {
        let id = ObjectIdentifier(node)
        let controller = nodeControllers[id] ?? AetherScreenController(screenNode: node)
        nodeControllers[id] = controller
        present(controller, blockInteraction: blockInteraction, completion: completion)
        return controller
    }

    public func dismiss(_ node: AetherScreenNode, completion: (() -> Void)? = nil) {
        let id = ObjectIdentifier(node)
        guard let controller = nodeControllers[id] else {
            completion?()
            return
        }
        dismiss(controller) { [weak self] in
            self?.nodeControllers[id] = nil
            completion?()
        }
    }

    public func updateLayout(_ layout: AetherWindowLayout, transition: ContainedViewLayoutTransition) {
        presentationContext.updateLayout(layout, transition: transition)
        transition.updateFrame(view: portalHost, frame: CGRect(origin: .zero, size: layout.size))
    }

    public func hitTest(point: CGPoint, in view: UIView, with event: UIEvent?) -> UIView? {
        presentationContext.hitTest(point: point, in: view, with: event)
    }

    public func addGlobalPortal(sourceView: AetherPortalSourceView) {
        portalHost.addPortal(sourceView: sourceView)
    }

    private func installPortalHost(in containerView: UIView) {
        if portalHost.superview !== containerView {
            portalHost.removeFromSuperview()
            portalHost.frame = containerView.bounds
            portalHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            containerView.addSubview(portalHost)
        }
    }
}
