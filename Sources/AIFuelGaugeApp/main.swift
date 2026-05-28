import AppKit
import Combine
import Security
import SwiftUI
import UserNotifications
import AIFuelGaugeCore

@MainActor
final class AIFuelGaugeAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let controller = DashboardController()
    private let settingsWindowController = SettingsWindowController()
    private let historyWindowController = HistoryWindowController()
    private var modelCancellable: AnyCancellable?
    private var appResignObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppPreferences.registerDefaults()
        installMainMenu()
        NotificationBridge.requestAuthorization()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        self.statusItem = statusItem
        updateStatusItem(with: controller.model)

        modelCancellable = controller.$model.sink { [weak self] model in
            self?.updateStatusItem(with: model)
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 500, height: 700)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                controller: controller,
                actions: DashboardActions(
                    refresh: { [weak controller] in controller?.refresh() },
                    settings: { [weak self] in self?.settingsWindowController.show() },
                    history: { [weak self, weak controller] in
                        guard let dashboard = controller?.historyDashboard() else { return }
                        self?.historyWindowController.show(dashboard: dashboard)
                    },
                    copyStatus: { [weak controller] in controller?.copyStatusSnapshot() },
                    copyDiagnostics: { [weak controller] in controller?.copyDiagnostics() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        )
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.popover.performClose(nil)
            }
        }
    }

    private func updateStatusItem(with model: DashboardViewModel) {
        guard let button = statusItem?.button else { return }
        button.title = model.title
        button.image = NSImage(systemSymbolName: statusSymbolName(for: model.state), accessibilityDescription: model.statusLabel)
        button.image?.isTemplate = false
        button.imagePosition = .imageLeading
        button.contentTintColor = statusTintColor(for: model.state)
        button.toolTip = "\(model.statusLabel) · \(model.insight)"
    }

    private func statusSymbolName(for state: UsageState) -> String {
        switch state {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "gauge.medium"
        case .critical: return "exclamationmark.triangle.fill"
        case .exhausted: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func statusTintColor(for state: UsageState) -> NSColor {
        switch state {
        case .safe: return NSColor.systemGreen
        case .caution: return NSColor.systemYellow
        case .critical: return NSColor.systemOrange
        case .exhausted: return NSColor.systemRed
        case .unknown: return NSColor.systemGray
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit AI Fuel Gauge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            controller.refresh()
        }
    }
}

private enum AppPreferences {
    static let claudeCodePlanLabelKey = "claudeCodePlanLabel"
    static let cursorPlanOverrideKey = "cursorPlanOverride"
    static let alert50EnabledKey = "alert50Enabled"
    static let alert75EnabledKey = "alert75Enabled"
    static let alert90EnabledKey = "alert90Enabled"
    static let alert100EnabledKey = "alert100Enabled"
    static let codexAlertProfileKey = "codexAlertProfile"
    static let cursorAlertProfileKey = "cursorAlertProfile"
    static let openRouterAlertProfileKey = "openRouterAlertProfile"
    static let claudeCodeAlertProfileKey = "claudeCodeAlertProfile"
    static let staleWarningsEnabledKey = "staleWarningsEnabled"
    static let refreshIntervalSecondsKey = "refreshIntervalSeconds"
    static let menuBarDisplayModeKey = "menuBarDisplayMode"
    static let openAIMonthlyBudgetUSDKey = "openAIMonthlyBudgetUSD"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            claudeCodePlanLabelKey: "Free",
            cursorPlanOverrideKey: "",
            alert50EnabledKey: false,
            alert75EnabledKey: true,
            alert90EnabledKey: true,
            alert100EnabledKey: true,
            codexAlertProfileKey: AlertThresholdProfile.inherit.rawValue,
            cursorAlertProfileKey: AlertThresholdProfile.inherit.rawValue,
            openRouterAlertProfileKey: AlertThresholdProfile.inherit.rawValue,
            claudeCodeAlertProfileKey: AlertThresholdProfile.inherit.rawValue,
            staleWarningsEnabledKey: true,
            refreshIntervalSecondsKey: 180,
            menuBarDisplayModeKey: MenuBarDisplayMode.detailed.rawValue,
            openAIMonthlyBudgetUSDKey: ""
        ])
    }

    static func localPlanPreferences() -> LocalPlanPreferences {
        LocalPlanPreferences(
            claudeCodePlan: string(for: claudeCodePlanLabelKey),
            cursorPlanOverride: string(for: cursorPlanOverrideKey)
        )
    }

    static func alertThresholds() -> [Double] {
        var thresholds: [Double] = []
        if UserDefaults.standard.bool(forKey: alert50EnabledKey) { thresholds.append(0.50) }
        if UserDefaults.standard.bool(forKey: alert75EnabledKey) { thresholds.append(0.75) }
        if UserDefaults.standard.bool(forKey: alert90EnabledKey) { thresholds.append(0.90) }
        if UserDefaults.standard.bool(forKey: alert100EnabledKey) { thresholds.append(1.00) }
        return thresholds
    }

    static func alertThresholdsByProvider() -> [Provider: [Double]] {
        let providerKeys: [(Provider, String)] = [
            (.codex, codexAlertProfileKey),
            (.cursor, cursorAlertProfileKey),
            (.openRouter, openRouterAlertProfileKey),
            (.claudeCode, claudeCodeAlertProfileKey)
        ]
        return providerKeys.reduce(into: [Provider: [Double]]()) { result, item in
            let profile = AlertThresholdProfile(rawValue: UserDefaults.standard.string(forKey: item.1) ?? "") ?? .inherit
            guard profile != .inherit else { return }
            result[item.0] = profile.thresholds(global: alertThresholds())
        }
    }

    static var staleWarningsEnabled: Bool {
        UserDefaults.standard.bool(forKey: staleWarningsEnabledKey)
    }

    static var refreshIntervalSeconds: TimeInterval {
        let seconds = UserDefaults.standard.integer(forKey: refreshIntervalSecondsKey)
        return TimeInterval(max(60, seconds))
    }

    static var menuBarDisplayMode: MenuBarDisplayMode {
        let rawValue = UserDefaults.standard.string(forKey: menuBarDisplayModeKey) ?? MenuBarDisplayMode.detailed.rawValue
        return MenuBarDisplayMode(rawValue: rawValue) ?? .detailed
    }

    static func budgetPreferences() -> UsageBudgetPreferences {
        UsageBudgetPreferences(openAIMonthlyUSD: double(for: openAIMonthlyBudgetUSDKey))
    }

    private static func string(for key: String) -> String? {
        let trimmed = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func double(for key: String) -> Double? {
        guard let value = string(for: key) else { return nil }
        let sanitized = value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return Double(sanitized)
    }
}

private enum AlertThresholdProfile: String, CaseIterable, Identifiable {
    case inherit
    case early
    case standard
    case criticalOnly
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: "Global"
        case .early: "Early"
        case .standard: "Standard"
        case .criticalOnly: "Critical"
        case .off: "Off"
        }
    }

    var detail: String {
        switch self {
        case .inherit: "Use the global warning thresholds."
        case .early: "Warn at 50%, 75%, 90%, and 100%."
        case .standard: "Warn at 75%, 90%, and 100%."
        case .criticalOnly: "Warn only at 90% and 100%."
        case .off: "Do not send quota alerts for this provider."
        }
    }

    func thresholds(global: [Double]) -> [Double] {
        switch self {
        case .inherit: global
        case .early: [0.50, 0.75, 0.90, 1.00]
        case .standard: [0.75, 0.90, 1.00]
        case .criticalOnly: [0.90, 1.00]
        case .off: []
        }
    }
}

private enum AppStoragePaths {
    private static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AI Fuel Gauge", isDirectory: true)
    }

    static var historyURL: URL {
        appSupportDirectory.appendingPathComponent("usage-history.json")
    }

    static var statusURL: URL {
        appSupportDirectory.appendingPathComponent("status.json")
    }
}

private extension Notification.Name {
    static let aiFuelGaugeHistoryCleared = Notification.Name("aiFuelGaugeHistoryCleared")
}

@MainActor
private final class DashboardController: ObservableObject {
    @Published private(set) var model: DashboardViewModel
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshCancellable: AnyCancellable?
    private var localSourceCancellable: AnyCancellable?
    private var preferenceCancellable: AnyCancellable?
    private var historyCancellable: AnyCancellable?
    private var summary: UsageSummary?
    private let historyStore = UsageHistoryFileStore(fileURL: AppStoragePaths.historyURL)
    private var history: UsageHistorySeries
    private var notifiedStaleIDs = Set<String>()
    private var lastRefreshAt = Date.distantPast
    private var lastLocalSourceFingerprint = LocalAgentSourceMonitor().fingerprint()

    init() {
        let loadedHistory = UsageHistoryFileStore(fileURL: AppStoragePaths.historyURL).load()
        self.history = loadedHistory
        self.model = DashboardViewModel(
            summary: UsageSummary(snapshots: []),
            history: loadedHistory.percentsBySnapshotID,
            historySamples: loadedHistory.samplesBySnapshotID,
            menuBarDisplayMode: AppPreferences.menuBarDisplayMode
        )
        startAutoRefresh()
        startLocalSourceMonitor()
        observePreferences()
        observeHistoryChanges()
        refresh()
    }


    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshAt = Date()
        refreshError = nil
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let result = await Self.loadUsageOffMain()
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let previous = self.summary
            self.summary = result.summary
            self.history.record(summary: result.summary)
            try? self.historyStore.save(self.history)
            self.rebuildModel()
            self.refreshError = result.error
            self.deliverAlerts(for: result.summary, previous: previous)
            self.isRefreshing = false
        }
    }

    private func startAutoRefresh() {
        autoRefreshCancellable = Timer.publish(every: 60, tolerance: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, Date().timeIntervalSince(self.lastRefreshAt) >= AppPreferences.refreshIntervalSeconds else { return }
                self.refresh()
            }
    }

    private func startLocalSourceMonitor() {
        localSourceCancellable = Timer.publish(every: 20, tolerance: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    let fingerprint = await Task.detached(priority: .utility) {
                        LocalAgentSourceMonitor().fingerprint()
                    }.value
                    await MainActor.run {
                        guard fingerprint != self.lastLocalSourceFingerprint else { return }
                        self.lastLocalSourceFingerprint = fingerprint
                        self.refresh()
                    }
                }
            }
    }

    private func observePreferences() {
        preferenceCancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildModel()
                }
            }
    }

    private func observeHistoryChanges() {
        historyCancellable = NotificationCenter.default.publisher(for: .aiFuelGaugeHistoryCleared)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.clearHistory()
                }
            }
    }

    private func clearHistory() {
        history = UsageHistorySeries()
        rebuildModel()
    }

    func copyDiagnostics() {
        let report = DashboardDiagnosticsReport.make(
            summary: summary ?? UsageSummary(snapshots: []),
            history: history,
            historyPath: AppStoragePaths.historyURL.path,
            refreshError: refreshError
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func copyStatusSnapshot() {
        let snapshot = DashboardStatusSnapshot.make(model: model)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot, forType: .string)
    }

    func historyDashboard() -> UsageHistoryDashboard {
        UsageHistoryDashboard(history: history, summary: summary ?? UsageSummary(snapshots: []))
    }

    private func rebuildModel() {
        let currentSummary = summary ?? UsageSummary(snapshots: [])
        model = DashboardViewModel(
            summary: currentSummary,
            history: history.percentsBySnapshotID,
            historySamples: history.samplesBySnapshotID,
            menuBarDisplayMode: AppPreferences.menuBarDisplayMode
        )
        writeStatusExport()
    }

    private func writeStatusExport() {
        do {
            try FileManager.default.createDirectory(at: AppStoragePaths.statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try DashboardStatusExport.jsonData(model: model)
            try data.write(to: AppStoragePaths.statusURL, options: [.atomic])
        } catch {
            refreshError = [refreshError, "Status export failed"].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: " · ")
        }
    }

    private func deliverAlerts(for current: UsageSummary, previous: UsageSummary?) {
        let alertPlanner = UsageAlertPlanner(
            thresholds: AppPreferences.alertThresholds(),
            providerThresholds: AppPreferences.alertThresholdsByProvider()
        )
        let crossingAlerts = alertPlanner.alerts(previous: previous, current: current)
        let staleAlerts = AppPreferences.staleWarningsEnabled
            ? alertPlanner.staleAlerts(summary: current, now: Date(), maxAge: 600)
            .filter { notifiedStaleIDs.insert($0.identifier).inserted }
            : []
        let currentIDs = Set(current.snapshots.map(\.id))
        notifiedStaleIDs = notifiedStaleIDs.filter { staleID in
            currentIDs.contains(staleID.replacingOccurrences(of: "-stale", with: ""))
        }
        NotificationBridge.deliver(crossingAlerts + staleAlerts)
    }

    private static func loadUsageOffMain() async -> (summary: UsageSummary, error: String?) {
        await Task.detached(priority: .userInitiated) {
            var snapshots: [UsageSnapshot] = []
            var warnings: [String] = []

            do {
                snapshots.append(contentsOf: try LocalUsageCollector(planPreferences: AppPreferences.localPlanPreferences()).collect())
            } catch {
                warnings.append("Local refresh failed")
            }

            do {
                let codexSnapshots = try await CodexUsageConnector().fetchUsage()
                if !codexSnapshots.isEmpty {
                    snapshots.removeAll { $0.provider == .codex && $0.source == .localLogs }
                    snapshots.append(contentsOf: codexSnapshots)
                }
            } catch {
                let hasLocalCodexFallback = snapshots.contains { $0.provider == .codex && $0.source == .localLogs }
                warnings.append(hasLocalCodexFallback ? "Codex account unavailable, using local fallback" : "Codex account unavailable")
            }

            do {
                let cursorSnapshots = try await CursorUsageConnector(planPreferences: AppPreferences.localPlanPreferences()).fetchUsage()
                if !cursorSnapshots.isEmpty {
                    snapshots.removeAll { $0.provider == .cursor && $0.source == .localLogs }
                    snapshots.append(contentsOf: cursorSnapshots)
                }
            } catch {
                let hasLocalCursorFallback = snapshots.contains { $0.provider == .cursor && $0.source == .localLogs }
                if hasLocalCursorFallback {
                    warnings.append("Cursor usage unavailable, using subscription fallback")
                }
            }

            if let openRouterKey = KeychainStore.readOpenRouterKey(), !openRouterKey.isEmpty {
                let connector = OpenRouterConnector()
                do {
                    snapshots.append(try await connector.fetchCurrentKeyUsage(apiKey: openRouterKey))
                } catch {
                    warnings.append("OpenRouter key check failed")
                }
                do {
                    snapshots.append(try await connector.fetchAccountCredits(apiKey: openRouterKey))
                } catch {
                    warnings.append("OpenRouter credits failed")
                }
            }

            if let openAIAdminKey = KeychainStore.readOpenAIAdminKey(), !openAIAdminKey.isEmpty {
                let connector = OpenAIConnector()
                do {
                    snapshots.append(try await connector.fetchCurrentMonthCosts(adminKey: openAIAdminKey))
                } catch {
                    warnings.append("OpenAI costs failed")
                }
                do {
                    snapshots.append(try await connector.fetchCurrentMonthCompletionsUsage(adminKey: openAIAdminKey))
                } catch {
                    warnings.append("OpenAI usage failed")
                }
            }

            snapshots = UsageBudgetApplier.apply(preferences: AppPreferences.budgetPreferences(), to: snapshots)

            let summary = UsageSummary(snapshots: snapshots)
            return (summary, warnings.isEmpty ? nil : warnings.joined(separator: " · "))
        }.value
    }
}

private enum NotificationBridge {
    private static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func deliver(_ alerts: [UsageAlertEvent]) {
        guard canUseUserNotifications, !alerts.isEmpty else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = alert.state >= .critical ? .default : nil
            let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

private struct DashboardActions {
    let refresh: () -> Void
    let settings: () -> Void
    let history: () -> Void
    let copyStatus: () -> Void
    let copyDiagnostics: () -> Void
    let quit: () -> Void
}

private struct DashboardView: View {
    @ObservedObject var controller: DashboardController
    let actions: DashboardActions

    private var model: DashboardViewModel { controller.model }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            InsightStrip(text: model.insight, state: model.state)
            SourceHealthStrip(items: model.sourceHealth)
            if !model.setupGuidance.isEmpty {
                SetupGuidanceView(items: model.setupGuidance)
            }
            if !model.resetTimeline.isEmpty {
                ResetTimelineStrip(items: model.resetTimeline)
            }
            if let gauge = model.primaryGauge {
                PrimaryGaugeView(gauge: gauge)
            } else {
                UnknownGaugeView()
            }
            if model.rows.isEmpty, model.primaryGauge == nil {
                EmptySourcesView()
            } else if !model.rows.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            SourceRowView(row: row)
                            if row.id != model.rows.last?.id {
                                Divider().padding(.leading, 20).opacity(0.45)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            footer
        }
        .padding(16)
        .frame(width: 500, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Fuel Gauge")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(model.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatePill(state: model.state, label: model.statusLabel)
        }
    }

    private var footerStatusText: String {
        if controller.isRefreshing { return "Refreshing usage · \(model.trustDigest)" }
        return "\(model.footerNote) · \(model.trustDigest)"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(controller.refreshError ?? footerStatusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(controller.refreshError == nil ? Color.secondary.opacity(0.60) : Color.red)
                .lineLimit(1)
            Spacer(minLength: 8)
            FooterButton(title: "Refresh", systemName: "arrow.clockwise", action: actions.refresh)
            FooterButton(title: "Settings", systemName: "slider.horizontal.3", action: actions.settings)
            FooterButton(title: "History", systemName: "chart.line.uptrend.xyaxis", action: actions.history)
            FooterButton(title: "Status", systemName: "doc.on.doc", action: actions.copyStatus)
            FooterButton(title: "Report", systemName: "doc.on.clipboard", action: actions.copyDiagnostics)
            FooterButton(title: "Quit", systemName: "xmark", action: actions.quit)
        }
        .padding(.top, 1)
    }
}

private struct SetupGuidanceView: View {
    let items: [DashboardSetupItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Improve accuracy")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color(for: item.state))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(item.title)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(item.status)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(color(for: item.state))
                            }
                            Text(item.action)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.84))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .accessibilityLabel(items.map { "\($0.title): \($0.status). \($0.action)" }.joined(separator: ", "))
    }
}

private struct ResetTimelineStrip: View {
    let items: [DashboardResetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Next resets")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 7) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Circle()
                                .fill(color(for: item.state))
                                .frame(width: 5, height: 5)
                            Text(item.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        Text(item.value)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(color(for: item.state))
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.64), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .accessibilityLabel(items.map { "\($0.title) resets in \($0.value)" }.joined(separator: ", "))
    }
}

private struct SourceHealthStrip: View {
    let items: [DashboardSourceHealthItem]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(color(for: item.state))
                        .frame(width: 5, height: 5)
                    Text(item.title)
                        .lineLimit(1)
                    Text(item.value)
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.82))
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.64), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel(items.map { "\($0.title) \($0.value)" }.joined(separator: ", "))
    }
}

private struct InsightStrip: View {
    let text: String
    let state: UsageState

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color(for: state))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(color(for: state).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color(for: state).opacity(0.20), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch state {
        case .safe: "bolt.fill"
        case .caution: "speedometer"
        case .critical, .exhausted: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

private struct PrimaryGaugeView: View {
    let gauge: DashboardGauge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gauge.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(gauge.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(gauge.value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(color(for: gauge.state).gradient)
                        .frame(width: max(8, proxy.size.width * gauge.percent))
                }
            }
            .frame(height: 7)
            HStack {
                Text(gauge.caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color(for: gauge.state))
                Spacer()
                Text("Used")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            if let paceCaption = gauge.paceCaption {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: paceCaption.localizedCaseInsensitiveContains("warning") ? "speedometer" : "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(paceCaption.localizedCaseInsensitiveContains("warning") ? Color.orange : color(for: gauge.state).opacity(0.82))
                        .frame(width: 10)
                    Text(paceCaption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.84))
                        .lineLimit(2)
                }
            }
            if !gauge.explanation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: gauge.confidence == .exact ? "checkmark.seal.fill" : "info.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color(for: gauge.state).opacity(gauge.confidence == .unknown ? 0.65 : 0.95))
                        .frame(width: 10)
                    Text(gauge.explanation)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.82))
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct UnknownGaugeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect a quota source")
                .font(.system(size: 12, weight: .semibold))
            Text("Local logs are visible. Exact limits need a provider API key or a tool that exposes rate-limit metadata.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptySourcesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No live sources yet")
                .font(.system(size: 12, weight: .semibold))
            Text("Open Settings to add OpenRouter, or use Claude Code/Codex locally and refresh.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SourceRowView: View {
    let row: DashboardRow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color(for: row.state))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(row.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(row.value)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.state == .unknown ? .secondary : .primary)
                    .lineLimit(1)
            }
            if let percent = row.meterPercent {
                MiniMeter(percent: percent, label: row.meterLabel ?? "quota lane", state: row.state)
                    .padding(.leading, 16)
            }
            if row.trendPercents.count >= 2 {
                UsageSparkline(samples: row.trendPercents, state: row.state)
                    .frame(height: 18)
                    .padding(.leading, 16)
                    .accessibilityLabel("Recent usage trend")
                if let trendCaption = row.trendCaption {
                    Text(trendCaption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .padding(.leading, 16)
                }
            }
            if let paceCaption = row.paceCaption {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: paceCaption.localizedCaseInsensitiveContains("warning") ? "speedometer" : "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(paceCaption.localizedCaseInsensitiveContains("warning") ? Color.orange : color(for: row.state).opacity(0.82))
                        .frame(width: 10)
                    Text(paceCaption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.84))
                        .lineLimit(2)
                }
                .padding(.leading, 16)
            }
            if !row.explanation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: row.confidence == .exact ? "checkmark.seal.fill" : "info.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color(for: row.state).opacity(row.confidence == .unknown ? 0.65 : 0.95))
                        .frame(width: 10)
                    Text(row.explanation)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.82))
                        .lineLimit(2)
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

private struct UsageSparkline: View {
    let samples: [Double]
    let state: UsageState

    var body: some View {
        GeometryReader { proxy in
            let clamped = samples.map { min(max($0, 0), 1) }
            Path { path in
                guard clamped.count >= 2, proxy.size.width > 0, proxy.size.height > 0 else { return }
                let step = proxy.size.width / CGFloat(clamped.count - 1)
                for (index, sample) in clamped.enumerated() {
                    let x = CGFloat(index) * step
                    let y = proxy.size.height - (CGFloat(sample) * proxy.size.height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color(for: state).opacity(0.78), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            Path { path in
                let y = proxy.size.height * 0.25
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
            }
            .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
    }
}

private struct MiniMeter: View {
    let percent: Double
    let label: String
    let state: UsageState

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(color(for: state).opacity(0.88))
                        .frame(width: max(5, proxy.size.width * min(max(percent, 0), 1)))
                }
            }
            .frame(height: 5)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color(for: state))
                .lineLimit(1)
        }
    }
}

private struct StatePill: View {
    let state: UsageState
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color(for: state))
                .frame(width: 6, height: 6)
            Text(label)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color(for: state).opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
    }
}

private struct FooterButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

@MainActor
private final class HistoryWindowController {
    private var window: NSWindow?

    func show(dashboard: UsageHistoryDashboard) {
        if let window {
            window.contentView = NSHostingView(rootView: HistoryWindowView(dashboard: dashboard))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Fuel Gauge History"
        window.center()
        window.contentView = NSHostingView(rootView: HistoryWindowView(dashboard: dashboard))
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HistoryWindowView: View {
    let dashboard: UsageHistoryDashboard
    @State private var copyMessage = "CSV includes lane IDs, timestamps, and percentages only."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(dashboard.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(copyMessage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.75))
                }
                Spacer()
                Button {
                    copyCSV()
                } label: {
                    Label("Copy CSV", systemImage: "tablecells")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(dashboard.items.isEmpty)
            }

            if dashboard.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No comparable history yet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("History appears after a few refreshes from sources with known limits. It stores lane IDs, timestamps, and percentages only.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(dashboard.items) { item in
                            HistoryLaneCard(item: item)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func copyCSV() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dashboard.csvText, forType: .string)
        copyMessage = "Copied CSV to clipboard."
    }
}

private struct HistoryLaneCard: View {
    let item: UsageHistoryDashboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(color(for: item.state))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.latestValue)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color(for: item.state))
            }

            UsageSparkline(samples: item.samples, state: item.state)
                .frame(height: 34)
                .accessibilityLabel("\(item.title) history trend")

            HStack(spacing: 8) {
                HistoryMetricPill(text: item.peakValue)
                HistoryMetricPill(text: item.deltaValue)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HistoryMetricPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

@MainActor
private final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Fuel Gauge Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @State private var openRouterKey: String
    @State private var openAIAdminKey: String
    @State private var message: String = "Stored in macOS Keychain. Not synced."
    @State private var openAIMessage: String = "Stored in macOS Keychain. Admin key is used only for OpenAI usage/cost APIs."
    @State private var isTestingOpenRouterKey = false
    @State private var isTestingOpenAIKey = false
    @State private var cursorMessage: String
    @State private var isTestingCursorUsage = false
    @State private var historyMessage: String = "History stores only lane IDs, timestamps, and percentages."
    @State private var maintenanceMessage: String = "Use Releases for signed zips, or copy the Homebrew command for terminal updates."
    @State private var isCheckingForUpdates = false
    @State private var detectedCursorPlan: String
    @State private var detectedCursorStatus: String
    @State private var detectedCursorAccount: String
    @AppStorage(AppPreferences.claudeCodePlanLabelKey) private var claudeCodePlanLabel = "Free"
    @AppStorage(AppPreferences.cursorPlanOverrideKey) private var cursorPlanOverride = ""
    @AppStorage(AppPreferences.alert50EnabledKey) private var alert50Enabled = false
    @AppStorage(AppPreferences.alert75EnabledKey) private var alert75Enabled = true
    @AppStorage(AppPreferences.alert90EnabledKey) private var alert90Enabled = true
    @AppStorage(AppPreferences.alert100EnabledKey) private var alert100Enabled = true
    @AppStorage(AppPreferences.codexAlertProfileKey) private var codexAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.cursorAlertProfileKey) private var cursorAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.openRouterAlertProfileKey) private var openRouterAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.claudeCodeAlertProfileKey) private var claudeCodeAlertProfile = AlertThresholdProfile.inherit.rawValue
    @AppStorage(AppPreferences.staleWarningsEnabledKey) private var staleWarningsEnabled = true
    @AppStorage(AppPreferences.refreshIntervalSecondsKey) private var refreshIntervalSeconds = 180
    @AppStorage(AppPreferences.menuBarDisplayModeKey) private var menuBarDisplayMode = MenuBarDisplayMode.detailed.rawValue
    @AppStorage(AppPreferences.openAIMonthlyBudgetUSDKey) private var openAIMonthlyBudgetUSD = ""

    init() {
        _openRouterKey = State(initialValue: KeychainStore.readOpenRouterKey() ?? "")
        _openAIAdminKey = State(initialValue: KeychainStore.readOpenAIAdminKey() ?? "")
        let cursorState = CursorAccountStateReader(
            cursorDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor")
        ).read()
        _detectedCursorPlan = State(initialValue: cursorState?.displayPlan ?? "Not found")
        _detectedCursorStatus = State(initialValue: cursorState?.displayStatus ?? "No local account status")
        _detectedCursorAccount = State(initialValue: cursorState?.maskedEmail ?? "No account identity")
        let cursorMessage = cursorState
            .map { state in
                "Detected \(state.displayPlan ?? "plan unknown") · \(state.displayStatus ?? "status unknown") · \(state.maskedEmail ?? "account hidden"). Test for exact live usage."
            } ?? "Cursor account not detected yet. Open Cursor while signed in, then test again."
        _cursorMessage = State(initialValue: cursorMessage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider keys")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Local-first sources stay automatic. Add keys only for providers that expose official usage metadata.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                SettingsPanel {
                    Text("Plan labels")
                        .font(.system(size: 11, weight: .semibold))
                    EditablePlanRow(provider: "Codex", value: "Auto from account", detail: "Exact plan and quota from ~/.codex/auth.json when available.")
                    EditableTextPlanRow(provider: "Claude Code", text: $claudeCodePlanLabel, placeholder: "Free", detail: "Shown with local token estimates. Clear it if this is wrong.")
                    EditableTextPlanRow(provider: "Cursor", text: $cursorPlanOverride, placeholder: detectedCursorPlan, detail: "Detected: \(detectedCursorPlan) · \(detectedCursorStatus) · \(detectedCursorAccount). Override only if needed.")
                    HStack(spacing: 8) {
                        Button(isTestingCursorUsage ? "Testing Cursor" : "Test Cursor") {
                            testCursorUsage()
                        }
                        .disabled(isTestingCursorUsage)
                        .help("Verify live Cursor usage without exposing your token")
                        Text(cursorMessage)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

            SettingsPanel {
                Text("Menu bar")
                    .font(.system(size: 11, weight: .semibold))
                Picker("Display", selection: $menuBarDisplayMode) {
                    Text("Detail").tag(MenuBarDisplayMode.detailed.rawValue)
                    Text("Pair").tag(MenuBarDisplayMode.pair.rawValue)
                    Text("Spark").tag(MenuBarDisplayMode.sparkline.rawValue)
                    Text("Compact").tag(MenuBarDisplayMode.compact.rawValue)
                    Text("Minimal").tag(MenuBarDisplayMode.minimal.rawValue)
                }
                .pickerStyle(.segmented)
                Text("Detail includes reset time. Pair shows two useful lanes. Spark adds recent trend. Compact drops reset. Minimal shows only the tightest percentage.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            SettingsPanel {
                Text("Auto-sync")
                    .font(.system(size: 11, weight: .semibold))
                Picker("Refresh", selection: $refreshIntervalSeconds) {
                    Text("1 min").tag(60)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                    Text("15 min").tag(900)
                }
                .pickerStyle(.segmented)
                Text("Runs in the background while the menu bar app is open. Manual Refresh always works immediately.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            SettingsPanel {
                Text("Warnings")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 12) {
                    Toggle("50%", isOn: $alert50Enabled)
                    Toggle("75%", isOn: $alert75Enabled)
                    Toggle("90%", isOn: $alert90Enabled)
                    Toggle("100%", isOn: $alert100Enabled)
                    Toggle("Stale", isOn: $staleWarningsEnabled)
                }
                .font(.system(size: 10, weight: .medium))
                Text("Alerts fire when usage crosses enabled thresholds. Codex notifications use remaining-capacity language.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            SettingsPanel {
                Text("Budget guardrails")
                    .font(.system(size: 11, weight: .semibold))
                EditableTextPlanRow(
                    provider: "OpenAI",
                    text: $openAIMonthlyBudgetUSD,
                    placeholder: "optional USD",
                    detail: "Turns current-month OpenAI spend into a comparable budget lane. Leave blank to show spend only."
                )
            }

            SettingsPanel {
                Text("Provider alert profiles")
                    .font(.system(size: 11, weight: .semibold))
                AlertProfileRow(provider: "Codex", selection: $codexAlertProfile)
                AlertProfileRow(provider: "Cursor", selection: $cursorAlertProfile)
                AlertProfileRow(provider: "OpenRouter", selection: $openRouterAlertProfile)
                AlertProfileRow(provider: "Claude Code", selection: $claudeCodeAlertProfile)
                Text("Global keeps the warning toggles above. Use Off for providers where notifications are noisy.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            SettingsPanel {
                Text("OpenRouter API key")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    SecureField("sk-or-v1-...", text: $openRouterKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") {
                        pasteOpenRouterKey()
                    }
                    .help("Paste from clipboard")
                    Button(isTestingOpenRouterKey ? "Testing" : "Test") {
                        testOpenRouterKey()
                    }
                    .disabled(isTestingOpenRouterKey)
                    .help("Test without saving")
                }
                HStack(spacing: 8) {
                    Button("Save OpenRouter") {
                        saveOpenRouterKey()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Delete") {
                        KeychainStore.deleteOpenRouterKey()
                        openRouterKey = ""
                        message = "OpenRouter key deleted."
                    }
                    Spacer()
                }
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            SettingsPanel {
                Text("OpenAI Admin key")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    SecureField("sk-admin-...", text: $openAIAdminKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") {
                        pasteOpenAIAdminKey()
                    }
                    .help("Paste from clipboard")
                    Button(isTestingOpenAIKey ? "Testing" : "Test") {
                        testOpenAIAdminKey()
                    }
                    .disabled(isTestingOpenAIKey)
                    .help("Test without saving")
                }
                HStack(spacing: 8) {
                    Button("Save OpenAI") {
                        saveOpenAIAdminKey()
                    }
                    Button("Delete") {
                        KeychainStore.deleteOpenAIAdminKey()
                        openAIAdminKey = ""
                        openAIMessage = "OpenAI Admin key deleted."
                    }
                    Spacer()
                }
                Text(openAIMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            SettingsPanel {
                Text("Data & privacy")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    Button("Reveal history") {
                        revealHistory()
                    }
                    Button("Reveal status JSON") {
                        revealStatusExport()
                    }
                    Button("Clear history") {
                        clearHistory()
                    }
                    Spacer()
                }
                Text(historyMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            SettingsPanel {
                Text("App maintenance")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    Button(isCheckingForUpdates ? "Checking" : "Check updates") {
                        checkForUpdates()
                    }
                    .disabled(isCheckingForUpdates)
                    Button("Open releases") {
                        openReleases()
                    }
                    Button("Copy update command") {
                        copyUpdateCommand()
                    }
                    Button("Reveal app") {
                        revealInstalledApp()
                    }
                    Spacer()
                }
                Text(maintenanceMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(spacing: 8) {
                HStack {
                    Button("Cursor usage") {
                        NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard")!)
                    }
                    Button("OpenRouter usage") {
                        NSWorkspace.shared.open(URL(string: "https://openrouter.ai/settings/credits")!)
                    }
                    Button("OpenAI usage") {
                        NSWorkspace.shared.open(URL(string: "https://platform.openai.com/usage")!)
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
    }
    .frame(width: 560, height: 860)
    }

    private func pasteOpenRouterKey() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else {
            message = "Clipboard does not contain text."
            return
        }
        openRouterKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        message = "Pasted from clipboard. Save to store it in Keychain."
    }

    private func pasteOpenAIAdminKey() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else {
            openAIMessage = "Clipboard does not contain text."
            return
        }
        openAIAdminKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIMessage = "Pasted from clipboard. Save to store it in Keychain."
    }

    private func saveOpenRouterKey() {
        do {
            try KeychainStore.saveOpenRouterKey(openRouterKey)
            message = "OpenRouter key saved. Refresh will use it for live API polling."
        } catch {
            message = "Could not save key: \(error.localizedDescription)"
        }
    }

    private func saveOpenAIAdminKey() {
        do {
            try KeychainStore.saveOpenAIAdminKey(openAIAdminKey)
            openAIMessage = "OpenAI Admin key saved. Refresh will use it for cost and usage polling."
        } catch {
            openAIMessage = "Could not save key: \(error.localizedDescription)"
        }
    }

    private func testOpenRouterKey() {
        let key = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            message = OpenRouterSetupCheck.failureMessage(error: ConnectorError.emptyAPIKey)
            return
        }
        isTestingOpenRouterKey = true
        message = "Testing OpenRouter key..."
        Task {
            let result: String
            do {
                let connector = OpenRouterConnector()
                let keySnapshot = try await connector.fetchCurrentKeyUsage(apiKey: key)
                let creditsSnapshot = try? await connector.fetchAccountCredits(apiKey: key)
                result = OpenRouterSetupCheck.successMessage(keySnapshot: keySnapshot, creditsSnapshot: creditsSnapshot)
            } catch {
                result = OpenRouterSetupCheck.failureMessage(error: error)
            }
            await MainActor.run {
                message = result
                isTestingOpenRouterKey = false
            }
        }
    }

    private func testOpenAIAdminKey() {
        let key = openAIAdminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            openAIMessage = OpenAISetupCheck.failureMessage(error: ConnectorError.emptyAPIKey)
            return
        }
        isTestingOpenAIKey = true
        openAIMessage = "Testing OpenAI Admin key..."
        Task {
            let result: String
            do {
                let connector = OpenAIConnector()
                let costs = try await connector.fetchCurrentMonthCosts(adminKey: key)
                let tokens = try? await connector.fetchCurrentMonthCompletionsUsage(adminKey: key)
                result = OpenAISetupCheck.successMessage(costs: costs, tokens: tokens)
            } catch {
                result = OpenAISetupCheck.failureMessage(error: error)
            }
            await MainActor.run {
                openAIMessage = result
                isTestingOpenAIKey = false
            }
        }
    }

    private func testCursorUsage() {
        isTestingCursorUsage = true
        cursorMessage = "Testing Cursor live usage..."
        Task {
            let result: String
            do {
                let snapshots = try await CursorUsageConnector(planPreferences: AppPreferences.localPlanPreferences()).fetchUsage()
                result = CursorSetupCheck.successMessage(snapshots: snapshots)
            } catch {
                result = CursorSetupCheck.failureMessage(error: error)
            }
            await MainActor.run {
                cursorMessage = result
                isTestingCursorUsage = false
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

    private func revealStatusExport() {
        let statusURL = AppStoragePaths.statusURL
        if FileManager.default.fileExists(atPath: statusURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([statusURL])
            historyMessage = "Revealed status.json in Finder."
            return
        }
        do {
            try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(statusURL.deletingLastPathComponent())
            historyMessage = "Opened status folder. status.json appears after the next refresh."
        } catch {
            historyMessage = "Could not open status folder: \(error.localizedDescription)"
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

    private func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ozansozuozgit/aifuelgauge/releases/latest")!)
        maintenanceMessage = "Opened the latest GitHub release."
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
            await MainActor.run {
                maintenanceMessage = result
                isCheckingForUpdates = false
            }
        }
    }

    private func copyUpdateCommand() {
        let command = "brew upgrade --cask ai-fuel-gauge || brew install --cask https://raw.githubusercontent.com/ozansozuozgit/aifuelgauge/main/Casks/ai-fuel-gauge.rb"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        maintenanceMessage = "Copied Homebrew update command."
    }

    private func revealInstalledApp() {
        let appURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/AI Fuel Gauge.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
            maintenanceMessage = "Revealed installed app in Finder."
            return
        }
        NSWorkspace.shared.open(appURL.deletingLastPathComponent())
        maintenanceMessage = "Opened ~/Applications. The installed app was not found there."
    }

    private var currentAppVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

private struct SettingsPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EditablePlanRow: View {
    let provider: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(provider)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct EditableTextPlanRow: View {
    let provider: String
    @Binding var text: String
    let placeholder: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(provider)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 86, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 110)
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct AlertProfileRow: View {
    let provider: String
    @Binding var selection: String

    private var selectedProfile: AlertThresholdProfile {
        AlertThresholdProfile(rawValue: selection) ?? .inherit
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(provider)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 86, alignment: .leading)
            Picker(provider, selection: $selection) {
                ForEach(AlertThresholdProfile.allCases) { profile in
                    Text(profile.title).tag(profile.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 118)
            Text(selectedProfile.detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private enum KeychainStore {
    private static let service = "AI Fuel Gauge"
    private static let openRouterAccount = "openrouter-api-key"
    private static let openAIAdminAccount = "openai-admin-api-key"

    static func readOpenRouterKey() -> String? {
        read(account: openRouterAccount)
    }

    static func readOpenAIAdminKey() -> String? {
        read(account: openAIAdminAccount)
    }

    static func saveOpenRouterKey(_ key: String) throws {
        try save(key, account: openRouterAccount)
    }

    static func saveOpenAIAdminKey(_ key: String) throws {
        try save(key, account: openAIAdminAccount)
    }

    static func deleteOpenRouterKey() {
        delete(account: openRouterAccount)
    }

    static func deleteOpenAIAdminKey() {
        delete(account: openAIAdminAccount)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ key: String, account: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(account: account)
            return
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status): "Keychain status \(status)"
        }
    }
}

private func color(for state: UsageState) -> Color {
    switch state {
    case .safe: Color(red: 0.23, green: 0.68, blue: 0.39)
    case .caution: Color(red: 0.86, green: 0.61, blue: 0.18)
    case .critical: Color(red: 0.88, green: 0.36, blue: 0.25)
    case .exhausted: Color(red: 0.70, green: 0.18, blue: 0.18)
    case .unknown: Color(red: 0.50, green: 0.53, blue: 0.58)
    }
}

private enum DemoData {
    static func summary() -> UsageSummary {
        UsageSummary(snapshots: [
            UsageSnapshot(
                provider: .openRouter,
                source: .officialAPI,
                label: "OpenRouter main key",
                used: .credits(76),
                limit: .credits(100),
                reset: .rollingWindow(secondsRemaining: 3600),
                confidence: .exact,
                updatedAt: Date()
            ),
            UsageSnapshot(
                provider: .claudeCode,
                source: .localLogs,
                label: "Claude Code",
                used: .tokens(input: 1200, output: 340, cacheRead: 4100, cacheWrite: 800),
                limit: nil,
                reset: nil,
                confidence: .estimated,
                updatedAt: Date()
            ),
            UsageSnapshot(
                provider: .codex,
                source: .localLogs,
                label: "Codex",
                used: .percent(42),
                limit: .percent(100),
                reset: .rollingWindow(secondsRemaining: 7200),
                confidence: .exact,
                updatedAt: Date()
            )
        ])
    }
}

let delegate = AIFuelGaugeAppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
