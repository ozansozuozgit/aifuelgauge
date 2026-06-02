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
