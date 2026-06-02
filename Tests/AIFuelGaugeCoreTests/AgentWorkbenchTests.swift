import XCTest
@testable import AIFuelGaugeCore

final class AgentWorkbenchTests: XCTestCase {
    func testCollectsQuickRoutesAndRecentSessionsWithoutReadingPromptText() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }

        let claudeProject = home.appendingPathComponent(".claude/projects/-Users-ozan-demo")
        let codexDay = home.appendingPathComponent(".codex/sessions/2026/06/02")
        let codexConfig = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: claudeProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDay, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "model = \"gpt\"".write(to: codexConfig, atomically: true, encoding: .utf8)

        let claudeLog = claudeProject.appendingPathComponent("session.jsonl")
        let codexLog = codexDay.appendingPathComponent("rollout.jsonl")
        try #"{"message":{"content":"do not surface me"}}"#.write(to: claudeLog, atomically: true, encoding: .utf8)
        try #"{"type":"event_msg"}"#.write(to: codexLog, atomically: true, encoding: .utf8)
        try setModificationDate(Date(timeIntervalSince1970: 2_000), for: claudeLog)
        try setModificationDate(Date(timeIntervalSince1970: 3_000), for: codexLog)

        let snapshot = AgentWorkbenchCollector(
            homeDirectory: home,
            now: { Date(timeIntervalSince1970: 3_060) },
            devServerOutput: { nil }
        ).collect()

        XCTAssertEqual(snapshot.sessions.map(\.provider), [.codex, .claudeCode])
        XCTAssertEqual(snapshot.sessions[0].project, "02")
        XCTAssertEqual(snapshot.sessions[1].project, "demo")
        XCTAssertFalse(snapshot.sessions.map(\.detail).joined().contains("do not surface me"))
        XCTAssertTrue(snapshot.routes.contains { $0.title == "Codex config" && $0.exists })
        XCTAssertTrue(snapshot.routes.contains { $0.title == "Claude logs" && $0.exists })
    }

    func testParsesLocalDevServersFromLsofOutput() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    1234 ozan   21u  IPv6  11111      0t0  TCP *:3000 (LISTEN)
        python  2222 ozan    8u  IPv4  22222      0t0  TCP 127.0.0.1:8000 (LISTEN)
        ssh     3333 ozan    9u  IPv4  33333      0t0  TCP 127.0.0.1:22 (LISTEN)
        """

        let servers = LocalDevServerDetector().parse(output)

        XCTAssertEqual(servers.map(\.port), [3000, 8000])
        XCTAssertEqual(servers.map(\.processID), [1234, 2222])
        XCTAssertEqual(servers.map(\.url), ["http://localhost:3000", "http://localhost:8000"])
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
