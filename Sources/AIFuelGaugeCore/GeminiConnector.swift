import Foundation

// NOTE: Built against the documented Gemini Code Assist shape but NOT yet
// verified against a live account (no ~/.gemini/oauth_creds.json on the dev
// machine). Shipped behind a default-OFF toggle until verified.

// MARK: - Credentials

public struct GeminiCredentials: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    /// Expiry as milliseconds since epoch, as the Gemini CLI stores it.
    public let expiryDateMillis: Double?

    public init(accessToken: String, refreshToken: String?, expiryDateMillis: Double?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiryDateMillis = expiryDateMillis
    }

    /// Unknown expiry → assume usable (the call will 401 if it's actually dead).
    public func isExpired(now: Date, skew: TimeInterval = 60) -> Bool {
        guard let expiryDateMillis else { return false }
        return now.timeIntervalSince1970 >= (expiryDateMillis / 1000.0) - skew
    }
}

public enum GeminiCredentialsReader {
    private struct File: Decodable {
        let access_token: String
        let refresh_token: String?
        let expiry_date: Double?
    }

    public static func credentialsURL(home: URL) -> URL {
        home.appendingPathComponent(".gemini/oauth_creds.json")
    }

    public static func parse(fileData: Data) throws -> GeminiCredentials {
        let file = try JSONDecoder().decode(File.self, from: fileData)
        return GeminiCredentials(
            accessToken: file.access_token,
            refreshToken: file.refresh_token,
            expiryDateMillis: file.expiry_date
        )
    }

    public static func loadFromDisk(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> GeminiCredentials? {
        guard let data = try? Data(contentsOf: credentialsURL(home: home)) else { return nil }
        return try? parse(fileData: data)
    }
}

// MARK: - Quota parser

/// Maps the Code Assist `retrieveUserQuota` response (per-model remaining
/// fraction + reset time) into exact `UsageSnapshot` lanes.
public enum GeminiQuotaParser {
    private struct Bucket: Decodable {
        let modelId: String?
        let remainingFraction: Double?
        let resetTime: String?
    }
    private struct Response: Decodable {
        let buckets: [Bucket]?
    }

    public static func parse(data: Data, tier: String?, now: Date) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let buckets = response.buckets ?? []
        // Keep the tightest (lowest remaining) bucket per model.
        var lowestByModel: [String: Bucket] = [:]
        for bucket in buckets {
            guard let model = bucket.modelId, let fraction = bucket.remainingFraction else { continue }
            if let existing = lowestByModel[model], (existing.remainingFraction ?? 1) <= fraction { continue }
            lowestByModel[model] = bucket
        }
        let plan = planLabel(tier)
        let account = UsageAccount(identifier: "gemini-oauth", displayName: "Gemini", plan: plan)
        // Stable display order: Pro, Flash, Flash-Lite, then anything else.
        func rank(_ id: String?) -> Int {
            let lower = id?.lowercased() ?? ""
            if lower.contains("flash-lite") { return 2 }
            if lower.contains("flash") { return 1 }
            if lower.contains("pro") { return 0 }
            return 3
        }
        let sorted = lowestByModel.values.sorted { rank($0.modelId) < rank($1.modelId) }
        return sorted.compactMap { bucket in
            guard let model = bucket.modelId, let fraction = bucket.remainingFraction else { return nil }
            let usedPercent = min(max((1 - fraction) * 100, 0), 100)
            return UsageSnapshot(
                provider: .gemini,
                source: .officialAPI,
                account: account,
                label: modelLabel(model),
                used: .percent(usedPercent),
                limit: .percent(100),
                reset: bucket.resetTime.flatMap(ISO8601Tolerant.date).map { .fixed($0) },
                confidence: .exact,
                updatedAt: now
            )
        }
    }

    static func modelLabel(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower.contains("flash-lite") { return "Flash-Lite" }
        if lower.contains("flash") { return "Flash" }
        if lower.contains("pro") { return "Pro" }
        return modelId
    }

    static func planLabel(_ tier: String?) -> String? {
        guard let tier = tier?.lowercased() else { return nil }
        if tier.contains("free") { return "Free" }
        if tier.contains("standard") { return "Paid" }
        if tier.contains("legacy") { return "Legacy" }
        if tier.contains("enterprise") { return "Enterprise" }
        return nil
    }
}

// MARK: - Connector

public final class GeminiConnector {
    private let transport: HTTPTransport
    private let quotaURL: URL
    private let tierURL: URL
    private let now: () -> Date

    public init(
        transport: HTTPTransport = URLSession.shared,
        quotaURL: URL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!,
        tierURL: URL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.quotaURL = quotaURL
        self.tierURL = tierURL
        self.now = now
    }

    private struct TierResponse: Decodable {
        struct Tier: Decodable { let id: String? }
        let currentTier: Tier?
    }

    public func fetchUsage(credentials: GeminiCredentials) async throws -> [UsageSnapshot] {
        let tier = try? await fetchTier(accessToken: credentials.accessToken)
        let quotaData = try await post(url: quotaURL, accessToken: credentials.accessToken, body: Data("{}".utf8))
        return try GeminiQuotaParser.parse(data: quotaData, tier: tier, now: now())
    }

    public func fetchUsageFromLocalCredentials(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async throws -> [UsageSnapshot] {
        guard let credentials = GeminiCredentialsReader.loadFromDisk(home: home) else { return [] }
        // Token-while-valid: a stale token surfaces as a soft failure upstream.
        // (Refresh would require extracting the gemini-cli client secret; left
        // for a verified follow-up.)
        guard !credentials.isExpired(now: now()) else { return [] }
        return try await fetchUsage(credentials: credentials)
    }

    private func fetchTier(accessToken: String) async throws -> String? {
        let body = Data(#"{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}"#.utf8)
        let data = try await post(url: tierURL, accessToken: accessToken, body: body)
        return (try? JSONDecoder().decode(TierResponse.self, from: data))?.currentTier?.id
    }

    private func post(url: URL, accessToken: String, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.badStatus(http.statusCode) }
        return data
    }
}
