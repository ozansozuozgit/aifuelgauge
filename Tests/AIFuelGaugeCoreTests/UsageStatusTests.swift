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

    func testExactOfficialSpendCanShowInMenuBarWithoutAQuotaLimit() {
        let openAI = UsageSnapshot(
            provider: .openAI,
            source: .officialAPI,
            label: "Current month costs",
            used: .usd(42.5),
            limit: nil,
            reset: nil,
            confidence: .exact,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let summary = UsageSummary(snapshots: [openAI])

        XCTAssertEqual(summary.primarySnapshot?.usagePercent, nil)
        XCTAssertEqual(summary.menuBarTitle, "OAI $42.50")
    }

    func testCodexMenuBarPrefersSessionLaneWhileWeeklyIsHealthy() {
        let summary = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.14, reset: 3600),
            snapshot(provider: .codex, label: "Weekly", percent: 0.46, reset: 72 * 3600)
        ])

        XCTAssertEqual(summary.primarySnapshot?.label, "5h")
        XCTAssertEqual(summary.menuBarTitle, "Codex 5h 86% left · 1h")
    }

    func testCodexMenuBarShowsWeeklyWhenWeeklyIsActuallyConstrained() {
        let summary = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.14, reset: 3600),
            snapshot(provider: .codex, label: "Weekly", percent: 0.82, reset: 72 * 3600)
        ])

        XCTAssertEqual(summary.primarySnapshot?.label, "Weekly")
        XCTAssertEqual(summary.menuBarTitle, "Codex Wk 18% left · 3d")
    }

    func testMenuBarDisplayModesTradeDetailForSpace() {
        let summary = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.14, reset: 3600)
        ])

        XCTAssertEqual(summary.menuBarTitle(mode: .detailed), "Codex 5h 86% left · 1h")
        XCTAssertEqual(summary.menuBarTitle(mode: .pair), "Codex 5h 86% left")
        XCTAssertEqual(summary.menuBarTitle(mode: .sparkline), "Codex 5h 86% left")
        XCTAssertEqual(summary.menuBarTitle(mode: .compact), "Codex 5h 86% left")
        XCTAssertEqual(summary.menuBarTitle(mode: .minimal), "86% left")
    }

    func testSparklineMenuBarModeUsesHistoryForPrimaryLane() {
        let summary = UsageSummary(snapshots: [
            snapshot(provider: .cursor, label: "Included total", percent: 0.55, reset: 3600)
        ])
        let id = summary.primarySnapshot!.id

        XCTAssertEqual(
            summary.menuBarTitle(mode: .sparkline, history: [id: [0.1, 0.25, 0.5, 0.75]]),
            "Cursor 55% ▂▃▅▆"
        )
    }

    func testSparklineMenuBarModeShowsCodexHeadroomTrend() {
        let summary = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.75, reset: 3600)
        ])
        let id = summary.primarySnapshot!.id

        XCTAssertEqual(
            summary.menuBarTitle(mode: .sparkline, history: [id: [0.25, 0.5, 0.75]]),
            "Codex 5h 25% left ▆▅▃"
        )
    }

    func testPairMenuBarModeShowsTwoMostRelevantComparableLanes() {
        let summary = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.14, reset: 3600),
            snapshot(provider: .cursor, label: "Included total", percent: 0.59, reset: 7200),
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: "Pro"),
                label: "Included spend",
                used: .usd(20),
                limit: nil,
                reset: .rollingWindow(secondsRemaining: 7200),
                confidence: .exact,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ])

        XCTAssertEqual(summary.menuBarTitle(mode: .pair), "Cursor 59% · Codex 5h 86% left")
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
        XCTAssertEqual(alerts.last?.title, "Codex · 5h has 9% left")
        XCTAssertEqual(alerts.last?.body, "9% left · resets in 10m")
        XCTAssertEqual(alerts.last?.identifier, "codex-5h-90")
    }

    func testAlertPlannerUsesProviderSpecificThresholds() {
        let earlier = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.74, reset: 3600),
            snapshot(provider: .cursor, label: "Included total", percent: 0.74, reset: 3600),
            snapshot(provider: .openRouter, label: "main", percent: 0.74, reset: 3600)
        ])
        let later = UsageSummary(snapshots: [
            snapshot(provider: .codex, label: "5h", percent: 0.80, reset: 600),
            snapshot(provider: .cursor, label: "Included total", percent: 0.80, reset: 600),
            snapshot(provider: .openRouter, label: "main", percent: 0.80, reset: 600)
        ])
        let planner = UsageAlertPlanner(
            thresholds: [0.75],
            providerThresholds: [
                .codex: [0.90],
                .cursor: []
            ]
        )

        let alerts = planner.alerts(previous: earlier, current: later)

        XCTAssertEqual(alerts.map(\.identifier), ["openRouter-main-75"])
        XCTAssertEqual(alerts.map(\.provider), [.openRouter])
    }

    func testDashboardRowsShowSubscriptionPlansWithoutFakeQuotaData() {
        let summary = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .cursor,
                source: .localLogs,
                account: UsageAccount(identifier: "cursor-local", displayName: "Cursor", plan: "Pro"),
                label: "Subscription active",
                used: .requests(0),
                limit: nil,
                reset: nil,
                confidence: .unknown,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                account: UsageAccount(identifier: "codex-account", displayName: "Codex", plan: "Pro"),
                label: "5h",
                used: .percent(18),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ])

        let model = DashboardViewModel(summary: summary, now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(model.primaryGauge?.title, "Codex · Pro · 5h")
        XCTAssertEqual(model.rows.map(\.title), ["Cursor · Subscription"])
        XCTAssertEqual(model.rows.map(\.value), ["Pro"])
        XCTAssertNil(model.rows.first?.meterPercent)
    }

    func testAlertPlannerEmitsResetReadyWhenAConstrainedLaneRefreshes() {
        let earlier = UsageSummary(snapshots: [snapshot(provider: .codex, label: "5h", percent: 0.91, reset: 120)])
        let later = UsageSummary(snapshots: [snapshot(provider: .codex, label: "5h", percent: 0.08, reset: 5 * 3600)])
        let planner = UsageAlertPlanner(thresholds: [0.75, 0.9])

        let alerts = planner.alerts(previous: earlier, current: later)

        XCTAssertEqual(alerts.map(\.identifier), ["codex-5h-reset-ready"])
        XCTAssertEqual(alerts.map(\.title), ["Codex · 5h is ready again"])
        XCTAssertEqual(alerts.map(\.body), ["92% left · next reset in 5h"])
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
