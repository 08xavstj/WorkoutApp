import Foundation

/// Energy availability: what's left for the body after training, per kg of
/// fat-free mass: (intake − exercise energy) / fat-free mass, in kcal/kg/day.
///
/// The 2023 IOC consensus on Relative Energy Deficiency in Sport (Mountjoy
/// et al., Br J Sports Med 2023) puts the zone with health effects (hormones,
/// bone, immunity, low HRV, poor sleep, injury) at 30 kcal/kg FFM/day or
/// less, with about 45 as the level that maintains everything; the earlier
/// dose-response work is Loucks et al. (J Sports Sci 2011). The cut-off is a
/// simplification, not a diagnosis: exercise calories and body fat are both
/// estimates, so this is a guard rail for a cut, not a verdict.
public enum EnergyAvailability {
    /// Below this, sustained, is low energy availability (IOC 2023; Loucks 2011).
    public static let lowThreshold = 30.0
    /// About the level that keeps hormones, bone and recovery normal (IOC 2023).
    public static let adequate = 45.0
    /// Logged days needed in the last 7 before the flag can show (app choice:
    /// a couple of unlogged days shouldn't make a week look starved).
    public static let minimumLoggedDays = 5

    public struct Day: Sendable, Equatable {
        public var date: Date
        public var intakeKcal: Double?
        public var exerciseKcal: Double

        public init(date: Date, intakeKcal: Double?, exerciseKcal: Double) {
            self.date = date
            self.intakeKcal = intakeKcal
            self.exerciseKcal = exerciseKcal
        }
    }

    public struct Result: Sendable, Equatable {
        /// Average kcal per kg fat-free mass per day over the logged days.
        public var kcalPerKgFFM: Double
        public var loggedDays: Int
        public var fatFreeMassKg: Double
        public var isLow: Bool { kcalPerKgFFM < EnergyAvailability.lowThreshold }

        /// "28 kcal/kg fat-free mass".
        public var valueText: String {
            "\(Int(kcalPerKgFFM.rounded())) kcal per kg fat-free mass"
        }
    }

    /// Fat-free mass from body fat %, or nil when body fat isn't known
    /// (without it the flag is skipped rather than guessed).
    public static func fatFreeMass(bodyMassKg: Double?, bodyFatPercent: Double?) -> Double? {
        guard let bodyMassKg, bodyMassKg > 0, let fat = bodyFatPercent, fat > 3, fat < 60 else { return nil }
        return bodyMassKg * (1 - fat / 100)
    }

    /// One day's energy availability, kcal per kg fat-free mass; nil for bad input.
    public static func compute(intakeKcal: Double, exerciseKcal: Double, fatFreeMassKg: Double) -> Double? {
        guard fatFreeMassKg > 0, intakeKcal >= 0, exerciseKcal >= 0 else { return nil }
        return (intakeKcal - exerciseKcal) / fatFreeMassKg
    }

    /// The last 7 days' average over the logged ones (a day with no intake
    /// logged, or zero, is skipped). Nil without body fat or enough logged days.
    public static func assess(days: [Day], fatFreeMassKg: Double?) -> Result? {
        guard let fatFreeMassKg, fatFreeMassKg > 0 else { return nil }
        let recent = days.sorted { $0.date < $1.date }.suffix(7)
        let values = recent.compactMap { day -> Double? in
            guard let intake = day.intakeKcal, intake > 0 else { return nil }
            return compute(intakeKcal: intake, exerciseKcal: max(0, day.exerciseKcal), fatFreeMassKg: fatFreeMassKg)
        }
        guard values.count >= minimumLoggedDays else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return Result(kcalPerKgFFM: average, loggedDays: values.count, fatFreeMassKg: fatFreeMassKg)
    }

    /// The flag's wording, by goal: ease the deficit rather than push through.
    /// Endurance athletes are the group most at risk (IOC 2023).
    public static func message(_ result: Result, goals: Goals?) -> String? {
        guard result.isLow else { return nil }
        let value = "About \(result.valueText) a day over the last \(result.loggedDays) logged days, under the 30 the IOC consensus links with hormone, bone and recovery problems."
        switch goals?.weight {
        case .lose:
            return value + " Ease the deficit: eat a bit more on training days, or slow the rate. Pushing through here costs muscle, sleep and HRV, not just fat."
        default:
            if goals?.focuses.contains(.endurance) == true {
                return value + " Big training weeks need more food, not less; add carbs around sessions and ease the deficit if weight is dropping."
            }
            return value + " Intake looks low for how much you train; ease the deficit or log the meals you skipped so the picture is right."
        }
    }
}
