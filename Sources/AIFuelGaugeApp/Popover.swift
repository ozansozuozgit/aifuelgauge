import SwiftUI
import AppKit
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

/// Reduces a lane's detail line to its most useful segment for the resting row:
/// the reset phrase (and any low-reserve note). Trust, source, account, and
/// freshness move to the trust chip and the expanded receipt, so the subtitle
/// stays a single calm line instead of a noisy chain of metadata.
func laneSubtitle(_ detail: String) -> String {
    let drop: Set<String> = ["exact", "estimated", "estimate", "unknown", "no limit",
                             "local", "api", "account"]
    return detail
        .split(separator: "·")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { segment in
            let lower = segment.lowercased()
            return !segment.isEmpty
                && !segment.contains("@")
                && !drop.contains(lower)
                && !lower.hasPrefix("acct")
                && !lower.hasSuffix("ago")
                && lower != "now"
        }
        .joined(separator: " · ")
}

struct LaneRow: View {
    let row: DashboardRow
    let showDetails: Bool
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onToggleDetails: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 9) {
                Circle().fill(FuelTheme.color(for: row.state)).frame(width: 8, height: 8)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(laneSubtitle(row.detail)).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                            .lineLimit(1)
                        // Only surface trust when it's the exception — exact lanes stay quiet.
                        if row.confidence != .exact { TrustChip(confidence: row.confidence) }
                    }
                }
                Spacer(minLength: 6)
                // Tier 1: the answer — biggest, boldest, state-colored.
                Text(row.value).font(.fuelMono(14.5, weight: .bold))
                    .foregroundStyle(FuelTheme.color(for: row.state))
                    .lineLimit(1).fixedSize()
                // Row actions reveal on hover so the resting row is pure data.
                if hovering {
                    HStack(spacing: 8) {
                        laneButton("doc.on.doc", action: onCopy)
                        if row.dashboardURL != nil { laneButton("arrow.up.right.square", action: onOpen) }
                        laneButton(showDetails ? "chevron.up" : "chevron.down", action: onToggleDetails)
                    }
                    .transition(.opacity)
                } else if showDetails {
                    laneButton("chevron.up", action: onToggleDetails)
                }
            }
            Meter(percent: row.meterPercent, state: row.state)
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
        .padding(.vertical, 9).padding(.horizontal, 10)
        .background(hovering ? FuelTheme.surfaceHover : .clear,
                    in: RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) { hovering = isHovering }
        }
    }

    private func laneButton(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(active ? FuelTheme.accent : FuelTheme.text3)
        }
        .buttonStyle(.plain)
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
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.system(size: 13))
                }.buttonStyle(.bordered).help("Settings")
                Button(action: onHistory) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 13))
                }.buttonStyle(.bordered).help("History")
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
    /// Persisted single-provider focus ("" = all providers).
    @AppStorage("popoverProviderFilter") private var providerFilterRaw = ""

    private var model: DashboardViewModel { controller.model }

    /// Providers that currently have lanes, in first-seen order — drives the
    /// in-popover provider switcher.
    private var availableProviders: [Provider] {
        var seen = Set<Provider>()
        var result: [Provider] = []
        for row in orderedRows where !seen.contains(row.provider) {
            seen.insert(row.provider)
            result.append(row.provider)
        }
        return result
    }

    /// The active focus, ignored if that provider no longer has lanes.
    private var activeProviderFilter: Provider? {
        guard let provider = Provider(rawValue: providerFilterRaw),
              availableProviders.contains(provider) else { return nil }
        return provider
    }

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
        let scoped: [DashboardRow]
        switch laneFilter {
        case .usable:
            let usable = orderedRows.filter(\.showsInUsableFilter)
            scoped = usable.isEmpty ? orderedRows : usable
        case .all:
            scoped = orderedRows
        }
        guard let provider = activeProviderFilter else { return scoped }
        let withinScope = scoped.filter { $0.provider == provider }
        // A picked provider always shows its lanes, even if the usable filter
        // would otherwise hide them all.
        return withinScope.isEmpty ? orderedRows.filter { $0.provider == provider } : withinScope
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            routerRow
            laneToolbar
            laneList
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
                Text(headerSubtitle).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3).lineLimit(1)
            }
            Spacer()
            StatePill(state: headerState, label: stateLabel)
        }
    }

    /// Cross-provider "use this engine now" recommendation — the Fuel Router.
    @ViewBuilder private var routerRow: some View {
        if let rec = model.recommendation {
            HStack(spacing: 9) {
                Image(systemName: rec.isConstrained ? "exclamationmark.triangle.fill" : "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FuelTheme.color(for: rec.state))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(rec.isConstrained ? "HEADS UP" : "USE NOW")
                            .font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
                        Text(rec.title).font(.fuelText(12.5, weight: .semibold)).foregroundStyle(FuelTheme.text)
                            .lineLimit(1)
                    }
                    Text(rec.detail).font(.fuelText(11)).foregroundStyle(FuelTheme.text3).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let command = rec.launchCommand {
                    Button { copyToPasteboard(command) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc").font(.system(size: 10))
                            Text(command).font(.fuelMono(11))
                        }
                        .foregroundStyle(FuelTheme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(FuelTheme.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Copy \"\(command)\" to clipboard")
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(FuelTheme.color(for: rec.state).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var laneToolbar: some View {
        HStack(spacing: 8) {
            Text("LANES").font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            Picker("", selection: $laneFilter) {
                Text("Usable \(usableCount)").tag(LaneFilter.usable)
                Text("All \(orderedRows.count)").tag(LaneFilter.all)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            if availableProviders.count > 1 {
                providerFilterMenu
            } else {
                Label("Drag to reorder", systemImage: "line.3.horizontal")
                    .labelStyle(.titleAndIcon)
                    .font(.fuelText(10.5)).foregroundStyle(FuelTheme.text3)
            }
        }
    }

    /// Compact menu to focus a single provider (or all). Scales past a chip row
    /// without crowding the 420pt popover.
    private var providerFilterMenu: some View {
        Menu {
            Button {
                providerFilterRaw = ""
            } label: {
                if activeProviderFilter == nil {
                    Label("All providers", systemImage: "checkmark")
                } else {
                    Text("All providers")
                }
            }
            Divider()
            ForEach(availableProviders, id: \.self) { provider in
                Button {
                    providerFilterRaw = provider.rawValue
                } label: {
                    if activeProviderFilter == provider {
                        Label(provider.displayName, systemImage: "checkmark")
                    } else {
                        Text(provider.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 11))
                Text(activeProviderFilter?.displayName ?? "All providers")
                    .font(.fuelText(11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(activeProviderFilter == nil ? FuelTheme.text3 : FuelTheme.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder private var laneList: some View {
        if model.rows.isEmpty {
            emptyState
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
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(FuelTheme.divider)
                }
                .onMove(perform: moveRows)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .frame(height: laneListHeight)
        }
    }

    /// Friendly zero/loading state instead of a bare grey well.
    private var emptyState: some View {
        VStack(spacing: 8) {
            BrandMark(size: 30)
            Text("Reading your usage…").font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
            Text("If nothing appears, connect a source in Settings to start tracking your limits.")
                .font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: actions.settings) {
                Label("Open Settings", systemImage: "gearshape")
            }.buttonStyle(.bordered).controlSize(.small).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 16)
    }

    /// Adapts the list height to row count (so few lanes don't leave a big well)
    /// while capping so the popover stays compact; the List scrolls past the cap.
    private var laneListHeight: CGFloat {
        let collapsed: CGFloat = 66
        let expandedExtra: CGFloat = 92
        let expandedCount = visibleRows.filter { detailRowIDs.contains($0.id) }.count
        let raw = CGFloat(visibleRows.count) * collapsed + CGFloat(expandedCount) * expandedExtra
        return min(max(raw, collapsed), 340)
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

    private var usableCount: Int {
        orderedRows.filter(\.showsInUsableFilter).count
    }

    /// The lane the user actually cares about right now: the most constrained
    /// one currently visible. Drives the header pill and subtitle so they always
    /// agree with what's on screen (no "Almost out" while every lane reads green).
    private var tightestRow: DashboardRow? {
        visibleRows.max { lhs, rhs in
            if lhs.state != rhs.state { return lhs.state < rhs.state }
            return (lhs.meterPercent ?? 1) > (rhs.meterPercent ?? 1)
        }
    }

    private var headerState: UsageState {
        tightestRow?.state ?? model.state
    }

    private var headerSubtitle: String {
        guard let row = tightestRow else { return model.statusLabel }
        if headerState >= .caution {
            // Name the constraint and how much is left, e.g. "Codex · Weekly · 8% left".
            return "\(row.title) · \(row.value)"
        }
        return "All lanes healthy"
    }

    private var stateLabel: String {
        switch headerState {
        case .safe: return "Healthy"
        case .caution: return "Getting tight"
        case .critical: return "Almost out"
        case .exhausted: return "Spent"
        case .unknown: return "Estimating"
        }
    }
}
