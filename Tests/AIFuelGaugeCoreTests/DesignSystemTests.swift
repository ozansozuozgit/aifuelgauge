import AppKit
import XCTest
import SwiftUI
@testable import AIFuelGaugeCore

final class DesignSystemTests: XCTestCase {
    func testOKLCHBlackAndWhite() {
        let black = OKLCH.srgb(l: 0.0, c: 0.0, h: 0.0)
        XCTAssertEqual(black.r, 0.0, accuracy: 0.01)
        XCTAssertEqual(black.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(black.b, 0.0, accuracy: 0.01)

        let white = OKLCH.srgb(l: 1.0, c: 0.0, h: 0.0)
        XCTAssertEqual(white.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(white.g, 1.0, accuracy: 0.01)
        XCTAssertEqual(white.b, 1.0, accuracy: 0.01)
    }

    func testOKLCHSafeGreenIsGreenish() {
        // safe (light): oklch(0.66 0.15 150) — known anchor ≈ rgb(0.24, 0.67, 0.37)
        let safe = OKLCH.srgb(l: 0.66, c: 0.15, h: 150)
        XCTAssertEqual(safe.r, 0.24, accuracy: 0.05)
        XCTAssertEqual(safe.g, 0.67, accuracy: 0.05)
        XCTAssertEqual(safe.b, 0.37, accuracy: 0.05)
        XCTAssertGreaterThan(safe.g, safe.r) // green dominant
        XCTAssertGreaterThan(safe.g, safe.b)
    }

    func testValuesAreClampedToUnitRange() {
        let c = OKLCH.srgb(l: 0.5, c: 0.4, h: 25) // high chroma, guaranteed out-of-gamut
        for v in [c.r, c.g, c.b] {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
    }
}

extension DesignSystemTests {
    func testFuelStateColorsExistForEveryState() {
        for state in [UsageState.unknown, .safe, .caution, .critical, .exhausted] {
            // Should not crash and should resolve to some color.
            _ = FuelTheme.color(for: state)
        }
    }

    func testSurfaceTokensDistinctLightDark() {
        // Resolve the dynamic NSColor in both appearances and confirm they differ.
        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!
        let token = FuelTheme.surfaceRaised
        var lightColor = NSColor.black
        var darkColor = NSColor.black
        light.performAsCurrentDrawingAppearance { lightColor = NSColor(token).usingColorSpace(.sRGB)! }
        dark.performAsCurrentDrawingAppearance { darkColor = NSColor(token).usingColorSpace(.sRGB)! }
        XCTAssertNotEqual(lightColor, darkColor)
    }
}
