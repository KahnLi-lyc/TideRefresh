# TideRefresh

[English](README.md)

面向 iOS/iPadOS 16+ 的 Swift 6 UIKit 刷新与分页组件，支持纵向
`UIScrollView`、`UITableView` 和 `UICollectionView`。通过 Swift Package Manager
集成，**核心库零第三方依赖**。支持下拉刷新、上拉/自动/预加载分页、有上限的短内容补页、
async 和回调式取消，以及可替换的动画。不会替换业务的滚动代理，也不使用全局 swizzling。
数据数组和数据源仍由应用管理。

## 当前状态与安装

最新预发布版本为 **0.1.0-beta.1**。当前分支准备尚未发布的
**0.1.0-beta.2** 网络 Demo 候选版本，不修改公共 API。在 Xcode 的
Add Package Dependencies 中添加仓库，或使用：

```swift
dependencies: [
    .package(
        url: "https://github.com/KahnLi-lyc/TideRefresh.git",
        exact: "0.1.0-beta.1"
    ),
]
```

在目标的依赖中添加 `.product(name: "TideRefresh", package: "TideRefresh")`。
只有在明确测试未发布变更时才依赖 `main`。应用应提交解析后的依赖版本以便复现。

要求 Swift 6.0 兼容语法、UIKit、iOS/iPadOS 16+。当前不覆盖横向滚动、倒置聊天列表、
嵌套滚动仲裁、SwiftUI、macOS 和 Mac Catalyst。

## async 刷新与游标分页

下面的完整控制器读取 JSON：
`{"items":[{"id":1,"title":"First"}],"nextCursor":"page-2"}`。
通过 `FeedViewController(endpoint:)` 传入实际接口地址。最后一页应返回 `null` 或省略
`nextCursor`。集合视图可沿用同样的协调器，只需将 `onUpdate` 中的数据源更新替换成集合
视图或 diffable data source 的实现。

```swift
import Foundation
import UIKit
import TideRefresh

struct FeedItem: Decodable, Sendable {
    let id: Int
    let title: String
}

private struct FeedResponse: Decodable, Sendable {
    let items: [FeedItem]
    let nextCursor: String?
}

@MainActor
final class FeedViewController: UITableViewController {
    private let endpoint: URL
    private var items: [FeedItem] = []
    private var refreshController: RefreshController?
    private var pagination: PaginationCoordinator<FeedItem, String>?

    init(endpoint: URL) {
        self.endpoint = endpoint
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let endpoint = endpoint
        pagination = PaginationCoordinator(
            loader: { request in
                guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                    throw URLError(.badURL)
                }
                if case let .nextPage(cursor) = request {
                    components.queryItems = (components.queryItems ?? []) + [
                        URLQueryItem(name: "cursor", value: cursor),
                    ]
                }
                guard let url = components.url else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let page = try JSONDecoder().decode(FeedResponse.self, from: data)
                return Page(items: page.items, nextCursor: page.nextCursor)
            },
            onUpdate: { [weak self] update in
                guard let self else { return }
                switch update {
                case let .replace(items): self.items = items
                case let .append(items): self.items.append(contentsOf: items)
                }
                self.tableView.reloadData()
            }
        )

        do {
            let controller = try RefreshController(scrollView: tableView)
            refreshController = controller
            controller.setAsyncHandlers(
                refresh: { [weak self] in
                    guard let pagination = self?.pagination else { return .cancelled }
                    let hasMore = try await pagination.refresh()
                    return .success(hasMoreData: hasMore)
                },
                loadMore: { [weak self] in
                    guard let pagination = self?.pagination else { return .cancelled }
                    let hasMore = try await pagination.loadMore()
                    return .success(hasMoreData: hasMore)
                }
            )
            controller.beginRefreshing()
        } catch {
            assertionFailure("Refresh attachment failed: \(error)")
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item")
            ?? UITableViewCell(style: .default, reuseIdentifier: "Item")
        var content = cell.defaultContentConfiguration()
        content.text = items[indexPath.row].title
        cell.contentConfiguration = content
        return cell
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshController?.cancel()
        pagination?.cancel()
    }
}
```

必须**先安装 handler，再调用 `beginRefreshing()`**。刷新控制器的 async handler 返回
`RefreshResult`，协调器的 `refresh()` / `loadMore()` 返回是否还有下一页的 `Bool`，
两者通过 `.success(hasMoreData:)` 连接。普通错误进入失败状态；`CancellationError`
以及任务取消不会显示失败。

`PaginationCoordinator<Item, Cursor>` 的两个泛型参数都必须满足 `Sendable`，loader
是 `@Sendable` 闭包。请求类型 `PaginationRequest<Cursor>` 使用 `.refresh` 表示第一页，
使用 `.nextPage(cursor)` 表示下一页。接口返回 `Page<Item, Cursor>`。

`onUpdate` **同步运行在 MainActor**：在 `.replace` 中替换业务数组，在 `.append` 中追加，
随后更新视图。不要另起 `Task` 延迟修改数组，否则会破坏提交顺序。耗时网络操作放在 loader。
协调器只保存游标和请求状态，不持有业务列表。

刷新会取消旧请求，即使旧 loader 忽略取消，过期响应也不会更新游标或触发 `onUpdate`。
失败保留已提交游标，便于重试。加载中重复调用 `loadMore()` 会立即返回当前可用性，
不会新建请求，也不会等待当前请求。首次刷新成功前和分页结束后，`loadMore()` 直接返回
`false`。空页也可以携带下一页游标，是否结束由游标决定。

## 回调式网络接口

已有回调式接口可以使用 `onRefresh` / `onLoadMore`。每次收到一个独立的
`RefreshOperation`，完成时调用 `finish`，在 `onCancel` 中取消底层工作。
下面的适配器可直接用于 URLSession；传入的 `onData` 如果引用页面，应使用弱捕获。

```swift
import Foundation
import TideRefresh

@MainActor
private final class RequestLifetime {
    var isCancelled = false
}

@MainActor
func installCallbackRefresh(
    on controller: RefreshController,
    url: URL,
    onData: @escaping @MainActor (Data) -> Void
) {
    controller.onRefresh = { operation in
        let lifetime = RequestLifetime()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            Task { @MainActor in
                guard !lifetime.isCancelled else { return }
                if let error = error as? URLError, error.code == .cancelled {
                    operation.finish(.cancelled)
                } else if error == nil, let data,
                          let response = response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode) {
                    onData(data)
                    operation.finish(.success(hasMoreData: false))
                } else {
                    operation.finish(.failure)
                }
            }
        }
        operation.onCancel = {
            lifetime.isCancelled = true
            task.cancel()
        }
        task.resume()
    }
    controller.beginRefreshing()
}
```

`finish` 是一次性的；取消后或重复完成的调用会被忽略。但控制器无法撤销回调自行执行的
业务数据修改，所以示例在 `onData` 前检查请求生命周期。所有 UI 更新都需回到 MainActor。

## 分页模式、失败与短内容

```swift
let configuration = RefreshConfiguration(
    headerHeight: 60,
    footerHeight: 44,
    loadMoreMode: .prefetch(distance: 240),
    isHapticsEnabled: true,
    shortContentPageLimit: 2
)
let controller = try RefreshController(
    scrollView: collectionView,
    configuration: configuration
)
```

| 配置或结果 | 行为 |
| --- | --- |
| `.pull` | 向上拉过 footer 阈值并松手后加载。 |
| `.automatic`（默认） | 拖动或减速滚动到内容底部时加载。 |
| `.prefetch(distance:)` | 滚动进入底部指定距离内时预加载。 |
| `.success(hasMoreData: false)` | 显示没有更多数据，停止下一页请求。 |
| `.failure` | 停止加载；失败 footer 可点击重试。 |
| `.cancelled` | 结束操作，不显示失败。 |

短内容默认不会连续自动请求，`shortContentPageLimit` 默认为 `0`。设为正数后，成功操作
完成且内容不足一屏时，最多追加指定次数的补页；空页同样消耗预算。失败、取消、无更多数据
或预算用尽都会停止。刷新重置预算。`resetPagination(hasMoreData:)` 重置展示层的分页
可用性与预算，**不会清除协调器游标**；切换筛选条件或查询时应重新刷新协调器。
也可手动调用 `beginLoadingMore()`。

## 生命周期、所有权与 Insets

控制器和动画 API 都隔离在 MainActor。滚动视图强持有已挂载的控制器，控制器弱持有滚动
视图。handler 和协调器回调会被保留，引用拥有它们的页面时应弱捕获。重复刷新不会新建
并行刷新；刷新可取消正在进行的分页。`cancel()` 取消当前操作并保留控件；`detach()`
可重复调用，会取消组件任务、移除观察者和子视图、停止动画，并仅移除组件自己的 inset 增量。

同一滚动视图重复挂载会抛出 `.alreadyAttached`。动画视图共享或已经有父视图时抛出
`.sharedAnimatorView`。替换组件前先 detach，每个边缘使用独立动画实例和视图。

组件使用 `adjustedContentInset` 计算边界，使用容器宽度布局，适应 iPad 和分屏。
宿主改变 inset 时按增量修改，例如 `tableView.contentInset.bottom += keyboardDelta`，
组件移除自己的增量时会保留宿主变化。绝对赋值表示包含组件当前贡献在内的总 inset；
组件无法从赋值本身推断调用者是否打算包含这部分贡献。

## 主题、动画与辅助功能

`DefaultRefreshAnimator` 包含箭头、系统加载指示器、状态文字和可选的 `lastUpdated`
时间；时间不持久化。`FrameRefreshAnimator(frames:duration:)` 接收应用提供的 `UIImage`
序列，不负责 GIF 解码。`configure(theme:strings:)` 更新颜色和自定义文字。内置英文、
简体中文随应用本地化选择，支持 Dynamic Type、VoiceOver 操作与公告、减少动态效果、
可关闭的阈值触觉反馈。

自定义动画通过独立 extension 实现协议，示例可直接用于 `headerAnimator:`：

```swift
import UIKit
import TideRefresh

@MainActor
final class SpinnerAnimator {
    private lazy var spinner = UIActivityIndicatorView(style: .medium)
}

extension SpinnerAnimator: RefreshAnimator {
    var view: UIView { spinner }

    func configure(theme: RefreshTheme, strings: RefreshStrings) {
        spinner.color = theme.tintColor
        spinner.accessibilityLabel = strings.refreshing
    }

    func update(state: RefreshState, progress: CGFloat) {
        state == .loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    func stop() { spinner.stopAnimating() }
}
```

拖动 `progress` 可超过 `1`，索引动画帧时应先限制范围。自定义动画应提供适当的辅助功能
说明并遵循 Reduce Motion。`stop()` 在 detach 时释放临时动画资源。

[可选 Lottie 适配器](Examples/LottieDemo/README.md) 是独立示例包，精确依赖 Lottie
**4.5.2**。将 `Examples/LottieDemo` 作为本地 package 加入 iOS 应用，链接
`TideRefreshLottieDemo`，再提供有使用权限的 JSON 动画。核心库和默认 demo 不依赖 Lottie。

## Demo 与验证

打开 `Examples/TideRefreshDemo.xcodeproj`，选择 `TideRefreshDemo`，可在 iPhone、
iPad、模拟器或真机运行。七个页面覆盖列表、网格、短内容补页、上拉 footer、预加载、
序列帧、可控失败及 **Network Scenarios**。

Network Scenarios 使用真实的临时 `URLSession` 发起请求，由本地 `URLProtocol` Mock
返回 HTTP 响应，不访问公网。可选择场景和延迟，并通过工具栏执行刷新、加载更多、取消、
重置。状态区显示 HTTP 状态、请求数、完成数、取消数、项目数、刷新数和页数。场景覆盖空页、短页、
无更多数据、HTTP 500/503、footer 点击重试、超时、错误 JSON，以及刷新抢占慢分页。

| iPhone 列表 | iPad 网格 |
| --- | --- |
| ![iPhone 列表 Demo](docs/images/iphone-table.png) | ![iPad 网格 Demo](docs/images/ipad-collection.png) |

![网络场景 Demo](docs/images/network-scenarios.png)

```sh
xcodebuild -showdestinations -project Examples/TideRefreshDemo.xcodeproj -scheme TideRefreshDemo
bash scripts/verify.sh build 'generic/platform=iOS Simulator'
bash scripts/verify.sh test 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
bash scripts/verify.sh test 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=latest'
```

多版本 Xcode 可通过 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 选择。
设备名或 UUID 需匹配本机已安装的模拟器。UIKit 不支持直接在 macOS 上 `swift build`。
测试结果位于 `.build/DerivedData/Logs/Test`。CI 配置包含 Swift 6.0 基线编译、iPhone/iPad
模拟器测试，以及 SwiftFormat **0.61.1** lint。

已提交的工程可通过开发专用 Ruby 工具 `xcodeproj` **1.28.1** 重新生成：

```sh
gem install xcodeproj -v 1.28.1
ruby -e 'gem "xcodeproj", "1.28.1"; load "scripts/generate-project.rb"'
```

当前分支证据：Xcode 27 beta 使用 Swift 6 模式编译通过。在 iPhone 16 / iOS 18.2 与
iPad Pro 11-inch (M4) / iPadOS 18.5 上，40 个 XCTest 和 16 个 UI 场景全部通过。
最终 Mock 传输层重构后，10 个 API 客户端测试与 6 个网络 UI 场景也已定向重跑通过。
SwiftFormat 和空白检查通过。Xcode 16.2 基线及 Xcode 26.6 CI 结果记录在本次 PR。

自动化覆盖可访问控件、窗口尺寸变化和方向变化；人工 VoiceOver、真机分屏/Stage Manager
仍待检查。强制深色模式的大字体截图已人工查看，见[验证报告](docs/verification.md)；DocC 已编译成功。
**iOS 16 真正运行验证仍待完成，是 1.0 发布门槛**；部署目标设置为 16.0 不等于验证了该运行环境。

更多信息：[迁移指南](docs/migration.md)、[发布检查表](docs/release-checklist.md)、
[变更记录](CHANGELOG.md)、[贡献说明](CONTRIBUTING.md)、[参考与来源](docs/references.md)。
采用 [MIT 许可证](LICENSE)。
