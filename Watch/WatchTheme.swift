import SwiftUI

/// Forwards to the shared `WatchPalette` (Shared/WatchPalette.swift), which the
/// complications use too. Kept so older views compile; removed once nothing
/// reads it (C9 of the Watch redesign).
nonisolated enum WatchTheme {
    static let lifting = WatchPalette.lifting
    static let strain = WatchPalette.strain
    static let recovery = WatchPalette.recovery
    static let heart = WatchPalette.heart
    static let zoneColors = WatchPalette.zoneColors

    static func zoneColor(_ zone: Int?) -> Color {
        WatchPalette.zoneColor(zone)
    }
}

/// "12:34" from seconds.
nonisolated func watchClock(_ seconds: TimeInterval) -> String {
    Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
}
