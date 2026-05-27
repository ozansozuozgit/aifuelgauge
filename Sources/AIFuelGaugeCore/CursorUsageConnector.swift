import Foundation

public enum CursorUsageConnectorError: Error, Equatable {
    case missingAccountState
    case missingAccessToken
    case usageRequestFailed
    case invalidUsageResponse
}

public final class CursorUsageConnector {
    private let accountStateReader: CursorAccountStateReader
    private let planPreferences: LocalPlanPreferences
    private let transport: HTTPTransport
    private let usageURL: URL
    private let now: @Sendable () -> Date

    public init(
        cursorDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor"),
        fileManager: FileManager = .default,
        planPreferences: LocalPlanPreferences = LocalPlanPreferences(),
        transport: HTTPTransport = URLSession.shared,
        usageURL: URL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountStateReader = CursorAccountStateReader(cursorDirectory: cursorDirectory, fileManager: fileManager)
        self.planPreferences = planPreferences
        self.transport = transport
        self.usageURL = usageURL
        self.now = now
    }

    public func fetchUsage() async throws -> [UsageSnapshot] {
        guard let state = accountStateReader.read() else {
            throw CursorUsageConnectorError.missingAccountState
        }
        guard let accessToken = state.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty else {
            throw CursorUsageConnectorError.missingAccessToken
        }

        var request = URLRequest(url: usageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("desktop", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("AI Fuel Gauge", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CursorUsageConnectorError.usageRequestFailed
        }
        let plan = planPreferences.cursorPlanOverride ?? state.displayPlan
        return try CursorUsageResponseParser(now: now).parse(data: data, plan: plan)
    }
}

public struct CursorUsageResponseParser: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func parse(data: Data, plan: String?) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        guard let planUsage = response.planUsage else {
            throw CursorUsageConnectorError.invalidUsageResponse
        }

        let generatedAt = now()
        let reset = response.billingCycleEnd.date.map(ResetInfo.fixed)
        let account = UsageAccount(identifier: "cursor-account", displayName: "Cursor", plan: normalizedPlan(plan))

        var snapshots: [UsageSnapshot] = []
        snapshots.append(contentsOf: snapshot(
            account: account,
            label: "Included total",
            percentUsed: planUsage.totalPercentUsed,
            reset: reset,
            updatedAt: generatedAt
        ))
        snapshots.append(contentsOf: snapshot(
            account: account,
            label: "API usage",
            percentUsed: planUsage.apiPercentUsed,
            reset: reset,
            updatedAt: generatedAt
        ))
        snapshots.append(contentsOf: snapshot(
            account: account,
            label: "Auto usage",
            percentUsed: planUsage.autoPercentUsed,
            reset: reset,
            updatedAt: generatedAt
        ))

        guard !snapshots.isEmpty else { throw CursorUsageConnectorError.invalidUsageResponse }
        return snapshots
    }

    private func snapshot(
        account: UsageAccount,
        label: String,
        percentUsed: Double?,
        reset: ResetInfo?,
        updatedAt: Date
    ) -> [UsageSnapshot] {
        guard let percentUsed, percentUsed.isFinite else { return [] }
        return [
            UsageSnapshot(
                provider: .cursor,
                source: .experimentalWebSession,
                account: account,
                label: label,
                used: .percent(max(0, percentUsed)),
                limit: .percent(100),
                reset: reset,
                confidence: .exact,
                updatedAt: updatedAt
            )
        ]
    }

    private func normalizedPlan(_ plan: String?) -> String? {
        let trimmed = plan?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CursorUsageResponse: Decodable {
    let billingCycleEnd: CursorFlexibleMilliseconds
    let planUsage: CursorPlanUsage?
}

private struct CursorPlanUsage: Decodable {
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

private struct CursorFlexibleMilliseconds: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self),
           let milliseconds = Double(string) {
            self.date = Date(timeIntervalSince1970: milliseconds / 1000)
            return
        }
        if let milliseconds = try? container.decode(Double.self) {
            self.date = Date(timeIntervalSince1970: milliseconds / 1000)
            return
        }
        self.date = nil
    }
}
