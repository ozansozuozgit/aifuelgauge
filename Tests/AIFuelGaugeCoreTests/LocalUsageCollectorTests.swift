import XCTest
@testable import AIFuelGaugeCore

final class LocalUsageCollectorTests: XCTestCase {
    func testCollectsSnapshotsFromDetectedClaudeCodexAndOpenCodeSources() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let claudeDir = home.appendingPathComponent(".claude/projects/proj")
        let codexDir = home.appendingPathComponent(".codex/sessions/2026/05/26")
        let opencodeDir = home.appendingPathComponent(".local/share/opencode")
        let cursorDir = home.appendingPathComponent("Library/Application Support/Cursor")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: opencodeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
        let cursorDB = cursorDir.appendingPathComponent("User/globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: cursorDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LocalAgentUsageTests.createCursorStateDatabase(at: cursorDB, values: [
            "cursorAuth/stripeMembershipType": "pro",
            "cursorAuth/stripeSubscriptionStatus": "active"
        ])
        try """
        {"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":3,"cache_read_input_tokens":4,"cache_creation_input_tokens":5}}}
        """.write(to: claudeDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-05-26T12:10:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":66.0,"window_minutes":300,"resets_at":2600}}}}
        """.write(to: codexDir.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: opencodeDir.appendingPathComponent("opencode.db").path, contents: Data())

        let collector = LocalUsageCollector(
            homeDirectory: home,
            now: { Date(timeIntervalSince1970: 2000) },
            planPreferences: LocalPlanPreferences(claudeCodePlan: "Free")
        )
        let snapshots = try collector.collect()

        XCTAssertEqual(snapshots.map(\.provider), [.claudeCode, .codex, .openCode, .cursor])
        XCTAssertEqual(snapshots[0].used, .tokens(input: 10, output: 3, cacheRead: 4, cacheWrite: 5))
        XCTAssertEqual(snapshots[0].account?.plan, "Free")
        XCTAssertEqual(snapshots[1].used, .percent(66))
        XCTAssertEqual(snapshots[2].confidence, .unknown)
        XCTAssertEqual(snapshots[3].label, "Subscription active")
        XCTAssertEqual(snapshots[3].account?.plan, "Pro")
        XCTAssertTrue(snapshots[3].isSubscriptionOnly)
    }
}
