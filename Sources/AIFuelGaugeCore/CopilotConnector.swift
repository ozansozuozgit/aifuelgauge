import Foundation

// NOTE: Built against the documented GitHub Copilot shape but NOT yet verified
// against a live account (no ~/.config/github-copilot on the dev machine).
// Shipped behind a default-OFF toggle until verified. Device-flow auth is a
// Settings action; the refresh loop only reuses an existing local token.

// MARK: - Token discovery

/// Reads the GitHub OAuth token the Copilot editor plugins already store on disk.
public enum CopilotTokenReader {
    private struct Entry: Decodable { let oauth_token: String? }

    public static func tokenURLs(home: URL) -> [URL] {
        let base = home.appendingPathComponent(".config/github-copilot")
        return [base.appendingPathComponent("apps.json"), base.appendingPathComponent("hosts.json")]
    }

    /// Parse an apps.json / hosts.json blob — a dictionary keyed by host, each
    /// value carrying an `oauth_token`. Returns the first non-empty token.
    public static func parseToken(fileData: Data) -> String? {
        guard let map = try? JSONDecoder().decode([String: Entry].self, from: fileData) else { return nil }
        return map.values.compactMap { $0.oauth_token }.first { !$0.isEmpty }
    }

    public static func loadToken(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        for url in tokenURLs(home: home) {
            if let data = try? Data(contentsOf: url), let token = parseToken(fileData: data) {
                return token
            }
        }
        return nil
    }
}

// MARK: - Usage parser

/// Maps the `copilot_internal/user` quota snapshot into exact lanes.
public enum CopilotUsageParser {
    private struct Quota: Decodable {
        let entitlement: Double?
        let remaining: Double?
        let percent_remaining: Double?
    }
    private struct Response: Decodable {
        let copilot_plan: String?
        let quota_reset_date: String?
        let quota_snapshots: [String: Quota]?
    }

    /// Lanes we surface, in display order, mapped to friendly labels.
    private static let laneOrder: [(key: String, label: String)] = [
        ("premium_interactions", "Premium"),
        ("chat", "Chat"),
        ("completions", "Completions"),
    ]

    public static func parse(data: Data, now: Date) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let snapshots = response.quota_snapshots ?? [:]
        let plan = planLabel(response.copilot_plan)
        let account = UsageAccount(identifier: "copilot", displayName: "Copilot", plan: plan)
        let reset = response.quota_reset_date.flatMap(parseDate).map { ResetInfo.fixed($0) }

        var rows: [UsageSnapshot] = []
        for (key, label) in laneOrder {
            guard let quota = snapshots[key] else { continue }
            guard let used = usedPercent(quota) else { continue }   // skips placeholders
            rows.append(UsageSnapshot(
                provider: .copilot,
                source: .officialAPI,
                account: account,
                label: label,
                used: .percent(used),
                limit: .percent(100),
                reset: reset,
                confidence: .exact,
                updatedAt: now))
        }
        return rows
    }

    /// Returns used-percent, or nil for placeholder quotas (zero entitlement =
    /// token-based billing) so we don't show a fake "0% used" lane.
    private static func usedPercent(_ quota: Quota) -> Double? {
        if let entitlement = quota.entitlement, entitlement == 0,
           (quota.remaining ?? 0) == 0, quota.percent_remaining == nil {
            return nil
        }
        let remainingPercent: Double
        if let percent = quota.percent_remaining {
            remainingPercent = percent
        } else if let entitlement = quota.entitlement, entitlement > 0, let remaining = quota.remaining {
            remainingPercent = (remaining / entitlement) * 100
        } else {
            return nil
        }
        return min(max(100 - remainingPercent, 0), 100)
    }

    static func planLabel(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw.contains("enterprise") { return "Enterprise" }
        if raw.contains("business") { return "Business" }
        if raw.contains("pro+") || raw.contains("pro_plus") { return "Pro+" }
        if raw.contains("pro") { return "Pro" }
        if raw.contains("free") { return "Free" }
        return raw.capitalized
    }

    /// Copilot returns a date-only string (`2026-06-01`); fall back from full
    /// ISO8601 to a UTC day parse.
    static func parseDate(_ string: String) -> Date? {
        if let date = ISO8601Tolerant.date(string) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

// MARK: - Connector

public final class CopilotConnector {
    private let transport: HTTPTransport
    private let usageURL: URL
    private let now: () -> Date

    public init(
        transport: HTTPTransport = URLSession.shared,
        usageURL: URL = URL(string: "https://api.github.com/copilot_internal/user")!,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.usageURL = usageURL
        self.now = now
    }

    public func fetchUsage(token: String) async throws -> [UsageSnapshot] {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.badStatus(http.statusCode) }
        return try CopilotUsageParser.parse(data: data, now: now())
    }

    public func fetchUsageFromLocalToken(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async throws -> [UsageSnapshot] {
        guard let token = CopilotTokenReader.loadToken(home: home) else { return [] }
        return try await fetchUsage(token: token)
    }
}
