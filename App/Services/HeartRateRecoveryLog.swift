import Foundation

/// Heart-rate recovery measured after hard efforts, kept so the stat can be
/// compared with your own usual range (`HeartRateRecovery.usualRange`): the
/// per-minute heart rate the app reads covers only two weeks, which holds
/// one or two hard sessions. A small JSON blob in UserDefaults, keyed by the
/// workout's end; not a SwiftData model. Demo mode keeps nothing.
enum HeartRateRecoveryLog {
    private static let key = "heartRateRecoveryLog"
    /// Most recent measurements kept (app's choice: a few months of hard sessions).
    static let kept = 30

    /// Every stored measurement, oldest first, merged with `fresh` (which win
    /// for the same workout end), and saved back.
    static func merge(_ fresh: [(date: Date, drop: Double)]) -> [(date: Date, drop: Double)] {
        var stored: [Double: Double] = DemoMode.isOn ? [:] : load()
        for entry in fresh {
            stored[entry.date.timeIntervalSince1970.rounded()] = entry.drop
        }
        let trimmed = stored.sorted { $0.key < $1.key }.suffix(kept)
        if !DemoMode.isOn, let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return trimmed.map { (date: Date(timeIntervalSince1970: $0.key), drop: $0.value) }
    }

    private static func load() -> [Double: Double] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Double: Double].self, from: data) else { return [:] }
        return decoded
    }
}
