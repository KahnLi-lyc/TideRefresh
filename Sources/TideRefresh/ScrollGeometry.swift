import UIKit

/// Pure scroll calculations exclude insets owned by the refresh controller.
struct ScrollGeometry {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var topDistance: CGFloat {
        max(0, -topInset - offset)
    }

    var bottomOffset: CGFloat {
        max(-topInset, contentHeight + bottomInset - viewportHeight)
    }

    var bottomDistance: CGFloat {
        max(0, offset - bottomOffset)
    }

    var remainingDistance: CGFloat {
        bottomOffset - offset
    }

    var isShort: Bool {
        contentHeight <= max(0, viewportHeight - topInset - bottomInset)
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
