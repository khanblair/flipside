/// Which face of the card is currently showing.
public enum CardState: Equatable, Sendable {
    case front
    case back
}

/// Tracks whether the card is showing its front (badge) or back (note) face
/// and toggles between the two on demand.
public final class FlipStateMachine {
    public private(set) var state: CardState = .front

    public init() {}

    /// Flips to the other face and returns the new state.
    @discardableResult
    public func toggle() -> CardState {
        state = (state == .front) ? .back : .front
        return state
    }
}
