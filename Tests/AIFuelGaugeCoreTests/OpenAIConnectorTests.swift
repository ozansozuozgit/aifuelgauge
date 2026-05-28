import XCTest
@testable import AIFuelGaugeCore

final class OpenAIConnectorTests: XCTestCase {
    func testFetchesCurrentMonthCostsFromOrganizationCostsEndpoint() async throws {
        let body = """
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1761955200,
              "end_time": 1762041600,
              "results": [
                { "object": "organization.costs.result", "amount": { "value": 4.25, "currency": "usd" }, "line_item": null, "project_id": null },
                { "object": "organization.costs.result", "amount": { "value": 1.75, "currency": "usd" }, "line_item": null, "project_id": null }
              ]
            }
          ],
          "has_more": false,
          "next_page": null
        }
        """.data(using: .utf8)!
        let transport = OpenAIMockHTTPTransport(responseData: body)
        let connector = OpenAIConnector(
            transport: transport,
            calendar: utcCalendar(),
            now: { Date(timeIntervalSince1970: 1762000000) }
        )

        let snapshot = try await connector.fetchCurrentMonthCosts(adminKey: "admin-key")

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.host, "api.openai.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v1/organization/costs")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer admin-key")
        XCTAssertEqual(queryValue("start_time", in: transport.requests[0]), "1761955200")
        XCTAssertEqual(queryValue("bucket_width", in: transport.requests[0]), "1d")
        XCTAssertEqual(snapshot.provider, .openAI)
        XCTAssertEqual(snapshot.source, .officialAPI)
        XCTAssertEqual(snapshot.label, "Current month costs")
        XCTAssertEqual(snapshot.used, .usd(6))
        XCTAssertNil(snapshot.limit)
        XCTAssertNil(snapshot.usagePercent)
        XCTAssertEqual(snapshot.confidence, .exact)
    }

    func testFetchesCurrentMonthCompletionsUsageWithoutInventingLimit() async throws {
        let body = """
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1761955200,
              "end_time": 1762041600,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 1000,
                  "output_tokens": 500,
                  "input_cached_tokens": 800,
                  "input_audio_tokens": 0,
                  "output_audio_tokens": 0,
                  "num_model_requests": 5
                },
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 30,
                  "output_tokens": 20,
                  "input_cached_tokens": 10,
                  "num_model_requests": 1
                }
              ]
            }
          ],
          "has_more": false,
          "next_page": null
        }
        """.data(using: .utf8)!
        let transport = OpenAIMockHTTPTransport(responseData: body)
        let connector = OpenAIConnector(
            transport: transport,
            calendar: utcCalendar(),
            now: { Date(timeIntervalSince1970: 1762000000) }
        )

        let snapshot = try await connector.fetchCurrentMonthCompletionsUsage(adminKey: "admin-key")

        XCTAssertEqual(transport.requests[0].url?.path, "/v1/organization/usage/completions")
        XCTAssertEqual(snapshot.provider, .openAI)
        XCTAssertEqual(snapshot.label, "Current month tokens")
        XCTAssertEqual(snapshot.used, .tokens(input: 1030, output: 520, cacheRead: 810, cacheWrite: 0))
        XCTAssertNil(snapshot.limit)
        XCTAssertNil(snapshot.usagePercent)
    }

    func testSetupCheckMessagesStaySecretSafeAndActionable() {
        let costs = UsageSnapshot(
            provider: .openAI,
            source: .officialAPI,
            label: "Current month costs",
            used: .usd(12.5),
            limit: nil,
            reset: nil,
            confidence: .exact,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let tokens = UsageSnapshot(
            provider: .openAI,
            source: .officialAPI,
            label: "Current month tokens",
            used: .tokens(input: 1_000_000, output: 250_000, cacheRead: 3_000_000, cacheWrite: 0),
            limit: nil,
            reset: nil,
            confidence: .exact,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let success = OpenAISetupCheck.successMessage(costs: costs, tokens: tokens)
        let failure = OpenAISetupCheck.failureMessage(error: ConnectorError.badStatus(401))

        XCTAssertEqual(success, "OpenAI Admin key works. Month cost is $12.50. Usage API returned 4.25M tokens.")
        XCTAssertEqual(failure, "OpenAI rejected the Admin key or request (HTTP 401). Use an organization Admin key with Usage API access.")
        XCTAssertFalse(success.localizedCaseInsensitiveContains("sk-"))
        XCTAssertFalse(failure.localizedCaseInsensitiveContains("sk-"))
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
    }
}

private final class OpenAIMockHTTPTransport: HTTPTransport {
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
