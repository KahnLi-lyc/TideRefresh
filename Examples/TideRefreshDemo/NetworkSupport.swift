import Foundation
import os
import TideRefresh

enum NetworkScenario: String, CaseIterable {
    case success
    case empty
    case short
    case refreshFailure
    case loadMoreFailure
    case timeout
    case malformedJSON
    case staleResponse

    var title: String {
        switch self {
        case .success: "Success & Pagination"
        case .empty: "Empty First Page"
        case .short: "Short Content Fill"
        case .refreshFailure: "Refresh HTTP 500"
        case .loadMoreFailure: "Load More Retry"
        case .timeout: "Request Timeout"
        case .malformedJSON: "Malformed JSON"
        case .staleResponse: "Refresh Preempts Page"
        }
    }
}

enum NetworkDelay: String, CaseIterable {
    case fast
    case normal
    case slow

    var title: String {
        switch self {
        case .fast: "Fast (50 ms)"
        case .normal: "Normal (300 ms)"
        case .slow: "Slow (1.5 s)"
        }
    }

    var nanoseconds: UInt64 {
        switch self {
        case .fast: 50_000_000
        case .normal: 300_000_000
        case .slow: 1_500_000_000
        }
    }
}

struct NetworkMetrics: Equatable {
    let requestCount: Int
    let activeRequestCount: Int
    let completionCount: Int
    let cancellationCount: Int
    let lastStatusCode: Int?
    let requestedCursors: [Int?]
    let lastURL: String?
}

enum DemoAPIError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
}

actor DemoAPIClient {
    // MARK: - Private Properties

    private let scenario: NetworkScenario
    private let delay: NetworkDelay
    private let sessionID: UUID
    private let session: URLSession

    // MARK: - Initialization

    init(scenario: NetworkScenario, delay: NetworkDelay) {
        self.scenario = scenario
        self.delay = delay
        sessionID = UUID()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.timeoutIntervalForRequest = 5
        session = URLSession(configuration: configuration)
        MockURLProtocol.register(sessionID: sessionID)
    }

    deinit {
        session.invalidateAndCancel()
        MockURLProtocol.retire(sessionID: sessionID)
    }

    // MARK: - Public Methods

    func load(_ request: PaginationRequest<Int>) async throws -> Page<DemoItem, Int> {
        let urlRequest = try makeRequest(for: request)
        let result: (Data, URLResponse)
        if scenario == .staleResponse, case .nextPage = request {
            // 故意模拟不响应任务取消的旧 SDK，验证协调器会丢弃迟到结果。
            let session = session
            result = try await Task.detached {
                try await session.data(for: urlRequest)
            }.value
        } else {
            result = try await session.data(for: urlRequest)
        }
        let (data, response) = result
        guard let response = response as? HTTPURLResponse else {
            throw DemoAPIError.invalidResponse
        }
        guard 200 ..< 300 ~= response.statusCode else {
            throw DemoAPIError.httpStatus(response.statusCode)
        }
        let payload = try JSONDecoder().decode(DemoPagePayload.self, from: data)
        return Page(items: payload.items, nextCursor: payload.nextCursor)
    }

    func metrics() async -> NetworkMetrics {
        await MockURLProtocol.metrics(for: sessionID)
    }

    func waitForRequestCount(_ count: Int) async {
        await MockURLProtocol.waitForRequestCount(count, sessionID: sessionID)
    }

    func waitForCancellationCount(_ count: Int) async {
        await MockURLProtocol.waitForCancellationCount(count, sessionID: sessionID)
    }

    func waitForCompletionCount(_ count: Int) async {
        await MockURLProtocol.waitForCompletionCount(count, sessionID: sessionID)
    }

    func cancelRequests() async -> NetworkMetrics {
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        tasks.forEach { $0.cancel() }
        await MockURLProtocol.waitForNoActiveRequests(sessionID: sessionID)
        return await self.metrics()
    }

    // MARK: - Private Methods

    private func makeRequest(for request: PaginationRequest<Int>) throws -> URLRequest {
        var components = URLComponents(string: "https://mock.tiderefresh.local/items")
        var query = [
            URLQueryItem(name: "scenario", value: scenario.rawValue),
            URLQueryItem(name: "delay", value: delay.rawValue),
            URLQueryItem(name: "session", value: sessionID.uuidString),
        ]
        if case let .nextPage(cursor) = request {
            query.append(URLQueryItem(name: "cursor", value: String(cursor)))
        }
        components?.queryItems = query
        guard let url = components?.url else { throw DemoAPIError.invalidResponse }
        return URLRequest(url: url)
    }
}

final class MockURLProtocol: URLProtocol {
    // MARK: - Private Properties

    private static let store = MockHTTPStore()
    private let lifecycleLock = NSLock()
    private var isStopped = false
    private var responseThread: MockResponseThread?

    // MARK: - Lifecycle

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "mock.tiderefresh.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let pending = try Self.store.prepare(for: request)
            let thread = MockResponseThread(request: request, pending: pending, owner: self, store: Self.store)
            lifecycleLock.lock()
            guard !isStopped else {
                lifecycleLock.unlock()
                thread.cancelRequest()
                return
            }
            responseThread = thread
            thread.start()
            lifecycleLock.unlock()
        } catch {
            lifecycleLock.lock()
            if !isStopped {
                client?.urlProtocol(self, didFailWithError: error)
            }
            lifecycleLock.unlock()
        }
    }

    override func stopLoading() {
        lifecycleLock.lock()
        isStopped = true
        let thread = responseThread
        responseThread = nil
        lifecycleLock.unlock()
        thread?.cancelRequest()
    }

    // MARK: - Public Methods

    static func metrics(for sessionID: UUID) async -> NetworkMetrics {
        store.metrics(for: sessionID)
    }

    static func waitForRequestCount(_ count: Int, sessionID: UUID) async {
        await store.waitForRequestCount(count, sessionID: sessionID)
    }

    static func waitForCancellationCount(_ count: Int, sessionID: UUID) async {
        await store.waitForCancellationCount(count, sessionID: sessionID)
    }

    static func waitForCompletionCount(_ count: Int, sessionID: UUID) async {
        await store.waitForCompletionCount(count, sessionID: sessionID)
    }

    static func waitForNoActiveRequests(sessionID: UUID) async {
        await store.waitForNoActiveRequests(sessionID: sessionID)
    }

    static func register(sessionID: UUID) {
        store.register(sessionID: sessionID)
    }

    static func retire(sessionID: UUID) {
        store.retire(sessionID: sessionID)
    }
}

private final class MockResponseThread: Thread {
    private enum RequestState: Equatable {
        case registered
        case committed
        case cancelled
    }

    // MARK: - Private Properties

    private let requestValue: URLRequest
    private let pending: MockHTTPStore.PendingResponse
    private weak var owner: MockURLProtocol?
    private let store: MockHTTPStore
    private let stateLock = OSAllocatedUnfairLock(initialState: RequestState.registered)

    // MARK: - Initialization

    init(
        request: URLRequest,
        pending: MockHTTPStore.PendingResponse,
        owner: MockURLProtocol,
        store: MockHTTPStore
    ) {
        requestValue = request
        self.pending = pending
        self.owner = owner
        self.store = store
        super.init()
        name = "TideRefresh.MockHTTP"
        qualityOfService = .userInitiated
    }

    // MARK: - Lifecycle

    override func main() {
        do {
            wait(for: pending.delayNanoseconds)
            guard !isCancelled else { return }
            let mock = try store.response(for: pending)
            guard commitRequest() else { return }
            let delivered = finish(mock)
            store.recordCompletion(
                sessionID: pending.context.sessionID,
                statusCode: delivered ? mock.statusCode : nil
            )
        } catch {
            guard commitRequest() else { return }
            if let owner {
                owner.client?.urlProtocol(owner, didFailWithError: error)
            }
            store.recordCompletion(sessionID: pending.context.sessionID, statusCode: nil)
        }
    }

    func cancelRequest() {
        let result: (shouldCancel: Bool, shouldRecord: Bool) = stateLock.withLock { state in
            switch state {
            case .registered:
                state = .cancelled
                return (true, true)
            case .committed, .cancelled:
                return (false, false)
            }
        }
        guard result.shouldCancel else { return }
        cancel()
        if result.shouldRecord {
            store.recordCancellation(sessionID: pending.context.sessionID)
        }
    }

    // MARK: - Private Methods

    private func wait(for nanoseconds: UInt64) {
        let seconds = TimeInterval(nanoseconds) / 1_000_000_000
        let deadline = Date().addingTimeInterval(seconds)
        while !isCancelled {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(remaining, 0.01))
        }
    }

    private func commitRequest() -> Bool {
        stateLock.withLock { state in
            guard state == .registered else { return false }
            state = .committed
            return true
        }
    }

    private func finish(_ mock: MockHTTPResponse) -> Bool {
        guard let owner,
              let url = requestValue.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: mock.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            return false
        }
        owner.client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
        owner.client?.urlProtocol(owner, didLoad: mock.data)
        owner.client?.urlProtocolDidFinishLoading(owner)
        return true
    }
}

private struct DemoPagePayload: Codable {
    let items: [DemoItem]
    let nextCursor: Int?
}

private struct MockHTTPResponse {
    let statusCode: Int
    let data: Data
}

private struct MockHTTPStore {
    fileprivate struct RequestContext {
        let scenario: NetworkScenario
        let delay: NetworkDelay
        let sessionID: UUID
        let cursor: Int?
        let url: URL
    }

    fileprivate struct PendingResponse {
        let context: RequestContext
        let attempt: Int
        let revision: Int
        let delayNanoseconds: UInt64
    }

    private struct SessionState {
        var requestCount = 0
        var activeRequestCount = 0
        var completionCount = 0
        var cancellationCount = 0
        var lastStatusCode: Int?
        var requestedCursors = [Int?]()
        var lastURL: String?
        var refreshCount = 0
        var cursorAttempts = [Int: Int]()
        var isRetired = false
    }

    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct Storage {
        var sessions = [UUID: SessionState]()
        var requestWaiters = [UUID: [Waiter]]()
        var completionWaiters = [UUID: [Waiter]]()
        var cancellationWaiters = [UUID: [Waiter]]()
        var idleWaiters = [UUID: [CheckedContinuation<Void, Never>]]()
    }

    private let lock = OSAllocatedUnfairLock(initialState: Storage())

    func register(sessionID: UUID) {
        lock.withLock { storage in
            storage.sessions[sessionID] = SessionState()
        }
    }

    func prepare(for request: URLRequest) throws -> PendingResponse {
        let context = try context(for: request)
        let result: (PendingResponse?, [CheckedContinuation<Void, Never>]) = lock.withLock { storage in
            guard var state = storage.sessions[context.sessionID], !state.isRetired else {
                return (nil, [])
            }
            state.requestCount += 1
            state.activeRequestCount += 1
            state.requestedCursors.append(context.cursor)
            state.lastURL = context.url.absoluteString
            let attempt: Int
            if let cursor = context.cursor {
                attempt = state.cursorAttempts[cursor, default: 0] + 1
                state.cursorAttempts[cursor] = attempt
            } else {
                attempt = state.refreshCount + 1
                state.refreshCount = attempt
            }
            storage.sessions[context.sessionID] = state
            let ready = takeReadyWaiters(
                in: &storage.requestWaiters,
                for: context.sessionID,
                count: state.requestCount
            )
            let delay = context.scenario == .staleResponse && context.cursor != nil
                ? 3_000_000_000 : context.delay.nanoseconds
            return (
                Optional(PendingResponse(
                    context: context,
                    attempt: attempt,
                    revision: max(1, state.refreshCount),
                    delayNanoseconds: delay
                )),
                ready
            )
        }
        let (pending, ready) = result
        ready.forEach { $0.resume() }
        guard let pending else { throw URLError(.cancelled) }
        return pending
    }

    func response(for pending: PendingResponse) throws -> MockHTTPResponse {
        let context = pending.context
        if context.scenario == .timeout {
            throw URLError(.timedOut)
        }
        if context.scenario == .refreshFailure, context.cursor == nil, pending.attempt > 1 {
            return MockHTTPResponse(statusCode: 500, data: Data())
        }
        if context.scenario == .loadMoreFailure, context.cursor == 1, pending.attempt == 1 {
            return MockHTTPResponse(statusCode: 503, data: Data())
        }
        if context.scenario == .malformedJSON {
            return MockHTTPResponse(statusCode: 200, data: Data("{broken".utf8))
        }

        let page = context.cursor ?? 0
        let pageSize = switch context.scenario {
        case .short: 2
        case .loadMoreFailure: 15
        default: 5
        }
        let payload: DemoPagePayload
        if context.scenario == .empty, page == 0 {
            payload = DemoPagePayload(items: [], nextCursor: nil)
        } else {
            let items = makeItems(page: page, pageSize: pageSize, revision: pending.revision)
            payload = DemoPagePayload(items: items, nextCursor: page < 2 ? page + 1 : nil)
        }
        let data = try JSONEncoder().encode(payload)
        return MockHTTPResponse(statusCode: 200, data: data)
    }

    func recordCancellation(sessionID: UUID) {
        let ready: [CheckedContinuation<Void, Never>] = lock.withLock { storage in
            guard var state = storage.sessions[sessionID] else { return [] }
            state.cancellationCount += 1
            state.activeRequestCount = max(0, state.activeRequestCount - 1)
            if state.isRetired, state.activeRequestCount == 0 {
                storage.sessions.removeValue(forKey: sessionID)
                return []
            }
            storage.sessions[sessionID] = state
            let cancellation = takeReadyWaiters(
                in: &storage.cancellationWaiters,
                for: sessionID,
                count: state.cancellationCount
            )
            let idle = state.activeRequestCount == 0
                ? storage.idleWaiters.removeValue(forKey: sessionID) ?? [] : []
            return cancellation + idle
        }
        ready.forEach { $0.resume() }
    }

    func recordCompletion(sessionID: UUID, statusCode: Int?) {
        let ready: [CheckedContinuation<Void, Never>] = lock.withLock { storage in
            guard var state = storage.sessions[sessionID] else { return [] }
            state.completionCount += 1
            state.activeRequestCount = max(0, state.activeRequestCount - 1)
            if let statusCode { state.lastStatusCode = statusCode }
            if state.isRetired, state.activeRequestCount == 0 {
                storage.sessions.removeValue(forKey: sessionID)
                return []
            }
            storage.sessions[sessionID] = state
            let completion = takeReadyWaiters(
                in: &storage.completionWaiters,
                for: sessionID,
                count: state.completionCount
            )
            let idle = state.activeRequestCount == 0
                ? storage.idleWaiters.removeValue(forKey: sessionID) ?? [] : []
            return completion + idle
        }
        ready.forEach { $0.resume() }
    }

    func metrics(for sessionID: UUID) -> NetworkMetrics {
        lock.withLock { storage in
            let state = storage.sessions[sessionID] ?? SessionState()
            return NetworkMetrics(
                requestCount: state.requestCount,
                activeRequestCount: state.activeRequestCount,
                completionCount: state.completionCount,
                cancellationCount: state.cancellationCount,
                lastStatusCode: state.lastStatusCode,
                requestedCursors: state.requestedCursors,
                lastURL: state.lastURL
            )
        }
    }

    func waitForRequestCount(_ count: Int, sessionID: UUID) async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { storage in
                guard let state = storage.sessions[sessionID], !state.isRetired else { return true }
                if state.requestCount >= count { return true }
                storage.requestWaiters[sessionID, default: []].append(
                    Waiter(count: count, continuation: continuation)
                )
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func waitForCancellationCount(_ count: Int, sessionID: UUID) async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { storage in
                guard let state = storage.sessions[sessionID], !state.isRetired else { return true }
                if state.cancellationCount >= count { return true }
                storage.cancellationWaiters[sessionID, default: []].append(
                    Waiter(count: count, continuation: continuation)
                )
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func waitForCompletionCount(_ count: Int, sessionID: UUID) async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { storage in
                guard let state = storage.sessions[sessionID], !state.isRetired else { return true }
                if state.completionCount >= count { return true }
                storage.completionWaiters[sessionID, default: []].append(
                    Waiter(count: count, continuation: continuation)
                )
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func waitForNoActiveRequests(sessionID: UUID) async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { storage in
                guard let state = storage.sessions[sessionID], !state.isRetired else { return true }
                if state.activeRequestCount == 0 { return true }
                storage.idleWaiters[sessionID, default: []].append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func retire(sessionID: UUID) {
        let waiters = lock.withLock { storage in
            if var state = storage.sessions[sessionID] {
                state.isRetired = true
                if state.activeRequestCount == 0 {
                    storage.sessions.removeValue(forKey: sessionID)
                } else {
                    storage.sessions[sessionID] = state
                }
            }
            let request = storage.requestWaiters.removeValue(forKey: sessionID) ?? []
            let completion = storage.completionWaiters.removeValue(forKey: sessionID) ?? []
            let cancellation = storage.cancellationWaiters.removeValue(forKey: sessionID) ?? []
            let idle = storage.idleWaiters.removeValue(forKey: sessionID) ?? []
            let counted = request + completion + cancellation
            return counted.map(\.continuation) + idle
        }
        waiters.forEach { $0.resume() }
    }

    private func context(for request: URLRequest) throws -> RequestContext {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scenarioValue = components.queryItems?.first(where: { $0.name == "scenario" })?.value,
              let scenario = NetworkScenario(rawValue: scenarioValue),
              let delayValue = components.queryItems?.first(where: { $0.name == "delay" })?.value,
              let delay = NetworkDelay(rawValue: delayValue),
              let sessionValue = components.queryItems?.first(where: { $0.name == "session" })?.value,
              let sessionID = UUID(uuidString: sessionValue)
        else {
            throw DemoAPIError.invalidResponse
        }
        let cursor = components.queryItems?.first(where: { $0.name == "cursor" })?.value.flatMap(Int.init)
        return RequestContext(scenario: scenario, delay: delay, sessionID: sessionID, cursor: cursor, url: url)
    }

    private func makeItems(page: Int, pageSize: Int, revision: Int) -> [DemoItem] {
        (0 ..< pageSize).map { offset in
            let id = page * pageSize + offset
            return DemoItem(
                id: id,
                title: "Network Item \(id + 1)",
                subtitle: "HTTP page \(page + 1), revision \(revision)",
                symbol: "network"
            )
        }
    }

    private func takeReadyWaiters(
        in storage: inout [UUID: [Waiter]],
        for sessionID: UUID,
        count: Int
    ) -> [CheckedContinuation<Void, Never>] {
        let pending = storage.removeValue(forKey: sessionID) ?? []
        let ready = pending.filter { $0.count <= count }
        let remaining = pending.filter { $0.count > count }
        if !remaining.isEmpty { storage[sessionID] = remaining }
        return ready.map(\.continuation)
    }
}
