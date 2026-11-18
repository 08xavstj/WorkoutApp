import Foundation

/// The heart-rate zones the phone chose (Settings › Training › Heart-rate
/// zones), kept on the Watch so cardio has them with the phone out of reach.
/// The phone sends a `HeartRateZoneScheme` under `WatchMessage.zones`; the
/// WatchConnectivity delegate (`WatchWorkoutModel`) stores it here.
nonisolated enum WatchZoneStore {
    /// Where the zones in use came from, best first (`WatchCardioModel.resolveZones`).
    nonisolated enum Source: String, Sendable {
        /// Sent by the iPhone app.
        case phone
        /// Apple Health's own zones (watchOS 27), with nothing from the phone yet.
        case health
        /// Tensile's zones from a maximum heart rate estimated from the age in Health.
        case ageEstimate
        /// No age either: a stand-in age, so the numbers are rough.
        case standIn

        /// One line for the zones page and the start sheet.
        var caption: String {
            switch self {
            case .phone: "Zones from your iPhone."
            case .health: "Zones from Apple Health. Open Tensile on your iPhone to use your own."
            case .ageEstimate: "Zones estimated from your age. Open Tensile on your iPhone for better ones."
            case .standIn: "Rough zones: no age in Health yet. Open Tensile on your iPhone to set them."
            }
        }

        /// The same in a few words, for one line under the live zone.
        var shortCaption: String {
            switch self {
            case .phone: "Zones: iPhone"
            case .health: "Zones: Apple Health"
            case .ageEstimate: "Zones: from age"
            case .standIn: "Zones: rough estimate"
            }
        }
    }

    /// The zones in use and where they came from.
    nonisolated struct Choice: Sendable, Equatable {
        var scheme: HeartRateZoneScheme
        var source: Source
    }

    /// The age used when Health has none, the same stand-in as the phone's
    /// settings (`UserSettings.age`): 30. The app's choice; the caption says "rough".
    static let standInAge = 30

    private static let key = "cardioZoneScheme"

    /// Keeps the phone's zones. Called off the main actor, from the WatchConnectivity delegate.
    static func save(_ scheme: HeartRateZoneScheme) {
        guard let data = try? JSONEncoder().encode(scheme) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The phone's zones as last received, or nil before the first. Percent-of-max
    /// zones a phone sent before that option was dropped (17 Nov 2026) are
    /// skipped: the Watch uses Health's or Tensile's from age until the phone
    /// sends its zones again.
    static var fromPhone: HeartRateZoneScheme? {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(HeartRateZoneScheme.self, from: $0) }
            .flatMap { $0.kind == .percentOfMax ? nil : $0 }
    }
}
