import UIKit

private enum RefreshRole: Equatable {
    case refresh
    case loadMore
}

/// Attachment fails when another controller already owns the scroll view.
public enum RefreshAttachmentError: Error {
    case alreadyAttached
    case sharedAnimatorView
}

/// Attaches refresh controls without replacing the host scroll delegate.
///
/// The scroll view retains its controller. Keep callbacks weak with respect to their
/// owner. Call `detach()` to remove controls, or `cancel()` when leaving a page.
@MainActor
public final class RefreshController: NSObject {
    // MARK: - Public Properties

    public typealias Handler = @MainActor (RefreshOperation) -> Void
    public typealias AsyncHandler = @MainActor () async throws -> RefreshResult

    public private(set) var headerState: RefreshState = .idle
    public private(set) var footerState: RefreshState = .idle
    public private(set) var hasMoreData = true
    public var isRefreshing: Bool {
        operation?.edge == refreshEdge
    }

    public var isLoadingMore: Bool {
        operation?.edge == loadMoreEdge
    }

    public var isAttached: Bool {
        scrollView != nil && attached
    }

    public private(set) weak var scrollView: UIScrollView?
    public var onRefresh: Handler? {
        didSet { if attached { layoutControls() } }
    }

    public var onLoadMore: Handler? {
        didSet { if attached { updateFooterInset(); layoutControls() } }
    }

    // MARK: - Private Properties

    private static var associationKey: UInt8 = 0
    private let axis: RefreshAxis
    private let layoutDirection: UIUserInterfaceLayoutDirection
    private let configuration: RefreshConfiguration
    private let headerAnimator: any RefreshAnimator
    private let footerAnimator: any RefreshAnimator
    private var strings: RefreshStrings
    private var observations: [NSKeyValueObservation] = []
    private var operation: RefreshOperation?
    private var task: Task<Void, Never>?
    /// Internal completion barrier used by deterministic cancellation regression tests.
    var activeTask: Task<Void, Never>? {
        task
    }

    private var operationID: UUID?
    private var refreshPull = PullStateMachine()
    private var loadMorePull = PullStateMachine()
    private var ownedStart: CGFloat = 0
    private var ownedEnd: CGFloat = 0
    private var modifyingInsets = false
    private var attached = false
    private var automaticArmed = true
    private var shortContentPages = 0
    private var fillGeneration = UUID()
    private var fillEnabled = false
    private var fillScheduled = false
    private var isLayingOut = false
    private var isCancelling = false
    private var originalBounce = false
    private var originalAccessibilityActions: [UIAccessibilityCustomAction]?
    private var refreshAction: UIAccessibilityCustomAction?
    private var loadAction: UIAccessibilityCustomAction?

    // MARK: - Views

    private lazy var headerView = makeHost(for: headerAnimator)
    private lazy var footerView = makeHost(for: footerAnimator)

    // MARK: - Initialization

    /// Attaches one controller. Custom animators must each supply a distinct, unparented view.
    ///
    /// Horizontal attachment resolves leading and trailing from the scroll view's effective
    /// layout direction at initialization. Detach and reattach after changing that direction.
    public init(
        scrollView: UIScrollView,
        axis: RefreshAxis = .vertical,
        configuration: RefreshConfiguration = .init(),
        headerAnimator: (any RefreshAnimator)? = nil,
        footerAnimator: (any RefreshAnimator)? = nil,
        theme: RefreshTheme = .init(),
        strings: RefreshStrings = .init(),
        onRefresh: Handler? = nil,
        onLoadMore: Handler? = nil
    ) throws {
        guard objc_getAssociatedObject(scrollView, &Self.associationKey) == nil else {
            throw RefreshAttachmentError.alreadyAttached
        }
        let refreshEdge: RefreshEdge = axis == .vertical ? .top : .leading
        let loadMoreEdge: RefreshEdge = axis == .vertical ? .bottom : .trailing
        let header: any RefreshAnimator = if let headerAnimator {
            headerAnimator
        } else if axis == .horizontal {
            RingRefreshAnimator(edge: refreshEdge)
        } else {
            DefaultRefreshAnimator(edge: refreshEdge)
        }
        let footer: any RefreshAnimator = if let footerAnimator {
            footerAnimator
        } else if axis == .horizontal {
            RingRefreshAnimator(edge: loadMoreEdge)
        } else {
            DefaultRefreshAnimator(edge: loadMoreEdge)
        }
        guard header.view !== footer.view, header.view.superview == nil, footer.view.superview == nil else {
            throw RefreshAttachmentError.sharedAnimatorView
        }
        self.scrollView = scrollView
        self.axis = axis
        layoutDirection = scrollView.effectiveUserInterfaceLayoutDirection
        self.configuration = configuration
        self.headerAnimator = header
        self.footerAnimator = footer
        self.strings = strings
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        super.init()
        originalBounce = axis == .vertical ? scrollView.alwaysBounceVertical : scrollView.alwaysBounceHorizontal
        if axis == .vertical {
            scrollView.alwaysBounceVertical = true
        } else {
            scrollView.alwaysBounceHorizontal = true
        }
        attached = true
        objc_setAssociatedObject(scrollView, &Self.associationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        configure(theme: theme, strings: strings)
        scrollView.addSubview(headerView)
        scrollView.addSubview(footerView)
        footerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryFooter)))
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
        installAccessibility()
        installObservers(scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        updateFooterInset()
        layoutControls()
    }

    // MARK: - Lifecycle

    deinit { task?.cancel() }

    // MARK: - Public Methods

    /// Installs structured async handlers. Results auto-finish; errors display retry state.
    public func setAsyncHandlers(refresh: AsyncHandler?, loadMore: AsyncHandler? = nil) {
        if let refresh {
            onRefresh = { [weak self] operation in self?.run(refresh, operation: operation) }
        } else { onRefresh = nil }
        if let loadMore {
            onLoadMore = { [weak self] operation in self?.run(loadMore, operation: operation) }
        } else { onLoadMore = nil }
    }

    /// Starts refresh and cancels pagination. A refresh already in progress is not duplicated.
    public func beginRefreshing() {
        begin(.refresh)
    }

    /// Starts a page request if attached, idle, and more data is available.
    public func beginLoadingMore() {
        begin(.loadMore)
    }

    /// Cancels the current operation without displaying an error or changing pagination availability.
    public func cancel() {
        guard !isCancelling else { return }
        isCancelling = true
        let previous = operation
        operation = nil
        operationID = nil
        fillGeneration = UUID()
        fillEnabled = false
        fillScheduled = false
        task?.cancel()
        task = nil
        refreshPull = PullStateMachine()
        loadMorePull = PullStateMachine()
        setStartInset(0)
        setState(.idle, role: .refresh)
        setState(hasMoreData ? .idle : .noMoreData, role: .loadMore)
        isCancelling = false
        // 先清理本次状态，再通知业务；取消回调可能同步发起新操作。
        previous?.invalidate()
    }

    /// Makes pagination available again and resets the bounded short-content fill budget.
    public func resetPagination(hasMoreData: Bool = true) {
        self.hasMoreData = hasMoreData
        fillGeneration = UUID()
        fillScheduled = false
        shortContentPages = 0
        automaticArmed = true
        if !isLoadingMore { setState(hasMoreData ? .idle : .noMoreData, role: .loadMore) }
        scheduleShortContentFill()
    }

    /// Reapplies the built-in/custom animator theme and current localized strings.
    public func configure(theme: RefreshTheme, strings: RefreshStrings = .init()) {
        self.strings = strings
        headerAnimator.configure(theme: theme, strings: strings)
        footerAnimator.configure(theme: theme, strings: strings)
        refreshAction?.name = strings.pullToRefresh
        loadAction?.name = strings.loadMore
        layoutControls()
    }

    /// Removes the controls and their observations. Safe to call repeatedly.
    public func detach() {
        guard attached, let scrollView else { return }
        attached = false
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        NotificationCenter.default.removeObserver(self)
        scrollView.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
        cancel()
        setEndInset(0)
        headerAnimator.stop()
        footerAnimator.stop()
        headerView.removeFromSuperview()
        footerView.removeFromSuperview()
        if axis == .vertical {
            scrollView.alwaysBounceVertical = originalBounce
        } else {
            scrollView.alwaysBounceHorizontal = originalBounce
        }
        // 保留业务在挂载之后新增的辅助功能操作。
        scrollView.accessibilityCustomActions = scrollView.accessibilityCustomActions?.filter {
            $0 !== refreshAction && $0 !== loadAction
        }
        objc_setAssociatedObject(scrollView, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        self.scrollView = nil
        onRefresh = nil
        onLoadMore = nil
    }

    // MARK: - View Setup

    private func makeHost(for animator: any RefreshAnimator) -> UIView {
        let host = UIView()
        let view = animator.view
        host.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return host
    }

    private func layoutControls() {
        guard attached, !isLayingOut, let scrollView else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let inset = baseInsets
        let headerExtent = effectiveHeaderHeight
        let footerExtent = effectiveFooterHeight
        if axis == .vertical {
            let width = max(0, scrollView.bounds.width - inset.left - inset.right)
            headerView.frame = CGRect(x: inset.left, y: -headerExtent, width: width, height: headerExtent)
            footerView.frame = CGRect(
                x: inset.left,
                y: max(scrollView.contentSize.height, geometry?.viewportLengthMinusInsets ?? 0),
                width: width,
                height: footerExtent
            )
        } else {
            let height = max(0, scrollView.bounds.height - inset.top - inset.bottom)
            let contentEnd = max(scrollView.contentSize.width, geometry?.viewportLengthMinusInsets ?? 0)
            let lowerFrame = CGRect(x: -footerExtent, y: inset.top, width: footerExtent, height: height)
            let upperFrame = CGRect(x: contentEnd, y: inset.top, width: headerExtent, height: height)
            if isReversed {
                headerView.frame = upperFrame
                footerView.frame = lowerFrame
            } else {
                headerView.frame = CGRect(x: -headerExtent, y: inset.top, width: headerExtent, height: height)
                footerView.frame = CGRect(x: contentEnd, y: inset.top, width: footerExtent, height: height)
            }
        }
        footerView.isHidden = onLoadMore == nil
        headerView.isHidden = onRefresh == nil
        if ownedStart > 0, ownedStart != headerExtent { setStartInset(headerExtent) }
        if onLoadMore != nil, ownedEnd != footerExtent { setEndInset(footerExtent) }
    }

    private var effectiveHeaderHeight: CGFloat {
        max(configuration.validHeaderHeight, UIFontMetrics.default.scaledValue(for: 44))
    }

    private var effectiveFooterHeight: CGFloat {
        max(configuration.validFooterHeight, UIFontMetrics.default.scaledValue(for: 44))
    }

    private func installAccessibility() {
        guard let scrollView else { return }
        refreshAction = UIAccessibilityCustomAction(name: strings.pullToRefresh) { [weak self] _ in
            guard let self, isAttached, onRefresh != nil else { return false }
            beginRefreshing()
            return true
        }
        loadAction = UIAccessibilityCustomAction(name: strings.loadMore) { [weak self] _ in
            guard let self, isAttached, onLoadMore != nil, hasMoreData else { return false }
            beginLoadingMore()
            return true
        }
        originalAccessibilityActions = scrollView.accessibilityCustomActions
        scrollView.accessibilityCustomActions = (originalAccessibilityActions ?? []) + [refreshAction, loadAction].compactMap(\.self)
        footerView.isAccessibilityElement = true
        footerView.accessibilityTraits = .button
        footerView.accessibilityCustomActions = [loadAction].compactMap(\.self)
    }

    private func installObservers(_ scrollView: UIScrollView) {
        observations = [
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scrollChanged() }
            },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.layoutControls()
                    self?.scheduleShortContentFill()
                }
            },
            scrollView.observe(\.bounds, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue?.size != change.newValue?.size else { return }
                MainActor.assumeIsolated { self?.layoutControls() }
            },
            scrollView.observe(\.contentInset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.modifyingInsets else { return }
                    self.layoutControls()
                }
            },
            scrollView.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.modifyingInsets else { return }
                    self.layoutControls()
                }
            },
        ]
    }

    // MARK: - Actions

    @objc private func preferencesChanged() {
        guard attached else { return }
        layoutControls()
        headerAnimator.update(
            state: headerState,
            progress: geometry.map { $0.startDistance / effectiveHeaderHeight } ?? 0
        )
        guard attached else { return }
        footerAnimator.update(
            state: footerState,
            progress: geometry.map { $0.endDistance / effectiveFooterHeight } ?? 0
        )
    }

    @objc private func retryFooter() {
        if footerState == .failed { beginLoadingMore() }
    }

    @objc private func panChanged() {
        guard let scrollView, attached else { return }
        switch scrollView.panGestureRecognizer.state {
        case .began:
            automaticArmed = true
            scrollChanged()
        case .changed:
            scrollChanged()
        case .ended, .cancelled, .failed:
            let cancelled = scrollView.panGestureRecognizer.state != .ended
            let refresh = refreshPull.release(cancelled: cancelled)
            let loadMore = loadMorePull.release(cancelled: cancelled)
            if refresh { beginRefreshing() }
            else if loadMore { beginLoadingMore() }
            else if operation == nil {
                if headerState == .armed || headerState == .pulling { setState(.idle, role: .refresh) }
                if footerState == .armed || footerState == .pulling { setState(.idle, role: .loadMore) }
            }
        default: break
        }
    }

    // MARK: - Private Methods

    private var baseInsets: UIEdgeInsets {
        guard let scrollView else { return .zero }
        var inset = scrollView.adjustedContentInset
        if axis == .vertical {
            inset.top -= ownedStart
            inset.bottom -= ownedEnd
        } else if isReversed {
            inset.right -= ownedStart
            inset.left -= ownedEnd
        } else {
            inset.left -= ownedStart
            inset.right -= ownedEnd
        }
        return inset
    }

    private var geometry: ScrollGeometry? {
        guard let scrollView else { return nil }
        let inset = baseInsets
        if axis == .vertical {
            return ScrollGeometry(
                offset: scrollView.contentOffset.y,
                contentLength: scrollView.contentSize.height,
                viewportLength: scrollView.bounds.height,
                lowerInset: inset.top,
                upperInset: inset.bottom,
                isReversed: false
            )
        }
        return ScrollGeometry(
            offset: scrollView.contentOffset.x,
            contentLength: scrollView.contentSize.width,
            viewportLength: scrollView.bounds.width,
            lowerInset: inset.left,
            upperInset: inset.right,
            isReversed: isReversed
        )
    }

    private func scrollChanged() {
        guard attached, !modifyingInsets, let scrollView, let geometry else { return }
        layoutControls()
        // 分页时仍允许下拉手势；松开后刷新会取消旧分页。
        if !isRefreshing, scrollView.isDragging, onRefresh != nil {
            let state = refreshPull.drag(distance: geometry.startDistance, threshold: effectiveHeaderHeight)
            setState(state, role: .refresh, progress: geometry.startDistance / effectiveHeaderHeight)
        }
        guard operation == nil, hasMoreData, onLoadMore != nil, footerState != .failed else { return }
        if configuration.loadMoreMode == .pull {
            if scrollView.isDragging {
                let state = loadMorePull.drag(distance: geometry.endDistance, threshold: effectiveFooterHeight)
                setState(state, role: .loadMore, progress: geometry.endDistance / effectiveFooterHeight)
            }
            return
        }
        guard !geometry.isShort else { return }
        let distance: CGFloat = if case let .prefetch(value) = configuration.loadMoreMode {
            value.isFinite ? max(0, value) : 200
        } else { 0 }
        if geometry.remainingDistance > distance + 1 { automaticArmed = true }
        if automaticArmed, geometry.remainingDistance <= distance,
           scrollView.isDragging || scrollView.isDecelerating
        {
            automaticArmed = false
            beginLoadingMore()
        }
    }

    private var isReversed: Bool {
        axis == .horizontal && layoutDirection == .rightToLeft
    }

    private var refreshEdge: RefreshEdge {
        axis == .vertical ? .top : .leading
    }

    private var loadMoreEdge: RefreshEdge {
        axis == .vertical ? .bottom : .trailing
    }

    private func begin(_ role: RefreshRole) {
        guard attached, !isCancelling else { return }
        let handler = role == .refresh ? onRefresh : onLoadMore
        guard let handler else { return }
        if role == .refresh {
            guard !isRefreshing else { return }
            cancel()
            // 取消回调可能卸载组件或启动其他操作。
            guard attached, operation == nil else { return }
            shortContentPages = 0
        } else {
            guard operation == nil, hasMoreData else { return }
        }
        let id = UUID()
        fillGeneration = UUID()
        fillScheduled = false
        operationID = id
        let edge = role == .refresh ? refreshEdge : loadMoreEdge
        let operation = RefreshOperation(edge: edge) { [weak self] result in
            self?.finish(id: id, role: role, result: result)
        }
        self.operation = operation
        setState(.loading, role: role)
        guard attached, operationID == id else { return }
        if role == .refresh, let scrollView {
            setStartInset(effectiveHeaderHeight)
            guard attached, operationID == id else { return }
            scrollView.setContentOffset(startContentOffset(in: scrollView), animated: false)
        }
        guard attached, operationID == id else { return }
        handler(operation)
    }

    private func run(_ handler: @escaping AsyncHandler, operation: RefreshOperation) {
        task = Task { @MainActor in
            let result: RefreshResult
            do {
                try Task.checkCancellation()
                result = try await handler()
                try Task.checkCancellation()
            } catch is CancellationError {
                operation.finish(.cancelled)
                return
            } catch {
                operation.finish(Task.isCancelled ? .cancelled : .failure)
                return
            }
            operation.finish(result)
        }
    }

    private func finish(id: UUID, role: RefreshRole, result: RefreshResult) {
        guard attached, operationID == id else { return }
        let generation = fillGeneration
        operation = nil
        operationID = nil
        task = nil
        if role == .refresh { setStartInset(0) }
        guard attached, operation == nil, fillGeneration == generation else { return }
        switch result {
        case let .success(hasMore):
            hasMoreData = hasMore
            if role == .refresh {
                (headerAnimator as? DefaultRefreshAnimator)?.lastUpdated = Date()
                setState(.succeeded, role: .refresh)
            }
            guard attached, operation == nil, fillGeneration == generation else { return }
            setState(hasMore ? .idle : .noMoreData, role: .loadMore)
            guard attached, operation == nil, fillGeneration == generation else { return }
            fillEnabled = true
            scheduleShortContentFill()
        case .failure:
            fillEnabled = false
            setState(.failed, role: role)
        case .cancelled:
            setState(.idle, role: role)
        }
    }

    private func scheduleShortContentFill() {
        guard attached, fillEnabled, !fillScheduled, operation == nil, hasMoreData, onLoadMore != nil,
              shortContentPages < max(0, configuration.shortContentPageLimit) else { return }
        fillScheduled = true
        let generation = fillGeneration
        // 等待本次数据源布局完成；预算保证空页也不会造成无限请求。
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, attached, fillGeneration == generation else { return }
            fillScheduled = false
            scrollView?.layoutIfNeeded()
            guard fillEnabled, operation == nil, geometry?.isShort == true else { return }
            shortContentPages += 1
            beginLoadingMore()
        }
    }

    private func setState(_ state: RefreshState, role: RefreshRole, progress: CGFloat = 0) {
        let old = role == .refresh ? headerState : footerState
        if role == .refresh {
            headerState = state
            headerAnimator.update(state: state, progress: progress)
        } else {
            footerState = state
            footerAnimator.update(state: state, progress: progress)
            guard attached else { return }
            footerView.accessibilityLabel = state.accessibilityLabel(edge: loadMoreEdge, strings: strings)
        }
        guard attached else { return }
        if state == .armed, old != .armed, configuration.isHapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if state != old, [.loading, .failed, .noMoreData, .succeeded].contains(state) {
            let message = state == .failed ? strings.retry : state == .noMoreData ? strings.noMoreData : state == .succeeded ? strings.updated : role == .refresh ? strings.refreshing : strings.loadingMore
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func updateFooterInset() {
        setEndInset(onLoadMore == nil ? 0 : effectiveFooterHeight)
    }

    private func setStartInset(_ value: CGFloat) {
        guard let scrollView else { return }
        let delta = value - ownedStart
        guard abs(delta) > 0.001 else { return }
        modifyingInsets = true
        ownedStart = value
        if axis == .vertical {
            scrollView.contentInset.top += delta
        } else if isReversed {
            scrollView.contentInset.right += delta
        } else {
            scrollView.contentInset.left += delta
        }
        if value == 0, !scrollView.isDragging, let geometry {
            if !isReversed, axisOffset(in: scrollView) < geometry.startOffset {
                setAxisOffset(geometry.startOffset, in: scrollView)
            } else if isReversed, axisOffset(in: scrollView) > geometry.startOffset {
                setAxisOffset(geometry.startOffset, in: scrollView)
            }
        }
        modifyingInsets = false
    }

    private func setEndInset(_ value: CGFloat) {
        guard let scrollView else { return }
        let delta = value - ownedEnd
        guard abs(delta) > 0.001 else { return }
        modifyingInsets = true
        ownedEnd = value
        if axis == .vertical {
            scrollView.contentInset.bottom += delta
        } else if isReversed {
            scrollView.contentInset.left += delta
        } else {
            scrollView.contentInset.right += delta
        }
        modifyingInsets = false
    }

    private func startContentOffset(in scrollView: UIScrollView) -> CGPoint {
        if axis == .vertical {
            return CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
        }
        if isReversed {
            let x = max(
                -scrollView.adjustedContentInset.left,
                scrollView.contentSize.width + scrollView.adjustedContentInset.right - scrollView.bounds.width
            )
            return CGPoint(x: x, y: scrollView.contentOffset.y)
        }
        return CGPoint(x: -scrollView.adjustedContentInset.left, y: scrollView.contentOffset.y)
    }

    private func axisOffset(in scrollView: UIScrollView) -> CGFloat {
        axis == .vertical ? scrollView.contentOffset.y : scrollView.contentOffset.x
    }

    private func setAxisOffset(_ value: CGFloat, in scrollView: UIScrollView) {
        if axis == .vertical {
            scrollView.contentOffset.y = value
        } else {
            scrollView.contentOffset.x = value
        }
    }
}

private extension ScrollGeometry {
    var viewportLengthMinusInsets: CGFloat {
        max(0, viewportLength - lowerInset - upperInset)
    }
}
