import Foundation

public struct UsageRefreshReconciler: Sendable {
    public let cursorGracePeriod: TimeInterval

    public init(cursorGracePeriod: TimeInterval = 24 * 3600) {
        self.cursorGracePeriod = max(0, cursorGracePeriod)
    }

    public func reconcile(current: UsageSummary, previous: UsageSummary?, now: Date = Date()) -> UsageSummary {
        preserveRecentCursorUsage(current: current, previous: previous, now: now)
    }

    public func warningMessage(original: String?, current: UsageSummary, reconciled: UsageSummary) -> String? {
        var parts = (original ?? "")
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Cursor usage unavailable, using subscription fallback" }

        if didPreserveCursorUsage(current: current, reconciled: reconciled) {
            parts.append("Cursor live refresh failed; showing last successful usage. Open Cursor once if this stays stale.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func preserveRecentCursorUsage(current: UsageSummary, previous: UsageSummary?, now: Date) -> UsageSummary {
        guard !hasExactCursorUsage(current.snapshots),
              hasCursorFallback(current.snapshots),
              let previous else {
            return current
        }

        let preserved = previous.snapshots
            .filter(isExactCursorUsage)
            .filter { now.timeIntervalSince($0.updatedAt) <= cursorGracePeriod }
            .map {
                $0.withProviderNote("Live Cursor refresh failed; showing last successful account usage. Open Cursor once while signed in if this stays stale.")
            }
        guard !preserved.isEmpty else { return current }

        let nonCursorSnapshots = current.snapshots.filter { $0.provider != .cursor }
        return UsageSummary(snapshots: nonCursorSnapshots + preserved)
    }

    private func didPreserveCursorUsage(current: UsageSummary, reconciled: UsageSummary) -> Bool {
        !hasExactCursorUsage(current.snapshots) && hasExactCursorUsage(reconciled.snapshots)
    }

    private func hasExactCursorUsage(_ snapshots: [UsageSnapshot]) -> Bool {
        snapshots.contains(where: isExactCursorUsage)
    }

    private func hasCursorFallback(_ snapshots: [UsageSnapshot]) -> Bool {
        snapshots.contains { $0.provider == .cursor && $0.isSubscriptionOnly }
    }

    private func isExactCursorUsage(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.provider == .cursor
            && snapshot.source == .experimentalWebSession
            && snapshot.confidence == .exact
            && snapshot.usagePercent?.isFinite == true
            && !snapshot.isSubscriptionOnly
    }
}
