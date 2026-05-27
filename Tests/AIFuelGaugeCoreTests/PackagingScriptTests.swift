import XCTest

final class PackagingScriptTests: XCTestCase {
    func testPackageAndLaunchAgentScriptsExist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let packageScript = root.appendingPathComponent("scripts/package-app.sh")
        let launchAgentScript = root.appendingPathComponent("scripts/install-launch-agent.sh")
        let uninstallScript = root.appendingPathComponent("scripts/uninstall.sh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageScript.path), "package-app.sh should build a real .app bundle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: launchAgentScript.path), "install-launch-agent.sh should install Launch at Login")
        XCTAssertTrue(FileManager.default.fileExists(atPath: uninstallScript.path), "uninstall.sh should remove the standalone install")
    }

    func testPackagingScriptBuildsMenuBarOnlyBundleMetadata() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/package-app.sh"))

        XCTAssertTrue(script.contains("<key>LSUIElement</key>"), "bundle should run as a menu bar accessory")
        XCTAssertTrue(script.contains("<true/>"), "bundle should enable LSUIElement")
        XCTAssertTrue(script.contains("codesign --force --deep --sign -"), "bundle should be ad-hoc signed for local standalone installs")
        XCTAssertTrue(script.contains("swift build -c \"$configuration\" --product aifuelgauge >&2"), "package-app.sh should keep stdout machine-readable for installers")
    }

    func testInstallScriptCapturesOnlyPackagedAppPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/install-launch-agent.sh"))

        XCTAssertTrue(script.contains("| tail -n 1"), "install script should tolerate build chatter and use only the final app path")
        XCTAssertTrue(script.contains("[[ ! -d \"$app_source\" ]]"), "install script should fail clearly if packaging did not produce an app")
    }
}
