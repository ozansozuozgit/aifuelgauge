import Foundation

public struct DashboardGauge: Equatable {
    public let title: String
    public let value: String
    public let subtitle: String
    public let percent: Double
    public let state: UsageState
    public let confidence: Confidence

    public init(title: String, value: String, subtitle: String, percent: Double, state: UsageState, confidence: Confidence) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.percent = percent
        self.state = state
        self.confidence = confidence
    }
}

public struct DashboardRow: Equatable, Identifiable {
    public var id: String { title }
    public let title: String
    public let value: String
    public let detail: String
    public let confidence: Confidence
    public let state: UsageState

    public init(title: String, value: String, detail: String, confidence: Confidence, state: UsageState) {
        self.title = title
        self.value = value
        self.detail = detail
        self.confidence = confidence
        self.state = state
    }
}

public struct DashboardViewModel: Equatable {
    public let title: String
    public let subtitle: String
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
        self.footerNote = "Local monitoring · No cloud sync"
        self.primaryGauge = summary.primarySnapshot.flatMap { Self.gauge(for: $0) }
        self.rows = summary.snapshots
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state > rhs.state }
                return lhs.provider.displayName < rhs.provider.displayName
            }
            .map { snapshot in
                DashboardRow(
                    title: snapshot.provider.displayName,
                    value: Self.value(for: snapshot),
                    detail: Self.detail(for: snapshot, now: now),
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
            title: snapshot.provider.displayName,
            value: value,
            subtitle: "\(confidenceLabel(snapshot.confidence)) · \(reset)",
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

    private static func detail(for snapshot: UsageSnapshot, now: Date) -> String {
        var parts = [confidenceLabel(snapshot.confidence), sourceLabel(snapshot.source), relativeTime(from: snapshot.updatedAt, now: now)]
        if let reset = snapshot.reset?.compactTitle {
            parts.append("resets \(reset)")
        }
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
