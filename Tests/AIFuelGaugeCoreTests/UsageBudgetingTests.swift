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
        XCTAssertNil(UsageBudgetPreferences(cursorMonthlyUSD: 0).cursorMonthlyUSD)
        XCTAssertNil(UsageBudgetPreferences(openRouterMonthlyCredits: .infinity).openRouterMonthlyCredits)
        XCTAssertNil(UsageBudgetApplier.apply(preferences: UsageBudgetPreferences(), to: [snapshot]).first?.limit)
        XCTAssertNil(UsageBudgetApplier.apply(preferences: UsageBudgetPreferences(openAIMonthlyUSD: -1), to: [snapshot]).first?.limit)
    }

    func testAppliesUserCursorBudgetToSpendRowsOnly() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                label: "Included spend",
                used: .usd(12.50),
                limit: nil,
                reset: nil,
                confidence: .exact,
                providerNote: "Provider explanation survives local budgets.",
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                label: "Included total",
                used: .percent(42),
                limit: .percent(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ]

        let budgeted = UsageBudgetApplier.apply(
            preferences: UsageBudgetPreferences(cursorMonthlyUSD: 20),
            to: snapshots
        )

        XCTAssertEqual(budgeted[0].limit, .usd(20))
        XCTAssertEqual(budgeted[0].usagePercent, 0.625)
        XCTAssertEqual(budgeted[0].providerNote, "Provider explanation survives local budgets.")
        XCTAssertEqual(budgeted[1].limit, .percent(100))
    }

    func testAppliesUserOpenRouterBudgetOnlyWhenProviderHasNoKeyLimit() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "main",
                used: .credits(8),
                limit: nil,
                reset: nil,
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "OpenRouter credits",
                used: .credits(25),
                limit: .credits(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ]

        let budgeted = UsageBudgetApplier.apply(
            preferences: UsageBudgetPreferences(openRouterMonthlyCredits: 10),
            to: snapshots
        )

        XCTAssertEqual(budgeted[0].limit, .credits(10))
        XCTAssertEqual(budgeted[0].usagePercent, 0.8)
        XCTAssertEqual(budgeted[1].limit, .credits(100))
    }

    func testAppliesOnlyMatchingBudgetTypesAndLeavesUnrelatedRowsAlone() {
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
            ),
            UsageSnapshot(
                provider: .openCode,
                source: .localLogs,
                label: "OpenCode tokens",
                used: .tokens(input: 10, output: 20, cacheRead: 0, cacheWrite: 0),
                limit: nil,
                reset: nil,
                confidence: .estimated,
                updatedAt: now
            )
        ]

        let budgeted = UsageBudgetApplier.apply(
            preferences: UsageBudgetPreferences(
                openAIMonthlyUSD: 100,
                cursorMonthlyUSD: 20,
                openRouterMonthlyCredits: 10
            ),
            to: snapshots
        )

        XCTAssertNil(budgeted[0].limit)
        XCTAssertEqual(budgeted[1].limit, .usd(20))
        XCTAssertNil(budgeted[2].limit)
    }
}
