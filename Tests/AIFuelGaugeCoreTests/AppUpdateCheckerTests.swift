import XCTest
@testable import AIFuelGaugeCore

final class AppUpdateCheckerTests: XCTestCase {
    func testDetectsAvailableGitHubRelease() async throws {
        let body = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/ozansozuozgit/aifuelgauge/releases/tag/v0.2.0"
        }
        """.data(using: .utf8)!
        let transport = UpdateMockHTTPTransport(responseData: body)
        let checker = AppUpdateChecker(transport: transport)

        let result = try await checker.check(currentVersion: "0.1.0")

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://api.github.com/repos/ozansozuozgit/aifuelgauge/releases/latest")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(result.currentVersion, "0.1.0")
        XCTAssertEqual(result.latestVersion, "v0.2.0")
        XCTAssertTrue(result.isUpdateAvailable)
        XCTAssertEqual(result.message, "Update available: 0.1.0 -> v0.2.0.")
    }

    func testTreatsMatchingReleaseAsCurrent() async throws {
        let body = """
        {
          "tag_name": "v0.1.0",
          "html_url": "https://github.com/ozansozuozgit/aifuelgauge/releases/tag/v0.1.0"
        }
        """.data(using: .utf8)!
        let checker = AppUpdateChecker(transport: UpdateMockHTTPTransport(responseData: body))

        let result = try await checker.check(currentVersion: "0.1.0")

        XCTAssertFalse(result.isUpdateAvailable)
        XCTAssertEqual(result.message, "Up to date: 0.1.0 matches v0.1.0.")
    }

    func testUnknownCurrentVersionDoesNotClaimUpdateStatus() async throws {
        let body = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/ozansozuozgit/aifuelgauge/releases/tag/v0.2.0"
        }
        """.data(using: .utf8)!
        let checker = AppUpdateChecker(transport: UpdateMockHTTPTransport(responseData: body))

        let result = try await checker.check(currentVersion: nil)

        XCTAssertNil(result.currentVersion)
        XCTAssertFalse(result.isUpdateAvailable)
        XCTAssertEqual(result.message, "Latest release is v0.2.0. Current build version is unavailable.")
    }
}

private final class UpdateMockHTTPTransport: HTTPTransport {
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
