import UIKit
import AsyncDisplayKit

public final class AetherWindowRootViewController: ASDKViewController<ASDisplayNode> {
    public var transitionToSize: ((CGSize, TimeInterval, UIInterfaceOrientation) -> Void)?
    public var voiceOverStatusChanged: ((Bool) -> Void)?
    public var environmentLayoutChanged: (() -> Void)?

    private var voiceOverObserver: NSObjectProtocol?
    private var statusBarRequest = AetherStatusBarRequest()
    private let windowHostView: AetherWindowHostView

    public var orientations: UIInterfaceOrientationMask = {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }() {
        didSet {
            guard oldValue != orientations else { return }
            aetherAssertMainThread()
            if #available(iOS 16.0, *) {
                view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
                setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    public var gestureEdges: UIRectEdge = [] {
        didSet {
            guard oldValue != gestureEdges else { return }
            aetherAssertMainThread()
            setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }
    }

    public var prefersOnScreenNavigationHidden: Bool = false {
        didSet {
            guard oldValue != prefersOnScreenNavigationHidden else { return }
            aetherAssertMainThread()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    public var hostView: AetherWindowHostView {
        windowHostView
    }

    public override init() {
        let windowHostView = AetherWindowHostView()
        self.windowHostView = windowHostView
        super.init(node: ASDisplayNode(viewBlock: { windowHostView }))
        extendedLayoutIncludesOpaqueBars = true
        voiceOverObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.voiceOverStatusChanged?(UIAccessibility.isVoiceOverRunning)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let voiceOverObserver {
            NotificationCenter.default.removeObserver(voiceOverObserver)
        }
    }

    public func updateStatusBar(
        style: UIStatusBarStyle,
        hidden: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let request = AetherStatusBarRequest(style: style, isHidden: hidden)
        guard statusBarRequest != request else { return }
        statusBarRequest = request
        switch transition {
        case .immediate:
            setNeedsStatusBarAppearanceUpdate()
        case .animated:
            transition.animateView { [weak self] in
                self?.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    public func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            return orientation
        }
        if view.bounds.width > view.bounds.height {
            return .landscapeLeft
        }
        return .portrait
    }

    public override func loadView() {
        super.loadView()
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        statusBarRequest.style
    }

    public override var prefersStatusBarHidden: Bool {
        statusBarRequest.isHidden
    }

    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientations
    }

    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        gestureEdges
    }

    public override var prefersHomeIndicatorAutoHidden: Bool {
        prefersOnScreenNavigationHidden
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
            || previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
            || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
            || previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else {
            return
        }
        environmentLayoutChanged?()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        environmentLayoutChanged?()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let orientation = currentInterfaceOrientation()
        UIView.performWithoutAnimation {
            self.transitionToSize?(size, coordinator.transitionDuration, orientation)
        }
    }
}
