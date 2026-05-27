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
        XCTAssertEqual(model.insight, "Start watching OpenRouter · main: 24% left.")
        XCTAssertEqual(model.trustDigest, "1 exact · 1 estimated")
        XCTAssertEqual(model.footerNote, "Account live · local fallback")
        XCTAssertEqual(model.sourceHealth, [
            DashboardSourceHealthItem(id: "live", title: "Live", value: "1", state: .safe),
            DashboardSourceHealthItem(id: "fallback", title: "Fallback", value: "1", state: .safe)
        ])
        XCTAssertEqual(model.primaryGauge?.title, "OpenRouter · main")
        XCTAssertEqual(model.primaryGauge?.value, "76%")
        XCTAssertEqual(model.primaryGauge?.subtitle, "Exact · resets in 1h")
        XCTAssertEqual(model.primaryGauge?.caption, "24 credits left")
        XCTAssertEqual(model.rows.map(\.title), ["OpenRouter · main", "Claude Code"])
        XCTAssertEqual(model.rows.map(\.value), ["76% used", "460 tokens"])
        XCTAssertEqual(model.rows.map(\.detail), ["24 credits left · resets in 1h · Exact · API · 1m ago", "in 100 · out 20 · cache 340 · Estimated · local · 1m ago"])
        XCTAssertEqual(model.rows[0].meterPercent, 0.76)
        XCTAssertEqual(model.rows[0].meterLabel, "24 credits left")
        XCTAssertEqual(model.rows[0].trendPercents, [])
        XCTAssertEqual(model.rows[0].explanation, "Exact from official OpenRouter API. Shows comparable credits with remaining capacity and refresh freshness.")
        XCTAssertEqual(model.rows[1].meterPercent, nil)
        XCTAssertEqual(model.rows[1].explanation, "Estimated from local Claude Code usage metadata. Token totals are approximate and no prompt text is stored.")
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
                provider: .codex,
                source: .localLogs,
                label: "5h",
                used: .percent(17),
                limit: nil,
                reset: nil,
                confidence: .unknown,
                updatedAt: Date(timeIntervalSince1970: 0)
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

        XCTAssertEqual(model.rows.map(\.title), ["Claude Code", "Codex · 5h", "OpenCode"])
        XCTAssertEqual(model.rows.map(\.value), ["2.86B tokens", "Waiting", "No data"])
        XCTAssertEqual(model.rows.map(\.detail), ["in 2.00B · out 800.00M · cache 62.39M · Estimated · local · now", "Expired window · local · last event 1m ago", "Unknown · local · now"])
        XCTAssertEqual(model.rows[1].explanation, "Last seen 17% used before reset. Waiting for Codex to emit a fresh 5h quota event; not showing expired data as current.")
        XCTAssertNil(model.primaryGauge)
    }

    func testRowsUseSnapshotIdentitySoOneProviderCanAppearMoreThanOnce() {
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "OpenRouter key",
                used: .credits(10),
                limit: .credits(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "OpenRouter credits",
                used: .credits(25),
                limit: .credits(200),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ]), now: now)

        XCTAssertEqual(Set(model.rows.map(\.id)).count, 2)
        XCTAssertEqual(model.rows.map(\.title), ["OpenRouter credits", "OpenRouter key"])
    }

    func testSameProviderSameLaneCanRepresentMultipleSubscriptions() {
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .claude,
                source: .officialAPI,
                account: UsageAccount(identifier: "personal", displayName: "Personal", plan: "Pro"),
                label: "5h",
                used: .percent(62),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .claude,
                source: .officialAPI,
                account: UsageAccount(identifier: "work", displayName: "Work", plan: "Team"),
                label: "5h",
                used: .percent(28),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: now
            )
        ]), now: now)

        XCTAssertEqual(Set(model.rows.map(\.id)).count, 2)
        XCTAssertEqual(model.rows.map(\.id).sorted(), ["claude-personal-5h", "claude-work-5h"])
        XCTAssertEqual(model.rows.map(\.title), ["Claude · Personal · Pro · 5h", "Claude · Work · Team · 5h"])
    }

    func testLongResetsUseCalendarCopyAndInsightRecommendsBestLane() {
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        let now = ISO8601DateFormatter().date(from: "2026-05-27T18:37:00Z")!
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .codex,
                source: .localLogs,
                label: "5h",
                used: .percent(5),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 4 * 60),
                confidence: .exact,
                updatedAt: now.addingTimeInterval(-3 * 3600)
            ),
            UsageSnapshot(
                provider: .codex,
                source: .localLogs,
                label: "Weekly",
                used: .percent(43),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 74 * 3600),
                confidence: .exact,
                updatedAt: now.addingTimeInterval(-3 * 3600)
            )
        ]), now: now)

        XCTAssertEqual(model.title, "Codex 5h 95% left · 4m")
        XCTAssertEqual(model.insight, "Use Codex · 5h now: 95% left. Weekly reserve is 57% left.")
        XCTAssertEqual(model.primaryGauge?.value, "95%")
        XCTAssertEqual(model.primaryGauge?.subtitle, "Exact · left · resets in 4m")
        XCTAssertEqual(model.primaryGauge?.caption, "5% used")
        XCTAssertEqual(model.rows.map(\.title), ["Codex · Weekly"])
        XCTAssertEqual(model.rows.map(\.value), ["57% left"])
        XCTAssertEqual(model.rows.map(\.detail), [
            "43% used · resets Sat 4 PM (3d 2h) · Exact · local · 3h ago"
        ])
    }

    func testResetTimelineShowsSoonestWindowsWithCapacity() {
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "main",
                used: .credits(76),
                limit: .credits(100),
                reset: .rollingWindow(secondsRemaining: 7_200),
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                label: "5h",
                used: .percent(5),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 240),
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: "Pro"),
                label: "Included total",
                used: .percent(59),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3_600),
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .claude,
                source: .officialAPI,
                label: "5h",
                used: .percent(20),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 9_000),
                confidence: .exact,
                updatedAt: now
            )
        ]), now: now)

        XCTAssertEqual(model.resetTimeline, [
            DashboardResetItem(id: "codex-5h", title: "Codex · 5h", detail: "reset window · 95% left", value: "4m", state: .safe),
            DashboardResetItem(id: "cursor-cursor-account-Included total", title: "Cursor · Pro · Included total", detail: "reset window · 41% left", value: "1h", state: .safe),
            DashboardResetItem(id: "openRouter-main", title: "OpenRouter · main", detail: "reset window · 24 credits left", value: "2h", state: .caution)
        ])
    }

    func testCodexAccountUsageReadsAsRemainingCapacity() {
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                label: "5h",
                used: .percent(14),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                label: "Weekly",
                used: .percent(46),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 72 * 3600),
                confidence: .exact,
                updatedAt: now
            )
        ]), now: now)

        XCTAssertEqual(model.title, "Codex 5h 86% left · 1h")
        XCTAssertEqual(model.footerNote, "Account live")
        XCTAssertEqual(model.rows.map(\.title), ["Codex · Weekly"])
        XCTAssertEqual(model.rows.map(\.value), ["54% left"])
        XCTAssertEqual(model.rows[0].detail, "46% used · resets Sat 7 PM (3d) · Exact · account · now")
        XCTAssertEqual(model.rows[0].explanation, "")
    }

    func testSourceHealthFlagsFallbackSetupAndStaleSources() {
        let now = Date(timeIntervalSince1970: 1_000)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: "Pro"),
                label: "Included total",
                used: .percent(59),
                limit: .percent(100),
                reset: nil,
                confidence: .exact,
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
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ]), now: now)

        XCTAssertEqual(model.sourceHealth, [
            DashboardSourceHealthItem(id: "live", title: "Live", value: "1", state: .safe),
            DashboardSourceHealthItem(id: "fallback", title: "Fallback", value: "1", state: .safe),
            DashboardSourceHealthItem(id: "setup", title: "Setup", value: "1", state: .unknown),
            DashboardSourceHealthItem(id: "stale", title: "Stale", value: "1", state: .caution)
        ])
    }

    func testSetupGuidanceExplainsMissingSourcesWhenNothingExactIsConnected() {
        let model = DashboardViewModel(summary: UsageSummary(snapshots: []), now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(model.setupGuidance, [
            DashboardSetupItem(
                id: "codex-missing",
                title: "Codex",
                status: "Not detected",
                action: "Run Codex once, then refresh to pick up quota metadata.",
                state: .unknown
            ),
            DashboardSetupItem(
                id: "cursor-missing",
                title: "Cursor",
                status: "Not detected",
                action: "Open Cursor while signed in so the local account state can be read.",
                state: .unknown
            ),
            DashboardSetupItem(
                id: "openrouter-missing",
                title: "OpenRouter",
                status: "API key missing",
                action: "Paste an API key in Settings for exact credit usage.",
                state: .unknown
            )
        ])
    }

    func testSetupGuidanceOnlyShowsActionableFallbacksWhenExactSourcesExist() {
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                label: "5h",
                used: .percent(20),
                limit: .percent(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .cursor,
                source: .localLogs,
                account: UsageAccount(identifier: "cursor-local", displayName: "Cursor", plan: "Pro"),
                label: "Subscription active",
                used: .requests(0),
                limit: nil,
                reset: nil,
                confidence: .unknown,
                updatedAt: now
            )
        ]), now: now)

        XCTAssertEqual(model.setupGuidance, [
            DashboardSetupItem(
                id: "cursor-subscription-only",
                title: "Cursor",
                status: "Plan found, usage missing",
                action: "Open Cursor while signed in, then refresh for live account usage.",
                state: .caution
            )
        ])
    }

    func testRowsExposeBoundedUsageHistoryForSparklines() {
        let now = Date(timeIntervalSince1970: 100)
        let older = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "key",
                used: .credits(20),
                limit: .credits(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ])
        let current = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "key",
                used: .credits(45),
                limit: .credits(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ])
        var history = UsageHistorySeries(maxSamples: 3)
        history.record(summary: older, now: now)
        history.record(summary: current, now: now.addingTimeInterval(60))

        let model = DashboardViewModel(summary: current, now: now, history: history.percentsBySnapshotID)

        XCTAssertEqual(model.rows.first?.trendPercents, [0.2, 0.45])
        XCTAssertEqual(model.rows.first?.trendCaption, "7d peak 45% · up 25 pts")
    }

    func testTrendCaptionSummarizesSteadyAndFallingUsage() {
        let now = Date(timeIntervalSince1970: 100)
        let current = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "key",
                used: .credits(20),
                limit: .credits(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ])

        var falling = UsageHistorySeries(maxSamples: 3)
        falling.record(summary: UsageSummary(snapshots: [
            UsageSnapshot(provider: .openRouter, source: .officialAPI, label: "key", used: .credits(60), limit: .credits(100), reset: nil, confidence: .exact, updatedAt: now)
        ]), now: now)
        falling.record(summary: current, now: now.addingTimeInterval(60))

        let fallingModel = DashboardViewModel(summary: current, now: now, history: falling.percentsBySnapshotID)
        XCTAssertEqual(fallingModel.rows.first?.trendCaption, "7d peak 60% · down 40 pts")

        let steadyHistory = ["openRouter-key": [0.199, 0.201]]
        let steadyModel = DashboardViewModel(summary: current, now: now, history: steadyHistory)
        XCTAssertEqual(steadyModel.rows.first?.trendCaption, "7d peak 20% · steady")
    }

    func testDiagnosticsReportIsCopyableAndSanitized() {
        let generatedAt = Date(timeIntervalSince1970: 200)
        let updatedAt = Date(timeIntervalSince1970: 100)
        let summary = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: "Pro"),
                label: "API usage",
                used: .percent(100),
                limit: .percent(100),
                reset: nil,
                confidence: .exact,
                updatedAt: updatedAt
            )
        ])
        let history = UsageHistorySeries(maxSamples: 3, samplesBySnapshotID: [
            "cursor-cursor-account-API usage": [
                UsageHistorySample(recordedAt: updatedAt, percent: 1)
            ]
        ])

        let report = DashboardDiagnosticsReport.make(
            summary: summary,
            history: history,
            historyPath: "/tmp/usage-history.json",
            refreshError: "Cursor usage unavailable, using subscription fallback",
            generatedAt: generatedAt
        )

        XCTAssertTrue(report.contains("AI Fuel Gauge Diagnostics"))
        XCTAssertTrue(report.contains("History path: /tmp/usage-history.json"))
        XCTAssertTrue(report.contains("Cursor / Cursor · Pro / API usage: 100% used, exhausted, exact, experimentalWebSession"))
        XCTAssertTrue(report.contains("cursor-cursor-account-API usage: 1 samples, latest 100%"))
        XCTAssertTrue(report.contains("Privacy: diagnostics include source names, status, timestamps, and percentages only."))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("token:"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("sk-"))
    }

    func testStatusSnapshotIsCompactAndSanitized() {
        let generatedAt = Date(timeIntervalSince1970: 200)
        let now = Date(timeIntervalSince1970: 100)
        let model = DashboardViewModel(summary: UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                label: "5h",
                used: .percent(20),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: now
            ),
            UsageSnapshot(
                provider: .cursor,
                source: .localLogs,
                account: UsageAccount(identifier: "cursor-local", displayName: "Cursor", plan: "Pro"),
                label: "Subscription active",
                used: .requests(0),
                limit: nil,
                reset: nil,
                confidence: .unknown,
                updatedAt: now
            )
        ]), now: now)

        let snapshot = DashboardStatusSnapshot.make(model: model, generatedAt: generatedAt)

        XCTAssertTrue(snapshot.contains("AI Fuel Gauge Status"))
        XCTAssertTrue(snapshot.contains("Menu: Codex 5h 80% left · 1h"))
        XCTAssertTrue(snapshot.contains("Primary: Codex · 5h · 80% · Exact · left · resets in 1h"))
        XCTAssertTrue(snapshot.contains("Cursor: Plan found, usage missing · Open Cursor while signed in, then refresh for live account usage."))
        XCTAssertTrue(snapshot.contains("Privacy: status includes source names, percentages, and timing only."))
        XCTAssertFalse(snapshot.localizedCaseInsensitiveContains("token:"))
        XCTAssertFalse(snapshot.localizedCaseInsensitiveContains("sk-"))
    }

    func testViewModelUsesConfiguredMenuBarDisplayMode() {
        let now = Date(timeIntervalSince1970: 100)
        let summary = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .codex,
                source: .experimentalWebSession,
                label: "5h",
                used: .percent(14),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: now
            )
        ])

        let model = DashboardViewModel(summary: summary, now: now, menuBarDisplayMode: .compact)

        XCTAssertEqual(model.title, "Codex 5h 86% left")
    }

    func testUsageHistoryPrunesMissingRowsAndKeepsRecentSamplesOnly() {
        let now = Date(timeIntervalSince1970: 100)
        var history = UsageHistorySeries(maxSamples: 2)
        history.record(summary: UsageSummary(snapshots: [
            UsageSnapshot(provider: .openRouter, source: .officialAPI, label: "key", used: .credits(10), limit: .credits(100), reset: nil, confidence: .exact, updatedAt: now),
            UsageSnapshot(provider: .cursor, source: .experimentalWebSession, label: "API usage", used: .percent(25), limit: .percent(100), reset: nil, confidence: .exact, updatedAt: now)
        ]), now: now)
        history.record(summary: UsageSummary(snapshots: [
            UsageSnapshot(provider: .openRouter, source: .officialAPI, label: "key", used: .credits(20), limit: .credits(100), reset: nil, confidence: .exact, updatedAt: now)
        ]), now: now.addingTimeInterval(60))
        history.record(summary: UsageSummary(snapshots: [
            UsageSnapshot(provider: .openRouter, source: .officialAPI, label: "key", used: .credits(30), limit: .credits(100), reset: nil, confidence: .exact, updatedAt: now)
        ]), now: now.addingTimeInterval(120))

        XCTAssertEqual(history.percentsBySnapshotID, ["openRouter-key": [0.2, 0.3]])
    }

    func testUsageHistoryFileStorePersistsBoundedSamples() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("usage-history.json")
        let store = UsageHistoryFileStore(fileURL: fileURL, maxSamples: 2)
        let now = Date(timeIntervalSince1970: 100)
        let history = UsageHistorySeries(maxSamples: 4, samplesBySnapshotID: [
            "openRouter-key": [
                UsageHistorySample(recordedAt: now, percent: 0.1),
                UsageHistorySample(recordedAt: now.addingTimeInterval(60), percent: 0.2),
                UsageHistorySample(recordedAt: now.addingTimeInterval(120), percent: 0.3)
            ],
            "cursor-api": [UsageHistorySample(recordedAt: now, percent: 1.0)]
        ])

        try store.save(history)
        let loaded = store.load()

        XCTAssertEqual(loaded.maxSamples, 2)
        XCTAssertEqual(loaded.percentsBySnapshotID, [
            "cursor-api": [1.0],
            "openRouter-key": [0.2, 0.3]
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try store.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testUsageHistoryPrunesSamplesOlderThanRetention() {
        let now = Date(timeIntervalSince1970: 10_000)
        var history = UsageHistorySeries(maxSamples: 10, retention: 120)
        history.record(summary: UsageSummary(snapshots: [
            UsageSnapshot(provider: .openRouter, source: .officialAPI, label: "key", used: .credits(10), limit: .credits(100), reset: nil, confidence: .exact, updatedAt: now)
        ]), now: now.addingTimeInterval(-180))
        history.record(summary: UsageSummary(snapshots: [
            UsageSnapshot(provider: .openRouter, source: .officialAPI, label: "key", used: .credits(20), limit: .credits(100), reset: nil, confidence: .exact, updatedAt: now)
        ]), now: now)

        XCTAssertEqual(history.percentsBySnapshotID, ["openRouter-key": [0.2]])
    }

    func testUsageHistoryFileStoreMigratesLegacyPercentArrays() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("usage-history.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(
            """
            {
              "maxSamples": 96,
              "samplesBySnapshotID": {
                "openRouter-key": [0.1, 0.2, 0.3]
              }
            }
            """.utf8
        ).write(to: fileURL)

        let loaded = UsageHistoryFileStore(fileURL: fileURL, maxSamples: 2).load()

        XCTAssertEqual(loaded.percentsBySnapshotID, ["openRouter-key": [0.2, 0.3]])
    }

    func testUsageHistoryDashboardSummarizesLocalSamples() {
        let now = Date(timeIntervalSince1970: 1_000)
        let summary = UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: "Pro"),
                label: "Included total",
                used: .percent(90),
                limit: .percent(100),
                reset: nil,
                confidence: .exact,
                updatedAt: now
            )
        ])
        let history = UsageHistorySeries(maxSamples: 4, samplesBySnapshotID: [
            "cursor-cursor-account-Included total": [
                UsageHistorySample(recordedAt: now.addingTimeInterval(-600), percent: 0.25),
                UsageHistorySample(recordedAt: now.addingTimeInterval(-60), percent: 0.90)
            ],
            "openRouter-key": [
                UsageHistorySample(recordedAt: now.addingTimeInterval(-120), percent: 0.40)
            ]
        ])

        let dashboard = UsageHistoryDashboard(history: history, summary: summary, now: now)

        XCTAssertEqual(dashboard.title, "Usage history")
        XCTAssertEqual(dashboard.subtitle, "2 lanes · local 7-day file")
        XCTAssertEqual(dashboard.items.map(\.title), ["Cursor · Pro · Included total", "OpenRouter Key"])
        XCTAssertEqual(dashboard.items.map(\.latestValue), ["90%", "40%"])
        XCTAssertEqual(dashboard.items.map(\.peakValue), ["peak 90%", "peak 40%"])
        XCTAssertEqual(dashboard.items.map(\.deltaValue), ["+65 pts", "steady"])
        XCTAssertEqual(dashboard.items.map(\.detail), ["2 samples · latest 1m ago", "1 sample · latest 2m ago"])
        XCTAssertEqual(dashboard.items.map(\.state), [.critical, .safe])
        XCTAssertEqual(
            dashboard.csvText,
            """
            snapshot_id,title,recorded_at,usage_percent
            "cursor-cursor-account-Included total","Cursor · Pro · Included total","1970-01-01T00:06:40.000Z","25"
            "cursor-cursor-account-Included total","Cursor · Pro · Included total","1970-01-01T00:15:40.000Z","90"
            "openRouter-key","OpenRouter Key","1970-01-01T00:14:40.000Z","40"
            """
        )
    }
}
