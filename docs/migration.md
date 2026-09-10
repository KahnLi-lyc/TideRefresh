# Migration / 迁移指南

TideRefresh is an original UIKit implementation, not a drop-in replacement for
MJRefresh, ESPullToRefresh, CRRefresh, KafkaRefresh, or UIScrollView-InfiniteScroll.
Those projects are conceptual references documented in [provenance](references.md).
The 0.1.0-beta.1 prerelease is available; see
[installation](../README.md#status-and-installation). Use the version tag for
repeatable integration and `main` only when intentionally evaluating unreleased work.

TideRefresh 并非旧组件的同名 API 替换。迁移时先保留业务网络层与数据源，再逐步替换
刷新展示和分页调度。支持范围为 Swift 6、iOS/iPadOS 16+ 的纵向 UIKit 列表，以及横向
`UIScrollView` / `UICollectionView`。

## Map Responsibilities / 职责映射

| Existing responsibility / 原职责 | TideRefresh API / 迁移目标 |
| --- | --- |
| Header/footer attachment | `try RefreshController(scrollView:axis:)`; axis defaults to `.vertical` |
| Begin refresh | Install handlers, then `beginRefreshing()` |
| Begin next page | `beginLoadingMore()` |
| Callback completion | `RefreshOperation.finish(.success(hasMoreData: ...))` |
| Failure / retry | `.failure`; tap failed footer to retry |
| No more data | `.success(hasMoreData: false)` |
| Reset presentation availability | `resetPagination(hasMoreData:)` |
| Cancel network request | Async task cancellation or `operation.onCancel` |
| Remove controls | `detach()` |
| Serialized cursor loading | `PaginationCoordinator<Item, Cursor>` |
| Custom animation | `RefreshAnimator` conformance in an extension |

## Integration Steps / 集成顺序

1. Remove the old refresh attachment, observers, inset adjustments, and completion
   calls for this scroll view. Keep the application's delegate and data source.
   先移除该列表的旧刷新控件和对应 inset 调整，避免两套组件同时管理边界。
2. Attach one controller with `try`. Existing calls remain vertical; pass
   `axis: .horizontal` for a horizontal scroll or collection view. Keep owners
   weak in retained callbacks.
   同一滚动视图只挂载一个控制器，重复挂载会抛出错误。
3. Use `setAsyncHandlers` for async loaders, or `onRefresh` / `onLoadMore` for
   callback APIs. Install handlers before beginning a refresh. Async handlers
   return `RefreshResult`; callback handlers receive `RefreshOperation`.
4. If adopting the coordinator, make `Item` and `Cursor` `Sendable`. Translate
   `.refresh` and `.nextPage(cursor)` to your server's request format and return
   `Page(items:nextCursor:)`. Mutate application items synchronously in `onUpdate`.
   协调器返回 `Bool`，需映射到 `.success(hasMoreData:)`，不要直接作为 handler 返回值。
5. Connect cancellation to the network layer. Check callback lifetime before
   mutating data; ignoring a stale `finish` alone cannot protect application data.
   取消不是失败。失败保留游标；刷新会取消旧分页并屏蔽迟到响应。
6. Choose `.pull`, `.automatic`, or `.prefetch(distance:)`. Set a bounded
   `shortContentPageLimit` only when extra requests should fill a short viewport.
7. Test existing safe-area, keyboard, rotation, split-view, and inset behavior.
   Apply host inset changes by deltas. An absolute assignment is the total inset
   including component contributions, whose intent cannot be inferred afterward.
8. Call `cancel()` when leaving a page if its work should stop. Call `detach()`
   when replacing or removing controls. Refresh the coordinator when filters
   change; controller `resetPagination` does not clear its cursor.

## Semantic Differences / 行为差异

- One active presentation operation: a refresh cancels pagination; a duplicate
  refresh does not launch another request. Coordinator duplicate load-more calls
  return immediately with current availability, rather than joining a request.
- An empty page is not necessarily the last page. `nextCursor == nil` ends
  coordinator pagination. Map page-number APIs to a `Sendable` integer cursor.
- Short-content auto-fill is off by default and bounded when enabled. It is not
  an unlimited loop until a server produces visible content.
- Animators control appearance, not network requests or data ownership. Use
  distinct unparented animator views for header and footer. Frame animation takes
  decoded `UIImage` values; optional Lottie lives in `Examples/LottieDemo`.
- Horizontal refresh uses semantic `.leading` and pagination uses `.trailing`.
  LTR/RTL physical mapping is captured at attachment time, so detach and reattach
  after changing layout direction. Omitted horizontal animators are rings; custom
  animators must be initialized with the matching leading/trailing edge. Existing
  `headerHeight` / `footerHeight` values become extents along the horizontal axis.
- UIKit callbacks run on MainActor. Keep network payloads `Sendable`, avoid
  `@unchecked Sendable`, and do not move UI mutations into the loader.
- Horizontal `UITableView`, inverted chat, nested-scroll arbitration, SwiftUI,
  and Catalyst compatibility layers are not provided. Validate iOS 16 runtime
  behavior before treating that support as release-qualified.

See the [English](../README.md) and [中文](../README.zh-Hans.md) READMEs for complete
network, callback, animation, and lifecycle examples.
