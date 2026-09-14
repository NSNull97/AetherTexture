import UIKit
import AsyncDisplayKit

/// Controller that manages search activation, results display, and dismissal.
///
/// Port of Telegram's `SearchDisplayController`. Provides a background overlay,
/// a search content view (results), and wires text changes from the search bar
/// to the content.
///
/// Usage:
/// ```swift
/// let searchController = AetherSearchDisplayController(
///     contentController: MySearchResultsController(),
///     cancel: { /* dismiss search */ }
/// )
/// // Activate: add searchController.view to your hierarchy
/// // Wire text: searchController.updateSearchText("query")
/// ```
public final class AetherSearchDisplayController {

    /// The content controller that displays search results.
    public let contentController: AetherSearchContentController

    /// Background view (dimming overlay behind results).
    public let backgroundView: UIView

    /// Whether the controller is being deactivated (prevents re-entrant cancel).
    public var isDeactivating = false

    private let cancel: () -> Void

    public init(contentController: AetherSearchContentController, cancel: @escaping () -> Void) {
        self.contentController = contentController
        self.cancel = cancel

        self.backgroundView = UIView()
        self.backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        self.backgroundView.alpha = 0.0

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        self.backgroundView.addGestureRecognizer(tap)

        self.contentController.cancel = { [weak self] in
            self?.isDeactivating = true
            cancel()
        }
        self.contentController.dismissInput = { [weak self] in
            // Subclass/consumer should resign first responder on the search bar
            self?.onDismissInput?()
        }
    }

    /// Called when the content requests keyboard dismissal without cancelling search.
    public var onDismissInput: (() -> Void)?

    /// Forward search text to the content controller.
    public func updateSearchText(_ text: String) {
        contentController.searchTextUpdated(text: text)
    }

    /// Layout the background and content views within the given bounds.
    public func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let contentFrame = CGRect(
            x: 0,
            y: navigationBarHeight,
            width: layout.size.width,
            height: layout.size.height - navigationBarHeight
        )
        backgroundView.frame = CGRect(origin: .zero, size: layout.size)
        contentController.view.frame = contentFrame
        contentController.containerLayoutUpdated(layout, transition: transition)
    }

    /// Animate the search UI in.
    public func activate(insertIn container: UIView, above: UIView?) {
        backgroundView.layer.removeAllAnimations()
        contentController.view.layer.removeAllAnimations()
        backgroundView.alpha = 0.0
        contentController.view.alpha = 0.0
        contentController.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        if let above {
            container.insertSubview(backgroundView, aboveSubview: above)
        } else {
            container.addSubview(backgroundView)
        }
        container.addSubview(contentController.view)

        let profile = AetherMotion.search.presentation
        UIView.animate(
            withDuration: profile.duration,
            delay: 0.0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.backgroundView.alpha = 1.0
            self.contentController.view.alpha = 1.0
            self.contentController.view.transform = .identity
        }
    }

    /// Animate the search UI out and remove from hierarchy.
    public func deactivate(animated: Bool) {
        isDeactivating = true
        let cleanup = {
            self.backgroundView.removeFromSuperview()
            self.contentController.view.removeFromSuperview()
        }
        if animated {
            let profile = AetherMotion.search.dismissal
            UIView.animate(
                withDuration: profile.duration,
                delay: 0.0,
                usingSpringWithDamping: profile.dampingRatio,
                initialSpringVelocity: profile.initialVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                self.backgroundView.alpha = 0.0
                self.contentController.view.alpha = 0.0
                self.contentController.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            }, completion: { _ in
                cleanup()
                self.contentController.view.alpha = 1.0
                self.contentController.view.transform = .identity
            })
        } else {
            self.backgroundView.alpha = 0.0
            cleanup()
        }
    }

    @objc private func backgroundTapped() {
        cancel()
    }
}

// MARK: - Search Content Controller

/// Base class for search result controllers used with `AetherSearchDisplayController`.
///
/// Subclass and override `searchTextUpdated(text:)` to filter/fetch results.
open class AetherSearchContentController: ASDKViewController<ASDisplayNode> {
    public override init() {
        super.init(node: ASDisplayNode())
    }

    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(node: ASDisplayNode())
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Called when search text changes.
    open func searchTextUpdated(text: String) {
    }

    /// Layout update from the search display controller.
    open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
    }

    /// Set by the display controller — call to dismiss the entire search.
    public var cancel: (() -> Void)?

    /// Set by the display controller — call to just dismiss keyboard.
    public var dismissInput: (() -> Void)?
}
