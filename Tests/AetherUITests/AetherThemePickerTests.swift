import XCTest
import UIKit
import AsyncDisplayKit
@testable import AetherUI

@MainActor
final class AetherThemePickerTests: XCTestCase {
    func testThemeCasesAreDistinctAndCodable() throws {
        let cases = AetherThemePickerView.Theme.allCases
        XCTAssertEqual(cases, [.light, .dark, .system])
        XCTAssertTrue(cases.allSatisfy { !$0.title.isEmpty })
        XCTAssertEqual(cases.map(\.displayName), ["Light", "Dark", "System"])

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for theme in cases {
            let encoded = try encoder.encode(theme)
            XCTAssertEqual(try decoder.decode(AetherThemePickerView.Theme.self, from: encoded), theme)
        }
    }

    func testPickerStartsWithRequestedThemeAndPublishesSelection() {
        let picker = AetherThemePickerView(theme: .light)
        XCTAssertEqual(picker.theme, .light)

        var changes: [AetherThemePickerView.Theme] = []
        picker.themeChanged = { changes.append($0) }

        picker.setTheme(.dark, animated: false)

        XCTAssertEqual(picker.theme, .dark)
        XCTAssertEqual(changes, [.dark])
    }

    func testPickerAutomaticallyFitsContentAndHonorsExplicitMinimumHeight() {
        let picker = AetherThemePickerView()
        let automaticSize = picker.intrinsicContentSize
        XCTAssertEqual(automaticSize.width, 320)
        XCTAssertGreaterThan(automaticSize.height, 0)
        XCTAssertLessThan(automaticSize.height, 278, "Automatic fitting should remove the unused bottom space")
        XCTAssertEqual(picker.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)), automaticSize)

        picker.preferredHeight = 304.0

        XCTAssertEqual(picker.intrinsicContentSize, CGSize(width: 320.0, height: 304.0))
    }

    func testPickerCanBeHostedByAlertWithoutLosingSelectionCallback() {
        let picker = AetherThemePickerView(theme: .system)
        let alert = AetherAlertController(
            title: nil,
            message: nil,
            actions: [],
            customContentView: picker
        )
        XCTAssertTrue(alert.customContentView === picker)

        var selected: AetherThemePickerView.Theme?
        picker.themeChanged = { selected = $0 }
        picker.setTheme(.dark, animated: false)

        XCTAssertEqual(selected, .dark)
        XCTAssertEqual(picker.intrinsicContentSize, picker.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)))
    }

    func testPickerSelectionSendsValueChangedOncePerActualChange() {
        let picker = AetherThemePickerView()
        var eventCount = 0
        picker.addAction(UIAction { _ in eventCount += 1 }, for: .valueChanged)

        picker.setTheme(.light, animated: false)
        picker.setTheme(.light, animated: false)
        picker.setTheme(.system, animated: false)

        XCTAssertEqual(eventCount, 2)
    }

    func testThemePickerModalUsesContentSizedBottomSheetAndAetherDetent() {
        let modal = AetherThemePickerModalController(theme: .dark)

        XCTAssertEqual(modal.theme, .dark)
        XCTAssertNil(modal.config.fixedSize)
        XCTAssertTrue(modal.config.sizesToContent)
        XCTAssertEqual(modal.config.detents, [.stage1])
        XCTAssertFalse(modal.config.showsGrabber)
        XCTAssertEqual(modal.config.sideInset, 8)
        XCTAssertEqual(modal.config.bottomInsetStage1, 8)
        XCTAssertEqual(modal.config.bottomInsetStage2, 8)
        XCTAssertEqual(modal.config.topCornerRadius, 26)
        XCTAssertEqual(modal.config.bottomCornerRadiusStage1, modal.config.topCornerRadius)
        XCTAssertEqual(modal.config.bottomCornerRadiusStage2, modal.config.topCornerRadius)
        XCTAssertTrue(modal.config.bottomCornersFollowContainer)

        modal.loadViewIfNeeded()
        XCTAssertTrue(modal.pickerView.isDescendant(of: modal.contentView))
    }

    func testModalOwnsAdaptiveOutlineWithoutASecondFixedCardClip() throws {
        let standalone = AetherThemePickerView(theme: .light)
        let standaloneCard = try XCTUnwrap(standalone.subviews.first)
        XCTAssertEqual(standaloneCard.layer.cornerRadius, 26)
        XCTAssertTrue(standaloneCard.clipsToBounds)

        let modal = AetherThemePickerModalController(theme: .light)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 8, y: 500, width: 386, height: 330)
        modal.view.setNeedsLayout()
        modal.view.layoutIfNeeded()
        let hostedCard = try XCTUnwrap(modal.pickerView.subviews.first)
        XCTAssertEqual(hostedCard.layer.cornerRadius, 0)
        XCTAssertFalse(hostedCard.clipsToBounds, "The modal must be the only outer surface clip")

        if #available(iOS 26.0, *) {
            XCTAssertEqual(modal.view.cornerConfiguration, .uniformEdges(
                topRadius: .fixed(26),
                bottomRadius: .containerConcentric(minimum: 26)
            ))
            XCTAssertTrue(modal.view.clipsToBounds)
        } else {
            XCTAssertEqual(modal.view.layer.cornerRadius, 26)
        }
    }

    func testThemePickerModalUsesEightPointSideAndBottomMargins() throws {
        let modal = AetherThemePickerModalController(theme: .dark)
        let presentation = AetherModalPresentationController(
            presentedViewController: modal,
            presenting: UIViewController()
        )
        let safeArea = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        for width: CGFloat in [320, 402] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 874)
            let frame = try XCTUnwrap(presentation.contentSizedFrame(in: bounds, safeAreaInsets: safeArea))

            XCTAssertEqual(frame.minX, bounds.minX + 8, accuracy: 0.001)
            XCTAssertEqual(frame.width, bounds.width - 16, accuracy: 0.001)
            XCTAssertEqual(frame.maxX, bounds.maxX - 8, accuracy: 0.001)
            XCTAssertEqual(frame.maxY, bounds.maxY - 8, accuracy: 0.001)
            XCTAssertGreaterThan(frame.minY, bounds.height / 2)
            var contentSafeArea = safeArea
            contentSafeArea.bottom -= 8
            XCTAssertEqual(
                frame.height,
                modal.contentHeight(forWidth: frame.width, safeAreaInsets: contentSafeArea),
                accuracy: 0.001
            )
        }
    }

    func testContentSizedModalClampsHeightToAvailableViewport() throws {
        let modal = AetherThemePickerModalController()
        let presentation = AetherModalPresentationController(
            presentedViewController: modal,
            presenting: UIViewController()
        )
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 250)
        let safeArea = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let frame = try XCTUnwrap(presentation.contentSizedFrame(in: bounds, safeAreaInsets: safeArea))

        XCTAssertEqual(frame.minY, safeArea.top, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, bounds.maxY - 8, accuracy: 0.001)
        XCTAssertEqual(frame.width, bounds.width - 16, accuracy: 0.001)
    }

    func testPickerUsesAetherSegmentsWithOneLineTextAndSmallIcons() throws {
        for width: CGFloat in [304, 386] {
            let picker = AetherThemePickerView(theme: .light)
            picker.frame.size = picker.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            picker.layoutIfNeeded()
            let control = try XCTUnwrap(descendants(of: picker).compactMap { $0 as? AetherSegmentedControl }.first)
            control.layoutIfNeeded()
            XCTAssertEqual(control.items.map(\.title), ["Light", "Dark", "System"])
            XCTAssertEqual(control.selectedIndex, 0)
            XCTAssertLessThanOrEqual(control.debugScrollView.contentSize.width, control.bounds.width + 0.5)
            let titles = descendants(of: control).compactMap { ASViewToDisplayNode($0) as? ASTextNode }
                .filter { ["Light", "Dark", "System"].contains($0.attributedText?.string ?? "") }
            XCTAssertEqual(titles.count, 6, "Both normal and selected Aether layers should contain all options")

            for title in titles {
                let text = try XCTUnwrap(title.attributedText)
                let font = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
                let fontTraits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
                let weight = try XCTUnwrap(fontTraits?[.weight] as? CGFloat)

                XCTAssertEqual(title.maximumNumberOfLines, 1)
                XCTAssertEqual(font.pointSize, 13, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(weight, UIFont.Weight.semibold.rawValue)
                XCTAssertGreaterThanOrEqual(title.bounds.width + 0.5, text.size().width, "\(text.string) is clipped at width \(width)")
                XCTAssertGreaterThanOrEqual(title.bounds.height + 0.5, font.lineHeight)
                XCTAssertTrue(control.bounds.contains(title.view.convert(title.bounds, to: control)))
            }
            let icons = descendants(of: control).compactMap { $0 as? UIImageView }
                .filter { $0.accessibilityIdentifier?.hasPrefix("aether.segment.icon.") == true }
            XCTAssertEqual(icons.count, 6)
            for icon in icons {
                XCTAssertNotNil(icon.image)
                XCTAssertLessThanOrEqual(icon.bounds.width, 18)
                XCTAssertLessThanOrEqual(icon.bounds.height, 18)
                XCTAssertTrue(control.bounds.contains(icon.convert(icon.bounds, to: control)))
            }
        }
    }

    func testAetherSegmentSelectionUpdatesThemeAndPublishesOneEvent() throws {
        let picker = laidOutPicker(theme: .light)
        let control = try XCTUnwrap(descendants(of: picker).compactMap { $0 as? AetherSegmentedControl }.first)
        var changes: [AetherThemePickerView.Theme] = []
        var eventCount = 0
        picker.themeChanged = { changes.append($0) }
        picker.addAction(UIAction { _ in eventCount += 1 }, for: .valueChanged)

        control.selectedIndexChanged(1)
        control.selectedIndexChanged(1)

        XCTAssertEqual(picker.theme, .dark)
        XCTAssertEqual(control.selectedIndex, 1)
        XCTAssertEqual(changes, [.dark])
        XCTAssertEqual(eventCount, 1)
    }

    func testModalFittingLeavesOnlyCaptionPaddingAndHomeIndicatorOverlap() throws {
        for width: CGFloat in [320, 402] {
            let modal = AetherThemePickerModalController(theme: .dark)
            let presentation = AetherModalPresentationController(presentedViewController: modal, presenting: UIViewController())
            let safeArea = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            let frame = try XCTUnwrap(presentation.contentSizedFrame(in: CGRect(x: 0, y: 0, width: width, height: 874), safeAreaInsets: safeArea))
            let safeAreaUnderlap = safeArea.bottom - 8
            modal.loadViewIfNeeded()
            modal.additionalSafeAreaInsets.bottom = safeAreaUnderlap
            modal.view.frame = frame
            modal.view.setNeedsLayout()
            modal.view.layoutIfNeeded()
            modal.pickerView.layoutIfNeeded()

            XCTAssertEqual(modal.pickerView.bounds.width, width - 16, accuracy: 0.001)
            let caption = try XCTUnwrap(descendants(of: modal.pickerView).compactMap { $0 as? UILabel }
                .first { $0.text == "Dark appearance stays on, day and night." })
            let captionFrame = caption.convert(caption.bounds, to: modal.view)
            XCTAssertEqual(modal.view.bounds.maxY - captionFrame.maxY, safeAreaUnderlap + 12, accuracy: 1)
            XCTAssertGreaterThan(captionFrame.height, 0)
        }
    }

    func testMoonUsesOneClosedCrescentContour() throws {
        let picker = laidOutPicker(theme: .dark)
        let moon = try XCTUnwrap(namedLayer("aether.theme.moon", in: picker.layer) as? CAShapeLayer)
        let path = try XCTUnwrap(moon.path)
        var contourStarts = 0
        var contourEnds = 0
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: contourStarts += 1
            case .closeSubpath: contourEnds += 1
            default: break
            }
        }

        XCTAssertEqual(contourStarts, 1, "Two overlapping circles create two visible crescents")
        XCTAssertEqual(contourEnds, 1)
        XCTAssertFalse(path.boundingBoxOfPath.isEmpty)
    }

    func testSunAndMoonTravelAcrossSkyDuringThemeTransition() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Celestial movement is intentionally disabled by Reduce Motion")
        }
        let picker = laidOutPicker(theme: .light)
        let sun = try XCTUnwrap(namedLayer("aether.theme.sun", in: picker.layer))
        let moon = try XCTUnwrap(namedLayer("aether.theme.moon", in: picker.layer))
        let lightPositions = [sun.position, moon.position]

        picker.setTheme(.dark, animated: true)

        for (index, layer) in [sun, moon].enumerated() {
            XCTAssertNotEqual(layer.position, lightPositions[index])
            let animation = try XCTUnwrap(layer.animation(forKey: "aether.theme.position") as? CAKeyframeAnimation)
            XCTAssertEqual(animation.keyPath, "position")
            let samples = try XCTUnwrap(animation.values as? [NSValue]).map(\.cgPointValue)
            XCTAssertGreaterThan(samples.count, 2)
            XCTAssertNotEqual(samples.first, samples.last)
            let horizontalSpan = (samples.map(\.x).max() ?? 0) - (samples.map(\.x).min() ?? 0)
            let verticalSpan = (samples.map(\.y).max() ?? 0) - (samples.map(\.y).min() ?? 0)
            XCTAssertGreaterThan(horizontalSpan, 20)
            XCTAssertGreaterThan(verticalSpan, 20)
            XCTAssertGreaterThan(animation.duration, 0)
        }

        picker.setTheme(.light, animated: false)
        XCTAssertNil(sun.animation(forKey: "aether.theme.position"))
        XCTAssertNil(moon.animation(forKey: "aether.theme.position"))
        XCTAssertEqual(sun.position, lightPositions[0])
        XCTAssertEqual(moon.position, lightPositions[1])
    }

    private func laidOutPicker(theme: AetherThemePickerView.Theme) -> AetherThemePickerView {
        let picker = AetherThemePickerView(theme: theme)
        picker.frame = CGRect(x: 0, y: 0, width: 320, height: 278)
        picker.layoutIfNeeded()
        return picker
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func namedLayer(_ name: String, in layer: CALayer) -> CALayer? {
        if layer.name == name { return layer }
        return layer.sublayers?.compactMap { namedLayer(name, in: $0) }.first
    }
}
