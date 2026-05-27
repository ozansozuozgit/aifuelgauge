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

        let snapshots = try CursorUsageResponseParser(now: { Date(timeIntervalSince1970: 200) }).parse(data: data, plan: "Pro")

        XCTAssertEqual(snapshots.map(\.provider), [.cursor, .cursor, .cursor])
        XCTAssertEqual(snapshots.map(\.source), [.experimentalWebSession, .experimentalWebSession, .experimentalWebSession])
        XCTAssertEqual(snapshots.map(\.label), ["Included total", "API usage", "Auto usage"])
        XCTAssertEqual(snapshots.map(\.used), [
            .percent(59.112820512820505),
            .percent(100),
            .percent(46.20666666666667)
        ])
        XCTAssertEqual(snapshots.map(\.limit), [.percent(100), .percent(100), .percent(100)])
        XCTAssertEqual(snapshots.map(\.confidence), [.exact, .exact, .exact])
        XCTAssertEqual(snapshots.map(\.updatedAt), [
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200)
        ])
        XCTAssertEqual(snapshots.map(\.reset), [
            .fixed(Date(timeIntervalSince1970: 1_780_785_201)),
            .fixed(Date(timeIntervalSince1970: 1_780_785_201)),
            .fixed(Date(timeIntervalSince1970: 1_780_785_201))
        ])
        XCTAssertEqual(snapshots.first?.account?.plan, "Pro")
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
}
