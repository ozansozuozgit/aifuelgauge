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
            if let snapshots = try? CodexUsageResponseParser(now: now).parse(data: data), !snapshots.isEmpty {
                return snapshots
            }
        } catch {
            // A stale Codex OAuth access token commonly shows up as 401/403.
            // Refresh once and retry before falling back to local session logs.
        }

        let refreshedToken = try await refreshAccessToken(refreshToken: auth.refreshToken)
        let refreshedData = try await fetchUsageData(accessToken: refreshedToken, accountID: auth.accountID)
        return try CodexUsageResponseParser(now: now).parse(data: refreshedData)
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
            accountID: auth.tokens.account_id ?? ""
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

    private func refreshAccessToken(refreshToken: String) async throws -> String {
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
        return token.access_token
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public struct CodexUsageResponseParser: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func parse(data: Data) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        let generatedAt = now()
        var snapshots: [UsageSnapshot] = []

        if let primary = response.rate_limit?.primary_window {
            snapshots.append(snapshot(for: primary, label: "5h", plan: response.plan_type, generatedAt: generatedAt))
        }
        if let secondary = response.rate_limit?.secondary_window {
            snapshots.append(snapshot(for: secondary, label: "Weekly", plan: response.plan_type, generatedAt: generatedAt))
        }
        for item in response.additional_rate_limits ?? [] {
            guard let prefix = Self.additionalLimitDisplayName(item.limit_name) else { continue }
            if let primary = item.rate_limit?.primary_window, Self.shouldShowAdditional(window: primary, limit: item.rate_limit) {
                snapshots.append(snapshot(for: primary, label: [prefix, "5h"].compactMap { $0 }.joined(separator: " · "), plan: response.plan_type, generatedAt: generatedAt))
            }
            if let secondary = item.rate_limit?.secondary_window, Self.shouldShowAdditional(window: secondary, limit: item.rate_limit) {
                snapshots.append(snapshot(for: secondary, label: [prefix, "Weekly"].compactMap { $0 }.joined(separator: " · "), plan: response.plan_type, generatedAt: generatedAt))
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
        if trimmed.localizedCaseInsensitiveContains("codex"),
           let last = trimmed.split(separator: "-").last {
            return "\(last) model"
        }
        return trimmed
    }

    private func snapshot(for window: CodexUsageWindow, label: String, plan: String?, generatedAt: Date) -> UsageSnapshot {
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
            account: UsageAccount(identifier: "codex-account", displayName: "Codex", plan: Self.displayPlan(for: plan)),
            label: label,
            used: .percent(window.used_percent),
            limit: .percent(100),
            reset: secondsRemaining > 0 ? .rollingWindow(secondsRemaining: secondsRemaining) : nil,
            confidence: .exact,
            updatedAt: generatedAt
        )
    }

    private static func displayPlan(for rawPlan: String?) -> String? {
        guard let rawPlan else { return nil }
        let normalized = rawPlan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "pro", "prolite", "plus":
            return "Pro"
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
}

private struct CodexAuth {
    let accessToken: String
    let refreshToken: String
    let accountID: String
}

private struct CodexAuthFile: Decodable {
    let tokens: CodexAuthTokens
}

private struct CodexAuthTokens: Decodable {
    let access_token: String?
    let refresh_token: String?
    let account_id: String?
}

private struct CodexRefreshResponse: Decodable {
    let access_token: String
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
