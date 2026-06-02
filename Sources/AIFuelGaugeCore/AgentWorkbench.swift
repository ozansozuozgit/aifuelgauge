import Foundation

public struct AgentWorkbenchSnapshot: Codable, Equatable, Sendable {
    public let sessions: [AgentSessionSummary]
    public let routes: [AgentQuickRoute]
    public let devServers: [LocalDevServer]
    public let updatedAt: Date

    public init(
        sessions: [AgentSessionSummary],
        routes: [AgentQuickRoute],
        devServers: [LocalDevServer],
        updatedAt: Date
    ) {
        self.sessions = sessions
        self.routes = routes
        self.devServers = devServers
        self.updatedAt = updatedAt
    }

    public static let empty = AgentWorkbenchSnapshot(sessions: [], routes: [], devServers: [], updatedAt: Date.distantPast)

    public var isEmpty: Bool {
        sessions.isEmpty && routes.isEmpty && devServers.isEmpty
    }
}

public struct AgentSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let provider: Provider
    public let project: String
    public let status: String
    public let detail: String
    public let updatedAt: Date
    public let transcriptPath: String?

    public init(
        id: String,
        provider: Provider,
        project: String,
        status: String,
        detail: String,
        updatedAt: Date,
        transcriptPath: String?
    ) {
        self.id = id
        self.provider = provider
        self.project = project
        self.status = status
        self.detail = detail
        self.updatedAt = updatedAt
        self.transcriptPath = transcriptPath
    }
}

public struct AgentQuickRoute: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let provider: Provider
    public let title: String
    public let path: String
    public let exists: Bool

    public init(id: String, provider: Provider, title: String, path: String, exists: Bool) {
        self.id = id
        self.provider = provider
        self.title = title
        self.path = path
        self.exists = exists
    }
}

public struct LocalDevServer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let port: Int
    public let processID: Int
    public let command: String
    public let url: String

    public init(id: String, port: Int, processID: Int, command: String, url: String) {
        self.id = id
        self.port = port
        self.processID = processID
        self.command = command
        self.url = url
    }
}

public struct AgentWorkbenchCollector {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let devServerOutput: (() -> String?)?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        devServerOutput: (() -> String?)? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.devServerOutput = devServerOutput
    }

    public func collect() -> AgentWorkbenchSnapshot {
        AgentWorkbenchSnapshot(
            sessions: recentSessions(),
            routes: quickRoutes(),
            devServers: LocalDevServerDetector(output: devServerOutput).detect(),
            updatedAt: now()
        )
    }

    private func quickRoutes() -> [AgentQuickRoute] {
        let candidates: [(Provider, String, URL)] = [
            (.claudeCode, "Claude skills", homeDirectory.appendingPathComponent(".claude/skills")),
            (.claudeCode, "Claude plugins", homeDirectory.appendingPathComponent(".claude/plugins")),
            (.claudeCode, "Claude config", homeDirectory.appendingPathComponent(".claude/settings.json")),
            (.claudeCode, "Claude logs", homeDirectory.appendingPathComponent(".claude/projects")),
            (.codex, "Codex skills", homeDirectory.appendingPathComponent(".codex/skills")),
            (.codex, "Codex plugins", homeDirectory.appendingPathComponent(".codex/plugins")),
            (.codex, "Codex config", homeDirectory.appendingPathComponent(".codex/config.toml")),
            (.codex, "Codex logs", homeDirectory.appendingPathComponent(".codex/sessions")),
            (.cursor, "Cursor state", homeDirectory.appendingPathComponent("Library/Application Support/Cursor")),
            (.openCode, "OpenCode data", homeDirectory.appendingPathComponent(".local/share/opencode"))
        ]

        return candidates.map { provider, title, url in
            AgentQuickRoute(
                id: "\(provider.rawValue)-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))",
                provider: provider,
                title: title,
                path: url.path,
                exists: fileManager.fileExists(atPath: url.path)
            )
        }
    }

    private func recentSessions() -> [AgentSessionSummary] {
        let claude = recentJSONLSessions(
            provider: .claudeCode,
            root: homeDirectory.appendingPathComponent(".claude/projects"),
            projectFromFile: { fileURL in
                Self.readableProjectName(fromClaudeProjectDirectory: fileURL.deletingLastPathComponent())
            }
        )
        let codex = recentJSONLSessions(
            provider: .codex,
            root: homeDirectory.appendingPathComponent(".codex/sessions"),
            projectFromFile: { fileURL in
                let parent = fileURL.deletingLastPathComponent()
                return parent.lastPathComponent.isEmpty ? "Codex session" : parent.lastPathComponent
            }
        )
        return (claude + codex)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(8)
            .map { $0 }
    }

    private func recentJSONLSessions(
        provider: Provider,
        root: URL,
        projectFromFile: (URL) -> String
    ) -> [AgentSessionSummary] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
              ) else {
            return []
        }

        var files: [(URL, Date, Int)] = []
        for item in enumerator {
            guard let fileURL = item as? URL, fileURL.pathExtension == "jsonl" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            files.append((fileURL, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0))
        }

        return files
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { fileURL, modifiedAt, size in
                AgentSessionSummary(
                    id: "\(provider.rawValue)-\(fileURL.path)",
                    provider: provider,
                    project: projectFromFile(fileURL),
                    status: ageLabel(for: modifiedAt),
                    detail: size > 0 ? byteLabel(size) : "session log",
                    updatedAt: modifiedAt,
                    transcriptPath: fileURL.path
                )
            }
    }

    private static func readableProjectName(fromClaudeProjectDirectory directory: URL) -> String {
        let name = directory.lastPathComponent
        if name.hasPrefix("-") {
            let path = name
                .dropFirst()
                .replacingOccurrences(of: "-", with: "/")
            return path.split(separator: "/").last.map(String.init) ?? "Claude session"
        }
        return name.isEmpty ? "Claude session" : name
    }

    private func ageLabel(for date: Date) -> String {
        let seconds = max(0, now().timeIntervalSince(date))
        if seconds < 90 { return "active" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    private func byteLabel(_ bytes: Int) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return "\(bytes / 1_024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

public struct LocalDevServerDetector {
    private let output: (() -> String?)?

    public init(output: (() -> String?)? = nil) {
        self.output = output
    }

    public func detect() -> [LocalDevServer] {
        parse(output?() ?? Self.runLsof())
    }

    public func parse(_ output: String?) -> [LocalDevServer] {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var servers: [LocalDevServer] = []
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9,
                  let processID = Int(parts[1]),
                  let nameIndex = parts.firstIndex(of: "TCP") else {
                continue
            }
            let name = parts[nameIndex...].joined(separator: " ")
            guard name.contains("(LISTEN)"),
                  let port = Self.port(from: name),
                  (3000...9999).contains(port) else {
                continue
            }
            let command = String(parts[0])
            let url = "http://localhost:\(port)"
            servers.append(LocalDevServer(
                id: "\(processID)-\(port)",
                port: port,
                processID: processID,
                command: command,
                url: url
            ))
        }

        var seen = Set<String>()
        return servers
            .sorted { lhs, rhs in lhs.port == rhs.port ? lhs.processID < rhs.processID : lhs.port < rhs.port }
            .filter { seen.insert($0.id).inserted }
            .prefix(12)
            .map { $0 }
    }

    private static func port(from value: String) -> Int? {
        let pattern = #":(\d+)\s+\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Int(value[range])
    }

    private static func runLsof() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }
}
