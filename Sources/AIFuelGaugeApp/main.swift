import AppKit
import Combine
import Darwin
import Security
import SwiftUI
import UniformTypeIdentifiers
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
        guard !Self.terminateDuplicateInstanceIfNeeded() else { return }
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
        let hosting = NSHostingController(
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
                    openQuickRoute: { [weak controller] route in controller?.openQuickRoute(route) },
                    copyQuickRoute: { [weak controller] route in controller?.copyQuickRoute(route) },
                    revealSession: { [weak controller] session in controller?.revealSession(session) },
                    openServer: { [weak controller] server in controller?.openServer(server) },
                    stopServer: { [weak controller] server in controller?.stopServer(server) },
                    copyRow: { row in
                        let text = row.receiptText.isEmpty ? row.value : row.receiptText
                        copyToPasteboard(text)
                    },
                    openRow: { row in
                        if let s = row.dashboardURL, let url = URL(string: s) {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    quit: { NSApp.terminate(nil) }
                )
            )
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    private func updateStatusItem(with model: DashboardViewModel) {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        let image = statusItemImage(title: model.title, state: model.state, accessibilityLabel: model.statusLabel)
        statusItem?.length = min(image.size.width, Self.maximumStatusItemWidth)
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.toolTip = "\(model.statusLabel) · \(model.insight)"
        button.setAccessibilityLabel("AI Fuel Gauge: \(model.title). \(model.statusLabel).")
    }

    private static let maximumStatusItemWidth: CGFloat = 150

    private static func terminateDuplicateInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let currentBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let installedBundlePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/AI Fuel Gauge.app")
            .standardizedFileURL
            .path
        let currentIsInstalledCopy = currentBundlePath == installedBundlePath
        let runningCopies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessID }

        guard !runningCopies.isEmpty else { return false }

        if currentIsInstalledCopy {
            for runningCopy in runningCopies {
                guard runningCopy.bundleURL?.standardizedFileURL.path != currentBundlePath else { continue }
                runningCopy.terminate()
            }
            return false
        }

        NSApp.terminate(nil)
        return true
    }

    private func statusItemImage(title: String, state: UsageState, accessibilityLabel: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let text = title as NSString
        let textSize = text.size(withAttributes: attributes)
        let iconSize = NSSize(width: 15, height: 15)
        let spacing: CGFloat = 5
        let horizontalPadding: CGFloat = 2
        let height: CGFloat = 22
        let maxTextWidth = Self.maximumStatusItemWidth - horizontalPadding * 2 - iconSize.width - spacing
        let textWidth = min(textSize.width, maxTextWidth)
        let width = ceil(horizontalPadding * 2 + iconSize.width + spacing + textWidth)
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.set()
        let iconRect = NSRect(
            x: horizontalPadding,
            y: floor((height - iconSize.height) / 2),
            width: iconSize.width,
            height: iconSize.height
        )
        statusSymbolImage(for: state, accessibilityLabel: accessibilityLabel)?.draw(in: iconRect)
        text.draw(
            in: NSRect(
                x: horizontalPadding + iconSize.width + spacing,
                y: floor((height - textSize.height) / 2),
                width: textWidth,
                height: ceil(textSize.height)
            ),
            withAttributes: attributes
        )

        image.isTemplate = true
        image.accessibilityDescription = "AI Fuel Gauge \(title)"
        return image
    }

    private func statusSymbolImage(for state: UsageState, accessibilityLabel: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let candidates: [String]
        switch state {
        case .safe:
            candidates = ["gauge.with.dots.needle.33percent", "gauge.low", "checkmark.circle.fill"]
        case .caution:
            candidates = ["gauge.with.dots.needle.50percent", "gauge.medium", "speedometer"]
        case .critical:
            candidates = ["gauge.with.dots.needle.67percent", "gauge.high", "exclamationmark.triangle.fill"]
        case .exhausted:
            candidates = ["gauge.with.dots.needle.100percent", "xmark.octagon.fill"]
        case .unknown:
            candidates = ["gauge.with.dots.needle.0percent", "questionmark.circle.fill"]
        }
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel)?
                .withSymbolConfiguration(configuration) {
                image.isTemplate = true
                return image
            }
        }
        return nil
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

        let dashboardItem = NSMenuItem()
        mainMenu.addItem(dashboardItem)
        let dashboardMenu = NSMenu(title: "AI Fuel Gauge")
        dashboardMenu.addItem(NSMenuItem(title: "Show Dashboard", action: #selector(showDashboard), keyEquivalent: "d"))
        dashboardMenu.addItem(NSMenuItem(title: "Refresh Usage", action: #selector(refreshUsage), keyEquivalent: "r"))
        dashboardMenu.addItem(NSMenuItem.separator())
        dashboardMenu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ","))
        dashboardMenu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: "h"))
        dashboardMenu.addItem(NSMenuItem.separator())
        dashboardMenu.addItem(NSMenuItem(title: "Copy Status", action: #selector(copyStatus), keyEquivalent: "s"))
        dashboardMenu.addItem(NSMenuItem(title: "Copy Diagnostics Report", action: #selector(copyDiagnostics), keyEquivalent: "i"))
        dashboardItem.submenu = dashboardMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showDashboard() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshUsage() {
        controller.refresh()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHistory() {
        historyWindowController.show(dashboard: controller.historyDashboard())
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyStatus() {
        controller.copyStatusSnapshot()
    }

    @objc private func copyDiagnostics() {
        controller.copyDiagnostics()
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

enum AppPreferences {
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
    static let menuBarProviderFocusKey = "menuBarProviderFocus"
    static let heroLayoutKey = "heroLayout"
    static let laneOrderKey = "laneOrder"
    static let openAIMonthlyBudgetUSDKey = "openAIMonthlyBudgetUSD"
    static let cursorMonthlyBudgetUSDKey = "cursorMonthlyBudgetUSD"
    static let openRouterMonthlyBudgetCreditsKey = "openRouterMonthlyBudgetCredits"
    static let monitorClaudeCodeEnabledKey = "monitorClaudeCodeEnabled"
    static let monitorCodexEnabledKey = "monitorCodexEnabled"
    static let monitorCursorEnabledKey = "monitorCursorEnabled"
    static let monitorOpenCodeEnabledKey = "monitorOpenCodeEnabled"
    static let monitorOpenRouterEnabledKey = "monitorOpenRouterEnabled"
    static let monitorOpenAIEnabledKey = "monitorOpenAIEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            claudeCodePlanLabelKey: "",
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
            menuBarProviderFocusKey: MenuBarProviderFocus.auto.rawValue,
            heroLayoutKey: HeroLayout.featured.rawValue,
            laneOrderKey: [],
            openAIMonthlyBudgetUSDKey: "",
            cursorMonthlyBudgetUSDKey: "",
            openRouterMonthlyBudgetCreditsKey: "",
            monitorClaudeCodeEnabledKey: true,
            monitorCodexEnabledKey: true,
            monitorCursorEnabledKey: true,
            monitorOpenCodeEnabledKey: true,
            monitorOpenRouterEnabledKey: true,
            monitorOpenAIEnabledKey: true
        ])
    }

    static func localPlanPreferences() -> LocalPlanPreferences {
        let detectedClaudePlan = ClaudeAccountStateReader().read()?.displayPlan
        let manualClaudePlan = string(for: claudeCodePlanLabelKey)
        let claudePlan = manualClaudePlan == "Free" ? (detectedClaudePlan ?? manualClaudePlan) : (manualClaudePlan ?? detectedClaudePlan)
        return LocalPlanPreferences(
            claudeCodePlan: claudePlan,
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

    static var menuBarProviderFocus: MenuBarProviderFocus {
        let rawValue = UserDefaults.standard.string(forKey: menuBarProviderFocusKey) ?? MenuBarProviderFocus.auto.rawValue
        return MenuBarProviderFocus(rawValue: rawValue) ?? .auto
    }

    static var heroLayout: HeroLayout {
        let raw = UserDefaults.standard.string(forKey: heroLayoutKey) ?? HeroLayout.featured.rawValue
        return HeroLayout(rawValue: raw) ?? .featured
    }

    static func laneOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: laneOrderKey) ?? []
    }

    static func budgetPreferences() -> UsageBudgetPreferences {
        UsageBudgetPreferences(
            openAIMonthlyUSD: double(for: openAIMonthlyBudgetUSDKey),
            cursorMonthlyUSD: double(for: cursorMonthlyBudgetUSDKey),
            openRouterMonthlyCredits: double(for: openRouterMonthlyBudgetCreditsKey)
        )
    }

    static var monitoredProviders: Set<Provider> {
        var providers = Set<Provider>()
        if UserDefaults.standard.bool(forKey: monitorClaudeCodeEnabledKey) { providers.insert(.claudeCode) }
        if UserDefaults.standard.bool(forKey: monitorCodexEnabledKey) { providers.insert(.codex) }
        if UserDefaults.standard.bool(forKey: monitorCursorEnabledKey) { providers.insert(.cursor) }
        if UserDefaults.standard.bool(forKey: monitorOpenCodeEnabledKey) { providers.insert(.openCode) }
        if UserDefaults.standard.bool(forKey: monitorOpenRouterEnabledKey) { providers.insert(.openRouter) }
        if UserDefaults.standard.bool(forKey: monitorOpenAIEnabledKey) { providers.insert(.openAI) }
        return providers
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

enum AlertThresholdProfile: String, CaseIterable, Identifiable {
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

enum AppStoragePaths {
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

    static var claudeStatusLineURL: URL {
        appSupportDirectory.appendingPathComponent("claude-statusline.json")
    }
}

extension Notification.Name {
    static let aiFuelGaugeHistoryCleared = Notification.Name("aiFuelGaugeHistoryCleared")
}

@MainActor
final class DashboardController: ObservableObject {
    @Published private(set) var model: DashboardViewModel
    @Published private(set) var workbench: AgentWorkbenchSnapshot = .empty
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
    private var isLocalSourceScanInFlight = false
    private let minimumLocalChangeRefreshInterval: TimeInterval = 60

    init() {
        let loadedHistory = UsageHistoryFileStore(fileURL: AppStoragePaths.historyURL).load()
        self.history = loadedHistory
        self.model = DashboardViewModel(
            summary: UsageSummary(snapshots: []),
            history: loadedHistory.percentsBySnapshotID,
            historySamples: loadedHistory.samplesBySnapshotID,
            monitoredProviders: AppPreferences.monitoredProviders,
            menuBarProviderFocus: AppPreferences.menuBarProviderFocus,
            menuBarDisplayMode: AppPreferences.menuBarDisplayMode,
            preferredMenuBarSnapshotID: Self.preferredMenuBarSnapshotID(
                in: UsageSummary(snapshots: []),
                monitoredProviders: AppPreferences.monitoredProviders
            )
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
            let reconciler = UsageRefreshReconciler()
            let reconciledSummary = reconciler.reconcile(current: result.summary, previous: previous)
            let refreshError = reconciler.warningMessage(
                original: result.error,
                current: result.summary,
                reconciled: reconciledSummary
            )
            self.summary = reconciledSummary
            self.workbench = result.workbench
            self.history.record(summary: reconciledSummary)
            try? self.historyStore.save(self.history)
            self.rebuildModel()
            self.refreshError = refreshError
            self.deliverAlerts(for: reconciledSummary, previous: previous)
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
        localSourceCancellable = Timer.publish(every: 60, tolerance: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isLocalSourceScanInFlight else { return }
                self.isLocalSourceScanInFlight = true
                Task { [weak self] in
                    let fingerprint = await Task.detached(priority: .utility) {
                        LocalAgentSourceMonitor().fingerprint()
                    }.value
                    await MainActor.run {
                        guard let self else { return }
                        self.isLocalSourceScanInFlight = false
                        guard fingerprint != self.lastLocalSourceFingerprint else { return }
                        self.lastLocalSourceFingerprint = fingerprint
                        guard Date().timeIntervalSince(self.lastRefreshAt) >= self.minimumLocalChangeRefreshInterval else { return }
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

    func openQuickRoute(_ route: AgentQuickRoute) {
        NSWorkspace.shared.open(URL(fileURLWithPath: route.path))
    }

    func copyQuickRoute(_ route: AgentQuickRoute) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(route.path, forType: .string)
    }

    func revealSession(_ session: AgentSessionSummary) {
        guard let transcriptPath = session.transcriptPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
    }

    func openServer(_ server: LocalDevServer) {
        guard let url = URL(string: server.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func stopServer(_ server: LocalDevServer) {
        guard server.processID > 1 else { return }
        kill(pid_t(server.processID), SIGTERM)
        workbench = AgentWorkbenchCollector().collect()
    }

    func historyDashboard() -> UsageHistoryDashboard {
        let monitoredProviders = AppPreferences.monitoredProviders
        let visibleSummary = UsageSummary(snapshots: (summary?.snapshots ?? []).filter { monitoredProviders.contains($0.provider) })
        let visibleHistory = UsageHistorySeries(
            maxSamples: history.maxSamples,
            retention: history.retention,
            samplesBySnapshotID: history.samplesBySnapshotID.filter { snapshotID, _ in
                monitoredProviders.contains(where: { provider in
                    snapshotID == provider.rawValue || snapshotID.hasPrefix("\(provider.rawValue)-")
                })
            }
        )
        return UsageHistoryDashboard(history: visibleHistory, summary: visibleSummary)
    }

    private func rebuildModel() {
        let monitoredProviders = AppPreferences.monitoredProviders
        let currentSummary = UsageSummary(snapshots: (summary?.snapshots ?? []).filter { monitoredProviders.contains($0.provider) })
        model = DashboardViewModel(
            summary: currentSummary,
            history: history.percentsBySnapshotID,
            historySamples: history.samplesBySnapshotID,
            monitoredProviders: monitoredProviders,
            menuBarProviderFocus: AppPreferences.menuBarProviderFocus,
            menuBarDisplayMode: AppPreferences.menuBarDisplayMode,
            preferredMenuBarSnapshotID: Self.preferredMenuBarSnapshotID(
                in: currentSummary,
                monitoredProviders: monitoredProviders
            )
        )
        writeStatusExport()
    }

    private static func preferredMenuBarSnapshotID(in summary: UsageSummary, monitoredProviders: Set<Provider>) -> String? {
        let visibleIDs = Set(summary.snapshots.filter { monitoredProviders.contains($0.provider) }.map(\.id))
        return AppPreferences.laneOrder().first { visibleIDs.contains($0) }
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

    private static func loadUsageOffMain() async -> (summary: UsageSummary, workbench: AgentWorkbenchSnapshot, error: String?) {
        await Task.detached(priority: .userInitiated) {
            let monitoredProviders = AppPreferences.monitoredProviders
            var snapshots: [UsageSnapshot] = []
            var warnings: [String] = []
            let workbench = AgentWorkbenchCollector().collect()

            do {
                let localSnapshots = try LocalUsageCollector(planPreferences: AppPreferences.localPlanPreferences()).collect()
                snapshots.append(contentsOf: localSnapshots.filter { monitoredProviders.contains($0.provider) })
            } catch {
                warnings.append("Local refresh failed")
            }

            if monitoredProviders.contains(.codex) {
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
            }

            if monitoredProviders.contains(.cursor) {
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
            }

            if monitoredProviders.contains(.openRouter),
               let openRouterKey = KeychainStore.readOpenRouterKey(), !openRouterKey.isEmpty {
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

            if monitoredProviders.contains(.openAI),
               let openAIAdminKey = KeychainStore.readOpenAIAdminKey(), !openAIAdminKey.isEmpty {
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
            return (summary, workbench, warnings.isEmpty ? nil : warnings.joined(separator: " · "))
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

struct DashboardActions {
    let refresh: () -> Void
    let settings: () -> Void
    let history: () -> Void
    let copyStatus: () -> Void
    let copyDiagnostics: () -> Void
    let openQuickRoute: (AgentQuickRoute) -> Void
    let copyQuickRoute: (AgentQuickRoute) -> Void
    let revealSession: (AgentSessionSummary) -> Void
    let openServer: (LocalDevServer) -> Void
    let stopServer: (LocalDevServer) -> Void
    let copyRow: (DashboardRow) -> Void
    let openRow: (DashboardRow) -> Void
    let quit: () -> Void
}

enum LaneFilter: Hashable {
    case usable
    case all
}

struct WorkbenchSection: View {
    let snapshot: AgentWorkbenchSnapshot
    let openQuickRoute: (AgentQuickRoute) -> Void
    let copyQuickRoute: (AgentQuickRoute) -> Void
    let revealSession: (AgentSessionSummary) -> Void
    let openServer: (LocalDevServer) -> Void
    let stopServer: (LocalDevServer) -> Void

    @State private var isExpanded: Bool = false

    private var existingRoutes: [AgentQuickRoute] {
        snapshot.routes.filter(\.exists)
    }

    var body: some View {
        if !snapshot.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header — tappable collapse toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FuelTheme.text2)
                        Text("Workbench")
                            .font(.fuelText(13, weight: .semibold))
                            .foregroundStyle(FuelTheme.text)
                        Text(summaryLabel)
                            .font(.fuelText(11.5))
                            .foregroundStyle(FuelTheme.text3)
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FuelTheme.text3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    // Divider
                    Rectangle()
                        .fill(FuelTheme.divider)
                        .frame(height: 1)
                        .padding(.horizontal, 12)

                    // Two-column grid: SESSIONS | DEV SERVERS (routes nested)
                    HStack(alignment: .top, spacing: 14) {
                        if !snapshot.sessions.isEmpty {
                            workbenchGroup(title: "SESSIONS") {
                                ForEach(snapshot.sessions.prefix(3)) { session in
                                    WorkbenchSessionRow(session: session, reveal: { revealSession(session) })
                                }
                            }
                        }

                        if !snapshot.devServers.isEmpty || !existingRoutes.isEmpty {
                            workbenchGroup(title: "DEV SERVERS") {
                                ForEach(snapshot.devServers.prefix(3)) { server in
                                    WorkbenchServerRow(
                                        server: server,
                                        open: { openServer(server) },
                                        stop: { stopServer(server) }
                                    )
                                }
                                if !existingRoutes.isEmpty {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("ROUTES")
                                            .font(.fuelEyebrow)
                                            .foregroundStyle(FuelTheme.text3)
                                            .padding(.top, snapshot.devServers.isEmpty ? 0 : 6)
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 4)], alignment: .leading, spacing: 4) {
                                            ForEach(existingRoutes.prefix(6)) { route in
                                                WorkbenchRouteButton(
                                                    route: route,
                                                    open: { openQuickRoute(route) },
                                                    copy: { copyQuickRoute(route) }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
            }
            .background(FuelTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous)
                    .strokeBorder(FuelTheme.border, lineWidth: 1)
            )
        }
    }

    private var summaryLabel: String {
        let parts = [
            snapshot.sessions.isEmpty ? nil : "\(snapshot.sessions.count) sessions",
            snapshot.devServers.isEmpty ? nil : "\(snapshot.devServers.count) servers",
            existingRoutes.isEmpty ? nil : "\(existingRoutes.count) routes"
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private func workbenchGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.fuelEyebrow)
                .foregroundStyle(FuelTheme.text3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WorkbenchSessionRow: View {
    let session: AgentSessionSummary
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 7) {
                providerBadge(session.provider.shortName)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(.fuelText(11.5, weight: .semibold))
                        .foregroundStyle(FuelTheme.text)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(session.status)
                            .foregroundStyle(session.status.lowercased() == "active" ? FuelTheme.safe : FuelTheme.text3)
                        Text("· \(session.detail)")
                            .foregroundStyle(FuelTheme.text3)
                    }
                    .font(.fuelText(10))
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reveal session log")
    }

    private func providerBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(FuelTheme.text2)
            .frame(width: 26, height: 17)
            .background(FuelTheme.track, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct WorkbenchServerRow: View {
    let server: LocalDevServer
    let open: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Text(":\(server.port)")
                        .font(.fuelMono(11.5))
                        .foregroundStyle(FuelTheme.accent)
                    Text(server.command)
                        .font(.fuelText(11))
                        .foregroundStyle(FuelTheme.text2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(server.url)")

            Button(action: open) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FuelTheme.text3)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Open \(server.url)")

            Button(action: stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FuelTheme.text3)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Stop process \(server.processID)")
        }
        .padding(.vertical, 4)
    }
}

private struct WorkbenchRouteButton: View {
    let route: AgentQuickRoute
    let open: () -> Void
    let copy: () -> Void

    var body: some View {
        Menu {
            Button("Open", action: open)
            Button("Copy path", action: copy)
        } label: {
            Text(route.title)
                .font(.fuelText(10.5, weight: .medium))
                .foregroundStyle(FuelTheme.text2)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(FuelTheme.track, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help(route.path)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboard.title)
                        .font(.fuelText(18, weight: .bold))
                        .foregroundStyle(FuelTheme.text)
                    Text(dashboard.subtitle)
                        .font(.fuelText(11))
                        .foregroundStyle(FuelTheme.text2)
                    Text(copyMessage)
                        .font(.fuelText(9))
                        .foregroundStyle(FuelTheme.text3)
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
                        .font(.fuelText(13, weight: .semibold))
                        .foregroundStyle(FuelTheme.text)
                    Text("History appears after a few refreshes from sources with known limits. It stores lane IDs, timestamps, and percentages only.")
                        .font(.fuelText(11))
                        .foregroundStyle(FuelTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fuelCard(radius: FuelTheme.radiusMD, padding: 14)
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
        .background(FuelTheme.surface)
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
                    .fill(FuelTheme.color(for: item.state))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.fuelText(13, weight: .semibold))
                        .foregroundStyle(FuelTheme.text)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.fuelText(10))
                        .foregroundStyle(FuelTheme.text3)
                }
                Spacer()
                Text(item.latestValue)
                    .font(.fuelMono(22, weight: .semibold))
                    .foregroundStyle(FuelTheme.color(for: item.state))
            }

            Sparkline(points: item.samples, state: item.state)
                .frame(height: 34)
                .accessibilityLabel("\(item.title) history trend")

            Divider()
                .background(FuelTheme.divider)

            HStack(spacing: 8) {
                HistoryMetricPill(label: "peak", value: item.peakValue, state: item.state)
                HistoryMetricPill(label: "delta", value: item.deltaValue, state: item.state)
                Spacer()
            }
        }
        .fuelCard(radius: FuelTheme.radiusMD, padding: 12)
    }
}

private struct HistoryMetricPill: View {
    let label: String
    let value: String
    let state: UsageState

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.fuelMono(10))
                .foregroundStyle(FuelTheme.color(for: state))
            Text(label)
                .font(.fuelEyebrow)
                .foregroundStyle(FuelTheme.text3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FuelTheme.surfaceSunken, in: Capsule())
        .overlay(Capsule().strokeBorder(FuelTheme.border.opacity(0.5)))
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

enum LaunchAgentManager {
    private static let label = "com.ozansozuoz.aifuelgauge"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var executableURL: URL? {
        Bundle.main.executableURL
    }

    static func enable() throws {
        guard let executableURL else {
            throw LaunchAgentError.missingExecutable
        }
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executableURL.path)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          <key>StandardOutPath</key>
          <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/aifuelgauge.log</string>
          <key>StandardErrorPath</key>
          <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/aifuelgauge.log</string>
        </dict>
        </plist>
        """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        _ = runLaunchctl(arguments: ["enable", "gui/\(getuid())/\(label)"])
    }

    static func disable() throws {
        _ = runLaunchctl(arguments: ["disable", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func statusMessage() -> String {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return "Start at login is off. Enable it to recreate the LaunchAgent."
        }
        let executablePath = executableURL?.path ?? "unknown executable"
        return "Start at login is on. LaunchAgent: \(plistURL.path). Current executable: \(executablePath)."
    }

    @discardableResult
    private static func runLaunchctl(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private enum ClaudeStatusLineInstaller {
    private static let commandPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/aifuelgauge-statusline.py")
    private static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    static func statusMessage() -> String {
        guard FileManager.default.fileExists(atPath: commandPath.path) else {
            return "Claude exact usage not enabled."
        }
        guard FileManager.default.fileExists(atPath: AppStoragePaths.claudeStatusLineURL.path) else {
            return "Claude exact enabled; waiting for the next Claude Code response."
        }
        return "Claude exact usage capture is enabled."
    }

    static func install(outputURL: URL) throws -> String {
        try FileManager.default.createDirectory(at: commandPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var settings = try readSettings()
        let previousCommand = previousStatusLineCommand(from: settings)
        let script = scriptContents(outputURL: outputURL, previousCommand: previousCommand)
        try script.write(to: commandPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandPath.path)

        settings["statusLine"] = [
            "type": "command",
            "command": commandPath.path,
            "refreshInterval": 30
        ]
        try writeSettings(settings)

        if previousCommand == nil {
            return "Claude exact enabled; continue Claude Code once to capture rate limits."
        }
        return "Claude exact enabled and chained to your existing Claude statusline."
    }

    private static func previousStatusLineCommand(from settings: [String: Any]) -> String? {
        guard let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command != commandPath.path else {
            return nil
        }
        return command
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: [.atomic])
    }

    private static func scriptContents(outputURL: URL, previousCommand: String?) -> String {
        let previousJSON = previousCommand.map { jsonStringLiteral($0) } ?? "None"
        let outputJSON = jsonStringLiteral(outputURL.path)
        return """
        #!/usr/bin/env python3
        import json
        import os
        import subprocess
        import sys
        import time

        OUTPUT_PATH = \(outputJSON)
        PREVIOUS_COMMAND = \(previousJSON)

        raw = sys.stdin.read()
        try:
            payload = json.loads(raw) if raw.strip() else {}
        except Exception:
            payload = {}

        rate_limits = payload.get("rate_limits") or {}
        capture = {
            "updated_at": time.time(),
            "session_id": payload.get("session_id"),
            "model": payload.get("model"),
            "rate_limits": {
                "five_hour": rate_limits.get("five_hour"),
                "seven_day": rate_limits.get("seven_day"),
            },
        }

        try:
            os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
            tmp_path = f"{OUTPUT_PATH}.tmp.{os.getpid()}"
            with open(tmp_path, "w", encoding="utf-8") as handle:
                json.dump(capture, handle, separators=(",", ":"))
            os.replace(tmp_path, OUTPUT_PATH)
        except Exception:
            pass

        if PREVIOUS_COMMAND:
            try:
                result = subprocess.run(
                    PREVIOUS_COMMAND,
                    input=raw,
                    text=True,
                    shell=True,
                    capture_output=True,
                    timeout=2,
                )
                output = (result.stdout or "").rstrip("\\n")
                if output:
                    print(output)
                    sys.exit(0)
            except Exception:
                pass

        five = (rate_limits.get("five_hour") or {}).get("used_percentage")
        seven = (rate_limits.get("seven_day") or {}).get("used_percentage")
        parts = []
        if isinstance(five, (int, float)):
            parts.append(f"5h {five:.0f}%")
        if isinstance(seven, (int, float)):
            parts.append(f"7d {seven:.0f}%")
        print("Claude " + " · ".join(parts) if parts else "Claude")
        """
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data(#"[""]"#.utf8)
        let json = String(data: data, encoding: .utf8) ?? #"[""]"#
        return String(json.dropFirst().dropLast())
    }
}

private enum LaunchAgentError: LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable: "Current app executable could not be found."
        }
    }
}

enum KeychainStore {
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
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
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

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
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
