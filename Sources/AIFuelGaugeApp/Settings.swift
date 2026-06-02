// Sources/AIFuelGaugeApp/Settings.swift
import AppKit
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
    @AppStorage(AppPreferences.monitorCodexEnabledKey) private var monitorCodexEnabled = true
    @AppStorage(AppPreferences.monitorCursorEnabledKey) private var monitorCursorEnabled = true
    @AppStorage(AppPreferences.monitorClaudeCodeEnabledKey) private var monitorClaudeCodeEnabled = true
    @AppStorage(AppPreferences.monitorOpenCodeEnabledKey) private var monitorOpenCodeEnabled = true
    @AppStorage(AppPreferences.monitorOpenRouterEnabledKey) private var monitorOpenRouterEnabled = true
    @AppStorage(AppPreferences.monitorOpenAIEnabledKey) private var monitorOpenAIEnabled = true
    @AppStorage(AppPreferences.claudeCodePlanLabelKey) private var claudeCodePlanLabel = ""
    @AppStorage(AppPreferences.cursorPlanOverrideKey) private var cursorPlanOverride = ""

    var body: some View {
        SettingsPane(title: "Providers",
                     subtitle: "Turn sources on or off. Disabling one removes it from polling, alerts, history, and the exported status snapshot.") {
            SettingsGroup(title: "Monitored sources") {
                monitorRow("Codex", icon: "cpu", helper: "Account quota plus local fallback from ~/.codex.", isOn: $monitorCodexEnabled)
                divider
                monitorRow("Cursor", icon: "cursorarrow.rays", helper: "Local account state plus live current-period usage.", isOn: $monitorCursorEnabled)
                divider
                monitorRow("Claude Code", icon: "sparkles", helper: "Local token estimates from ~/.claude/projects.", isOn: $monitorClaudeCodeEnabled)
                divider
                monitorRow("OpenCode", icon: "chevron.left.forwardslash.chevron.right", helper: "Local token estimates from OpenCode SQLite.", isOn: $monitorOpenCodeEnabled)
                divider
                monitorRow("OpenRouter", icon: "point.3.connected.trianglepath.dotted", helper: "Official key and credit endpoints when a key is saved.", isOn: $monitorOpenRouterEnabled)
                divider
                monitorRow("OpenAI", icon: "brain", helper: "Official organization costs and token usage when an admin key is saved.", isOn: $monitorOpenAIEnabled)
            }
            SettingsGroup(title: "Plan label overrides") {
                SettingsRow(icon: "tag", title: "Codex",
                            helper: "Exact plan and quota from ~/.codex/auth.json when available.") {
                    Text("Auto")
                        .font(.fuelText(12, weight: .semibold)).foregroundStyle(FuelTheme.text3)
                }
                divider
                SettingsRow(icon: "tag", title: "Claude Code",
                            helper: "Override the detected plan label only if needed.") {
                    TextField("Auto", text: $claudeCodePlanLabel)
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                }
                divider
                SettingsRow(icon: "tag", title: "Cursor",
                            helper: "Override the detected plan label only if needed.") {
                    TextField("Auto", text: $cursorPlanOverride)
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                }
            }
        }
    }

    private var divider: some View {
        Divider().background(FuelTheme.divider).padding(.leading, 14)
    }

    private func monitorRow(_ provider: String, icon: String, helper: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(icon: icon, title: provider, helper: helper) {
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(FuelTheme.accent)
        }
    }
}

/// Keychain-backed key entry with Connected state + sanitized status line.
struct KeyField: View {
    let title: String
    let helper: String
    @Binding var value: String
    let isConnected: Bool
    let status: String
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        SettingsRow(icon: "key", title: title, helper: helper) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.fuelText(11, weight: .semibold)).foregroundStyle(FuelTheme.safe)
                    }
                    SecureField("Paste key", text: $value).textFieldStyle(.roundedBorder).frame(width: 180)
                    Button("Save", action: onSave).buttonStyle(.bordered)
                    if isConnected { Button("Clear", action: onClear).buttonStyle(.borderless) }
                }
                if !status.isEmpty { Text(status).font(.fuelText(10.5)).foregroundStyle(FuelTheme.text3) }
            }
        }
    }
}

struct APIKeysPane: View {
    @State private var openRouterKey = ""
    @State private var openAIAdminKey = ""
    @State private var openRouterConnected = false
    @State private var openAIConnected = false
    @State private var openRouterStatus = "Stored in macOS Keychain. Not synced."
    @State private var openAIStatus = "Stored in macOS Keychain. Admin key is used only for OpenAI usage/cost APIs."

    var body: some View {
        SettingsPane(title: "API Keys",
                     subtitle: "Keys are stored in the macOS Keychain and used only for official usage and cost APIs.") {
            SettingsGroup(title: "OpenRouter") {
                KeyField(title: "OpenRouter API key",
                         helper: "Enables official key and credit endpoints.",
                         value: $openRouterKey,
                         isConnected: openRouterConnected,
                         status: openRouterStatus,
                         onSave: saveOpenRouter,
                         onClear: clearOpenRouter)
            }
            SettingsGroup(title: "OpenAI") {
                KeyField(title: "OpenAI Admin key",
                         helper: "Enables official organization cost and usage polling.",
                         value: $openAIAdminKey,
                         isConnected: openAIConnected,
                         status: openAIStatus,
                         onSave: saveOpenAI,
                         onClear: clearOpenAI)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        openRouterKey = KeychainStore.readOpenRouterKey() ?? ""
        openAIAdminKey = KeychainStore.readOpenAIAdminKey() ?? ""
        openRouterConnected = !openRouterKey.isEmpty
        openAIConnected = !openAIAdminKey.isEmpty
    }

    private func saveOpenRouter() {
        do {
            try KeychainStore.saveOpenRouterKey(openRouterKey)
            openRouterConnected = !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            openRouterStatus = "OpenRouter key saved. Refresh will use it for live API polling."
        } catch {
            openRouterStatus = "Could not save key: \(error.localizedDescription)"
        }
    }

    private func clearOpenRouter() {
        KeychainStore.deleteOpenRouterKey()
        openRouterKey = ""
        openRouterConnected = false
        openRouterStatus = "OpenRouter key deleted."
    }

    private func saveOpenAI() {
        do {
            try KeychainStore.saveOpenAIAdminKey(openAIAdminKey)
            openAIConnected = !openAIAdminKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            openAIStatus = "OpenAI Admin key saved. Refresh will use it for cost and usage polling."
        } catch {
            openAIStatus = "Could not save key: \(error.localizedDescription)"
        }
    }

    private func clearOpenAI() {
        KeychainStore.deleteOpenAIAdminKey()
        openAIAdminKey = ""
        openAIConnected = false
        openAIStatus = "OpenAI Admin key deleted."
    }
}

struct AlertsPane: View {
    @AppStorage(AppPreferences.alert50EnabledKey) private var alert50Enabled = false
    @AppStorage(AppPreferences.alert75EnabledKey) private var alert75Enabled = true
    @AppStorage(AppPreferences.alert90EnabledKey) private var alert90Enabled = true
    @AppStorage(AppPreferences.alert100EnabledKey) private var alert100Enabled = true
    @AppStorage(AppPreferences.staleWarningsEnabledKey) private var staleWarningsEnabled = true
    @AppStorage(AppPreferences.codexAlertProfileKey) private var codexAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.cursorAlertProfileKey) private var cursorAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.openRouterAlertProfileKey) private var openRouterAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.claudeCodeAlertProfileKey) private var claudeCodeAlertProfile = AlertThresholdProfile.inherit.rawValue

    var body: some View {
        SettingsPane(title: "Alerts",
                     subtitle: "Choose which thresholds notify you, and tune notifications per provider.") {
            SettingsGroup(title: "Notification thresholds") {
                toggleRow("50%", icon: "bell", helper: "Notify when usage crosses 50% of a lane.", isOn: $alert50Enabled)
                divider
                toggleRow("75%", icon: "bell", helper: "Notify when usage crosses 75% of a lane.", isOn: $alert75Enabled)
                divider
                toggleRow("90%", icon: "bell", helper: "Notify when usage crosses 90% of a lane.", isOn: $alert90Enabled)
                divider
                toggleRow("100%", icon: "bell.badge", helper: "Notify when a lane is exhausted.", isOn: $alert100Enabled)
                divider
                toggleRow("Stale data warnings", icon: "clock.badge.exclamationmark",
                          helper: "Warn when a provider's data goes stale.", isOn: $staleWarningsEnabled)
            }
            SettingsGroup(title: "Per-provider alert profile") {
                profileRow("Codex", selection: $codexAlertProfile)
                divider
                profileRow("Cursor", selection: $cursorAlertProfile)
                divider
                profileRow("OpenRouter", selection: $openRouterAlertProfile)
                divider
                profileRow("Claude Code", selection: $claudeCodeAlertProfile)
            }
        }
    }

    private var divider: some View {
        Divider().background(FuelTheme.divider).padding(.leading, 14)
    }

    private func toggleRow(_ title: String, icon: String, helper: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(icon: icon, title: title, helper: helper) {
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(FuelTheme.accent)
        }
    }

    private func profileRow(_ provider: String, selection: Binding<String>) -> some View {
        let profile = AlertThresholdProfile(rawValue: selection.wrappedValue) ?? .inherit
        return SettingsRow(icon: "slider.horizontal.3", title: provider, helper: profile.detail) {
            Picker("", selection: selection) {
                ForEach(AlertThresholdProfile.allCases) { profile in
                    Text(profile.title).tag(profile.rawValue)
                }
            }.pickerStyle(.menu).labelsHidden().fixedSize()
        }
    }
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
    @State private var historyMessage = "History stores only lane IDs, timestamps, and percentages."

    var body: some View {
        SettingsPane(title: "Data & Privacy",
                     subtitle: "All data stays on your Mac. History is local-only; clearing it is immediate and permanent.") {
            SettingsGroup(title: "Local history") {
                SettingsRow(icon: "clock.arrow.circlepath", title: "Usage history",
                            helper: historyMessage) {
                    HStack(spacing: 8) {
                        Button("Reveal history") { revealHistory() }.buttonStyle(.bordered)
                        Button("Clear history") { clearHistory() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func revealHistory() {
        let historyURL = AppStoragePaths.historyURL
        if FileManager.default.fileExists(atPath: historyURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([historyURL])
            historyMessage = "Revealed usage-history.json in Finder."
            return
        }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(historyURL.deletingLastPathComponent())
            historyMessage = "History file has not been created yet. Opened its folder."
        } catch {
            historyMessage = "Could not open history folder: \(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        do {
            try UsageHistoryFileStore(fileURL: AppStoragePaths.historyURL).clear()
            NotificationCenter.default.post(name: .aiFuelGaugeHistoryCleared, object: nil)
            historyMessage = "Local usage history cleared."
        } catch {
            historyMessage = "Could not clear history: \(error.localizedDescription)"
        }
    }
}

struct AboutPane: View {
    @State private var maintenanceMessage = "Use Releases for signed zips, or copy the Homebrew command for terminal updates."
    @State private var isCheckingForUpdates = false

    var body: some View {
        SettingsPane(title: "About", subtitle: "Local-first AI usage gauge") {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Fuel Gauge").font(.fuelText(15, weight: .bold)).foregroundStyle(FuelTheme.text)
                Text(appVersionString).font(.fuelMono(12)).foregroundStyle(FuelTheme.text3)
            }
            SettingsGroup(title: "App maintenance") {
                SettingsRow(icon: "arrow.down.circle", title: "Updates",
                            helper: maintenanceMessage) {
                    HStack(spacing: 8) {
                        Button(isCheckingForUpdates ? "Checking" : "Check updates") { checkForUpdates() }
                            .buttonStyle(.bordered)
                            .disabled(isCheckingForUpdates)
                        Button("Copy update command") { copyUpdateCommand() }.buttonStyle(.bordered)
                        Button("Open releases") { openReleases() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var currentAppVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var appVersionString: String {
        currentAppVersion.map { "v\($0)" } ?? "local build"
    }

    private func checkForUpdates() {
        isCheckingForUpdates = true
        maintenanceMessage = "Checking GitHub releases..."
        Task {
            let result: String
            do {
                let update = try await AppUpdateChecker().check(currentVersion: currentAppVersion)
                result = update.message
            } catch ConnectorError.badStatus(404) {
                result = "No GitHub release is published yet."
            } catch {
                result = "Could not check releases. Use Open releases or try again later."
            }
            await MainActor.run { maintenanceMessage = result; isCheckingForUpdates = false }
        }
    }

    private func copyUpdateCommand() {
        let command = "brew upgrade --cask ai-fuel-gauge || brew install --cask https://raw.githubusercontent.com/ozansozuozgit/aifuelgauge/main/Casks/ai-fuel-gauge.rb"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        maintenanceMessage = "Copied Homebrew update command."
    }

    private func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ozansozuozgit/aifuelgauge/releases/latest")!)
        maintenanceMessage = "Opened the latest GitHub release."
    }
}
