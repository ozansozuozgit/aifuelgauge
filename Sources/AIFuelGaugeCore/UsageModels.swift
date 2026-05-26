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
        return "\(max(hours, 1))h"
    }
}

public struct UsageSnapshot: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { "\(provider.rawValue)-\(label)" }
    public let provider: Provider
    public let source: UsageSource
    public let label: String
    public let used: UsageQuantity
    public let limit: UsageQuantity?
    public let reset: ResetInfo?
    public let confidence: Confidence
    public let updatedAt: Date

    public init(
        provider: Provider,
        source: UsageSource,
        label: String,
        used: UsageQuantity,
        limit: UsageQuantity?,
        reset: ResetInfo?,
        confidence: Confidence,
        updatedAt: Date
    ) {
        self.provider = provider
        self.source = source
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
            .sorted { lhs, rhs in
                switch (lhs.usagePercent, rhs.usagePercent) {
                case let (left?, right?): return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.updatedAt > rhs.updatedAt
                }
            }
            .first
    }

    public var menuBarTitle: String {
        guard let primarySnapshot, let percent = primarySnapshot.usagePercent else {
            return "AI usage"
        }
        let percentage = Int((percent * 100).rounded())
        if let resetTitle = primarySnapshot.reset?.compactTitle {
            return "\(primarySnapshot.provider.shortName) \(percentage)% · \(resetTitle)"
        }
        return "\(primarySnapshot.provider.shortName) \(percentage)%"
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
