import Foundation

/// Pure selection helpers for the popover hero (Featured + Top-3 layouts).
public enum HeroFocus {
    /// Rows ordered tightest-first (highest meterPercent). Rows with no
    /// meterPercent sort last. Restricts to usable rows when any exist.
    public static func orderedTightest(_ rows: [DashboardRow]) -> [DashboardRow] {
        let usable = rows.filter(\.showsInUsableFilter)
        let pool = usable.isEmpty ? rows : usable
        return pool.sorted { lhs, rhs in
            (lhs.meterPercent ?? -1) > (rhs.meterPercent ?? -1)
        }
    }

    public static func tightestLane(_ rows: [DashboardRow]) -> DashboardRow? {
        orderedTightest(rows).first
    }

    public static func topLanes(_ rows: [DashboardRow], count: Int) -> [DashboardRow] {
        Array(orderedTightest(rows).prefix(count))
    }

    /// Hero focus: the pinned row if it still exists, else the tightest lane.
    public static func resolve(_ rows: [DashboardRow], pinnedID: String?) -> DashboardRow? {
        if let pinnedID, let pinned = rows.first(where: { $0.id == pinnedID }) {
            return pinned
        }
        return tightestLane(rows)
    }
}
