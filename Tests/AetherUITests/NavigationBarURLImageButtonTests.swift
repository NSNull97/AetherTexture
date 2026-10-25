import XCTest
import UIKit
@testable import AetherUI

/// `UIBarButtonItem(imageURL:)` is the avatar button used by Twitty's root
/// screens. It is hosted inside a glass `GlassControlGroup`; these tests
/// check that the photo is actually drawn there, not only assigned.
final class NavigationBarURLImageButtonTests: XCTestCase {
    override func tearDown() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        super.tearDown()
    }

    func testAvatarButtonStaysLegacyAndDrawsPhotoInsideGlassGroup() throws {
        let (bar, button) = try makeAvatarBar()
        layout(bar)

        assertDrawsPhoto(button)
    }

    func testAvatarPhotoSurvivesPushAndPop() throws {
        let (bar, button) = try makeAvatarBar()
        let rootItem = try XCTUnwrap(bar.item)
        layout(bar)

        let detailItem = NavigationBarItem()
        detailItem.title = "Detail"
        bar.previousItem = .item(rootItem)
        bar.item = detailItem
        layout(bar, transition: .animated(duration: 0.3, curve: .easeInOut))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        bar.previousItem = nil
        bar.item = rootItem
        layout(bar, transition: .animated(duration: 0.3, curve: .easeInOut))
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        layout(bar)

        XCTAssertTrue(button.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(Self.hasGlassGroupAncestor(button))
        assertDrawsPhoto(button)
    }

    func testHighlightDoesNotDimPhoto() throws {
        let (bar, button) = try makeAvatarBar()
        layout(bar)

        button.isHighlighted = true
        assertDrawsPhoto(button)
        button.isHighlighted = false
    }

    // MARK: - Helpers

    private func makeAvatarBar() throws -> (NavigationBarImpl, UIButton) {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = NavigationBarImpl(
            presentationData: NavigationBarPresentationData(
                theme: NavigationBarTheme(style: .glass, appearanceStyle: .liquidGlassV1)
            )
        )
        bar.frame = hostView.bounds
        hostView.addSubview(bar)
        bar.buttonLayerHostView = hostView

        let photo = UIGraphicsImageRenderer(size: CGSize(width: 120.0, height: 120.0)).image { context in
            UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).setFill()
            context.fill(CGRect(x: 0.0, y: 0.0, width: 120.0, height: 120.0))
        }.withRenderingMode(.alwaysOriginal)
        let item = UIBarButtonItem(imageURL: nil, placeholderImage: photo, target: nil, action: nil)
        let button = try XCTUnwrap(item.customView as? UIButton)

        let navigationItem = NavigationBarItem()
        navigationItem.leftBarButtonItem = item
        bar.item = navigationItem
        return (bar, button)
    }

    private func layout(_ bar: NavigationBarImpl, transition: ContainedViewLayoutTransition = .immediate) {
        bar.updateLayout(
            size: CGSize(width: 320.0, height: 104.0),
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: transition
        )
    }

    private func assertDrawsPhoto(_ button: UIButton, file: StaticString = #filePath, line: UInt = #line) {
        button.layoutIfNeeded()

        // A configuration-based UIButton ignores legacy images and resets
        // the corner radius during layout; that was the gray-plate bug.
        XCTAssertNil(button.configuration, file: file, line: line)
        XCTAssertNil(button.configurationUpdateHandler, file: file, line: line)
        XCTAssertEqual(button.layer.cornerRadius, 19.0, accuracy: 0.5, file: file, line: line)
        XCTAssertTrue(button.imageView?.superview === button, "Image view is not installed", file: file, line: line)

        let pixel = Self.centerPixel(of: button)
        XCTAssertGreaterThan(pixel.red, 0.8, "Avatar center is \(pixel)", file: file, line: line)
        XCTAssertLessThan(pixel.green, 0.3, "Avatar center is \(pixel)", file: file, line: line)
        XCTAssertLessThan(pixel.blue, 0.3, "Avatar center is \(pixel)", file: file, line: line)
    }

    private static func hasGlassGroupAncestor(_ view: UIView) -> Bool {
        var current = view.superview
        while let candidate = current {
            if candidate is GlassControlGroup { return true }
            current = candidate.superview
        }
        return false
    }

    private static func centerPixel(of view: UIView) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (0, 0, 0)
        }
        context.translateBy(x: -view.bounds.midX, y: -view.bounds.midY)
        view.layer.render(in: context)
        return (CGFloat(data[0]) / 255.0, CGFloat(data[1]) / 255.0, CGFloat(data[2]) / 255.0)
    }
}
