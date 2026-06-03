import Foundation

/// Merges Claude usage sources by confidence: exact OAuth lanes supersede the
/// statusline (`.localLogs` percent) lanes for the same provider; the token
/// estimate lane (no `usagePercent`) is preserved for breakdown context.
///
/// Priority: OAuth-exact → statusline (exact) → JSONL token estimate.
public enum ClaudeSourcePlanner {
    public static func plan(local: [UsageSnapshot], oauth: [UsageSnapshot]) -> [UsageSnapshot] {
        guard !oauth.isEmpty else { return local }
        let kept = local.filter { snapshot in
            guard snapshot.provider == .claudeCode else { return true }
            // Drop local-logs percent lanes (the statusline 5h/Weekly), which
            // the exact OAuth lanes replace. Keep token-estimate / non-percent.
            let isStatuslinePercent = snapshot.source == .localLogs && snapshot.usagePercent != nil
            return !isStatuslinePercent
        }
        return kept + oauth
    }
}
