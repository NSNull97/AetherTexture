import UIKit
import XCTest
@testable import AetherUI

@MainActor
final class AetherModalNavigationContentTests: XCTestCase {
    func testPushAndPopFollowTopScreenScrollAndFooter() {
        let root = ModalTestScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()

        XCTAssertTrue(modal.primaryScrollView === root.scrollView)
        XCTAssertTrue(modal.footerView === root.footer)
        XCTAssertEqual(modal.footerHeight, 88)

        let detail = ModalTestScreen()
        detail.drawsFooterEdge = false
        root.push(detail, animated: false)
        XCTAssertTrue(modal.primaryScrollView === detail.scrollView)
        XCTAssertTrue(modal.footerView === detail.footer)
        XCTAssertFalse(modal.footerEdgeEffectEnabled)
        XCTAssertFalse(root.footer.isDescendant(of: modal.view))

        let plain = ModalTestPlainScreen()
        detail.push(plain, animated: false)
        XCTAssertTrue(modal.primaryScrollView === plain.scrollView)
        XCTAssertNil(modal.footerView)
        XCTAssertEqual(modal.footerHeight, 0)
        XCTAssertTrue(modal.footerEdgeEffectEnabled)

        _ = modal.popViewController(animated: false)
        XCTAssertTrue(modal.primaryScrollView === detail.scrollView)
        XCTAssertTrue(modal.footerView === detail.footer)
        XCTAssertFalse(modal.footerEdgeEffectEnabled)

        _ = modal.popViewController(animated: false)
        XCTAssertTrue(modal.primaryScrollView === root.scrollView)
        XCTAssertTrue(modal.footerView === root.footer)
        XCTAssertTrue(modal.footerEdgeEffectEnabled)
    }

    func testAnimatedPushAndPopReleaseInactiveScreenViews() async {
        let root = ModalTestPlainScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        modal.view.layoutIfNeeded()

        let detail = ModalTestPlainScreen()
        modal.pushViewController(detail, animated: true)
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertTrue(modal.topViewController === detail)
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertNil(root.view.superview)
        XCTAssertNotNil(detail.view.superview)

        _ = modal.popViewController(animated: true)
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertTrue(modal.topViewController === root)
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertNil(detail.view.superview)
        XCTAssertNotNil(root.view.superview)
    }

    func testAnimatedModalNavigationKeepsFooterInSheetCoordinates() async {
        let root = ModalTestScreen()
        let modal = AetherModalNavigationController(
            rootViewController: root,
            config: .init(detents: [.stage2], initialDetent: .stage2)
        )
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        modal.view.layoutIfNeeded()

        let standalone = AetherNavigationController(rootViewController: ModalTestPlainScreen())
        standalone.loadViewIfNeeded()
        XCTAssertEqual(modal.internalNavigationController.view.backgroundColor,
                       standalone.view.backgroundColor)

        let footerHost = root.footer.superview
        let detail = ModalTestPlainScreen()
        root.push(detail, animated: true)
        XCTAssertTrue(modal.internalNavigationController.isTransitioning)
        XCTAssertTrue(modal.footerView === root.footer)
        XCTAssertEqual(modal.footerHeight, 88)
        XCTAssertTrue(root.footer.superview === footerHost)
        XCTAssertFalse(root.footer.isDescendant(of: root.view))
        XCTAssertEqual(root.footer.alpha, 1)
        XCTAssertEqual(root.footer.convert(root.footer.bounds, to: modal.view).maxY, modal.view.bounds.maxY, accuracy: 1)

        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertNil(modal.footerView)
        XCTAssertTrue(modal.primaryScrollView === detail.scrollView)
        XCTAssertNil(root.footer.superview)

        detail.pop(animated: true)
        XCTAssertTrue(modal.internalNavigationController.isTransitioning)
        XCTAssertNil(modal.footerView)
        XCTAssertFalse(root.footer.isDescendant(of: root.view))
        XCTAssertTrue(root.footer.isDescendant(of: modal.view))
        XCTAssertEqual(root.footer.convert(root.footer.bounds, to: modal.view).maxY, modal.view.bounds.maxY, accuracy: 1)
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertTrue(modal.footerView === root.footer)
        XCTAssertEqual(root.footer.alpha, 1)
        XCTAssertFalse(root.footer.superview === root.view)
    }

    func testPushAndPopDoNotStretchAfterDroppedDisplayFrames() {
        let root = ModalTestPlainScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        modal.view.layoutIfNeeded()

        let detail = ModalTestPlainScreen()
        modal.pushViewController(detail, animated: true)
        XCTAssertTrue(modal.internalNavigationController.isTransitioning)
        let pushStart = CACurrentMediaTime()
        Thread.sleep(forTimeInterval: 0.36)
        while modal.internalNavigationController.isTransitioning,
              CACurrentMediaTime() - pushStart < 0.8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertLessThan(CACurrentMediaTime() - pushStart, 0.58)

        _ = modal.popViewController(animated: true)
        XCTAssertTrue(modal.internalNavigationController.isTransitioning)
        let popStart = CACurrentMediaTime()
        Thread.sleep(forTimeInterval: 0.36)
        while modal.internalNavigationController.isTransitioning,
              CACurrentMediaTime() - popStart < 0.8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertLessThan(CACurrentMediaTime() - popStart, 0.58)
    }

    func testSearchAccessoryKeepsOutgoingScreenTopInsetDuringPop() {
        let root = ModalTestPlainScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = modal
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        modal.loadViewIfNeeded()
        modal.view.layoutIfNeeded()

        let detail = ModalTestPlainScreen()
        let search = AetherSearchController()
        search.prefersNavigationBarPlacement = true
        detail.searchController = search
        modal.pushViewController(detail, animated: false)
        modal.view.layoutIfNeeded()
        let settledHeight = detail.cleanNavigationHeight
        XCTAssertGreaterThan(settledHeight, root.cleanNavigationHeight)

        _ = modal.popViewController(animated: true)
        XCTAssertEqual(detail.cleanNavigationHeight, settledHeight, accuracy: 1)
    }

    func testPlainRootPreservesManuallyConfiguredFooter() {
        let root = ModalTestPlainScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.contentConfigurationMode = .manual
        modal.loadViewIfNeeded()
        let footer = UIView()
        modal.footerView = footer
        modal.footerHeight = 72
        modal.primaryScrollView = root.scrollView

        let detail = ModalTestPlainScreen()
        root.push(detail, animated: false)
        XCTAssertTrue(modal.footerView === footer)
        XCTAssertEqual(modal.footerHeight, 72)
        XCTAssertTrue(modal.primaryScrollView === root.scrollView)

        detail.pop(animated: false)
        XCTAssertTrue(modal.footerView === footer)
        XCTAssertEqual(modal.footerHeight, 72)
    }

    func testCompactViewportAndMaterialTrackActualBoundsWithoutRasterization() {
        let root = ModalTestScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        for size in [CGSize(width: 374, height: 360), CGSize(width: 390, height: 750), CGSize(width: 374, height: 410)] {
            modal.view.frame = CGRect(origin: .zero, size: size)
            modal.view.setNeedsLayout()
            modal.view.layoutIfNeeded()
            XCTAssertEqual(modal.contentView.bounds.size, size)
            XCTAssertEqual(modal.internalNavigationController.view.bounds.size, size)
            XCTAssertEqual(modal.modalSurfaceForTesting?.bounds.size, size)
            XCTAssertEqual(modal.modalSurfaceForTesting?.transform, .identity)
            XCTAssertTrue(modal.contentView.superview === modal.view)
            XCTAssertEqual(root.footer.convert(root.footer.bounds, to: modal.view).maxY, size.height, accuracy: 0.5)
        }
        modal.beginInteractiveResize()
        XCTAssertFalse(modal.contentView.layer.shouldRasterize)
        modal.endInteractiveResize()
        XCTAssertFalse(modal.contentView.layer.shouldRasterize)
    }

    func testAutomaticConfigurationWorksWhenRootDoesNotAdoptModalContent() {
        let root = ModalTestPlainScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        XCTAssertTrue(modal.primaryScrollView === root.scrollView)
        let detail = ModalTestScreen()
        modal.pushViewController(detail, animated: false)
        XCTAssertTrue(modal.footerView === detail.footer)
        XCTAssertTrue(modal.primaryScrollView === detail.scrollView)
        modal.setViewControllers([], animated: false)
        XCTAssertNil(modal.footerView)
        XCTAssertNil(modal.primaryScrollView)
        XCTAssertNil(detail.footer.superview)
    }

    func testCancelledInteractivePopKeepsFooterOwnedBySheetAtCompactHeight() async throws {
        let root = ModalTestScreen()
        let detail = ModalTestScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 8, y: 380, width: 374, height: 420)
        modal.view.layoutIfNeeded()
        modal.pushViewController(detail, animated: false)
        modal.view.layoutIfNeeded()
        let host = try XCTUnwrap(detail.footer.superview)
        let container = try XCTUnwrap(detail.view.superview as? NavigationContainer)
        let pan = ModalTestPanGesture()
        pan.testTranslation = CGPoint(x: 100, y: 0)
        pan.testState = .changed
        container.perform(NSSelectorFromString("panGesture:"), with: pan)
        XCTAssertTrue(modal.internalNavigationController.isTransitioning)
        XCTAssertTrue(detail.footer.superview === host)
        XCTAssertFalse(detail.footer.isDescendant(of: detail.view))
        XCTAssertEqual(detail.footer.convert(detail.footer.bounds, to: modal.view).maxY, 420, accuracy: 0.5)
        pan.testState = .cancelled
        container.perform(NSSelectorFromString("panGesture:"), with: pan)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertTrue(modal.topViewController === detail)
        XCTAssertTrue(modal.footerView === detail.footer)
        XCTAssertTrue(detail.footer.superview === host)
        XCTAssertNil(root.footer.superview)
        XCTAssertEqual(detail.footer.convert(detail.footer.bounds, to: modal.view).maxY, 420, accuracy: 0.5)
        XCTAssertEqual(detail.footer.convert(detail.footer.bounds, to: modal.view).minX, 0, accuracy: 0.5)
    }

    func testSharedFooterRemainsAttachedAfterPushAndCancelledPop() async throws {
        let root = ModalTestScreen()
        let detail = ModalTestScreen(footer: root.footer)
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 374, height: 420)
        modal.view.layoutIfNeeded()
        let host = try XCTUnwrap(root.footer.superview)
        modal.pushViewController(detail, animated: true)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(detail.footer.superview === host)
        let container = try XCTUnwrap(detail.view.superview as? NavigationContainer)
        let pan = ModalTestPanGesture()
        pan.testTranslation = CGPoint(x: 80, y: 0)
        pan.testState = .changed
        container.perform(NSSelectorFromString("panGesture:"), with: pan)
        pan.testState = .cancelled
        container.perform(NSSelectorFromString("panGesture:"), with: pan)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(modal.footerView === detail.footer)
        XCTAssertTrue(detail.footer.superview === host)
        XCTAssertEqual(detail.footer.convert(detail.footer.bounds, to: modal.view).maxY, 420, accuracy: 0.5)
    }

    func testFooterReservationBelongsToEachScreenDuringTransition() {
        let root = ModalTestScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 374, height: 420)
        modal.view.layoutIfNeeded()
        let detail = ModalTestPlainScreen()
        modal.pushViewController(detail, animated: true)
        XCTAssertEqual(modal.additionalSafeAreaInsets.bottom, 0, accuracy: 0.5)
        let layout = ContainerViewLayout(size: modal.view.bounds.size)
        let source = modal.internalNavigationController.layoutForController?(root, layout)
        let target = modal.internalNavigationController.layoutForController?(detail, layout)
        XCTAssertEqual(source?.additionalInsets.bottom ?? -1, 88, accuracy: 0.5)
        XCTAssertEqual(target?.additionalInsets.bottom ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(root.additionalSafeAreaInsets.bottom, 88, accuracy: 0.5)
        XCTAssertEqual(detail.additionalSafeAreaInsets.bottom, 0, accuracy: 0.5)
    }

    func testCornerPolicyMatchesCompactAndExpandedGeometry() {
        let modal = AetherModalController(config: .init(topCornerRadius: 30))
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 374, height: 420)
        modal.applyDetentProgress(0)
        XCTAssertEqual(modal.resolvedCornerRadii().top, 30)
        XCTAssertEqual(modal.resolvedCornerRadii().bottom, 30)
        modal.applyDetentProgress(0.5)
        XCTAssertEqual(modal.resolvedCornerRadii().bottom, 15)
        modal.applyDetentProgress(1)
        XCTAssertEqual(modal.resolvedCornerRadii().bottom, 0)
        let custom = AetherModalController(config: .init(bottomCornerRadiusStage1: 24, bottomCornerRadiusStage2: 12))
        custom.loadViewIfNeeded()
        custom.view.frame = modal.view.frame
        custom.applyDetentProgress(1)
        XCTAssertEqual(custom.resolvedCornerRadii().bottom, 12)
    }

    func testChangingFooterConfigurationModeReconcilesInsetsImmediately() {
        let root = ModalTestScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 374, height: 420)
        modal.view.layoutIfNeeded()
        let layout = ContainerViewLayout(size: modal.view.bounds.size)

        modal.contentConfigurationMode = .manual
        XCTAssertEqual(modal.additionalSafeAreaInsets.bottom, 88, accuracy: 0.5)
        XCTAssertEqual(modal.internalNavigationController.layoutForController?(root, layout).additionalInsets.bottom, 0)
        XCTAssertTrue(modal.footerView === root.footer)

        modal.contentConfigurationMode = .perScreen
        XCTAssertEqual(modal.additionalSafeAreaInsets.bottom, 0, accuracy: 0.5)
        XCTAssertEqual(modal.internalNavigationController.layoutForController?(root, layout).additionalInsets.bottom, 88)
        XCTAssertTrue(modal.footerView === root.footer)
    }

    func testChangingFooterModeDuringPushKeepsOwnershipUntilCompletion() async {
        let root = ModalTestScreen()
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 374, height: 420)
        modal.view.layoutIfNeeded()
        let detail = ModalTestScreen()
        modal.pushViewController(detail, animated: true)
        modal.contentConfigurationMode = .manual
        let layout = ContainerViewLayout(size: modal.view.bounds.size)
        XCTAssertEqual(modal.additionalSafeAreaInsets.bottom, 0, accuracy: 0.5)
        XCTAssertEqual(modal.internalNavigationController.layoutForController?(detail, layout).additionalInsets.bottom, 88)

        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(modal.internalNavigationController.isTransitioning)
        XCTAssertEqual(modal.additionalSafeAreaInsets.bottom, 88, accuracy: 0.5)
        XCTAssertEqual(modal.internalNavigationController.layoutForController?(detail, layout).additionalInsets.bottom, 0)
        XCTAssertTrue(modal.footerView === detail.footer)
    }

    func testKeyboardHidingWithoutPrimaryScrollDoesNotLeakInsetToNextScreen() {
        let modal = AetherModalController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = modal
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        modal.view.layoutIfNeeded()
        let source = UIScrollView()
        source.contentInset.bottom = 7
        modal.primaryScrollView = source
        let keyboardInWindow = CGRect(x: 0, y: window.bounds.height - 300, width: window.bounds.width, height: 300)
        let coordinateSpace = window.windowScene?.screen.coordinateSpace ?? UIScreen.main.coordinateSpace
        let keyboardOnScreen = window.convert(keyboardInWindow, to: coordinateSpace)
        NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
            UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboardOnScreen),
            UIResponder.keyboardAnimationDurationUserInfoKey: 0.0
        ])
        XCTAssertEqual(source.contentInset.bottom, 307, accuracy: 0.5)
        modal.primaryScrollView = nil
        XCTAssertEqual(source.contentInset.bottom, 7, accuracy: 0.5)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil, userInfo: [
            UIResponder.keyboardAnimationDurationUserInfoKey: 0.0
        ])
        let target = UIScrollView()
        target.contentInset.bottom = 11
        modal.primaryScrollView = target
        XCTAssertEqual(target.contentInset.bottom, 11, accuracy: 0.5)
    }


}

@MainActor
private final class ModalTestScreen: AetherViewController, AetherModalContent {
    let scrollView = UIScrollView()
    let footer: UIView

    init(footer: UIView = UIView()) {
        self.footer = footer
        super.init(navigationBarPresentationData: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var drawsFooterEdge = true

    var modalFooterView: UIView? { footer }
    var modalFooterHeight: CGFloat { 88 }
    var modalFooterEdgeEffectEnabled: Bool { drawsFooterEdge }
    var modalPrimaryScrollView: UIScrollView? { scrollView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(scrollView)
    }
}

@MainActor
private final class ModalTestPlainScreen: AetherViewController {
    let scrollView = UIScrollView()
    override var primaryScrollViewForChrome: UIScrollView? { scrollView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(scrollView)
    }
}

@MainActor
private final class ModalTestPanGesture: UIPanGestureRecognizer {
    var testState: UIGestureRecognizer.State = .possible
    var testTranslation: CGPoint = .zero
    override var state: UIGestureRecognizer.State {
        get { testState }
        set { testState = newValue }
    }
    override func translation(in view: UIView?) -> CGPoint { testTranslation }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}
