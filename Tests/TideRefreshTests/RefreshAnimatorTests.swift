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

    func testExpressiveAnimatorsMapPullProgressWithoutVisibleText() {
        let animators: [any RefreshAnimator] = [
            RingRefreshAnimator(edge: .top),
            DotsRefreshAnimator(edge: .top),
            TideRefreshAnimator(edge: .top),
        ]

        for animator in animators {
            animator.view.frame = CGRect(x: 0, y: 0, width: 160, height: 60)
            animator.view.layoutIfNeeded()
            animator.update(state: .pulling, progress: 0.4)

            XCTAssertEqual(animator.view.subviews.first?.alpha ?? 0, 0.4, accuracy: 0.001)
            XCTAssertTrue(findSubviews(UILabel.self, in: animator.view).isEmpty)
            XCTAssertEqual(animator.view.accessibilityLabel, RefreshStrings().pullToRefresh)
        }
    }

    func testExpressiveAnimatorsStartAndStopOwnedLoadingAnimations() {
        let animators: [any RefreshAnimator] = [
            RingRefreshAnimator(edge: .bottom),
            DotsRefreshAnimator(edge: .bottom),
            TideRefreshAnimator(edge: .bottom),
        ]

        for animator in animators {
            animator.view.frame = CGRect(x: 0, y: 0, width: 160, height: 60)
            animator.view.layoutIfNeeded()
            animator.update(state: .loading, progress: .nan)

            if !UIAccessibility.isReduceMotionEnabled {
                XCTAssertGreaterThan(animationCount(in: animator.view.layer), 0)
            }
            XCTAssertEqual(animator.view.accessibilityLabel, RefreshStrings().loadingMore)

            animator.stop()
            animator.stop()
            XCTAssertEqual(animationCount(in: animator.view.layer), 0)
        }
    }

    func testExpressiveAnimatorsClampInvalidProgressAndShowTerminalSymbols() {
        let animators: [any RefreshAnimator] = [
            RingRefreshAnimator(edge: .bottom),
            DotsRefreshAnimator(edge: .bottom),
            TideRefreshAnimator(edge: .bottom),
        ]

        for animator in animators {
            animator.update(state: .pulling, progress: .infinity)
            XCTAssertEqual(animator.view.subviews.first?.alpha, 0)

            animator.update(state: .armed, progress: 20)
            XCTAssertEqual(animator.view.subviews.first?.alpha, 1)

            animator.update(state: .failed, progress: 0)
            XCTAssertTrue(hasVisibleTerminalImage(in: animator.view))
            XCTAssertEqual(animator.view.accessibilityLabel, RefreshStrings().retry)

            animator.update(state: .noMoreData, progress: 0)
            XCTAssertTrue(hasVisibleTerminalImage(in: animator.view))
            XCTAssertEqual(animator.view.accessibilityLabel, RefreshStrings().noMoreData)
        }
    }

    func testHorizontalEdgesUseRefreshAndLoadMoreAccessibilitySemantics() {
        let strings = RefreshStrings(
            pullToRefresh: "Pull leading",
            refreshing: "Refresh leading",
            loadMore: "Pull trailing",
            loadingMore: "Load trailing"
        )
        let leading = RingRefreshAnimator(edge: .leading)
        let trailing = RingRefreshAnimator(edge: .trailing)
        leading.configure(theme: .init(), strings: strings)
        trailing.configure(theme: .init(), strings: strings)

        leading.update(state: .pulling, progress: 0.5)
        trailing.update(state: .pulling, progress: 0.5)
        XCTAssertEqual(leading.view.accessibilityLabel, "Pull leading")
        XCTAssertEqual(trailing.view.accessibilityLabel, "Pull trailing")

        leading.update(state: .loading, progress: 0)
        trailing.update(state: .loading, progress: 0)
        XCTAssertEqual(leading.view.accessibilityLabel, "Refresh leading")
        XCTAssertEqual(trailing.view.accessibilityLabel, "Load trailing")
    }

    func testDefaultAnimatorTreatsLeadingAsRefreshAndUsesHorizontalLayout() {
        let strings = RefreshStrings(pullToRefresh: "Pull", loadMore: "Load", updated: "Updated")
        let animator = DefaultRefreshAnimator(edge: .leading)
        animator.lastUpdated = Date(timeIntervalSince1970: 0)
        animator.configure(theme: .init(), strings: strings)
        animator.update(state: .idle, progress: 0)

        XCTAssertEqual(findSubview(UIStackView.self, in: animator.view)?.axis, .vertical)
        XCTAssertTrue(findSubview(UILabel.self, in: animator.view)?.text?.contains("Pull") == true)
        XCTAssertTrue(findSubview(UILabel.self, in: animator.view)?.text?.contains(":") == true)
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

    private func animationCount(in layer: CALayer) -> Int {
        (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) {
            $0 + animationCount(in: $1)
        }
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
