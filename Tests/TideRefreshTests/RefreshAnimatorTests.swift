@testable import TideRefresh
import UIKit
import XCTest

@MainActor
final class RefreshAnimatorTests: XCTestCase {
    func testActivityIndicatorShowsOnlyDuringInteractiveAndLoadingStates() {
        let animator = ActivityIndicatorRefreshAnimator(edge: .top)
        let indicator = findSubview(UIActivityIndicatorView.self, in: animator.view)

        animator.update(state: .idle, progress: 0)
        XCTAssertEqual(indicator?.alpha, 0)
        XCTAssertFalse(indicator?.isAnimating ?? true)

        animator.update(state: .pulling, progress: 0.5)
        XCTAssertEqual(indicator?.alpha ?? 0, 0.5, accuracy: 0.001)
        XCTAssertFalse(indicator?.isAnimating ?? true)

        animator.update(state: .loading, progress: 0)
        XCTAssertEqual(indicator?.alpha, 1)
        XCTAssertTrue(indicator?.isAnimating ?? false)

        animator.stop()
        animator.stop()
        XCTAssertFalse(indicator?.isAnimating ?? true)
    }

    func testHiddenTerminalPresentationHasNoVisibleFailureOrEndState() {
        let animator = ActivityIndicatorRefreshAnimator(edge: .bottom, terminalPresentation: .hidden)
        let indicator = findSubview(UIActivityIndicatorView.self, in: animator.view)

        animator.update(state: .failed, progress: 0)
        XCTAssertEqual(indicator?.alpha, 0)
        XCTAssertFalse(hasVisibleTerminalImage(in: animator.view))

        animator.update(state: .noMoreData, progress: 0)
        XCTAssertEqual(indicator?.alpha, 0)
        XCTAssertFalse(hasVisibleTerminalImage(in: animator.view))
    }

    func testSymbolTerminalPresentationKeepsTextVisualsHiddenAndAccessibilityAccurate() {
        let strings = RefreshStrings(refreshing: "Refreshing accessibly", loadingMore: "Loading accessibly",
                                     retry: "Retry accessibly", noMoreData: "Finished accessibly")
        let animator = ActivityIndicatorRefreshAnimator(edge: .bottom, terminalPresentation: .symbols)
        animator.configure(theme: .init(tintColor: .systemPink), strings: strings)

        animator.update(state: .failed, progress: 0)
        XCTAssertTrue(hasVisibleTerminalImage(in: animator.view))
        XCTAssertEqual(animator.view.accessibilityLabel, "Retry accessibly")
        XCTAssertTrue(findSubviews(UILabel.self, in: animator.view).isEmpty)

        animator.update(state: .noMoreData, progress: 0)
        XCTAssertTrue(hasVisibleTerminalImage(in: animator.view))
        XCTAssertEqual(animator.view.accessibilityLabel, "Finished accessibly")

        animator.update(state: .loading, progress: 0)
        XCTAssertEqual(animator.view.accessibilityLabel, "Loading accessibly")
    }

    private func hasVisibleTerminalImage(in view: UIView) -> Bool {
        findSubviews(UIImageView.self, in: view).contains {
            !$0.isHidden && $0.alpha > 0 && !hasActivityIndicatorAncestor($0)
        }
    }

    private func hasActivityIndicatorAncestor(_ view: UIView) -> Bool {
        var ancestor = view.superview
        while let current = ancestor {
            if current is UIActivityIndicatorView { return true }
            ancestor = current.superview
        }
        return false
    }

    private func findSubview<View: UIView>(_ type: View.Type, in view: UIView) -> View? {
        findSubviews(type, in: view).first
    }

    private func findSubviews<View: UIView>(_ type: View.Type, in view: UIView) -> [View] {
        var matches = view.subviews.compactMap { $0 as? View }
        for subview in view.subviews {
            matches += findSubviews(type, in: subview)
        }
        return matches
    }
}
