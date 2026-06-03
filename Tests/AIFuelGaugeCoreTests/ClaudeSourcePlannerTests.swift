import XCTest
@testable import AIFuelGaugeCore

final class ClaudeSourcePlannerTests: XCTestCase {
    private func percentLane(_ label: String, _ pct: Double, source: UsageSource) -> UsageSnapshot {
        UsageSnapshot(provider: .claudeCode, source: source, label: label,
                      used: .percent(pct), limit: .percent(100), reset: nil,
                      confidence: .exact, updatedAt: Date())
    }
    private func tokenLane() -> UsageSnapshot {
        UsageSnapshot(provider: .claudeCode, source: .localLogs, label: "Claude Code",
                      used: .tokens(input: 1, output: 1, cacheRead: 0, cacheWrite: 0),
                      limit: nil, reset: nil, confidence: .estimated, updatedAt: Date())
    }

    func testOAuthSupersedesStatuslinePercentLanes() {
        let local = [percentLane("5h", 90, source: .localLogs), tokenLane()]
        let oauth = [percentLane("5h", 7, source: .officialAPI)]
        let merged = ClaudeSourcePlanner.plan(local: local, oauth: oauth)
        XCTAssertEqual(merged.filter { $0.label == "5h" }.count, 1)
        XCTAssertEqual(merged.first { $0.label == "5h" }?.used, .percent(7))
        XCTAssertTrue(merged.contains { $0.label == "Claude Code" })
    }

    func testNoOAuthKeepsLocal() {
        let local = [percentLane("5h", 90, source: .localLogs), tokenLane()]
        let merged = ClaudeSourcePlanner.plan(local: local, oauth: [])
        XCTAssertEqual(merged.count, 2)
    }

    func testLeavesOtherProvidersUntouched() {
        let codex = UsageSnapshot(provider: .codex, source: .localLogs, label: "5h",
                                  used: .percent(50), limit: .percent(100), reset: nil,
                                  confidence: .exact, updatedAt: Date())
        let merged = ClaudeSourcePlanner.plan(local: [codex], oauth: [percentLane("5h", 7, source: .officialAPI)])
        XCTAssertTrue(merged.contains { $0.provider == .codex })
    }
}
