@testable import TideRefresh
import UIKit
import XCTest

@MainActor
final class RefreshControllerTests: XCTestCase {
    func testCompletionIsScopedAndDuplicateRefreshIsIgnored() throws {
        let scroll = makeScroll()
        var handles: [RefreshOperation] = []
        let controller = try RefreshController(scrollView: scroll, onRefresh: { handles.append($0) })
        controller.beginRefreshing()
        controller.beginRefreshing()
        XCTAssertEqual(handles.count, 1)
        XCTAssertEqual(scroll.contentInset.top, 60)
        controller.cancel()
        controller.beginRefreshing()
        handles[0].finish(.failure)
        XCTAssertTrue(controller.isRefreshing)
        handles[1].finish(.success(hasMoreData: false))
        handles[1].finish(.failure)
        XCTAssertFalse(controller.isRefreshing)
        XCTAssertFalse(controller.hasMoreData)
        XCTAssertEqual(controller.headerState, .succeeded)
        controller.detach()
    }

    func testRefreshCancelsPaginationAndRetainsNewOperation() throws {
        let scroll = makeScroll()
        var old: RefreshOperation?
        var refresh: RefreshOperation?
        var cancellations = 0
        let controller = try RefreshController(scrollView: scroll, onRefresh: { refresh = $0 }, onLoadMore: {
            old = $0
            $0.onCancel = { cancellations += 1 }
        })
        controller.beginLoadingMore()
        controller.beginRefreshing()
        XCTAssertEqual(cancellations, 1)
        old?.finish(.success(hasMoreData: false))
        XCTAssertTrue(controller.hasMoreData)
        XCTAssertTrue(controller.isRefreshing)
        refresh?.finish()
        controller.detach()
    }

    func testDetachPreservesHostInsetChangesAndExistingAccessibilityActions() throws {
        let scroll = makeScroll()
        scroll.contentInset = UIEdgeInsets(top: 10, left: 3, bottom: 20, right: 4)
        let original = UIAccessibilityCustomAction(name: "Host") { _ in true }
        scroll.accessibilityCustomActions = [original]
        var handle: RefreshOperation?
        let controller = try RefreshController(scrollView: scroll, onRefresh: { handle = $0 }, onLoadMore: { _ in })
        controller.beginRefreshing()
        scroll.contentInset.top += 12
        scroll.contentInset.bottom += 30
        controller.detach()
        controller.detach()
        handle?.finish(.failure)
        XCTAssertEqual(scroll.contentInset, UIEdgeInsets(top: 22, left: 3, bottom: 50, right: 4))
        XCTAssertEqual(scroll.accessibilityCustomActions?.count, 1)
        XCTAssertTrue(scroll.accessibilityCustomActions?.first === original)
        XCTAssertFalse(scroll.alwaysBounceVertical)
        XCTAssertFalse(controller.isAttached)
    }

    func testAttachmentIsExclusiveAndAllowsReattachmentAfterDetach() throws {
        let scroll = makeScroll()
        let first = try RefreshController(scrollView: scroll)
        XCTAssertThrowsError(try RefreshController(scrollView: scroll))
        first.detach()
        let second = try RefreshController(scrollView: scroll)
        XCTAssertTrue(second.isAttached)
        second.detach()
    }

    func testFailedPaginationRetainsAvailabilityAndCanRetry() throws {
        let scroll = makeScroll()
        var calls = 0
        let controller = try RefreshController(scrollView: scroll, onLoadMore: {
            calls += 1
            $0.finish(calls == 1 ? .failure : .success(hasMoreData: false))
        })
        controller.beginLoadingMore()
        XCTAssertEqual(controller.footerState, .failed)
        XCTAssertTrue(controller.hasMoreData)
        controller.beginLoadingMore()
        XCTAssertEqual(controller.footerState, .noMoreData)
        controller.beginLoadingMore()
        XCTAssertEqual(calls, 2)
        controller.resetPagination()
        XCTAssertEqual(controller.footerState, .idle)
        controller.detach()
    }

    func testFooterAccessibilityLabelTracksLoadingAndTerminalStates() throws {
        let scroll = makeScroll()
        let strings = RefreshStrings(loadMore: "Load", loadingMore: "Loading", noMoreData: "Complete")
        var operation: RefreshOperation?
        let controller = try RefreshController(scrollView: scroll, strings: strings, onLoadMore: { operation = $0 })
        let footer = scroll.subviews.first { $0.isAccessibilityElement && $0.accessibilityTraits.contains(.button) }

        controller.beginLoadingMore()
        XCTAssertEqual(footer?.accessibilityLabel, "Loading")
        operation?.finish(.success(hasMoreData: false))
        XCTAssertEqual(footer?.accessibilityLabel, "Complete")
        controller.detach()
    }

    func testCancellationCallbackCanDetachWithoutStartingRefresh() throws {
        let scroll = makeScroll()
        var calls = 0
        let controller = try RefreshController(scrollView: scroll, onRefresh: { _ in calls += 1 })
        controller.onLoadMore = { [weak controller] operation in
            operation.onCancel = { [weak controller] in controller?.detach() }
        }
        controller.beginLoadingMore()
        controller.beginRefreshing()
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(controller.isAttached)
    }

    func testControllerReleasedWhenScrollIsReleased() {
        weak var weakController: RefreshController?
        autoreleasepool {
            let scroll = makeScroll()
            let controller = try? RefreshController(scrollView: scroll)
            weakController = controller
            XCTAssertNotNil(weakController)
        }
        XCTAssertNil(weakController)
    }

    func testCallbacksDoNotRunForShortContentByDefault() throws {
        let scroll = makeScroll()
        scroll.contentSize.height = 0
        var calls = 0
        let controller = try RefreshController(scrollView: scroll, onRefresh: { $0.finish() }, onLoadMore: { _ in calls += 1 })
        controller.beginRefreshing()
        scroll.contentOffset.y = 100
        XCTAssertEqual(calls, 0)
        controller.detach()
    }

    func testShortContentFillStopsAtBudget() async throws {
        let scroll = makeScroll()
        scroll.contentSize.height = 20
        var calls = 0
        let filled = expectation(description: "Bounded pages loaded")
        let controller = try RefreshController(scrollView: scroll,
                                               configuration: .init(shortContentPageLimit: 2),
                                               onRefresh: { $0.finish() }, onLoadMore: {
                                                   calls += 1
                                                   $0.finish()
                                                   if calls == 2 { filled.fulfill() }
                                               })
        controller.beginRefreshing()
        await fulfillment(of: [filled], timeout: 2)
        XCTAssertEqual(calls, 2)
        controller.detach()
    }

    func testCancelledBeforeAsyncTaskStartsDoesNotCallHandler() async throws {
        let scroll = makeScroll()
        let controller = try RefreshController(scrollView: scroll)
        var calls = 0
        controller.setAsyncHandlers(refresh: { calls += 1; return .success() })
        controller.beginRefreshing()
        let queuedTask = controller.activeTask
        controller.detach()
        await queuedTask?.value
        XCTAssertEqual(calls, 0)
    }

    func testAnimatorCanDetachDuringLoadingWithoutInvokingCallback() throws {
        let scroll = makeScroll()
        let animator = TestAnimator()
        var calls = 0
        let controller = try RefreshController(scrollView: scroll, headerAnimator: animator, onRefresh: { _ in calls += 1 })
        animator.onLoading = { [weak controller] in controller?.detach() }
        controller.beginRefreshing()
        XCTAssertFalse(controller.isAttached)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(scroll.contentInset, .zero)
    }

    func testHostInsetObserverCanDetachDuringLoading() throws {
        let scroll = makeScroll()
        var calls = 0
        let controller = try RefreshController(scrollView: scroll, onRefresh: { _ in calls += 1 })
        let observer = scroll.observe(\.contentInset) { _, _ in
            MainActor.assumeIsolated { if controller.isRefreshing { controller.detach() } }
        }
        controller.beginRefreshing()
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(controller.isAttached)
        XCTAssertEqual(scroll.contentInset.top, 0)
        observer.invalidate()
    }

    func testShortContentFillReconsidersDelayedLayout() async throws {
        let scroll = makeScroll()
        let filled = expectation(description: "Fill after content shrinks")
        let controller = try RefreshController(scrollView: scroll, configuration: .init(shortContentPageLimit: 1),
                                               onRefresh: { $0.finish() }, onLoadMore: { operation in
                                                   operation.finish(.success(hasMoreData: false))
                                                   filled.fulfill()
                                               })
        controller.beginRefreshing()
        scroll.contentSize.height = 20
        await fulfillment(of: [filled], timeout: 2)
        controller.detach()
    }

    func testPreferenceChangeRefreshesAnimatorAndDetachStopsObserving() throws {
        let scroll = makeScroll()
        let animator = TestAnimator()
        let controller = try RefreshController(scrollView: scroll, headerAnimator: animator)
        let before = animator.updates
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        XCTAssertGreaterThan(animator.updates, before)
        controller.detach()
        let detached = animator.updates
        NotificationCenter.default.post(name: UIContentSizeCategory.didChangeNotification, object: nil)
        XCTAssertEqual(animator.updates, detached)
    }

    func testSuccessAnimatorCanStartPaginationWithoutLosingLoadingState() throws {
        let scroll = makeScroll()
        let animator = TestAnimator()
        let controller = try RefreshController(scrollView: scroll, headerAnimator: animator,
                                               onRefresh: { $0.finish() }, onLoadMore: { _ in })
        animator.onSuccess = { [weak controller] in controller?.beginLoadingMore() }
        controller.beginRefreshing()
        XCTAssertTrue(controller.isLoadingMore)
        XCTAssertEqual(controller.footerState, .loading)
        controller.detach()
    }

    func testResetPaginationDoesNotStrandScheduledShortFill() async throws {
        let scroll = makeScroll()
        scroll.contentSize.height = 10
        let loaded = expectation(description: "Fill survives reset")
        let controller = try RefreshController(scrollView: scroll, configuration: .init(shortContentPageLimit: 1),
                                               onRefresh: { $0.finish() }, onLoadMore: {
                                                   $0.finish(.success(hasMoreData: false))
                                                   loaded.fulfill()
                                               })
        controller.beginRefreshing()
        controller.resetPagination()
        await fulfillment(of: [loaded], timeout: 2)
        controller.detach()
    }

    private func makeScroll() -> UIScrollView {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 390, height: 1200)
        return scroll
    }
}

@MainActor
private final class TestAnimator: RefreshAnimator {
    var view: UIView {
        contentView
    }

    var onLoading: (() -> Void)?
    var onSuccess: (() -> Void)?
    var updates = 0
    private lazy var contentView = UIView()
    func update(state: RefreshState, progress: CGFloat) {
        updates += 1
        if state == .loading { onLoading?() }
        if state == .succeeded { onSuccess?() }
    }

    func configure(theme: RefreshTheme, strings: RefreshStrings) {}
    func stop() {}
}

final class ScrollGeometryTests: XCTestCase {
    func testSafeAreaIsExcludedFromPullDistance() {
        let geometry = ScrollGeometry(offset: -148, contentHeight: 1000, viewportHeight: 800, topInset: 88, bottomInset: 34)
        XCTAssertEqual(geometry.topDistance, 60)
        XCTAssertEqual(geometry.bottomOffset, 234)
        XCTAssertFalse(geometry.isShort)
    }

    func testShortContentBottomUsesRestingTop() {
        let geometry = ScrollGeometry(offset: -44, contentHeight: 10, viewportHeight: 800, topInset: 88, bottomInset: 34)
        XCTAssertEqual(geometry.bottomOffset, -88)
        XCTAssertEqual(geometry.bottomDistance, 44)
        XCTAssertTrue(geometry.isShort)
    }

    func testThresholdCrossingBacktrackingAndCancelledRelease() {
        var state = PullStateMachine()
        XCTAssertEqual(state.drag(distance: 61, threshold: 60), .armed)
        XCTAssertEqual(state.drag(distance: 59, threshold: 60), .pulling)
        XCTAssertFalse(state.release(cancelled: false))
        _ = state.drag(distance: 60, threshold: 60)
        XCTAssertFalse(state.release(cancelled: true))
        _ = state.drag(distance: 60, threshold: 60)
        XCTAssertTrue(state.release(cancelled: false))
        XCTAssertFalse(state.release(cancelled: false))
    }
}
