import UIKit

/// The edge at which an operation is presented.
public enum RefreshEdge: Sendable {
    case top
    case bottom
}

/// Observable presentation state, independent of the application's data model.
public enum RefreshState: Equatable, Sendable {
    case idle
    case pulling
    case armed
    case loading
    case succeeded
    case failed
    case noMoreData
}

/// An operation's outcome. Cancellation never displays an error.
public enum RefreshResult: Sendable {
    case success(hasMoreData: Bool = true)
    case failure
    case cancelled
}

/// When the footer should request another page.
public enum LoadMoreMode: Equatable, Sendable {
    case pull
    case automatic
    case prefetch(distance: CGFloat = 200)
}

/// Trigger geometry and behavior. Invalid dimensions fall back to safe defaults.
public struct RefreshConfiguration: Sendable {
    public var headerHeight: CGFloat
    public var footerHeight: CGFloat
    public var loadMoreMode: LoadMoreMode
    public var isHapticsEnabled: Bool
    /// Maximum automatic requests while content does not fill the viewport. Default: zero.
    public var shortContentPageLimit: Int

    public init(
        headerHeight: CGFloat = 60,
        footerHeight: CGFloat = 44,
        loadMoreMode: LoadMoreMode = .automatic,
        isHapticsEnabled: Bool = true,
        shortContentPageLimit: Int = 0
    ) {
        self.headerHeight = headerHeight
        self.footerHeight = footerHeight
        self.loadMoreMode = loadMoreMode
        self.isHapticsEnabled = isHapticsEnabled
        self.shortContentPageLimit = shortContentPageLimit
    }

    var validHeaderHeight: CGFloat {
        headerHeight.isFinite && headerHeight > 0 ? headerHeight : 60
    }

    var validFooterHeight: CGFloat {
        footerHeight.isFinite && footerHeight > 0 ? footerHeight : 44
    }
}

/// Customizable, localized status labels. Defaults follow the application's language.
public struct RefreshStrings: Sendable {
    public var pullToRefresh: String
    public var releaseToRefresh: String
    public var refreshing: String
    public var loadMore: String
    public var loadingMore: String
    public var retry: String
    public var noMoreData: String
    public var updated: String

    public init(
        pullToRefresh: String? = nil,
        releaseToRefresh: String? = nil,
        refreshing: String? = nil,
        loadMore: String? = nil,
        loadingMore: String? = nil,
        retry: String? = nil,
        noMoreData: String? = nil,
        updated: String? = nil
    ) {
        self.pullToRefresh = pullToRefresh ?? String(localized: "Pull to refresh", bundle: .module)
        self.releaseToRefresh = releaseToRefresh ?? String(localized: "Release to refresh", bundle: .module)
        self.refreshing = refreshing ?? String(localized: "Refreshing", bundle: .module)
        self.loadMore = loadMore ?? String(localized: "Load more", bundle: .module)
        self.loadingMore = loadingMore ?? String(localized: "Loading more", bundle: .module)
        self.retry = retry ?? String(localized: "Failed. Tap to retry", bundle: .module)
        self.noMoreData = noMoreData ?? String(localized: "No more data", bundle: .module)
        self.updated = updated ?? String(localized: "Updated", bundle: .module)
    }
}
