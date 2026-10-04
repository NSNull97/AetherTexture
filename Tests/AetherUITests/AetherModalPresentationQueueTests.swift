import UIKit
import XCTest
@testable import AetherUI

@MainActor
final class AetherModalPresentationQueueTests: XCTestCase {
    func testLatestDetentRequestWaitsUntilContentTransitionEnds() async {
        let root = AetherViewController(navigationBarPresentationData: nil)
        let modal = AetherModalNavigationController(rootViewController: root)
        modal.loadViewIfNeeded()
        modal.view.frame = CGRect(x: 0, y: 0, width: 390, height: 422)
        modal.view.layoutIfNeeded()

        // This exercises queue ownership only. Real UIKit presentation and its
        // container require an application host, which SwiftPM tests lack.
        let presentation = AetherModalPresentationController(
            presentedViewController: modal, presenting: UIViewController()
        )
        let detail = AetherViewController(navigationBarPresentationData: nil)
        modal.pushViewController(detail, animated: true)
        XCTAssertTrue(modal.isContentTransitioning)

        presentation.setDetent(.stage1, animated: false)
        presentation.setDetent(.stage2, animated: false)
        presentation.resumePendingDetentIfPossible()
        XCTAssertEqual(modal.currentDetent, .stage1)

        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(modal.isContentTransitioning)
        presentation.resumePendingDetentIfPossible()
        XCTAssertEqual(modal.currentDetent, .stage2)
    }
}
