import XCTest
import UIKit
@testable import AetherUI

final class AetherActionSheetPresentationTests: XCTestCase {
    @MainActor
    func testFloatingCardUsesAlertSurfaceAndSeparatedPillRows() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let source = UIView(frame: CGRect(x: 340, y: 130, width: 44, height: 44))
        window.addSubview(source)
        let root = AetherActionSheetControllerView(theme: .light)
        root.sourceView = source
        root.frame = window.bounds
        root.setGroups([AetherActionSheetItemGroup(items: [
            AetherActionSheetTextItem(title: "Медиатека"),
            AetherActionSheetButtonItem(title: "Только загруженная музыка", action: {}),
            AetherActionSheetButtonItem(title: "Управление плейлистами", action: {})
        ])])
        window.addSubview(root)
        root.layoutIfNeeded()

        let card = try XCTUnwrap(root.subviews.compactMap { $0 as? GlassBackgroundView }.first)
        let group = try XCTUnwrap(descendant(of: AetherActionSheetItemGroupView.self, in: card))
        group.layoutIfNeeded()
        XCTAssertEqual(card.frame.maxX, source.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(card.frame.minY, source.frame.minY, accuracy: 0.5)
        XCTAssertGreaterThan(card.frame.width, 220)
        XCTAssertLessThanOrEqual(card.frame.width, 354)
        XCTAssertEqual(card.glassCornerRadius, 38)
        XCTAssertEqual(group.itemViews.count, 3)
        XCTAssertEqual(group.itemViews[1].frame.height, 48, accuracy: 1)
        XCTAssertEqual(group.itemViews[2].frame.minY - group.itemViews[1].frame.maxY, 8, accuracy: 0.5)
        XCTAssertFalse(group.itemViews[1].hasSeparator)

        let wideWidth = card.frame.width
        root.setGroups([AetherActionSheetItemGroup(items: [
            AetherActionSheetButtonItem(title: "OK", action: {})
        ])])
        root.layoutIfNeeded()
        XCTAssertEqual(card.frame.width, 220, accuracy: 0.5)
        XCTAssertLessThan(card.frame.width, wideWidth)

        source.frame.origin.y = 790
        root.setNeedsLayout()
        root.layoutIfNeeded()
        XCTAssertEqual(card.frame.maxY, source.frame.maxY, accuracy: 0.5)
    }

    @MainActor
    func testSourceIsRestoredAfterReverseTransition() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let source = UIView(frame: CGRect(x: 340, y: 130, width: 44, height: 44))
        source.backgroundColor = .systemBlue
        source.layer.cornerRadius = 22
        source.alpha = 0.73
        window.addSubview(source)
        let root = AetherActionSheetControllerView(theme: .light)
        root.frame = window.bounds
        root.sourceView = source
        root.setGroups([AetherActionSheetItemGroup(items: [
            AetherActionSheetTextItem(title: "Медиатека"),
            AetherActionSheetButtonItem(title: "Загрузить аудиофайл", action: {})
        ])])
        window.addSubview(root)
        root.layoutIfNeeded()

        let finished = expectation(description: "sheet dismissed")
        root.dismiss = { cancelled in
            XCTAssertTrue(cancelled)
            finished.fulfill()
        }
        root.animateIn()
        XCTAssertEqual(source.alpha, 0)
        XCTAssertFalse(source.isUserInteractionEnabled)
        let midTransition = expectation(description: "card expands from source")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            let bloom = root.subviews.compactMap { $0 as? ContextMenuGlassmorphicTransitionView }.first
            XCTAssertNotNil(bloom)
            XCTAssertGreaterThan(bloom?.finalMenuGlassSurfaceView.frame.width ?? 0, source.frame.width)
            XCTAssertLessThan(bloom?.finalMenuGlassSurfaceView.frame.width ?? .greatestFiniteMagnitude, 354)
            midTransition.fulfill()
            root.animateOut(cancelled: true)
        }
        wait(for: [midTransition], timeout: 1)
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(source.alpha, 0.73, accuracy: 0.001)
        XCTAssertTrue(source.isUserInteractionEnabled)
    }

    @MainActor
    func testExpandedMenuRowsRemainInteractive() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let source = UIView(frame: CGRect(x: 340, y: 130, width: 44, height: 44))
        source.backgroundColor = .systemBlue
        window.addSubview(source)
        let root = AetherActionSheetControllerView(theme: .light)
        root.frame = window.bounds
        root.sourceView = source
        root.setGroups([AetherActionSheetItemGroup(items: [
            AetherActionSheetButtonItem(title: "Открыть", action: {})
        ])])
        window.addSubview(root)
        root.layoutIfNeeded()
        root.animateIn()

        let expanded = expectation(description: "menu fully expanded")
        let dismissed = expectation(description: "menu closed")
        root.dismiss = { _ in dismissed.fulfill() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if let group = self.descendant(of: AetherActionSheetItemGroupView.self, in: root),
               let item = group.itemViews.first {
                let point = item.convert(CGPoint(x: item.bounds.midX, y: item.bounds.midY), to: root)
                var hit = root.hitTest(point, with: nil)
                var reachedItem = false
                while let view = hit {
                    if view === item { reachedItem = true; break }
                    hit = view.superview
                }
                XCTAssertTrue(reachedItem)
            } else {
                XCTFail("Action row is missing from the expanded menu")
            }
            expanded.fulfill()
            root.animateOut(cancelled: false)
        }
        wait(for: [expanded, dismissed], timeout: 3)
    }

    @MainActor
    private func descendant<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        for child in view.subviews {
            if let match = child as? T { return match }
            if let match = descendant(of: type, in: child) { return match }
        }
        return nil
    }
}
