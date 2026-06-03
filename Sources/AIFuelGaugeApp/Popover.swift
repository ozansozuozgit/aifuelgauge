import SwiftUI
import AIFuelGaugeCore

/// Linear capsule meter. Striped variant for unknown / no-limit sources.
struct Meter: View {
    let percent: Double?   // nil => no-limit striped bar
    let state: UsageState
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FuelTheme.track)
                if let percent {
                    Capsule()
                        .fill(FuelTheme.color(for: state))
                        .frame(width: max(0, min(1, percent)) * geo.size.width)
                } else {
                    Capsule()
                        .fill(.linearGradient(
                            stops: [.init(color: FuelTheme.unknown.opacity(0.5), location: 0),
                                    .init(color: FuelTheme.unknown.opacity(0.15), location: 1)],
                            startPoint: .leading, endPoint: .trailing))
                }
            }
        }
        .frame(height: height)
    }
}

/// 7-point trend sparkline, state-colored line + soft area fill.
struct Sparkline: View {
    let points: [Double]
    let state: UsageState

    var body: some View {
        GeometryReader { geo in
            let pts = normalizedPoints(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    areaPath(pts, height: geo.size.height).fill(FuelTheme.color(for: state).opacity(0.14))
                    linePath(pts).stroke(FuelTheme.color(for: state),
                                         style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 28)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let lo = points.min() ?? 0, hi = points.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
        return points.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height - CGFloat((v - lo) / span) * size.height)
        }
    }
    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path(); p.addLines(pts); return p
    }
    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = Path()
        guard let first = pts.first, let last = pts.last else { return p }
        p.move(to: CGPoint(x: first.x, y: height))
        p.addLine(to: first); pts.dropFirst().forEach { p.addLine(to: $0) }
        p.addLine(to: CGPoint(x: last.x, y: height)); p.closeSubpath()
        return p
    }
}

/// Exact / Estimate / No-limit trust chip.
struct TrustChip: View {
    let confidence: Confidence
    var body: some View {
        let chip = confidence.chip
        return HStack(spacing: 4) {
            Image(systemName: chip.symbol).font(.system(size: 9, weight: .semibold))
            Text(chip.label).font(.fuelText(10.5, weight: .medium))
        }
        .foregroundStyle(chip.color)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(chip.color.opacity(0.12), in: Capsule())
    }
}

/// Header state pill, e.g. "Almost out".
struct StatePill: View {
    let state: UsageState
    var label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(FuelTheme.color(for: state)).frame(width: 6, height: 6)
            Text(label).font(.fuelText(11.5, weight: .semibold))
        }
        .foregroundStyle(FuelTheme.text2)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(FuelTheme.color(for: state).opacity(0.12), in: Capsule())
    }
}

/// Trims noisy trailing segments (masked email, "account", "acct …", "now")
/// from a lane's detail line so it stays concise in the popover.
func conciseDetail(_ detail: String) -> String {
    detail
        .split(separator: "·")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { segment in
            let lower = segment.lowercased()
            return !segment.isEmpty
                && !segment.contains("@")
                && lower != "now"
                && lower != "account"
                && !lower.hasPrefix("acct")
        }
        .joined(separator: " · ")
}

struct LaneRow: View {
    let row: DashboardRow
    let showDetails: Bool
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onToggleDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(FuelTheme.color(for: row.state)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
                        .lineLimit(1)
                    Text(conciseDetail(row.detail)).font(.fuelText(11)).foregroundStyle(FuelTheme.text3).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(row.value).font(.fuelMono(12.5)).foregroundStyle(FuelTheme.text)
                    .lineLimit(1).fixedSize()
                laneButton("doc.on.doc", action: onCopy)
                if row.dashboardURL != nil { laneButton("arrow.up.right.square", action: onOpen) }
                laneButton(showDetails ? "chevron.up" : "chevron.down", action: onToggleDetails)
            }
            Meter(percent: row.meterPercent, state: row.state)
            if let label = row.meterLabel {
                Text(label).font(.fuelText(11)).foregroundStyle(FuelTheme.color(for: row.state))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if showDetails {
                if !row.trendPercents.isEmpty {
                    HStack(spacing: 8) {
                        Sparkline(points: row.trendPercents, state: row.state).frame(width: 90)
                        TrustChip(confidence: row.confidence)
                        if let trend = row.trendCaption {
                            Text(trend).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                        }
                        Spacer()
                    }
                }
                if let pace = row.paceCaption {
                    Label(pace, systemImage: "checkmark").labelStyle(.titleAndIcon)
                        .font(.fuelText(11.5)).foregroundStyle(FuelTheme.text2)
                }
                if !row.receiptText.isEmpty {
                    Label(row.receiptText, systemImage: "info.circle").labelStyle(.titleAndIcon)
                        .font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
    }

    private func laneButton(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(active ? FuelTheme.accent : FuelTheme.text3)
        }
        .buttonStyle(.plain)
    }
}

struct ResetCard: View {
    let eyebrow: String
    let value: String
    let caption: String
    let state: UsageState
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow).font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            Text(value).font(.fuelMono(15)).foregroundStyle(FuelTheme.color(for: state))
            Text(caption).font(.fuelText(11)).foregroundStyle(FuelTheme.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fuelCard(radius: FuelTheme.radiusMD, padding: 10)
    }
}

struct ResetContextStrip: View {
    struct Item: Identifiable { let id = UUID(); let eyebrow: String; let value: String; let caption: String; let state: UsageState }
    let items: [Item]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { ResetCard(eyebrow: $0.eyebrow, value: $0.value, caption: $0.caption, state: $0.state) }
        }
    }
}

struct ActionBar: View {
    let trustTally: String
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onHistory: () -> Void
    let onCopySnapshot: () -> Void
    let onCopyDiagnostics: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").font(.system(size: 10)).foregroundStyle(FuelTheme.safe)
                Text(trustTally).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                Spacer()
            }
            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderedProminent).tint(FuelTheme.accent)
                Button(action: onSettings) { Label("Settings", systemImage: "gearshape") }.buttonStyle(.bordered)
                Button(action: onHistory) { Label("History", systemImage: "chart.xyaxis.line") }.buttonStyle(.bordered)
                Spacer()
                Menu {
                    Button("Copy snapshot", action: onCopySnapshot)
                    Button("Copy diagnostics", action: onCopyDiagnostics)
                    Divider()
                    Button("Quit AI Fuel Gauge", action: onQuit)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14)).foregroundStyle(FuelTheme.text3)
                }.menuStyle(.borderlessButton).fixedSize()
            }
            .font(.fuelText(12, weight: .semibold))
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(FuelTheme.accent)
    }
}

struct DashboardView: View {
    @ObservedObject var controller: DashboardController
    let actions: DashboardActions

    @State private var laneFilter: LaneFilter = .usable
    @State private var detailRowIDs: Set<String> = []
    @State private var customOrder: [String] = AppPreferences.laneOrder()

    private var model: DashboardViewModel { controller.model }

    /// All rows arranged by the user's saved drag order; rows not yet in the
    /// saved order keep their model position and are appended.
    private var orderedRows: [DashboardRow] {
        guard !customOrder.isEmpty else { return model.rows }
        let byID = Dictionary(model.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = customOrder.compactMap { byID[$0] }
        let seen = Set(ordered.map(\.id))
        return ordered + model.rows.filter { !seen.contains($0.id) }
    }

    private var visibleRows: [DashboardRow] {
        switch laneFilter {
        case .usable:
            let usable = orderedRows.filter(\.showsInUsableFilter)
            return usable.isEmpty ? orderedRows : usable
        case .all:
            return orderedRows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            laneToolbar
            laneList
            ResetContextStrip(items: resetItems)
            WorkbenchSection(
                snapshot: controller.workbench,
                openQuickRoute: actions.openQuickRoute,
                copyQuickRoute: actions.copyQuickRoute,
                revealSession: actions.revealSession,
                openServer: actions.openServer,
                stopServer: actions.stopServer
            )
            ActionBar(
                trustTally: model.trustDigest,
                onRefresh: actions.refresh,
                onSettings: actions.settings,
                onHistory: actions.history,
                onCopySnapshot: actions.copyStatus,
                onCopyDiagnostics: actions.copyDiagnostics,
                onQuit: actions.quit
            )
        }
        .padding(16)
        .frame(width: 420)
        .background(FuelTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Fuel Gauge").font(.fuelText(14, weight: .bold)).foregroundStyle(FuelTheme.text)
                Text(model.statusLabel).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3)
            }
            Spacer()
            StatePill(state: model.state, label: stateLabel)
        }
    }

    private var laneToolbar: some View {
        HStack(spacing: 8) {
            Text("LANES").font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            Picker("", selection: $laneFilter) {
                Text("Usable").tag(LaneFilter.usable)
                Text("All").tag(LaneFilter.all)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Text("\(visibleRows.count)").font(.fuelMono(11)).foregroundStyle(FuelTheme.text3)
            Spacer()
            Label("Drag to reorder", systemImage: "line.3.horizontal")
                .labelStyle(.titleAndIcon)
                .font(.fuelText(10.5)).foregroundStyle(FuelTheme.text3)
        }
    }

    @ViewBuilder private var laneList: some View {
        if model.rows.isEmpty {
            Text("Estimating usage…")
                .font(.fuelText(12)).foregroundStyle(FuelTheme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fuelCard(radius: FuelTheme.radiusMD, padding: 16)
        } else {
            List {
                ForEach(visibleRows) { row in
                    LaneRow(
                        row: row,
                        showDetails: detailRowIDs.contains(row.id),
                        onCopy: { actions.copyRow(row) },
                        onOpen: { actions.openRow(row) },
                        onToggleDetails: { toggleDetails(row.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(FuelTheme.divider)
                }
                .onMove(perform: moveRows)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .frame(height: laneListHeight)
            .background(FuelTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
        }
    }

    /// Adapts the list height to row count (so few lanes don't leave a big well)
    /// while capping so the popover stays compact; the List scrolls past the cap.
    private var laneListHeight: CGFloat {
        let collapsed: CGFloat = 86
        let expandedExtra: CGFloat = 96
        let expandedCount = visibleRows.filter { detailRowIDs.contains($0.id) }.count
        let raw = CGFloat(visibleRows.count) * collapsed + CGFloat(expandedCount) * expandedExtra
        return min(max(raw, collapsed), 320)
    }

    /// Reorders the visible lanes and persists the new global order.
    private func moveRows(from source: IndexSet, to destination: Int) {
        var visible = visibleRows
        visible.move(fromOffsets: source, toOffset: destination)
        let visibleSet = Set(visibleRows.map(\.id))
        let hiddenIDs = orderedRows.map(\.id).filter { !visibleSet.contains($0) }
        let newOrder = visible.map(\.id) + hiddenIDs
        customOrder = newOrder
        AppPreferences.saveLaneOrder(newOrder)
    }

    private func toggleDetails(_ id: String) {
        if detailRowIDs.contains(id) { detailRowIDs.remove(id) } else { detailRowIDs.insert(id) }
    }

    private var stateLabel: String {
        switch model.state {
        case .safe: return "Healthy"
        case .caution: return "Getting tight"
        case .critical: return "Almost out"
        case .exhausted: return "Spent"
        case .unknown: return "Estimating"
        }
    }

    private var resetItems: [ResetContextStrip.Item] {
        model.resetTimeline.prefix(3).map { item in
            ResetContextStrip.Item(eyebrow: "RESET", value: item.value, caption: item.title, state: item.state)
        }
    }
}
