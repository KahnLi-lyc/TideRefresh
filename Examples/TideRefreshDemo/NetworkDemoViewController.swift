import TideRefresh
import UIKit

@MainActor
final class NetworkDemoViewController: UIViewController {
    // MARK: - Private Properties

    private var selectedScenario: NetworkScenario
    private var selectedDelay: NetworkDelay
    private var apiClient: DemoAPIClient
    private var items = [DemoItem]()
    private var refreshCount = 0
    private var pageCount = 0
    private var requestCount = 0
    private var completionCount = 0
    private var cancellationCount = 0
    private var lastStatusCode: Int?
    private var status = "Ready"
    private var loadID: UUID?
    private var refreshController: RefreshController?
    private lazy var pagination = makePagination()

    // MARK: - Views

    private lazy var scenarioButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "server.rack")
        configuration.imagePadding = 8
        configuration.imagePlacement = .leading
        configuration.titleAlignment = .leading
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "network-scenario-button"
        return button
    }()

    private lazy var delayButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "timer")
        configuration.imagePadding = 8
        configuration.imagePlacement = .leading
        configuration.titleAlignment = .leading
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "network-delay-button"
        return button
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.accessibilityIdentifier = "network-status"
        return label
    }()

    private lazy var controlsView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [scenarioButton, delayButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 20, bottom: 12, trailing: 20)
        return stack
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "The first page returned no items"
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "network-empty-state"
        label.isHidden = true
        return label
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        table.backgroundView = emptyLabel
        table.accessibilityIdentifier = "network-list"
        table.register(UITableViewCell.self, forCellReuseIdentifier: "network-item")
        return table
    }()

    // MARK: - Initialization

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        selectedScenario = Self.argument("--network-scenario", in: arguments)
            .flatMap(NetworkScenario.init(rawValue:)) ?? .success
        selectedDelay = Self.argument("--network-delay", in: arguments)
            .flatMap(NetworkDelay.init(rawValue:)) ?? .normal
        apiClient = DemoAPIClient(scenario: selectedScenario, delay: selectedDelay)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Network Scenarios"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        setUpViews()
        updateMenus()
        attachRefresh()
        updateStatus()
        refreshController?.beginRefreshing()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if parent == nil || isBeingDismissed || navigationController?.isBeingDismissed == true ||
            navigationController?.viewControllers.contains(self) == false
        {
            let client = apiClient
            loadID = nil
            refreshController?.detach()
            pagination.cancel()
            Task { await client.cancelRequests() }
        }
    }

    // MARK: - View Setup

    private func setUpViews() {
        view.addSubview(controlsView)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.topAnchor.constraint(equalTo: controlsView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
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
    }

    private func attachRefresh() {
        do {
            let controller = try RefreshController(
                scrollView: tableView,
                configuration: configuration(for: selectedScenario)
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
        guard loadID != nil else {
            updateMetrics()
            return
        }
        let client = apiClient
        status = "Cancelling"
        updateStatus()
        Task { [weak self] in
            let metrics = await client.cancelRequests()
            guard let self, client === apiClient else { return }
            loadID = nil
            refreshController?.cancel()
            pagination.cancel()
            status = "Cancelled"
            apply(metrics)
        }
    }

    @objc private func reset() {
        rebuildAndRefresh(clearItems: true)
    }

    // MARK: - Private Methods

    private func makePagination() -> PaginationCoordinator<DemoItem, Int> {
        PaginationCoordinator(loader: apiClient.load) { [weak self] update in
            self?.apply(update)
        }
    }

    private func perform(refresh: Bool) async throws -> RefreshResult {
        let id = UUID()
        let client = apiClient
        let coordinator = pagination
        loadID = id
        status = refresh ? "Refreshing" : "Loading more"
        updateStatus()
        scheduleAutomaticCancellationIfNeeded(refresh: refresh, client: client)
        do {
            let hasMore = try await (refresh ? coordinator.refresh() : coordinator.loadMore())
            guard loadID == id else { throw CancellationError() }
            loadID = nil
            status = hasMore ? "Updated" : "No more data"
            await readMetrics(from: client)
            monitorLateResponse(from: client)
            return .success(hasMoreData: hasMore)
        } catch is CancellationError {
            if loadID == id {
                loadID = nil
                status = "Cancelled"
                await readMetrics(from: client)
            }
            throw CancellationError()
        } catch let DemoAPIError.httpStatus(code) {
            if loadID == id {
                loadID = nil
                status = "Failed HTTP \(code)"
                await readMetrics(from: client)
            }
            throw DemoAPIError.httpStatus(code)
        } catch let error as URLError where error.code == .timedOut {
            if loadID == id {
                loadID = nil
                status = "Timed out"
                await readMetrics(from: client)
            }
            throw error
        } catch let error as URLError where error.code == .cancelled {
            if loadID == id {
                loadID = nil
                status = "Cancelled"
                await readMetrics(from: client)
            }
            throw CancellationError()
        } catch {
            if loadID == id {
                loadID = nil
                status = "Invalid JSON"
                await readMetrics(from: client)
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
        tableView.reloadData()
        emptyLabel.isHidden = !items.isEmpty
        updateStatus()
    }

    private func rebuildAndRefresh(clearItems: Bool) {
        loadID = nil
        refreshController?.detach()
        pagination.cancel()
        apiClient = DemoAPIClient(scenario: selectedScenario, delay: selectedDelay)
        pagination = makePagination()
        requestCount = 0
        completionCount = 0
        cancellationCount = 0
        lastStatusCode = nil
        if clearItems {
            items = []
            refreshCount = 0
            pageCount = 0
            tableView.reloadData()
            emptyLabel.isHidden = true
        }
        status = "Ready"
        attachRefresh()
        updateStatus()
        refreshController?.beginRefreshing()
    }

    private func select(_ scenario: NetworkScenario) {
        selectedScenario = scenario
        updateMenus()
        rebuildAndRefresh(clearItems: true)
    }

    private func select(_ delay: NetworkDelay) {
        selectedDelay = delay
        updateMenus()
        rebuildAndRefresh(clearItems: true)
    }

    private func updateMenus() {
        scenarioButton.configuration?.title = selectedScenario.title
        scenarioButton.menu = UIMenu(children: NetworkScenario.allCases.map { scenario in
            UIAction(title: scenario.title, state: scenario == selectedScenario ? .on : .off) { [weak self] _ in
                self?.select(scenario)
            }
        })
        delayButton.configuration?.title = selectedDelay.title
        delayButton.menu = UIMenu(children: NetworkDelay.allCases.map { delay in
            UIAction(title: delay.title, state: delay == selectedDelay ? .on : .off) { [weak self] _ in
                self?.select(delay)
            }
        })
    }

    private func updateMetrics() {
        let client = apiClient
        Task { [weak self] in
            guard let self else { return }
            await readMetrics(from: client)
        }
    }

    private func readMetrics(from client: DemoAPIClient) async {
        let metrics = await client.metrics()
        guard client === apiClient else { return }
        apply(metrics)
    }

    private func apply(_ metrics: NetworkMetrics) {
        requestCount = metrics.requestCount
        completionCount = metrics.completionCount
        cancellationCount = metrics.cancellationCount
        lastStatusCode = metrics.lastStatusCode
        updateStatus()
    }

    private func monitorLateResponse(from client: DemoAPIClient) {
        guard selectedScenario == .staleResponse,
              requestCount >= 3,
              completionCount < requestCount
        else { return }
        let expectedCount = requestCount
        Task { [weak self] in
            await client.waitForCompletionCount(expectedCount)
            guard let self else { return }
            await readMetrics(from: client)
        }
    }

    private func scheduleAutomaticCancellationIfNeeded(refresh: Bool, client: DemoAPIClient) {
        guard !refresh,
              ProcessInfo.processInfo.arguments.contains("--network-auto-cancel")
        else { return }
        Task { [weak self] in
            await client.waitForRequestCount(2)
            guard let self, client === apiClient, loadID != nil else { return }
            cancel()
        }
    }

    private func updateStatus() {
        let code = lastStatusCode.map(String.init) ?? "-"
        statusLabel.text = "\(status) · HTTP: \(code) · Requests: \(requestCount) · Completed: \(completionCount) · Cancels: \(cancellationCount) · Items: \(items.count) · Refreshes: \(refreshCount) · Pages: \(pageCount)"
    }

    private func configuration(for scenario: NetworkScenario) -> RefreshConfiguration {
        RefreshConfiguration(shortContentPageLimit: scenario == .short ? 2 : 0)
    }

    private func action(_ symbol: String, label: String, id: String, selector: Selector) -> UIBarButtonItem {
        let button = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: selector)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = id
        return button
    }

    private static func argument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

extension NetworkDemoViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "network-item", for: indexPath)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = item.subtitle
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: item.symbol)
        content.imageProperties.tintColor = .systemTeal
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "network-item-\(item.id)"
        return cell
    }
}
