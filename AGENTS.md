# TideRefresh Engineering Rules

## Product

- Independent Swift 6 UIKit library; Swift 6.0-compatible syntax and APIs.
- iOS/iPadOS 16+, SPM only, no dependencies in the core library.
- Support vertical UIScrollView, UITableView and UICollectionView, plus horizontal
  UIScrollView and UICollectionView. Horizontal UITableView, inverted chat, nested
  scrolling arbitration, SwiftUI and Catalyst are out of scope.
- Preserve the application's delegate and inset changes. No global swizzling.

## Swift and UIKit

- Four-space indentation. Use UpperCamelCase types and lowerCamelCase members.
- Owned subviews use `private lazy var` closure initialization. Injected views and
  protocol-facing read-only accessors are exceptions. Never initialize lazy views
  just to clean them up.
- Use relevant, nonempty MARK groups in this order: Public Properties, Private
  Properties, Views, Initialization, Lifecycle, Public Methods, View Setup,
  Actions, Private Methods. Put protocol conformances in separate extensions.
- Use concise, descriptive names: isRefreshing, hasMoreData, beginRefreshing.
- Document public declarations using `///`, including cancellation and ownership.
  Internal Chinese comments explain non-obvious behavior; do not narrate syntax.
- UIKit ownership and UI callbacks are MainActor-isolated. Cross-actor payloads
  conform to Sendable. Do not silence concurrency errors with unchecked Sendable.
- Avoid forced unwraps and try!. Prefer composition, private implementation, and
  the smallest useful public surface. No unnecessary open classes.
- Use system Auto Layout for child views and container geometry for refresh
  positioning. Never use the screen width to size a component.
- Detach is idempotent: cancel owned tasks, invalidate observers, restore only
  component-owned insets, and prevent stale completions or business callbacks.

## Verification and Delivery

- Read CONTRIBUTING.md before editing. Add focused behavioral tests for state,
  concurrency, layout and lifecycle changes. Never claim checks that did not run.
- Use Conventional Commits and codex/ feature branches. Do not merge or release.
- Keep each stage reviewable; dependent PRs must identify their base explicitly.
- Use pinned tools and CI; record unavailable iOS 16 runtime validation honestly.
- Core implementation is original; document conceptual references and retain
  upstream notices whenever code or substantial portions are reused.
