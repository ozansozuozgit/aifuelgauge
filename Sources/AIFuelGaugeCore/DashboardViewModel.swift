import Foundation

public struct DashboardGauge: Equatable, Sendable {
    public let title: String
    public let value: String
    public let subtitle: String
    public let caption: String
    public let percent: Double
    public let state: UsageState
    public let confidence: Confidence

    public init(title: String, value: String, subtitle: String, caption: String, percent: Double, state: UsageState, confidence: Confidence) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.caption = caption
        self.percent = percent
        self.state = state
        self.confidence = confidence
    }
}

public struct DashboardRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let detail: String
    public let explanation: String
    public let meterPercent: Double?
    public let meterLabel: String?
    public let confidence: Confidence
    public let state: UsageState

    public init(id: String, title: String, value: String, detail: String, explanation: String, meterPercent: Double?, meterLabel: String?, confidence: Confidence, state: UsageState) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
        self.explanation = explanation
        self.meterPercent = meterPercent
        self.meterLabel = meterLabel
        self.confidence = confidence
        self.state = state
    }
}

public struct DashboardViewModel: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let insight: String
    public let trustDigest: String
    public let statusLabel: String
    public let footerNote: String
    public let primaryGauge: DashboardGauge?
    public let rows: [DashboardRow]
    public let state: UsageState

    public init(summary: UsageSummary, now: Date = Date()) {
        self.title = summary.menuBarTitle
        self.state = summary.overallState
        self.statusLabel = Self.statusLabel(for: summary.overallState)
        self.subtitle = Self.subtitle(for: summary, now: now)
        self.insight = Self.insight(for: summary)
        self.trustDigest = Self.trustDigest(for: summary)
        self.footerNote = "Local monitoring · No cloud sync"
        self.primaryGauge = summary.primarySnapshot.flatMap { Self.gauge(for: $0) }
        self.rows = summary.snapshots
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state > rhs.state }
                return lhs.provider.displayName < rhs.provider.displayName
            }
            .map { snapshot in
                DashboardRow(
                    id: snapshot.id,
                    title: Self.rowTitle(for: snapshot),
                    value: Self.value(for: snapshot),
                    detail: Self.detail(for: snapshot, now: now),
                    explanation: Self.explanation(for: snapshot),
                    meterPercent: snapshot.usagePercent.map { min(max($0, 0), 1) },
                    meterLabel: Self.remainingLabel(for: snapshot),
                    confidence: snapshot.confidence,
                    state: snapshot.state
                )
            }
    }

    private static func gauge(for snapshot: UsageSnapshot) -> DashboardGauge? {
        guard let usagePercent = snapshot.usagePercent else { return nil }
        let clamped = min(max(usagePercent, 0), 1)
        let reset = snapshot.reset?.compactTitle.map { "resets in \($0)" } ?? "live quota"
        let value = "\(Int((usagePercent * 100).rounded()))%"
        return DashboardGauge(
            title: Self.rowTitle(for: snapshot),
            value: value,
            subtitle: "\(confidenceLabel(snapshot.confidence)) · \(reset)",
            caption: remainingLabel(for: snapshot) ?? "Limit window active",
            percent: clamped,
            state: snapshot.state,
            confidence: snapshot.confidence
        )
    }

    private static func subtitle(for summary: UsageSummary, now: Date) -> String {
        guard let newest = summary.snapshots.map(\.updatedAt).max() else {
            return "No sources yet"
        }
        return "Updated \(relativeTime(from: newest, now: now))"
    }

    private static func statusLabel(for state: UsageState) -> String {
        switch state {
        case .safe: "Safe"
        case .caution: "Watch"
        case .critical: "Near limit"
        case .exhausted: "Blocked"
        case .unknown: "Learning"
        }
    }

    private static func insight(for summary: UsageSummary) -> String {
        guard !summary.snapshots.isEmpty else {
            return "Add one exact source, then the menu bar can warn before you stall."
        }
        guard let snapshot = summary.primarySnapshot, let percent = snapshot.usagePercent else {
            let localCount = summary.snapshots.filter { $0.source == .localLogs }.count
            return "\(localCount) local source\(localCount == 1 ? "" : "s") found. Exact limits still need metadata."
        }
        let remaining = max(0, Int(((1 - percent) * 100).rounded()))
        switch snapshot.state {
        case .safe:
            return "Keep going. Tightest lane still has \(remaining)% headroom."
        case .caution:
            return "Start watching \(rowTitle(for: snapshot)): \(remaining)% left."
        case .critical:
            return "Save your flow. \(rowTitle(for: snapshot)) has only \(remaining)% left."
        case .exhausted:
            return "This lane is spent. Switch provider or wait for reset."
        case .unknown:
            return "Sources found, but no comparable limit yet."
        }
    }

    private static func trustDigest(for summary: UsageSummary) -> String {
        let exact = summary.snapshots.filter { $0.confidence == .exact }.count
        let estimated = summary.snapshots.filter { $0.confidence == .estimated }.count
        let unknown = summary.snapshots.filter { $0.confidence == .unknown }.count
        var parts: [String] = []
        if exact > 0 { parts.append("\(exact) exact") }
        if estimated > 0 { parts.append("\(estimated) estimated") }
        if unknown > 0 { parts.append("\(unknown) unknown") }
        return parts.isEmpty ? "No sources" : parts.joined(separator: " · ")
    }

    private static func rowTitle(for snapshot: UsageSnapshot) -> String {
        let label = snapshot.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label != snapshot.provider.displayName else {
            return snapshot.provider.displayName
        }
        if label.localizedCaseInsensitiveContains(snapshot.provider.displayName) {
            return label
        }
        return "\(snapshot.provider.displayName) · \(label)"
    }

    private static func remainingLabel(for snapshot: UsageSnapshot) -> String? {
        guard let limit = snapshot.limit,
              snapshot.used.isComparable(with: limit),
              let used = snapshot.used.numericValueForLimitComparison,
              let total = limit.numericValueForLimitComparison,
              total > 0 else {
            return nil
        }
        let remaining = max(0, total - used)
        switch (snapshot.used, limit) {
        case (.percent, .percent):
            return "\(Int(remaining.rounded()))% left"
        case (.credits, .credits):
            return "\(format(remaining)) credits left"
        case (.usd, .usd):
            return "$\(format(remaining)) left"
        case (.requests, .requests):
            return "\(compact(Int(remaining.rounded()))) requests left"
        case (.tokens, .tokens):
            return "\(compact(Int(remaining.rounded()))) tokens left"
        default:
            return nil
        }
    }

    private static func tokenBreakdown(for quantity: UsageQuantity) -> String? {
        guard case let .tokens(input, output, cacheRead, cacheWrite) = quantity else { return nil }
        let cache = cacheRead + cacheWrite
        if input + output + cache == 0 { return nil }
        return "in \(compact(input)) · out \(compact(output)) · cache \(compact(cache))"
    }

    private static func explanation(for snapshot: UsageSnapshot) -> String {
        switch (snapshot.provider, snapshot.source, snapshot.confidence) {
        case (.openRouter, .officialAPI, .exact):
            return "Exact from official OpenRouter API. Shows comparable credits with remaining capacity and refresh freshness."
        case (.codex, .localLogs, .exact):
            return "Exact from local Codex rate-limit metadata. Reads quota window, reset time, and percent without prompt text."
        case (.codex, .localLogs, .unknown):
            return "Last local Codex \(snapshot.label) window has expired. Waiting for a fresh Codex rate-limit event; not showing the stale percent as current usage."
        case (.claudeCode, .localLogs, .estimated):
            return "Estimated from local Claude Code usage metadata. Token totals are approximate and no prompt text is stored."
        case (.openCode, .localLogs, .unknown):
            return "Detected OpenCode locally, but usage parsing is not wired yet. Treat this lane as setup needed."
        case (_, .officialAPI, .exact):
            return "Exact from the provider API. Shows comparable quota data and refresh freshness."
        case (_, .localLogs, .estimated):
            return "Estimated from local usage metadata. Good for trend awareness, not a hard provider limit."
        case (_, .localLogs, .exact):
            return "Exact from local rate-limit metadata exposed by the tool. No prompt text is stored."
        default:
            return "Source is detected, but the app cannot yet prove a comparable limit."
        }
    }

    private static func detail(for snapshot: UsageSnapshot, now: Date) -> String {
        var parts: [String] = []
        if let remaining = remainingLabel(for: snapshot) {
            parts.append(remaining)
        } else if let breakdown = tokenBreakdown(for: snapshot.used) {
            parts.append(breakdown)
        }
        if let reset = snapshot.reset?.compactTitle {
            parts.append("resets \(reset)")
        }
        parts.append(confidenceLabel(snapshot.confidence))
        parts.append(sourceLabel(snapshot.source))
        parts.append(relativeTime(from: snapshot.updatedAt, now: now))
        return parts.joined(separator: " · ")
    }

    private static func value(for snapshot: UsageSnapshot) -> String {
        if let usagePercent = snapshot.usagePercent {
            return "\(Int((usagePercent * 100).rounded()))% used"
        }

        if snapshot.confidence == .unknown {
            return "No data"
        }

        switch snapshot.used {
        case .tokens(let input, let output, let cacheRead, let cacheWrite):
            let total = input + output + cacheRead + cacheWrite
            if total == 0 { return "No tokens" }
            return "\(compact(total)) tokens"
        case .credits(let value):
            return "\(format(value)) credits"
        case .usd(let value):
            return "$\(format(value))"
        case .requests(let value):
            return "\(compact(value)) requests"
        case .percent(let value):
            return "\(Int(value.rounded()))%"
        }
    }

    private static func confidenceLabel(_ confidence: Confidence) -> String {
        switch confidence {
        case .exact: "Exact"
        case .estimated: "Estimated"
        case .unknown: "Unknown"
        }
    }

    private static func sourceLabel(_ source: UsageSource) -> String {
        switch source {
        case .localLogs: "local"
        case .officialAPI: "API"
        case .experimentalWebSession: "experimental"
        }
    }

    private static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "now" }
        let minutes = max(1, seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = max(1, minutes / 60)
        if hours < 24 { return "\(hours)h ago" }
        let days = max(1, hours / 24)
        return "\(days)d ago"
    }

    private static func compact(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 1_000_000_000 {
            return sign + String(format: "%.2fB", Double(absValue) / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return sign + String(format: "%.2fM", Double(absValue) / 1_000_000)
        }
        if absValue >= 10_000 {
            return sign + String(format: "%.1fK", Double(absValue) / 1_000)
        }
        return grouped(value)
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
