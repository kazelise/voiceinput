import AppKit
import SwiftUI

/// ChatWise / System-Settings palette, pixel-sampled from official material
/// (see `docs/research/chatwise-ui-openrouter.md`). Every color adapts to
/// light/dark automatically because it is backed by an
/// `NSColor(name:dynamicProvider:)` that resolves against the effective
/// appearance at draw time. Settings UI uses THESE tokens — never raw system
/// grays — so the window reads as a single calm, deliberate surface.
enum Theme {
    // MARK: Accent

    /// Blue-600 family. #4E80EE light / #2464EB dark.
    static let accent = dynamic("VIAccent",
                                light: hex(0x4E80EE),
                                dark: hex(0x2464EB))

    // MARK: Surfaces

    /// Card / form content background. #FFFFFF / #222125.
    static let contentBackground = dynamic("VIContentBackground",
                                           light: hex(0xFFFFFF),
                                           dark: hex(0x222125))

    /// Warm-stone sidebar / source-list background. #F2EDEC / #28272B.
    static let sidebarBackground = dynamic("VISidebarBackground",
                                           light: hex(0xF2EDEC),
                                           dark: hex(0x28272B))

    /// Window chrome behind cards. #EFEFF4 / #222125.
    static let chrome = dynamic("VIChrome",
                                light: hex(0xEFEFF4),
                                dark: hex(0x222125))

    /// Selected tab pill / segmented track. zinc-200 / zinc-700.
    static let pill = dynamic("VIPill",
                              light: hex(0xE4E4E7),
                              dark: hex(0x3F3F46))

    /// Filled input field fill. #F4F4F5 / #343337.
    static let fieldFill = dynamic("VIFieldFill",
                                   light: hex(0xF4F4F5),
                                   dark: hex(0x343337))

    /// Hairline rule / field border. #E4E4E7 / #3F3F46.
    static let hairline = dynamic("VIHairline",
                                  light: hex(0xE4E4E7),
                                  dark: hex(0x3F3F46))

    // MARK: Text

    /// Primary text. #0A0A0B / #F9F9F9.
    static let textPrimary = dynamic("VITextPrimary",
                                     light: hex(0x0A0A0B),
                                     dark: hex(0xF9F9F9))

    /// Secondary / helper text. #707074 / #96969C.
    static let textSecondary = dynamic("VITextSecondary",
                                       light: hex(0x707074),
                                       dark: hex(0x96969C))

    // MARK: - Construction helpers

    /// Wrap a dynamic `NSColor` so appearance switching is automatic.
    private static func dynamic(_ name: String,
                                light: NSColor,
                                dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    /// Opaque sRGB color from a 0xRRGGBB literal.
    private static func hex(_ rgb: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgb & 0xFF) / 255.0,
                alpha: 1.0)
    }
}
