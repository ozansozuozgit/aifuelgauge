import XCTest
@testable import AIFuelGaugeCore

final class LocalAgentUsageTests: XCTestCase {
    func testDetectsClaudeCodexAndOpenCodeLocalSourcesUnderHomeDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/share/opencode"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: home.appendingPathComponent(".local/share/opencode/opencode.db").path, contents: Data())

        let sources = LocalAgentDetector(homeDirectory: home).detectedSources()

        XCTAssertEqual(sources.map(\.provider), [.claudeCode, .codex, .openCode])
        XCTAssertEqual(sources.map(\.kind), [.jsonlDirectory, .jsonlDirectory, .sqliteDatabase])
    }

    func testParsesClaudeJsonlAssistantUsageWithoutReadingMessageText() throws {
        let lines = [
            """
            {"type":"assistant","timestamp":"2026-05-26T12:00:00Z","cwd":"/repo/app","message":{"model":"claude-sonnet-4","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":40}}}
            """,
            """
            {"type":"assistant","timestamp":"2026-05-26T12:05:00Z","cwd":"/repo/app","message":{"model":"claude-sonnet-4","content":[{"type":"text","text":"do not parse me"}],"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":7,"cache_creation_input_tokens":2}}}
            """
        ]

        let snapshot = try ClaudeJSONLUsageParser().parse(lines: lines, label: "Claude Code")

        XCTAssertEqual(snapshot.provider, .claudeCode)
        XCTAssertEqual(snapshot.source, .localLogs)
        XCTAssertEqual(snapshot.used, .tokens(input: 110, output: 25, cacheRead: 307, cacheWrite: 42))
        XCTAssertNil(snapshot.limit)
        XCTAssertEqual(snapshot.confidence, .estimated)
    }

    func testParsesLatestCodexRateLimitTokenCount() throws {
        let lines = [
            """
            {"timestamp":"2026-05-26T12:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":2000},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_at":3000}}}}
            """,
            """
            {"timestamp":"2026-05-26T12:10:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":81.0,"window_minutes":300,"resets_at":2600}}}}
            """
        ]

        let snapshot = try CodexJSONLUsageParser(now: { Date(timeIntervalSince1970: 2000) }).parseLatestRateLimit(lines: lines)

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.used, .percent(81))
        XCTAssertEqual(snapshot.limit, .percent(100))
        XCTAssertEqual(snapshot.reset, .rollingWindow(secondsRemaining: 600))
        XCTAssertEqual(snapshot.state, .caution)
    }

    func testParsesCodexPrimaryAndWeeklyRateLimitLanes() throws {
        let lines = [
            """
            {"timestamp":"2026-05-26T12:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":17.0,"window_minutes":300,"resets_at":2600},"secondary":{"used_percent":42.0,"window_minutes":10080,"resets_at":5000}}}}
            """
        ]

        let snapshots = try CodexJSONLUsageParser(now: { Date(timeIntervalSince1970: 2000) }).parseRateLimits(lines: lines)

        XCTAssertEqual(snapshots.map(\.label), ["5h", "Weekly"])
        XCTAssertEqual(snapshots.map(\.used), [.percent(17), .percent(42)])
        XCTAssertEqual(snapshots.map(\.reset), [.rollingWindow(secondsRemaining: 600), .rollingWindow(secondsRemaining: 3000)])
    }
}
