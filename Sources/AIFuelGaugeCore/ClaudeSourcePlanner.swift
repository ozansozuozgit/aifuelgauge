import Foundation

/// Merges Claude usage sources by confidence: exact OAuth lanes supersede the
/// statusline (`.localLogs` percent) lanes for the same provider; the token
/// estimate lane (no `usagePercent`) is preserved for breakdown context.
///
/// Priority: OAuth-exact → JSONL token estimate. The statusline is intentionally
/// dropped whenever OAuth is the configured path, because the statusline file is
/// per-window and unreliable (each Claude session overwrites it with its own
/// view); we never want to flip to it, even if a given OAuth call failed.
public enum ClaudeSourcePlanner {
    /// - Parameter oauthAvailable: whether Claude OAuth credentials exist at all.
    ///   When true, statusline percent lanes are dropped even if `oauth` is empty
    ///   this cycle (a transient OAuth failure must not surface the bad
    ///   statusline value). Defaults to `!oauth.isEmpty` for callers that don't
    ///   know.
    public static func plan(local: [UsageSnapshot], oauth: [UsageSnapshot], oauthAvailable: Bool? = nil) -> [UsageSnapshot] {
        let suppressStatusline = oauthAvailable ?? !oauth.isEmpty
        guard suppressStatusline else { return local }
        let kept = local.filter { snapshot in
            guard snapshot.provider == .claudeCode else { return true }
            // Drop local-logs percent lanes (the statusline 5h/Weekly), which
            // OAuth replaces. Keep token-estimate / non-percent lanes.
            let isStatuslinePercent = snapshot.source == .localLogs && snapshot.usagePercent != nil
            return !isStatuslinePercent
        }
        return kept + oauth
    }
}
