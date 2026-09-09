import TideRefresh
@testable import TideRefreshDemo
import XCTest

@MainActor
final class DemoAPIClientTests: XCTestCase {
    func testSuccessBuildsURLAndReturnsFirstPage() async throws {
        let client = DemoAPIClient(scenario: .success, delay: .fast)

        let page = try await client.load(.refresh)
        let metrics = await client.metrics()

        XCTAssertEqual(page.items.count, 5)
        XCTAssertEqual(page.nextCursor, 1)
        XCTAssertEqual(metrics.requestCount, 1)
        XCTAssertEqual(metrics.requestedCursors.count, 1)
        XCTAssertNil(metrics.requestedCursors[0])
        XCTAssertEqual(metrics.lastStatusCode, 200)
        XCTAssertTrue(metrics.lastURL?.contains("scenario=success") == true)
        XCTAssertFalse(metrics.lastURL?.contains("cursor=") == true)
    }

    func testPaginationSendsCursorAndEndsAfterThirdPage() async throws {
        let client = DemoAPIClient(scenario: .success, delay: .fast)

        let first = try await client.load(.refresh)
        let second = try await client.load(.nextPage(XCTUnwrap(first.nextCursor)))
        let third = try await client.load(.nextPage(XCTUnwrap(second.nextCursor)))
        let metrics = await client.metrics()

        XCTAssertEqual(second.items.first?.id, 5)
        XCTAssertEqual(third.items.first?.id, 10)
        XCTAssertNil(third.nextCursor)
        XCTAssertEqual(metrics.requestedCursors, [nil, 1, 2])
        XCTAssertTrue(metrics.lastURL?.contains("cursor=2") == true)
    }

    func testEmptyScenarioReturnsTerminalEmptyPage() async throws {
        let client = DemoAPIClient(scenario: .empty, delay: .fast)

        let page = try await client.load(.refresh)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertNil(page.nextCursor)
    }

    func testShortScenarioReturnsBoundedSmallPages() async throws {
        let client = DemoAPIClient(scenario: .short, delay: .fast)

        let first = try await client.load(.refresh)
        let second = try await client.load(.nextPage(XCTUnwrap(first.nextCursor)))
        let third = try await client.load(.nextPage(XCTUnwrap(second.nextCursor)))

        XCTAssertEqual([first.items.count, second.items.count, third.items.count], [2, 2, 2])
        XCTAssertNil(third.nextCursor)
    }

    func testSecondRefreshReturnsHTTP500() async throws {
        let client = DemoAPIClient(scenario: .refreshFailure, delay: .fast)
        _ = try await client.load(.refresh)

        let error = await capturedError { try await client.load(.refresh) }
        let metrics = await client.metrics()

        XCTAssertEqual(error as? DemoAPIError, .httpStatus(500))
        XCTAssertEqual(metrics.lastStatusCode, 500)
        XCTAssertEqual(metrics.requestCount, 2)
    }

    func testLoadMoreFailureRetainsCursorForRetry() async throws {
        let client = DemoAPIClient(scenario: .loadMoreFailure, delay: .fast)
        let first = try await client.load(.refresh)
        let cursor = try XCTUnwrap(first.nextCursor)

        let error = await capturedError { try await client.load(.nextPage(cursor)) }
        let retry = try await client.load(.nextPage(cursor))
        let metrics = await client.metrics()

        XCTAssertEqual(error as? DemoAPIError, .httpStatus(503))
        XCTAssertEqual(retry.items.first?.id, 15)
        XCTAssertEqual(metrics.requestedCursors, [nil, 1, 1])
    }

    func testMalformedJSONThrowsDecodingError() async {
        let client = DemoAPIClient(scenario: .malformedJSON, delay: .fast)

        let error = await capturedError { try await client.load(.refresh) }
        let metrics = await client.metrics()

        XCTAssertTrue(error is DecodingError)
        XCTAssertEqual(metrics.lastStatusCode, 200)
    }

    func testTimeoutPropagatesURLError() async {
        let client = DemoAPIClient(scenario: .timeout, delay: .fast)

        let error = await capturedError { try await client.load(.refresh) }

        XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }

    func testCancellationStopsRequestAndRecordsIt() async {
        let client = DemoAPIClient(scenario: .success, delay: .slow)
        let request = Task { try await client.load(.refresh) }
        await client.waitForRequestCount(1)

        request.cancel()
        let error = await capturedError { try await request.value }
        await client.waitForCancellationCount(1)
        let metrics = await client.metrics()

        XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        XCTAssertEqual(metrics.requestCount, 1)
        XCTAssertEqual(metrics.activeRequestCount, 0)
        XCTAssertEqual(metrics.completionCount, 0)
        XCTAssertEqual(metrics.cancellationCount, 1)
    }

    func testStalePageFinishesAfterNewRefreshWithOriginalRevision() async throws {
        let client = DemoAPIClient(scenario: .staleResponse, delay: .fast)
        _ = try await client.load(.refresh)
        let oldPage = Task { try await client.load(.nextPage(1)) }
        await client.waitForRequestCount(2)

        let latest = try await client.load(.refresh)
        let old = try await oldPage.value
        let metrics = await client.metrics()

        XCTAssertTrue(latest.items.allSatisfy { $0.subtitle.contains("revision 2") })
        XCTAssertTrue(old.items.allSatisfy { $0.subtitle.contains("revision 1") })
        XCTAssertEqual(metrics.requestedCursors, [nil, 1, nil])
        XCTAssertEqual(metrics.activeRequestCount, 0)
        XCTAssertEqual(metrics.completionCount, 3)
    }

    private func capturedError(_ operation: () async throws -> some Any) async -> (any Error)? {
        do {
            _ = try await operation()
            XCTFail("Expected operation to throw")
            return nil
        } catch {
            return error
        }
    }
}
