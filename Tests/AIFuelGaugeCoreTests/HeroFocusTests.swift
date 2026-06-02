import XCTest
@testable import AIFuelGaugeCore

final class HeroFocusTests: XCTestCase {
    private func row(_ id: String, percent: Double?, usable: Bool = true, state: UsageState = .caution) -> DashboardRow {
        DashboardRow(
            id: id, title: id, value: "", detail: "", dashboardURL: nil, explanation: "",
            meterPercent: percent, meterLabel: nil, trendPercents: [], trendCaption: nil,
            paceCaption: nil, receiptText: "", confidence: .exact, state: state,
            showsInUsableFilter: usable
        )
    }

    func testTightestLaneIsHighestUsableMeter() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90), row("c", percent: 0.55)]
        XCTAssertEqual(HeroFocus.tightestLane(rows)?.id, "b")
    }

    func testTightestLaneIgnoresNonUsableWhenUsableExist() {
        let rows = [row("a", percent: 0.95, usable: false), row("b", percent: 0.40, usable: true)]
        XCTAssertEqual(HeroFocus.tightestLane(rows)?.id, "b")
    }

    func testTightestLaneFallsBackToAllWhenNoUsable() {
        let rows = [row("a", percent: 0.95, usable: false), row("b", percent: 0.40, usable: false)]
        XCTAssertEqual(HeroFocus.tightestLane(rows)?.id, "a")
    }

    func testTopThreeOrderedByMeterDescending() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90), row("c", percent: 0.55), row("d", percent: 0.10)]
        XCTAssertEqual(HeroFocus.topLanes(rows, count: 3).map(\.id), ["b", "c", "a"])
    }

    func testResolveFocusReturnsPinnedRowWhenPresent() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90)]
        XCTAssertEqual(HeroFocus.resolve(rows, pinnedID: "a")?.id, "a")
    }

    func testResolveFocusFallsBackToTightestWhenPinMissing() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90)]
        XCTAssertEqual(HeroFocus.resolve(rows, pinnedID: "zzz")?.id, "b")
    }

    func testResolveFocusAutoWhenPinNil() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90)]
        XCTAssertEqual(HeroFocus.resolve(rows, pinnedID: nil)?.id, "b")
    }
}
