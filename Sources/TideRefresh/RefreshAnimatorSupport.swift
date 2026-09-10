import UIKit

/// Controls how text-free animators represent failure and pagination exhaustion.
public enum RefreshTerminalPresentation: Equatable, Sendable {
    /// Leaves terminal states visually empty. The application remains responsible for visible feedback.
    case hidden
    /// Displays a retry symbol for failure and a short line when no more data is available.
    case symbols
}

@MainActor
final class RefreshAnimatorContainerView: UIView {
    // MARK: - Private Properties

    private let contentView: UIView
    private let terminalPresentation: RefreshTerminalPresentation

    // MARK: - Views

    private lazy var terminalImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = false
        return imageView
    }()

    // MARK: - Initialization

    init(contentView: UIView, terminalPresentation: RefreshTerminalPresentation) {
        self.contentView = contentView
        self.terminalPresentation = terminalPresentation
        super.init(frame: .zero)
        setUpViews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Public Methods

    func configure(theme: RefreshTheme) {
        backgroundColor = theme.backgroundColor
        tintColor = theme.tintColor
        terminalImageView.tintColor = theme.tintColor
    }

    func present(state: RefreshState, progress: CGFloat, edge: RefreshEdge, strings: RefreshStrings) {
        accessibilityLabel = state.accessibilityLabel(edge: edge, strings: strings)
        contentView.alpha = state.contentAlpha(progress: progress)
        terminalImageView.isHidden = true

        guard terminalPresentation == .symbols else { return }
        switch state {
        case .failed:
            terminalImageView.image = UIImage(systemName: "arrow.clockwise")
            terminalImageView.isHidden = false
        case .noMoreData:
            terminalImageView.image = UIImage(systemName: "minus")
            terminalImageView.isHidden = false
        default:
            break
        }
    }

    // MARK: - View Setup

    private func setUpViews() {
        isAccessibilityElement = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        addSubview(terminalImageView)
        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor),
            terminalImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            terminalImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            terminalImageView.widthAnchor.constraint(equalToConstant: 18),
            terminalImageView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}

extension RefreshState {
    func accessibilityLabel(edge: RefreshEdge, strings: RefreshStrings) -> String {
        switch self {
        case .idle, .pulling:
            edge.isRefresh ? strings.pullToRefresh : strings.loadMore
        case .armed:
            strings.releaseToRefresh
        case .loading:
            edge.isRefresh ? strings.refreshing : strings.loadingMore
        case .succeeded:
            strings.updated
        case .failed:
            strings.retry
        case .noMoreData:
            strings.noMoreData
        }
    }

    func contentAlpha(progress: CGFloat) -> CGFloat {
        switch self {
        case .pulling:
            progress.clampedProgress
        case .armed, .loading:
            1
        case .idle, .succeeded, .failed, .noMoreData:
            0
        }
    }
}

extension RefreshEdge {
    var isRefresh: Bool {
        self == .top || self == .leading
    }

    var isHorizontal: Bool {
        self == .leading || self == .trailing
    }
}

extension CGFloat {
    var clampedProgress: CGFloat {
        isFinite ? Swift.min(1, Swift.max(0, self)) : 0
    }
}
