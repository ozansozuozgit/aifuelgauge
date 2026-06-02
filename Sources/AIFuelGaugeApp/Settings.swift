// Sources/AIFuelGaugeApp/Settings.swift
import SwiftUI
import AIFuelGaugeCore

/// Titled card section. `title` rendered as an eyebrow above a rounded card.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            VStack(spacing: 0) { content }
                .background(FuelTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous).strokeBorder(FuelTheme.border))
        }
    }
}

/// Label + helper + trailing control, with an icon well.
struct SettingsRow<Control: View>: View {
    let icon: String?
    let title: String
    let helper: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(FuelTheme.text2)
                    .frame(width: 28, height: 28)
                    .background(FuelTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
                if let helper { Text(helper).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3) }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// Pane scaffold: big title + subtitle, then content.
struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.fuelText(20, weight: .bold)).foregroundStyle(FuelTheme.text)
                    Text(subtitle).font(.fuelText(12.5)).foregroundStyle(FuelTheme.text2)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
