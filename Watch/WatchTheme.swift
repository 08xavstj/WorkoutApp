import SwiftUI

/// The app's score colours (dark variants from `App/Design/Theme.swift`),
/// defined here because `Theme` needs UIKit, which watchOS doesn't have.
enum WatchTheme {
    static let lifting = color(0xFF6B97)
    static let strain = color(0xFF8E3C)
    static let recovery = color(0x3EDB84)
    static let heart = color(0xFF6E86)
    /// Heart-rate zones 1-5 (the dark variants of `Theme.zoneColors`).
    static let zoneColors = [color(0x7DBBFF), color(0x3ADBA6), color(0xFFD24D), color(0xFF9A4D), color(0xFF5C7A)]

    /// The color of zone 1-5; grey under zone 1 or with no reading.
    static func zoneColor(_ zone: Int?) -> Color {
        guard let zone, zone >= 1, zone <= zoneColors.count else { return .gray }
        return zoneColors[zone - 1]
    }

    nonisolated static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// "12:34" from seconds.
nonisolated func watchClock(_ seconds: TimeInterval) -> String {
    Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
}
