import Foundation

public final class OpenAIConnector {
    private let transport: HTTPTransport
    private let baseURL: URL
    private let now: () -> Date
    private let calendar: Calendar
    private let decoder = JSONDecoder()

    public init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL = URL(string: "https://api.openai.com/v1/organization")!,
        calendar: Calendar = Calendar(identifier: .gregorian),
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.calendar = calendar
        self.now = now
    }

    public func fetchCurrentMonthCosts(adminKey: String) async throws -> UsageSnapshot {
        let response: OpenAICostsEnvelope = try await get(
            path: "costs",
            adminKey: adminKey,
            query: currentMonthQuery(limit: 31)
        )
        let total = response.data
            .flatMap(\.results)
            .filter { $0.amount.currency.lowercased() == "usd" }
            .reduce(0) { $0 + $1.amount.value }
        return UsageSnapshot(
            provider: .openAI,
            source: .officialAPI,
            label: "Current month costs",
            used: .usd(total),
            limit: nil,
            reset: currentMonthReset(),
            confidence: .exact,
            updatedAt: now()
        )
    }

    public func fetchCurrentMonthCompletionsUsage(adminKey: String) async throws -> UsageSnapshot {
        let response: OpenAICompletionsUsageEnvelope = try await get(
            path: "usage/completions",
            adminKey: adminKey,
            query: currentMonthQuery(limit: 31)
        )
        let totals = response.data
            .flatMap(\.results)
            .reduce((input: 0, output: 0, cacheRead: 0)) { partial, result in
                (
                    input: partial.input + result.input_tokens,
                    output: partial.output + result.output_tokens,
                    cacheRead: partial.cacheRead + result.input_cached_tokens
                )
            }
        return UsageSnapshot(
            provider: .openAI,
            source: .officialAPI,
            label: "Current month tokens",
            used: .tokens(input: totals.input, output: totals.output, cacheRead: totals.cacheRead, cacheWrite: 0),
            limit: nil,
            reset: currentMonthReset(),
            confidence: .exact,
            updatedAt: now()
        )
    }

    private func get<T: Decodable>(path: String, adminKey: String, query: [URLQueryItem]) async throws -> T {
        let trimmedKey = adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ConnectorError.emptyAPIKey }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ConnectorError.invalidURL(path)
        }
        components.queryItems = query
        guard let url = components.url else { throw ConnectorError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
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

    private func currentMonthQuery(limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start_time", value: "\(Int(currentMonthStart().timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(now().timeIntervalSince1970))"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
    }

    private func currentMonthStart() -> Date {
        calendar.dateInterval(of: .month, for: now())?.start ?? now()
    }

    private func currentMonthReset() -> ResetInfo? {
        guard let interval = calendar.dateInterval(of: .month, for: now()) else { return nil }
        return .fixed(interval.end)
    }
}

public enum OpenAISetupCheck {
    public static func successMessage(costs: UsageSnapshot, tokens: UsageSnapshot?) -> String {
        var parts = ["OpenAI Admin key works."]
        if case .usd(let value) = costs.used {
            parts.append("Month cost is $\(String(format: "%.2f", value)).")
        }
        if let tokens, case let .tokens(input, output, cacheRead, cacheWrite) = tokens.used {
            let total = input + output + cacheRead + cacheWrite
            parts.append("Usage API returned \(compact(total)) tokens.")
        }
        return parts.joined(separator: " ")
    }

    public static func failureMessage(error: Error) -> String {
        switch error {
        case ConnectorError.emptyAPIKey:
            return "Paste an OpenAI Admin key before testing."
        case ConnectorError.badStatus(let status):
            return "OpenAI rejected the Admin key or request (HTTP \(status)). Use an organization Admin key with Usage API access."
        default:
            return "OpenAI test failed. Check the key, network, or organization permissions."
        }
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
        if absValue >= 1_000 {
            return sign + String(format: "%.1fK", Double(absValue) / 1_000)
        }
        return "\(value)"
    }
}

private struct OpenAICostsEnvelope: Decodable {
    let data: [OpenAICostBucket]
}

private struct OpenAICostBucket: Decodable {
    let results: [OpenAICostResult]
}

private struct OpenAICostResult: Decodable {
    let amount: OpenAICostAmount
}

private struct OpenAICostAmount: Decodable {
    let value: Double
    let currency: String
}

private struct OpenAICompletionsUsageEnvelope: Decodable {
    let data: [OpenAICompletionsUsageBucket]
}

private struct OpenAICompletionsUsageBucket: Decodable {
    let results: [OpenAICompletionsUsageResult]
}

private struct OpenAICompletionsUsageResult: Decodable {
    let input_tokens: Int
    let output_tokens: Int
    let input_cached_tokens: Int

    private enum CodingKeys: String, CodingKey {
        case input_tokens
        case output_tokens
        case input_cached_tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input_tokens = try container.decodeIfPresent(Int.self, forKey: .input_tokens) ?? 0
        output_tokens = try container.decodeIfPresent(Int.self, forKey: .output_tokens) ?? 0
        input_cached_tokens = try container.decodeIfPresent(Int.self, forKey: .input_cached_tokens) ?? 0
    }
}
