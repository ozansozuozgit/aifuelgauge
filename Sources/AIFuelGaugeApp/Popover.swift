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
