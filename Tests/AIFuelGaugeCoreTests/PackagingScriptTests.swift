import XCTest

final class PackagingScriptTests: XCTestCase {
    func testPackageAndLaunchAgentScriptsExist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let packageScript = root.appendingPathComponent("scripts/package-app.sh")
        let iconScript = root.appendingPathComponent("scripts/build-app-icon.swift")
        let releaseZipScript = root.appendingPathComponent("scripts/package-release-zip.sh")
        let launchAgentScript = root.appendingPathComponent("scripts/install-launch-agent.sh")
        let uninstallScript = root.appendingPathComponent("scripts/uninstall.sh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageScript.path), "package-app.sh should build a real .app bundle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconScript.path), "build-app-icon.swift should create the app icon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: releaseZipScript.path), "package-release-zip.sh should build a GitHub release artifact")
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
        XCTAssertTrue(script.contains("<key>CFBundleIconFile</key>"), "bundle should advertise an app icon")
        XCTAssertTrue(script.contains("scripts/build-app-icon.swift"), "package-app.sh should generate the iconset")
        XCTAssertTrue(script.contains("iconutil -c icns"), "package-app.sh should compile an icns file")
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

    func testReleaseZipScriptAndWorkflowPublishTaggedBuilds() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/package-release-zip.sh"))
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/release.yml"))
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"))

        XCTAssertTrue(script.contains("scripts/package-app.sh"), "release zip should reuse the normal app packaging script")
        XCTAssertTrue(script.contains("ditto -c -k --keepParent"), "release zip should preserve the .app bundle structure on macOS")
        XCTAssertTrue(script.contains("shasum -a 256"), "release zip should publish a checksum")
        XCTAssertTrue(workflow.contains("runs-on: macos-14"), "release packaging should run on macOS")
        XCTAssertTrue(workflow.contains("swift test"), "release workflow should test before packaging")
        XCTAssertTrue(workflow.contains("gh release create"), "tagged builds should create a GitHub release")
        XCTAssertTrue(makefile.contains("release-zip:"), "Makefile should expose release packaging locally")
    }
}
