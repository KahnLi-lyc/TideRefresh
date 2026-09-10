import UIKit

/// A text-free refresh animator backed by `UIActivityIndicatorView`.
///
/// Create a distinct instance for each refresh edge. The animator owns its view,
/// stops activity when detached, and leaves request cancellation to `RefreshController`.
@MainActor
public final class ActivityIndicatorRefreshAnimator {
    // MARK: - Private Properties

    private let edge: RefreshEdge
    private let style: UIActivityIndicatorView.Style
    private let terminalPresentation: RefreshTerminalPresentation
    private var strings = RefreshStrings()
    private var isViewLoaded = false

    // MARK: - Views

    private lazy var indicatorView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: style)
        indicator.hidesWhenStopped = false
        return indicator
    }()

    private lazy var containerView: RefreshAnimatorContainerView = {
        isViewLoaded = true
        return RefreshAnimatorContainerView(contentView: indicatorView, terminalPresentation: terminalPresentation)
    }()

    // MARK: - Initialization

    /// Creates a system activity indicator for one edge.
    ///
    /// - Parameters:
    ///   - edge: The edge whose state determines the accessible description.
    ///   - style: The system activity indicator size.
    ///   - terminalPresentation: The visual treatment for failure and no-more-data states.
    public init(
        edge: RefreshEdge,
        style: UIActivityIndicatorView.Style = .medium,
        terminalPresentation: RefreshTerminalPresentation = .hidden
    ) {
        self.edge = edge
        self.style = style
        self.terminalPresentation = terminalPresentation
    }
}

extension ActivityIndicatorRefreshAnimator: RefreshAnimator {
    /// The animator-owned view. Do not reparent it while attached to a controller.
    public var view: UIView {
        containerView
    }

    /// Applies semantic colors and accessible status strings without adding visible text.
    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        self.strings = strings
        indicatorView.color = theme.tintColor
        containerView.configure(theme: theme)
    }

    /// Updates visibility from drag progress and animates only while loading.
    public func update(state: RefreshState, progress: CGFloat) {
        if state == .loading {
            indicatorView.startAnimating()
        } else {
            indicatorView.stopAnimating()
        }
        containerView.present(state: state, progress: progress, edge: edge, strings: strings)
    }

    /// Stops the system indicator. Calling this method repeatedly is safe.
    public func stop() {
        guard isViewLoaded else { return }
        indicatorView.stopAnimating()
        indicatorView.layer.removeAllAnimations()
    }
}
