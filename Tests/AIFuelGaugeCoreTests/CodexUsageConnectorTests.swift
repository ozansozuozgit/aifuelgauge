import XCTest
@testable import AIFuelGaugeCore

final class CodexUsageConnectorTests: XCTestCase {
    func testParsesCodexAccountUsageWindows() throws {
        let data = """
        {
          "plan_type": "prolite",
          "rate_limit": {
            "primary_window": {
              "used_percent": 14,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 8612,
              "reset_at": 1779925233
            },
            "secondary_window": {
              "used_percent": 46,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 258176,
              "reset_at": 1780174797
            }
          },
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 0,
                  "limit_window_seconds": 18000,
                  "reset_after_seconds": 18000,
                  "reset_at": 1779934621
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshots = try CodexUsageResponseParser(now: { Date(timeIntervalSince1970: 100) }).parse(data: data)

        XCTAssertEqual(snapshots.map(\.provider), [.codex, .codex])
        XCTAssertEqual(snapshots.map(\.source), [.experimentalWebSession, .experimentalWebSession])
        XCTAssertEqual(snapshots.map(\.label), ["5h", "Weekly"])
        XCTAssertEqual(snapshots.map(\.used), [.percent(14), .percent(46)])
        XCTAssertEqual(snapshots.map(\.limit), [.percent(100), .percent(100)])
        XCTAssertEqual(snapshots.map { $0.account?.plan }, ["Pro", "Pro"])
        XCTAssertEqual(snapshots[0].reset, .rollingWindow(secondsRemaining: 8612))
        XCTAssertEqual(snapshots[1].reset, .rollingWindow(secondsRemaining: 258176))
        XCTAssertEqual(snapshots[0].confidence, .exact)
    }

    func testParserKeepsPlusPlanDistinctFromPro() throws {
        let data = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 3,
              "reset_after_seconds": 1200
            }
          }
        }
        """.data(using: .utf8)!

        let snapshots = try CodexUsageResponseParser(now: { Date(timeIntervalSince1970: 100) }).parse(data: data)

        XCTAssertEqual(snapshots.first?.account?.plan, "Plus")
    }

    func testParserKeysCodexAccountByStableAccountID() throws {
        let data = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 3,
              "reset_after_seconds": 1200
            }
          }
        }
        """.data(using: .utf8)!

        let parser = CodexUsageResponseParser(now: { Date(timeIntervalSince1970: 100) })
        let firstAccount = try parser.parse(data: data, accountID: "acct_one", identityHint: "o***e@example.com")
        let secondAccount = try parser.parse(data: data, accountID: "acct_two", identityHint: "t***o@example.com")

        XCTAssertNotEqual(firstAccount.first?.account?.identifier, "codex-account")
        XCTAssertNotEqual(firstAccount.first?.account?.identifier, secondAccount.first?.account?.identifier)
        XCTAssertEqual(firstAccount.first?.account?.identityHint, "o***e@example.com")
        XCTAssertEqual(secondAccount.first?.account?.identityHint, "t***o@example.com")
    }

    func testParserKeepsActiveAdditionalModelLimitsWithReadableNames() throws {
        let data = """
        {
          "plan_type": "prolite",
          "rate_limit": {
            "primary_window": {
              "used_percent": 14,
              "reset_after_seconds": 8612
            }
          },
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 64,
                  "reset_after_seconds": 18000
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshots = try CodexUsageResponseParser(now: { Date(timeIntervalSince1970: 100) }).parse(data: data)

        XCTAssertEqual(snapshots.map(\.label), ["5h", "Spark model · 5h"])
        XCTAssertEqual(snapshots.map(\.used), [.percent(14), .percent(64)])
    }

    func testParserRejectsResponsesWithoutComparableWindows() throws {
        let data = #"{"plan_type":"prolite","rate_limit":{}}"#.data(using: .utf8)!

        XCTAssertThrowsError(try CodexUsageResponseParser().parse(data: data)) { error in
            XCTAssertEqual(error as? CodexUsageConnectorError, .invalidUsageResponse)
        }
    }
}
