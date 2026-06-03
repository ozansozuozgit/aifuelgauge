import XCTest
@testable import AIFuelGaugeCore

final class FuelRouterTests: XCTestCase {
    private func lane(_ provider: Provider, _ label: String, usedPercent: Double, resetSeconds: TimeInterval? = 3600) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider, source: .officialAPI, label: label,
            used: .percent(usedPercent), limit: .percent(100),
            reset: resetSeconds.map { .rollingWindow(secondsRemaining: $0) },
            confidence: .exact, updatedAt: Date())
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRecommendsEngineWithMostHeadroom() {
        let snapshots = [
            lane(.claudeCode, "5h", usedPercent: 90),
            lane(.codex, "5h", usedPercent: 12),
            lane(.cursor, "5h", usedPercent: 50),
        ]
        let rec = FuelRouter.recommend(snapshots: snapshots, now: now)
        XCTAssertEqual(rec?.provider, .codex)
        XCTAssertEqual(rec?.remainingPercent, 88)
        XCTAssertEqual(rec?.isConstrained, false)
        XCTAssertEqual(rec?.launchCommand, "codex")
        XCTAssertEqual(rec?.title, "Codex · 5h")
    }

    func testBindingConstraintIsTightestLanePerProvider() {
        // Codex 5h is fresh but its weekly is nearly gone → Codex headroom is low.
        let snapshots = [
            lane(.codex, "5h", usedPercent: 5),
            lane(.codex, "Weekly", usedPercent: 96),
            lane(.claudeCode, "5h", usedPercent: 40),
        ]
        let rec = FuelRouter.recommend(snapshots: snapshots, now: now)
        XCTAssertEqual(rec?.provider, .claudeCode)   // Codex blocked by weekly
        XCTAssertEqual(rec?.remainingPercent, 60)
    }

    func testConstrainedWhenAllTightPointsToSoonestReset() {
        let snapshots = [
            lane(.claudeCode, "5h", usedPercent: 95, resetSeconds: 7200),
            lane(.codex, "5h", usedPercent: 92, resetSeconds: 600),
        ]
        let rec = FuelRouter.recommend(snapshots: snapshots, now: now)
        XCTAssertEqual(rec?.isConstrained, true)
        XCTAssertEqual(rec?.provider, .codex)        // resets soonest (10m)
        XCTAssertTrue(rec?.detail.contains("resets in") == true)
    }

    func testNilWithSingleEngine() {
        let snapshots = [lane(.codex, "5h", usedPercent: 10), lane(.codex, "Weekly", usedPercent: 20)]
        XCTAssertNil(FuelRouter.recommend(snapshots: snapshots, now: now))
    }

    func testIgnoresApiSpendProviders() {
        let codex = lane(.codex, "5h", usedPercent: 30)
        let openAI = UsageSnapshot(provider: .openAI, source: .officialAPI, label: "Current month costs",
                                   used: .usd(5), limit: .usd(100), reset: nil, confidence: .exact, updatedAt: Date())
        // Only one *coding* engine → no recommendation.
        XCTAssertNil(FuelRouter.recommend(snapshots: [codex, openAI], now: now))
    }
}
