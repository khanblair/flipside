import CoreGraphics

/// A pure, in-memory keyed store of `TrackedWindow` values.
///
/// This type carries no OS dependency: it is generic over its key type so
/// that production code can key it by a live `AXUIElement` accessibility
/// handle (which cannot be constructed outside a real accessibility
/// session) while unit tests can key it by a plain `String`.
public struct WindowRegistry<Key: Hashable> {
    private var windowsByKey: [Key: TrackedWindow] = [:]

    public init() {}

    /// Inserts a new tracked window for `key`, or replaces the existing one.
    public mutating func upsert(_ window: TrackedWindow, for key: Key) {
        windowsByKey[key] = window
    }

    /// Updates only the frame of the entry at `key`. No-op if `key` isn't present.
    public mutating func updateFrame(_ frame: CGRect, for key: Key) {
        guard var window = windowsByKey[key] else { return }
        window.frame = frame
        windowsByKey[key] = window
    }

    /// Removes and returns the tracked window for `key`, or `nil` if absent.
    @discardableResult
    public mutating func remove(for key: Key) -> TrackedWindow? {
        windowsByKey.removeValue(forKey: key)
    }

    /// All currently tracked windows, in no particular order.
    public func all() -> [TrackedWindow] {
        Array(windowsByKey.values)
    }

    /// All currently tracked windows together with their keys, in no
    /// particular order. Callers that must create/destroy per-window state
    /// (e.g. one overlay window per tracked window) need the key to tell
    /// windows apart — `all()` alone is ambiguous when two windows share
    /// identical field values.
    public func allKeyed() -> [(Key, TrackedWindow)] {
        Array(windowsByKey)
    }
}
