import Foundation

// MARK: - Credentials

/// Claude Code's own OAuth credentials, read from `~/.claude/.credentials.json`
/// (or the matching Keychain item). Reading these lets us fetch exact Claude
/// usage without our injected statusline hook.
public struct ClaudeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    /// Expiry as milliseconds since the Unix epoch (as Claude Code stores it).
    public let expiresAtMillis: Double?
    /// Reserved: plan tier is not present in the credentials file; kept optional
    /// so a future enrichment (from the refresh response) can populate it.
    public let subscriptionType: String?

    public init(accessToken: String, refreshToken: String?, expiresAtMillis: Double?, subscriptionType: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMillis = expiresAtMillis
        self.subscriptionType = subscriptionType
    }

    /// True when the access token is missing an expiry or is within `skew`
    /// seconds of expiring. The ~8h tokens expire often, so this gates refresh.
    public func isExpired(now: Date, skew: TimeInterval = 60) -> Bool {
        guard let expiresAtMillis else { return true }
        return now.timeIntervalSince1970 >= (expiresAtMillis / 1000.0) - skew
    }
}

/// Reads and writes Claude's OAuth credential file, plus a Keychain fallback.
public enum ClaudeCredentialsReader {
    private struct File: Codable {
        struct OAuth: Codable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth
    }

    public static func credentialsURL(home: URL) -> URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    /// Parse the JSON contents of `~/.claude/.credentials.json`.
    public static func parse(fileData: Data) throws -> ClaudeCredentials {
        let file = try JSONDecoder().decode(File.self, from: fileData)
        return ClaudeCredentials(
            accessToken: file.claudeAiOauth.accessToken,
            refreshToken: file.claudeAiOauth.refreshToken,
            expiresAtMillis: file.claudeAiOauth.expiresAt
        )
    }

    /// Encode credentials back into the file's JSON shape (for write-back after refresh).
    public static func encode(_ credentials: ClaudeCredentials) throws -> Data {
        let file = File(claudeAiOauth: .init(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAtMillis
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    public static func loadFromDisk(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ClaudeCredentials? {
        guard let data = try? Data(contentsOf: credentialsURL(home: home)) else { return nil }
        return try? parse(fileData: data)
    }

    /// Reads the "Claude Code-credentials" generic password via the security CLI.
    public static func loadFromKeychain() -> ClaudeCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return try? parse(fileData: data)
    }

    public static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ClaudeCredentials? {
        loadFromDisk(home: home) ?? loadFromKeychain()
    }

    /// Atomically write refreshed credentials back to the credential file,
    /// preserving 0600 permissions (temp file in the same dir + replace).
    public static func writeBack(_ credentials: ClaudeCredentials,
                                 home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let url = credentialsURL(home: home)
        let data = try encode(credentials)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".credentials.json.tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

// MARK: - Token refresh

/// Result of an OAuth refresh; `refreshToken` rotates and must be persisted.
public struct ClaudeRefreshedToken: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtMillis: Double?
}

/// Refreshes an expired Claude access token. The token endpoint sits behind
/// Cloudflare and rejects generic user-agents (error 1010), so we send a
/// CLI-style User-Agent that passes.
public final class ClaudeTokenRefresher {
    public static let defaultClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let defaultUserAgent = "claude-cli/1.0.0 (external, aifuelgauge)"

    private let transport: HTTPTransport
    private let endpoint: URL
    private let clientID: String
    private let userAgent: String
    private let now: () -> Date

    public init(
        transport: HTTPTransport = URLSession.shared,
        endpoint: URL = URL(string: "https://platform.claude.com/v1/oauth/token")!,
        clientID: String = ClaudeTokenRefresher.defaultClientID,
        userAgent: String = ClaudeTokenRefresher.defaultUserAgent,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.clientID = clientID
        self.userAgent = userAgent
        self.now = now
    }

    private struct Response: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    /// Pure parse of a refresh response into a rotated token.
    public static func parse(data: Data, fallbackRefreshToken: String, now: Date) throws -> ClaudeRefreshedToken {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let expiresAtMillis = response.expires_in.map { (now.timeIntervalSince1970 + $0) * 1000.0 }
        return ClaudeRefreshedToken(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? fallbackRefreshToken,
            expiresAtMillis: expiresAtMillis
        )
    }

    public func refresh(refreshToken: String) async throws -> ClaudeRefreshedToken {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID),
        ]
        request.httpBody = (components.percentEncodedQuery ?? "").data(using: .utf8)

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.badStatus(http.statusCode) }
        return try Self.parse(data: data, fallbackRefreshToken: refreshToken, now: now())
    }
}

// MARK: - Usage parser

/// Maps Anthropic's OAuth usage response (snake_case windows, percent
/// utilization) into exact `UsageSnapshot` lanes.
public enum ClaudeOAuthUsageParser {
    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
    private struct Response: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let seven_day_sonnet: Window?
    }

    public static func parse(data: Data, subscriptionType: String?, now: Date) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let plan = planLabel(subscriptionType)
        let account = UsageAccount(identifier: "claude-oauth", displayName: "Claude", plan: plan)
        var rows: [UsageSnapshot] = []
        func add(_ window: Window?, label: String) {
            guard let window, let util = window.utilization else { return }
            rows.append(UsageSnapshot(
                provider: .claudeCode,
                source: .officialAPI,
                account: account,
                label: label,
                used: .percent(min(max(util, 0), 100)),
                limit: .percent(100),
                reset: window.resets_at.flatMap(parseDate).map { .fixed($0) },
                confidence: .exact,
                updatedAt: now))
        }
        add(response.five_hour, label: "5h")
        add(response.seven_day, label: "Weekly")
        add(response.seven_day_opus, label: "Weekly · Opus")
        add(response.seven_day_sonnet, label: "Weekly · Sonnet")
        return rows
    }

    static func planLabel(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw.contains("max"), raw.contains("20") { return "Max 20x" }
        if raw.contains("max"), raw.contains("5") { return "Max 5x" }
        if raw.contains("max") { return "Max" }
        if raw.contains("pro") { return "Pro" }
        if raw.contains("team") { return "Team" }
        if raw.contains("enterprise") { return "Enterprise" }
        return raw.capitalized
    }

    /// Anthropic returns microseconds + offset; reuse the shared tolerant parser.
    static func parseDate(_ string: String) -> Date? { ISO8601Tolerant.date(string) }
}

// MARK: - Cache

/// Process-wide cache of the last successful Claude usage lanes. Anthropic's
/// OAuth usage endpoint is aggressively rate-limited (HTTP 429 after rapid
/// calls), so we debounce calls and preserve the last good result on failure
/// rather than letting callers fall back to the unreliable per-window statusline.
public actor ClaudeUsageCache {
    public static let shared = ClaudeUsageCache()
    private var lanes: [UsageSnapshot] = []
    private var storedAt: Date?

    public init() {}

    func fresh(within interval: TimeInterval, now: Date) -> [UsageSnapshot]? {
        guard let storedAt, !lanes.isEmpty, now.timeIntervalSince(storedAt) < interval else { return nil }
        return lanes
    }

    func store(_ lanes: [UsageSnapshot], at date: Date) {
        self.lanes = lanes
        self.storedAt = date
    }
}

// MARK: - Connector

public final class ClaudeOAuthConnector {
    private let transport: HTTPTransport
    private let usageEndpoint: URL
    private let refresher: ClaudeTokenRefresher
    private let userAgent: String
    private let now: () -> Date
    private let cache: ClaudeUsageCache
    /// Don't re-hit the rate-limited endpoint more often than this.
    private let minRefetchInterval: TimeInterval
    /// Keep serving the last good value for up to this long when calls fail.
    private let stalePreserveTTL: TimeInterval

    public init(
        transport: HTTPTransport = URLSession.shared,
        usageEndpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        refresher: ClaudeTokenRefresher = ClaudeTokenRefresher(),
        userAgent: String = ClaudeTokenRefresher.defaultUserAgent,
        now: @escaping () -> Date = Date.init,
        cache: ClaudeUsageCache = .shared,
        minRefetchInterval: TimeInterval = 120,
        stalePreserveTTL: TimeInterval = 1800
    ) {
        self.transport = transport
        self.usageEndpoint = usageEndpoint
        self.refresher = refresher
        self.userAgent = userAgent
        self.now = now
        self.cache = cache
        self.minRefetchInterval = minRefetchInterval
        self.stalePreserveTTL = stalePreserveTTL
    }

    /// Fetch usage with an already-valid access token.
    public func fetchUsage(credentials: ClaudeCredentials) async throws -> [UsageSnapshot] {
        var request = URLRequest(url: usageEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.badStatus(http.statusCode) }
        return try ClaudeOAuthUsageParser.parse(data: data, subscriptionType: credentials.subscriptionType, now: now())
    }

    /// Load credentials from disk/Keychain; refresh + write back if expired;
    /// then fetch usage — debounced and cached. Returns [] if no credentials.
    public func fetchUsageFromLocalCredentials(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async throws -> [UsageSnapshot] {
        let nowDate = now()
        // Debounce: reuse a very recent result so frequent (e.g. activity-driven)
        // refreshes don't hammer the rate-limited endpoint or churn the token.
        if let recent = await cache.fresh(within: minRefetchInterval, now: nowDate) { return recent }
        guard let stored = ClaudeCredentialsReader.load(home: home) else { return [] }
        do {
            var credentials = stored
            if credentials.isExpired(now: nowDate) {
                guard let refreshToken = credentials.refreshToken else { return [] }
                let rotated = try await refresher.refresh(refreshToken: refreshToken)
                credentials = ClaudeCredentials(
                    accessToken: rotated.accessToken,
                    refreshToken: rotated.refreshToken,
                    expiresAtMillis: rotated.expiresAtMillis,
                    subscriptionType: stored.subscriptionType
                )
                // Persist rotation so Claude Code and we stay in sync. Best-effort:
                // a failed write must not block returning fresh usage.
                try? ClaudeCredentialsReader.writeBack(credentials, home: home)
            }
            let lanes = try await fetchUsage(credentials: credentials)
            await cache.store(lanes, at: nowDate)
            return lanes
        } catch {
            // Rate-limited / transient: hold the last good value instead of
            // letting the caller drop to the unreliable per-window statusline.
            if let preserved = await cache.fresh(within: stalePreserveTTL, now: nowDate) { return preserved }
            throw error
        }
    }

    /// Cache + preserve path without disk access — used by tests and reusable by
    /// callers that already hold credentials.
    public func fetchUsageCached(credentials: ClaudeCredentials) async throws -> [UsageSnapshot] {
        let nowDate = now()
        if let recent = await cache.fresh(within: minRefetchInterval, now: nowDate) { return recent }
        do {
            let lanes = try await fetchUsage(credentials: credentials)
            await cache.store(lanes, at: nowDate)
            return lanes
        } catch {
            if let preserved = await cache.fresh(within: stalePreserveTTL, now: nowDate) { return preserved }
            throw error
        }
    }
}
