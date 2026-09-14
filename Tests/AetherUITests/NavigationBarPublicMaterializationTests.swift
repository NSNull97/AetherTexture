import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class NavigationBarPublicMaterializationTests: XCTestCase {
    private let transition = ContainedViewLayoutTransition.animated(duration: 0.34, curve: .navigationFluidMorph)

    func testCustomControlSnapshotSurvivesRepeatedLayoutAndIsRemovedAtCompletion() throws {
        try requirePublicFallback()
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 104))
        let bar = makeBar(in: host)
        bar.item = NavigationBarItem()
        layout(bar)
        let control = label("Edit")
        let item = NavigationBarItem()
        item.rightBarButtonItems = [UIBarButtonItem(customView: control)]
        bar.withButtonMorphTransition(transition) {
            bar.item = item
            layout(bar, transition: transition)
        }

        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: control))
        let proxy = try XCTUnwrap(control.superview?.subviews.first(where: AetherContentMaterialization.isSnapshotView))
        layout(bar)
        layout(bar)
        XCTAssertTrue(proxy.superview === control.superview)
        XCTAssertFalse(AetherContentMaterialization.isAnimating(view: proxy))

        settle()
        XCTAssertFalse(AetherContentMaterialization.isAnimating(view: control))
        XCTAssertNil(proxy.superview)
        XCTAssertEqual(control.alpha, 1)
        XCTAssertEqual(proxies(in: host).count, 0)
    }

    func testReturningTitleCancelsOldDisappearanceAndPreservesTransformAndInteraction() throws {
        try requirePublicFallback()
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 104))
        let bar = makeBar(in: host)
        let first = label("First")
        let originalTransform = CGAffineTransform(rotationAngle: 0.04)
        first.transform = originalTransform
        first.isUserInteractionEnabled = true
        let firstItem = NavigationBarItem()
        firstItem.titleView = first
        bar.item = firstItem
        layout(bar)

        let second = label("Second")
        let secondItem = NavigationBarItem()
        secondItem.titleView = second
        bar.withButtonMorphTransition(transition) {
            bar.item = secondItem
            layout(bar, transition: transition)
        }
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: first))
        XCTAssertFalse(first.isUserInteractionEnabled)
        bar.withButtonMorphTransition(transition) {
            bar.item = firstItem
            layout(bar, transition: transition)
        }
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: first))
        XCTAssertTrue(first.isUserInteractionEnabled)
        XCTAssertEqual(first.transform, originalTransform)

        settle()
        XCTAssertNotNil(first.superview)
        XCTAssertNil(second.superview)
        XCTAssertEqual(first.alpha, 1)
        XCTAssertEqual(first.transform, originalTransform)
        XCTAssertTrue(first.isUserInteractionEnabled)
        XCTAssertEqual(proxies(in: host).count, 0)
    }

    func testReturningCustomControlSurvivesOldRemovalCompletion() throws {
        try requirePublicFallback()
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 104))
        let bar = makeBar(in: host)
        let first = label("Edit")
        first.isUserInteractionEnabled = true
        let item = NavigationBarItem()
        item.rightBarButtonItems = [UIBarButtonItem(customView: first)]
        bar.item = item
        layout(bar)
        let replacement = NavigationBarItem()
        replacement.rightBarButtonItems = [UIBarButtonItem(customView: label("Done"))]
        bar.withButtonMorphTransition(transition) {
            bar.item = replacement
            layout(bar, transition: transition)
        }
        XCTAssertTrue(AetherContentMaterialization.isAnimating(view: first))
        bar.withButtonMorphTransition(transition) {
            bar.item = item
            layout(bar, transition: transition)
        }
        settle()
        XCTAssertNotNil(first.superview)
        XCTAssertTrue(first.isUserInteractionEnabled)
        XCTAssertEqual(first.transform, .identity)
        XCTAssertEqual(first.alpha, 1)
        XCTAssertEqual(proxies(in: host).count, 0)
    }

    private func requirePublicFallback() throws {
        guard CALayer.blur() == nil else {
            throw XCTSkip("Run with APPSTORE_SAFE to exercise the public materialization renderer")
        }
    }

    private func makeBar(in host: UIView) -> NavigationBarImpl {
        let bar = NavigationBarImpl(presentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme(style: .glass, appearanceStyle: .liquidGlassV1)
        ))
        bar.frame = host.bounds
        host.addSubview(bar)
        bar.buttonLayerHostView = host
        return bar
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.sizeToFit()
        return label
    }

    private func layout(_ bar: NavigationBarImpl, transition: ContainedViewLayoutTransition = .immediate) {
        bar.updateLayout(
            size: CGSize(width: 320, height: 104),
            defaultHeight: 60,
            additionalTopHeight: 0,
            additionalContentHeight: 0,
            additionalBackgroundHeight: 0,
            leftInset: 0,
            rightInset: 0,
            appearsHidden: false,
            isLandscape: false,
            transition: transition
        )
    }

    private func settle() {
        let finished = expectation(description: "Navigation materialization settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finished.fulfill() }
        wait(for: [finished], timeout: 2)
    }

    private func proxies(in view: UIView) -> [UIView] {
        view.subviews.flatMap { child in
            (AetherContentMaterialization.isSnapshotView(child) ? [child] : []) + proxies(in: child)
        }
    }
}
