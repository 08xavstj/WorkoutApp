import Foundation
import AppCore

/// Small choices the owner makes for the weekly drink limit and the weight
/// hold, kept in UserDefaults (no SwiftData model). Views that change them
/// use `@AppStorage` with the same keys so they redraw.
nonisolated enum HealthyLivingSettings {
    /// The owner's weekly drink limit (`DrinkLimit`), standard drinks; absent when none is set.
    static let drinkLimitKey = "weeklyDrinkLimit"
    /// The weight being held after a target was reached (`WeightHold.State`, JSON).
    static let weightHoldKey = "weightHoldState"
    /// "Not now" on the hold offer hides it until this date (seconds since 1970).
    static let holdOfferSnoozeKey = "weightHoldOfferSnoozedUntil"

    static var drinkLimit: Double? {
        UserDefaults.standard.object(forKey: drinkLimitKey) as? Double
    }

    static var weightHold: WeightHold.State? {
        get { decodeHold(UserDefaults.standard.data(forKey: weightHoldKey)) }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: weightHoldKey)
            } else {
                UserDefaults.standard.removeObject(forKey: weightHoldKey)
            }
        }
    }

    static func decodeHold(_ data: Data?) -> WeightHold.State? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WeightHold.State.self, from: data)
    }

    static func encodeHold(_ state: WeightHold.State?) -> Data? {
        state.flatMap { try? JSONEncoder().encode($0) }
    }
}
