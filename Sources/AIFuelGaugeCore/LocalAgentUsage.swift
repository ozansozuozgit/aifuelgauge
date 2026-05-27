import Foundation

public enum LocalAgentSourceKind: String, Codable, Equatable, Hashable {
    case jsonlDirectory
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
            )
        ]
        return candidates.filter { source in
            switch source.kind {
            case .jsonlDirectory:
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: source.url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            case .sqliteDatabase:
                return fileManager.fileExists(atPath: source.url.path)
            }
        }
    }
}

public enum LocalUsageParseError: Error, Equatable {
    case noUsageFound
}

public struct ClaudeJSONLUsageParser {
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func parse(lines: [String], label: String = "Claude Code") throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var foundUsage = false

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(ClaudeJSONLEvent.self, from: data),
                  let usage = event.message?.usage else {
                continue
            }
            foundUsage = true
            input += usage.input_tokens ?? 0
            output += usage.output_tokens ?? 0
            cacheRead += usage.cache_read_input_tokens ?? 0
            cacheWrite += usage.cache_creation_input_tokens ?? 0
        }

        guard foundUsage else { throw LocalUsageParseError.noUsageFound }
        return UsageSnapshot(
            provider: .claudeCode,
            source: .localLogs,
            label: label,
            used: .tokens(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite),
            limit: nil,
            reset: nil,
            confidence: .estimated,
            updatedAt: now()
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
        var latestPrimary: CodexRateLimit?
        var latestSecondary: CodexRateLimit?

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(CodexJSONLEvent.self, from: data),
                  event.payload.type == "token_count" else {
                continue
            }
            if let primary = event.payload.rate_limits?.primary {
                latestPrimary = primary
            }
            if let secondary = event.payload.rate_limits?.secondary {
                latestSecondary = secondary
            }
        }

        let generatedAt = now()
        var snapshots: [UsageSnapshot] = []
        if let latestPrimary {
            snapshots.append(snapshot(for: latestPrimary, label: codexWindowLabel(for: latestPrimary) ?? primaryFallbackLabel, now: generatedAt))
        }
        if let latestSecondary {
            snapshots.append(snapshot(for: latestSecondary, label: codexWindowLabel(for: latestSecondary) ?? "Weekly", now: generatedAt))
        }
        guard !snapshots.isEmpty else { throw LocalUsageParseError.noUsageFound }
        return snapshots
    }

    private func snapshot(for rateLimit: CodexRateLimit, label: String, now generatedAt: Date) -> UsageSnapshot {
        let secondsRemaining = max(0, TimeInterval(rateLimit.resets_at) - generatedAt.timeIntervalSince1970)
        return UsageSnapshot(
            provider: .codex,
            source: .localLogs,
            label: label,
            used: .percent(rateLimit.used_percent),
            limit: .percent(100),
            reset: .rollingWindow(secondsRemaining: secondsRemaining),
            confidence: .exact,
            updatedAt: generatedAt
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

public struct LocalUsageCollector {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
    }

    public func collect() throws -> [UsageSnapshot] {
        let sources = LocalAgentDetector(homeDirectory: homeDirectory, fileManager: fileManager).detectedSources()
        var snapshots: [UsageSnapshot] = []
        for source in sources {
            switch source.provider {
            case .claudeCode:
                if let snapshot = try? ClaudeJSONLUsageParser(now: now).parse(lines: readJSONLLines(recursivelyUnder: source.url), label: "Claude Code") {
                    snapshots.append(snapshot)
                }
            case .codex:
                if let codexSnapshots = try? CodexJSONLUsageParser(now: now).parseRateLimits(lines: readJSONLLines(recursivelyUnder: source.url)) {
                    snapshots.append(contentsOf: codexSnapshots)
                }
            case .openCode:
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

        let files = enumerator.compactMap { item -> LocalJSONLFile? in
            guard let fileURL = item as? URL, fileURL.pathExtension == "jsonl" else { return nil }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { return nil }
            return LocalJSONLFile(
                url: fileURL,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                byteSize: values.fileSize ?? 0
            )
        }
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

private struct LocalJSONLFile {
    let url: URL
    let modifiedAt: Date
    let byteSize: Int
}

private struct ClaudeJSONLEvent: Decodable {
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

private struct CodexJSONLEvent: Decodable {
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
