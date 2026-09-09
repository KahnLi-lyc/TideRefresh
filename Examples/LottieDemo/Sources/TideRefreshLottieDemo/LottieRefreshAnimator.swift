import Lottie
import TideRefresh
import UIKit

/// An optional Lottie-backed animator. Lottie is a dependency of this example only.
///
/// Create a separate instance for each refresh edge. The animator owns its view
/// and stops playback when the controller detaches. The application supplies its
/// own licensed Lottie animation through the initializer.
@MainActor
public final class LottieRefreshAnimator {
    // MARK: - Private Properties

    private let animation: LottieAnimation?
    private let edge: RefreshEdge
    private var isViewLoaded = false
    private var strings = RefreshStrings()

    // MARK: - Views

    private lazy var animationView: LottieAnimationView = {
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        view.backgroundBehavior = .pauseAndRestore
        view.isAccessibilityElement = true
        isViewLoaded = true
        return view
    }()

    // MARK: - Initialization

    /// Creates an animator using application-owned animation data.
    ///
    /// A `nil` animation produces an empty view with accessible status text.
    public init(animation: LottieAnimation?, edge: RefreshEdge = .top) {
        self.animation = animation
        self.edge = edge
    }
}

extension LottieRefreshAnimator: RefreshAnimator {
    /// The animator-owned view, hosted and sized by `RefreshController`.
    public var view: UIView {
        animationView
    }

    /// Plays during loading or scrubs to the current drag progress.
    /// Reduce Motion displays a static frame with accessible status text.
    public func update(state: RefreshState, progress: CGFloat) {
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0
        if state == .loading, !UIAccessibility.isReduceMotionEnabled {
            if !animationView.isAnimationPlaying { animationView.play() }
        } else {
            animationView.pause()
            animationView.currentProgress = progress
        }
        switch state {
        case .idle, .pulling:
            animationView.accessibilityLabel = edge == .top ? strings.pullToRefresh : strings.loadMore
        case .armed: animationView.accessibilityLabel = strings.releaseToRefresh
        case .loading:
            animationView.accessibilityLabel = edge == .top ? strings.refreshing : strings.loadingMore
        case .succeeded: animationView.accessibilityLabel = strings.updated
        case .failed: animationView.accessibilityLabel = strings.retry
        case .noMoreData: animationView.accessibilityLabel = strings.noMoreData
        }
    }

    /// Applies background and tint colors and the localized status strings.
    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        self.strings = strings
        animationView.backgroundColor = theme.backgroundColor
        animationView.tintColor = theme.tintColor
    }

    /// Stops playback without instantiating an unused animation view.
    public func stop() {
        guard isViewLoaded else { return }
        animationView.stop()
    }
}
