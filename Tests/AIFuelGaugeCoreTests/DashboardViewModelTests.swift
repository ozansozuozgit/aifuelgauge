import XCTest
@testable import AIFuelGaugeCore

final class DashboardViewModelTests: XCTestCase {
    func testBuildsConciseRowsForDetectedSourcesAndProviderUsage() {
        let snapshots = [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "main",
                used: .credits(76),
                limit: .credits(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            UsageSnapshot(
                provider: .claudeCode,
                source: .localLogs,
                label: "Claude Code",
                used: .tokens(input: 100, output: 20, cacheRead: 300, cacheWrite: 40),
                limit: nil,
                reset: nil,
                confidence: .estimated,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ]

        let model = DashboardViewModel(summary: UsageSummary(snapshots: snapshots))

        XCTAssertEqual(model.title, "OR 76% · 1h")
        XCTAssertEqual(model.rows.map(\.title), ["OpenRouter", "Claude Code"])
        XCTAssertEqual(model.rows.map(\.detail), ["76% used · exact", "460 tokens · estimated"])
    }
}
