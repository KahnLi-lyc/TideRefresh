# Optional Lottie Adapter

This separate Swift package demonstrates `RefreshAnimator` with Lottie **4.5.2**,
pinned exactly. The core TideRefresh package and the default demo do not depend on
Lottie and do not download it.

Add `Examples/LottieDemo` as a local package in an iOS 16+ application and link its
`TideRefreshLottieDemo` product. Add a Lottie JSON animation that you own or are
licensed to redistribute to that application's bundle.

```swift
import Lottie
import TideRefresh
import TideRefreshLottieDemo

let animator = LottieRefreshAnimator(
    animation: LottieAnimation.named("Refresh", bundle: .main)
)
let refresh = try RefreshController(
    scrollView: tableView,
    headerAnimator: animator
)
refresh.setAsyncHandlers(refresh: { [weak model] in
    guard let model else { return .cancelled }
    try await model.refresh()
    return .success(hasMoreData: model.hasMoreData)
})
```

Create one animator per edge. Drag progress scrubs the animation, loading loops it,
and Reduce Motion keeps it still. Detach stops playback. Color changes in a Lottie
composition require that composition's own keypath/value-provider customization;
the adapter's theme configures only its hosting view.

Resolve and build this package separately from the core repository checks:

```sh
swift package --package-path Examples/LottieDemo resolve
xcodebuild -scheme TideRefreshLottieDemo -destination 'generic/platform=iOS Simulator' build
```

Run the `xcodebuild` command from `Examples/LottieDemo`, or open its `Package.swift`
in Xcode and select an iOS simulator. A macOS `swift build` is unsuitable because
both the core library and this adapter use UIKit.
