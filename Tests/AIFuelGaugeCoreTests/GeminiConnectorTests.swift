import XCTest
@testable import AIFuelGaugeCore

private final class StubTransport: HTTPTransport {
    var responses: [Data]
    var status: Int
    init(responses: [Data], status: Int = 200) { self.responses = responses; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = responses.isEmpty ? Data() : responses.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

final class GeminiConnectorTests: XCTestCase {

    func testCredentialsParse() throws {
        let json = #"{"access_token":"a","refresh_token":"r","expiry_date":1893456000000}"#
        let creds = try GeminiCredentialsReader.parse(fileData: Data(json.utf8))
        XCTAssertEqual(creds.accessToken, "a")
        XCTAssertEqual(creds.refreshToken, "r")
        XCTAssertEqual(creds.expiryDateMillis, 1893456000000)
    }

    func testIsExpiredUnknownExpiryAssumesUsable() {
        let creds = GeminiCredentials(accessToken: "a", refreshToken: nil, expiryDateMillis: nil)
        XCTAssertFalse(creds.isExpired(now: Date()))
    }

    func testQuotaParserMapsBucketsToLanes() throws {
        let json = """
        {"buckets":[
          {"modelId":"gemini-2.5-pro","remainingFraction":0.75,"resetTime":"2026-06-04T00:00:00Z"},
          {"modelId":"gemini-2.5-flash","remainingFraction":0.5,"resetTime":"2026-06-04T00:00:00Z"},
          {"modelId":"gemini-2.5-flash-lite","remainingFraction":0.9,"resetTime":"2026-06-04T00:00:00Z"}
        ]}
        """
        let now = Date(timeIntervalSince1970: 1_000_000)
        let rows = try GeminiQuotaParser.parse(data: Data(json.utf8), tier: "free-tier", now: now)
        XCTAssertEqual(rows.map(\.label), ["Pro", "Flash", "Flash-Lite"])
        XCTAssertEqual(rows.first?.used, .percent(25))      // 1 - 0.75
        XCTAssertEqual(rows.first?.provider, .gemini)
        XCTAssertEqual(rows.first?.confidence, .exact)
        XCTAssertEqual(rows.first?.account?.plan, "Free")
        XCTAssertNotNil(rows.first?.reset)
    }

    func testQuotaParserKeepsLowestRemainingPerModel() throws {
        let json = """
        {"buckets":[
          {"modelId":"gemini-pro","remainingFraction":0.8,"resetTime":"2026-06-04T00:00:00Z"},
          {"modelId":"gemini-pro","remainingFraction":0.3,"resetTime":"2026-06-04T00:00:00Z"}
        ]}
        """
        let rows = try GeminiQuotaParser.parse(data: Data(json.utf8), tier: nil, now: Date())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.used, .percent(70))      // tightest: 1 - 0.3
    }

    func testConnectorFetchesQuotaWithBearer() async throws {
        let tier = Data(#"{"currentTier":{"id":"standard-tier"}}"#.utf8)
        let quota = Data(#"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.4,"resetTime":"2026-06-04T00:00:00Z"}]}"#.utf8)
        let transport = StubTransport(responses: [tier, quota])
        let connector = GeminiConnector(transport: transport)
        let creds = GeminiCredentials(accessToken: "tok", refreshToken: nil, expiryDateMillis: nil)
        let rows = try await connector.fetchUsage(credentials: creds)
        XCTAssertEqual(rows.first?.used, .percent(60))
        XCTAssertEqual(rows.first?.account?.plan, "Paid")
    }
}
