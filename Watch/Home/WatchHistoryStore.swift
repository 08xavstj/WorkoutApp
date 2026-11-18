import Foundation
import Observation

/// The last workout recorded on this Watch, for Home's "Last activity" row.
/// Kept on the Watch only (UserDefaults); the full record is in Apple Health
/// and on the iPhone.
nonisolated struct WatchActivityRecord: Codable, Sendable, Equatable {
    nonisolated enum Kind: String, Codable, Sendable {
        case lift, cardio
    }

    var kind: Kind
    /// "Push", "Outdoor run".
    var title: String
    var start: Date
    var end: Date
    /// Without pauses.
    var minutes: Int
    /// "16 sets", "5.02 km · 5:12 /km".
    var detail: String
    var averageBpm: Int?
    var maximumBpm: Int?
    /// `CardioActivity.rawValue` for cardio.
    var activity: String?
    var saved: Bool
}

nonisolated enum WatchHistoryStore {
    private static let key = "watchLastActivity"

    static var last: WatchActivityRecord? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchActivityRecord.self, from: $0) }
    }

    static func save(_ record: WatchActivityRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// The Watch's own settings (Home › Settings).
nonisolated enum WatchPreferences {
    /// A light tap 10 s before a rest ends (`RestCues.warningSeconds`). On by default.
    static let restWarningKey = "watchRestWarning"
    /// A tap at each split and lap. On by default; the banner shows either way.
    static let splitTapsKey = "watchSplitTaps"
    /// "auto" (the region's), "km" or "mi".
    static let distanceUnitKey = "watchDistanceUnit"

    static var restWarning: Bool { UserDefaults.standard.object(forKey: restWarningKey) as? Bool ?? true }
    static var splitTaps: Bool { UserDefaults.standard.object(forKey: splitTapsKey) as? Bool ?? true }
    static var distanceUnit: String { UserDefaults.standard.string(forKey: distanceUnitKey) ?? "auto" }
}

/// True where distances are in miles: the choice in Settings, else the
/// region's (the US and the UK).
nonisolated func watchUsesMiles() -> Bool {
    switch WatchPreferences.distanceUnit {
    case "km": return false
    case "mi": return true
    default:
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }
}

/// The phone's face data, observed by Home so its glance and plan card
/// change as soon as new data arrives (`WatchComplications.store` reloads it).
@Observable
final class FaceFeed {
    static let shared = FaceFeed()

    private(set) var data: WatchFaceData? = WatchFaceStore.load()
    /// The latest workout end, from the phone's log or this Watch.
    private(set) var lastWorkoutEnd: Date? = WatchFaceStore.lastWorkoutEnd(WatchFaceStore.load())

    func reload() {
        data = WatchFaceStore.load()
        lastWorkoutEnd = WatchFaceStore.lastWorkoutEnd(data)
    }
}
