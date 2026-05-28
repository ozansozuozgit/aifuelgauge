import Foundation

public struct AppUpdateCheckResult: Equatable, Sendable {
    public let currentVersion: String?
    public let latestVersion: String
    public let releaseURL: URL
    public let isUpdateAvailable: Bool
    public let message: String

    public init(currentVersion: String?, latestVersion: String, releaseURL: URL, isUpdateAvailable: Bool, message: String) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.isUpdateAvailable = isUpdateAvailable
        self.message = message
    }
}

public final class AppUpdateChecker {
    private let transport: HTTPTransport
    private let latestReleaseURL: URL
    private let decoder = JSONDecoder()

    public init(
        transport: HTTPTransport = URLSession.shared,
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/ozansozuozgit/aifuelgauge/releases/latest")!
    ) {
        self.transport = transport
        self.latestReleaseURL = latestReleaseURL
    }

    public func check(currentVersion: String?) async throws -> AppUpdateCheckResult {
        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AI Fuel Gauge", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.badStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectorError.badStatus(httpResponse.statusCode)
        }

        let release = try decoder.decode(GitHubLatestRelease.self, from: data)
        let trimmedCurrent = currentVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrent = trimmedCurrent.flatMap { $0.isEmpty ? nil : $0 }
        let updateAvailable = normalizedCurrent.map { Self.isVersion(release.tagName, newerThan: $0) } ?? false
        let message: String
        if let normalizedCurrent {
            message = updateAvailable
                ? "Update available: \(normalizedCurrent) -> \(release.tagName)."
                : "Up to date: \(normalizedCurrent) matches \(release.tagName)."
        } else {
            message = "Latest release is \(release.tagName). Current build version is unavailable."
        }

        return AppUpdateCheckResult(
            currentVersion: normalizedCurrent,
            latestVersion: release.tagName,
            releaseURL: release.htmlURL,
            isUpdateAvailable: updateAvailable,
            message: message
        )
    }

    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        guard let left = versionParts(lhs), let right = versionParts(rhs) else { return false }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart != rightPart { return leftPart > rightPart }
        }
        return false
    }

    private static func versionParts(_ raw: String) -> [Int]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var started = false
        var buffer = ""
        for character in trimmed {
            if !started, character == "v" || character == "V" {
                continue
            }
            if character.isNumber || character == "." {
                started = true
                buffer.append(character)
            } else if started {
                break
            }
        }
        let parts = buffer
            .split(separator: ".", omittingEmptySubsequences: true)
            .compactMap { Int($0) }
        return parts.isEmpty ? nil : parts
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
