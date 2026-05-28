import Foundation

public enum Provider: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case claudeCode
    case claude
    case codex
    case openCode
    case openRouter
    case openAI
    case anthropic
    case cursor
    case gemini

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claude: "Claude"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .cursor: "Cursor"
        case .gemini: "Gemini"
        }
    }

    public var shortName: String {
        switch self {
        case .claudeCode: "CC"
        case .claude: "Claude"
        case .codex: "Codex"
        case .openCode: "OC"
        case .openRouter: "OR"
        case .openAI: "OAI"
        case .anthropic: "ANT"
        case .cursor: "Cursor"
        case .gemini: "Gemini"
        }
    }
}

public enum UsageSource: String, Codable, Equatable, Hashable, Sendable {
    case localLogs
    case officialAPI
    case experimentalWebSession
}

public enum MenuBarDisplayMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case detailed
    case pair
    case sparkline
    case compact
    case minimal
}

public struct UsageAccount: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let displayName: String
    public let plan: String?
    public let identityHint: String?

    public init(identifier: String, displayName: String, plan: String? = nil, identityHint: String? = nil) {
        self.identifier = identifier
        self.displayName = displayName
        self.plan = plan
        self.identityHint = identityHint
    }

    public var displayTitle: String {
        guard let plan, !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return displayName
        }
        return "\(displayName) · \(plan)"
    }
}

public enum Confidence: String, Codable, Equatable, Hashable, Sendable {
    case exact
    case estimated
    case unknown
}

public enum UsageState: String, Codable, Equatable, Hashable, Comparable, Sendable {
    case unknown
    case safe
    case caution
    case critical
    case exhausted

    public static func < (lhs: UsageState, rhs: UsageState) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .safe: 1
        case .caution: 2
        case .critical: 3
        case .exhausted: 4
        }
    }
}

public enum UsageQuantity: Codable, Equatable, Hashable, Sendable {
    case credits(Double)
    case usd(Double)
    case requests(Int)
    case percent(Double)
    case tokens(input: Int, output: Int, cacheRead: Int, cacheWrite: Int)

    public var numericValueForLimitComparison: Double? {
        switch self {
        case .credits(let value): value
        case .usd(let value): value
        case .requests(let value): Double(value)
        case .percent(let value): value
        case .tokens(let input, let output, let cacheRead, let cacheWrite):
            Double(input + output + cacheRead + cacheWrite)
        }
    }

    public func isComparable(with other: UsageQuantity) -> Bool {
        switch (self, other) {
        case (.credits, .credits), (.usd, .usd), (.requests, .requests), (.percent, .percent), (.tokens, .tokens): true
        default: false
        }
    }
}

public enum ResetInfo: Codable, Equatable, Hashable, Sendable {
    case rollingWindow(secondsRemaining: TimeInterval)
    case fixed(Date)

    public var secondsRemaining: TimeInterval? {
        switch self {
        case .rollingWindow(let seconds): max(0, seconds)
        case .fixed(let date): max(0, date.timeIntervalSinceNow)
        }
    }

    public var compactTitle: String? {
        guard let secondsRemaining else { return nil }
        let minutes = Int((secondsRemaining / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = Int((Double(minutes) / 60).rounded(.down))
        if hours < 24 { return "\(max(hours, 1))h" }
        let days = max(1, hours / 24)
        return "\(days)d"
    }
}

public struct UsageSnapshot: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String {
        [provider.rawValue, account?.identifier, label]
            .compactMap { $0 }
            .joined(separator: "-")
    }
    public let provider: Provider
    public let source: UsageSource
    public let account: UsageAccount?
    public let label: String
    public let used: UsageQuantity
    public let limit: UsageQuantity?
    public let reset: ResetInfo?
    public let confidence: Confidence
    public let updatedAt: Date

    public init(
        provider: Provider,
        source: UsageSource,
        account: UsageAccount? = nil,
        label: String,
        used: UsageQuantity,
        limit: UsageQuantity?,
        reset: ResetInfo?,
        confidence: Confidence,
        updatedAt: Date
    ) {
        self.provider = provider
        self.source = source
        self.account = account
        self.label = label
        self.used = used
        self.limit = limit
        self.reset = reset
        self.confidence = confidence
        self.updatedAt = updatedAt
    }

    public var usagePercent: Double? {
        guard let limit, used.isComparable(with: limit),
              let usedValue = used.numericValueForLimitComparison,
              let limitValue = limit.numericValueForLimitComparison,
              limitValue > 0 else {
            return nil
        }
        return usedValue / limitValue
    }

    public var state: UsageState {
        guard let usagePercent else { return .unknown }
        if usagePercent >= 1 { return .exhausted }
        if usagePercent >= 0.9 { return .critical }
        if usagePercent >= 0.75 { return .caution }
        return .safe
    }

    public var isSubscriptionOnly: Bool {
        limit == nil && label.localizedCaseInsensitiveContains("subscription")
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let snapshots: [UsageSnapshot]

    public init(snapshots: [UsageSnapshot]) {
        self.snapshots = snapshots
    }

    public var overallState: UsageState {
        snapshots.map(\.state).max() ?? .unknown
    }

    public var primarySnapshot: UsageSnapshot? {
        snapshots
            .sorted(by: Self.prefersForPrimary)
            .first
    }

    public var menuBarTitle: String {
        menuBarTitle(mode: .detailed)
    }

    public func menuBarTitle(mode: MenuBarDisplayMode, history: [String: [Double]] = [:]) -> String {
        guard let primarySnapshot else {
            return "AI usage"
        }
        guard let percent = primarySnapshot.usagePercent else {
            guard primarySnapshot.confidence == .exact, primarySnapshot.source == .officialAPI else {
                return "AI usage"
            }
            return Self.menuBarUnboundedSegment(for: primarySnapshot)
        }
        switch mode {
        case .detailed:
            break
        case .pair:
            let lanes = snapshots
                .filter { $0.usagePercent != nil }
                .sorted(by: Self.prefersForPrimary)
                .prefix(2)
                .map { Self.menuBarSegment(for: $0, includeReset: false) }
            guard lanes.count > 1 else {
                return Self.menuBarSegment(for: primarySnapshot, includeReset: false)
            }
            return lanes.joined(separator: " · ")
        case .compact:
            return Self.menuBarSegment(for: primarySnapshot, includeReset: false)
        case .sparkline:
            let base = Self.menuBarSegment(for: primarySnapshot, includeReset: false)
            guard let sparkline = Self.menuBarSparkline(for: primarySnapshot, history: history[primarySnapshot.id]) else {
                return base
            }
            return "\(base) \(sparkline)"
        case .minimal:
            let percentage: Int
            let qualifier: String
            if Self.prefersRemainingDisplay(primarySnapshot) {
                percentage = Int((max(0, 1 - percent) * 100).rounded())
                qualifier = " left"
            } else {
                percentage = Int((percent * 100).rounded())
                qualifier = ""
            }
            return "\(percentage)%\(qualifier)"
        }
        return Self.menuBarSegment(for: primarySnapshot, includeReset: true)
    }

    private static func menuBarSegment(for snapshot: UsageSnapshot, includeReset: Bool) -> String {
        guard let percent = snapshot.usagePercent else { return snapshot.provider.shortName }
        let percentage: Int
        let qualifier: String
        if prefersRemainingDisplay(snapshot) {
            percentage = Int((max(0, 1 - percent) * 100).rounded())
            qualifier = " left"
        } else {
            percentage = Int((percent * 100).rounded())
            qualifier = ""
        }
        let lane = menuLaneLabel(for: snapshot).map { " \($0)" } ?? ""
        let base = "\(snapshot.provider.shortName)\(lane) \(percentage)%\(qualifier)"
        guard includeReset, let resetTitle = snapshot.reset?.compactTitle else { return base }
        return "\(base) · \(resetTitle)"
    }

    private static func menuBarSparkline(for snapshot: UsageSnapshot, history: [Double]?) -> String? {
        guard snapshot.usagePercent != nil else { return nil }
        let values = (history ?? [])
            .filter(\.isFinite)
            .suffix(8)
            .map { min(max($0, 0), 1) }
        guard values.count >= 2 else { return nil }
        let displayValues = prefersRemainingDisplay(snapshot)
            ? values.map { 1 - $0 }
            : values
        let ticks = Array("▁▂▃▄▅▆▇█")
        return String(displayValues.map { value in
            let index = min(ticks.count - 1, max(0, Int((value * Double(ticks.count - 1)).rounded())))
            return ticks[index]
        })
    }

    private static func menuBarUnboundedSegment(for snapshot: UsageSnapshot) -> String {
        switch snapshot.used {
        case .usd(let value):
            return "\(snapshot.provider.shortName) $\(format(value))"
        case .tokens(let input, let output, let cacheRead, let cacheWrite):
            let total = input + output + cacheRead + cacheWrite
            guard total > 0 else { return snapshot.provider.shortName }
            return "\(snapshot.provider.shortName) \(compact(total)) tok"
        case .credits(let value):
            return "\(snapshot.provider.shortName) \(format(value)) cr"
        case .requests(let value):
            return "\(snapshot.provider.shortName) \(compact(value)) req"
        case .percent(let value):
            return "\(snapshot.provider.shortName) \(Int(value.rounded()))%"
        }
    }

    private static func prefersForPrimary(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) -> Bool {
        if lhs.state != rhs.state { return lhs.state > rhs.state }

        if lhs.provider == .codex, rhs.provider == .codex, lhs.state == .safe {
            let leftPriority = codexLanePriority(lhs)
            let rightPriority = codexLanePriority(rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
        }

        switch (lhs.usagePercent, rhs.usagePercent) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func prefersRemainingDisplay(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.provider == .codex && snapshot.usagePercent != nil
    }

    private static func codexLanePriority(_ snapshot: UsageSnapshot) -> Int {
        let label = snapshot.label.lowercased()
        if label.contains("5h") || label.contains("session") { return 0 }
        if label.contains("weekly") || label.contains("week") || label.contains("7d") { return 2 }
        return 1
    }

    private static func menuLaneLabel(for snapshot: UsageSnapshot) -> String? {
        guard snapshot.provider == .codex else { return nil }
        let label = snapshot.label.lowercased()
        if label.contains("spark") { return "Spark" }
        if label.contains("5h") || label.contains("session") { return "5h" }
        if label.contains("weekly") || label.contains("week") || label.contains("7d") { return "Wk" }
        return nil
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
        if absValue >= 1_000 {
            return sign + String(format: "%.1fK", Double(absValue) / 1_000)
        }
        return "\(value)"
    }

    private static func format(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        return String(format: "%.2f", value)
    }
}

public struct ThresholdTracker: Equatable, Sendable {
    public let thresholds: [Double]

    public init(thresholds: [Double]) {
        self.thresholds = thresholds.sorted()
    }

    public func crossedThresholds(previous: Double, current: Double) -> [Double] {
        guard current > previous else { return [] }
        return thresholds.filter { threshold in
            previous < threshold && current >= threshold
        }
    }
}

public struct UsageAlertEvent: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let thresholdPercent: Double?
    public let provider: Provider
    public let state: UsageState

    public init(identifier: String, title: String, body: String, thresholdPercent: Double?, provider: Provider, state: UsageState) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.thresholdPercent = thresholdPercent
        self.provider = provider
        self.state = state
    }
}

public struct UsageAlertPlanner: Equatable, Sendable {
    public let defaultThresholds: [Double]
    public let providerThresholds: [Provider: [Double]]

    public init(thresholds: [Double] = [0.75, 0.9, 1.0], providerThresholds: [Provider: [Double]] = [:]) {
        self.defaultThresholds = thresholds.sorted()
        self.providerThresholds = providerThresholds.mapValues { $0.sorted() }
    }

    public func alerts(previous: UsageSummary?, current: UsageSummary) -> [UsageAlertEvent] {
        guard let previous else { return [] }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.snapshots.map { ($0.id, $0) })
        return current.snapshots.flatMap { snapshot -> [UsageAlertEvent] in
            guard let currentPercent = snapshot.usagePercent,
                  let previousPercent = previousByID[snapshot.id]?.usagePercent else {
                return []
            }
            let thresholds = thresholds(for: snapshot.provider)
            guard !thresholds.isEmpty else { return [] }
            let tracker = ThresholdTracker(thresholds: thresholds)
            var events = tracker.crossedThresholds(previous: previousPercent, current: currentPercent).map { threshold in
                quotaAlert(for: snapshot, currentPercent: currentPercent, threshold: threshold)
            }
            if let previousSnapshot = previousByID[snapshot.id],
               previousSnapshot.state >= .caution,
               snapshot.state == .safe,
               currentPercent < previousPercent {
                events.append(resetReadyAlert(for: snapshot, currentPercent: currentPercent))
            }
            return events
        }
    }

    private func thresholds(for provider: Provider) -> [Double] {
        providerThresholds[provider] ?? defaultThresholds
    }

    public func staleAlerts(summary: UsageSummary, now: Date, maxAge: TimeInterval = 300) -> [UsageAlertEvent] {
        summary.snapshots.compactMap { snapshot in
            let age = now.timeIntervalSince(snapshot.updatedAt)
            guard age > maxAge else { return nil }
            return UsageAlertEvent(
                identifier: "\(snapshot.id)-stale",
                title: "\(displayTitle(for: snapshot)) is stale",
                body: "Last update was \(relativeAge(age)). Refresh or check the connector.",
                thresholdPercent: nil,
                provider: snapshot.provider,
                state: .unknown
            )
        }
    }

    private func quotaAlert(for snapshot: UsageSnapshot, currentPercent: Double, threshold: Double) -> UsageAlertEvent {
        let percentUsed = Int((currentPercent * 100).rounded())
        let thresholdPercent = Int((threshold * 100).rounded())
        let remaining = max(0, Int(((1 - currentPercent) * 100).rounded()))
        let reset = snapshot.reset?.compactTitle.map { " · resets in \($0)" } ?? ""
        let title = snapshot.provider == .codex
            ? "\(displayTitle(for: snapshot)) has \(remaining)% left"
            : "\(displayTitle(for: snapshot)) is at \(percentUsed)%"
        return UsageAlertEvent(
            identifier: "\(snapshot.id)-\(thresholdPercent)",
            title: title,
            body: "\(remaining)% left\(reset)",
            thresholdPercent: threshold,
            provider: snapshot.provider,
            state: snapshot.state
        )
    }

    private func resetReadyAlert(for snapshot: UsageSnapshot, currentPercent: Double) -> UsageAlertEvent {
        let remaining = max(0, Int(((1 - currentPercent) * 100).rounded()))
        let reset = snapshot.reset?.compactTitle.map { " · next reset in \($0)" } ?? ""
        return UsageAlertEvent(
            identifier: "\(snapshot.id)-reset-ready",
            title: "\(displayTitle(for: snapshot)) is ready again",
            body: "\(remaining)% left\(reset)",
            thresholdPercent: nil,
            provider: snapshot.provider,
            state: .safe
        )
    }

    private func displayTitle(for snapshot: UsageSnapshot) -> String {
        let label = snapshot.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account = snapshot.account {
            let accountName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let plan = account.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountMatchesProvider = accountName.caseInsensitiveCompare(snapshot.provider.displayName) == .orderedSame
            if accountMatchesProvider, let plan, !plan.isEmpty {
                if snapshot.isSubscriptionOnly {
                    return "\(snapshot.provider.displayName) · Subscription"
                }
                if label.isEmpty || label == snapshot.provider.displayName || label == accountName {
                    return "\(snapshot.provider.displayName) · \(plan)"
                }
                return "\(snapshot.provider.displayName) · \(plan) · \(label)"
            }
        }
        guard !label.isEmpty, label != snapshot.provider.displayName else {
            return snapshot.provider.displayName
        }
        if label.localizedCaseInsensitiveContains(snapshot.provider.displayName) {
            return label
        }
        return "\(snapshot.provider.displayName) · \(label)"
    }

    private func relativeAge(_ age: TimeInterval) -> String {
        let seconds = max(0, Int(age))
        if seconds < 45 { return "now" }
        let minutes = max(1, seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = max(1, minutes / 60)
        if hours < 24 { return "\(hours)h ago" }
        return "\(max(1, hours / 24))d ago"
    }
}
