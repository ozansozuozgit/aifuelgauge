import Foundation

public protocol HTTPTransport: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

public enum ConnectorError: Error, Equatable, LocalizedError {
    case invalidURL(String)
    case badStatus(Int)
    case emptyAPIKey

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): "Invalid URL: \(value)"
        case .badStatus(let status): "Provider returned HTTP \(status)"
        case .emptyAPIKey: "API key is empty"
        }
    }
}

public final class OpenRouterConnector {
    private let transport: HTTPTransport
    private let baseURL: URL
    private let now: () -> Date
    private let decoder = JSONDecoder()

    public init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.now = now
    }

    public func fetchCurrentKeyUsage(apiKey: String) async throws -> UsageSnapshot {
        let response: OpenRouterKeyEnvelope = try await get(path: "key", apiKey: apiKey)
        let key = response.data
        let usedCredits = key.limit == nil ? key.usage_monthly : key.usage_monthly
        return UsageSnapshot(
            provider: .openRouter,
            source: .officialAPI,
            label: key.label.isEmpty ? "OpenRouter key" : key.label,
            used: .credits(usedCredits),
            limit: key.limit.map { .credits($0) },
            reset: nil,
            confidence: .exact,
            updatedAt: now()
        )
    }

    public func fetchAccountCredits(apiKey: String) async throws -> UsageSnapshot {
        let response: OpenRouterCreditsEnvelope = try await get(path: "credits", apiKey: apiKey)
        return UsageSnapshot(
            provider: .openRouter,
            source: .officialAPI,
            label: "OpenRouter credits",
            used: .credits(response.data.total_usage),
            limit: .credits(response.data.total_credits),
            reset: nil,
            confidence: .exact,
            updatedAt: now()
        )
    }

    private func get<T: Decodable>(path: String, apiKey: String) async throws -> T {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ConnectorError.emptyAPIKey }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.badStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectorError.badStatus(httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct OpenRouterKeyEnvelope: Decodable {
    let data: OpenRouterKeyData
}

private struct OpenRouterKeyData: Decodable {
    let label: String
    let limit: Double?
    let limit_reset: String?
    let limit_remaining: Double?
    let include_byok_in_limit: Bool
    let usage: Double
    let usage_daily: Double
    let usage_weekly: Double
    let usage_monthly: Double
    let byok_usage: Double
    let byok_usage_daily: Double
    let byok_usage_weekly: Double
    let byok_usage_monthly: Double
    let is_free_tier: Bool
}

private struct OpenRouterCreditsEnvelope: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let total_credits: Double
    let total_usage: Double
}
