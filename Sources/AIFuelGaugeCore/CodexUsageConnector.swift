import Foundation

public enum CodexUsageConnectorError: Error, Equatable {
    case missingAuthFile
    case invalidAuthFile
    case missingAccessToken
    case missingRefreshToken
    case refreshFailed
    case usageRequestFailed
    case invalidUsageResponse
}

public struct CodexUsageConnector: Sendable {
    private let authURL: URL
    private let usageURL: URL
    private let tokenURL: URL
    private let clientID: String
    private let now: @Sendable () -> Date

    public init(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json"),
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!,
        tokenURL: URL = URL(string: "https://auth.openai.com/oauth/token")!,
        clientID: String = "app_EMoamEEZ73f0CkXaXp7hrann",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authURL = authURL
        self.usageURL = usageURL
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.now = now
    }

    public func fetchUsage() async throws -> [UsageSnapshot] {
        let auth = try readAuth()
        do {
            let data = try await fetchUsageData(accessToken: auth.accessToken, accountID: auth.accountID)
            if let snapshots = try? CodexUsageResponseParser(now: now).parse(
                data: data,
                accountID: auth.accountID,
                identityHint: auth.identityHint
            ), !snapshots.isEmpty {
                return snapshots
            }
        } catch {
            // A stale Codex OAuth access token commonly shows up as 401/403.
            // Refresh once and retry before falling back to local session logs.
        }

        let refreshed = try await refreshAccessToken(refreshToken: auth.refreshToken)
        // Persist the rotated token back to auth.json (preserving all other
        // fields) so we and the Codex CLI stay in sync — OpenAI rotates refresh
        // tokens, so discarding the new one would break the next CLI refresh.
        persistRefreshedTokens(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken)
        let refreshedData = try await fetchUsageData(accessToken: refreshed.accessToken, accountID: auth.accountID)
        return try CodexUsageResponseParser(now: now).parse(
            data: refreshedData,
            accountID: auth.accountID,
            identityHint: auth.identityHint
        )
    }

    private func persistRefreshedTokens(accessToken: String, refreshToken: String?) {
        guard let existing = try? Data(contentsOf: authURL),
              let merged = try? CodexAuthWriter.merge(
                existing: existing,
                accessToken: accessToken,
                refreshToken: refreshToken,
                lastRefresh: now()
              ) else { return }
        let tmp = authURL.deletingLastPathComponent()
            .appendingPathComponent("auth.json.tmp-\(UUID().uuidString)")
        guard (try? merged.write(to: tmp, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try? FileManager.default.replaceItemAt(authURL, withItemAt: tmp)
    }

    private func readAuth() throws -> CodexAuth {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw CodexUsageConnectorError.missingAuthFile
        }
        let data = try Data(contentsOf: authURL)
        let auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        guard let accessToken = auth.tokens.access_token, !accessToken.isEmpty else {
            throw CodexUsageConnectorError.missingAccessToken
        }
        guard let refreshToken = auth.tokens.refresh_token, !refreshToken.isEmpty else {
            throw CodexUsageConnectorError.missingRefreshToken
        }
        return CodexAuth(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountID: auth.tokens.account_id ?? "",
            identityHint: Self.identityHint(fromIDToken: auth.tokens.id_token)
        )
    }

    private func fetchUsageData(accessToken: String, accountID: String) async throws -> Data {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CodexUsageConnectorError.usageRequestFailed
        }
        return data
    }

    private func refreshAccessToken(refreshToken: String) async throws -> (accessToken: String, refreshToken: String?) {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        request.httpBody = body
            .map { key, value in "\(Self.percentEncode(key))=\(Self.percentEncode(value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CodexUsageConnectorError.refreshFailed
        }
        let token = try JSONDecoder().decode(CodexRefreshResponse.self, from: data)
        return (token.access_token, token.refresh_token)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func identityHint(fromIDToken token: String?) -> String? {
        guard let token else { return nil }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = object["email"] as? String else {
            return nil
        }
        return maskEmail(email)
    }

    private static func maskEmail(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let atIndex = trimmed.firstIndex(of: "@"), atIndex > trimmed.startIndex else { return nil }
        let local = String(trimmed[..<atIndex])
        let domain = String(trimmed[trimmed.index(after: atIndex)...])
        guard !domain.isEmpty else { return nil }
        let first = local.first.map(String.init) ?? ""
        let suffix = local.count > 2 ? String(local.suffix(1)) : ""
        return "\(first)***\(suffix)@\(domain)"
    }
}

public struct CodexUsageResponseParser: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func parse(data: Data, accountID: String? = nil, identityHint: String? = nil) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        let generatedAt = now()
        let account = Self.account(plan: response.plan_type, accountID: accountID, identityHint: identityHint)
        var snapshots: [UsageSnapshot] = []

        if let primary = response.rate_limit?.primary_window {
            snapshots.append(snapshot(for: primary, label: Self.windowLabel(seconds: primary.limit_window_seconds, fallback: "5h"), account: account, generatedAt: generatedAt))
        }
        if let secondary = response.rate_limit?.secondary_window {
            snapshots.append(snapshot(for: secondary, label: Self.windowLabel(seconds: secondary.limit_window_seconds, fallback: "Weekly"), account: account, generatedAt: generatedAt))
        }
        for item in response.additional_rate_limits ?? [] {
            guard let prefix = Self.additionalLimitDisplayName(item.limit_name) else { continue }
            if let primary = item.rate_limit?.primary_window, Self.shouldShowAdditional(window: primary, limit: item.rate_limit) {
                let window = Self.windowLabel(seconds: primary.limit_window_seconds, fallback: "5h")
                snapshots.append(snapshot(for: primary, label: "\(prefix) · \(window)", account: account, generatedAt: generatedAt))
            }
            if let secondary = item.rate_limit?.secondary_window, Self.shouldShowAdditional(window: secondary, limit: item.rate_limit) {
                let window = Self.windowLabel(seconds: secondary.limit_window_seconds, fallback: "Weekly")
                snapshots.append(snapshot(for: secondary, label: "\(prefix) · \(window)", account: account, generatedAt: generatedAt))
            }
        }

        guard !snapshots.isEmpty else { throw CodexUsageConnectorError.invalidUsageResponse }
        return snapshots
    }

    private static func shouldShowAdditional(window: CodexUsageWindow, limit: CodexRateLimitResponse?) -> Bool {
        window.used_percent > 0 || limit?.limit_reached == true
    }

    private static func additionalLimitDisplayName(_ rawName: String?) -> String? {
        guard let rawName else { return nil }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.localizedCaseInsensitiveContains("spark") { return "Spark" }
        if trimmed.localizedCaseInsensitiveContains("codex"),
           let last = trimmed.split(separator: "-").last {
            return "\(last) model"
        }
        return trimmed
    }

    /// Labels a window by its length so the name reflects the real reset cadence
    /// rather than its position in the response. Falls back to the positional
    /// name when the API omits `limit_window_seconds`.
    static func windowLabel(seconds: Int?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        if seconds <= 6 * 3600 { return "5h" }
        if seconds >= 6 * 24 * 3600 { return "Weekly" }
        if seconds % (24 * 3600) == 0 { return "\(seconds / (24 * 3600))d" }
        return "\(max(1, seconds / 3600))h"
    }

    private func snapshot(for window: CodexUsageWindow, label: String, account: UsageAccount, generatedAt: Date) -> UsageSnapshot {
        let secondsRemaining: TimeInterval
        if let resetAfterSeconds = window.reset_after_seconds {
            secondsRemaining = TimeInterval(resetAfterSeconds)
        } else if let resetAt = window.reset_at {
            secondsRemaining = max(0, TimeInterval(resetAt) - generatedAt.timeIntervalSince1970)
        } else {
            secondsRemaining = 0
        }

        return UsageSnapshot(
            provider: .codex,
            source: .experimentalWebSession,
            account: account,
            label: label,
            used: .percent(window.used_percent),
            limit: .percent(100),
            reset: secondsRemaining > 0 ? .rollingWindow(secondsRemaining: secondsRemaining) : nil,
            confidence: .exact,
            updatedAt: generatedAt
        )
    }

    private static func account(plan: String?, accountID: String?, identityHint: String?) -> UsageAccount {
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedIdentityHint = identityHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identifier = trimmedAccountID.isEmpty ? "codex-account" : "codex-\(stableHash(trimmedAccountID))"
        return UsageAccount(
            identifier: identifier,
            displayName: "Codex",
            plan: displayPlan(for: plan),
            identityHint: trimmedIdentityHint.isEmpty ? nil : trimmedIdentityHint
        )
    }

    private static func displayPlan(for rawPlan: String?) -> String? {
        guard let rawPlan else { return nil }
        let normalized = rawPlan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "pro", "prolite":
            return "Pro"
        case "plus":
            return "Plus"
        case "free":
            return "Free"
        case "team", "teams":
            return "Team"
        case "business":
            return "Business"
        case "enterprise":
            return "Enterprise"
        default:
            return rawPlan
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
                .joined(separator: " ")
        }
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct CodexAuth {
    let accessToken: String
    let refreshToken: String
    let accountID: String
    let identityHint: String?
}

private struct CodexAuthFile: Decodable {
    let tokens: CodexAuthTokens
}

private struct CodexAuthTokens: Decodable {
    let id_token: String?
    let access_token: String?
    let refresh_token: String?
    let account_id: String?
}

private struct CodexRefreshResponse: Decodable {
    let access_token: String
    let refresh_token: String?
}

/// Merges refreshed Codex tokens into the existing `auth.json` contents,
/// preserving every other field (auth_mode, OPENAI_API_KEY, …) so a write-back
/// never drops data the Codex CLI relies on.
public enum CodexAuthWriter {
    public static func merge(existing: Data, accessToken: String, refreshToken: String?, lastRefresh: Date) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
            throw CodexUsageConnectorError.invalidAuthFile
        }
        var tokens = (object["tokens"] as? [String: Any]) ?? [:]
        tokens["access_token"] = accessToken
        if let refreshToken { tokens["refresh_token"] = refreshToken }
        object["tokens"] = tokens
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        object["last_refresh"] = iso.string(from: lastRefresh)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

private struct CodexUsageResponse: Decodable {
    let plan_type: String?
    let rate_limit: CodexRateLimitResponse?
    let additional_rate_limits: [CodexAdditionalRateLimit]?
}

private struct CodexAdditionalRateLimit: Decodable {
    let limit_name: String?
    let rate_limit: CodexRateLimitResponse?
}

private struct CodexRateLimitResponse: Decodable {
    let allowed: Bool?
    let limit_reached: Bool?
    let primary_window: CodexUsageWindow?
    let secondary_window: CodexUsageWindow?
}

private struct CodexUsageWindow: Decodable {
    let used_percent: Double
    let limit_window_seconds: Int?
    let reset_after_seconds: Int?
    let reset_at: Double?
}
