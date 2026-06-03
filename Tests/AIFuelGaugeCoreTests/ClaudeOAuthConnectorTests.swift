import XCTest
@testable import AIFuelGaugeCore

private final class StubTransport: HTTPTransport {
    let data: Data
    let status: Int
    var lastRequest: URLRequest?
    init(data: Data, status: Int) { self.data = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

final class ClaudeOAuthConnectorTests: XCTestCase {

    // MARK: Credentials reader

    func testCredentialsReaderParsesFileJSON() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"ref-456","expiresAt":1893456000000}}
        """
        let creds = try ClaudeCredentialsReader.parse(fileData: Data(json.utf8))
        XCTAssertEqual(creds.accessToken, "tok-123")
        XCTAssertEqual(creds.refreshToken, "ref-456")
        XCTAssertEqual(creds.expiresAtMillis, 1893456000000)
    }

    func testCredentialsEncodeRoundTrips() throws {
        let creds = ClaudeCredentials(accessToken: "a", refreshToken: "r", expiresAtMillis: 12345)
        let data = try ClaudeCredentialsReader.encode(creds)
        let parsed = try ClaudeCredentialsReader.parse(fileData: data)
        XCTAssertEqual(parsed.accessToken, "a")
        XCTAssertEqual(parsed.refreshToken, "r")
        XCTAssertEqual(parsed.expiresAtMillis, 12345)
    }

    func testIsExpired() {
        let now = Date(timeIntervalSince1970: 1000)
        let valid = ClaudeCredentials(accessToken: "a", refreshToken: nil, expiresAtMillis: (1000 + 600) * 1000)
        let expired = ClaudeCredentials(accessToken: "a", refreshToken: nil, expiresAtMillis: (1000 - 10) * 1000)
        let missing = ClaudeCredentials(accessToken: "a", refreshToken: nil, expiresAtMillis: nil)
        XCTAssertFalse(valid.isExpired(now: now))
        XCTAssertTrue(expired.isExpired(now: now))
        XCTAssertTrue(missing.isExpired(now: now))
    }

    func testLoadFromDiskReturnsNilForMissingHome() {
        XCTAssertNil(ClaudeCredentialsReader.loadFromDisk(home: URL(fileURLWithPath: "/nonexistent-home-xyz")))
    }

    func testWriteBackThenLoadRoundTrips() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let creds = ClaudeCredentials(accessToken: "new-acc", refreshToken: "new-ref", expiresAtMillis: 999)
        try ClaudeCredentialsReader.writeBack(creds, home: home)
        let loaded = try XCTUnwrap(ClaudeCredentialsReader.loadFromDisk(home: home))
        XCTAssertEqual(loaded.accessToken, "new-acc")
        XCTAssertEqual(loaded.refreshToken, "new-ref")
        let perms = try FileManager.default.attributesOfItem(atPath: ClaudeCredentialsReader.credentialsURL(home: home).path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    // MARK: Refresh

    func testRefreshParseRotatesToken() throws {
        let json = """
        {"access_token":"new-acc","refresh_token":"new-ref","expires_in":28800,"token_type":"Bearer"}
        """
        let now = Date(timeIntervalSince1970: 1000)
        let token = try ClaudeTokenRefresher.parse(data: Data(json.utf8), fallbackRefreshToken: "old", now: now)
        XCTAssertEqual(token.accessToken, "new-acc")
        XCTAssertEqual(token.refreshToken, "new-ref")
        XCTAssertEqual(token.expiresAtMillis, (1000 + 28800) * 1000)
    }

    func testRefreshParseFallsBackWhenNoRotation() throws {
        let json = #"{"access_token":"only-acc","expires_in":100}"#
        let token = try ClaudeTokenRefresher.parse(data: Data(json.utf8), fallbackRefreshToken: "keep", now: Date())
        XCTAssertEqual(token.refreshToken, "keep")
    }

    func testRefresherSendsCLIUserAgentAndForm() async throws {
        let body = Data(#"{"access_token":"x","refresh_token":"y","expires_in":1}"#.utf8)
        let transport = StubTransport(data: body, status: 200)
        let refresher = ClaudeTokenRefresher(transport: transport)
        _ = try await refresher.refresh(refreshToken: "ref-1")
        let req = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), ClaudeTokenRefresher.defaultUserAgent)
        let sent = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("grant_type=refresh_token"))
        XCTAssertTrue(sent.contains("refresh_token=ref-1"))
        XCTAssertTrue(sent.contains("client_id="))
    }

    // MARK: Usage parser

    func testParserMapsWindowsToExactPercentLanes() throws {
        let json = """
        {"five_hour":{"utilization":7,"resets_at":"2026-06-03T18:00:00Z"},
         "seven_day":{"utilization":46,"resets_at":"2026-06-08T11:00:00Z"}}
        """
        let now = Date(timeIntervalSince1970: 1_000_000)
        let rows = try ClaudeOAuthUsageParser.parse(data: Data(json.utf8), subscriptionType: "max", now: now)
        let fiveHour = try XCTUnwrap(rows.first { $0.label == "5h" })
        XCTAssertEqual(fiveHour.provider, .claudeCode)
        XCTAssertEqual(fiveHour.source, .officialAPI)
        XCTAssertEqual(fiveHour.confidence, .exact)
        XCTAssertEqual(fiveHour.used, .percent(7))
        XCTAssertEqual(fiveHour.limit, .percent(100))
        XCTAssertEqual(fiveHour.account?.plan, "Max")
        XCTAssertNotNil(fiveHour.reset)
        XCTAssertTrue(rows.contains { $0.label == "Weekly" && $0.used == .percent(46) })
    }

    func testParserParsesMicrosecondResetDates() {
        let date = ClaudeOAuthUsageParser.parseDate("2026-06-03T17:40:00.029958+00:00")
        XCTAssertNotNil(date)
    }

    func testParserHandlesRealFixture() throws {
        let url = Bundle.module.url(forResource: "claude-oauth-usage", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        let rows = try ClaudeOAuthUsageParser.parse(data: data, subscriptionType: nil, now: Date())
        XCTAssertEqual(Set(rows.map(\.label)), ["5h", "Weekly", "Weekly · Sonnet"])
        XCTAssertTrue(rows.allSatisfy { $0.confidence == .exact })
        XCTAssertEqual(rows.first { $0.label == "5h" }?.used, .percent(41))
    }

    // MARK: Connector

    func testConnectorSendsAuthHeadersAndReturnsLanes() async throws {
        let body = Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-06-03T18:00:00Z"}}"#.utf8)
        let transport = StubTransport(data: body, status: 200)
        let creds = ClaudeCredentials(accessToken: "tok-xyz", refreshToken: nil, expiresAtMillis: nil)
        let connector = ClaudeOAuthConnector(transport: transport)
        let rows = try await connector.fetchUsage(credentials: creds)
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-xyz")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(rows.first?.used, .percent(12))
    }

    func testConnectorThrowsOnBadStatus() async {
        let transport = StubTransport(data: Data(), status: 401)
        let connector = ClaudeOAuthConnector(transport: transport)
        let creds = ClaudeCredentials(accessToken: "bad", refreshToken: nil, expiresAtMillis: nil)
        do {
            _ = try await connector.fetchUsage(credentials: creds)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .badStatus(401))
        }
    }
}
