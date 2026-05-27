import XCTest
import SQLite3
@testable import AIFuelGaugeCore

final class LocalAgentUsageTests: XCTestCase {
    func testDetectsClaudeCodexAndOpenCodeLocalSourcesUnderHomeDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/share/opencode"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Application Support/Cursor"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: home.appendingPathComponent(".local/share/opencode/opencode.db").path, contents: Data())

        let sources = LocalAgentDetector(homeDirectory: home).detectedSources()

        XCTAssertEqual(sources.map(\.provider), [.claudeCode, .codex, .openCode, .cursor])
        XCTAssertEqual(sources.map(\.kind), [.jsonlDirectory, .jsonlDirectory, .sqliteDatabase, .directory])
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
        XCTAssertNil(snapshot.account)
        XCTAssertNil(snapshot.limit)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.updatedAt, Date(timeIntervalSince1970: 1_779_797_100))
    }

    func testReadsCursorPlanFromLocalStateDatabaseWithoutHardcodingPlan() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cursorDir = home.appendingPathComponent("Library/Application Support/Cursor")
        let dbURL = cursorDir.appendingPathComponent("User/globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.createCursorStateDatabase(at: dbURL, values: [
            "cursorAuth/stripeMembershipType": "pro",
            "cursorAuth/stripeSubscriptionStatus": "active",
            "cursorAuth/cachedEmail": "user@example.com"
        ])

        let state = try XCTUnwrap(CursorAccountStateReader(cursorDirectory: cursorDir).read())

        XCTAssertEqual(state.membershipType, "pro")
        XCTAssertEqual(state.displayPlan, "Pro")
        XCTAssertEqual(state.displayStatus, "active")
        XCTAssertEqual(state.email, "user@example.com")
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

    func testCodexUsesNewestTimestampInsteadOfLastLineWhenFilesAreReadNewestFirst() throws {
        let lines = [
            """
            {"timestamp":"2026-05-26T23:45:22.288Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1779853890},"secondary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1780174797}}}}
            """,
            """
            {"timestamp":"2026-05-26T21:54:02.235Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":48.0,"window_minutes":300,"resets_at":1779835472},"secondary":{"used_percent":37.0,"window_minutes":10080,"resets_at":1780174797}}}}
            """
        ]

        let snapshots = try CodexJSONLUsageParser(now: { Date(timeIntervalSince1970: 1779850000) }).parseRateLimits(lines: lines)

        XCTAssertEqual(snapshots.map(\.used), [.percent(17), .percent(42)])
        XCTAssertEqual(snapshots.map(\.updatedAt), [
            Date(timeIntervalSince1970: 1_779_839_122.288),
            Date(timeIntervalSince1970: 1_779_839_122.288)
        ])
    }

    func testCodexExpiredWindowIsNoDataInsteadOfStaleExactPercent() throws {
        let lines = [
            """
            {"timestamp":"2026-05-26T23:45:22.288Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1779853890},"secondary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1780174797}}}}
            """
        ]

        let snapshots = try CodexJSONLUsageParser(now: { Date(timeIntervalSince1970: 1779879706) }).parseRateLimits(lines: lines)

        XCTAssertEqual(snapshots.map(\.label), ["5h", "Weekly"])
        XCTAssertEqual(snapshots[0].confidence, .unknown)
        XCTAssertNil(snapshots[0].limit)
        XCTAssertNil(snapshots[0].usagePercent)
        XCTAssertEqual(snapshots[0].reset, nil)
        XCTAssertEqual(snapshots[1].confidence, .exact)
        XCTAssertEqual(snapshots[1].used, .percent(42))
        XCTAssertEqual(snapshots[1].reset, .rollingWindow(secondsRemaining: 295091))
    }

    static func createCursorStateDatabase(at url: URL, values: [String: String]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);", nil, nil, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "INSERT INTO ItemTable (key, value) VALUES (?, ?);", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        for (key, value) in values {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        }
    }
}
