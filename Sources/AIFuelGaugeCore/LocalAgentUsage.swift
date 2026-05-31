import Foundation
import SQLite3

public enum LocalAgentSourceKind: String, Codable, Equatable, Hashable {
    case jsonlDirectory
    case directory
    case sqliteDatabase
}

public struct LocalAgentSource: Codable, Equatable, Hashable {
    public let provider: Provider
    public let kind: LocalAgentSourceKind
    public let url: URL

    public init(provider: Provider, kind: LocalAgentSourceKind, url: URL) {
        self.provider = provider
        self.kind = kind
        self.url = url
    }
}

public struct LocalAgentDetector {
    private let homeDirectory: URL
    private let fileManager: FileManager

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func detectedSources() -> [LocalAgentSource] {
        let candidates: [LocalAgentSource] = [
            LocalAgentSource(
                provider: .claudeCode,
                kind: .jsonlDirectory,
                url: homeDirectory.appendingPathComponent(".claude/projects")
            ),
            LocalAgentSource(
                provider: .codex,
                kind: .jsonlDirectory,
                url: homeDirectory.appendingPathComponent(".codex/sessions")
            ),
            LocalAgentSource(
                provider: .openCode,
                kind: .sqliteDatabase,
                url: homeDirectory.appendingPathComponent(".local/share/opencode/opencode.db")
            ),
            LocalAgentSource(
                provider: .cursor,
                kind: .directory,
                url: homeDirectory.appendingPathComponent("Library/Application Support/Cursor")
            )
        ]
        return candidates.filter { source in
            switch source.kind {
            case .jsonlDirectory, .directory:
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: source.url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            case .sqliteDatabase:
                return fileManager.fileExists(atPath: source.url.path)
            }
        }
    }
}

public struct LocalAgentSourceFingerprint: Equatable, Sendable {
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }
}

public struct LocalAgentSourceMonitor {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let maxFingerprintFiles = 2_000

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func fingerprint() -> LocalAgentSourceFingerprint {
        LocalAgentSourceFingerprint(values: [
            "claude-projects": directoryStamp(homeDirectory.appendingPathComponent(".claude/projects"), allowedExtensions: ["jsonl"]),
            "claude-statusline": fileStamp(homeDirectory.appendingPathComponent("Library/Application Support/AI Fuel Gauge/claude-statusline.json")),
            "codex-sessions": directoryStamp(homeDirectory.appendingPathComponent(".codex/sessions"), allowedExtensions: ["jsonl"]),
            "codex-auth": fileStamp(homeDirectory.appendingPathComponent(".codex/auth.json")),
            "cursor-state": fileStamp(homeDirectory.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")),
            "opencode-db": fileStamp(homeDirectory.appendingPathComponent(".local/share/opencode/opencode.db"))
        ])
    }

    private func fileStamp(_ url: URL) -> String {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return "missing"
        }
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        return "file:\(Int(modifiedAt * 1_000)):\(size)"
    }

    private func directoryStamp(_ url: URL, allowedExtensions: Set<String>) -> String {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "missing"
        }
        let rootModifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        ) else {
            return "dir:\(Int(rootModifiedAt * 1_000)):0:0"
        }

        var count = 0
        var totalSize = 0
        var newestModifiedAt = rootModifiedAt
        var truncated = false
        for item in enumerator {
            guard let fileURL = item as? URL else { break }
            if !allowedExtensions.isEmpty, !allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            if count >= maxFingerprintFiles {
                truncated = true
                break
            }
            count += 1
            totalSize += values.fileSize ?? 0
            newestModifiedAt = max(newestModifiedAt, values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
        return "dir:\(Int(newestModifiedAt * 1_000)):\(count):\(totalSize):\(truncated ? "truncated" : "complete")"
    }
}

public enum LocalUsageParseError: Error, Equatable {
    case noUsageFound
}

public struct LocalPlanPreferences: Equatable, Sendable {
    public let claudeCodePlan: String?
    public let cursorPlanOverride: String?

    public init(claudeCodePlan: String? = nil, cursorPlanOverride: String? = nil) {
        self.claudeCodePlan = Self.normalized(claudeCodePlan)
        self.cursorPlanOverride = Self.normalized(cursorPlanOverride)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ClaudeAccountState: Equatable, Sendable {
    public let organizationType: String?
    public let organizationRateLimitTier: String?
    public let email: String?
    public let updatedAt: Date

    public init(organizationType: String?, organizationRateLimitTier: String? = nil, email: String?, updatedAt: Date) {
        self.organizationType = organizationType
        self.organizationRateLimitTier = organizationRateLimitTier
        self.email = email
        self.updatedAt = updatedAt
    }

    public var displayPlan: String? {
        let normalizedTier = organizationRateLimitTier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalizedTier.contains("max") && normalizedTier.contains("20") {
            return "Max 20x"
        }
        if normalizedTier.contains("max") && normalizedTier.contains("5") {
            return "Max 5x"
        }

        guard let organizationType else { return nil }
        let normalized = organizationType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "claude_free", "free":
            return "Free"
        case "claude_pro", "pro":
            return "Pro"
        case "claude_max", "max":
            return "Max"
        case let value where value.contains("max") && value.contains("20"):
            return "Max 20x"
        case let value where value.contains("max") && value.contains("5"):
            return "Max 5x"
        case "":
            return nil
        default:
            return organizationType
                .replacingOccurrences(of: "claude_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
                .joined(separator: " ")
        }
    }

    public var maskedEmail: String? {
        Self.maskEmail(email)
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

public struct ClaudeAccountStateReader {
    private let homeDirectory: URL
    private let fileManager: FileManager

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func read() -> ClaudeAccountState? {
        let url = homeDirectory.appendingPathComponent(".claude.json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any] else {
            return nil
        }
        let updatedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let state = ClaudeAccountState(
            organizationType: account["organizationType"] as? String,
            organizationRateLimitTier: account["organizationRateLimitTier"] as? String,
            email: account["emailAddress"] as? String,
            updatedAt: updatedAt
        )
        if state.organizationType == nil, state.organizationRateLimitTier == nil, state.email == nil { return nil }
        return state
    }
}

public struct ClaudeJSONLUsageParser {
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func parse(lines: [String], label: String = "Claude Code", account: UsageAccount? = nil) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var foundUsage = false
        var latestTimestamp: Date?

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(ClaudeJSONLEvent.self, from: data),
                  let usage = event.message?.usage else {
                continue
            }
            foundUsage = true
            if let timestamp = LocalTimestampParser.date(from: event.timestamp), latestTimestamp.map({ timestamp > $0 }) ?? true {
                latestTimestamp = timestamp
            }
            input += usage.input_tokens ?? 0
            output += usage.output_tokens ?? 0
            cacheRead += usage.cache_read_input_tokens ?? 0
            cacheWrite += usage.cache_creation_input_tokens ?? 0
        }

        guard foundUsage else { throw LocalUsageParseError.noUsageFound }
        return UsageSnapshot(
            provider: .claudeCode,
            source: .localLogs,
            account: account,
            label: label,
            used: .tokens(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite),
            limit: nil,
            reset: nil,
            confidence: .estimated,
            updatedAt: latestTimestamp ?? now()
        )
    }
}

public struct ClaudeStatusLineUsageReader {
    private let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AI Fuel Gauge/claude-statusline.json"),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    public func read(account: UsageAccount?) -> [UsageSnapshot] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(ClaudeStatusLinePayload.self, from: data) else {
            return []
        }

        let updatedAt = Date(timeIntervalSince1970: payload.updated_at)
        let fiveHour = snapshot(
            label: "5h",
            window: payload.rate_limits?.five_hour,
            account: account,
            updatedAt: updatedAt
        )
        let weekly = snapshot(
            label: "Weekly",
            window: payload.rate_limits?.seven_day,
            account: account,
            updatedAt: updatedAt
        )
        return [fiveHour, weekly].compactMap { $0 }
    }

    private func snapshot(label: String, window: ClaudeStatusLineWindow?, account: UsageAccount?, updatedAt: Date) -> UsageSnapshot? {
        guard let window, let usedPercentage = window.used_percentage, usedPercentage.isFinite else {
            return nil
        }
        let reset = window.resets_at.map { ResetInfo.fixed(Date(timeIntervalSince1970: $0)) }
        return UsageSnapshot(
            provider: .claudeCode,
            source: .localLogs,
            account: account,
            label: label,
            used: .percent(min(max(usedPercentage, 0), 100)),
            limit: .percent(100),
            reset: reset,
            confidence: .exact,
            providerNote: "Captured from Claude Code statusline rate_limits; no prompt text is stored.",
            updatedAt: updatedAt
        )
    }
}

public struct CodexJSONLUsageParser {
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func parseLatestRateLimit(lines: [String], label: String = "Codex") throws -> UsageSnapshot {
        guard let snapshot = try parseRateLimits(lines: lines, primaryFallbackLabel: label).first else {
            throw LocalUsageParseError.noUsageFound
        }
        return snapshot
    }

    public func parseRateLimits(lines: [String], primaryFallbackLabel: String = "Codex") throws -> [UsageSnapshot] {
        let decoder = JSONDecoder()
        var latestPrimary: TimedCodexRateLimit?
        var latestSecondary: TimedCodexRateLimit?

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(CodexJSONLEvent.self, from: data),
                  event.payload.type == "token_count" else {
                continue
            }
            let eventTimestamp = LocalTimestampParser.date(from: event.timestamp) ?? now()
            if let primary = event.payload.rate_limits?.primary {
                let timed = TimedCodexRateLimit(rateLimit: primary, timestamp: eventTimestamp)
                if latestPrimary.map({ eventTimestamp >= $0.timestamp }) ?? true {
                    latestPrimary = timed
                }
            }
            if let secondary = event.payload.rate_limits?.secondary {
                let timed = TimedCodexRateLimit(rateLimit: secondary, timestamp: eventTimestamp)
                if latestSecondary.map({ eventTimestamp >= $0.timestamp }) ?? true {
                    latestSecondary = timed
                }
            }
        }

        let generatedAt = now()
        var snapshots: [UsageSnapshot] = []
        if let latestPrimary {
            snapshots.append(snapshot(for: latestPrimary.rateLimit, label: codexWindowLabel(for: latestPrimary.rateLimit) ?? primaryFallbackLabel, now: generatedAt, updatedAt: latestPrimary.timestamp))
        }
        if let latestSecondary {
            snapshots.append(snapshot(for: latestSecondary.rateLimit, label: codexWindowLabel(for: latestSecondary.rateLimit) ?? "Weekly", now: generatedAt, updatedAt: latestSecondary.timestamp))
        }
        guard !snapshots.isEmpty else { throw LocalUsageParseError.noUsageFound }
        return snapshots
    }

    private func snapshot(for rateLimit: CodexRateLimit, label: String, now generatedAt: Date, updatedAt: Date) -> UsageSnapshot {
        let secondsRemaining = TimeInterval(rateLimit.resets_at) - generatedAt.timeIntervalSince1970
        guard secondsRemaining > 0 else {
            return UsageSnapshot(
                provider: .codex,
                source: .localLogs,
                label: label,
                used: .percent(rateLimit.used_percent),
                limit: nil,
                reset: nil,
                confidence: .unknown,
                updatedAt: updatedAt
            )
        }
        return UsageSnapshot(
            provider: .codex,
            source: .localLogs,
            label: label,
            used: .percent(rateLimit.used_percent),
            limit: .percent(100),
            reset: .rollingWindow(secondsRemaining: secondsRemaining),
            confidence: .exact,
            updatedAt: updatedAt
        )
    }

    private func codexWindowLabel(for rateLimit: CodexRateLimit) -> String? {
        guard let minutes = rateLimit.window_minutes, minutes > 0 else { return nil }
        if minutes == 10_080 { return "Weekly" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

public struct OpenCodeSQLiteUsageParser {
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func parse(databaseURL: URL, label: String = "OpenCode tokens") throws -> UsageSnapshot {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw LocalUsageParseError.noUsageFound
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT
          COUNT(*),
          COALESCE(SUM(json_extract(data, '$.tokens.input')), 0),
          COALESCE(SUM(json_extract(data, '$.tokens.output')), 0),
          COALESCE(SUM(json_extract(data, '$.tokens.cache.read')), 0),
          COALESCE(SUM(json_extract(data, '$.tokens.cache.write')), 0),
          COALESCE(MAX(time_updated), 0)
        FROM message
        WHERE json_type(data, '$.tokens') IS NOT NULL;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw LocalUsageParseError.noUsageFound
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalUsageParseError.noUsageFound
        }
        let rowCount = sqlite3_column_int64(statement, 0)
        guard rowCount > 0 else { throw LocalUsageParseError.noUsageFound }

        let input = Int(sqlite3_column_int64(statement, 1))
        let output = Int(sqlite3_column_int64(statement, 2))
        let cacheRead = Int(sqlite3_column_int64(statement, 3))
        let cacheWrite = Int(sqlite3_column_int64(statement, 4))
        let updatedAt = date(fromOpenCodeTimestamp: sqlite3_column_int64(statement, 5))

        return UsageSnapshot(
            provider: .openCode,
            source: .localLogs,
            label: label,
            used: .tokens(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite),
            limit: nil,
            reset: nil,
            confidence: .estimated,
            updatedAt: updatedAt
        )
    }

    private func date(fromOpenCodeTimestamp timestamp: Int64) -> Date {
        guard timestamp > 0 else { return now() }
        if timestamp > 10_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

public struct LocalUsageCollector {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let planPreferences: LocalPlanPreferences

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        planPreferences: LocalPlanPreferences = LocalPlanPreferences()
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.planPreferences = planPreferences
    }

    public func collect() throws -> [UsageSnapshot] {
        let sources = LocalAgentDetector(homeDirectory: homeDirectory, fileManager: fileManager).detectedSources()
        var snapshots: [UsageSnapshot] = []
        for source in sources {
            switch source.provider {
            case .claudeCode:
                let claudeAccount = ClaudeAccountStateReader(homeDirectory: homeDirectory, fileManager: fileManager).read()
                let plan = planPreferences.claudeCodePlan ?? claudeAccount?.displayPlan
                let account = UsageAccount(
                    identifier: "claude-code-local",
                    displayName: "Claude Code",
                    plan: plan,
                    identityHint: claudeAccount?.maskedEmail
                )
                snapshots.append(contentsOf: ClaudeStatusLineUsageReader(
                    fileURL: homeDirectory.appendingPathComponent("Library/Application Support/AI Fuel Gauge/claude-statusline.json"),
                    fileManager: fileManager,
                    now: now
                ).read(account: account))
                if let snapshot = try? ClaudeJSONLUsageParser(now: now).parse(
                    lines: readJSONLLines(recursivelyUnder: source.url),
                    label: "Claude Code",
                    account: account
                ) {
                    let statusLineScript = homeDirectory.appendingPathComponent(".claude/aifuelgauge-statusline.py")
                    let statusLineCapture = homeDirectory.appendingPathComponent("Library/Application Support/AI Fuel Gauge/claude-statusline.json")
                    if fileManager.fileExists(atPath: statusLineScript.path),
                       !fileManager.fileExists(atPath: statusLineCapture.path) {
                        snapshots.append(snapshot.withProviderNote("Claude exact usage capture is enabled but waiting for Claude Code to run the statusline after an assistant response."))
                    } else {
                        snapshots.append(snapshot)
                    }
                }
            case .codex:
                if let codexSnapshots = try? CodexJSONLUsageParser(now: now).parseRateLimits(lines: readJSONLLines(recursivelyUnder: source.url)) {
                    snapshots.append(contentsOf: codexSnapshots)
                }
            case .openCode:
                if let snapshot = try? OpenCodeSQLiteUsageParser(now: now).parse(databaseURL: source.url) {
                    snapshots.append(snapshot)
                } else {
                    snapshots.append(UsageSnapshot(
                        provider: .openCode,
                        source: .localLogs,
                        label: "OpenCode",
                        used: .tokens(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
                        limit: nil,
                        reset: nil,
                        confidence: .unknown,
                        updatedAt: now()
                    ))
                }
            case .cursor:
                let cursorState = CursorAccountStateReader(cursorDirectory: source.url, fileManager: fileManager).read()
                let plan = planPreferences.cursorPlanOverride ?? cursorState?.displayPlan
                let status = cursorState?.displayStatus
                let updatedAt = cursorState?.updatedAt ?? now()
                snapshots.append(UsageSnapshot(
                    provider: .cursor,
                    source: .localLogs,
                    account: UsageAccount(
                        identifier: "\(cursorState?.stableAccountIdentifier ?? "cursor-account")-local",
                        displayName: "Cursor",
                        plan: plan,
                        identityHint: cursorState?.maskedEmail
                    ),
                    label: status.map { "Subscription \($0)" } ?? "Subscription",
                    used: .requests(0),
                    limit: nil,
                    reset: nil,
                    confidence: .unknown,
                    updatedAt: updatedAt
                ))
            default:
                continue
            }
        }
        return snapshots
    }

    private func readJSONLLines(recursivelyUnder directory: URL) -> [String] {
        let maxFiles = 120
        let maxTotalBytes = 6_000_000
        let maxBytesPerFile = 512_000

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        ) else {
            return []
        }

        var newestFiles: [LocalJSONLFile] = []
        newestFiles.reserveCapacity(maxFiles)
        for item in enumerator {
            guard let fileURL = item as? URL, fileURL.pathExtension == "jsonl" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            newestFiles.append(LocalJSONLFile(
                url: fileURL,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                byteSize: values.fileSize ?? 0
            ))
            if newestFiles.count > maxFiles * 2 {
                newestFiles.sort { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
                newestFiles.removeSubrange(maxFiles...)
            }
        }
        let files = newestFiles
            .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
            .prefix(maxFiles)

        var lines: [String] = []
        var bytesRead = 0
        for file in files {
            guard bytesRead < maxTotalBytes else { break }
            let byteLimit = min(maxBytesPerFile, maxTotalBytes - bytesRead)
            guard let data = readTail(of: file.url, byteLimit: byteLimit), !data.isEmpty else { continue }
            bytesRead += data.count
            guard var contents = String(data: data, encoding: .utf8) else { continue }
            if file.byteSize > data.count, let newline = contents.firstIndex(of: "\n") {
                contents.removeSubrange(contents.startIndex...newline)
            }
            lines.append(contents)
        }
        return lines.flatMap { $0.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
    }

    private func readTail(of fileURL: URL, byteLimit: Int) -> Data? {
        guard byteLimit > 0 else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize = min(UInt64(byteLimit), fileSize)
        try? handle.seek(toOffset: fileSize - readSize)
        return try? handle.readToEnd()
    }
}

public struct CursorAccountState: Equatable, Sendable {
    public let membershipType: String?
    public let subscriptionStatus: String?
    public let email: String?
    public let accessToken: String?
    public let updatedAt: Date

    public init(
        membershipType: String?,
        subscriptionStatus: String?,
        email: String?,
        accessToken: String?,
        updatedAt: Date
    ) {
        self.membershipType = membershipType
        self.subscriptionStatus = subscriptionStatus
        self.email = email
        self.accessToken = accessToken
        self.updatedAt = updatedAt
    }

    public var displayPlan: String? {
        guard let membershipType else { return nil }
        switch membershipType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "free", "hobby":
            return "Free"
        case "pro":
            return "Pro"
        case "pro_plus", "proplus", "pro-plus":
            return "Pro+"
        case "ultra":
            return "Ultra"
        case "team", "teams", "business":
            return "Team"
        case "enterprise":
            return "Enterprise"
        case "":
            return nil
        default:
            return membershipType
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
                .joined(separator: " ")
        }
    }

    public var displayStatus: String? {
        guard let subscriptionStatus else { return nil }
        switch subscriptionStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "active":
            return "active"
        case "trialing":
            return "trial"
        case "canceled", "cancelled":
            return "cancelled"
        case "past_due":
            return "past due"
        case "":
            return nil
        default:
            return subscriptionStatus.replacingOccurrences(of: "_", with: " ")
        }
    }

    public var maskedEmail: String? {
        Self.maskEmail(email)
    }

    public var stableAccountIdentifier: String {
        guard let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !normalized.isEmpty else {
            return "cursor-account"
        }
        return "cursor-\(Self.stableHash(normalized))"
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

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct CursorAccountStateReader {
    private let cursorDirectory: URL
    private let fileManager: FileManager

    public init(cursorDirectory: URL, fileManager: FileManager = .default) {
        self.cursorDirectory = cursorDirectory
        self.fileManager = fileManager
    }

    public func read() -> CursorAccountState? {
        let databaseURL = cursorDirectory.appendingPathComponent("User/globalStorage/state.vscdb")
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        let updatedAt = (try? databaseURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        guard let values = readCursorAuthValues(from: databaseURL) else { return nil }
        let state = CursorAccountState(
            membershipType: values["cursorAuth/stripeMembershipType"],
            subscriptionStatus: values["cursorAuth/stripeSubscriptionStatus"],
            email: values["cursorAuth/cachedEmail"],
            accessToken: values["cursorAuth/accessToken"],
            updatedAt: updatedAt
        )
        if state.membershipType == nil, state.subscriptionStatus == nil, state.email == nil, state.accessToken == nil { return nil }
        return state
    }

    private func readCursorAuthValues(from databaseURL: URL) -> [String: String]? {
        let keys = [
            "cursorAuth/stripeMembershipType",
            "cursorAuth/stripeSubscriptionStatus",
            "cursorAuth/cachedEmail",
            "cursorAuth/accessToken"
        ]
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            return nil
        }
        defer { sqlite3_close(database) }

        let placeholders = keys.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT key, value FROM ItemTable WHERE key IN (\(placeholders));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        for (index, key) in keys.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), key, -1, SQLITE_TRANSIENT)
        }

        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPointer = sqlite3_column_text(statement, 0),
                  let valuePointer = sqlite3_column_text(statement, 1) else {
                continue
            }
            let key = String(cString: keyPointer)
            let value = String(cString: valuePointer)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
            if !value.isEmpty {
                values[key] = value
            }
        }
        return values
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct LocalJSONLFile {
    let url: URL
    let modifiedAt: Date
    let byteSize: Int
}

private struct ClaudeJSONLEvent: Decodable {
    let timestamp: String?
    let message: ClaudeMessage?
}

private struct ClaudeMessage: Decodable {
    let usage: ClaudeUsage?
}

private struct ClaudeUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
}

private struct ClaudeStatusLinePayload: Decodable {
    let updated_at: Double
    let rate_limits: ClaudeStatusLineRateLimits?
}

private struct ClaudeStatusLineRateLimits: Decodable {
    let five_hour: ClaudeStatusLineWindow?
    let seven_day: ClaudeStatusLineWindow?
}

private struct ClaudeStatusLineWindow: Decodable {
    let used_percentage: Double?
    let resets_at: Double?
}

private struct CodexJSONLEvent: Decodable {
    let timestamp: String?
    let payload: CodexPayload
}

private struct CodexPayload: Decodable {
    let type: String
    let rate_limits: CodexRateLimits?
}

private struct CodexRateLimits: Decodable {
    let primary: CodexRateLimit?
    let secondary: CodexRateLimit?
}

private struct CodexRateLimit: Decodable {
    let used_percent: Double
    let window_minutes: Int?
    let resets_at: Double
}

private struct TimedCodexRateLimit {
    let rateLimit: CodexRateLimit
    let timestamp: Date
}

private enum LocalTimestampParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) { return date }

        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        return wholeSecondFormatter.date(from: value)
    }
}
