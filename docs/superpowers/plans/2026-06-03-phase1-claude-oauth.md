# Phase 1 — Claude Exact Usage (Zero Setup) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get exact Claude 5h / weekly (and Opus/Sonnet) usage percentages directly from Claude's own on-disk OAuth credentials, so the app no longer needs our injected statusline hook.

**Architecture:** A new `ClaudeOAuthConnector` reads credentials via a `ClaudeCredentialsReader`, calls Anthropic's OAuth usage endpoint through the existing `HTTPTransport` protocol, and maps the response with a pure `ClaudeOAuthUsageParser`. A pure `ClaudeSourcePlanner` merges OAuth-exact lanes over the existing statusline/JSONL lanes. Wired into `DashboardController.loadUsageOffMain` like the existing Codex/Cursor blocks, failing soft.

**Tech Stack:** Swift, SwiftPM, XCTest. Reuses `HTTPTransport`, `ConnectorError`, `UsageSnapshot`, `UsageAccount` from `AIFuelGaugeCore`.

---

## File structure

- Create: `Sources/AIFuelGaugeCore/ClaudeOAuthConnector.swift` — credential reader, response models, parser, connector.
- Create: `Sources/AIFuelGaugeCore/ClaudeSourcePlanner.swift` — pure merge/dedupe of Claude sources.
- Modify: `Sources/AIFuelGaugeApp/main.swift:740-758` — add Claude OAuth block in the refresh loop.
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeOAuthConnectorTests.swift`
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeSourcePlannerTests.swift`
- Fixture: `Tests/AIFuelGaugeCoreTests/Fixtures/claude-oauth-usage.json` (from the spike)

---

### Task 1: Spike — confirm credential shape, endpoint, and response on the real machine

This is throwaway verification; it is NOT committed except for the sanitized fixture it produces.

- [ ] **Step 1: Check which credential source exists**

Run:
```bash
ls -l ~/.claude/.credentials.json 2>/dev/null && echo "FILE PRESENT" || echo "no file"
security find-generic-password -s "Claude Code-credentials" -g 2>&1 | head -5 || true
```
Expected: either the file exists, or the Keychain item is found. Note which one. If the file exists, inspect its key path (without printing secrets):
```bash
python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.claude/.credentials.json')));print(list(d.keys()));print(list(d.get('claudeAiOauth',{}).keys()))"
```
Record the actual top-level key (e.g. `claudeAiOauth`) and field names (`accessToken`, `refreshToken`, `expiresAt`, `subscriptionType`).

- [ ] **Step 2: Hit the usage endpoint with the real token and capture the response**

Run (reads token from the file, prints only the JSON response):
```bash
python3 - <<'PY'
import json, os, urllib.request
d = json.load(open(os.path.expanduser('~/.claude/.credentials.json')))
tok = d['claudeAiOauth']['accessToken']
req = urllib.request.Request(
    'https://api.anthropic.com/api/oauth/usage',
    headers={'Authorization': f'Bearer {tok}', 'anthropic-beta': 'oauth-2025-04-20'})
print(urllib.request.urlopen(req, timeout=10).read().decode())
PY
```
Expected: JSON containing windows like `five_hour`/`fiveHour`, `seven_day`/`sevenDay`, each with `utilization` and `resets_at`/`resetsAt`. **Record the exact JSON key style (snake_case vs camelCase).**

- [ ] **Step 3: Save a sanitized fixture**

Take the response from Step 2, replace any email/identifiers with placeholders, and save it to `Tests/AIFuelGaugeCoreTests/Fixtures/claude-oauth-usage.json`. This is the contract the parser is tested against. If the real keys differ from this plan's assumed names, **update the `CodingKeys` in Task 3 to match this fixture** — the fixture is the source of truth.

- [ ] **Step 4: Commit the fixture**

```bash
mkdir -p Tests/AIFuelGaugeCoreTests/Fixtures
git add Tests/AIFuelGaugeCoreTests/Fixtures/claude-oauth-usage.json
git commit -m "test: add sanitized Claude OAuth usage fixture from spike"
```

---

### Task 2: ClaudeCredentialsReader

**Files:**
- Create: `Sources/AIFuelGaugeCore/ClaudeOAuthConnector.swift`
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeOAuthConnectorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AIFuelGaugeCore

final class ClaudeOAuthConnectorTests: XCTestCase {
    func testCredentialsReaderParsesFileJSON() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"ref-456","expiresAt":1893456000000,"subscriptionType":"max"}}
        """
        let creds = try ClaudeCredentialsReader.parse(fileData: Data(json.utf8))
        XCTAssertEqual(creds.accessToken, "tok-123")
        XCTAssertEqual(creds.refreshToken, "ref-456")
        XCTAssertEqual(creds.subscriptionType, "max")
        XCTAssertEqual(creds.expiresAtMillis, 1893456000000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeOAuthConnectorTests/testCredentialsReaderParsesFileJSON`
Expected: FAIL — `ClaudeCredentialsReader` undefined.

- [ ] **Step 3: Write minimal implementation**

In `ClaudeOAuthConnector.swift`:
```swift
import Foundation

public struct ClaudeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAtMillis: Double?
    public let subscriptionType: String?
}

public enum ClaudeCredentialsReader {
    private struct File: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Double?
            let subscriptionType: String?
        }
        let claudeAiOauth: OAuth
    }

    /// Parse the JSON contents of ~/.claude/.credentials.json.
    public static func parse(fileData: Data) throws -> ClaudeCredentials {
        let file = try JSONDecoder().decode(File.self, from: fileData)
        return ClaudeCredentials(
            accessToken: file.claudeAiOauth.accessToken,
            refreshToken: file.claudeAiOauth.refreshToken,
            expiresAtMillis: file.claudeAiOauth.expiresAt,
            subscriptionType: file.claudeAiOauth.subscriptionType
        )
    }

    /// Best-effort load from disk; Keychain fallback added in Task 6.
    public static func loadFromDisk(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ClaudeCredentials? {
        let url = home.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? parse(fileData: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeOAuthConnectorTests/testCredentialsReaderParsesFileJSON`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeCore/ClaudeOAuthConnector.swift Tests/AIFuelGaugeCoreTests/ClaudeOAuthConnectorTests.swift
git commit -m "feat: ClaudeCredentialsReader parses Claude OAuth credentials file"
```

---

### Task 3: ClaudeOAuthUsageParser → [UsageSnapshot]

**Files:**
- Modify: `Sources/AIFuelGaugeCore/ClaudeOAuthConnector.swift`
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeOAuthConnectorTests.swift`

> Field names below assume snake_case (`five_hour`, `seven_day`, `utilization`, `resets_at`). **If the Task 1 fixture uses camelCase, change the `CodingKeys`/property names accordingly.**

- [ ] **Step 1: Write the failing test**

```swift
func testParserMapsWindowsToExactPercentLanes() throws {
    let json = """
    {"five_hour":{"utilization":7,"resets_at":"2026-06-03T18:00:00Z"},
     "seven_day":{"utilization":46,"resets_at":"2026-06-08T11:00:00Z"}}
    """
    let now = Date(timeIntervalSince1970: 1_000_000)
    let rows = try ClaudeOAuthUsageParser.parse(data: Data(json.utf8), subscriptionType: "max", now: now)
    let fiveHour = try XCTUnwrap(rows.first { $0.label == "5h" })
    XCTAssertEqual(fiveHour.provider, .claudeCode)
    XCTAssertEqual(fiveHour.source, .officialAPI)
    XCTAssertEqual(fiveHour.confidence, .exact)
    XCTAssertEqual(fiveHour.used, .percent(7))
    XCTAssertEqual(fiveHour.limit, .percent(100))
    XCTAssertEqual(fiveHour.account?.plan, "Max")
    XCTAssertTrue(rows.contains { $0.label == "Weekly" && $0.used == .percent(46) })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeOAuthConnectorTests/testParserMapsWindowsToExactPercentLanes`
Expected: FAIL — `ClaudeOAuthUsageParser` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `ClaudeOAuthConnector.swift`:
```swift
public enum ClaudeOAuthUsageParser {
    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
    private struct Response: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let seven_day_sonnet: Window?
    }

    public static func parse(data: Data, subscriptionType: String?, now: Date) throws -> [UsageSnapshot] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let plan = planLabel(subscriptionType)
        let account = UsageAccount(identifier: "claude-oauth", displayName: "Claude", plan: plan)
        var rows: [UsageSnapshot] = []
        func add(_ window: Window?, label: String) {
            guard let window, let util = window.utilization else { return }
            rows.append(UsageSnapshot(
                provider: .claudeCode,
                source: .officialAPI,
                account: account,
                label: label,
                used: .percent(min(max(util, 0), 100)),
                limit: .percent(100),
                reset: window.resets_at.flatMap(parseDate).map { .fixed($0) },
                confidence: .exact,
                updatedAt: now))
        }
        add(response.five_hour, label: "5h")
        add(response.seven_day, label: "Weekly")
        add(response.seven_day_opus, label: "Weekly · Opus")
        add(response.seven_day_sonnet, label: "Weekly · Sonnet")
        return rows
    }

    private static func planLabel(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw.contains("max") && raw.contains("20") { return "Max 20x" }
        if raw.contains("max") && raw.contains("5") { return "Max 5x" }
        if raw.contains("max") { return "Max" }
        if raw.contains("pro") { return "Pro" }
        if raw.contains("team") { return "Team" }
        if raw.contains("enterprise") { return "Enterprise" }
        return raw.capitalized
    }

    private static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeOAuthConnectorTests/testParserMapsWindowsToExactPercentLanes`
Expected: PASS.

- [ ] **Step 5: Add a fixture-driven test and run it**

```swift
func testParserHandlesRealFixture() throws {
    let url = Bundle.module.url(forResource: "claude-oauth-usage", withExtension: "json", subdirectory: "Fixtures")
    let data = try Data(contentsOf: try XCTUnwrap(url))
    let rows = try ClaudeOAuthUsageParser.parse(data: data, subscriptionType: "max", now: Date())
    XCTAssertFalse(rows.isEmpty)
    XCTAssertTrue(rows.allSatisfy { $0.confidence == .exact })
}
```
Note: this requires the test target to expose resources. If `Bundle.module` resource access is not configured, add `resources: [.copy("Fixtures")]` to the test target in `Package.swift`. Run:
`swift test --filter ClaudeOAuthConnectorTests/testParserHandlesRealFixture`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: ClaudeOAuthUsageParser maps usage windows to exact lanes"
```

---

### Task 4: ClaudeOAuthConnector.fetchUsage()

**Files:**
- Modify: `Sources/AIFuelGaugeCore/ClaudeOAuthConnector.swift`
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeOAuthConnectorTests.swift`

- [ ] **Step 1: Write the failing test (stub transport)**

```swift
private final class StubTransport: HTTPTransport {
    let data: Data
    let status: Int
    var lastRequest: URLRequest?
    init(data: Data, status: Int) { self.data = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

func testConnectorSendsAuthHeadersAndReturnsLanes() async throws {
    let body = Data(#"{"five_hour":{"utilization":12,"resets_at":"2026-06-03T18:00:00Z"}}"#.utf8)
    let transport = StubTransport(data: body, status: 200)
    let creds = ClaudeCredentials(accessToken: "tok-xyz", refreshToken: nil, expiresAtMillis: nil, subscriptionType: "pro")
    let connector = ClaudeOAuthConnector(transport: transport)
    let rows = try await connector.fetchUsage(credentials: creds)
    XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-xyz")
    XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    XCTAssertEqual(rows.first?.used, .percent(12))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeOAuthConnectorTests/testConnectorSendsAuthHeadersAndReturnsLanes`
Expected: FAIL — `ClaudeOAuthConnector` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `ClaudeOAuthConnector.swift`:
```swift
public final class ClaudeOAuthConnector {
    private let transport: HTTPTransport
    private let endpoint: URL
    private let now: () -> Date

    public init(
        transport: HTTPTransport = URLSession.shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.now = now
    }

    public func fetchUsage(credentials: ClaudeCredentials) async throws -> [UsageSnapshot] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ConnectorError.badStatus(http.statusCode) }
        return try ClaudeOAuthUsageParser.parse(data: data, subscriptionType: credentials.subscriptionType, now: now())
    }

    /// Convenience: load creds from disk and fetch; returns [] if no creds.
    public func fetchUsageFromLocalCredentials() async throws -> [UsageSnapshot] {
        guard let creds = ClaudeCredentialsReader.loadFromDisk() else { return [] }
        return try await fetchUsage(credentials: creds)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeOAuthConnectorTests/testConnectorSendsAuthHeadersAndReturnsLanes`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: ClaudeOAuthConnector fetches exact usage over HTTPTransport"
```

---

### Task 5: ClaudeSourcePlanner — merge OAuth over statusline/JSONL

**Files:**
- Create: `Sources/AIFuelGaugeCore/ClaudeSourcePlanner.swift`
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeSourcePlannerTests.swift`

Behavior: if OAuth lanes exist, drop existing `.claudeCode` percent lanes coming from `.localLogs` (the statusline 5h/Weekly), keep the `.claudeCode` token-estimate lane (no usagePercent), and append OAuth lanes. If no OAuth lanes, return local unchanged.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AIFuelGaugeCore

final class ClaudeSourcePlannerTests: XCTestCase {
    private func percentLane(_ label: String, _ pct: Double, source: UsageSource) -> UsageSnapshot {
        UsageSnapshot(provider: .claudeCode, source: source, label: label,
                      used: .percent(pct), limit: .percent(100), reset: nil,
                      confidence: .exact, updatedAt: Date())
    }
    private func tokenLane() -> UsageSnapshot {
        UsageSnapshot(provider: .claudeCode, source: .localLogs, label: "Claude Code",
                      used: .tokens(input: 1, output: 1, cacheRead: 0, cacheWrite: 0),
                      limit: nil, reset: nil, confidence: .estimated, updatedAt: Date())
    }

    func testOAuthSupersedesStatuslinePercentLanes() {
        let local = [percentLane("5h", 90, source: .localLogs), tokenLane()]
        let oauth = [percentLane("5h", 7, source: .officialAPI)]
        let merged = ClaudeSourcePlanner.plan(local: local, oauth: oauth)
        // statusline 5h dropped, oauth 5h kept, token lane kept
        XCTAssertEqual(merged.filter { $0.label == "5h" }.count, 1)
        XCTAssertEqual(merged.first { $0.label == "5h" }?.used, .percent(7))
        XCTAssertTrue(merged.contains { $0.label == "Claude Code" })
    }

    func testNoOAuthKeepsLocal() {
        let local = [percentLane("5h", 90, source: .localLogs), tokenLane()]
        let merged = ClaudeSourcePlanner.plan(local: local, oauth: [])
        XCTAssertEqual(merged.count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeSourcePlannerTests`
Expected: FAIL — `ClaudeSourcePlanner` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Merges Claude usage sources by confidence: exact OAuth lanes supersede the
/// statusline (.localLogs percent) lanes for the same provider; the token
/// estimate lane (no usagePercent) is preserved for breakdown context.
public enum ClaudeSourcePlanner {
    public static func plan(local: [UsageSnapshot], oauth: [UsageSnapshot]) -> [UsageSnapshot] {
        guard !oauth.isEmpty else { return local }
        let kept = local.filter { snapshot in
            guard snapshot.provider == .claudeCode else { return true }
            // Drop local-logs percent lanes (the statusline 5h/Weekly); keep others.
            let isStatuslinePercent = snapshot.source == .localLogs && snapshot.usagePercent != nil
            return !isStatuslinePercent
        }
        return kept + oauth
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeSourcePlannerTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: ClaudeSourcePlanner merges exact OAuth lanes over statusline"
```

---

### Task 6: Keychain fallback for credentials

**Files:**
- Modify: `Sources/AIFuelGaugeCore/ClaudeOAuthConnector.swift`
- Test: `Tests/AIFuelGaugeCoreTests/ClaudeOAuthConnectorTests.swift`

The Keychain item `"Claude Code-credentials"` stores the same JSON as the file. Read it via the `security` CLI (consistent with how the app already shells out) or `SecItemCopyMatching`. Parsing is already covered by `ClaudeCredentialsReader.parse`; this only adds the source.

- [ ] **Step 1: Write the failing test (parse path is reused; test the selection helper)**

```swift
func testLoadPrefersFileThenKeychain() throws {
    // File parsing already tested; assert loadFromDisk returns nil for a missing home.
    let creds = ClaudeCredentialsReader.loadFromDisk(home: URL(fileURLWithPath: "/nonexistent-home"))
    XCTAssertNil(creds)
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `swift test --filter ClaudeOAuthConnectorTests/testLoadPrefersFileThenKeychain`
Expected: PASS already (loadFromDisk returns nil). If it fails, fix `loadFromDisk` to guard missing files.

- [ ] **Step 3: Add Keychain read used by the connector convenience**

Add to `ClaudeCredentialsReader`:
```swift
    /// Reads the "Claude Code-credentials" generic password via the security CLI.
    public static func loadFromKeychain() -> ClaudeCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return try? parse(fileData: data)
    }
```
And update `loadFromDisk` callers via a new combined entry:
```swift
    public static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ClaudeCredentials? {
        loadFromDisk(home: home) ?? loadFromKeychain()
    }
```
Update `ClaudeOAuthConnector.fetchUsageFromLocalCredentials()` to call `ClaudeCredentialsReader.load()`.

- [ ] **Step 4: Run the full connector test file**

Run: `swift test --filter ClaudeOAuthConnectorTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: Claude credentials Keychain fallback"
```

---

### Task 7: Wire into the refresh loop

**Files:**
- Modify: `Sources/AIFuelGaugeApp/main.swift` (after the local collector block, ~line 745, before the Codex block)

- [ ] **Step 1: Add the Claude OAuth block**

Insert after the `LocalUsageCollector` do/catch (currently ending ~line 745):
```swift
            if monitoredProviders.contains(.claudeCode) {
                do {
                    let oauthLanes = try await ClaudeOAuthConnector().fetchUsageFromLocalCredentials()
                    if !oauthLanes.isEmpty {
                        snapshots = ClaudeSourcePlanner.plan(local: snapshots, oauth: oauthLanes)
                    }
                } catch {
                    warnings.append("Claude usage unavailable")
                }
            }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Run the full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (0 failures).

- [ ] **Step 4: Manual verification on the real app**

Run: `make install` then open the menu bar popover.
Expected: Claude Code lanes show exact "% left" with a plan label (e.g. "Claude Code · Max 5x · 5h") sourced from OAuth, and the footer trust tally counts them as exact — even with the statusline hook uninstalled.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeApp/main.swift
git commit -m "feat: read exact Claude usage from local OAuth creds in refresh loop"
```

---

## Self-review notes

- **Spec coverage:** Phase 1 requirements (credential discovery file→Keychain, oauth/usage endpoint + headers, window→exact lanes, plan tier, source planner oauth→statusline→jsonl, soft-fail wiring) each map to Tasks 2–7. Refresh (expiry) is intentionally deferred: Task 1 confirms whether the local token is long-lived enough that read-only works without refresh; if the spike shows frequent expiry, add a refresh sub-task before Task 7 using the refresh shape captured in the spike.
- **Type consistency:** `ClaudeCredentials`, `ClaudeCredentialsReader.parse/loadFromDisk/loadFromKeychain/load`, `ClaudeOAuthUsageParser.parse(data:subscriptionType:now:)`, `ClaudeOAuthConnector.fetchUsage(credentials:)`/`fetchUsageFromLocalCredentials()`, `ClaudeSourcePlanner.plan(local:oauth:)` are used consistently across tasks.
- **Fixture dependency:** Task 3 Step 5 + `Package.swift` resource note — only needed if the fixture test is kept; the synthetic tests don't require resources.
