import XCTest
@testable import AIFuelGaugeCore

final class DashboardViewModelTests: XCTestCase {
    func testBuildsConciseRowsForDetectedSourcesAndProviderUsage() {
        let now = Date(timeIntervalSince1970: 160)
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

        let model = DashboardViewModel(summary: UsageSummary(snapshots: snapshots), now: now)

        XCTAssertEqual(model.title, "OR 76% · 1h")
        XCTAssertEqual(model.subtitle, "Updated 1m ago")
        XCTAssertEqual(model.statusLabel, "Watch")
        XCTAssertEqual(model.primaryGauge?.title, "OpenRouter")
        XCTAssertEqual(model.primaryGauge?.value, "76%")
        XCTAssertEqual(model.primaryGauge?.subtitle, "Exact · resets in 1h")
        XCTAssertEqual(model.rows.map(\.title), ["OpenRouter", "Claude Code"])
        XCTAssertEqual(model.rows.map(\.value), ["76% used", "460 tokens"])
        XCTAssertEqual(model.rows.map(\.detail), ["Exact · API · 1m ago · resets 1h", "Estimated · local · 1m ago"])
    }

    func testFormatsLargeTokenCountsAndUnknownRowsWithoutScaryRawNumbers() {
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .claudeCode,
                source: .localLogs,
                label: "Claude Code",
                used: .tokens(input: 2_000_000_000, output: 800_000_000, cacheRead: 60_000_000, cacheWrite: 2_394_369),
                limit: nil,
                reset: nil,
                confidence: .estimated,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .openCode,
                source: .localLogs,
                label: "OpenCode",
                used: .tokens(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
                limit: nil,
                reset: nil,
                confidence: .unknown,
                updatedAt: now
            )
        ]), now: now)

        XCTAssertEqual(model.rows.map(\.title), ["Claude Code", "OpenCode"])
        XCTAssertEqual(model.rows.map(\.value), ["2.86B tokens", "No data"])
        XCTAssertEqual(model.rows.map(\.detail), ["Estimated · local · now", "Unknown · local · now"])
        XCTAssertNil(model.primaryGauge)
    }
}
