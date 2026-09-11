import Foundation

/// The outcome of deciding whether a candidate list of stored notes
/// identifies a single, clear match for a newly-appeared window.
///
/// This type is intentionally a pure decision seam: it does not itself
/// search for candidates. Something upstream (a Tier 2 bundle-ID +
/// title-pattern search, for example) is responsible for assembling the
/// candidate list; `AmbiguousMatchDetector` only classifies it.
public enum MatchResult: Equatable {
    /// No candidate notes were found.
    case none
    /// Exactly one candidate note was found — a clear, unambiguous match.
    case unambiguous(Note)
    /// Two or more candidate notes were found; Flipside cannot silently
    /// guess which (if any) belongs to the new window and must prompt
    /// the user to confirm. See spec §7 (Tier 2 discussion).
    case ambiguous([Note])
}

/// Decides whether an already-built list of candidate notes represents a
/// clear match, no match, or an ambiguous match for a newly-appeared window.
///
/// Building the candidate list (e.g. a broader bundle-ID + generic-title
/// search, since `identity_key` is unique in storage and an exact-key
/// lookup can only ever yield 0 or 1 results) is out of scope here — see
/// spec §7 and §12 item 1.
public enum AmbiguousMatchDetector {
    /// Classifies a candidate list into a `MatchResult`.
    ///
    /// - Parameter candidates: The plausible candidate notes for a
    ///   newly-appeared window, in whatever order the caller's search
    ///   produced them. Order is preserved in the `.ambiguous` case.
    /// - Returns: `.none` for zero candidates, `.unambiguous` for exactly
    ///   one, and `.ambiguous` (carrying all of them, in order) for two
    ///   or more.
    public static func resolve(candidates: [Note]) -> MatchResult {
        switch candidates.count {
        case 0:
            return .none
        case 1:
            return .unambiguous(candidates[0])
        default:
            return .ambiguous(candidates)
        }
    }
}
