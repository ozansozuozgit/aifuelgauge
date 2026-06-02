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
    @AppStorage(AppPreferences.refreshIntervalSecondsKey) private var refreshIntervalSeconds = 180
    @State private var launchAgentMessage = LaunchAgentManager.statusMessage()
    @State private var isChangingLaunchAgent = false
    @State private var startAtLogin = false

    private let cadences: [(label: String, seconds: Int)] = [("1m", 60), ("3m", 180), ("5m", 300), ("15m", 900)]

    var body: some View {
        SettingsPane(title: "General",
                     subtitle: "How often AI Fuel Gauge refreshes in the background, and whether it starts with your Mac.") {
            SettingsGroup(title: "Auto-sync") {
                SettingsRow(icon: "arrow.clockwise", title: "Refresh cadence",
                            helper: "Background polling interval. Manual refresh always works instantly.") {
                    Picker("", selection: $refreshIntervalSeconds) {
                        ForEach(cadences, id: \.seconds) { Text($0.label).tag($0.seconds) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsGroup(title: "Startup") {
                SettingsRow(icon: "power", title: "Start at login",
                            helper: launchAgentMessage) {
                    Toggle("", isOn: $startAtLogin).labelsHidden().toggleStyle(.switch).tint(FuelTheme.accent)
                        .disabled(isChangingLaunchAgent)
                }
            }
        }
        .onAppear {
            launchAgentMessage = LaunchAgentManager.statusMessage()
            startAtLogin = launchAgentMessage.hasPrefix("Start at login is on")
        }
        .onChange(of: startAtLogin) { _, newValue in
            setLaunchAgent(enabled: newValue)
        }
    }

    // Mirrors LegacySettingsView.setLaunchAgent: toggles isChangingLaunchAgent, shows a
    // transient message, calls LaunchAgentManager.enable()/disable() off the main actor,
    // and on failure reverts the toggle and reports the error in the helper text.
    private func setLaunchAgent(enabled: Bool) {
        guard enabled != launchAgentMessage.hasPrefix("Start at login is on") else { return }
        isChangingLaunchAgent = true
        launchAgentMessage = enabled ? "Enabling start at login..." : "Disabling start at login..."
        Task {
            let result: String
            var failed = false
            do {
                if enabled {
                    try LaunchAgentManager.enable()
                } else {
                    try LaunchAgentManager.disable()
                }
                result = LaunchAgentManager.statusMessage()
            } catch {
                failed = true
                result = "Could not \(enabled ? "enable" : "disable") start at login: \(error.localizedDescription)"
            }
            await MainActor.run {
                launchAgentMessage = result
                isChangingLaunchAgent = false
                if failed { startAtLogin = !enabled }
                else { startAtLogin = result.hasPrefix("Start at login is on") }
            }
        }
    }
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
    @AppStorage(AppPreferences.menuBarDisplayModeKey) private var displayMode = MenuBarDisplayMode.detailed.rawValue
    @AppStorage(AppPreferences.menuBarProviderFocusKey) private var providerFocus = MenuBarProviderFocus.auto.rawValue
    @AppStorage(AppPreferences.heroLayoutKey) private var heroLayout = HeroLayout.featured.rawValue

    var body: some View {
        SettingsPane(title: "Menu bar",
                     subtitle: "Control how much the menu-bar label shows, and which provider drives it.") {
            SettingsGroup(title: "Preview") {
                HStack {
                    Spacer()
                    Text("◐ Claude 5h · 19% · 47m")
                        .font(.fuelMono(12)).foregroundStyle(FuelTheme.critical)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(FuelTheme.surfaceSunken, in: Capsule())
                    Spacer()
                }.padding(.vertical, 14)
            }
            SettingsGroup(title: "Display density") {
                SettingsRow(icon: nil, title: "Label detail", helper: "From full detail down to a single status glyph.") {
                    Picker("", selection: $displayMode) {
                        Text("Detail").tag(MenuBarDisplayMode.detailed.rawValue)
                        Text("Pair").tag(MenuBarDisplayMode.pair.rawValue)
                        Text("Trend").tag(MenuBarDisplayMode.sparkline.rawValue)
                        Text("Compact").tag(MenuBarDisplayMode.compact.rawValue)
                        Text("Min").tag(MenuBarDisplayMode.minimal.rawValue)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Divider().background(FuelTheme.divider).padding(.leading, 14)
                SettingsRow(icon: nil, title: "Provider focus", helper: "Auto picks the tightest useful lane. Pin one to always lead.") {
                    Picker("", selection: $providerFocus) {
                        ForEach(MenuBarProviderFocus.allCases, id: \.rawValue) { focus in
                            Text(focusLabel(focus)).tag(focus.rawValue)
                        }
                    }.pickerStyle(.menu).labelsHidden().fixedSize()
                }
            }
            SettingsGroup(title: "Popover hero") {
                SettingsRow(icon: nil, title: "Default layout", helper: "Featured shows one big gauge; Top 3 shows three compact gauges.") {
                    Picker("", selection: $heroLayout) {
                        Text("Featured").tag(HeroLayout.featured.rawValue)
                        Text("Top 3").tag(HeroLayout.trio.rawValue)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }

    // Matches the labels LegacySettingsView uses for its Focus picker.
    private func focusLabel(_ focus: MenuBarProviderFocus) -> String {
        switch focus {
        case .auto: return "Auto"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .claudeCode: return "Claude"
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        }
    }
}
struct BudgetsPane: View {
    @AppStorage(AppPreferences.openAIMonthlyBudgetUSDKey) private var openAI = ""
    @AppStorage(AppPreferences.cursorMonthlyBudgetUSDKey) private var cursor = ""
    @AppStorage(AppPreferences.openRouterMonthlyBudgetCreditsKey) private var openRouter = ""

    var body: some View {
        SettingsPane(title: "Budgets",
                     subtitle: "Optional monthly guardrails turn raw spend rows into comparable warning lanes. Leave blank to show spend only — never an invented limit.") {
            SettingsGroup(title: "Monthly guardrails") {
                budgetRow("OpenAI", helper: "Turns month-to-date spend into a budget lane.", text: $openAI, prefix: "$")
                Divider().background(FuelTheme.divider).padding(.leading, 14)
                budgetRow("Cursor", helper: "Optional spend guardrail for Cursor spend rows.", text: $cursor, prefix: "$")
                Divider().background(FuelTheme.divider).padding(.leading, 14)
                budgetRow("OpenRouter", helper: "Optional key-usage guardrail in credits.", text: $openRouter, prefix: nil)
            }
        }
    }

    private func budgetRow(_ title: String, helper: String, text: Binding<String>, prefix: String?) -> some View {
        SettingsRow(icon: "dollarsign", title: title, helper: helper) {
            HStack(spacing: 4) {
                if let prefix { Text(prefix).font(.fuelMono(12)).foregroundStyle(FuelTheme.text3) }
                TextField("", text: text).textFieldStyle(.roundedBorder).frame(width: 90).font(.fuelMono(12))
            }
        }
    }
}
struct PrivacyPane: View {
    var body: some View { SettingsPane(title: "Data & Privacy", subtitle: "All data stays on your Mac.") { EmptyView() } }
}
struct AboutPane: View {
    var body: some View { SettingsPane(title: "About", subtitle: "AI Fuel Gauge.") { EmptyView() } }
}
