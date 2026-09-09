import UIKit

/// The appearance shared by the built-in animators. UIKit values remain on MainActor.
@MainActor
public struct RefreshTheme {
    public var tintColor: UIColor
    public var textColor: UIColor
    public var backgroundColor: UIColor

    public init(
        tintColor: UIColor = .systemTeal,
        textColor: UIColor = .secondaryLabel,
        backgroundColor: UIColor = .clear
    ) {
        self.tintColor = tintColor
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

/// Receives presentation changes. An animator belongs to a single refresh edge.
@MainActor
public protocol RefreshAnimator: AnyObject {
    /// Owned by the animator and hosted by the controller. Do not reparent while attached.
    var view: UIView { get }
    /// Updates visual state and drag progress; progress can exceed one past the threshold.
    func update(state: RefreshState, progress: CGFloat)
    /// Applies colors and localized/custom strings.
    func configure(theme: RefreshTheme, strings: RefreshStrings)
    /// Stops animations and releases transient rendering resources on detach.
    func stop()
}

/// Standard arrow, activity indicator and status label with Dynamic Type support.
@MainActor
public final class DefaultRefreshAnimator: RefreshAnimator {
    // MARK: - Public Properties

    public var view: UIView {
        containerView
    }

    /// Set to display the last successful refresh time. It is not persisted by the library.
    public var lastUpdated: Date?

    // MARK: - Private Properties

    private let edge: RefreshEdge
    private var strings = RefreshStrings()
    private var currentState: RefreshState = .idle

    // MARK: - Views

    private lazy var containerView: UIView = {
        let view = UIView()
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
        ])
        return view
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [arrowView, spinner, statusLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var arrowView: UIImageView = {
        let image = UIImageView(image: UIImage(systemName: edge == .top ? "arrow.down" : "arrow.up"))
        image.contentMode = .scaleAspectFit
        image.widthAnchor.constraint(equalToConstant: 18).isActive = true
        image.heightAnchor.constraint(equalToConstant: 18).isActive = true
        image.isAccessibilityElement = false
        return image
    }()

    private lazy var spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    // MARK: - Initialization

    public init(edge: RefreshEdge) {
        self.edge = edge
    }

    // MARK: - Public Methods

    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        self.strings = strings
        view.backgroundColor = theme.backgroundColor
        arrowView.tintColor = theme.tintColor
        spinner.color = theme.tintColor
        statusLabel.textColor = theme.textColor
        update(state: currentState, progress: 0)
    }

    public func update(state: RefreshState, progress: CGFloat) {
        currentState = state
        let isLoading = state == .loading
        isLoading ? spinner.startAnimating() : spinner.stopAnimating()
        arrowView.isHidden = isLoading || state == .failed || state == .noMoreData
        // 减少动态效果时保留状态文字，不进行旋转过渡。
        let angle: CGFloat = state == .armed && !UIAccessibility.isReduceMotionEnabled ? .pi : 0
        arrowView.transform = CGAffineTransform(rotationAngle: angle)
        var text: String = switch state {
        case .idle, .pulling: edge == .top ? strings.pullToRefresh : strings.loadMore
        case .armed: strings.releaseToRefresh
        case .loading: edge == .top ? strings.refreshing : strings.loadingMore
        case .failed: strings.retry
        case .noMoreData: strings.noMoreData
        case .succeeded: strings.updated
        }
        if edge == .top, let lastUpdated, state != .loading {
            text += " · " + lastUpdated.formatted(date: .omitted, time: .shortened)
        }
        statusLabel.text = text
        view.accessibilityLabel = text
    }

    public func stop() {
        spinner.stopAnimating()
        arrowView.layer.removeAllAnimations()
    }
}

/// Displays application-provided image frames. Core does not decode GIF files.
@MainActor
public final class FrameRefreshAnimator: RefreshAnimator {
    // MARK: - Public Properties

    public var view: UIView {
        imageView
    }

    // MARK: - Private Properties

    private let frames: [UIImage]
    private let duration: TimeInterval

    // MARK: - Views

    private lazy var imageView: UIImageView = {
        let image = UIImageView(image: frames.first)
        image.contentMode = .scaleAspectFit
        image.animationImages = frames
        image.animationDuration = duration
        return image
    }()

    // MARK: - Initialization

    /// Creates a frame animator. Empty frames render no image; duration defaults to 0.8 seconds.
    public init(frames: [UIImage], duration: TimeInterval = 0.8) {
        self.frames = frames
        self.duration = duration.isFinite && duration > 0 ? duration : 0.8
    }

    // MARK: - Public Methods

    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        view.tintColor = theme.tintColor
        view.backgroundColor = theme.backgroundColor
    }

    public func update(state: RefreshState, progress: CGFloat) {
        if state == .loading, !UIAccessibility.isReduceMotionEnabled {
            imageView.startAnimating()
        } else {
            imageView.stopAnimating()
            if !frames.isEmpty {
                let progress = progress.isFinite ? min(1, max(0, progress)) : 0
                imageView.image = frames[Int(progress * CGFloat(frames.count - 1))]
            }
        }
    }

    public func stop() {
        imageView.stopAnimating()
    }
}
