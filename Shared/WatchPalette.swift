import SwiftUI

/// The Apple Watch's colours, shared by the Watch app and its complications
/// (project.yml: `TensileWatch` and `TensileWatchWidgets` sources). The same
/// hexes as the dark variants of `App/Design/Theme.swift`, which needs UIKit
/// and so can't be compiled here. Everything is `nonisolated`: SwiftUI
/// resolves colours on a background render thread (CLAUDE.md).
///
/// Contrast (WCAG 2.x relative luminance, worked out for this file,
/// docs/research/watch-app-redesign-2026-11.md §4.8.2):
/// - every colour here on black is above 7 : 1, so coloured numbers on the
///   black workout pages pass AA (4.5 : 1) at any size;
/// - white on a filled score tint is only 1.4–3.0 : 1, so labels on filled
///   tints are black (`onTint`, 7.1–14.6 : 1), never white. The HIG asks for
///   4.5 : 1 up to 17 pt and 3 : 1 at 18 pt or bold (HIG Accessibility).
nonisolated enum WatchPalette {
    // MARK: Scores

    static let lifting = color(0xFF6B97)
    static let strain = color(0xFF8E3C)
    static let recovery = color(0x3EDB84)
    static let heart = color(0xFF6E86)

    // MARK: Plan and recovery bands

    /// The bed-by window (`Theme.sleep`, dark).
    static let sleep = color(0x9692FF)
    /// "Easy day" band (`Theme.oxygen`).
    static let easy = color(0x5C9DFF)
    /// "Normal" band (`Theme.recoveryModerate`).
    static let normal = color(0xFFC53D)
    /// "Recovered" band (`Theme.recoveryHigh`).
    static let recovered = color(0x3EDB84)

    /// Unlit ring segments and bar tracks.
    static let track = Color.white.opacity(0.18)

    /// Label colour on a filled score tint (see the contrast note above).
    static let onTint = Color.black

    // MARK: Zones

    /// Heart-rate zones 1-5 (the dark variants of `Theme.zoneColors`).
    static let zoneColors = [color(0x7DBBFF), color(0x3ADBA6), color(0xFFD24D), color(0xFF9A4D), color(0xFF5C7A)]

    /// The colour of zone 1-5; grey under zone 1 or with no reading.
    static func zoneColor(_ zone: Int?) -> Color {
        guard let zone, zone >= 1, zone <= zoneColors.count else { return .gray }
        return zoneColors[zone - 1]
    }

    /// The recovery band's colour ("low", "moderate", "high").
    static func band(_ band: String?) -> Color {
        switch band {
        case "low": easy
        case "moderate": normal
        case "high": recovered
        default: .secondary
        }
    }

    // MARK: Gradient pairs (rings and bars only, as on the phone)

    // Light end first, as `Theme.strainColors` etc. (dark variants).
    static let liftingColors = [color(0xFFB0CF), color(0xFF6B97)]
    static let strainColors = [color(0xFFD066), color(0xFF8E3C)]
    static let recoveryColors = [color(0xD4F06A), color(0x3EDB84)]
    static let heartColors = [color(0xFFB394), color(0xFF6E86)]

    static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
