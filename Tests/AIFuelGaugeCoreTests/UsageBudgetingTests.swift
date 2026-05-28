import XCTest
@testable import AIFuelGaugeCore

final class UsageBudgetingTests: XCTestCase {
    func testAppliesUserOpenAIBudgetToCurrentMonthSpend() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            UsageSnapshot(
                provider: .openAI,
                source: .officialAPI,
                label: "Current month costs",
                used: .usd(75),
                limit: nil,
                reset: .fixed(Date(timeIntervalSince1970: 200)),
                confidence: .exact,
                updatedAt: now
            )
        ]

        let budgeted = UsageBudgetApplier.apply(
            preferences: UsageBudgetPreferences(openAIMonthlyUSD: 100),
            to: snapshots
        )

        XCTAssertEqual(budgeted.first?.limit, .usd(100))
        XCTAssertEqual(budgeted.first?.usagePercent, 0.75)
        XCTAssertEqual(budgeted.first?.state, .caution)
    }

    func testIgnoresMissingOrInvalidBudgetsInsteadOfInventingLimits() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = UsageSnapshot(
            provider: .openAI,
            source: .officialAPI,
            label: "Current month costs",
            used: .usd(75),
            limit: nil,
            reset: nil,
            confidence: .exact,
            updatedAt: now
        )

        XCTAssertNil(UsageBudgetPreferences(openAIMonthlyUSD: -1).openAIMonthlyUSD)
        XCTAssertNil(UsageBudgetApplier.apply(preferences: UsageBudgetPreferences(), to: [snapshot]).first?.limit)
        XCTAssertNil(UsageBudgetApplier.apply(preferences: UsageBudgetPreferences(openAIMonthlyUSD: -1), to: [snapshot]).first?.limit)
    }

    func testDoesNotApplyOpenAIBudgetToTokenActivityOrOtherProviders() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            UsageSnapshot(
                provider: .openAI,
                source: .officialAPI,
                label: "Current month tokens",
                used: .tokens(input: 1, output: 2, cacheRead: 3, cacheWrite: 0),
                limit: nil,
                reset: nil,
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                label: "Included spend",
                used: .usd(70),
                limit: nil,
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ]

        let budgeted = UsageBudgetApplier.apply(
            preferences: UsageBudgetPreferences(openAIMonthlyUSD: 100),
            to: snapshots
        )

        XCTAssertTrue(budgeted.allSatisfy { $0.limit == nil })
    }
}
