import Darwin

/// Resolves the Chrome/Chromium profile directory for a tracked window, to
/// close the "Chrome profile gap" described in the spec (§7.1.1): title
/// alone cannot distinguish two Chrome windows running in different
/// profiles, so Chrome's identity key is extended with the profile
/// directory extracted from its process's command-line arguments.
enum ChromeProfileResolver {
    /// Bundle identifiers of browsers known to accept `--profile-directory=`
    /// on their command line. Only Chrome itself has been confirmed; other
    /// Chromium-based browsers are expected to behave the same way but are
    /// not yet verified.
    static let chromiumBundleIDs: Set<String> = ["com.google.Chrome"]

    /// Scans `arguments` for a `--profile-directory=` flag and returns the
    /// value after the `=`. Pure — no process access, fully unit-testable.
    ///
    /// Returns `nil` if no such argument is present, or if its value is
    /// empty (an empty profile name would be worse to embed in an identity
    /// key than falling back to the generic Tier 2 scheme).
    static func extractProfileDirectory(from arguments: [String]) -> String? {
        let prefix = "--profile-directory="
        for argument in arguments where argument.hasPrefix(prefix) {
            let value = String(argument.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Thin glue: reads `pid`'s command-line arguments via
    /// `ProcessArgumentsReader` and extracts the profile directory from
    /// them. Returns `nil` if the process's arguments can't be read, or if
    /// no `--profile-directory=` argument is present.
    static func profileDirectory(forPID pid: pid_t) -> String? {
        guard let arguments = ProcessArgumentsReader.arguments(forPID: pid) else {
            return nil
        }
        return extractProfileDirectory(from: arguments)
    }
}
