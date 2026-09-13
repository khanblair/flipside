import AppKit
import CoreGraphics

/// Reads the set of windows composited on the **active Space** via
/// `CGWindowList`.
///
/// Spec §6.3 rules out `CGWindowListCopyWindowInfo` for reading window titles
/// or content, because doing so requires the separate Screen Recording
/// permission. This use is different and stays within that constraint: only
/// `kCGWindowOwnerPID` and `kCGWindowBounds` are read, neither of which is
/// gated behind Screen Recording. Window names are never requested.
///
/// The Accessibility API has no notion of Spaces — it reports windows from
/// every Space at once — so this is the only way to know what the user can
/// actually see right now.
enum OnScreenWindowReader {
    static func onScreenWindows() -> [ActiveSpaceFilter.OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsValue = entry[kCGWindowBounds as String] else {
                return nil
            }
            // CGWindowList reports bounds in CoreGraphics' top-left-origin
            // space, the same convention the Accessibility API uses — so the
            // same conversion applies before comparing against a TrackedWindow.
            guard let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary) else {
                return nil
            }
            return ActiveSpaceFilter.OnScreenWindow(
                pid: pid,
                frame: AXWindowReader.convertAXRectToCocoa(origin: bounds.origin, size: bounds.size)
            )
        }
    }
}
