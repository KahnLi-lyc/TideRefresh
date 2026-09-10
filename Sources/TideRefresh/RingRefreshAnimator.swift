import UIKit

/// A text-free circular refresh animator whose stroke follows pull progress.
///
/// Create a distinct instance for each refresh edge. The animator owns its view
/// and removes all Core Animation activity when stopped or detached.
@MainActor
public final class RingRefreshAnimator {
    // MARK: - Private Properties

    private let edge: RefreshEdge
    private let terminalPresentation: RefreshTerminalPresentation
    private var strings = RefreshStrings()
    private var isViewLoaded = false

    // MARK: - Views

    private lazy var ringView = RingVisualView()

    private lazy var containerView: RefreshAnimatorContainerView = {
        isViewLoaded = true
        return RefreshAnimatorContainerView(contentView: ringView, terminalPresentation: terminalPresentation)
    }()

    // MARK: - Initialization

    /// Creates a progress ring for one edge.
    public init(edge: RefreshEdge, terminalPresentation: RefreshTerminalPresentation = .symbols) {
        self.edge = edge
        self.terminalPresentation = terminalPresentation
    }
}

extension RingRefreshAnimator: RefreshAnimator {
    /// The animator-owned view. Do not reparent it while attached to a controller.
    public var view: UIView {
        containerView
    }

    /// Applies semantic colors and accessible status strings without visible text.
    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        self.strings = strings
        ringView.tintColor = theme.tintColor
        containerView.configure(theme: theme)
    }

    /// Draws pull progress or presents an indefinite loading arc.
    public func update(state: RefreshState, progress: CGFloat) {
        if state == .loading {
            ringView.startLoading(reduceMotion: UIAccessibility.isReduceMotionEnabled)
        } else {
            ringView.setProgress(progress.clampedProgress)
        }
        containerView.present(state: state, progress: progress, edge: edge, strings: strings)
    }

    /// Stops and removes all ring animations. Calling repeatedly is safe.
    public func stop() {
        guard isViewLoaded else { return }
        ringView.stopAnimating()
    }
}

@MainActor
private final class RingVisualView: UIView {
    // MARK: - Views

    private lazy var ringLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineCap = .round
        layer.lineWidth = 2
        layer.strokeEnd = 0
        return layer
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(ringLayer)
        updateColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(
            ovalIn: bounds.insetBy(dx: ringLayer.lineWidth / 2, dy: ringLayer.lineWidth / 2)
        ).cgPath
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }

    // MARK: - Public Methods

    override var intrinsicContentSize: CGSize {
        CGSize(width: 24, height: 24)
    }

    func setProgress(_ progress: CGFloat) {
        stopAnimating()
        ringLayer.strokeStart = 0
        ringLayer.strokeEnd = progress
    }

    func startLoading(reduceMotion: Bool) {
        ringLayer.strokeStart = 0.15
        ringLayer.strokeEnd = 0.9
        guard !reduceMotion, ringLayer.animation(forKey: "ring.rotation") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.byValue = CGFloat.pi * 2
        rotation.duration = 1
        rotation.repeatCount = .infinity
        ringLayer.add(rotation, forKey: "ring.rotation")
    }

    func stopAnimating() {
        ringLayer.removeAllAnimations()
        ringLayer.transform = CATransform3DIdentity
    }

    // MARK: - Private Methods

    private func updateColor() {
        ringLayer.strokeColor = tintColor.resolvedColor(with: traitCollection).cgColor
    }
}
