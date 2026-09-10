import UIKit

/// A text-free wave animator inspired by a calm moving tide.
///
/// Create a distinct instance for each refresh edge. The animator owns its view
/// and removes all Core Animation activity when stopped or detached.
@MainActor
public final class TideRefreshAnimator {
    // MARK: - Private Properties

    private let edge: RefreshEdge
    private let terminalPresentation: RefreshTerminalPresentation
    private var strings = RefreshStrings()
    private var isViewLoaded = false

    // MARK: - Views

    private lazy var tideView = TideVisualView()

    private lazy var containerView: RefreshAnimatorContainerView = {
        isViewLoaded = true
        return RefreshAnimatorContainerView(contentView: tideView, terminalPresentation: terminalPresentation)
    }()

    // MARK: - Initialization

    /// Creates a tide animator for one edge.
    public init(edge: RefreshEdge, terminalPresentation: RefreshTerminalPresentation = .symbols) {
        self.edge = edge
        self.terminalPresentation = terminalPresentation
    }
}

extension TideRefreshAnimator: RefreshAnimator {
    /// The animator-owned view. Do not reparent it while attached to a controller.
    public var view: UIView {
        containerView
    }

    /// Applies semantic colors and accessible status strings without visible text.
    public func configure(theme: RefreshTheme, strings: RefreshStrings) {
        self.strings = strings
        tideView.tintColor = theme.tintColor
        containerView.configure(theme: theme)
    }

    /// Raises the wave from pull progress or moves it while loading.
    public func update(state: RefreshState, progress: CGFloat) {
        if state == .loading {
            tideView.startLoading(reduceMotion: UIAccessibility.isReduceMotionEnabled)
        } else {
            tideView.setProgress(progress.clampedProgress)
        }
        containerView.present(state: state, progress: progress, edge: edge, strings: strings)
    }

    /// Stops and removes all wave animations. Calling repeatedly is safe.
    public func stop() {
        guard isViewLoaded else { return }
        tideView.stopAnimating()
    }
}

@MainActor
private final class TideVisualView: UIView {
    // MARK: - Private Properties

    private var amplitude: CGFloat = 0
    private var isLoading = false
    private var reducesMotion = false

    // MARK: - Views

    private lazy var waveLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.lineWidth = 2
        return layer
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(waveLayer)
        updateColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        waveLayer.frame = bounds
        if waveLayer.animation(forKey: "tide.phase") == nil {
            waveLayer.path = wavePath(amplitude: amplitude, phase: 0)
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            waveLayer.removeAllAnimations()
        } else if isLoading {
            applyLoadingAnimation()
        }
    }

    // MARK: - Public Methods

    override var intrinsicContentSize: CGSize {
        CGSize(width: 48, height: 16)
    }

    func setProgress(_ progress: CGFloat) {
        stopAnimating()
        amplitude = 5 * progress
        waveLayer.path = wavePath(amplitude: amplitude, phase: 0)
    }

    func startLoading(reduceMotion: Bool) {
        isLoading = true
        reducesMotion = reduceMotion
        amplitude = 4
        waveLayer.path = wavePath(amplitude: amplitude, phase: 0)
        applyLoadingAnimation()
    }

    func stopAnimating() {
        isLoading = false
        waveLayer.removeAllAnimations()
    }

    // MARK: - Private Methods

    private func applyLoadingAnimation() {
        if reducesMotion {
            waveLayer.removeAllAnimations()
            return
        }
        guard waveLayer.animation(forKey: "tide.phase") == nil else { return }
        let phase = CAKeyframeAnimation(keyPath: "path")
        phase.values = stride(from: 0, through: CGFloat.pi * 2, by: CGFloat.pi / 2).map {
            wavePath(amplitude: amplitude, phase: $0)
        }
        phase.duration = 1.4
        phase.repeatCount = .infinity
        phase.calculationMode = .linear
        waveLayer.add(phase, forKey: "tide.phase")
    }

    private func wavePath(amplitude: CGFloat, phase: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let centerY = bounds.midY
        let segments = 24
        for index in 0 ... segments {
            let fraction = CGFloat(index) / CGFloat(segments)
            let point = CGPoint(
                x: bounds.width * fraction,
                y: centerY + sin(fraction * .pi * 2 + phase) * amplitude
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path.cgPath
    }

    private func updateColor() {
        waveLayer.strokeColor = tintColor.resolvedColor(with: traitCollection).cgColor
    }
}
