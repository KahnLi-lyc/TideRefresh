import UIKit

/// A text-free three-dot refresh animator with progress-driven reveal.
///
/// Create a distinct instance for each refresh edge. The animator owns its view
/// and removes all Core Animation activity when stopped or detached.
@MainActor
public final class DotsRefreshAnimator {
    // MARK: - Private Properties

    private let edge: RefreshEdge
    private let terminalPresentation: RefreshTerminalPresentation
    private var strings = RefreshStrings()
    private var isViewLoaded = false

    // MARK: - Views

    private lazy var dotsView = DotsVisualView()

    private lazy var containerView: RefreshAnimatorContainerView = {
        isViewLoaded = true
        return RefreshAnimatorContainerView(contentView: dotsView, terminalPresentation: terminalPresentation)
    }()

    // MARK: - Initialization

    /// Creates a three-dot animator for one edge.
    public init(edge: RefreshEdge, terminalPresentation: RefreshTerminalPresentation = .symbols) {
        self.edge = edge
        self.terminalPresentation = terminalPresentation
    }
}

extension DotsRefreshAnimator: RefreshAnimator {
    /// The animator-owned view. Do not reparent it while attached to a controller.
    public var view: UIView {
        containerView
    }

    /// Applies semantic colors and accessible status strings without visible text.
    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        self.strings = strings
        dotsView.tintColor = theme.tintColor
        containerView.configure(theme: theme)
    }

    /// Reveals dots from pull progress or plays the loading sequence.
    public func update(state: RefreshState, progress: CGFloat) {
        if state == .loading {
            dotsView.startLoading(reduceMotion: UIAccessibility.isReduceMotionEnabled)
        } else {
            dotsView.setProgress(progress.clampedProgress)
        }
        containerView.present(state: state, progress: progress, edge: edge, strings: strings)
    }

    /// Stops and removes all dot animations. Calling repeatedly is safe.
    public func stop() {
        guard isViewLoaded else { return }
        dotsView.stopAnimating()
    }
}

@MainActor
private final class DotsVisualView: UIView {
    // MARK: - Private Properties

    private var isLoading = false
    private var reducesMotion = false

    // MARK: - Views

    private lazy var dotLayers: [CAShapeLayer] = (0 ..< 3).map { _ in
        let layer = CAShapeLayer()
        layer.opacity = 0
        return layer
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        for dotLayer in dotLayers {
            layer.addSublayer(dotLayer)
        }
        updateColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, dotLayer) in dotLayers.enumerated() {
            let origin = CGPoint(x: CGFloat(index) * 10, y: (bounds.height - 5) / 2)
            dotLayer.frame = CGRect(origin: origin, size: CGSize(width: 5, height: 5))
            dotLayer.path = UIBezierPath(ovalIn: dotLayer.bounds).cgPath
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            removeAnimations()
        } else if isLoading {
            applyLoadingAnimations()
        }
    }

    // MARK: - Public Methods

    override var intrinsicContentSize: CGSize {
        CGSize(width: 25, height: 10)
    }

    func setProgress(_ progress: CGFloat) {
        stopAnimating()
        for (index, dotLayer) in dotLayers.enumerated() {
            dotLayer.opacity = Float((progress * 3 - CGFloat(index)).clampedProgress)
        }
    }

    func startLoading(reduceMotion: Bool) {
        isLoading = true
        reducesMotion = reduceMotion
        applyLoadingAnimations()
    }

    func stopAnimating() {
        isLoading = false
        removeAnimations()
    }

    // MARK: - Private Methods

    private func applyLoadingAnimations() {
        for (index, dotLayer) in dotLayers.enumerated() {
            dotLayer.opacity = 1
            if reducesMotion {
                dotLayer.removeAllAnimations()
                dotLayer.transform = CATransform3DIdentity
                continue
            }
            guard dotLayer.animation(forKey: "dot.pulse") == nil else { continue }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.65, 1, 0.65]
            scale.keyTimes = [0, 0.5, 1]
            scale.duration = 0.9
            scale.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            scale.repeatCount = .infinity
            dotLayer.add(scale, forKey: "dot.pulse")
        }
    }

    private func removeAnimations() {
        for dotLayer in dotLayers {
            dotLayer.removeAllAnimations()
            dotLayer.transform = CATransform3DIdentity
        }
    }

    private func updateColor() {
        let color = tintColor.resolvedColor(with: traitCollection).cgColor
        for dotLayer in dotLayers {
            dotLayer.fillColor = color
        }
    }
}
