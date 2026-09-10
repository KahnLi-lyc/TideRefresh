# ``TideRefresh``

Attach cancellable refresh and pagination controls to vertical or horizontal UIKit scroll views.

## Overview

TideRefresh targets iOS/iPadOS 16+ with Swift 6.0-compatible APIs and no core
dependencies. ``RefreshController`` owns presentation, while the application
owns its data source. ``PaginationCoordinator`` optionally serializes cursor
requests and delivers committed item updates.

All presentation APIs are main-actor isolated. Attach with `try`, install
handlers, then begin refreshing:

```swift
import UIKit
import TideRefresh

@MainActor
func attach(
    to scrollView: UIScrollView,
    pagination: PaginationCoordinator<String, Int>
) throws -> RefreshController {
    let controller = try RefreshController(scrollView: scrollView)
    controller.setAsyncHandlers(
        refresh: { [weak pagination] in
            guard let pagination else { return .cancelled }
            return .success(hasMoreData: try await pagination.refresh())
        },
        loadMore: { [weak pagination] in
            guard let pagination else { return .cancelled }
            return .success(hasMoreData: try await pagination.loadMore())
        }
    )
    controller.beginRefreshing()
    return controller
}
```

The application must retain the coordinator. Its loader receives
``PaginationRequest`` and returns ``Page``; both items and cursors are `Sendable`.
Apply ``PaginationUpdate`` synchronously in the coordinator's main-actor
`onUpdate` closure. A newer refresh invalidates earlier results, even when the
loader does not cooperate with cancellation. Failure preserves the committed
cursor for retry. Coordinator methods return pagination availability; handlers
map that value to ``RefreshResult/success(hasMoreData:)``.

## Cancellation and Ownership

The scroll view retains its controller and the controller references the scroll
view weakly. Capture owners weakly in retained handlers. `cancel()` stops the
current operation; `detach()` also removes controls, observations, and only the
component's inset contributions. Detach is idempotent. Duplicate attachments and
shared or parented animator views throw ``RefreshAttachmentError``.

For callback APIs, call ``RefreshOperation/finish(_:)`` once and install
``RefreshOperation/onCancel`` to cancel underlying work. Late finish calls are
ignored; callback clients must also prevent their own stale data mutations.
Async handlers finish automatically. Cancellation does not present an error.

Host inset edits should use deltas while attached. Absolute inset assignments
represent the total including active component contributions. Boundaries use
`adjustedContentInset`; control cross-axis size comes from the scroll container.

## Axis and Semantic Edges

``RefreshAxis/vertical`` is the default, so existing ``RefreshController`` calls
remain source-compatible. Use ``RefreshAxis/horizontal`` for horizontal
`UIScrollView` and `UICollectionView` content. ``RefreshEdge/top`` and
``RefreshEdge/bottom`` identify vertical refresh and pagination; horizontal
operations report ``RefreshEdge/leading`` and ``RefreshEdge/trailing``.

Horizontal physical edges follow the scroll view's effective LTR or RTL direction
at attachment time. The mapping is fixed until detach; reattach after changing the
effective layout direction. Pull, automatic, prefetch, programmatic refresh, and
bounded short-content filling all use semantic edges. Configuration properties
`headerHeight` and `footerHeight` name the control extent along the selected axis.

Omitted animators default to ``DefaultRefreshAnimator`` vertically and
``RingRefreshAnimator`` horizontally. Custom horizontal animators must be created
for the appropriate leading or trailing edge because ``RefreshAnimator`` does not
receive its edge from the controller.

## Pagination and Presentation

``LoadMoreMode`` supports pull, automatic, and distance-based prefetch.
``RefreshConfiguration/shortContentPageLimit`` defaults to zero and bounds extra
requests while content is shorter than the viewport. A false `hasMoreData` success
stops pagination. Failed footers can be tapped to retry. Resetting controller
pagination availability does not reset a coordinator's cursor.

Use ``DefaultRefreshAnimator`` for localized labels, Dynamic Type, VoiceOver,
Reduce Motion, and an optional last-updated time. Text-free built-ins include
``ActivityIndicatorRefreshAnimator``, ``RingRefreshAnimator``,
``DotsRefreshAnimator``, and ``TideRefreshAnimator``. Their terminal states use
``RefreshTerminalPresentation`` while retaining accessible localized state.
``FrameRefreshAnimator`` uses application-provided images without decoding GIF
files. Custom ``RefreshAnimator``
conformances belong in extensions and provide one distinct view per edge, update
state and progress, apply ``RefreshTheme`` / ``RefreshStrings``, and stop on detach.
Progress may exceed one. Lottie is available only in a separate optional example
package pinned to 4.5.2; it is not a core dependency.

The latest prerelease is 0.1.0-beta.1. The beta.2 candidate adds horizontal
refresh and pagination plus local network Demo coverage. iOS 16 runtime validation
remains a 1.0 release gate. Horizontal `UITableView`, inverted chat, nested scrolling
arbitration, SwiftUI, and Catalyst are outside the supported scope.
Local Xcode 27 evidence includes 57 passing XCTest cases and 20 passing UI
scenarios on both iPhone and iPad, including horizontal LTR/RTL pulls and rotation.
Xcode 16.2 and Xcode 26.6 remain CI checks. Manual accessibility/device checks and
iOS 16 runtime verification remain release gates.

## Topics

### Attachment and Operations

- ``RefreshController``
- ``RefreshAttachmentError``
- ``RefreshOperation``
- ``RefreshResult``
- ``RefreshState``
- ``RefreshAxis``
- ``RefreshEdge``

### Pagination

- ``PaginationCoordinator``
- ``PaginationRequest``
- ``PaginationUpdate``
- ``Page``
- ``LoadMoreMode``
- ``RefreshConfiguration``

### Appearance

- ``RefreshAnimator``
- ``DefaultRefreshAnimator``
- ``ActivityIndicatorRefreshAnimator``
- ``RingRefreshAnimator``
- ``DotsRefreshAnimator``
- ``TideRefreshAnimator``
- ``FrameRefreshAnimator``
- ``RefreshTerminalPresentation``
- ``RefreshTheme``
- ``RefreshStrings``
