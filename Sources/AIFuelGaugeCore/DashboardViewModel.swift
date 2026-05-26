import Foundation

public struct DashboardRow: Equatable, Identifiable {
    public var id: String { title }
    public let title: String
    public let detail: String
    public let state: UsageState

    public init(title: String, detail: String, state: UsageState) {
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public struct DashboardViewModel: Equatable {
    public let title: String
    public let rows: [DashboardRow]
    public let state: UsageState

    public init(summary: UsageSummary) {
        self.title = summary.menuBarTitle
        self.state = summary.overallState
        self.rows = summary.snapshots.map { snapshot in
            DashboardRow(
                title: snapshot.provider.displayName,
                detail: Self.detail(for: snapshot),
                state: snapshot.state
            )
        }
    }

    private static func detail(for snapshot: UsageSnapshot) -> String {
        let confidence = snapshot.confidence.rawValue
        if let usagePercent = snapshot.usagePercent {
            return "\(Int((usagePercent * 100).rounded()))% used · \(confidence)"
        }
        switch snapshot.used {
        case .tokens(let input, let output, let cacheRead, let cacheWrite):
            return "\(input + output + cacheRead + cacheWrite) tokens · \(confidence)"
        case .credits(let value):
            return "\(format(value)) credits · \(confidence)"
        case .usd(let value):
            return "$\(format(value)) · \(confidence)"
        case .requests(let value):
            return "\(value) requests · \(confidence)"
        case .percent(let value):
            return "\(Int(value.rounded()))% · \(confidence)"
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
