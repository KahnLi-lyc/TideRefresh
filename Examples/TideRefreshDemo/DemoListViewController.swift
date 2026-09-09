import TideRefresh
import UIKit

@MainActor
final class DemoListViewController: UIViewController {
    // MARK: - Private Properties

    private let mode: DemoMode
    private let loader: DemoLoader
    private var items = [DemoItem]()
    private var refreshCount = 0
    private var pageCount = 0
    private var status = "Ready"
    private var loadID: UUID?
    private var refreshController: RefreshController?
    private var collectionDataSource: UICollectionViewDiffableDataSource<Int, Int>?
    private lazy var pagination = PaginationCoordinator<DemoItem, Int>(loader: loader.load) { [weak self] update in
        self?.apply(update)
    }

    // MARK: - Views

    private lazy var failureSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.accessibilityIdentifier = "failures-toggle"
        toggle.accessibilityLabel = "Simulate failures"
        toggle.addTarget(self, action: #selector(failuresChanged), for: .valueChanged)
        return toggle
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.accessibilityIdentifier = "demo-status"
        return label
    }()

    private lazy var controlsView: UIStackView = {
        let label = UILabel()
        label.text = "Simulate failures"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [label, failureSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let stack = UIStackView(arrangedSubviews: [row, statusLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 20, bottom: 12, trailing: 20)
        return stack
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 100
        table.accessibilityIdentifier = "demo-list"
        table.register(UITableViewCell.self, forCellReuseIdentifier: "item")
        return table
    }()

    private lazy var collectionView: UICollectionView = {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.showsSeparators = true
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .systemGroupedBackground
        collection.delegate = self
        collection.accessibilityIdentifier = "demo-list"
        return collection
    }()

    // MARK: - Initialization

    init(mode: DemoMode) {
        self.mode = mode
        let arguments = ProcessInfo.processInfo.arguments
        loader = DemoLoader(pageSize: mode == .short ? 3 : 20,
                            holdsSubsequentRefreshes: arguments.contains("--hold-refresh"))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        setUpViews()
        attachRefresh()
        updateStatus()
        refreshController?.beginRefreshing()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 普通详情页跳转保留请求；离开示例导航栈时才释放挂载和业务任务。
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            loadID = nil
            refreshController?.detach()
            pagination.cancel()
        }
    }

    // MARK: - View Setup

    private func setUpViews() {
        view.addSubview(controlsView)
        let scrollView: UIScrollView = mode == .collection ? collectionView : tableView
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.topAnchor.constraint(equalTo: controlsView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        toolbarItems = [
            action("arrow.clockwise", label: "Refresh", id: "refresh-button", selector: #selector(refresh)),
            UIBarButtonItem(systemItem: .flexibleSpace),
            action("xmark.circle", label: "Cancel", id: "cancel-button", selector: #selector(cancel)),
            UIBarButtonItem(systemItem: .flexibleSpace),
            action("arrow.counterclockwise", label: "Reset", id: "reset-button", selector: #selector(reset)),
            UIBarButtonItem(systemItem: .flexibleSpace),
            action("arrow.down.to.line", label: "Load more", id: "load-more-button", selector: #selector(loadMore)),
        ]
        if mode == .collection { setUpCollection() }
    }

    private func setUpCollection() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, DemoItem> { cell, _, item in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = item.title
            content.secondaryText = item.subtitle
            content.secondaryTextProperties.numberOfLines = 0
            content.image = UIImage(systemName: item.symbol)
            content.imageProperties.tintColor = .systemTeal
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
            cell.accessibilityIdentifier = "item-\(item.id)"
        }
        collectionDataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            [weak self] collectionView, indexPath, id in
            guard let item = self?.items.first(where: { $0.id == id }) else { return nil }
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    private func attachRefresh() {
        do {
            let scrollView: UIScrollView = mode == .collection ? collectionView : tableView
            let animator: (any RefreshAnimator)? = mode == .frames
                ? FrameRefreshAnimator(frames: makeFrames()) : nil
            let controller = try RefreshController(
                scrollView: scrollView,
                configuration: .init(loadMoreMode: mode.footerMode),
                headerAnimator: animator
            )
            controller.setAsyncHandlers(
                refresh: { [weak self] in
                    guard let self else { return .cancelled }
                    return try await self.perform(refresh: true)
                },
                loadMore: { [weak self] in
                    guard let self else { return .cancelled }
                    return try await self.perform(refresh: false)
                }
            )
            refreshController = controller
        } catch {
            status = "Attachment failed"
        }
    }

    // MARK: - Actions

    @objc private func refresh() {
        refreshController?.beginRefreshing()
    }

    @objc private func loadMore() {
        refreshController?.beginLoadingMore()
    }

    @objc private func cancel() {
        loadID = nil
        refreshController?.cancel()
        pagination.cancel()
        status = "Cancelled"
        updateStatus()
    }

    @objc private func reset() {
        loadID = nil
        refreshController?.cancel()
        pagination.cancel()
        failureSwitch.setOn(false, animated: true)
        refreshController?.resetPagination()
        refreshController?.beginRefreshing()
    }

    @objc private func failuresChanged() {
        status = failureSwitch.isOn ? "Failures on" : "Failures off"
        updateStatus()
    }

    // MARK: - Private Methods

    private func perform(refresh: Bool) async throws -> RefreshResult {
        let id = UUID()
        loadID = id
        status = refresh ? "Refreshing" : "Loading more"
        updateStatus()
        do {
            await loader.setFailuresEnabled(failureSwitch.isOn)
            try Task.checkCancellation()
            let hasMore = try await (refresh ? pagination.refresh() : pagination.loadMore())
            guard loadID == id else { throw CancellationError() }
            loadID = nil
            status = hasMore ? "Updated" : "No more data"
            updateStatus()
            return .success(hasMoreData: hasMore)
        } catch is CancellationError {
            // 旧任务只结束自身，不能覆盖新请求或离开页面后的状态。
            if loadID == id {
                loadID = nil
                status = "Cancelled"
                updateStatus()
            }
            throw CancellationError()
        } catch {
            if loadID == id {
                loadID = nil
                status = "Failed"
                updateStatus()
            }
            throw error
        }
    }

    private func apply(_ update: PaginationUpdate<DemoItem>) {
        switch update {
        case let .replace(values):
            items = values
            refreshCount += 1
            pageCount = 1
        case let .append(values):
            items += values
            pageCount += 1
        }
        if mode == .collection {
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            snapshot.appendItems(items.map(\.id))
            let previous = Set(collectionDataSource?.snapshot().itemIdentifiers ?? [])
            snapshot.reconfigureItems(items.map(\.id).filter { previous.contains($0) })
            collectionDataSource?.apply(snapshot, animatingDifferences: false)
        } else {
            tableView.reloadData()
        }
        updateStatus()
    }

    private func updateStatus() {
        statusLabel.text = "\(status) · Items: \(items.count) · Refreshes: \(refreshCount) · Pages: \(pageCount)"
    }

    private func action(_ symbol: String, label: String, id: String, selector: Selector) -> UIBarButtonItem {
        let button = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: selector)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = id
        return button
    }

    private func makeFrames() -> [UIImage] {
        guard let symbol = UIImage(systemName: "arrow.triangle.2.circlepath") else { return [] }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return (0 ..< 12).map { index in
            renderer.image { context in
                context.cgContext.translateBy(x: 16, y: 16)
                context.cgContext.rotate(by: CGFloat(index) * .pi / 6)
                symbol.withTintColor(.systemTeal, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: -12, y: -12, width: 24, height: 24))
            }
        }
    }

    private func showDetail(_ item: DemoItem) {
        navigationController?.pushViewController(DemoDetailViewController(item: item), animated: true)
    }
}

extension DemoListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = item.subtitle
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: item.symbol)
        content.imageProperties.tintColor = .systemTeal
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "item-\(item.id)"
        return cell
    }
}

extension DemoListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showDetail(items[indexPath.row])
    }
}

extension DemoListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = collectionDataSource?.itemIdentifier(for: indexPath),
              let item = items.first(where: { $0.id == id }) else { return }
        showDetail(item)
    }
}
