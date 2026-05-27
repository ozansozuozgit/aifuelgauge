import XCTest
@testable import AIFuelGaugeCore

final class CursorUsageConnectorTests: XCTestCase {
    func testParsesCursorCurrentPeriodUsageIntoSeparateLanes() throws {
        let data = Data(
            """
            {
              "billingCycleStart": "1778106801000",
              "billingCycleEnd": "1780785201000",
              "planUsage": {
                "totalSpend": 11527,
                "includedSpend": 2000,
                "bonusSpend": 9527,
                "limit": 2000,
                "remainingBonus": false,
                "autoPercentUsed": 46.20666666666667,
                "apiPercentUsed": 100,
                "totalPercentUsed": 59.112820512820505
              }
            }
            """.utf8
        )

        let snapshots = try CursorUsageResponseParser(now: { Date(timeIntervalSince1970: 200) }).parse(
            data: data,
            plan: "Pro",
            accountIdentifier: "cursor-abc123",
            identityHint: "u***r@example.com"
        )

        XCTAssertEqual(snapshots.map(\.provider), [.cursor, .cursor, .cursor, .cursor, .cursor])
        XCTAssertEqual(snapshots.map(\.source), [
            .experimentalWebSession,
            .experimentalWebSession,
            .experimentalWebSession,
            .experimentalWebSession,
            .experimentalWebSession
        ])
        XCTAssertEqual(snapshots.map(\.label), ["Included total", "API usage", "Auto usage", "Included spend", "Bonus spend"])
        XCTAssertEqual(snapshots.map(\.used), [
            .percent(59.112820512820505),
            .percent(100),
            .percent(46.20666666666667),
            .usd(20),
            .usd(95.27)
        ])
        XCTAssertEqual(snapshots.map(\.limit), [.percent(100), .percent(100), .percent(100), nil, nil])
        XCTAssertEqual(snapshots.map(\.confidence), [.exact, .exact, .exact, .exact, .exact])
        XCTAssertEqual(snapshots.map(\.updatedAt), [
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200)
        ])
        XCTAssertEqual(snapshots.map(\.reset), [
            .fixed(Date(timeIntervalSince1970: 1_780_785_201)),
            .fixed(Date(timeIntervalSince1970: 1_780_785_201)),
            .fixed(Date(timeIntervalSince1970: 1_780_785_201)),
            .fixed(Date(timeIntervalSince1970: 1_780_785_201)),
            .fixed(Date(timeIntervalSince1970: 1_780_785_201))
        ])
        XCTAssertEqual(snapshots.first?.account?.plan, "Pro")
        XCTAssertEqual(snapshots.first?.account?.identifier, "cursor-abc123")
        XCTAssertEqual(snapshots.first?.account?.identityHint, "u***r@example.com")
    }

    func testParsesCursorSpendWithoutHardcodingSubscriptionBudget() throws {
        let data = Data(
            """
            {
              "billingCycleEnd": 1780785201000,
              "planUsage": {
                "totalSpend": 7300,
                "includedSpend": 7000,
                "bonusSpend": 300
              }
            }
            """.utf8
        )

        let snapshots = try CursorUsageResponseParser(now: { Date(timeIntervalSince1970: 200) }).parse(
            data: data,
            plan: "Pro Plus",
            accountIdentifier: "cursor-abc123"
        )

        XCTAssertEqual(snapshots.map(\.label), ["Included spend", "Bonus spend"])
        XCTAssertEqual(snapshots.map(\.used), [.usd(70), .usd(3)])
        XCTAssertEqual(snapshots.map(\.limit), [nil, nil])
        XCTAssertEqual(snapshots.map(\.usagePercent), [nil, nil])
        XCTAssertEqual(Set(snapshots.compactMap(\.account?.plan)), ["Pro Plus"])
    }

    func testRejectsCursorUsageWithoutAnyComparableLane() {
        let data = Data(
            """
            {
              "billingCycleEnd": 1780785201000,
              "planUsage": {}
            }
            """.utf8
        )

        XCTAssertThrowsError(try CursorUsageResponseParser().parse(data: data, plan: nil)) { error in
            XCTAssertEqual(error as? CursorUsageConnectorError, .invalidUsageResponse)
        }
    }

    func testCursorSetupMessagesStaySecretSafeAndActionable() {
        let resetDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970 + 3_600)
        let snapshots = [
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(
                    identifier: "cursor-abc123",
                    displayName: "Cursor",
                    plan: "Pro",
                    identityHint: "u***r@example.com"
                ),
                label: "Included total",
                used: .percent(59.1),
                limit: .percent(100),
                reset: .fixed(resetDate),
                confidence: .exact,
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: UsageAccount(
                    identifier: "cursor-abc123",
                    displayName: "Cursor",
                    plan: "Pro",
                    identityHint: "u***r@example.com"
                ),
                label: "API usage",
                used: .percent(100),
                limit: .percent(100),
                reset: .fixed(resetDate),
                confidence: .exact,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        ]

        let success = CursorSetupCheck.successMessage(snapshots: snapshots)
        let failure = CursorSetupCheck.failureMessage(error: CursorUsageConnectorError.usageRequestFailed(statusCode: 401))

        XCTAssertTrue(success.contains("Cursor live usage works. Pro · acct u***r@example.com."))
        XCTAssertTrue(success.contains("Included total 59% used, API usage 100% used."))
        XCTAssertEqual(failure, "Cursor rejected the usage request (HTTP 401). Open Cursor, confirm you are signed in, then test again.")
        XCTAssertFalse(success.contains("Bearer"))
        XCTAssertFalse(success.contains("accessToken"))
        XCTAssertFalse(failure.contains("Bearer"))
        XCTAssertFalse(failure.contains("accessToken"))
    }
}
