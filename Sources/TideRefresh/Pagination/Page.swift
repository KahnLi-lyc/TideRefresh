/// A page of loaded items and the cursor used to request the following page.
public struct Page<Item: Sendable, Cursor: Sendable>: Sendable {
    // MARK: - Public Properties

    /// The items delivered by this page, which may be empty.
    public let items: [Item]

    /// The next page's cursor, or `nil` when pagination is exhausted.
    public let nextCursor: Cursor?

    // MARK: - Initialization

    /// Creates a page. An empty page may still provide a next cursor.
    public init(items: [Item], nextCursor: Cursor?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Identifies the page a pagination loader should fetch.
public enum PaginationRequest<Cursor: Sendable>: Sendable {
    /// Fetch the first page without using a previously loaded cursor.
    case refresh

    /// Fetch the page following the supplied cursor.
    case nextPage(Cursor)
}

/// A committed change that the application applies to its own item storage.
public enum PaginationUpdate<Item: Sendable>: Sendable {
    /// Replace the application's items after a successful refresh.
    case replace([Item])

    /// Append items after a successful next-page request.
    case append([Item])
}
