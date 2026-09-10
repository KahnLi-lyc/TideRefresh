import UIKit

/// Pure scroll calculations exclude insets owned by the refresh controller.
struct ScrollGeometry {
    let offset: CGFloat
    let contentLength: CGFloat
    let viewportLength: CGFloat
    let lowerInset: CGFloat
    let upperInset: CGFloat
    let isReversed: Bool

    var startOffset: CGFloat {
        isReversed ? upperOffset : lowerOffset
    }

    var endOffset: CGFloat {
        isReversed ? lowerOffset : upperOffset
    }

    var startDistance: CGFloat {
        max(0, -logicalOffset)
    }

    var endDistance: CGFloat {
        max(0, logicalOffset - scrollableLength)
    }

    var remainingDistance: CGFloat {
        scrollableLength - logicalOffset
    }

    var isShort: Bool {
        contentLength <= max(0, viewportLength - lowerInset - upperInset)
    }

    private var lowerOffset: CGFloat {
        -lowerInset
    }

    private var upperOffset: CGFloat {
        max(lowerOffset, contentLength + upperInset - viewportLength)
    }

    private var scrollableLength: CGFloat {
        upperOffset - lowerOffset
    }

    private var logicalOffset: CGFloat {
        isReversed ? upperOffset - offset : offset - lowerOffset
    }
}

/// Tracks a single drag without coupling the state machine to UIKit observations.
struct PullStateMachine {
    private(set) var state: RefreshState = .idle

    mutating func drag(distance: CGFloat, threshold: CGFloat) -> RefreshState {
        state = distance >= threshold ? .armed : (distance > 0 ? .pulling : .idle)
        return state
    }

    mutating func release(cancelled: Bool) -> Bool {
        let shouldStart = state == .armed && !cancelled
        state = .idle
        return shouldStart
    }
}
