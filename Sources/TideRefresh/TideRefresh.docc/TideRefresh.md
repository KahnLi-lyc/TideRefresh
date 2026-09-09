# ``TideRefresh``

Attach cancellable refresh and pagination controls to vertical UIKit scroll views.

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
`adjustedContentInset`; control width comes from the scroll container.

## Pagination and Presentation

``LoadMoreMode`` supports pull, automatic, and distance-based prefetch.
``RefreshConfiguration/shortContentPageLimit`` defaults to zero and bounds extra
requests while content is shorter than the viewport. A false `hasMoreData` success
stops pagination. Failed footers can be tapped to retry. Resetting controller
pagination availability does not reset a coordinator's cursor.

Use ``DefaultRefreshAnimator`` for localized labels, Dynamic Type, VoiceOver,
Reduce Motion, and an optional last-updated time. ``FrameRefreshAnimator`` uses
application-provided images without decoding GIF files. Custom ``RefreshAnimator``
conformances belong in extensions and provide one distinct view per edge, update
state and progress, apply ``RefreshTheme`` / ``RefreshStrings``, and stop on detach.
Progress may exceed one. Lottie is available only in a separate optional example
package pinned to 4.5.2; it is not a core dependency.

This is an unreleased 0.1 candidate. iOS 16 runtime validation remains a 1.0
release gate. Horizontal scrolling, inverted chat, nested scrolling arbitration,
SwiftUI, and Catalyst are outside the supported scope.
Local Xcode 27 beta / iOS 27 evidence includes 30 passing core tests and 10 passing
UI scenarios on each of iPhone and iPad across suite and targeted reruns. Stable
Xcode 26.6 device/simulator compilation passed; local stable simulator execution
is blocked by host/debug-service compatibility. Foundation CI passed, while
implementation Swift 6.0 compilation and formatting also passed. See the repository
pull requests for current stable simulator CI results. Manual accessibility/device
checks and iOS 16 runtime verification remain release gates.

## Topics

### Attachment and Operations

- ``RefreshController``
- ``RefreshAttachmentError``
- ``RefreshOperation``
- ``RefreshResult``
- ``RefreshState``
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
- ``FrameRefreshAnimator``
- ``RefreshTheme``
- ``RefreshStrings``
