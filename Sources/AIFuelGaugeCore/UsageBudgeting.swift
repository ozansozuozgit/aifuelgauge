import Foundation

public struct UsageBudgetPreferences: Equatable, Sendable {
    public let openAIMonthlyUSD: Double?

    public init(openAIMonthlyUSD: Double? = nil) {
        self.openAIMonthlyUSD = Self.positive(openAIMonthlyUSD)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

public enum UsageBudgetApplier {
    public static func apply(preferences: UsageBudgetPreferences, to snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        snapshots.map { snapshot in
            applyOpenAIBudget(preferences.openAIMonthlyUSD, to: snapshot)
        }
    }

    private static func applyOpenAIBudget(_ budget: Double?, to snapshot: UsageSnapshot) -> UsageSnapshot {
        guard let budget,
              snapshot.provider == .openAI,
              snapshot.limit == nil,
              snapshot.label.localizedCaseInsensitiveContains("cost"),
              case .usd = snapshot.used else {
            return snapshot
        }
        return UsageSnapshot(
            provider: snapshot.provider,
            source: snapshot.source,
            account: snapshot.account,
            label: snapshot.label,
            used: snapshot.used,
            limit: .usd(budget),
            reset: snapshot.reset,
            confidence: snapshot.confidence,
            updatedAt: snapshot.updatedAt
        )
    }
}
