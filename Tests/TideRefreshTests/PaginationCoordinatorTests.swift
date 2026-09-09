@testable import TideRefresh
import XCTest

@MainActor
final class PaginationCoordinatorTests: XCTestCase {
    func testRefreshReplacesAndPaginationAppendsUntilExhausted() async throws {
        let loader = ControlledPageLoader()
        var items = [Int]()
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load) { update in
            switch update {
            case let .replace(values): items = values
            case let .append(values): items += values
            }
        }

        let beforeRefresh = try await coordinator.loadMore()
        XCTAssertFalse(beforeRefresh)
        let initialCount = await loader.callCount
        XCTAssertEqual(initialCount, 0)

        let refresh = Task { try await coordinator.refresh() }
        let first = await loader.nextCall()
        XCTAssertTrue(coordinator.isLoading)
        guard case .refresh = first.request else { return XCTFail("Expected refresh") }
        await loader.succeed(first.id, items: [1, 2], nextCursor: 10)
        let firstHasMore = try await refresh.value
        XCTAssertTrue(firstHasMore)
        XCTAssertEqual(items, [1, 2])
        XCTAssertEqual(coordinator.nextCursor, 10)

        let more = Task { try await coordinator.loadMore() }
        let second = await loader.nextCall()
        guard case let .nextPage(cursor) = second.request else { return XCTFail("Expected next page") }
        XCTAssertEqual(cursor, 10)
        await loader.succeed(second.id, items: [3], nextCursor: nil)
        let secondHasMore = try await more.value
        XCTAssertFalse(secondHasMore)
        XCTAssertEqual(items, [1, 2, 3])
        XCTAssertFalse(coordinator.hasMoreData)
        XCTAssertFalse(coordinator.isLoading)
        let exhausted = try await coordinator.loadMore()
        XCTAssertFalse(exhausted)
        let finalCount = await loader.callCount
        XCTAssertEqual(finalCount, 2)
    }

    func testDuplicateLoadMoreDoesNotDispatchAnotherLoader() async throws {
        let loader = ControlledPageLoader()
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load, onUpdate: { _ in })
        let refresh = Task { try await coordinator.refresh() }
        let first = await loader.nextCall()
        await loader.succeed(first.id, items: [], nextCursor: 4)
        _ = try await refresh.value

        let more = Task { try await coordinator.loadMore() }
        let second = await loader.nextCall()
        let duplicateHasMore = try await coordinator.loadMore()
        XCTAssertTrue(duplicateHasMore)
        let count = await loader.callCount
        XCTAssertEqual(count, 2)
        await loader.succeed(second.id, items: [], nextCursor: nil)
        _ = try await more.value
    }

    func testRefreshPreemptsIgnoredCancellationAndSuppressesOldAppend() async throws {
        let loader = ControlledPageLoader()
        var items = [Int]()
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load) { update in
            switch update {
            case let .replace(values): items = values
            case let .append(values): items += values
            }
        }
        let initial = Task { try await coordinator.refresh() }
        let first = await loader.nextCall()
        await loader.succeed(first.id, items: [1], nextCursor: 10)
        _ = try await initial.value

        let old = Task { try await coordinator.loadMore() }
        let oldCall = await loader.nextCall()
        let oldWorker = try XCTUnwrap(coordinator.workerTask)
        let latest = Task { try await coordinator.refresh() }
        let latestCall = await loader.nextCall()
        await assertCancelled(old)
        await loader.succeed(latestCall.id, items: [20], nextCursor: 30)
        _ = try await latest.value
        await loader.succeed(oldCall.id, items: [99], nextCursor: 100)
        await oldWorker.value
        XCTAssertEqual(items, [20])
        XCTAssertEqual(coordinator.nextCursor, 30)
    }

    func testRefreshPreemptsOlderRefresh() async throws {
        let loader = ControlledPageLoader()
        var updates = [[Int]]()
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load) { update in
            if case let .replace(items) = update { updates.append(items) }
        }
        let old = Task { try await coordinator.refresh() }
        let oldCall = await loader.nextCall()
        let oldWorker = try XCTUnwrap(coordinator.workerTask)
        let latest = Task { try await coordinator.refresh() }
        let latestCall = await loader.nextCall()
        await assertCancelled(old)
        await loader.succeed(oldCall.id, items: [1], nextCursor: 1)
        await oldWorker.value
        XCTAssertTrue(updates.isEmpty)
        XCTAssertTrue(coordinator.isLoading)
        await loader.succeed(latestCall.id, items: [2], nextCursor: nil)
        _ = try await latest.value
        XCTAssertEqual(updates, [[2]])
    }

    func testFailuresPreserveCursorAndPermitRetry() async throws {
        let loader = ControlledPageLoader()
        var updateCount = 0
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load) { _ in updateCount += 1 }
        let initial = Task { try await coordinator.refresh() }
        let first = await loader.nextCall()
        await loader.succeed(first.id, items: [1], nextCursor: 5)
        _ = try await initial.value

        for refresh in [true, false] {
            let failed = Task {
                if refresh { return try await coordinator.refresh() }
                return try await coordinator.loadMore()
            }
            let call = await loader.nextCall()
            await loader.fail(call.id)
            do {
                _ = try await failed.value
                XCTFail("Expected failure")
            } catch is TestFailure {
                XCTAssertEqual(coordinator.nextCursor, 5)
                XCTAssertTrue(coordinator.hasMoreData)
                XCTAssertFalse(coordinator.isLoading)
            }
        }
        XCTAssertEqual(updateCount, 1)
        let retry = Task { try await coordinator.loadMore() }
        let retryCall = await loader.nextCall()
        guard case let .nextPage(cursor) = retryCall.request else { return XCTFail("Expected retry") }
        XCTAssertEqual(cursor, 5)
        await loader.succeed(retryCall.id, items: [2], nextCursor: nil)
        _ = try await retry.value
        XCTAssertEqual(updateCount, 2)
    }

    func testFailedInitialRefreshDoesNotEnableLoadMore() async throws {
        let loader = ControlledPageLoader()
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load, onUpdate: { _ in })
        let refresh = Task { try await coordinator.refresh() }
        let call = await loader.nextCall()
        await loader.fail(call.id)
        do {
            _ = try await refresh.value
            XCTFail("Expected failure")
        } catch is TestFailure {}
        let hasMore = try await coordinator.loadMore()
        XCTAssertFalse(hasMore)
        let count = await loader.callCount
        XCTAssertEqual(count, 1)
    }

    func testCallerCancellationCompletesWithoutWaitingForLoader() async throws {
        let loader = ControlledPageLoader()
        var updateCount = 0
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load) { _ in updateCount += 1 }
        let refresh = Task { try await coordinator.refresh() }
        let call = await loader.nextCall()
        let worker = try XCTUnwrap(coordinator.workerTask)
        refresh.cancel()
        await assertCancelled(refresh)
        XCTAssertFalse(coordinator.isLoading)
        await loader.succeed(call.id, items: [1], nextCursor: 1)
        await worker.value
        XCTAssertEqual(updateCount, 0)
        XCTAssertNil(coordinator.nextCursor)
    }

    func testCancelInsideUpdateDoesNotResumeCallerTwice() async {
        let loader = ControlledPageLoader()
        var coordinator: PaginationCoordinator<Int, Int>?
        coordinator = PaginationCoordinator<Int, Int>(loader: loader.load) { _ in
            coordinator?.cancel()
        }
        guard let active = coordinator else { return XCTFail("Missing coordinator") }
        let refresh = Task { try await active.refresh() }
        let call = await loader.nextCall()
        await loader.succeed(call.id, items: [1], nextCursor: 2)
        await assertCancelled(refresh)
        XCTAssertFalse(active.isLoading)
        XCTAssertEqual(active.nextCursor, 2)
        coordinator = nil
    }

    func testAlreadyCancelledCallerDoesNotDispatchLoader() async {
        let loader = ControlledPageLoader()
        let coordinator = PaginationCoordinator<Int, Int>(loader: loader.load, onUpdate: { _ in })
        let refresh = Task { try await coordinator.refresh() }
        refresh.cancel()
        await assertCancelled(refresh)
        let count = await loader.callCount
        XCTAssertEqual(count, 0)
        XCTAssertFalse(coordinator.isLoading)
    }

    func testCancelledLoaderDoesNotRetainCoordinator() async throws {
        let loader = ControlledPageLoader()
        var coordinator: PaginationCoordinator<Int, Int>? = PaginationCoordinator(
            loader: loader.load,
            onUpdate: { _ in }
        )
        let isReleased = { [weak coordinator] in coordinator == nil }
        let refresh = Task { [weak coordinator] in
            guard let coordinator else { throw CancellationError() }
            return try await coordinator.refresh()
        }
        let call = await loader.nextCall()
        let worker = try XCTUnwrap(coordinator?.workerTask)
        coordinator?.cancel()
        coordinator?.cancel()
        await assertCancelled(refresh)
        coordinator = nil
        XCTAssertTrue(isReleased())
        await loader.succeed(call.id, items: [1], nextCursor: nil)
        await worker.value
    }

    private func assertCancelled(_ task: Task<Bool, any Error>) async {
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct TestFailure: Error {}

private actor ControlledPageLoader {
    struct Call {
        let id: Int
        let request: PaginationRequest<Int>
    }

    private(set) var callCount = 0
    private var queued = [Call]()
    private var callWaiters = [CheckedContinuation<Call, Never>]()
    private var pending = [Int: CheckedContinuation<Page<Int, Int>, any Error>]()

    func load(_ request: PaginationRequest<Int>) async throws -> Page<Int, Int> {
        let id = callCount
        callCount += 1
        // 故意忽略取消，由测试控制旧请求何时返回。
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let call = Call(id: id, request: request)
            if callWaiters.isEmpty {
                queued.append(call)
            } else {
                callWaiters.removeFirst().resume(returning: call)
            }
        }
    }

    func nextCall() async -> Call {
        if !queued.isEmpty { return queued.removeFirst() }
        return await withCheckedContinuation { callWaiters.append($0) }
    }

    func succeed(_ id: Int, items: [Int], nextCursor: Int?) {
        pending.removeValue(forKey: id)?.resume(returning: Page(items: items, nextCursor: nextCursor))
    }

    func fail(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: TestFailure())
    }
}
