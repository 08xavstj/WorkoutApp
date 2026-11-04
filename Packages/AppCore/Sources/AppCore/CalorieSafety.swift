import Foundation

/// Guards on calorie targets, so a cut never asks for less than the body
/// needs to train and recover.
///
/// - **A maintenance estimate has to be physically possible.** Free-living
///   adults almost never spend less than 1.4 times their resting metabolism a
///   day; 1.40 is the bottom of the "sedentary" band (FAO/WHO/UNU, Human
///   Energy Requirements, 2004). A food-log maintenance below that almost
///   always means days weren't fully logged: under-recording is the main
///   error in food records (Burrows et al., Nutrients 2019). Such an estimate
///   isn't used.
/// - **The target's floor is personal.** Below about 30 kcal per kg of
///   fat-free mass, after subtracting exercise, is low energy availability,
///   which disturbs hormones, bone and muscle in men and women (IOC consensus
///   on REDs, Mountjoy et al., Br J Sports Med 2023; Loucks et al., J Sports
///   Sci 2011). The floor is the higher of that and the absolute minimum
///   (1,500 kcal men / 1,200 kcal women).
/// - **Same 30 for men and women.** The 30 kcal/kg line comes mostly from
///   studies in women. In exercising men, 4 days at 15 kcal/kg lowered leptin
///   and insulin but not the other metabolic hormones measured (Koehler et
///   al., J Sports Sci 2016), and no separate male threshold has been established
///   (Wasserfurth et al., Sports Med Open 2020). With no agreed lower number,
///   the app keeps the conservative 30 for everyone (docs/research/calories.md).
public enum CalorieSafety {
    /// Lowest believable maintenance, as a multiple of resting metabolism (FAO/WHO/UNU 2004).
    public static let minimumPhysicalActivityLevel = 1.4
    /// Energy availability below this, kcal per kg fat-free mass, is low (IOC REDs 2023).
    public static let minimumEnergyAvailability = 30.0

    /// Fat-free mass, kg: from body fat when known, otherwise the Boer
    /// lean-body-mass equation from height and weight (Boer, Am J Physiol 1984).
    public static func fatFreeMassKg(weightKg: Double, heightCm: Double?, sex: BiologicalSex, bodyFatPercent: Double?) -> Double {
        if let fat = bodyFatPercent, fat > 3, fat < 60 {
            return weightKg * (1 - fat / 100)
        }
        let height = heightCm ?? (sex == .male ? 176 : 163)
        let boer = sex == .male
            ? 0.407 * weightKg + 0.267 * height - 19.2
            : 0.252 * weightKg + 0.473 * height - 48.3
        // Keep the estimate within sensible bounds of body weight.
        return min(weightKg * 0.95, max(weightKg * 0.55, boer))
    }

    /// Whether a measured maintenance is believable for someone with this
    /// resting metabolism (at least 1.4× BMR).
    public static func isPlausibleMaintenance(_ maintenance: Double, bmr: Double) -> Bool {
        guard bmr > 0 else { return true }
        return maintenance >= bmr * minimumPhysicalActivityLevel
    }

    /// The lowest daily target: enough left after exercise for 30 kcal per kg
    /// of fat-free mass, and never under the absolute minimum.
    /// - Parameter exerciseKcalPerDay: average exercise calories a day (recent workouts).
    public static func minimumTarget(
        sex: BiologicalSex, weightKg: Double, heightCm: Double?, bodyFatPercent: Double?, exerciseKcalPerDay: Double
    ) -> Double {
        let fatFree = fatFreeMassKg(weightKg: weightKg, heightCm: heightCm, sex: sex, bodyFatPercent: bodyFatPercent)
        let availability = minimumEnergyAvailability * fatFree + max(0, exerciseKcalPerDay)
        return max(GoalPlanner.calorieFloor(sex: sex), availability.rounded())
    }
}
