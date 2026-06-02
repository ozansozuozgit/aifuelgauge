# AI Fuel Gauge Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the menu-bar popover, Settings window, and History window of AI Fuel Gauge in SwiftUI to match the `handoff/` redesign — faithful to the prototype, native-adapted, system-theme only — without touching the data layer.

**Architecture:** A new `DesignSystem.swift` token layer (in the core target) feeds three rebuilt SwiftUI surfaces. The popover and settings views move out of the 3000-line `main.swift` into focused `Popover.swift` and `Settings.swift` files. All data comes unchanged from the existing `DashboardController` / `DashboardViewModel`; the only new model-side work is one `heroLayout` preference and small pure helpers (tightest-lane ordering, hero-focus resolution) that get unit tests. Colors are defined via a runtime oklch→sRGB converter so the prototype's exact oklch values are preserved.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Package Manager (`swift build`, `swift test`), XCTest.

**Reference (authoritative for layout/spacing/values):**
- `handoff/HANDOFF.md` — spec
- `handoff/source/assets/app.css` — design tokens
- `handoff/source/assets/popover.jsx` — popover component structure
- `handoff/source/assets/settings.jsx` — settings form kit
- `handoff/source/assets/data.jsx` — ArcGauge / Meter / Sparkline / TrustChip
- `handoff/source/assets/icons.jsx` — icon set
- `handoff/screenshots/*.png` — visual acceptance targets

**Design spec:** `docs/superpowers/specs/2026-06-02-ai-fuel-gauge-redesign-design.md`

**Key existing types (do not redefine):**
- `DashboardController` (ObservableObject): `model: DashboardViewModel`, `workbench: AgentWorkbenchSnapshot`, `isRefreshing: Bool`, `refreshError: String?`, `refresh()`.
- `DashboardViewModel`: `title`, `statusLabel`, `insight`, `footerNote`, `trustDigest`, `state: UsageState`, `primaryGauge: DashboardGauge?`, `rows: [DashboardRow]`.
- `DashboardRow`: `id`, `title`, `value`, `detail`, `dashboardURL: String?`, `explanation`, `meterPercent: Double?`, `meterLabel: String?`, `trendPercents: [Double]`, `trendCaption: String?`, `paceCaption: String?`, `receiptText`, `confidence: Confidence`, `state: UsageState`, `showsInUsableFilter: Bool`.
- `DashboardGauge`: `snapshotID`, `title`, `value`, `subtitle`, `caption`, `explanation`, `percent: Double`, `state: UsageState`, `confidence: Confidence`, `paceCaption: String?`, `dashboardURL: String?`, `receiptText`.
- `UsageState`: `unknown | safe | caution | critical | exhausted` (Comparable).
- `Confidence`: `exact | estimated | unknown`.
- `MenuBarDisplayMode`: `detailed | pair | trend | compact | minimal`. `MenuBarProviderFocus`: `auto | …`.
- `AppPreferences` (private enum in `main.swift`): `menuBarDisplayMode`, `menuBarProviderFocus`, `refreshIntervalSeconds`, `monitoredProviders`, `laneOrder()/saveLaneOrder()`, `budgetPreferences()`, etc. Keys exposed as `static let …Key`.

---

## File Structure

**New files**
- `Sources/AIFuelGaugeCore/DesignSystem.swift` — oklch converter, color tokens (light/dark dynamic), typography, radii, shadows, `UsageState`/`Confidence` styling helpers.
- `Sources/AIFuelGaugeCore/HeroFocus.swift` — pure helpers: tightest-lane ordering, hero-focus resolution, top-3 selection. (Core target so it is unit-testable.)
- `Sources/AIFuelGaugeApp/Popover.swift` — `DashboardView` + popover subviews (`ArcGauge`, `Meter`, `Sparkline`, `TrustChip`, `StatePill`, `FocusPill`, `HeroFeaturedCard`, `HeroTrioCard`, `LaneRow`, `ResetContextStrip`, `ActionBar`).
- `Sources/AIFuelGaugeApp/Settings.swift` — `SettingsView` (NavigationSplitView) + form kit (`SettingsGroup`, `SettingsRow`, `SwitchControl`, `SegmentedControl`, `KeyField`) + panes.

**Modified files**
- `Sources/AIFuelGaugeApp/main.swift` — remove `DashboardView`, `SettingsView`, popover/settings subviews, `HistoryWindowView` (moved/rebuilt); add `heroLayout` to `AppPreferences`; restyle History inline or move it to `Popover.swift`. Keep `AIFuelGaugeAppDelegate`, `DashboardController`, status-item wiring, menu-bar label construction.

**New test files**
- `Tests/AIFuelGaugeCoreTests/DesignSystemTests.swift`
- `Tests/AIFuelGaugeCoreTests/HeroFocusTests.swift`

**Untouched:** all connectors, `AgentWorkbench`, `UsageBudgeting`, `UsageModels`, `UsageRefreshReconciler`, history stores, `AppUpdateChecker`, `OpenAIConnector`, `OpenRouterConnector`, `CursorUsageConnector`, `CodexUsageConnector`, `LocalAgentUsage`.

**Baseline check before starting:** Run `swift build` and `swift test` to confirm a green baseline. Expected: build succeeds, all tests pass.

---

## Phase 0 — Design System

### Task 1: oklch → sRGB converter (TDD)

**Files:**
- Create: `Sources/AIFuelGaugeCore/DesignSystem.swift`
- Test: `Tests/AIFuelGaugeCoreTests/DesignSystemTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AIFuelGaugeCoreTests/DesignSystemTests.swift
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
        let c = OKLCH.srgb(l: 0.5, c: 0.4, h: 25) // high chroma, may go out of gamut
        for v in [c.r, c.g, c.b] {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesignSystemTests`
Expected: FAIL — `OKLCH` is undefined / does not compile.

- [ ] **Step 3: Write the converter**

```swift
// Sources/AIFuelGaugeCore/DesignSystem.swift
import SwiftUI

/// Converts OKLCH color coordinates to gamma-encoded sRGB in [0,1].
/// Preserves the exact oklch values from handoff/source/assets/app.css.
public enum OKLCH {
    public static func srgb(l: Double, c: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180.0
        let a = c * cos(hr)
        let bb = c * sin(hr)

        let l_ = l + 0.3963377774 * a + 0.2158037573 * bb
        let m_ = l - 0.1055613458 * a - 0.0638541728 * bb
        let s_ = l - 0.0894841775 * a - 1.2914855480 * bb

        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        let r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let b = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return (gamma(r), gamma(g), gamma(b))
    }

    private static func gamma(_ v: Double) -> Double {
        let clamped = min(max(v, 0.0), 1.0)
        let encoded = clamped <= 0.0031308
            ? 12.92 * clamped
            : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
        return min(max(encoded, 0.0), 1.0)
    }

    /// Convenience: build a SwiftUI Color from oklch.
    public static func color(_ l: Double, _ c: Double, _ h: Double) -> Color {
        let rgb = srgb(l: l, c: c, h: h)
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1.0)
    }

    /// Convenience: oklch with explicit alpha.
    public static func color(_ l: Double, _ c: Double, _ h: Double, _ alpha: Double) -> Color {
        let rgb = srgb(l: l, c: c, h: h)
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: alpha)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DesignSystemTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeCore/DesignSystem.swift Tests/AIFuelGaugeCoreTests/DesignSystemTests.swift
git commit -m "feat: add OKLCH to sRGB color converter"
```

---

### Task 2: Color tokens (light/dark dynamic)

**Files:**
- Modify: `Sources/AIFuelGaugeCore/DesignSystem.swift`
- Test: `Tests/AIFuelGaugeCoreTests/DesignSystemTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `DesignSystemTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesignSystemTests`
Expected: FAIL — `FuelTheme` undefined.

- [ ] **Step 3: Implement the token layer**

Append to `DesignSystem.swift`. Hex values are copied verbatim from `handoff/source/assets/app.css` (`:root`/`[data-theme="dark"]`); state/accent colors use the oklch converter with the exact prototype values.

```swift
import AppKit

/// Builds a Color that resolves differently in light vs dark appearance.
private func dynamicColor(light: Color, dark: Color) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(isDark ? dark : light)
    })
}

private func hex(_ value: UInt32, _ alpha: Double = 1.0) -> Color {
    Color(.sRGB,
          red: Double((value >> 16) & 0xFF) / 255.0,
          green: Double((value >> 8) & 0xFF) / 255.0,
          blue: Double(value & 0xFF) / 255.0,
          opacity: alpha)
}

/// Central design tokens for the redesign. Mirrors handoff/source/assets/app.css.
public enum FuelTheme {
    // MARK: Brand accent (oklch)
    public static let accent     = dynamicColor(light: OKLCH.color(0.55, 0.16, 256), dark: OKLCH.color(0.68, 0.15, 256))
    public static let accentSoft = dynamicColor(light: OKLCH.color(0.55, 0.16, 256, 0.12), dark: OKLCH.color(0.68, 0.15, 256, 0.18))

    // MARK: Semantic state palette (oklch)
    public static let safe       = dynamicColor(light: OKLCH.color(0.66, 0.15, 150), dark: OKLCH.color(0.72, 0.16, 150))
    public static let caution    = dynamicColor(light: OKLCH.color(0.74, 0.14, 80),  dark: OKLCH.color(0.80, 0.14, 82))
    public static let critical   = dynamicColor(light: OKLCH.color(0.64, 0.18, 38),  dark: OKLCH.color(0.70, 0.18, 38))
    public static let exhausted  = dynamicColor(light: OKLCH.color(0.52, 0.18, 25),  dark: OKLCH.color(0.62, 0.19, 25))
    public static let unknown    = dynamicColor(light: OKLCH.color(0.62, 0.012, 260), dark: OKLCH.color(0.68, 0.012, 260))

    // MARK: Surfaces (hex from app.css)
    public static let canvas        = dynamicColor(light: hex(0xE9E9EC), dark: hex(0x161618))
    public static let canvas2       = dynamicColor(light: hex(0xDEDEDF), dark: hex(0x0E0E10))
    public static let surface       = dynamicColor(light: hex(0xFBFBFD), dark: hex(0x1F1F22))
    public static let surfaceRaised = dynamicColor(light: hex(0xFFFFFF), dark: hex(0x2A2A2E))
    public static let surfaceSunken = dynamicColor(light: hex(0xF1F1F4), dark: hex(0x161618))
    public static let surfaceHover  = dynamicColor(light: hex(0xF4F4F7), dark: hex(0x303035))
    public static let field         = dynamicColor(light: hex(0xFFFFFF), dark: hex(0x1A1A1D))

    // MARK: Text
    public static let text  = dynamicColor(light: hex(0x1C1C1E), dark: hex(0xF2F2F5))
    public static let text2 = dynamicColor(light: hex(0x5F5F66), dark: hex(0x9A9AA2))
    public static let text3 = dynamicColor(light: hex(0x8E8E96), dark: hex(0x6C6C74))

    // MARK: Lines / tracks
    public static let border       = dynamicColor(light: .black.opacity(0.09), dark: .white.opacity(0.10))
    public static let borderStrong = dynamicColor(light: .black.opacity(0.14), dark: .white.opacity(0.16))
    public static let divider      = dynamicColor(light: .black.opacity(0.065), dark: .white.opacity(0.075))
    public static let fieldBorder  = dynamicColor(light: .black.opacity(0.14), dark: .white.opacity(0.16))
    public static let track        = dynamicColor(light: .black.opacity(0.085), dark: .white.opacity(0.12))

    // MARK: Radii
    public static let radiusSM: CGFloat = 6
    public static let radiusMD: CGFloat = 10
    public static let radiusLG: CGFloat = 14
    public static let radiusXL: CGFloat = 18

    // MARK: State helpers
    public static func color(for state: UsageState) -> Color {
        switch state {
        case .safe: return safe
        case .caution: return caution
        case .critical: return critical
        case .exhausted: return exhausted
        case .unknown: return unknown
        }
    }
}

public extension Confidence {
    /// (label, SF Symbol name, color) for a TrustChip.
    var chip: (label: String, symbol: String, color: Color) {
        switch self {
        case .exact:     return ("Exact", "checkmark.seal", FuelTheme.safe)
        case .estimated: return ("Estimate", "info.circle", FuelTheme.text3)
        case .unknown:   return ("No limit", "minus.circle", FuelTheme.unknown)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DesignSystemTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeCore/DesignSystem.swift Tests/AIFuelGaugeCoreTests/DesignSystemTests.swift
git commit -m "feat: add light/dark design tokens"
```

---

### Task 3: Typography, shadows, and card modifiers

**Files:**
- Modify: `Sources/AIFuelGaugeCore/DesignSystem.swift`

- [ ] **Step 1: Add typography + shadow + card helpers**

Append to `DesignSystem.swift`. (No unit test — these are presentation constants; verified at build time and visually.)

```swift
public extension Font {
    /// Monospaced font for all numbers, %, $, and reset values.
    static func fuelMono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func fuelText(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Uppercase eyebrow label, e.g. "TIGHTEST LANE", "LANES".
    static let fuelEyebrow = Font.system(size: 10.5, weight: .semibold)
}

public struct FuelShadow {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
    /// Approximation of --shadow-pop.
    public static let pop = FuelShadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    /// Approximation of --shadow-win.
    public static let win = FuelShadow(color: .black.opacity(0.28), radius: 36, x: 0, y: 18)
}

public extension View {
    /// Raised card surface used by hero, reset, and settings cards.
    func fuelCard(radius: CGFloat = FuelTheme.radiusLG, padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(FuelTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FuelTheme.border, lineWidth: 1)
            )
    }
    func fuelShadow(_ shadow: FuelShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeCore/DesignSystem.swift
git commit -m "feat: add typography, shadow, and card helpers"
```

---

## Phase 1 — Hero focus helpers + heroLayout preference

### Task 4: Tightest-lane / hero-focus helpers (TDD)

**Files:**
- Create: `Sources/AIFuelGaugeCore/HeroFocus.swift`
- Test: `Tests/AIFuelGaugeCoreTests/HeroFocusTests.swift`

Pure functions over `[DashboardRow]`. "Tightest actionable lane" = the usable row with the highest `meterPercent` (most used / least room), preferring rows with a known `meterPercent`. Top-3 = first three of that ordering.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AIFuelGaugeCoreTests/HeroFocusTests.swift
import XCTest
@testable import AIFuelGaugeCore

final class HeroFocusTests: XCTestCase {
    private func row(_ id: String, percent: Double?, usable: Bool = true, state: UsageState = .caution) -> DashboardRow {
        DashboardRow(
            id: id, title: id, value: "", detail: "", dashboardURL: nil, explanation: "",
            meterPercent: percent, meterLabel: nil, trendPercents: [], trendCaption: nil,
            paceCaption: nil, receiptText: "", confidence: .exact, state: state,
            showsInUsableFilter: usable
        )
    }

    func testTightestLaneIsHighestUsableMeter() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90), row("c", percent: 0.55)]
        XCTAssertEqual(HeroFocus.tightestLane(rows)?.id, "b")
    }

    func testTightestLaneIgnoresNonUsableWhenUsableExist() {
        let rows = [row("a", percent: 0.95, usable: false), row("b", percent: 0.40, usable: true)]
        XCTAssertEqual(HeroFocus.tightestLane(rows)?.id, "b")
    }

    func testTightestLaneFallsBackToAllWhenNoUsable() {
        let rows = [row("a", percent: 0.95, usable: false), row("b", percent: 0.40, usable: false)]
        XCTAssertEqual(HeroFocus.tightestLane(rows)?.id, "a")
    }

    func testTopThreeOrderedByMeterDescending() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90), row("c", percent: 0.55), row("d", percent: 0.10)]
        XCTAssertEqual(HeroFocus.topLanes(rows, count: 3).map(\.id), ["b", "c", "a"])
    }

    func testResolveFocusReturnsPinnedRowWhenPresent() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90)]
        XCTAssertEqual(HeroFocus.resolve(rows, pinnedID: "a")?.id, "a")
    }

    func testResolveFocusFallsBackToTightestWhenPinMissing() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90)]
        XCTAssertEqual(HeroFocus.resolve(rows, pinnedID: "zzz")?.id, "b")
    }

    func testResolveFocusAutoWhenPinNil() {
        let rows = [row("a", percent: 0.30), row("b", percent: 0.90)]
        XCTAssertEqual(HeroFocus.resolve(rows, pinnedID: nil)?.id, "b")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HeroFocusTests`
Expected: FAIL — `HeroFocus` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/AIFuelGaugeCore/HeroFocus.swift
import Foundation

/// Pure selection helpers for the popover hero (Featured + Top-3 layouts).
public enum HeroFocus {
    /// Rows ordered tightest-first (highest meterPercent). Rows with no
    /// meterPercent sort last. Restricts to usable rows when any exist.
    public static func orderedTightest(_ rows: [DashboardRow]) -> [DashboardRow] {
        let usable = rows.filter(\.showsInUsableFilter)
        let pool = usable.isEmpty ? rows : usable
        return pool.sorted { lhs, rhs in
            (lhs.meterPercent ?? -1) > (rhs.meterPercent ?? -1)
        }
    }

    public static func tightestLane(_ rows: [DashboardRow]) -> DashboardRow? {
        orderedTightest(rows).first
    }

    public static func topLanes(_ rows: [DashboardRow], count: Int) -> [DashboardRow] {
        Array(orderedTightest(rows).prefix(count))
    }

    /// Hero focus: the pinned row if it still exists, else the tightest lane.
    public static func resolve(_ rows: [DashboardRow], pinnedID: String?) -> DashboardRow? {
        if let pinnedID, let pinned = rows.first(where: { $0.id == pinnedID }) {
            return pinned
        }
        return tightestLane(rows)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HeroFocusTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeCore/HeroFocus.swift Tests/AIFuelGaugeCoreTests/HeroFocusTests.swift
git commit -m "feat: add hero focus and tightest-lane helpers"
```

---

### Task 5: Add `heroLayout` preference

**Files:**
- Modify: `Sources/AIFuelGaugeCore/UsageModels.swift` (add enum near `MenuBarDisplayMode`)
- Modify: `Sources/AIFuelGaugeApp/main.swift` (`AppPreferences`: add key, default, accessor)

- [ ] **Step 1: Add the enum**

In `Sources/AIFuelGaugeCore/UsageModels.swift`, directly after the `MenuBarProviderFocus` enum, add:

```swift
public enum HeroLayout: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case featured
    case trio
}
```

- [ ] **Step 2: Add the preference key + default + accessor**

In `main.swift` `AppPreferences`, alongside `menuBarDisplayModeKey` / `menuBarProviderFocusKey`:

```swift
    static let heroLayoutKey = "heroLayout"
```

In `registerDefaults()`'s defaults dictionary, add:

```swift
            heroLayoutKey: HeroLayout.featured.rawValue,
```

Add the accessor near `menuBarProviderFocus`:

```swift
    static var heroLayout: HeroLayout {
        let raw = UserDefaults.standard.string(forKey: heroLayoutKey) ?? HeroLayout.featured.rawValue
        return HeroLayout(rawValue: raw) ?? .featured
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 4: Commit**

```bash
git add Sources/AIFuelGaugeCore/UsageModels.swift Sources/AIFuelGaugeApp/main.swift
git commit -m "feat: add heroLayout preference"
```

---

## Phase 2 — Popover primitive components

> These views are layout-faithful to `handoff/source/assets/data.jsx`. Where exact spacing/sizes are unspecified below, read the prototype component of the same name. Verify visually against `handoff/screenshots/02,03,04,14`. Each task ends with `swift build` (UI is not unit-tested) and a commit.

### Task 6: Create `Popover.swift` with `ArcGauge`

**Files:**
- Create: `Sources/AIFuelGaugeApp/Popover.swift`

The arc is a 259° sweep (matches `ArcGauge` in `data.jsx`): a gray track plus a state-colored value arc, with a centered mono value + caption. Start angle is chosen so the 259° arc is bottom-centered with a gap at the bottom (gap = 360−259 = 101°; start = 90° + 101/2 = 140.5°, sweep clockwise 259°).

- [ ] **Step 1: Write `ArcGauge`**

```swift
// Sources/AIFuelGaugeApp/Popover.swift
import SwiftUI
import AIFuelGaugeCore

/// 259° arc gauge. `percent` in 0...1, colored by `state`.
struct ArcGauge: View {
    let percent: Double
    let state: UsageState
    var value: String
    var caption: String = "USED"
    var diameter: CGFloat = 132
    var lineWidth: CGFloat = 12

    private let sweep = 259.0
    private var startAngle: Angle { .degrees(90 + (360 - sweep) / 2) }
    private var trim: CGFloat { CGFloat(sweep / 360.0) }
    private var clamped: Double { min(max(percent, 0), 1) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: trim)
                .stroke(FuelTheme.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(startAngle)
            // Value arc
            Circle()
                .trim(from: 0, to: trim * CGFloat(clamped))
                .stroke(FuelTheme.color(for: state), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(startAngle)
            // Center label
            VStack(spacing: 0) {
                Text(value).font(.fuelMono(28, weight: .semibold)).foregroundStyle(FuelTheme.text)
                Text(caption).font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.4), value: clamped)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift
git commit -m "feat: add ArcGauge component"
```

---

### Task 7: `Meter`, `Sparkline`, `TrustChip`, `StatePill`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Popover.swift`

- [ ] **Step 1: Add the components**

```swift
/// Linear capsule meter. Striped variant for unknown / no-limit sources.
struct Meter: View {
    let percent: Double?   // nil => no-limit striped bar
    let state: UsageState
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FuelTheme.track)
                if let percent {
                    Capsule()
                        .fill(FuelTheme.color(for: state))
                        .frame(width: max(0, min(1, percent)) * geo.size.width)
                } else {
                    Capsule()
                        .fill(.linearGradient(
                            stops: [.init(color: FuelTheme.unknown.opacity(0.5), location: 0),
                                    .init(color: FuelTheme.unknown.opacity(0.15), location: 1)],
                            startPoint: .leading, endPoint: .trailing))
                }
            }
        }
        .frame(height: height)
    }
}

/// 7-point trend sparkline, state-colored line + soft area fill.
struct Sparkline: View {
    let points: [Double]
    let state: UsageState

    var body: some View {
        GeometryReader { geo in
            let pts = normalizedPoints(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    areaPath(pts, height: geo.size.height).fill(FuelTheme.color(for: state).opacity(0.14))
                    linePath(pts).stroke(FuelTheme.color(for: state),
                                         style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 28)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let lo = points.min() ?? 0, hi = points.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
        return points.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height - CGFloat((v - lo) / span) * size.height)
        }
    }
    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path(); p.addLines(pts); return p
    }
    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = Path()
        guard let first = pts.first, let last = pts.last else { return p }
        p.move(to: CGPoint(x: first.x, y: height))
        p.addLine(to: first); pts.dropFirst().forEach { p.addLine(to: $0) }
        p.addLine(to: CGPoint(x: last.x, y: height)); p.closeSubpath()
        return p
    }
}

/// Exact / Estimate / No-limit trust chip.
struct TrustChip: View {
    let confidence: Confidence
    var body: some View {
        let chip = confidence.chip
        return HStack(spacing: 4) {
            Image(systemName: chip.symbol).font(.system(size: 9, weight: .semibold))
            Text(chip.label).font(.fuelText(10.5, weight: .medium))
        }
        .foregroundStyle(chip.color)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(chip.color.opacity(0.12), in: Capsule())
    }
}

/// Header state pill, e.g. "Almost out".
struct StatePill: View {
    let state: UsageState
    var label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(FuelTheme.color(for: state)).frame(width: 6, height: 6)
            Text(label).font(.fuelText(11.5, weight: .semibold))
        }
        .foregroundStyle(FuelTheme.text2)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(FuelTheme.color(for: state).opacity(0.12), in: Capsule())
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift
git commit -m "feat: add Meter, Sparkline, TrustChip, StatePill"
```

---

## Phase 3 — Popover assembly

### Task 8: `HeroFeaturedCard` + `FocusPill`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Popover.swift`

Layout target: `handoff/screenshots/02-popover-featured.png` and `HeroCard`/`FocusPill` in `popover.jsx`.

- [ ] **Step 1: Add the views**

```swift
/// In-popover focus selector ("Auto ▾" or a pinned provider). Transient — does
/// not change the menu bar. `rows` are the focusable lanes.
struct FocusPill: View {
    let rows: [DashboardRow]
    @Binding var pinnedID: String?

    var body: some View {
        Menu {
            Button("Auto") { pinnedID = nil }
            Divider()
            ForEach(rows) { row in
                Button(row.title) { pinnedID = row.id }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: pinnedID == nil ? "bolt.fill" : "pin.fill").font(.system(size: 9))
                Text(pinnedID == nil ? "Auto" : (rows.first { $0.id == pinnedID }?.title ?? "Auto"))
                    .font(.fuelText(11.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(FuelTheme.text)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(FuelTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous).strokeBorder(FuelTheme.border))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }
}

struct HeroFeaturedCard: View {
    let row: DashboardRow
    let allRows: [DashboardRow]
    let insight: String
    let resetCaption: String?   // e.g. "Resets in 47m"
    @Binding var pinnedID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArcGauge(percent: row.meterPercent ?? 0, state: row.state,
                     value: percentText, caption: "USED")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TIGHTEST LANE").font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
                    Spacer()
                    FocusPill(rows: allRows, pinnedID: $pinnedID)
                }
                Text(row.title).font(.fuelText(17, weight: .bold)).foregroundStyle(FuelTheme.text)
                Text(row.detail).font(.fuelText(12)).foregroundStyle(FuelTheme.text2)
                if !insight.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(FuelTheme.safe)
                        Text(insight).font(.fuelText(12, weight: .semibold)).foregroundStyle(FuelTheme.text)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FuelTheme.safe.opacity(0.12), in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
                }
                if let resetCaption {
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(FuelTheme.text3)
                        Text(resetCaption).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text2)
                    }
                }
            }
        }
        .fuelCard(radius: FuelTheme.radiusLG, padding: 16)
    }

    private var percentText: String {
        guard let p = row.meterPercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift
git commit -m "feat: add HeroFeaturedCard and FocusPill"
```

---

### Task 9: `HeroTrioCard`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Popover.swift`

Layout target: `handoff/screenshots/03-popover-top3.png`.

- [ ] **Step 1: Add the view**

```swift
struct HeroTrioCard: View {
    let rows: [DashboardRow]   // already top-3 ordered

    var body: some View {
        HStack(spacing: 12) {
            ForEach(rows) { row in
                VStack(spacing: 6) {
                    ArcGauge(percent: row.meterPercent ?? 0, state: row.state,
                             value: percentText(row), caption: "", diameter: 84, lineWidth: 8)
                    Text(row.title).font(.fuelText(12.5, weight: .semibold)).foregroundStyle(FuelTheme.text)
                    Text(row.detail).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fuelCard(radius: FuelTheme.radiusLG, padding: 16)
    }

    private func percentText(_ row: DashboardRow) -> String {
        guard let p = row.meterPercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift
git commit -m "feat: add HeroTrioCard"
```

---

### Task 10: `LaneRow`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Popover.swift`

Layout target: lane rows in `handoff/screenshots/02` and the expanded details in `04`. Replaces the old `SourceRowView`. `onCopy`/`onOpen`/`onPin` are passed in; details toggle is per-row local state.

- [ ] **Step 1: Add the view**

```swift
struct LaneRow: View {
    let row: DashboardRow
    let isPinned: Bool
    let showDetails: Bool
    let onPin: () -> Void
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(FuelTheme.color(for: row.state)).frame(width: 8, height: 8)
                Text(row.title).font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
                Text(row.detail).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3).lineLimit(1)
                Spacer()
                Text(row.value).font(.fuelMono(13)).foregroundStyle(FuelTheme.text)
                laneButton("pin.fill", active: isPinned, action: onPin)
                laneButton("doc.on.doc", action: onCopy)
                if row.dashboardURL != nil { laneButton("arrow.up.right.square", action: onOpen) }
            }
            Meter(percent: row.meterPercent, state: row.state)
            if let label = row.meterLabel {
                Text(label).font(.fuelText(11)).foregroundStyle(FuelTheme.color(for: row.state))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if showDetails {
                if !row.trendPercents.isEmpty {
                    HStack(spacing: 8) {
                        Sparkline(points: row.trendPercents, state: row.state).frame(width: 90)
                        TrustChip(confidence: row.confidence)
                        if let trend = row.trendCaption {
                            Text(trend).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                        }
                        Spacer()
                    }
                }
                if let pace = row.paceCaption {
                    Label(pace, systemImage: "checkmark").labelStyle(.titleAndIcon)
                        .font(.fuelText(11.5)).foregroundStyle(FuelTheme.text2)
                }
                if !row.receiptText.isEmpty {
                    Label(row.receiptText, systemImage: "info.circle").labelStyle(.titleAndIcon)
                        .font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
    }

    private func laneButton(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(active ? FuelTheme.accent : FuelTheme.text3)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift
git commit -m "feat: add LaneRow"
```

---

### Task 11: `ResetContextStrip` + `ActionBar`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Popover.swift`

`ResetContextStrip` renders up to three reset cards; reset data is derived in the assembly task from `model.rows` (see Task 12). `ActionBar` exposes Refresh / Settings / History + an overflow menu and the trust tally line.

- [ ] **Step 1: Add the views**

```swift
struct ResetCard: View {
    let eyebrow: String
    let value: String
    let caption: String
    let state: UsageState
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow).font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            Text(value).font(.fuelMono(15)).foregroundStyle(FuelTheme.color(for: state))
            Text(caption).font(.fuelText(11)).foregroundStyle(FuelTheme.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fuelCard(radius: FuelTheme.radiusMD, padding: 10)
    }
}

struct ResetContextStrip: View {
    struct Item: Identifiable { let id = UUID(); let eyebrow: String; let value: String; let caption: String; let state: UsageState }
    let items: [Item]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { ResetCard(eyebrow: $0.eyebrow, value: $0.value, caption: $0.caption, state: $0.state) }
        }
    }
}

struct ActionBar: View {
    let trustTally: String
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onHistory: () -> Void
    let onCopySnapshot: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").font(.system(size: 10)).foregroundStyle(FuelTheme.safe)
                Text(trustTally).font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                Spacer()
            }
            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderedProminent).tint(FuelTheme.accent)
                Button(action: onSettings) { Label("Settings", systemImage: "gearshape") }.buttonStyle(.bordered)
                Button(action: onHistory) { Label("History", systemImage: "chart.xyaxis.line") }.buttonStyle(.bordered)
                Spacer()
                Menu {
                    Button("Copy snapshot", action: onCopySnapshot)
                    Button("About", action: onAbout)
                    Divider()
                    Button("Quit AI Fuel Gauge", action: onQuit)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14)).foregroundStyle(FuelTheme.text3)
                }.menuStyle(.borderlessButton).fixedSize()
            }
            .font(.fuelText(12, weight: .semibold))
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift
git commit -m "feat: add ResetContextStrip and ActionBar"
```

---

### Task 12: Rebuild `DashboardView` and move it into `Popover.swift`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Popover.swift` (add `DashboardView`)
- Modify: `Sources/AIFuelGaugeApp/main.swift` (remove the old `DashboardView` + its popover-only subviews: `InsightStrip`, `UnknownGaugeView`, `EmptySourcesView`, `SourceRowView`, `UsageSparkline`, `MiniMeter`, `StatePill` (old), `FooterButton`, `ResetContextStrip` (old), and the old hero/header helpers). Keep `DashboardActions`, `WorkbenchSection` + its row subviews (reuse), `LaneFramePreferenceKey`, `SetupGuidanceView`.

> Reuse the existing `WorkbenchSection`, `WorkbenchSessionRow`, `WorkbenchServerRow`, `WorkbenchRouteButton` as-is for now (they are restyled in Task 13). Preserve existing lane filter (`LaneFilter`), reorder, and per-row details behavior; the prototype keeps Usable/All + count + reorder + details toggles.

- [ ] **Step 1: Note the existing `DashboardView` API**

Open `main.swift`, locate `private struct DashboardView` (currently ~line 840). Record its inputs: `@ObservedObject var controller: DashboardController`, `let actions: DashboardActions`. The new view keeps the same initializer signature so call sites are unchanged.

- [ ] **Step 2: Add the new `DashboardView` to `Popover.swift`**

```swift
struct DashboardView: View {
    @ObservedObject var controller: DashboardController
    let actions: DashboardActions

    @State private var laneFilter: LaneFilter = .usable
    @State private var detailRowIDs: Set<String> = []
    @State private var heroPinnedID: String?
    @AppStorage(AppPreferences.heroLayoutKey) private var heroLayoutRaw = HeroLayout.featured.rawValue

    private var model: DashboardViewModel { controller.model }
    private var heroLayout: HeroLayout { HeroLayout(rawValue: heroLayoutRaw) ?? .featured }

    private var visibleRows: [DashboardRow] {
        switch laneFilter {
        case .usable:
            let usable = model.rows.filter(\.showsInUsableFilter)
            return usable.isEmpty ? model.rows : usable
        case .all:
            return model.rows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            heroSection
            laneToolbar
            laneList
            ResetContextStrip(items: resetItems)
            WorkbenchSection(snapshot: controller.workbench, actions: actions)
            ActionBar(
                trustTally: model.footerNote,
                onRefresh: actions.refresh,
                onSettings: actions.openSettings,
                onHistory: actions.openHistory,
                onCopySnapshot: actions.copySnapshot,
                onAbout: actions.openAbout,
                onQuit: actions.quit
            )
        }
        .padding(16)
        .frame(width: 360)
        .background(FuelTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Fuel Gauge").font(.fuelText(14, weight: .bold)).foregroundStyle(FuelTheme.text)
                Text(model.statusLabel).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3)
            }
            Spacer()
            StatePill(state: model.state, label: stateLabel)
        }
    }

    @ViewBuilder private var heroSection: some View {
        if heroLayout == .trio {
            HeroTrioCard(rows: HeroFocus.topLanes(model.rows, count: 3))
        } else if let focus = HeroFocus.resolve(model.rows, pinnedID: heroPinnedID) {
            HeroFeaturedCard(row: focus, allRows: model.rows, insight: model.insight,
                             resetCaption: focus.meterLabel, pinnedID: $heroPinnedID)
        }
    }

    private var laneToolbar: some View {
        HStack(spacing: 8) {
            Text("LANES").font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            Picker("", selection: $laneFilter) {
                Text("Usable").tag(LaneFilter.usable)
                Text("All").tag(LaneFilter.all)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Text("\(visibleRows.count)").font(.fuelMono(11)).foregroundStyle(FuelTheme.text3)
            Spacer()
            // Hero layout quick-toggle (Featured / Top-3)
            Picker("", selection: $heroLayoutRaw) {
                Image(systemName: "gauge.medium").tag(HeroLayout.featured.rawValue)
                Image(systemName: "square.grid.3x1.below.line.grid.1x2").tag(HeroLayout.trio.rawValue)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private var laneList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    LaneRow(
                        row: row,
                        isPinned: heroPinnedID == row.id,
                        showDetails: detailRowIDs.contains(row.id),
                        onPin: { heroPinnedID = (heroPinnedID == row.id) ? nil : row.id },
                        onCopy: { actions.copyRow(row) },
                        onOpen: { actions.openRowURL(row) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { toggleDetails(row.id) }
                    if row.id != visibleRows.last?.id {
                        Divider().background(FuelTheme.divider).padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
        .background(FuelTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
    }

    private func toggleDetails(_ id: String) {
        if detailRowIDs.contains(id) { detailRowIDs.remove(id) } else { detailRowIDs.insert(id) }
    }

    private var stateLabel: String {
        switch model.state {
        case .safe: return "Healthy"
        case .caution: return "Getting tight"
        case .critical: return "Almost out"
        case .exhausted: return "Spent"
        case .unknown: return "Estimating"
        }
    }

    private var resetItems: [ResetContextStrip.Item] {
        HeroFocus.topLanes(model.rows, count: 3).compactMap { row in
            guard let label = row.meterLabel else { return nil }
            return ResetContextStrip.Item(eyebrow: "RESET", value: label, caption: row.title, state: row.state)
        }
    }
}
```

> **Note on `DashboardActions`:** the existing struct (in `main.swift`, ~line 825) currently has fields like `refresh`, `openSettings`, etc. Check its actual members. If `openHistory`, `copySnapshot`, `openAbout`, `quit`, `copyRow`, `openRowURL` are not all present, add the missing closures to `DashboardActions` and populate them at the call site in `AIFuelGaugeAppDelegate` (the delegate already implements history/settings/quit actions — wire to those existing methods). Do not invent new behavior; reuse the delegate's existing handlers.

- [ ] **Step 3: Delete the old `DashboardView` and obsolete subviews from `main.swift`**

Remove from `main.swift`: `DashboardView` (old), `InsightStrip`, `UnknownGaugeView`, `EmptySourcesView`, `SourceRowView`, `UsageSparkline`, `MiniMeter`, the old `StatePill`, `FooterButton`, and the old `ResetContextStrip`/hero helpers. Keep `WorkbenchSection` & workbench row subviews, `LaneFramePreferenceKey` (only if still referenced — otherwise remove), `SetupGuidanceView`, `DashboardActions`.

Ensure `BrandMark` is accessible to `Popover.swift` (it is defined in `main.swift`/app target — same module, so no import needed beyond `AIFuelGaugeCore`).

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds successfully. Resolve any missing-member errors on `DashboardActions` per the note in Step 2.

- [ ] **Step 5: Run the existing test suite**

Run: `swift test`
Expected: all tests pass (no core logic changed).

- [ ] **Step 6: Visual verification**

Run the app: `swift run AIFuelGaugeApp` (or `make run` if defined). Open the popover. Confirm against `handoff/screenshots/02` (featured), toggle the layout control to confirm `03` (top-3), tap a lane to confirm details (`04`), and switch macOS appearance to confirm dark (`14`). Fix spacing/color discrepancies against the prototype.

- [ ] **Step 7: Commit**

```bash
git add Sources/AIFuelGaugeApp/Popover.swift Sources/AIFuelGaugeApp/main.swift
git commit -m "feat: rebuild popover dashboard view to redesign"
```

---

### Task 13: Restyle `WorkbenchSection`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/main.swift` (or move the workbench views into `Popover.swift`)

Layout target: collapsible Workbench in `handoff/screenshots/04` (collapsed) and `13` (expanded: SESSIONS / DEV SERVERS columns).

- [ ] **Step 1: Update styling**

Re-skin `WorkbenchSection`, `WorkbenchSessionRow`, `WorkbenchServerRow`, `WorkbenchRouteButton` to the new tokens: `fuelCard` container, `FuelTheme.text/text2/text3`, mono for port numbers and counts, eyebrow labels for "SESSIONS"/"DEV SERVERS". Keep the existing data inputs and collapse behavior; only change colors, fonts, padding, and the header chevron to match the prototype. (Move these structs into `Popover.swift` if it keeps related code together — optional.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Visual verification**

Run the app, expand the Workbench, compare to `handoff/screenshots/13`.

- [ ] **Step 4: Commit**

```bash
git add Sources/AIFuelGaugeApp
git commit -m "feat: restyle Workbench section"
```

---

## Phase 4 — Settings

### Task 14: Create `Settings.swift` with the form kit

**Files:**
- Create: `Sources/AIFuelGaugeApp/Settings.swift`

Reference: `handoff/source/assets/settings.jsx` (`Switch`, `Row`, `Group`, `Segmented`, `KeyField`) and screenshots `05`–`12`, `15`.

- [ ] **Step 1: Add the form kit**

```swift
// Sources/AIFuelGaugeApp/Settings.swift
import SwiftUI
import AIFuelGaugeCore

/// Titled card section. `title` rendered as an eyebrow above a rounded card.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.fuelEyebrow).foregroundStyle(FuelTheme.text3)
            VStack(spacing: 0) { content }
                .background(FuelTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: FuelTheme.radiusMD, style: .continuous).strokeBorder(FuelTheme.border))
        }
    }
}

/// Label + helper + trailing control, with an icon well.
struct SettingsRow<Control: View>: View {
    let icon: String?
    let title: String
    let helper: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(FuelTheme.text2)
                    .frame(width: 28, height: 28)
                    .background(FuelTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: FuelTheme.radiusSM, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.fuelText(13, weight: .semibold)).foregroundStyle(FuelTheme.text)
                if let helper { Text(helper).font(.fuelText(11.5)).foregroundStyle(FuelTheme.text3) }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// Pane scaffold: big title + subtitle, then content.
struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.fuelText(20, weight: .bold)).foregroundStyle(FuelTheme.text)
                    Text(subtitle).font(.fuelText(12.5)).foregroundStyle(FuelTheme.text2)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Settings.swift
git commit -m "feat: add settings form kit"
```

---

### Task 15: Settings sidebar + `SettingsView` shell

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Settings.swift`

- [ ] **Step 1: Add the navigation shell**

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, providers, apiKeys, alerts, menuBar, budgets, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .providers: return "Providers"
        case .apiKeys: return "API Keys"
        case .alerts: return "Alerts"
        case .menuBar: return "Menu Bar"
        case .budgets: return "Budgets"
        case .privacy: return "Data & Privacy"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "dot.radiowaves.left.and.right"
        case .apiKeys: return "key"
        case .alerts: return "bell"
        case .menuBar: return "menubar.rectangle"
        case .budgets: return "dollarsign.circle"
        case .privacy: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                } header: {
                    HStack(spacing: 8) {
                        BrandMark(size: 18)
                        Text("AI Fuel Gauge").font(.fuelText(13, weight: .bold)).foregroundStyle(FuelTheme.text)
                    }.padding(.bottom, 4)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield").font(.system(size: 10)).foregroundStyle(FuelTheme.safe)
                    Text("Local-first · \(appVersionString)").font(.fuelText(11)).foregroundStyle(FuelTheme.text3)
                    Spacer()
                }.padding(12)
            }
        } detail: {
            detailPane.frame(minWidth: 460)
        }
        .frame(width: 760, height: 600)
    }

    @ViewBuilder private var detailPane: some View {
        switch selection {
        case .general:   GeneralPane()
        case .providers: ProvidersPane()
        case .apiKeys:   APIKeysPane()
        case .alerts:    AlertsPane()
        case .menuBar:   MenuBarPane()
        case .budgets:   BudgetsPane()
        case .privacy:   PrivacyPane()
        case .about:     AboutPane()
        }
    }

    private var appVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "v\($0)" } ?? "local build"
    }
}
```

> The 8 pane structs are added in Tasks 16–18. To keep the build green incrementally, add temporary stubs now (e.g. `struct GeneralPane: View { var body: some View { SettingsPane(title: "General", subtitle: "") { EmptyView() } } }`) for every pane, then replace each stub in the following tasks.

- [ ] **Step 2: Add stub panes, then build**

Add a minimal stub for each of the 8 panes (as above). Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIFuelGaugeApp/Settings.swift
git commit -m "feat: add settings sidebar shell with stub panes"
```

---

### Task 16: General, Menu Bar, and Budgets panes

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Settings.swift`

These bind to existing preferences. **Read the old `SettingsView` in `main.swift` (~line 1874–2768)** to copy the exact bindings, key names, formatters, and option lists — do not invent values. The data/logic is identical; only the layout changes.

- [ ] **Step 1: Implement `GeneralPane`**

Reference screenshot `06`. Refresh cadence segmented (1m/3m/5m/15m → seconds) + start-at-login switch. Reuse the existing `@AppStorage`/binding the old settings used for refresh interval and the existing launch-agent enable/disable calls.

```swift
struct GeneralPane: View {
    @AppStorage(AppPreferences.refreshIntervalKey) private var refreshSeconds = 180.0  // confirm key name in main.swift
    @State private var startAtLogin = false  // initialize from LaunchAgent.statusMessage() like the old pane

    private let cadences: [(label: String, seconds: Double)] = [("1m", 60), ("3m", 180), ("5m", 300), ("15m", 900)]

    var body: some View {
        SettingsPane(title: "General",
                     subtitle: "How often AI Fuel Gauge refreshes in the background, and whether it starts with your Mac.") {
            SettingsGroup(title: "Auto-sync") {
                SettingsRow(icon: "arrow.clockwise", title: "Refresh cadence",
                            helper: "Background polling interval. Manual refresh always works instantly.") {
                    Picker("", selection: $refreshSeconds) {
                        ForEach(cadences, id: \.seconds) { Text($0.label).tag($0.seconds) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsGroup(title: "Startup") {
                SettingsRow(icon: "power", title: "Start at login",
                            helper: "Recreate the launch agent so the gauge is always in your menu bar.") {
                    Toggle("", isOn: $startAtLogin).labelsHidden().toggleStyle(.switch)
                        .tint(FuelTheme.accent)
                        // .onChange: call the existing LaunchAgent.enable()/disable() used by the old pane
                }
            }
        }
    }
}
```

> Confirm `AppPreferences.refreshIntervalKey` exists; if the old code used a different key constant, use that. Wire `startAtLogin` to the same launch-agent helper the old pane used (search `main.swift` for `LaunchAgent` / `enable()` / `statusMessage()`).

- [ ] **Step 2: Implement `MenuBarPane`**

Reference screenshot `09`. Live preview + Label detail (`MenuBarDisplayMode`: Detail/Pair/Trend/Compact/Min) + Provider focus (`MenuBarProviderFocus`) + hero layout default.

```swift
struct MenuBarPane: View {
    @AppStorage(AppPreferences.menuBarDisplayModeKey) private var displayMode = MenuBarDisplayMode.detailed.rawValue
    @AppStorage(AppPreferences.menuBarProviderFocusKey) private var providerFocus = MenuBarProviderFocus.auto.rawValue
    @AppStorage(AppPreferences.heroLayoutKey) private var heroLayout = HeroLayout.featured.rawValue

    var body: some View {
        SettingsPane(title: "Menu bar",
                     subtitle: "Control how much the menu-bar label shows, and which provider drives it.") {
            SettingsGroup(title: "Preview") {
                HStack {
                    Spacer()
                    // Static representative preview; mirrors the old pane's preview string.
                    Text("◐ Claude 5h · 19% · 47m")
                        .font(.fuelMono(12)).foregroundStyle(FuelTheme.critical)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(FuelTheme.surfaceSunken, in: Capsule())
                    Spacer()
                }.padding(.vertical, 14)
            }
            SettingsGroup(title: "Display density") {
                SettingsRow(icon: nil, title: "Label detail", helper: "From full detail down to a single status glyph.") {
                    Picker("", selection: $displayMode) {
                        Text("Detail").tag(MenuBarDisplayMode.detailed.rawValue)
                        Text("Pair").tag(MenuBarDisplayMode.pair.rawValue)
                        Text("Trend").tag(MenuBarDisplayMode.trend.rawValue)
                        Text("Compact").tag(MenuBarDisplayMode.compact.rawValue)
                        Text("Min").tag(MenuBarDisplayMode.minimal.rawValue)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Divider().background(FuelTheme.divider).padding(.leading, 14)
                SettingsRow(icon: nil, title: "Provider focus", helper: "Auto picks the tightest useful lane. Pin one to always lead.") {
                    Picker("", selection: $providerFocus) {
                        ForEach(MenuBarProviderFocus.allCases, id: \.rawValue) { Text(focusLabel($0)).tag($0.rawValue) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsGroup(title: "Popover hero") {
                SettingsRow(icon: nil, title: "Default layout", helper: "Featured shows one big gauge; Top 3 shows three compact gauges.") {
                    Picker("", selection: $heroLayout) {
                        Text("Featured").tag(HeroLayout.featured.rawValue)
                        Text("Top 3").tag(HeroLayout.trio.rawValue)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }

    private func focusLabel(_ focus: MenuBarProviderFocus) -> String {
        // Reuse the display name the old pane used; fall back to capitalized rawValue.
        focus == .auto ? "Auto" : focus.rawValue.capitalized
    }
}
```

> Confirm the `MenuBarDisplayMode` case at UsageModels.swift:52 (between `pair` and `compact`) — it is `trend`; verify and use the real case name. Copy the provider-focus option labels from the old pane.

- [ ] **Step 3: Implement `BudgetsPane`**

Reference screenshot `10`. Monthly guardrail fields (OpenAI / Cursor / OpenRouter), reusing `AppPreferences.budgetPreferences()` and the existing save path.

```swift
struct BudgetsPane: View {
    // Bind to the same storage the old budgets pane used. Use @State seeded from
    // AppPreferences.budgetPreferences() and persist on change exactly as before.
    @State private var openAI = ""
    @State private var cursor = ""
    @State private var openRouter = ""

    var body: some View {
        SettingsPane(title: "Budgets",
                     subtitle: "Optional monthly guardrails turn raw spend rows into comparable warning lanes. Leave blank to show spend only — never an invented limit.") {
            SettingsGroup(title: "Monthly guardrails") {
                budgetRow("OpenAI", helper: "Turns month-to-date spend into a budget lane.", text: $openAI, prefix: "$")
                Divider().background(FuelTheme.divider).padding(.leading, 14)
                budgetRow("Cursor", helper: "Optional spend guardrail for Cursor spend rows.", text: $cursor, prefix: "$")
                Divider().background(FuelTheme.divider).padding(.leading, 14)
                budgetRow("OpenRouter", helper: "Optional key-usage guardrail in credits.", text: $openRouter, prefix: nil)
            }
        }
        // .onAppear: seed from AppPreferences.budgetPreferences(); .onChange: persist via the old save call.
    }

    private func budgetRow(_ title: String, helper: String, text: Binding<String>, prefix: String?) -> some View {
        SettingsRow(icon: "dollarsign", title: title, helper: helper) {
            HStack(spacing: 4) {
                if let prefix { Text(prefix).font(.fuelMono(12)).foregroundStyle(FuelTheme.text3) }
                TextField("", text: text).textFieldStyle(.roundedBorder).frame(width: 90).font(.fuelMono(12))
            }
        }
    }
}
```

> Replace `@State` seeding/persistence with the exact `budgetPreferences()` read and save used by the old pane (find it in `main.swift`).

- [ ] **Step 4: Build + visual verify**

Run: `swift build`, then `swift run AIFuelGaugeApp`, open Settings, compare General/Menu Bar/Budgets to screenshots `06`/`09`/`10` (light) and toggle appearance for dark.
Expected: builds; panes match.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeApp/Settings.swift
git commit -m "feat: implement General, Menu Bar, and Budgets settings panes"
```

---

### Task 17: Providers, API Keys, and Alerts panes

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Settings.swift`
- Reuse: existing `ProviderMonitorRow`, `AlertProfileRow`, `EditablePlanRow`, `EditableTextPlanRow` from `main.swift` (move them into `Settings.swift` and re-skin, or wrap them).

- [ ] **Step 1: Implement `ProvidersPane`**

Reference screenshot `05`. Monitored-source toggles with plan badges + plan-label overrides. Reuse `AppPreferences.monitoredProviders` and the existing per-provider toggle persistence. Render each provider as a `SettingsRow` with a trailing `Toggle(.switch)` tinted `FuelTheme.accent`, plus a small capsule badge (Plus / Pro / Max 5x / needs key) next to the title. Below, a "Plan label overrides" `SettingsGroup` reusing the existing editable plan rows.

> Pull the provider list, descriptions, badges, and toggle bindings from the old Providers panel in `main.swift`. Do not change which providers exist or their semantics.

- [ ] **Step 2: Implement `APIKeysPane`**

Reference screenshot `07`. A `KeyField` per provider (OpenRouter, OpenAI admin) with a secure entry, a "Connected" state, and a sanitized status line. Reuse the existing keychain calls (`KeychainStore.readOpenRouterKey()`, `saveOpenRouterKey`, `deleteOpenRouterKey`, and the OpenAI equivalents — confirm names in `main.swift` ~line 2890). Define `KeyField`:

```swift
struct KeyField: View {
    let title: String
    let helper: String
    @Binding var value: String
    let isConnected: Bool
    let status: String
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        SettingsRow(icon: "key", title: title, helper: helper) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.fuelText(11, weight: .semibold)).foregroundStyle(FuelTheme.safe)
                    }
                    SecureField("Paste key", text: $value).textFieldStyle(.roundedBorder).frame(width: 180)
                    Button("Save", action: onSave).buttonStyle(.bordered)
                    if isConnected { Button("Clear", action: onClear).buttonStyle(.borderless) }
                }
                if !status.isEmpty { Text(status).font(.fuelText(10.5)).foregroundStyle(FuelTheme.text3) }
            }
        }
    }
}
```

> Wire `isConnected`/`status` from the existing keychain read + the old pane's sanitized status logic.

- [ ] **Step 3: Implement `AlertsPane`**

Reference screenshots `08`/`15`. Reuse `AppPreferences.alertThresholds()` / `alertThresholdsByProvider()` and the existing `AlertProfileRow`. Wrap each alert profile in a `SettingsGroup`/`SettingsRow` styling. Keep the existing threshold-editing behavior.

- [ ] **Step 4: Build + visual verify**

Run: `swift build`, then run the app and compare Providers/API Keys/Alerts to `05`/`07`/`08` (and `15` dark).
Expected: builds; panes match; saving a key still persists (verify "Connected" appears after save).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeApp/Settings.swift Sources/AIFuelGaugeApp/main.swift
git commit -m "feat: implement Providers, API Keys, and Alerts settings panes"
```

---

### Task 18: Data & Privacy and About panes; remove old `SettingsView`

**Files:**
- Modify: `Sources/AIFuelGaugeApp/Settings.swift`
- Modify: `Sources/AIFuelGaugeApp/main.swift` (delete the old `SettingsView` + `SettingsPanel` + now-moved helper rows)

- [ ] **Step 1: Implement `PrivacyPane` and `AboutPane`**

Reference screenshots `11`/`12`. Copy the exact body text, links, and any actions (e.g. "clear history", "check for updates" via `AppUpdateChecker`) from the old panels; only restyle into `SettingsPane`/`SettingsGroup`/`SettingsRow`.

- [ ] **Step 2: Delete the old `SettingsView` from `main.swift`**

Remove `private struct SettingsView`, `SettingsPanel`, and any helper rows that were moved into `Settings.swift` (`EditablePlanRow`, `EditableTextPlanRow`, `ProviderMonitorRow`, `AlertProfileRow` if relocated). Confirm the only remaining reference to `SettingsView` is the window-creation call site in `AIFuelGaugeAppDelegate`, which now resolves to the new public `SettingsView` in `Settings.swift` (same module).

- [ ] **Step 3: Build + test**

Run: `swift build && swift test`
Expected: builds; all tests pass.

- [ ] **Step 4: Visual verify all panes**

Run the app; click through all 8 sidebar sections in light and dark; compare to screenshots `05`–`12`, `15`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIFuelGaugeApp
git commit -m "feat: finish settings panes and remove legacy SettingsView"
```

---

## Phase 5 — History window

### Task 19: Restyle the History window

**Files:**
- Modify: `Sources/AIFuelGaugeApp/main.swift` (`HistoryWindowView`, `HistoryLaneCard`, `HistoryMetricPill`)

- [ ] **Step 1: Re-skin to new tokens**

Update `HistoryWindowView`, `HistoryLaneCard`, `HistoryMetricPill` to use `FuelTheme` colors, `fuelCard`, mono numbers, `Sparkline` (from `Popover.swift`) for the trend, and eyebrow labels. Keep the data inputs (`UsageHistoryDashboard`/`UsageHistoryDashboardItem`) and the CSV-export action unchanged. Replace any old `UsageSparkline` usage with the new `Sparkline`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully (old `UsageSparkline` is gone — confirm no remaining references).

- [ ] **Step 3: Visual verify**

Run the app, open History from the action bar, confirm it matches the new design language (consistent with popover cards).

- [ ] **Step 4: Commit**

```bash
git add Sources/AIFuelGaugeApp/main.swift
git commit -m "feat: restyle History window to redesign"
```

---

## Phase 6 — Final verification

### Task 20: Full sweep + cleanup

**Files:**
- Modify: any (cleanup only)

- [ ] **Step 1: Full build + test**

Run: `swift build && swift test`
Expected: build succeeds; all tests pass.

- [ ] **Step 2: Dead-code check**

Search for now-unused symbols and remove them:

Run: `grep -rnE "InsightStrip|MiniMeter|UsageSparkline|FooterButton|UnknownGaugeView|EmptySourcesView|SourceRowView" Sources/`
Expected: no matches (all replaced). Remove any stragglers.

- [ ] **Step 3: Confirm `main.swift` shrank**

Run: `wc -l Sources/AIFuelGaugeApp/*.swift Sources/AIFuelGaugeCore/DesignSystem.swift Sources/AIFuelGaugeCore/HeroFocus.swift`
Expected: `main.swift` substantially smaller; `Popover.swift` + `Settings.swift` carry the moved UI.

- [ ] **Step 4: End-to-end visual pass**

Run the app and verify against every screenshot in both appearances:
- Popover featured (`02`), top-3 (`03`), details+workbench (`04`), dark (`14`).
- Settings: providers (`05`), general (`06`), api keys (`07`), alerts (`08` / dark `15`), menu bar (`09`), budgets (`10`), privacy (`11`), about (`12`).
- Confirm: hero quick-toggle flips Featured↔Top-3; pinning a lane changes the popover hero only (menu-bar label unchanged); refresh/settings/history actions work; saving an API key shows "Connected".

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: redesign cleanup and final verification"
```

---

## Self-Review Notes (for the author, not a task)

- **Spec coverage:** Design system (§2)→Tasks 1–3; popover (§3)→Tasks 6–13; settings (§4)→Tasks 14–18; history (§5)→Task 19; preferences (§6)→Task 5 + panes; testing (§7)→Tasks 1/4 + per-task build/visual; file plan (§8)→file structure + Tasks 12/18/20. Non-goals (§9) respected: system-only theme (no toggle), no snapshot infra, no data-layer changes.
- **Pin independence:** popover `heroPinnedID` is `@State` only (Task 12) and never writes `menuBarProviderFocus` — satisfies the locked decision.
- **Type consistency:** `FuelTheme`, `OKLCH`, `HeroFocus`, `HeroLayout`, `DashboardActions` referenced consistently. Where the plan depends on existing members whose exact names need confirmation (`DashboardActions` fields, `refreshIntervalKey`, keychain method names, the `MenuBarDisplayMode` `trend` case, budget read/save), each such step explicitly instructs the implementer to confirm against `main.swift` rather than assuming — these are integration points with already-working code, not new contracts.
