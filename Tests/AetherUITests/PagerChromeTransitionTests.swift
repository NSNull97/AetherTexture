import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class PagerChromeTransitionTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    func testAnimatedSelectionKeepsOutgoingEdgeUntilScrollingFinishes() throws {
        let outgoing = PagerChromeContentController()
        let incoming = UIViewController()
        let pager = makePager(controllers: [outgoing, incoming])
        let scrollView = pager.backingScrollViewForTesting
        let bar = try XCTUnwrap(pager.navigationBarView as? NavigationBarImpl)
        let effect = try XCTUnwrap(bar.debugEdgeEffectView)
        var selections: [Int] = []
        pager.selectedIndexChanged = { selections.append($0) }

        pager.setSelectedIndex(1, animated: true)

        XCTAssertEqual(pager.selectedIndex, 1)
        XCTAssertEqual(selections, [1])
        XCTAssertTrue(sourceController(of: pager) === outgoing)
        XCTAssertEqual(pager.resolvedNavigationBarScrollEdgeAlpha, 1.0)
        XCTAssertEqual(effect.alpha, 1.0)

        scrollView.setContentOffset(CGPoint(x: 120, y: 0), animated: false)
        updateLayout(of: pager)
        XCTAssertEqual(scrollView.contentOffset.x, 120, accuracy: 0.001)
        XCTAssertTrue(sourceController(of: pager) === outgoing)
        XCTAssertEqual(pager.resolvedNavigationBarScrollEdgeAlpha, 1.0)
        XCTAssertEqual(effect.alpha, 1.0)

        finishAnimation(of: pager, at: 1)

        XCTAssertTrue(sourceController(of: pager) === incoming)
        XCTAssertEqual(pager.resolvedNavigationBarScrollEdgeAlpha, 0.0)
        XCTAssertEqual(effect.alpha, 0.0, "The deferred source change must rebind the shared bar observer")
        XCTAssertEqual(selections, [1], "Settling chrome must not repeat public selection callbacks")
    }

    func testRepeatedAnimatedSelectionIgnoresEarlierDestinationCompletion() {
        let outgoing = PagerChromeContentController()
        let incoming = UIViewController()
        let pager = makePager(controllers: [outgoing, UIViewController(), incoming])

        pager.setSelectedIndex(1, animated: true)
        pager.setSelectedIndex(2, animated: true)
        finishAnimation(of: pager, at: 1)

        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertTrue(sourceController(of: pager) === outgoing)
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset.x, 320, accuracy: 0.001)

        finishAnimation(of: pager, at: 2)

        XCTAssertTrue(sourceController(of: pager) === incoming)
        XCTAssertEqual(pager.resolvedNavigationBarScrollEdgeAlpha, 0.0)
    }

    func testDragInterruptingAnimationCommitsChromeAtAlreadySelectedDestination() {
        let outgoing = PagerChromeContentController()
        let incoming = UIViewController()
        let pager = makePager(controllers: [outgoing, incoming])
        let scrollView = pager.backingScrollViewForTesting

        pager.setSelectedIndex(1, animated: true)
        pager.scrollViewWillBeginDragging(scrollView)
        finishAnimation(of: pager, at: 1)
        XCTAssertTrue(sourceController(of: pager) === outgoing, "An interrupted animation cannot commit chrome")

        pager.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        XCTAssertEqual(pager.selectedIndex, 1)
        XCTAssertTrue(sourceController(of: pager) === incoming)
    }

    func testRejectedDragAfterInterruptedAnimationRestoresSelectedPagesChrome() {
        let outgoing = PagerChromeContentController()
        let selected = UIViewController()
        let pager = makePager(controllers: [outgoing, selected, UIViewController()])
        let scrollView = pager.backingScrollViewForTesting
        pager.selectedIndexShouldChange = { _, commit in commit(false) }

        pager.setSelectedIndex(1, animated: true)
        pager.scrollViewWillBeginDragging(scrollView)
        scrollView.setContentOffset(CGPoint(x: 640, y: 0), animated: false)
        pager.scrollViewDidEndDecelerating(scrollView)

        XCTAssertEqual(pager.selectedIndex, 1)
        XCTAssertEqual(scrollView.contentOffset.x, 320, accuracy: 0.001)
        XCTAssertTrue(sourceController(of: pager) === selected)
    }

    func testImmediateRepeatedSelectionSettlesPendingChromeAndDetachesDistantSource() {
        let outgoing = PagerChromeContentController()
        let incoming = UIViewController()
        let pager = makePager(controllers: [
            outgoing, UIViewController(), UIViewController(), UIViewController(), incoming
        ])

        pager.setSelectedIndex(4, animated: true)
        XCTAssertTrue(sourceController(of: pager) === outgoing)
        XCTAssertTrue(outgoing.parent === pager, "The outgoing source must stay hosted during the transition")

        pager.setSelectedIndex(4, animated: false)

        XCTAssertTrue(sourceController(of: pager) === incoming)
        XCTAssertNil(outgoing.parent)
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset.x, 1_280, accuracy: 0.001)
    }

    func testAnimatedSelectionWithoutLoadedContentCommitsChromeImmediately() {
        let outgoing = UIViewController()
        let incoming = UIViewController()
        let pager = AetherPageViewController(pages: [
            .init(title: "First", viewController: outgoing),
            .init(title: "Second", viewController: incoming)
        ])

        pager.setSelectedIndex(1, animated: true)

        XCTAssertFalse(pager.isViewLoaded)
        XCTAssertTrue(sourceController(of: pager) === incoming)
    }

    func testAnimatedSelectionWithDetachedContentCommitsChromeImmediately() {
        let incoming = UIViewController()
        let pager = makePager(controllers: [PagerChromeContentController(), incoming])
        windows[0].rootViewController = nil

        pager.setSelectedIndex(1, animated: true)

        XCTAssertTrue(sourceController(of: pager) === incoming)
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset.x, 320, accuracy: 0.001)
    }

    func testSelectionWithAnimationsDisabledCommitsChromeImmediately() {
        let incoming = UIViewController()
        let pager = makePager(controllers: [PagerChromeContentController(), incoming])

        UIView.performWithoutAnimation {
            pager.setSelectedIndex(1, animated: true)
        }

        XCTAssertTrue(sourceController(of: pager) === incoming)
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset.x, 320, accuracy: 0.001)
    }

    func testDisappearingDuringAnimationSettlesChromeBeforeReappearance() {
        let outgoing = PagerChromeContentController()
        let incoming = UIViewController()
        let pager = makePager(controllers: [outgoing, incoming])

        pager.setSelectedIndex(1, animated: true)
        pager.viewWillDisappear(true)
        XCTAssertTrue(sourceController(of: pager) === outgoing)
        pager.viewDidDisappear(true)

        XCTAssertTrue(sourceController(of: pager) === incoming)
        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset.x, 320, accuracy: 0.001)
    }

    func testResizingDuringAnimationSettlesInNewPageCoordinates() {
        let outgoing = PagerChromeContentController()
        let incoming = UIViewController()
        let pager = makePager(controllers: [outgoing, incoming])

        pager.setSelectedIndex(1, animated: true)
        updateLayout(of: pager, width: 480)

        XCTAssertEqual(pager.backingScrollViewForTesting.contentOffset.x, 480, accuracy: 0.001)
        XCTAssertTrue(sourceController(of: pager) === incoming)
    }

    private func makePager(controllers: [UIViewController]) -> AetherPageViewController {
        let data = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let pager = AetherPageViewController(
            pages: controllers.enumerated().map { index, controller in
                .init(title: "Page \(index)", viewController: controller)
            },
            installViewPagerAsTopBarAccessory: false,
            navigationBarPresentationData: data
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.rootViewController = pager
        window.isHidden = false
        windows.append(window)
        pager.loadViewIfNeeded()
        updateLayout(of: pager)
        pager.view.layoutIfNeeded()
        return pager
    }

    private func updateLayout(of pager: AetherPageViewController, width: CGFloat = 320) {
        pager.view.frame = CGRect(x: 0, y: 0, width: width, height: 640)
        pager.containerLayoutUpdated(
            ContainerViewLayout(size: pager.view.bounds.size, safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )
    }

    private func sourceController(of pager: AetherPageViewController) -> UIViewController? {
        AetherChromeScrollSourceResolver.resolve(from: pager)?.controllerPath.last
    }

    private func finishAnimation(of pager: AetherPageViewController, at index: Int) {
        let scrollView = pager.backingScrollViewForTesting
        scrollView.setContentOffset(
            CGPoint(x: scrollView.bounds.width * CGFloat(index), y: 0),
            animated: false
        )
        pager.scrollViewDidEndScrollingAnimation(scrollView)
    }
}

@MainActor
private final class PagerChromeContentController: AetherViewController {
    let scrollView = UIScrollView()

    override var primaryScrollViewForChrome: UIScrollView? { scrollView }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset.y = 32
        view.addSubview(scrollView)
    }
}
