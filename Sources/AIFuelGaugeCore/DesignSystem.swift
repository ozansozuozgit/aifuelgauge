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
