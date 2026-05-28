import Foundation

public struct DashboardGauge: Equatable, Sendable {
    public let title: String
    public let value: String
    public let subtitle: String
    public let caption: String
    public let explanation: String
    public let percent: Double
    public let state: UsageState
    public let confidence: Confidence
    public let paceCaption: String?
    public let dashboardURL: String?
    public let receiptText: String

    public init(
        title: String,
        value: String,
        subtitle: String,
        caption: String,
        explanation: String = "",
        percent: Double,
        state: UsageState,
        confidence: Confidence,
        paceCaption: String? = nil,
        dashboardURL: String? = nil,
        receiptText: String = ""
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.caption = caption
        self.explanation = explanation
        self.percent = percent
        self.state = state
        self.confidence = confidence
        self.paceCaption = paceCaption
        self.dashboardURL = dashboardURL
        self.receiptText = receiptText
    }
}

public struct UsageHistorySample: Codable, Equatable, Sendable {
    public let recordedAt: Date
    public let percent: Double

    public init(recordedAt: Date, percent: Double) {
        self.recordedAt = recordedAt
        self.percent = min(max(percent, 0), 1)
    }
}

public struct UsageHistorySeries: Codable, Equatable, Sendable {
    public let maxSamples: Int
    public let retention: TimeInterval
    public private(set) var samplesBySnapshotID: [String: [UsageHistorySample]]

    public init(
        maxSamples: Int = 24,
        retention: TimeInterval = 7 * 24 * 3600,
        samplesBySnapshotID: [String: [UsageHistorySample]] = [:]
    ) {
        self.maxSamples = max(2, maxSamples)
        self.retention = max(1, retention)
        self.samplesBySnapshotID = samplesBySnapshotID.mapValues { samples in
            Array(samples.sorted { $0.recordedAt < $1.recordedAt }.suffix(max(2, maxSamples)))
        }
    }

    public init(maxSamples: Int = 24, retention: TimeInterval = 7 * 24 * 3600, legacyPercentsBySnapshotID: [String: [Double]], now: Date = Date()) {
        let migrated = legacyPercentsBySnapshotID.mapValues { percents in
            percents.suffix(max(2, maxSamples)).enumerated().map { index, percent in
                UsageHistorySample(recordedAt: now.addingTimeInterval(TimeInterval(index - percents.count)), percent: percent)
            }
        }
        self.init(maxSamples: maxSamples, retention: retention, samplesBySnapshotID: migrated)
    }

    public var percentsBySnapshotID: [String: [Double]] {
        samplesBySnapshotID.mapValues { samples in
            samples.map(\.percent)
        }
    }

    public mutating func record(summary: UsageSummary, now: Date = Date()) {
        let currentIDs = Set(summary.snapshots.map(\.id))
        samplesBySnapshotID = samplesBySnapshotID.filter { currentIDs.contains($0.key) }
        for snapshot in summary.snapshots {
            guard let usagePercent = snapshot.usagePercent, usagePercent.isFinite else { continue }
            var samples = samplesBySnapshotID[snapshot.id] ?? []
            samples.append(UsageHistorySample(recordedAt: now, percent: usagePercent))
            let cutoff = now.addingTimeInterval(-retention)
            samplesBySnapshotID[snapshot.id] = Array(samples
                .filter { $0.recordedAt >= cutoff }
                .sorted { $0.recordedAt < $1.recordedAt }
                .suffix(maxSamples))
        }
    }

    enum CodingKeys: String, CodingKey {
        case maxSamples
        case retention
        case samplesBySnapshotID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let maxSamples = try container.decodeIfPresent(Int.self, forKey: .maxSamples) ?? 24
        let retention = try container.decodeIfPresent(TimeInterval.self, forKey: .retention) ?? 7 * 24 * 3600
        if let samples = try? container.decode([String: [UsageHistorySample]].self, forKey: .samplesBySnapshotID) {
            self.init(maxSamples: maxSamples, retention: retention, samplesBySnapshotID: samples)
            return
        }
        let legacy = try container.decodeIfPresent([String: [Double]].self, forKey: .samplesBySnapshotID) ?? [:]
        self.init(maxSamples: maxSamples, retention: retention, legacyPercentsBySnapshotID: legacy)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxSamples, forKey: .maxSamples)
        try container.encode(retention, forKey: .retention)
        try container.encode(samplesBySnapshotID, forKey: .samplesBySnapshotID)
    }
}

public struct UsageHistoryFileStore {
    private let fileURL: URL
    private let maxSamples: Int
    private let retention: TimeInterval
    private let fileManager: FileManager

    public init(fileURL: URL, maxSamples: Int = 256, retention: TimeInterval = 7 * 24 * 3600, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.maxSamples = max(2, maxSamples)
        self.retention = max(1, retention)
        self.fileManager = fileManager
    }

    public func load() -> UsageHistorySeries {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(UsageHistorySeries.self, from: data) else {
            return UsageHistorySeries(maxSamples: maxSamples, retention: retention)
        }
        return UsageHistorySeries(maxSamples: maxSamples, retention: retention, samplesBySnapshotID: decoded.samplesBySnapshotID)
    }

    public func save(_ history: UsageHistorySeries) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let normalized = UsageHistorySeries(maxSamples: maxSamples, retention: retention, samplesBySnapshotID: history.samplesBySnapshotID)
        let data = try encoder.encode(normalized)
        try data.write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

public struct UsageHistoryDashboardItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let latestValue: String
    public let peakValue: String
    public let deltaValue: String
    public let samples: [Double]
    public let state: UsageState

    public init(
        id: String,
        title: String,
        detail: String,
        latestValue: String,
        peakValue: String,
        deltaValue: String,
        samples: [Double],
        state: UsageState
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.latestValue = latestValue
        self.peakValue = peakValue
        self.deltaValue = deltaValue
        self.samples = samples
        self.state = state
    }
}

public struct UsageHistoryDashboard: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let csvText: String
    public let items: [UsageHistoryDashboardItem]

    public init(history: UsageHistorySeries, summary: UsageSummary, now: Date = Date()) {
        let currentSnapshotsByID = Dictionary(uniqueKeysWithValues: summary.snapshots.map { ($0.id, $0) })
        self.title = "Usage history"
        self.csvText = Self.csvText(for: history, currentSnapshotsByID: currentSnapshotsByID)
        self.items = history.samplesBySnapshotID
            .compactMap { snapshotID, samples -> UsageHistoryDashboardItem? in
                let sorted = samples.sorted { $0.recordedAt < $1.recordedAt }
                guard let latest = sorted.last else { return nil }
                let percents = sorted.map(\.percent)
                let firstPercent = percents.first ?? latest.percent
                let deltaPoints = Int(((latest.percent - firstPercent) * 100).rounded())
                let delta: String
                if abs(deltaPoints) < 1 {
                    delta = "steady"
                } else if deltaPoints > 0 {
                    delta = "+\(deltaPoints) pts"
                } else {
                    delta = "-\(abs(deltaPoints)) pts"
                }
                let title = currentSnapshotsByID[snapshotID].map(Self.titleForSnapshot) ?? Self.titleForUnknownSnapshotID(snapshotID)
                let sampleWord = sorted.count == 1 ? "sample" : "samples"
                return UsageHistoryDashboardItem(
                    id: snapshotID,
                    title: title,
                    detail: "\(sorted.count) \(sampleWord) · latest \(Self.relativeTime(from: latest.recordedAt, now: now))",
                    latestValue: "\(Self.percent(latest.percent))%",
                    peakValue: "peak \(Self.percent(percents.max() ?? latest.percent))%",
                    deltaValue: delta,
                    samples: percents,
                    state: Self.state(for: latest.percent)
                )
            }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state > rhs.state }
                return lhs.title < rhs.title
            }
        self.subtitle = items.isEmpty
            ? "No comparable usage samples yet"
            : "\(items.count) lane\(items.count == 1 ? "" : "s") · local 7-day file"
    }

    private static func csvText(for history: UsageHistorySeries, currentSnapshotsByID: [String: UsageSnapshot]) -> String {
        let rows = history.samplesBySnapshotID.flatMap { snapshotID, samples -> [(String, String, UsageHistorySample)] in
            let title = currentSnapshotsByID[snapshotID].map(titleForSnapshot) ?? titleForUnknownSnapshotID(snapshotID)
            return samples.sorted { $0.recordedAt < $1.recordedAt }.map { sample in
                (snapshotID, title, sample)
            }
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2.recordedAt != rhs.2.recordedAt { return lhs.2.recordedAt < rhs.2.recordedAt }
            return lhs.0 < rhs.0
        }

        var lines = ["snapshot_id,title,recorded_at,usage_percent"]
        lines.append(contentsOf: rows.map { snapshotID, title, sample in
            [
                csvCell(snapshotID),
                csvCell(title),
                csvCell(iso8601(sample.recordedAt)),
                csvCell(String(percent(sample.percent)))
            ].joined(separator: ",")
        })
        return lines.joined(separator: "\n")
    }

    private static func csvCell(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func titleForSnapshot(_ snapshot: UsageSnapshot) -> String {
        let label = snapshot.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account = snapshot.account {
            let accountName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let plan = account.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
            if accountName.caseInsensitiveCompare(snapshot.provider.displayName) == .orderedSame,
               let plan,
               !plan.isEmpty {
                if label.isEmpty || label == snapshot.provider.displayName || label == accountName {
                    return "\(snapshot.provider.displayName) · \(plan)"
                }
                return "\(snapshot.provider.displayName) · \(plan) · \(label)"
            }
        }
        guard !label.isEmpty, label != snapshot.provider.displayName else {
            return snapshot.provider.displayName
        }
        if label.localizedCaseInsensitiveContains(snapshot.provider.displayName) {
            return label
        }
        return "\(snapshot.provider.displayName) · \(label)"
    }

    private static func titleForUnknownSnapshotID(_ snapshotID: String) -> String {
        snapshotID
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
            .joined(separator: " ")
    }

    private static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }

    private static func state(for percent: Double) -> UsageState {
        if percent >= 1 { return .exhausted }
        if percent >= 0.9 { return .critical }
        if percent >= 0.75 { return .caution }
        return .safe
    }

    private static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "now" }
        let minutes = max(1, seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = max(1, minutes / 60)
        if hours < 24 { return "\(hours)h ago" }
        let days = max(1, hours / 24)
        return "\(days)d ago"
    }
}

public enum DashboardDiagnosticsReport {
    public static func make(
        summary: UsageSummary,
        history: UsageHistorySeries,
        historyPath: String,
        refreshError: String?,
        generatedAt: Date = Date()
    ) -> String {
        var lines: [String] = [
            "AI Fuel Gauge Diagnostics",
            "Generated: \(iso8601(generatedAt))",
            "Overall state: \(summary.overallState.rawValue)",
            "Menu bar title: \(summary.menuBarTitle)",
            "History path: \(historyPath)",
            "History lanes: \(history.samplesBySnapshotID.count)",
            "Refresh warning: \(refreshError?.isEmpty == false ? refreshError! : "none")",
            "",
            "Sources:"
        ]

        if summary.snapshots.isEmpty {
            lines.append("- none")
        } else {
            for snapshot in summary.snapshots.sorted(by: diagnosticOrder) {
                let percent = snapshot.usagePercent.map { "\(Int(($0 * 100).rounded()))% used" } ?? "not comparable"
                let account = snapshot.account?.displayTitle ?? snapshot.provider.displayName
                let reset = snapshot.reset?.compactTitle.map { "reset \($0)" } ?? "no reset"
                lines.append("- \(snapshot.provider.displayName) / \(account) / \(snapshot.label): \(percent), \(snapshot.state.rawValue), \(snapshot.confidence.rawValue), \(snapshot.source.rawValue), \(reset), updated \(iso8601(snapshot.updatedAt))")
            }
        }

        lines.append("")
        lines.append("History samples:")
        if history.samplesBySnapshotID.isEmpty {
            lines.append("- none")
        } else {
            for key in history.samplesBySnapshotID.keys.sorted() {
                let samples = history.samplesBySnapshotID[key] ?? []
                let latest = samples.last.map { "\(Int(($0.percent * 100).rounded()))% at \(iso8601($0.recordedAt))" } ?? "none"
                lines.append("- \(key): \(samples.count) samples, latest \(latest)")
            }
        }

        lines.append("")
        lines.append("Privacy: diagnostics include source names, status, timestamps, and percentages only. They do not include prompts, API keys, auth tokens, or raw provider responses.")
        return lines.joined(separator: "\n")
    }

    private static func diagnosticOrder(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) -> Bool {
        if lhs.provider.displayName != rhs.provider.displayName {
            return lhs.provider.displayName < rhs.provider.displayName
        }
        return lhs.label < rhs.label
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public enum DashboardStatusSnapshot {
    public static func make(model: DashboardViewModel, generatedAt: Date = Date()) -> String {
        var lines: [String] = [
            "AI Fuel Gauge Status",
            "Generated: \(iso8601(generatedAt))",
            "Menu: \(model.title)",
            "State: \(model.statusLabel)",
            "Insight: \(model.insight)",
            "Sources: \(model.footerNote) · \(model.trustDigest)"
        ]

        if let gauge = model.primaryGauge {
            let pace = gauge.paceCaption.map { " · \($0)" } ?? ""
            lines.append("Primary: \(gauge.title) · \(gauge.value) · \(gauge.subtitle)\(pace)")
            if !gauge.explanation.isEmpty {
                lines.append("Primary source: \(gauge.explanation)")
            }
        }

        if !model.guidanceItems.isEmpty {
            lines.append("")
            lines.append("Guidance:")
            for item in model.guidanceItems {
                let reason = item.reason.isEmpty ? "" : " · \(item.reason)"
                lines.append("- \(item.title): \(item.value) · \(item.detail)\(reason)")
            }
        }

        if !model.resetTimeline.isEmpty {
            lines.append("")
            lines.append("Next resets:")
            for item in model.resetTimeline {
                lines.append("- \(item.title): \(item.value) · \(item.detail)")
            }
        }

        if !model.rows.isEmpty {
            lines.append("")
            lines.append("Lanes:")
            for row in model.rows.prefix(6) {
                let meter = row.meterLabel.map { " · \($0)" } ?? ""
                let pace = row.paceCaption.map { " · \($0)" } ?? ""
                lines.append("- \(row.title): \(row.value) · \(row.detail)\(meter)\(pace)")
            }
        }

        if !model.setupGuidance.isEmpty {
            lines.append("")
            lines.append("Setup:")
            for item in model.setupGuidance {
                lines.append("- \(item.title): \(item.status) · \(item.action)")
            }
        }

        lines.append("")
        lines.append("Privacy: status includes source names, percentages, and timing only. It does not include prompts, API keys, auth tokens, or raw provider responses.")
        return lines.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct DashboardStatusExport: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let menuTitle: String
    public let statusLabel: String
    public let insight: String
    public let footerNote: String
    public let trustDigest: String
    public let primary: Primary?
    public let guidance: [Guidance]
    public let resets: [Reset]
    public let lanes: [Lane]
    public let setup: [Setup]

    public init(
        generatedAt: String,
        menuTitle: String,
        statusLabel: String,
        insight: String,
        footerNote: String,
        trustDigest: String,
        primary: Primary?,
        guidance: [Guidance],
        resets: [Reset],
        lanes: [Lane],
        setup: [Setup]
    ) {
        self.generatedAt = generatedAt
        self.menuTitle = menuTitle
        self.statusLabel = statusLabel
        self.insight = insight
        self.footerNote = footerNote
        self.trustDigest = trustDigest
        self.primary = primary
        self.guidance = guidance
        self.resets = resets
        self.lanes = lanes
        self.setup = setup
    }

    public static func make(model: DashboardViewModel, generatedAt: Date = Date()) -> DashboardStatusExport {
        DashboardStatusExport(
            generatedAt: iso8601(generatedAt),
            menuTitle: model.title,
            statusLabel: model.statusLabel,
            insight: model.insight,
            footerNote: model.footerNote,
            trustDigest: model.trustDigest,
            primary: model.primaryGauge.map { gauge in
                Primary(
                    title: gauge.title,
                    value: gauge.value,
                    subtitle: gauge.subtitle,
                    caption: gauge.caption,
                    explanation: gauge.explanation,
                    percent: gauge.percent,
                    state: gauge.state.rawValue,
                    confidence: gauge.confidence.rawValue,
                    pace: gauge.paceCaption,
                    dashboardURL: gauge.dashboardURL,
                    receipt: gauge.receiptText
                )
            },
            guidance: model.guidanceItems.map { item in
                Guidance(title: item.title, value: item.value, detail: item.detail, reason: item.reason, state: item.state.rawValue)
            },
            resets: model.resetTimeline.map { item in
                Reset(title: item.title, detail: item.detail, value: item.value, state: item.state.rawValue)
            },
            lanes: model.rows.prefix(8).map { row in
                Lane(
                    title: row.title,
                    value: row.value,
                    detail: row.detail,
                    dashboardURL: row.dashboardURL,
                    meterPercent: row.meterPercent,
                    meterLabel: row.meterLabel,
                    trend: row.trendPercents,
                    trendCaption: row.trendCaption,
                    pace: row.paceCaption,
                    receipt: row.receiptText,
                    explanation: row.explanation,
                    confidence: row.confidence.rawValue,
                    state: row.state.rawValue
                )
            },
            setup: model.setupGuidance.map { item in
                Setup(title: item.title, status: item.status, action: item.action, state: item.state.rawValue)
            }
        )
    }

    public static func jsonData(model: DashboardViewModel, generatedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(make(model: model, generatedAt: generatedAt))
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public struct Primary: Codable, Equatable, Sendable {
        public let title: String
        public let value: String
        public let subtitle: String
        public let caption: String
        public let explanation: String
        public let percent: Double
        public let state: String
        public let confidence: String
        public let pace: String?
        public let dashboardURL: String?
        public let receipt: String
    }

    public struct Reset: Codable, Equatable, Sendable {
        public let title: String
        public let detail: String
        public let value: String
        public let state: String
    }

    public struct Guidance: Codable, Equatable, Sendable {
        public let title: String
        public let value: String
        public let detail: String
        public let reason: String
        public let state: String
    }

    public struct Lane: Codable, Equatable, Sendable {
        public let title: String
        public let value: String
        public let detail: String
        public let dashboardURL: String?
        public let meterPercent: Double?
        public let meterLabel: String?
        public let trend: [Double]
        public let trendCaption: String?
        public let pace: String?
        public let receipt: String
        public let explanation: String
        public let confidence: String
        public let state: String
    }

    public struct Setup: Codable, Equatable, Sendable {
        public let title: String
        public let status: String
        public let action: String
        public let state: String
    }
}

public struct DashboardRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let detail: String
    public let dashboardURL: String?
    public let explanation: String
    public let meterPercent: Double?
    public let meterLabel: String?
    public let trendPercents: [Double]
    public let trendCaption: String?
    public let paceCaption: String?
    public let receiptText: String
    public let confidence: Confidence
    public let state: UsageState

    public init(
        id: String,
        title: String,
        value: String,
        detail: String,
        dashboardURL: String? = nil,
        explanation: String,
        meterPercent: Double?,
        meterLabel: String?,
        trendPercents: [Double] = [],
        trendCaption: String? = nil,
        paceCaption: String? = nil,
        receiptText: String = "",
        confidence: Confidence,
        state: UsageState
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
        self.dashboardURL = dashboardURL
        self.explanation = explanation
        self.meterPercent = meterPercent
        self.meterLabel = meterLabel
        self.trendPercents = trendPercents
        self.trendCaption = trendCaption
        self.paceCaption = paceCaption
        self.receiptText = receiptText
        self.confidence = confidence
        self.state = state
    }
}

public struct DashboardSourceHealthItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let state: UsageState

    public init(id: String, title: String, value: String, state: UsageState) {
        self.id = id
        self.title = title
        self.value = value
        self.state = state
    }
}

public struct DashboardResetItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let value: String
    public let state: UsageState

    public init(id: String, title: String, detail: String, value: String, state: UsageState) {
        self.id = id
        self.title = title
        self.detail = detail
        self.value = value
        self.state = state
    }
}

public struct DashboardSetupItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let action: String
    public let state: UsageState

    public init(id: String, title: String, status: String, action: String, state: UsageState) {
        self.id = id
        self.title = title
        self.status = status
        self.action = action
        self.state = state
    }
}

public struct DashboardGuidanceItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let detail: String
    public let reason: String
    public let state: UsageState

    public init(id: String, title: String, value: String, detail: String, reason: String = "", state: UsageState) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
        self.reason = reason
        self.state = state
    }
}

public struct DashboardViewModel: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let insight: String
    public let trustDigest: String
    public let statusLabel: String
    public let footerNote: String
    public let sourceHealth: [DashboardSourceHealthItem]
    public let guidanceItems: [DashboardGuidanceItem]
    public let setupGuidance: [DashboardSetupItem]
    public let resetTimeline: [DashboardResetItem]
    public let primaryGauge: DashboardGauge?
    public let rows: [DashboardRow]
    public let state: UsageState

    public init(
        summary: UsageSummary,
        now: Date = Date(),
        history: [String: [Double]] = [:],
        historySamples: [String: [UsageHistorySample]] = [:],
        monitoredProviders: Set<Provider> = Set(Provider.allCases),
        menuBarProviderFocus: MenuBarProviderFocus = .auto,
        menuBarDisplayMode: MenuBarDisplayMode = .detailed
    ) {
        let visibleSummary = UsageSummary(snapshots: summary.snapshots.filter { monitoredProviders.contains($0.provider) })
        self.title = visibleSummary.menuBarTitle(mode: menuBarDisplayMode, history: history, providerFocus: menuBarProviderFocus)
        let dashboardState = Self.dashboardState(for: visibleSummary)
        self.state = dashboardState
        self.statusLabel = Self.statusLabel(for: dashboardState)
        self.subtitle = Self.subtitle(for: visibleSummary, now: now)
        self.insight = Self.insight(for: visibleSummary, now: now)
        self.trustDigest = Self.trustDigest(for: visibleSummary)
        self.footerNote = Self.footerNote(for: visibleSummary)
        self.sourceHealth = Self.sourceHealth(for: visibleSummary, now: now)
        self.guidanceItems = Self.guidanceItems(for: visibleSummary, history: history, now: now)
        self.setupGuidance = Self.setupGuidance(for: visibleSummary, monitoredProviders: monitoredProviders)
        self.resetTimeline = Self.resetTimeline(for: visibleSummary, now: now)
        let featuredSnapshot = Self.featuredSnapshot(for: visibleSummary)
        self.primaryGauge = featuredSnapshot.flatMap { Self.gauge(for: $0, historySamples: historySamples, now: now) }
        let hiddenPrimaryID = featuredSnapshot.flatMap { Self.hidesPrimaryRow($0) ? $0.id : nil }
        self.rows = visibleSummary.snapshots
            .filter { $0.id != hiddenPrimaryID }
            .sorted(by: Self.prefersRowOrder)
            .map { snapshot in
                let title = Self.rowTitle(for: snapshot)
                let value = Self.value(for: snapshot)
                let detail = Self.detail(for: snapshot, now: now)
                let dashboardURL = Self.dashboardURL(for: snapshot)
                let trendCaption = Self.trendCaption(for: snapshot, history: history)
                let paceCaption = Self.paceCaption(for: snapshot, historySamples: historySamples, now: now)
                return DashboardRow(
                    id: snapshot.id,
                    title: title,
                    value: value,
                    detail: detail,
                    dashboardURL: dashboardURL,
                    explanation: Self.explanation(for: snapshot),
                    meterPercent: snapshot.usagePercent.map { min(max($0, 0), 1) },
                    meterLabel: Self.remainingLabel(for: snapshot),
                    trendPercents: Self.trendPercents(for: snapshot, history: history),
                    trendCaption: trendCaption,
                    paceCaption: paceCaption,
                    receiptText: Self.receiptText(
                        for: snapshot,
                        title: title,
                        value: value,
                        detail: detail,
                        dashboardURL: dashboardURL,
                        trendCaption: trendCaption,
                        paceCaption: paceCaption,
                        now: now
                    ),
                    confidence: snapshot.confidence,
                    state: snapshot.state
                )
            }
    }

    private static func dashboardState(for summary: UsageSummary) -> UsageState {
        let comparable = summary.snapshots.filter { $0.usagePercent?.isFinite == true && !$0.isSubscriptionOnly }
        guard comparable.contains(where: { $0.state == .exhausted }) else {
            return summary.overallState
        }
        if comparable.contains(where: { $0.state != .exhausted }) {
            return .critical
        }
        return .exhausted
    }

    private static func featuredSnapshot(for summary: UsageSummary) -> UsageSnapshot? {
        let comparable = summary.snapshots.filter { $0.usagePercent?.isFinite == true && !$0.isSubscriptionOnly }
        let usable = comparable
            .filter { $0.state != .exhausted }
            .sorted(by: prefersFeaturedOrder)
        if let first = usable.first {
            return first
        }
        return summary.primarySnapshot
    }

    private static func activeHistorySamples(for snapshot: UsageSnapshot, historySamples: [String: [UsageHistorySample]]) -> [UsageHistorySample] {
        guard snapshot.usagePercent != nil else { return [] }
        let sorted = (historySamples[snapshot.id] ?? [])
            .filter { $0.percent.isFinite }
            .sorted { $0.recordedAt < $1.recordedAt }
        guard sorted.count >= 2 else { return [] }
        var startIndex = sorted.startIndex
        for index in sorted.indices.dropFirst() {
            let previousIndex = sorted.index(before: index)
            if sorted[index].percent + 0.02 < sorted[previousIndex].percent {
                startIndex = index
            }
        }
        return Array(sorted[startIndex...])
    }

    private static func trendPercents(for snapshot: UsageSnapshot, history: [String: [Double]]) -> [Double] {
        guard snapshot.usagePercent != nil else { return [] }
        return (history[snapshot.id] ?? [])
            .filter(\.isFinite)
            .map { min(max($0, 0), 1) }
    }

    private static func trendCaption(for snapshot: UsageSnapshot, history: [String: [Double]]) -> String? {
        let samples = trendPercents(for: snapshot, history: history)
        guard samples.count >= 2 else { return nil }
        let peak = Int(((samples.max() ?? 0) * 100).rounded())
        let deltaPoints = Int(((samples.last! - samples.first!) * 100).rounded())
        let direction: String
        if abs(deltaPoints) < 1 {
            direction = "steady"
        } else if deltaPoints > 0 {
            direction = "up \(deltaPoints) pts"
        } else {
            direction = "down \(abs(deltaPoints)) pts"
        }
        if let spike = usageSpike(for: snapshot, history: history) {
            return "Spike +\(spike.points) pts recently · 7d peak \(peak)% · \(direction)"
        }
        return "7d peak \(peak)% · \(direction)"
    }

    private static func paceCaption(for snapshot: UsageSnapshot, historySamples: [String: [UsageHistorySample]], now: Date) -> String? {
        guard let currentPercent = snapshot.usagePercent,
              currentPercent.isFinite,
              let reset = snapshot.reset,
              snapshot.confidence == .exact,
              !snapshot.isSubscriptionOnly else {
            return nil
        }
        let samples = activeHistorySamples(for: snapshot, historySamples: historySamples)
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else { return nil }
        let elapsed = last.recordedAt.timeIntervalSince(first.recordedAt)
        guard elapsed >= 5 * 60 else { return nil }
        let delta = last.percent - first.percent
        if currentPercent >= 1 {
            return "Pace: already at limit; wait for reset."
        }
        guard delta > 0.01 else {
            return "Pace: steady; projected to last past reset."
        }
        let ratePerSecond = delta / elapsed
        guard ratePerSecond > 0 else { return nil }
        let secondsToLimit = (1 - currentPercent) / ratePerSecond
        let resetSeconds = secondsRemaining(for: reset, now: now)
        guard resetSeconds > 0 else { return nil }
        if secondsToLimit < resetSeconds {
            let gap = resetSeconds - secondsToLimit
            return "Pace warning: limit in \(durationLabel(seconds: secondsToLimit, includeMinutes: true)), \(durationLabel(seconds: gap, includeMinutes: true)) before reset."
        }
        return "Pace ok: projected to last past reset."
    }

    private static func gauge(for snapshot: UsageSnapshot, historySamples: [String: [UsageHistorySample]], now: Date) -> DashboardGauge? {
        guard let usagePercent = snapshot.usagePercent else { return nil }
        let clamped = min(max(usagePercent, 0), 1)
        let reset = snapshot.reset.map { resetPhrase(for: $0, now: now) } ?? "live quota"
        let value = "\(displayPercent(for: snapshot))%"
        let subtitle = prefersRemainingDisplay(snapshot)
            ? "\(confidenceLabel(snapshot.confidence)) · left · \(reset)"
            : "\(confidenceLabel(snapshot.confidence)) · \(reset)"
        let paceCaption = paceCaption(for: snapshot, historySamples: historySamples, now: now)
        let dashboardURL = dashboardURL(for: snapshot)
        return DashboardGauge(
            title: Self.rowTitle(for: snapshot),
            value: value,
            subtitle: subtitle,
            caption: gaugeCaption(for: snapshot) ?? "Limit window active",
            explanation: explanation(for: snapshot),
            percent: clamped,
            state: snapshot.state,
            confidence: snapshot.confidence,
            paceCaption: paceCaption,
            dashboardURL: dashboardURL,
            receiptText: Self.receiptText(
                for: snapshot,
                title: Self.rowTitle(for: snapshot),
                value: value,
                detail: "\(subtitle) · \(gaugeCaption(for: snapshot) ?? "Limit window active")",
                dashboardURL: dashboardURL,
                trendCaption: nil,
                paceCaption: paceCaption,
                now: now
            )
        )
    }

    private static func subtitle(for summary: UsageSummary, now: Date) -> String {
        guard let newest = summary.snapshots.map(\.updatedAt).max() else {
            return "No sources yet"
        }
        return "Updated \(relativeTime(from: newest, now: now))"
    }

    private static func statusLabel(for state: UsageState) -> String {
        switch state {
        case .safe: "Safe"
        case .caution: "Watch"
        case .critical: "Near limit"
        case .exhausted: "Blocked"
        case .unknown: "Learning"
        }
    }

    private static func insight(for summary: UsageSummary, now: Date) -> String {
        guard !summary.snapshots.isEmpty else {
            return "Add one exact source, then the menu bar can warn before you stall."
        }
        guard let snapshot = summary.primarySnapshot, let percent = snapshot.usagePercent else {
            let subscriptionCount = summary.snapshots.filter(\.isSubscriptionOnly).count
            let localCount = summary.snapshots.filter { $0.source == .localLogs }.count
            let exactUnboundedCount = summary.snapshots.filter {
                $0.confidence == .exact && $0.source == .officialAPI && $0.usagePercent == nil
            }.count
            if exactUnboundedCount > 0 {
                return "\(exactUnboundedCount) exact spend/activity row\(exactUnboundedCount == 1 ? "" : "s") connected. Quota alerts still need comparable limits."
            }
            if subscriptionCount > 0 {
                return "\(subscriptionCount) subscription label\(subscriptionCount == 1 ? "" : "s") found. Usage limits still need exact connectors."
            }
            return "\(localCount) local source\(localCount == 1 ? "" : "s") found. Exact limits still need metadata."
        }
        if let codexInsight = codexInsight(for: summary) {
            return codexInsight
        }
        let remaining = max(0, Int(((1 - percent) * 100).rounded()))
        let comparable = summary.snapshots.compactMap { candidate -> (UsageSnapshot, Double)? in
            guard let value = candidate.usagePercent else { return nil }
            return (candidate, value)
        }
        if snapshot.state == .safe,
           let best = comparable.min(by: { $0.1 < $1.1 }),
           best.0.id != snapshot.id,
           best.0.state == .safe {
            return "Use \(rowTitle(for: best.0)) now; \(rowTitle(for: snapshot)) is the reserve at \(remaining)% left."
        }
        switch snapshot.state {
        case .safe:
            return "Keep going. Tightest lane still has \(remaining)% headroom."
        case .caution:
            return "Start watching \(rowTitle(for: snapshot)): \(remaining)% left."
        case .critical:
            return "Save your flow. \(rowTitle(for: snapshot)) has only \(remaining)% left."
        case .exhausted:
            return "This lane is spent. Switch provider or wait for reset."
        case .unknown:
            return "Sources found, but no comparable limit yet."
        }
    }

    private static func trustDigest(for summary: UsageSummary) -> String {
        let exact = summary.snapshots.filter { $0.confidence == .exact }.count
        let estimated = summary.snapshots.filter { $0.confidence == .estimated }.count
        let unknown = summary.snapshots.filter { $0.confidence == .unknown }.count
        var parts: [String] = []
        if exact > 0 { parts.append("\(exact) exact") }
        if estimated > 0 { parts.append("\(estimated) estimated") }
        if unknown > 0 { parts.append("\(unknown) unknown") }
        return parts.isEmpty ? "No sources" : parts.joined(separator: " · ")
    }

    private static func footerNote(for summary: UsageSummary) -> String {
        guard !summary.snapshots.isEmpty else { return "No sources" }
        let hasAccount = summary.snapshots.contains { $0.source == .experimentalWebSession || $0.source == .officialAPI }
        let hasFallback = summary.snapshots.contains { $0.source == .localLogs }
        switch (hasAccount, hasFallback) {
        case (true, true): return "Account live · local fallback"
        case (true, false): return "Account live"
        case (false, true): return "Local fallback"
        case (false, false): return "No sources"
        }
    }

    private static func sourceHealth(for summary: UsageSummary, now: Date) -> [DashboardSourceHealthItem] {
        guard !summary.snapshots.isEmpty else {
            return [DashboardSourceHealthItem(id: "none", title: "Sources", value: "None", state: .unknown)]
        }

        let liveCount = summary.snapshots.filter {
            ($0.source == .officialAPI || $0.source == .experimentalWebSession) && $0.confidence == .exact
        }.count
        let fallbackCount = summary.snapshots.filter { $0.source == .localLogs }.count
        let setupCount = summary.snapshots.filter { $0.confidence == .unknown || $0.isSubscriptionOnly }.count
        let staleCount = summary.snapshots.filter { now.timeIntervalSince($0.updatedAt) > 600 }.count

        var items: [DashboardSourceHealthItem] = []
        if liveCount > 0 {
            items.append(DashboardSourceHealthItem(
                id: "live",
                title: "Live",
                value: "\(liveCount)",
                state: .safe
            ))
        }
        if fallbackCount > 0 {
            items.append(DashboardSourceHealthItem(
                id: "fallback",
                title: "Fallback",
                value: "\(fallbackCount)",
                state: liveCount > 0 ? .safe : .unknown
            ))
        }
        if setupCount > 0 {
            items.append(DashboardSourceHealthItem(
                id: "setup",
                title: "Setup",
                value: "\(setupCount)",
                state: .unknown
            ))
        }
        if staleCount > 0 {
            items.append(DashboardSourceHealthItem(
                id: "stale",
                title: "Stale",
                value: "\(staleCount)",
                state: .caution
            ))
        }
        return items
    }

    private struct UsageSpike {
        let snapshot: UsageSnapshot
        let points: Int
        let latestPercent: Int
    }

    private static func usageSpike(for snapshot: UsageSnapshot, history: [String: [Double]]) -> UsageSpike? {
        let samples = trendPercents(for: snapshot, history: history)
        guard samples.count >= 2, let latest = samples.last else { return nil }
        let previousIndex = samples.index(samples.endIndex, offsetBy: -2)
        let previous = samples[previousIndex]
        let delta = latest - previous
        guard latest >= 0.50, delta >= 0.20 else { return nil }
        return UsageSpike(
            snapshot: snapshot,
            points: Int((delta * 100).rounded()),
            latestPercent: Int((latest * 100).rounded())
        )
    }

    private static func mostImportantSpike(in snapshots: [UsageSnapshot], history: [String: [Double]]) -> UsageSpike? {
        snapshots
            .compactMap { usageSpike(for: $0, history: history) }
            .sorted { lhs, rhs in
                if lhs.points != rhs.points { return lhs.points > rhs.points }
                if lhs.latestPercent != rhs.latestPercent { return lhs.latestPercent > rhs.latestPercent }
                return rowTitle(for: lhs.snapshot) < rowTitle(for: rhs.snapshot)
            }
            .first
    }

    private static func guidanceItems(for summary: UsageSummary, history: [String: [Double]], now: Date) -> [DashboardGuidanceItem] {
        let comparable = summary.snapshots.filter {
            $0.usagePercent?.isFinite == true && !$0.isSubscriptionOnly
        }

        func percentUsed(_ snapshot: UsageSnapshot) -> Double {
            snapshot.usagePercent ?? 1
        }

        let mostRoom = comparable
            .filter { $0.state != .exhausted }
            .sorted { lhs, rhs in
                let left = percentUsed(lhs)
                let right = percentUsed(rhs)
                if left != right { return left < right }
                if lhs.confidence != rhs.confidence { return lhs.confidence == .exact }
                return rowTitle(for: lhs) < rowTitle(for: rhs)
            }
            .first

        let tightest = comparable
            .sorted(by: prefersRowOrder)
            .first

        var items: [DashboardGuidanceItem] = []
        if let spike = mostImportantSpike(in: comparable, history: history) {
            items.append(DashboardGuidanceItem(
                id: "spike-\(spike.snapshot.id)",
                title: "Spike",
                value: rowTitle(for: spike.snapshot),
                detail: "+\(spike.points) pts recently · \(guidanceDetail(for: spike.snapshot, now: now))",
                reason: "Largest recent increase in stored history.",
                state: spike.snapshot.state == .safe ? .caution : spike.snapshot.state
            ))
        }
        guard comparable.count >= 2 else { return items }

        if let mostRoom {
            items.append(DashboardGuidanceItem(
                id: "most-room-\(mostRoom.id)",
                title: "Most room",
                value: rowTitle(for: mostRoom),
                detail: guidanceDetail(for: mostRoom, now: now),
                reason: "Lowest used comparable lane.",
                state: mostRoom.state
            ))
        }
        if let tightest, tightest.id != mostRoom?.id {
            items.append(DashboardGuidanceItem(
                id: "tightest-\(tightest.id)",
                title: "Tightest",
                value: rowTitle(for: tightest),
                detail: guidanceDetail(for: tightest, now: now),
                reason: "Highest used comparable lane.",
                state: tightest.state
            ))
        }
        return items
    }

    private static func guidanceDetail(for snapshot: UsageSnapshot, now: Date) -> String {
        var parts: [String] = []
        if let remaining = remainingLabel(for: snapshot) {
            parts.append(remaining)
        } else if let usagePercent = snapshot.usagePercent {
            parts.append("\(Int((max(0, 1 - usagePercent) * 100).rounded()))% left")
        }
        if let reset = snapshot.reset {
            parts.append(resetPhrase(for: reset, now: now))
        }
        parts.append(confidenceLabel(snapshot.confidence))
        return parts.joined(separator: " · ")
    }

    private static func dashboardURL(for snapshot: UsageSnapshot) -> String? {
        switch snapshot.provider {
        case .cursor:
            return "https://cursor.com/dashboard"
        case .openRouter:
            return "https://openrouter.ai/settings/credits"
        case .openAI:
            return "https://platform.openai.com/usage"
        default:
            return nil
        }
    }

    private static func setupGuidance(for summary: UsageSummary, monitoredProviders: Set<Provider>) -> [DashboardSetupItem] {
        let snapshots = summary.snapshots
        let exactComparableProviders = Set(snapshots.compactMap { snapshot -> Provider? in
            snapshot.usagePercent != nil && snapshot.confidence == .exact ? snapshot.provider : nil
        })
        let hasExactComparable = !exactComparableProviders.isEmpty
        let grouped = Dictionary(grouping: snapshots, by: \.provider)
        var items: [DashboardSetupItem] = []

        if monitoredProviders.contains(.codex), !exactComparableProviders.contains(.codex) {
            if grouped[.codex]?.isEmpty == false {
                items.append(DashboardSetupItem(
                    id: "codex-fallback",
                    title: "Codex",
                    status: "Using fallback data",
                    action: "Account usage is unavailable. Refresh after signing in to Codex.",
                    state: .unknown
                ))
            } else if !hasExactComparable {
                items.append(DashboardSetupItem(
                    id: "codex-missing",
                    title: "Codex",
                    status: "Not detected",
                    action: "Run Codex once, then refresh to pick up quota metadata.",
                    state: .unknown
                ))
            }
        }

        if monitoredProviders.contains(.cursor), !exactComparableProviders.contains(.cursor) {
            if grouped[.cursor]?.contains(where: { $0.isSubscriptionOnly }) == true {
                items.append(DashboardSetupItem(
                    id: "cursor-subscription-only",
                    title: "Cursor",
                    status: "Plan found, usage missing",
                    action: "Open Cursor while signed in, then refresh for live account usage.",
                    state: .caution
                ))
            } else if !hasExactComparable {
                items.append(DashboardSetupItem(
                    id: "cursor-missing",
                    title: "Cursor",
                    status: "Not detected",
                    action: "Open Cursor while signed in so the local account state can be read.",
                    state: .unknown
                ))
            }
        }

        if monitoredProviders.contains(.openRouter), !exactComparableProviders.contains(.openRouter), !hasExactComparable {
            items.append(DashboardSetupItem(
                id: "openrouter-missing",
                title: "OpenRouter",
                status: "API key missing",
                action: "Paste an API key in Settings for exact credit usage.",
                state: .unknown
            ))
        }

        if monitoredProviders.contains(.claudeCode),
           let claude = grouped[.claudeCode],
           !claude.contains(where: { $0.usagePercent != nil }),
           !hasExactComparable {
            items.append(DashboardSetupItem(
                id: "claude-estimated",
                title: "Claude Code",
                status: "Estimated only",
                action: "Local logs show token use, but no hard quota is exposed.",
                state: .unknown
            ))
        }

        return Array(items.prefix(3))
    }

    private static func resetTimeline(for summary: UsageSummary, now: Date) -> [DashboardResetItem] {
        summary.snapshots
            .compactMap { snapshot -> (UsageSnapshot, TimeInterval)? in
                guard let reset = snapshot.reset, !snapshot.isSubscriptionOnly else { return nil }
                return (snapshot, secondsRemaining(for: reset, now: now))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return rowTitle(for: lhs.0) < rowTitle(for: rhs.0)
            }
            .prefix(3)
            .map { snapshot, seconds in
                DashboardResetItem(
                    id: snapshot.id,
                    title: rowTitle(for: snapshot),
                    detail: resetTimelineDetail(for: snapshot, seconds: seconds, now: now),
                    value: resetTimelineValue(seconds: seconds),
                    state: snapshot.state
                )
            }
    }

    private static func resetTimelineDetail(for snapshot: UsageSnapshot, seconds: TimeInterval, now: Date) -> String {
        let capacity = prefersRemainingDisplay(snapshot)
            ? remainingLabel(for: snapshot)
            : remainingLabel(for: snapshot) ?? usedLabel(for: snapshot)
        let resolvedResetDate = snapshot.reset.map { resetDate(for: $0, now: now) }
        var parts: [String] = []
        if seconds >= 24 * 3600, let resolvedResetDate {
            parts.append(calendarResetLabel(for: resolvedResetDate))
        } else if seconds <= 60 {
            parts.append("ready now")
        } else {
            parts.append("reset window")
        }
        if let capacity { parts.append(capacity) }
        return parts.joined(separator: " · ")
    }

    private static func resetTimelineValue(seconds: TimeInterval) -> String {
        if seconds <= 60 { return "now" }
        return durationLabel(seconds: seconds, includeMinutes: seconds < 24 * 3600)
    }

    private static func rowTitle(for snapshot: UsageSnapshot) -> String {
        let label = snapshot.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account = snapshot.account {
            let accountName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let plan = account.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountMatchesProvider = accountName.caseInsensitiveCompare(snapshot.provider.displayName) == .orderedSame
            let planTitle = plan.flatMap { $0.isEmpty ? nil : $0 }

            if accountMatchesProvider, let planTitle {
                if snapshot.isSubscriptionOnly {
                    return "\(snapshot.provider.displayName) · Subscription"
                }
                if label.isEmpty || label == snapshot.provider.displayName || label == accountName {
                    return "\(snapshot.provider.displayName) · \(planTitle)"
                }
                return "\(snapshot.provider.displayName) · \(planTitle) · \(label)"
            }

            let accountTitle = account.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty || label == snapshot.provider.displayName || label == accountTitle {
                return "\(snapshot.provider.displayName) · \(accountTitle)"
            }
            return "\(snapshot.provider.displayName) · \(accountTitle) · \(label)"
        }
        guard !label.isEmpty, label != snapshot.provider.displayName else {
            return snapshot.provider.displayName
        }
        if label.localizedCaseInsensitiveContains(snapshot.provider.displayName) {
            return label
        }
        return "\(snapshot.provider.displayName) · \(label)"
    }

    private static func remainingLabel(for snapshot: UsageSnapshot) -> String? {
        guard let limit = snapshot.limit,
              snapshot.used.isComparable(with: limit),
              let used = snapshot.used.numericValueForLimitComparison,
              let total = limit.numericValueForLimitComparison,
              total > 0 else {
            return nil
        }
        let remaining = max(0, total - used)
        switch (snapshot.used, limit) {
        case (.percent, .percent):
            return "\(Int(remaining.rounded()))% left"
        case (.credits, .credits):
            return "\(format(remaining)) credits left"
        case (.usd, .usd):
            return "$\(format(remaining)) left"
        case (.requests, .requests):
            return "\(compact(Int(remaining.rounded()))) requests left"
        case (.tokens, .tokens):
            return "\(compact(Int(remaining.rounded()))) tokens left"
        default:
            return nil
        }
    }

    private static func usedLabel(for snapshot: UsageSnapshot) -> String? {
        guard let usagePercent = snapshot.usagePercent else { return nil }
        return "\(Int((usagePercent * 100).rounded()))% used"
    }

    private static func gaugeCaption(for snapshot: UsageSnapshot) -> String? {
        if prefersRemainingDisplay(snapshot) {
            return usedLabel(for: snapshot)
        }
        return remainingLabel(for: snapshot)
    }

    private static func tokenBreakdown(for quantity: UsageQuantity) -> String? {
        guard case let .tokens(input, output, cacheRead, cacheWrite) = quantity else { return nil }
        let cache = cacheRead + cacheWrite
        if input + output + cache == 0 { return nil }
        return "in \(compact(input)) · out \(compact(output)) · cache \(compact(cache))"
    }

    private static func lastSeenPercent(for snapshot: UsageSnapshot) -> Int? {
        guard case .percent(let value) = snapshot.used else { return nil }
        return Int(value.rounded())
    }

    private static func explanation(for snapshot: UsageSnapshot) -> String {
        func withProviderNote(_ base: String) -> String {
            guard let note = snapshot.providerNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
                return base
            }
            return "\(base) Provider note: \(note)"
        }

        if snapshot.isSubscriptionOnly {
            switch snapshot.provider {
            case .cursor:
                return "Cursor is detected locally. The app could not reach live usage, so this is only a subscription fallback."
            case .claudeCode, .claude:
                return "Plan label is shown separately from usage because Claude Code local logs do not expose a hard subscription quota."
            default:
                return "Subscription label only. This row confirms the plan, not a comparable usage limit."
            }
        }
        switch (snapshot.provider, snapshot.source, snapshot.confidence) {
        case (.openAI, .officialAPI, .exact):
            return withProviderNote("Exact from OpenAI organization usage APIs. Spend and token activity are shown without inventing a hard limit.")
        case (.openRouter, .officialAPI, .exact):
            return withProviderNote("Exact from official OpenRouter API. Shows comparable credits with remaining capacity and refresh freshness.")
        case (.codex, .experimentalWebSession, .exact):
            if snapshot.label.localizedCaseInsensitiveContains("spark") {
                return withProviderNote("Exact from Codex account usage. Spark is a model-specific quota reported separately from the general 5h window.")
            }
            return withProviderNote("Exact from Codex account usage. The 5h window is the active session limit; Weekly is the longer reserve.")
        case (.cursor, .experimentalWebSession, .exact):
            return withProviderNote("Exact from Cursor account usage. Uses the local Cursor auth token; no prompt text is read.")
        case (.codex, .localLogs, .exact):
            return withProviderNote("Fallback from local Codex session metadata. Useful when the account endpoint is unavailable, but it can lag behind Codex.")
        case (.codex, .localLogs, .unknown):
            let lastSeen = lastSeenPercent(for: snapshot).map { "Last seen \($0)% used before reset. " } ?? ""
            return "\(lastSeen)Waiting for Codex to emit a fresh \(snapshot.label) quota event; not showing expired data as current."
        case (.claudeCode, .localLogs, .estimated):
            return "Estimated from local Claude Code usage metadata. Token totals are approximate and no prompt text is stored."
        case (.openCode, .localLogs, .unknown):
            return "Detected OpenCode locally, but usage parsing is not wired yet. Treat this lane as setup needed."
        case (_, .officialAPI, .exact):
            return withProviderNote("Exact from the provider API. Shows comparable quota data and refresh freshness.")
        case (_, .localLogs, .estimated):
            return withProviderNote("Estimated from local usage metadata. Good for trend awareness, not a hard provider limit.")
        case (_, .localLogs, .exact):
            return withProviderNote("Exact from local rate-limit metadata exposed by the tool. No prompt text is stored.")
        default:
            return withProviderNote("Source is detected, but the app cannot yet prove a comparable limit.")
        }
    }

    private static func detail(for snapshot: UsageSnapshot, now: Date) -> String {
        if snapshot.isSubscriptionOnly {
            return ["Detected locally", "plan label", accountHint(for: snapshot), "usage not connected"].compactMap { $0 }.joined(separator: " · ")
        }
        if snapshot.provider == .codex, snapshot.source == .localLogs, snapshot.confidence == .unknown {
            return "Expired window · local · last event \(relativeTime(from: snapshot.updatedAt, now: now))"
        }
        var parts: [String] = []
        if prefersRemainingDisplay(snapshot), let used = usedLabel(for: snapshot) {
            parts.append(used)
        } else if let remaining = remainingLabel(for: snapshot) {
            parts.append(remaining)
        } else if let breakdown = tokenBreakdown(for: snapshot.used) {
            parts.append(breakdown)
        }
        if let reset = snapshot.reset {
            parts.append(resetPhrase(for: reset, now: now))
        }
        parts.append(confidenceLabel(snapshot.confidence))
        parts.append(sourceLabel(snapshot.source))
        if let accountHint = accountHint(for: snapshot) {
            parts.append(accountHint)
        }
        parts.append(relativeTime(from: snapshot.updatedAt, now: now))
        return parts.joined(separator: " · ")
    }

    private static func receiptText(
        for snapshot: UsageSnapshot,
        title: String,
        value: String,
        detail: String,
        dashboardURL: String?,
        trendCaption: String?,
        paceCaption: String?,
        now: Date
    ) -> String {
        var lines = [
            "AI Fuel Gauge lane receipt",
            "Lane: \(title)",
            "Value: \(value)",
            "Detail: \(detail)",
            "State: \(snapshot.state.rawValue)",
            "Confidence: \(snapshot.confidence.rawValue)",
            "Source: \(sourceLabel(snapshot.source))",
            "Updated: \(iso8601(snapshot.updatedAt)) (\(relativeTime(from: snapshot.updatedAt, now: now)))"
        ]
        if let usagePercent = snapshot.usagePercent {
            lines.append("Meter: \(Int((min(max(usagePercent, 0), 1) * 100).rounded()))% used")
        }
        if let reset = snapshot.reset {
            lines.append("Reset: \(resetPhrase(for: reset, now: now))")
        }
        if let account = snapshot.account?.displayTitle, !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Account: \(account)")
        }
        if let trendCaption, !trendCaption.isEmpty {
            lines.append("Trend: \(trendCaption)")
        }
        if let paceCaption, !paceCaption.isEmpty {
            lines.append("Pace: \(paceCaption)")
        }
        if let dashboardURL, !dashboardURL.isEmpty {
            lines.append("Dashboard: \(dashboardURL)")
        }
        let explanation = explanation(for: snapshot)
        if !explanation.isEmpty {
            lines.append("Explanation: \(explanation)")
        }
        lines.append("Privacy: no prompts, API keys, auth tokens, or raw provider responses included.")
        return lines.joined(separator: "\n")
    }

    private static func accountHint(for snapshot: UsageSnapshot) -> String? {
        guard let identityHint = snapshot.account?.identityHint?.trimmingCharacters(in: .whitespacesAndNewlines), !identityHint.isEmpty else {
            return nil
        }
        return "acct \(identityHint)"
    }

    private static func value(for snapshot: UsageSnapshot) -> String {
        if snapshot.isSubscriptionOnly, let plan = snapshot.account?.plan?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty {
            return plan
        }
        if snapshot.isSubscriptionOnly {
            return "Detected"
        }

        if let usagePercent = snapshot.usagePercent {
            if prefersRemainingDisplay(snapshot) {
                return "\(displayPercent(for: snapshot))% left"
            }
            return "\(Int((usagePercent * 100).rounded()))% used"
        }

        if snapshot.confidence == .unknown {
            if snapshot.provider == .codex, snapshot.source == .localLogs {
                return "Waiting"
            }
            return "No data"
        }

        switch snapshot.used {
        case .tokens(let input, let output, let cacheRead, let cacheWrite):
            let total = input + output + cacheRead + cacheWrite
            if total == 0 { return "No tokens" }
            return "\(compact(total)) tokens"
        case .credits(let value):
            return "\(format(value)) credits"
        case .usd(let value):
            return "$\(format(value))"
        case .requests(let value):
            return "\(compact(value)) requests"
        case .percent(let value):
            return "\(Int(value.rounded()))%"
        }
    }

    private static func confidenceLabel(_ confidence: Confidence) -> String {
        switch confidence {
        case .exact: "Exact"
        case .estimated: "Estimated"
        case .unknown: "Unknown"
        }
    }

    private static func sourceLabel(_ source: UsageSource) -> String {
        switch source {
        case .localLogs: "local"
        case .officialAPI: "API"
        case .experimentalWebSession: "account"
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func prefersRowOrder(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) -> Bool {
        let leftPriority = rowStatePriority(lhs)
        let rightPriority = rowStatePriority(rhs)
        if leftPriority != rightPriority { return leftPriority > rightPriority }
        if lhs.provider == .codex, rhs.provider == .codex, lhs.state == .safe {
            let leftPriority = codexLanePriority(lhs)
            let rightPriority = codexLanePriority(rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
        }
        switch (lhs.usagePercent, rhs.usagePercent) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.provider.displayName != rhs.provider.displayName {
                return lhs.provider.displayName < rhs.provider.displayName
            }
            return lhs.label < rhs.label
        }
    }

    private static func prefersFeaturedOrder(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) -> Bool {
        if lhs.provider == .codex, rhs.provider == .codex, lhs.state == .safe {
            let leftPriority = codexLanePriority(lhs)
            let rightPriority = codexLanePriority(rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
        }
        let leftPriority = rowStatePriority(lhs)
        let rightPriority = rowStatePriority(rhs)
        if leftPriority != rightPriority { return leftPriority > rightPriority }
        switch (lhs.usagePercent, rhs.usagePercent) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return rowTitle(for: lhs) < rowTitle(for: rhs)
        }
    }

    private static func rowStatePriority(_ snapshot: UsageSnapshot) -> Int {
        if snapshot.isSubscriptionOnly { return 0 }
        switch snapshot.state {
        case .critical: return 5
        case .caution: return 4
        case .safe: return 3
        case .exhausted: return 2
        case .unknown: return snapshot.confidence == .estimated ? 1 : 0
        }
    }

    private static func prefersRemainingDisplay(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.provider == .codex && snapshot.usagePercent != nil
    }

    private static func hidesPrimaryRow(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.provider == .codex && snapshot.usagePercent != nil
    }

    private static func displayPercent(for snapshot: UsageSnapshot) -> Int {
        guard let usagePercent = snapshot.usagePercent else { return 0 }
        let value = prefersRemainingDisplay(snapshot) ? max(0, 1 - usagePercent) : usagePercent
        return Int((value * 100).rounded())
    }

    private static func codexLanePriority(_ snapshot: UsageSnapshot) -> Int {
        let label = snapshot.label.lowercased()
        if label.contains("5h") || label.contains("session") { return 0 }
        if label.contains("weekly") || label.contains("week") || label.contains("7d") { return 2 }
        return 1
    }

    private static func codexInsight(for summary: UsageSummary) -> String? {
        let codex = summary.snapshots.filter { $0.provider == .codex }
        guard !codex.isEmpty else { return nil }
        if let stressed = codex
            .filter({ $0.state >= .caution })
            .sorted(by: prefersRowOrder)
            .first,
           let remaining = remainingLabel(for: stressed) {
            return "\(rowTitle(for: stressed)) is the constraint: \(remaining)."
        }
        let session = codex.first { codexLanePriority($0) == 0 }
        let weekly = codex.first { codexLanePriority($0) == 2 }
        if let session, let sessionRemaining = remainingLabel(for: session) {
            if let weekly, let weeklyRemaining = remainingLabel(for: weekly) {
                return "Use \(rowTitle(for: session)) now: \(sessionRemaining). Weekly reserve is \(weeklyRemaining)."
            }
            return "Use \(rowTitle(for: session)) now: \(sessionRemaining)."
        }
        return nil
    }

    private static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "now" }
        let minutes = max(1, seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = max(1, minutes / 60)
        if hours < 24 { return "\(hours)h ago" }
        let days = max(1, hours / 24)
        return "\(days)d ago"
    }

    private static func resetPhrase(for reset: ResetInfo, now: Date) -> String {
        let seconds = max(0, secondsRemaining(for: reset, now: now))
        if seconds < 24 * 3600 {
            return "resets in \(durationLabel(seconds: seconds, includeMinutes: true))"
        }
        let resetDate = resetDate(for: reset, now: now)
        return "resets \(calendarResetLabel(for: resetDate)) (\(durationLabel(seconds: seconds, includeMinutes: false)))"
    }

    private static func secondsRemaining(for reset: ResetInfo, now: Date) -> TimeInterval {
        switch reset {
        case .rollingWindow(let seconds): max(0, seconds)
        case .fixed(let date): max(0, date.timeIntervalSince(now))
        }
    }

    private static func resetDate(for reset: ResetInfo, now: Date) -> Date {
        switch reset {
        case .rollingWindow(let seconds): now.addingTimeInterval(max(0, seconds))
        case .fixed(let date): date
        }
    }

    private static func durationLabel(seconds: TimeInterval, includeMinutes: Bool) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded(.up)))
        if totalMinutes < 60 { return "\(max(totalMinutes, 0))m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 24 {
            if includeMinutes, minutes > 0 { return "\(hours)h \(minutes)m" }
            return "\(hours)h"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours > 0 { return "\(days)d \(remainingHours)h" }
        return "\(days)d"
    }

    private static func calendarResetLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE h a"
        return formatter.string(from: date)
    }

    private static func compact(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 1_000_000_000 {
            return sign + String(format: "%.2fB", Double(absValue) / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return sign + String(format: "%.2fM", Double(absValue) / 1_000_000)
        }
        if absValue >= 10_000 {
            return sign + String(format: "%.1fK", Double(absValue) / 1_000)
        }
        return grouped(value)
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
