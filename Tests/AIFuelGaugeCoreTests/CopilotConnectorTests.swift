import XCTest
@testable import AIFuelGaugeCore

private final class CopilotStubTransport: HTTPTransport {
    let data: Data
    let status: Int
    var lastRequest: URLRequest?
    init(data: Data, status: Int = 200) { self.data = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

final class CopilotConnectorTests: XCTestCase {

    func testTokenReaderParsesAppsJSON() {
        let json = #"{"github.com:Iv1.b507a08c87ecfe98":{"user":"u","oauth_token":"gho_abc"}}"#
        XCTAssertEqual(CopilotTokenReader.parseToken(fileData: Data(json.utf8)), "gho_abc")
    }

    func testTokenReaderParsesHostsJSON() {
        let json = #"{"github.com":{"user":"u","oauth_token":"gho_xyz"}}"#
        XCTAssertEqual(CopilotTokenReader.parseToken(fileData: Data(json.utf8)), "gho_xyz")
    }

    func testUsageParserMapsPremiumAndChat() throws {
        let json = """
        {"copilot_plan":"pro","quota_reset_date":"2026-06-01",
         "quota_snapshots":{
           "premium_interactions":{"entitlement":100,"remaining":45,"percent_remaining":45},
           "chat":{"entitlement":50,"remaining":20,"percent_remaining":40}}}
        """
        let now = Date(timeIntervalSince1970: 1_000_000)
        let rows = try CopilotUsageParser.parse(data: Data(json.utf8), now: now)
        XCTAssertEqual(rows.map(\.label), ["Premium", "Chat"])
        XCTAssertEqual(rows.first?.used, .percent(55))      // 100 - 45
        XCTAssertEqual(rows.first?.provider, .copilot)
        XCTAssertEqual(rows.first?.confidence, .exact)
        XCTAssertEqual(rows.first?.account?.plan, "Pro")
        XCTAssertNotNil(rows.first?.reset)
    }

    func testUsageParserDerivesPercentWhenMissing() throws {
        let json = """
        {"copilot_plan":"business","quota_snapshots":{
          "premium_interactions":{"entitlement":200,"remaining":50}}}
        """
        let rows = try CopilotUsageParser.parse(data: Data(json.utf8), now: Date())
        XCTAssertEqual(rows.first?.used, .percent(75))       // 100 - (50/200*100)
        XCTAssertEqual(rows.first?.account?.plan, "Business")
    }

    func testUsageParserSkipsPlaceholderQuotas() throws {
        let json = """
        {"copilot_plan":"business","quota_snapshots":{
          "premium_interactions":{"entitlement":0,"remaining":0}}}
        """
        let rows = try CopilotUsageParser.parse(data: Data(json.utf8), now: Date())
        XCTAssertTrue(rows.isEmpty)
    }

    func testConnectorSendsTokenHeader() async throws {
        let body = Data(#"{"copilot_plan":"pro","quota_snapshots":{"chat":{"entitlement":10,"remaining":5,"percent_remaining":50}}}"#.utf8)
        let transport = CopilotStubTransport(data: body)
        let connector = CopilotConnector(transport: transport)
        let rows = try await connector.fetchUsage(token: "gho_tok")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "token gho_tok")
        XCTAssertEqual(rows.first?.used, .percent(50))
    }
}
