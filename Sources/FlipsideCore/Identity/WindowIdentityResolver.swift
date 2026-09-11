/// Thin glue tying a `TrackedWindow` to `IdentityKeyBuilder` + `ChromeProfileResolver`
/// (spec §7 / §7.1.1). Not a pure function — `ChromeProfileResolver.profileDirectory(forPID:)`
/// does a live `sysctl` call for Chromium bundle IDs — so this isn't unit tested directly;
/// the two pieces it composes are each tested on their own.
public enum WindowIdentityResolver {
    public static func resolve(_ window: TrackedWindow) -> (key: String, tier: IdentityTier)? {
        let profileDirectory: String?
        if ChromeProfileResolver.chromiumBundleIDs.contains(window.bundleID) {
            profileDirectory = ChromeProfileResolver.profileDirectory(forPID: window.pid)
        } else {
            profileDirectory = nil
        }

        return IdentityKeyBuilder.key(
            bundleID: window.bundleID,
            documentPath: window.documentPath,
            title: window.title,
            chromeProfileDirectory: profileDirectory
        )
    }
}
