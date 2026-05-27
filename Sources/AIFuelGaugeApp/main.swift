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
    private var modelCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationBridge.requestAuthorization()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = controller.model.title
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        self.statusItem = statusItem

        modelCancellable = controller.$model.sink { [weak self] model in
            self?.statusItem?.button?.title = model.title
        }

        popover.behavior = .semitransient
        popover.contentSize = NSSize(width: 460, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                controller: controller,
                actions: DashboardActions(
                    refresh: { [weak controller] in controller?.refresh() },
                    settings: { [weak self] in self?.settingsWindowController.show() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        )
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

@MainActor
private final class DashboardController: ObservableObject {
    @Published private(set) var model: DashboardViewModel
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshCancellable: AnyCancellable?
    private var summary: UsageSummary?
    private var notifiedStaleIDs = Set<String>()
    private let alertPlanner = UsageAlertPlanner()

    init() {
        self.model = DashboardViewModel(summary: UsageSummary(snapshots: []))
        startAutoRefresh()
        refresh()
    }


    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let result = await Self.loadUsageOffMain()
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let previous = self.summary
            self.summary = result.summary
            self.model = DashboardViewModel(summary: result.summary)
            self.refreshError = result.error
            self.deliverAlerts(for: result.summary, previous: previous)
            self.isRefreshing = false
        }
    }

    private func startAutoRefresh() {
        autoRefreshCancellable = Timer.publish(every: 180, tolerance: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    private func deliverAlerts(for current: UsageSummary, previous: UsageSummary?) {
        let crossingAlerts = alertPlanner.alerts(previous: previous, current: current)
        let staleAlerts = alertPlanner.staleAlerts(summary: current, now: Date(), maxAge: 600)
            .filter { notifiedStaleIDs.insert($0.identifier).inserted }
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
                snapshots.append(contentsOf: try LocalUsageCollector().collect())
            } catch {
                warnings.append("Local refresh failed")
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
            if let gauge = model.primaryGauge {
                PrimaryGaugeView(gauge: gauge)
            } else {
                UnknownGaugeView()
            }
            if model.rows.isEmpty {
                EmptySourcesView()
            } else {
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
                .frame(maxHeight: 230)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            footer
        }
        .padding(16)
        .frame(width: 460, height: 500)
        .background(.regularMaterial)
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
            FooterButton(title: "Refresh", action: actions.refresh)
            FooterButton(title: "Settings", action: actions.settings)
            FooterButton(title: "Quit", action: actions.quit)
        }
        .padding(.top, 1)
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
        .background(color(for: state).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color(for: state).opacity(0.20), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch state {
        case .safe: "bolt.fill"
        case .caution: "speedometer"
        case .critical, .exhausted: "exclamationmark.triangle.fill"
        case .unknown: "sparkles"
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
        }
        .padding(12)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
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
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 230),
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
    @State private var message: String = "Stored in macOS Keychain. Not synced."

    init() {
        _openRouterKey = State(initialValue: KeychainStore.readOpenRouterKey() ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider keys")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("OpenRouter is first because it exposes official credit/key metadata cleanly.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenRouter API key")
                    .font(.system(size: 11, weight: .semibold))
                SecureField("sk-or-v1-...", text: $openRouterKey)
                    .textFieldStyle(.roundedBorder)
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Delete key") {
                    KeychainStore.deleteOpenRouterKey()
                    openRouterKey = ""
                    message = "OpenRouter key deleted."
                }
                Spacer()
                Button("Save key") {
                    do {
                        try KeychainStore.saveOpenRouterKey(openRouterKey)
                        message = "OpenRouter key saved. Refresh will use it for live API polling."
                    } catch {
                        message = "Could not save key: \(error.localizedDescription)"
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440, height: 230)
    }
}

private enum KeychainStore {
    private static let service = "AI Fuel Gauge"
    private static let openRouterAccount = "openrouter-api-key"

    static func readOpenRouterKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openRouterAccount,
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

    static func saveOpenRouterKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteOpenRouterKey()
            return
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openRouterAccount
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

    static func deleteOpenRouterKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openRouterAccount
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
