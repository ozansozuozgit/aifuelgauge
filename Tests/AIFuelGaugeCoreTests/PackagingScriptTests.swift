import XCTest

final class PackagingScriptTests: XCTestCase {
    func testPackageAndLaunchAgentScriptsExist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let packageScript = root.appendingPathComponent("scripts/package-app.sh")
        let launchAgentScript = root.appendingPathComponent("scripts/install-launch-agent.sh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageScript.path), "package-app.sh should build a real .app bundle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: launchAgentScript.path), "install-launch-agent.sh should install Launch at Login")
    }
}
