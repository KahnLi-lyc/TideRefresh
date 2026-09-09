import Foundation
import TideRefresh

enum DemoMode: String, CaseIterable {
    case table
    case collection
    case short
    case pull
    case prefetch
    case frames
    case network

    var title: String {
        switch self {
        case .table: "Table"
        case .collection: "Collection"
        case .short: "Short Content"
        case .pull: "Pull Footer"
        case .prefetch: "Prefetch Footer"
        case .frames: "Frame Animation"
        case .network: "Network Scenarios"
        }
    }

    var symbol: String {
        switch self {
        case .table: "list.bullet.rectangle"
        case .collection: "square.grid.2x2"
        case .short: "rectangle.compress.vertical"
        case .pull: "arrow.up.to.line"
        case .prefetch: "arrow.down.forward.and.arrow.up.backward"
        case .frames: "photo.stack"
        case .network: "network"
        }
    }

    var footerMode: LoadMoreMode {
        switch self {
        case .pull: .pull
        case .prefetch: .prefetch(distance: 240)
        default: .automatic
        }
    }
}

struct DemoItem: Codable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let symbol: String
}

actor DemoLoader {
    private let pageSize: Int
    private let delay: Duration
    private let holdsSubsequentRefreshes: Bool
    private var failuresEnabled = false
    private var revision = 0

    init(pageSize: Int, delay: Duration = .milliseconds(300), holdsSubsequentRefreshes: Bool = false) {
        self.pageSize = pageSize
        self.delay = delay
        self.holdsSubsequentRefreshes = holdsSubsequentRefreshes
    }

    func setFailuresEnabled(_ enabled: Bool) {
        failuresEnabled = enabled
    }

    func load(_ request: PaginationRequest<Int>) async throws -> Page<DemoItem, Int> {
        let shouldFail = failuresEnabled
        if holdsSubsequentRefreshes, revision > 0, case .refresh = request {
            // UI 取消测试使用可取消的等待，不依赖 XCTest 点击耗时和固定延迟。
            let cancellationGate = AsyncStream<Void> { _ in }
            for await _ in cancellationGate {}
            try Task.checkCancellation()
        }
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        if shouldFail { throw DemoFailure.unavailable }
        let page: Int
        switch request {
        case .refresh:
            page = 0
            revision += 1
        case let .nextPage(cursor):
            page = cursor
        }
        let subjects = [
            ("Architecture", "building.2", "Materials, spaces, and the details that shape a city."),
            ("Photography", "camera", "A field journal of light and everyday observations. New notes from today's collection."),
            ("Typography", "textformat", "Letters, rhythm, and the craft of clear communication."),
            ("Travel", "map", "Routes and places collected along the way."),
            ("Music", "music.note", "Listening notes from the studio, with a selection of recent recordings and performances."),
        ]
        let items = (0 ..< pageSize).map { offset in
            let id = page * pageSize + offset
            let subject = subjects[id % subjects.count]
            return DemoItem(
                id: id,
                title: "\(subject.0) \(id + 1)",
                subtitle: "\(subject.2) Edition \(revision).",
                symbol: subject.1
            )
        }
        return Page(items: items, nextCursor: page < 2 ? page + 1 : nil)
    }
}

private enum DemoFailure: Error {
    case unavailable
}
