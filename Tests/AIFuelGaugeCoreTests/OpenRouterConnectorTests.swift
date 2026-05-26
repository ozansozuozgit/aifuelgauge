import XCTest
@testable import AIFuelGaugeCore

final class OpenRouterConnectorTests: XCTestCase {
    func testFetchesCurrentKeyUsageAsExactCreditSnapshot() async throws {
        let body = """
        {
          "data": {
            "label": "main",
            "limit": 100,
            "limit_reset": "monthly",
            "limit_remaining": 24,
            "include_byok_in_limit": false,
            "usage": 150,
            "usage_daily": 12,
            "usage_weekly": 40,
            "usage_monthly": 99,
            "byok_usage": 0,
            "byok_usage_daily": 0,
            "byok_usage_weekly": 0,
            "byok_usage_monthly": 0,
            "is_free_tier": false
          }
        }
        """.data(using: .utf8)!
        let transport = MockHTTPTransport(responseData: body)
        let connector = OpenRouterConnector(transport: transport, now: { Date(timeIntervalSince1970: 200) })

        let snapshot = try await connector.fetchCurrentKeyUsage(apiKey: "sk-or-test")

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(snapshot.provider, .openRouter)
        XCTAssertEqual(snapshot.source, .officialAPI)
        XCTAssertEqual(snapshot.label, "main")
        XCTAssertEqual(snapshot.used, .credits(76))
        XCTAssertEqual(snapshot.limit, .credits(100))
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.usagePercent ?? -1, 0.76, accuracy: 0.001)
    }

    func testUnlimitedKeyUsesRemainingCreditsWithoutPretendingPercentKnown() async throws {
        let body = """
        {
          "data": {
            "label": "unlimited",
            "limit": null,
            "limit_reset": null,
            "limit_remaining": null,
            "include_byok_in_limit": false,
            "usage": 20,
            "usage_daily": 3,
            "usage_weekly": 8,
            "usage_monthly": 20,
            "byok_usage": 0,
            "byok_usage_daily": 0,
            "byok_usage_weekly": 0,
            "byok_usage_monthly": 0,
            "is_free_tier": false
          }
        }
        """.data(using: .utf8)!
        let connector = OpenRouterConnector(transport: MockHTTPTransport(responseData: body))

        let snapshot = try await connector.fetchCurrentKeyUsage(apiKey: "sk-or-test")

        XCTAssertEqual(snapshot.used, .credits(20))
        XCTAssertNil(snapshot.limit)
        XCTAssertNil(snapshot.usagePercent)
        XCTAssertEqual(snapshot.confidence, .exact)
    }

    func testFetchesAccountCreditsBalance() async throws {
        let body = """
        { "data": { "total_credits": 100.5, "total_usage": 25.75 } }
        """.data(using: .utf8)!
        let transport = MockHTTPTransport(responseData: body)
        let connector = OpenRouterConnector(transport: transport, now: { Date(timeIntervalSince1970: 200) })

        let snapshot = try await connector.fetchAccountCredits(apiKey: "mgmt-key")

        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://openrouter.ai/api/v1/credits")
        XCTAssertEqual(snapshot.used, .credits(25.75))
        XCTAssertEqual(snapshot.limit, .credits(100.5))
        XCTAssertEqual(snapshot.label, "OpenRouter credits")
    }
}

private final class MockHTTPTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let responseData: Data
    let statusCode: Int

    init(responseData: Data, statusCode: Int = 200) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
