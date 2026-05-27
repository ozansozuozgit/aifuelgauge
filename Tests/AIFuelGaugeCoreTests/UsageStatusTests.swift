import XCTest
@testable import AIFuelGaugeCore

final class UsageStatusTests: XCTestCase {
    func testQuotaPercentAndStateUseWorstKnownProvider() {
        let openRouter = UsageSnapshot(
            provider: .openRouter,
            source: .officialAPI,
            label: "OpenRouter main key",
            used: .credits(76),
            limit: .credits(100),
            reset: .rollingWindow(secondsRemaining: 3600),
            confidence: .exact,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let codex = UsageSnapshot(
            provider: .codex,
            source: .localLogs,
            label: "Codex local",
            used: .usd(1.2),
            limit: nil,
            reset: nil,
            confidence: .estimated,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let summary = UsageSummary(snapshots: [openRouter, codex])

        XCTAssertEqual(summary.overallState, .caution)
        XCTAssertEqual(summary.primarySnapshot?.provider, .openRouter)
        XCTAssertEqual(summary.primarySnapshot?.usagePercent ?? -1, 0.76, accuracy: 0.001)
        XCTAssertEqual(summary.menuBarTitle, "OR 76% · 1h")
    }

    func testUnknownLimitsStayInformativeWithoutPretendingExactness() {
        let claudeCode = UsageSnapshot(
            provider: .claudeCode,
            source: .localLogs,
            label: "Claude Code",
            used: .tokens(input: 1000, output: 400, cacheRead: 200, cacheWrite: 0),
            limit: nil,
            reset: nil,
            confidence: .estimated,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let summary = UsageSummary(snapshots: [claudeCode])

        XCTAssertEqual(summary.overallState, .unknown)
        XCTAssertEqual(summary.primarySnapshot?.usagePercent, nil)
        XCTAssertEqual(summary.menuBarTitle, "AI usage")
    }

    func testNotificationThresholdsOnlyFireOnceWhenCrossedUpwards() {
        let thresholds = ThresholdTracker(thresholds: [0.5, 0.75, 0.9])

        XCTAssertEqual(thresholds.crossedThresholds(previous: 0.49, current: 0.50), [0.5])
        XCTAssertEqual(thresholds.crossedThresholds(previous: 0.60, current: 0.74), [])
        XCTAssertEqual(thresholds.crossedThresholds(previous: 0.74, current: 0.91), [0.75, 0.9])
        XCTAssertEqual(thresholds.crossedThresholds(previous: 0.91, current: 0.80), [])
    }

    func testAlertPlannerEmitsQuotaCrossingEventsWithoutStartupSpam() {
        let earlier = UsageSummary(snapshots: [snapshot(provider: .codex, label: "5h", percent: 0.74, reset: 3600)])
        let later = UsageSummary(snapshots: [snapshot(provider: .codex, label: "5h", percent: 0.91, reset: 600)])
        let planner = UsageAlertPlanner(thresholds: [0.75, 0.9])

        XCTAssertEqual(planner.alerts(previous: nil, current: later), [])

        let alerts = planner.alerts(previous: earlier, current: later)

        XCTAssertEqual(alerts.map(\.thresholdPercent), [0.75, 0.9])
        XCTAssertEqual(alerts.last?.title, "Codex · 5h is at 91%")
        XCTAssertEqual(alerts.last?.body, "9% left · resets in 10m")
        XCTAssertEqual(alerts.last?.identifier, "codex-5h-90")
    }

    func testAlertPlannerEmitsStaleSourceEvents() {
        let summary = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "OpenRouter key",
                used: .credits(2),
                limit: .credits(10),
                reset: nil,
                confidence: .exact,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ])
        let planner = UsageAlertPlanner()

        let alerts = planner.staleAlerts(summary: summary, now: Date(timeIntervalSince1970: 500), maxAge: 300)

        XCTAssertEqual(alerts.map(\.title), ["OpenRouter key is stale"])
        XCTAssertEqual(alerts.map(\.body), ["Last update was 6m ago. Refresh or check the connector."])
    }

    private func snapshot(provider: Provider, label: String, percent: Double, reset: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            source: .localLogs,
            label: label,
            used: .percent(percent * 100),
            limit: .percent(100),
            reset: .rollingWindow(secondsRemaining: reset),
            confidence: .exact,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
