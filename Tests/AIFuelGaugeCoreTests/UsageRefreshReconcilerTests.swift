import XCTest
@testable import AIFuelGaugeCore

final class UsageRefreshReconcilerTests: XCTestCase {
    func testPreservesRecentCursorUsageWhenRefreshFallsBackToSubscriptionOnly() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let previousCursor = UsageSnapshot(
            provider: .cursor,
            source: .experimentalWebSession,
            account: UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: "Pro"),
            label: "Included total",
            used: .percent(42),
            limit: .percent(100),
            reset: .fixed(now.addingTimeInterval(3_600)),
            confidence: .exact,
            updatedAt: now.addingTimeInterval(-600)
        )
        let fallbackCursor = UsageSnapshot(
            provider: .cursor,
            source: .localLogs,
            account: UsageAccount(identifier: "cursor-account-local", displayName: "Cursor", plan: "Pro"),
            label: "Subscription active",
            used: .requests(0),
            limit: nil,
            reset: nil,
            confidence: .unknown,
            updatedAt: now
        )
        let openRouter = UsageSnapshot(
            provider: .openRouter,
            source: .officialAPI,
            label: "OpenRouter credits",
            used: .credits(10),
            limit: .credits(100),
            reset: nil,
            confidence: .exact,
            updatedAt: now
        )

        let reconciler = UsageRefreshReconciler()
        let reconciled = reconciler.reconcile(
            current: UsageSummary(snapshots: [fallbackCursor, openRouter]),
            previous: UsageSummary(snapshots: [previousCursor]),
            now: now
        )

        XCTAssertFalse(reconciled.snapshots.contains(where: \.isSubscriptionOnly))
        XCTAssertTrue(reconciled.snapshots.contains(openRouter))
        let cursor = try XCTUnwrap(reconciled.snapshots.first { $0.provider == .cursor })
        XCTAssertEqual(cursor.usagePercent, 0.42)
        XCTAssertEqual(cursor.updatedAt, now.addingTimeInterval(-600))
        XCTAssertTrue(cursor.providerNote?.contains("showing last successful account usage") == true)
    }

    func testDoesNotPreserveExpiredCursorUsage() {
        let now = Date(timeIntervalSince1970: 100_000)
        let previousCursor = UsageSnapshot(
            provider: .cursor,
            source: .experimentalWebSession,
            label: "Included total",
            used: .percent(20),
            limit: .percent(100),
            reset: nil,
            confidence: .exact,
            updatedAt: now.addingTimeInterval(-25 * 3_600)
        )
        let fallbackCursor = UsageSnapshot(
            provider: .cursor,
            source: .localLogs,
            label: "Subscription active",
            used: .requests(0),
            limit: nil,
            reset: nil,
            confidence: .unknown,
            updatedAt: now
        )

        let reconciled = UsageRefreshReconciler().reconcile(
            current: UsageSummary(snapshots: [fallbackCursor]),
            previous: UsageSummary(snapshots: [previousCursor]),
            now: now
        )

        XCTAssertEqual(reconciled.snapshots, [fallbackCursor])
    }

    func testWarningMessageExplainsPreservedCursorUsage() {
        let now = Date(timeIntervalSince1970: 10_000)
        let previousCursor = UsageSnapshot(
            provider: .cursor,
            source: .experimentalWebSession,
            label: "Included total",
            used: .percent(42),
            limit: .percent(100),
            reset: nil,
            confidence: .exact,
            updatedAt: now
        )
        let fallbackCursor = UsageSnapshot(
            provider: .cursor,
            source: .localLogs,
            label: "Subscription active",
            used: .requests(0),
            limit: nil,
            reset: nil,
            confidence: .unknown,
            updatedAt: now
        )
        let current = UsageSummary(snapshots: [fallbackCursor])
        let reconciler = UsageRefreshReconciler()
        let reconciled = reconciler.reconcile(
            current: current,
            previous: UsageSummary(snapshots: [previousCursor]),
            now: now
        )

        let warning = reconciler.warningMessage(
            original: "Cursor usage unavailable, using subscription fallback",
            current: current,
            reconciled: reconciled
        )

        XCTAssertEqual(
            warning,
            "Cursor live refresh failed; showing last successful usage. Open Cursor once if this stays stale."
        )
    }
}
