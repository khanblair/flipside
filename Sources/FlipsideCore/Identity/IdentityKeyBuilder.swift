import Foundation

/// Builds a stable, persistable identity key for a tracked window, following the
/// tiering scheme in the Flipside spec (§7 Window Identity & Persistence).
///
/// - Tier 1 (document): `{bundleID}::doc::{documentPath}` — used whenever a document
///   path is available (e.g. via `kAXDocumentAttribute`). Preferred whenever present.
/// - Tier 2 (title): `{bundleID}::title::{title}` — used when no document path is
///   available but the window has a usable title.
///   - Chrome/Chromium-specific extension (§7.1.1): when a profile directory is also
///     supplied (from `--profile-directory` process-argument lookup), the key becomes
///     `{bundleID}::profile::{profileDirectory}::title::{title}` so that two profiles
///     with identically-titled windows do not collide. This remains Tier 2 — it is a
///     special case layered on top of Tier 2, not a distinct tier.
/// - Tier 3 (session-only): neither a document path nor a usable title is available.
///   No stable key can be produced; the caller should track the window for the
///   current session only (never persisted).
public enum IdentityKeyBuilder {

    /// Bundle identifier for VS Code, whose window titles carry an unsaved-file
    /// indicator that must be stripped before use in an identity key (§7.1).
    private static let vsCodeBundleID = "com.microsoft.VSCode"

    /// The unsaved-file indicator VS Code prepends to a window title, e.g.
    /// `"● myproject — Visual Studio Code"`.
    private static let vsCodeUnsavedIndicator = "● "

    /// Builds the identity key and tier for a tracked window, per the rules above.
    ///
    /// - Parameters:
    ///   - bundleID: The owning application's bundle identifier.
    ///   - documentPath: The window's open document path, if any (e.g. from
    ///     `kAXDocumentAttribute`). An empty string is treated as absent.
    ///   - title: The window's title, if any. An empty or whitespace-only title is
    ///     treated as absent.
    ///   - chromeProfileDirectory: The Chrome/Chromium `--profile-directory` value for
    ///     the window's owning process, if applicable. Ignored when a document path is
    ///     present, and ignored (has no effect) when there is no usable title either.
    /// - Returns: The identity key and its tier, or `nil` when neither a document path
    ///   nor a usable title is available (Tier 3 — session-only, no stable key).
    public static func key(
        bundleID: String,
        documentPath: String?,
        title: String?,
        chromeProfileDirectory: String?
    ) -> (key: String, tier: IdentityTier)? {
        if let documentPath, !documentPath.isEmpty {
            return ("\(bundleID)::doc::\(documentPath)", .document)
        }

        guard let usableTitle = normalizedTitle(title, bundleID: bundleID) else {
            return nil
        }

        if let chromeProfileDirectory, !chromeProfileDirectory.isEmpty {
            return ("\(bundleID)::profile::\(chromeProfileDirectory)::title::\(usableTitle)", .title)
        }

        return ("\(bundleID)::title::\(usableTitle)", .title)
    }

    /// Normalizes a raw window title for use in an identity key.
    ///
    /// For VS Code (`com.microsoft.VSCode`), strips the unsaved-file indicator
    /// (`"● "`) that the app prepends to titles of windows with unsaved changes.
    /// The result is then trimmed of leading/trailing whitespace. An empty or
    /// whitespace-only title (before or after stripping) is treated as unusable,
    /// same as no title at all — for any app.
    ///
    /// - Parameters:
    ///   - title: The raw window title, if any.
    ///   - bundleID: The owning application's bundle identifier, used to decide
    ///     whether app-specific normalization applies.
    /// - Returns: The normalized, non-empty title, or `nil` if no usable title exists.
    public static func normalizedTitle(_ title: String?, bundleID: String) -> String? {
        guard var normalized = title else {
            return nil
        }

        if bundleID == vsCodeBundleID {
            normalized = normalized.replacingOccurrences(of: vsCodeUnsavedIndicator, with: "")
        }

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }
}
