import CoreGraphics

/// Guards the card/badge against frames that can't produce usable UI.
///
/// Tracked windows are whatever the Accessibility API reports, which
/// includes offscreen helper windows, zero-size placeholders, and windows
/// extending past the visible screen area. Showing a card for those
/// produces either an invisible card or one sprawling beyond the display.
public enum CardFrameSanitizer {
    /// The smallest card worth showing. Below this there isn't room for the
    /// header and a line of text, so the result would just be a stray sliver.
    public static let minimumSide: CGFloat = 120

    /// Clamps `frame` to the screen it mostly occupies. Returns `nil` when
    /// the frame is degenerate (non-finite, empty, entirely offscreen, or
    /// too small to render a usable card).
    public static func sanitized(_ frame: CGRect, visibleScreenFrames: [CGRect]) -> CGRect? {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else {
            return nil
        }
        guard frame.width >= minimumSide, frame.height >= minimumSide else { return nil }

        guard let bestScreen = visibleScreenFrames.max(by: { lhs, rhs in
            overlapArea(frame, lhs) < overlapArea(frame, rhs)
        }) else {
            return frame
        }

        // No meaningful overlap with any screen: the window is offscreen.
        guard overlapArea(frame, bestScreen) > 0 else { return nil }

        let clamped = frame.intersection(bestScreen)
        guard clamped.width >= minimumSide, clamped.height >= minimumSide else { return nil }
        return clamped
    }

    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }
}
