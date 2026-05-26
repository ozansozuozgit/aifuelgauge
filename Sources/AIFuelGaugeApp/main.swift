import AppKit
import SwiftUI
import AIFuelGaugeCore

@MainActor
final class AIFuelGaugeAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = DashboardViewModel(summary: DemoData.summary())
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = model.title
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 240)
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private struct DashboardView: View {
    let model: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Fuel Gauge")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(model.title)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatePill(state: model.state)
            }

            Divider()

            VStack(spacing: 10) {
                ForEach(model.rows) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: row.state))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .medium))
                            Text(row.detail)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Local-first prototype. OpenRouter + local Claude/Codex/OpenCode scaffolding next.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 320, height: 240)
    }

    private func color(for state: UsageState) -> Color {
        switch state {
        case .safe: .green
        case .caution: .yellow
        case .critical, .exhausted: .red
        case .unknown: .gray
        }
    }
}

private struct StatePill: View {
    let state: UsageState

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }

    private var label: String {
        switch state {
        case .safe: "safe"
        case .caution: "watch"
        case .critical: "near limit"
        case .exhausted: "blocked"
        case .unknown: "learning"
        }
    }
}

private enum DemoData {
    static func summary() -> UsageSummary {
        let localSnapshots = (try? LocalUsageCollector().collect()) ?? []
        if !localSnapshots.isEmpty {
            return UsageSummary(snapshots: localSnapshots)
        }
        return UsageSummary(snapshots: [
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
