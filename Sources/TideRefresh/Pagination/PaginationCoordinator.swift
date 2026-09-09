import Foundation

/// Serializes pagination requests and delivers successful updates on the main actor.
///
/// The application owns its items. This coordinator owns only cursor and request
/// state. A refresh cancels any previous request; stale results never reach the
/// update handler, even when a loader ignores task cancellation.
@MainActor
public final class PaginationCoordinator<Item: Sendable, Cursor: Sendable> {
    // MARK: - Public Properties

    /// The last successfully committed next cursor, or `nil` before refresh or at exhaustion.
    public private(set) var nextCursor: Cursor?

    /// Whether a successful refresh has provided a cursor for another page.
    public var hasMoreData: Bool {
        hasRefreshed && nextCursor != nil
    }

    /// Whether a request is awaiting completion, including its synchronous update callback.
    public var isLoading: Bool {
        pending != nil
    }

    /// 测试可等待整个 worker 完成，避免仅等待 loader 返回后就断言旧响应。
    var workerTask: Task<Void, Never>? {
        pending?.task
    }

    // MARK: - Private Properties

    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        let continuation: CheckedContinuation<Bool, any Error>
    }

    private let loader: @Sendable (PaginationRequest<Cursor>) async throws -> Page<Item, Cursor>
    private let onUpdate: @MainActor (PaginationUpdate<Item>) -> Void
    private var pending: Pending?
    private var hasRefreshed = false

    // MARK: - Initialization

    /// Creates a coordinator with a loader and a synchronous main-actor update handler.
    ///
    /// The coordinator retains both closures. Capture owners weakly when they retain
    /// the coordinator. The loader should cooperate with cancellation to release its
    /// resources promptly; correctness does not depend on that cooperation.
    public init(
        loader: @escaping @Sendable (PaginationRequest<Cursor>) async throws -> Page<Item, Cursor>,
        onUpdate: @escaping @MainActor (PaginationUpdate<Item>) -> Void
    ) {
        self.loader = loader
        self.onUpdate = onUpdate
    }

    // MARK: - Lifecycle

    deinit {
        pending?.task.cancel()
        pending?.continuation.resume(throwing: CancellationError())
    }

    // MARK: - Public Methods

    /// Loads the first page, cancelling any request already in progress.
    ///
    /// Success emits `.replace` and returns whether another page is available.
    /// Failure preserves the previously committed cursor and emits no update.
    /// Cancellation, including replacement by a newer refresh, promptly throws
    /// `CancellationError` without waiting for an uncooperative loader to finish.
    @discardableResult
    public func refresh() async throws -> Bool {
        try Task.checkCancellation()
        cancel()
        return try await perform(.refresh)
    }

    /// Loads the next page, emitting `.append` on success and returning `hasMoreData`.
    ///
    /// Before a successful refresh or after exhaustion this returns `false` without
    /// calling the loader. While another request is in progress, this returns the
    /// current `hasMoreData` without starting or awaiting a duplicate request.
    /// Failure leaves the cursor available for retry. Cancelling the calling task
    /// cancels this request and throws `CancellationError`.
    @discardableResult
    public func loadMore() async throws -> Bool {
        try Task.checkCancellation()
        guard pending == nil else { return hasMoreData }
        guard hasRefreshed, let nextCursor else { return false }
        return try await perform(.nextPage(nextCursor))
    }

    /// Cancels the current request without changing the last committed cursor.
    ///
    /// This operation is idempotent. The awaiting caller throws `CancellationError`
    /// promptly, and any later loader response is discarded. Previously delivered
    /// updates remain committed, including when this is called from `onUpdate`.
    public func cancel() {
        guard let pending else { return }
        self.pending = nil
        pending.task.cancel()
        pending.continuation.resume(throwing: CancellationError())
    }

    // MARK: - Private Methods

    private func perform(_ request: PaginationRequest<Cursor>) async throws -> Bool {
        let id = UUID()
        // 加载期间不强持有协调器；取消时可直接结束调用方的等待。
        let task = Task { @MainActor [weak self, loader] in
            let result: Result<Page<Item, Cursor>, any Error>
            do {
                let page = try await loader(request)
                try Task.checkCancellation()
                result = .success(page)
            } catch {
                result = .failure(Task.isCancelled ? CancellationError() : error)
            }
            self?.finish(id: id, request: request, result: result)
        }
        let hasMoreData: Bool = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending = Pending(id: id, task: task, continuation: continuation)
            }
        } onCancel: {
            // 先同步标记底层任务，避免主线程取消处理排队时提交已取消的结果。
            task.cancel()
            Task { @MainActor [weak self] in
                guard self?.pending?.id == id else { return }
                self?.cancel()
            }
        }
        try Task.checkCancellation()
        return hasMoreData
    }

    private func finish(
        id: UUID,
        request: PaginationRequest<Cursor>,
        result: Result<Page<Item, Cursor>, any Error>
    ) {
        // 被替换的请求即使忽略取消，也不能修改游标或发送业务更新。
        guard let pending, pending.id == id else { return }
        switch result {
        case let .success(page):
            nextCursor = page.nextCursor
            hasRefreshed = true
            let hasMoreData = self.hasMoreData
            switch request {
            case .refresh:
                onUpdate(.replace(page.items))
            case .nextPage:
                onUpdate(.append(page.items))
            }
            // 回调允许同步取消；再次检查，避免重复恢复 continuation。
            guard self.pending?.id == id else { return }
            self.pending = nil
            pending.continuation.resume(returning: hasMoreData)
        case let .failure(error):
            self.pending = nil
            pending.continuation.resume(throwing: error)
        }
    }
}
