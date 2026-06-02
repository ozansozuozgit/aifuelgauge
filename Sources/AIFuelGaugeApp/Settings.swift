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

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, providers, apiKeys, alerts, menuBar, budgets, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .providers: return "Providers"
        case .apiKeys: return "API Keys"
        case .alerts: return "Alerts"
        case .menuBar: return "Menu Bar"
        case .budgets: return "Budgets"
        case .privacy: return "Data & Privacy"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "dot.radiowaves.left.and.right"
        case .apiKeys: return "key"
        case .alerts: return "bell"
        case .menuBar: return "menubar.rectangle"
        case .budgets: return "dollarsign.circle"
        case .privacy: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                } header: {
                    HStack(spacing: 8) {
                        BrandMark(size: 18)
                        Text("AI Fuel Gauge").font(.fuelText(13, weight: .bold)).foregroundStyle(FuelTheme.text)
                    }.padding(.bottom, 4)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield").font(.system(size: 10)).foregroundStyle(FuelTheme.safe)
                    Text("Local-first · \(appVersionString)").font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                    Spacer()
                }.padding(12)
            }
        } detail: {
            detailPane.frame(minWidth: 460)
        }
        .frame(width: 760, height: 600)
    }

    @ViewBuilder private var detailPane: some View {
        switch selection {
        case .general:   GeneralPane()
        case .providers: ProvidersPane()
        case .apiKeys:   APIKeysPane()
        case .alerts:    AlertsPane()
        case .menuBar:   MenuBarPane()
        case .budgets:   BudgetsPane()
        case .privacy:   PrivacyPane()
        case .about:     AboutPane()
        }
    }

    private var appVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "v\($0)" } ?? "local build"
    }
}

// MARK: - Stub panes (filled in by Tasks 16-18)

struct GeneralPane: View {
    var body: some View { SettingsPane(title: "General", subtitle: "How often AI Fuel Gauge refreshes, and whether it starts with your Mac.") { EmptyView() } }
}
struct ProvidersPane: View {
    var body: some View { SettingsPane(title: "Providers", subtitle: "Turn sources on or off.") { EmptyView() } }
}
struct APIKeysPane: View {
    var body: some View { SettingsPane(title: "API Keys", subtitle: "Keys are stored in the macOS Keychain.") { EmptyView() } }
}
struct AlertsPane: View {
    var body: some View { SettingsPane(title: "Alerts", subtitle: "Threshold notifications per provider.") { EmptyView() } }
}
struct MenuBarPane: View {
    var body: some View { SettingsPane(title: "Menu bar", subtitle: "Control how much the menu-bar label shows.") { EmptyView() } }
}
struct BudgetsPane: View {
    var body: some View { SettingsPane(title: "Budgets", subtitle: "Optional monthly guardrails.") { EmptyView() } }
}
struct PrivacyPane: View {
    var body: some View { SettingsPane(title: "Data & Privacy", subtitle: "All data stays on your Mac.") { EmptyView() } }
}
struct AboutPane: View {
    var body: some View { SettingsPane(title: "About", subtitle: "AI Fuel Gauge.") { EmptyView() } }
}
