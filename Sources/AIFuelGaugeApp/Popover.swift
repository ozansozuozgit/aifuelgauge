import SwiftUI
import AIFuelGaugeCore

/// 259° arc gauge. `percent` in 0...1, colored by `state`.
struct ArcGauge: View {
    let percent: Double
    let state: UsageState
    var value: String
    var caption: String = "USED"
    var diameter: CGFloat = 132
    var lineWidth: CGFloat = 12

    private let sweep = 259.0
    private var startAngle: Angle { .degrees(90 + (360 - sweep) / 2) }
    private var trim: CGFloat { CGFloat(sweep / 360.0) }
    private var clamped: Double { min(max(percent, 0), 1) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: trim)
                .stroke(FuelTheme.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(startAngle)
            // Value arc
            Circle()
                .trim(from: 0, to: trim * CGFloat(clamped))
                .stroke(FuelTheme.color(for: state), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(startAngle)
            // Center label
            VStack(spacing: 0) {
                Text(value).font(.fuelMono(28, weight: .semibold)).foregroundStyle(FuelTheme.text)
                Text(caption).font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.4), value: clamped)
    }
}

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

/// In-popover focus selector ("Auto ▾" or a pinned provider). Transient — does
/// not change the menu bar. `rows` are the focusable lanes.
struct FocusPill: View {
    let rows: [DashboardRow]
    @Binding var pinnedID: String?

    var body: some View {
        Menu {
            Button("Auto") { pinnedID = nil }
            Divider()
            ForEach(rows) { row in
                Button(row.title) { pinnedID = row.id }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: pinnedID == nil ? "bolt.fill" : "pin.fill").font(.system(size: 9))
                Text(pinnedID == nil ? "Auto" : (rows.first { $0.id == pinnedID }?.title ?? "Auto"))
                    .font(.fuelText(11.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(FuelTheme.text)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(FuelTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous).strokeBorder(FuelTheme.border))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }
}

struct HeroFeaturedCard: View {
    let row: DashboardRow
    let allRows: [DashboardRow]
    let insight: String
    let resetCaption: String?   // e.g. "Resets in 47m"
    @Binding var pinnedID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArcGauge(percent: row.meterPercent ?? 0, state: row.state,
                     value: percentText, caption: "USED")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TIGHTEST LANE").font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
                    Spacer()
                    FocusPill(rows: allRows, pinnedID: $pinnedID)
                }
                Text(row.title).font(.fuelText(17, weight: .bold)).foregroundStyle(FuelTheme.text)
                Text(row.detail).font(.fuelText(12)).foregroundStyle(FuelTheme.text2)
                if !insight.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(FuelTheme.safe)
                        Text(insight).font(.fuelText(12, weight: .semibold)).foregroundStyle(FuelTheme.text)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FuelTheme.safe.opacity(0.12), in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
                }
                if let resetCaption {
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(FuelTheme.text3)
                        Text(resetCaption).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text2)
                    }
                }
            }
        }
        .fuelCard(radius: FuelTheme.radiusLG, padding: 16)
    }

    private var percentText: String {
        guard let p = row.meterPercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }
}

struct HeroTrioCard: View {
    let rows: [DashboardRow]   // already top-3 ordered

    var body: some View {
        HStack(spacing: 12) {
            ForEach(rows) { row in
                VStack(spacing: 6) {
                    ArcGauge(percent: row.meterPercent ?? 0, state: row.state,
                             value: percentText(row), caption: "", diameter: 84, lineWidth: 8)
                    Text(row.title).font(.fuelText(12.5, weight: .semibold)).foregroundStyle(FuelTheme.text)
                    Text(row.detail).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fuelCard(radius: FuelTheme.radiusLG, padding: 16)
    }

    private func percentText(_ row: DashboardRow) -> String {
        guard let p = row.meterPercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }
}

struct LaneRow: View {
    let row: DashboardRow
    let isPinned: Bool
    let showDetails: Bool
    let onPin: () -> Void
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(FuelTheme.color(for: row.state)).frame(width: 8, height: 8)
                Text(row.title).font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
                Text(row.detail).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3).lineLimit(1)
                Spacer()
                Text(row.value).font(.fuelMono(13)).foregroundStyle(FuelTheme.text)
                laneButton("pin.fill", active: isPinned, action: onPin)
                laneButton("doc.on.doc", action: onCopy)
                if row.dashboardURL != nil { laneButton("arrow.up.right.square", action: onOpen) }
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
    let onAbout: () -> Void
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
                    Button("About", action: onAbout)
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
