import AppKit
import SwiftUI

/// Converts OKLCH color coordinates to gamma-encoded sRGB in [0,1].
/// Preserves the exact oklch values from handoff/source/assets/app.css.
public enum OKLCH {
    public static func srgb(l: Double, c: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180.0
        let a = c * cos(hr)
        let labB = c * sin(hr)

        let l_ = l + 0.3963377774 * a + 0.2158037573 * labB
        let m_ = l - 0.1055613458 * a - 0.0638541728 * labB
        let s_ = l - 0.0894841775 * a - 1.2914855480 * labB

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
    public static let fieldBorder  = borderStrong
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

public struct FuelShadow: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color; self.radius = radius; self.x = x; self.y = y
    }
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
