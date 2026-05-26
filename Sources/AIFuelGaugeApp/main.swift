import AppKit
import Combine
import Security
import SwiftUI
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

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = controller.model.title
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        self.statusItem = statusItem

        modelCancellable = controller.$model.sink { [weak self] model in
            self?.statusItem?.button?.title = model.title
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 300)
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
            controller.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
private final class DashboardController: ObservableObject {
    @Published private(set) var model: DashboardViewModel

    init() {
        self.model = Self.loadModel()
    }

    func refresh() {
        model = Self.loadModel()
    }

    private static func loadModel() -> DashboardViewModel {
        let localSnapshots = (try? LocalUsageCollector().collect()) ?? []
        let summary = UsageSummary(snapshots: localSnapshots.isEmpty ? DemoData.summary().snapshots : localSnapshots)
        return DashboardViewModel(summary: summary)
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
            Divider().opacity(0.65)
            if let gauge = model.primaryGauge {
                PrimaryGaugeView(gauge: gauge)
            } else {
                UnknownGaugeView()
            }
            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    SourceRowView(row: row)
                    if row.id != model.rows.last?.id {
                        Divider().padding(.leading, 20).opacity(0.45)
                    }
                }
            }
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            footer
        }
        .padding(16)
        .frame(width: 360, height: 300)
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

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.footerNote)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            FooterButton(title: "Refresh", action: actions.refresh)
            FooterButton(title: "Settings", action: actions.settings)
            FooterButton(title: "Quit", action: actions.quit)
        }
        .padding(.top, 1)
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

private struct SourceRowView: View {
    let row: DashboardRow

    var body: some View {
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
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(row.state == .unknown ? .secondary : .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
                        message = "OpenRouter key saved. Refresh to use it when API polling is wired."
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
