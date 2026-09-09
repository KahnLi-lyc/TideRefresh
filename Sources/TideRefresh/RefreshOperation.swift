import UIKit

/// A one-shot completion handle scoped to one operation. Retaining it does not retain the controller.
@MainActor
public final class RefreshOperation {
    // MARK: - Public Properties

    public let edge: RefreshEdge
    /// Called once when the controller cancels this operation. Set this to cancel callback-based work.
    public var onCancel: (() -> Void)?

    // MARK: - Private Properties

    private var completion: ((RefreshResult) -> Void)?

    // MARK: - Initialization

    init(edge: RefreshEdge, completion: @escaping (RefreshResult) -> Void) {
        self.edge = edge
        self.completion = completion
    }

    // MARK: - Public Methods

    /// Completes this operation once. Calls after cancellation or a previous finish are ignored.
    public func finish(_ result: RefreshResult = .success()) {
        let completion = completion
        self.completion = nil
        onCancel = nil
        completion?(result)
    }

    // MARK: - Private Methods

    func invalidate() {
        completion = nil
        let onCancel = onCancel
        self.onCancel = nil
        onCancel?()
    }
}
