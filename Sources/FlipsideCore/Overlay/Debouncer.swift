import Foundation

/// A general-purpose coalescing utility that collapses a rapid burst of calls into a single
/// action, firing only the most recently scheduled action after a quiet period.
///
/// Intended (per the Flipside spec's risk mitigation for "rapid window churn") to coalesce
/// bursts of AXObserver move/resize callbacks into a single reposition, but this type has no
/// dependency on AX and can be used anywhere similar debouncing is needed.
public final class Debouncer {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingWorkItem: DispatchWorkItem?

    /// - Parameters:
    ///   - delay: How long to wait, in seconds, after the most recent `schedule` call before
    ///     firing its action.
    ///   - queue: The queue the action runs on, and the queue `schedule` is expected to be
    ///     safe to call from. Defaults to `.main`.
    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    /// Cancels any previously pending action and schedules `action` to run `delay` seconds
    /// from now on this debouncer's queue. Only the action from the most recent call within
    /// the delay window actually fires.
    public func schedule(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        pendingWorkItem = workItem
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
