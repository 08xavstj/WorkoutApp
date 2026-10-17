import Foundation
import AppCore

enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    var id: String { rawValue }

    static let poundsPerKilogram = 2.20462

    func display(_ kilograms: Double) -> Double {
        self == .kilograms ? kilograms : kilograms * Self.poundsPerKilogram
    }

    func toKilograms(_ value: Double) -> Double {
        self == .kilograms ? value : value / Self.poundsPerKilogram
    }

    func format(_ kilograms: Double) -> String {
        display(kilograms).formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum CoachMode: String, CaseIterable, Identifiable {
    /// Apple's on-device model: free and private, needs Apple Intelligence.
    case onDevice
    /// Claude through your Supabase Edge Function.
    case cloud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDevice: "On-device (Apple Intelligence)"
        case .cloud: "Claude (cloud)"
        }
    }
}

/// Settings saved in UserDefaults. Read and write through this object so views update.
@Observable
final class UserSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var age: Int { didSet { defaults.set(age, forKey: "age") } }
    var sex: BiologicalSex { didSet { defaults.set(sex.rawValue, forKey: "sex") } }
    /// 0 means "estimate from age".
    var maxHeartRate: Int { didSet { defaults.set(maxHeartRate, forKey: "maxHeartRate") } }
    var weightUnit: WeightUnit { didSet { defaults.set(weightUnit.rawValue, forKey: "weightUnit") } }
    var coachMode: CoachMode { didSet { defaults.set(coachMode.rawValue, forKey: "coachMode") } }
    var supabaseURL: String { didSet { defaults.set(supabaseURL, forKey: "supabaseURL") } }
    var supabaseAnonKey: String { didSet { defaults.set(supabaseAnonKey, forKey: "supabaseAnonKey") } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        age = defaults.object(forKey: "age") as? Int ?? 30
        sex = BiologicalSex(rawValue: defaults.string(forKey: "sex") ?? "") ?? .male
        maxHeartRate = defaults.integer(forKey: "maxHeartRate")
        weightUnit = WeightUnit(rawValue: defaults.string(forKey: "weightUnit") ?? "") ?? .pounds
        coachMode = CoachMode(rawValue: defaults.string(forKey: "coachMode") ?? "") ?? .onDevice
        supabaseURL = defaults.string(forKey: "supabaseURL") ?? ""
        supabaseAnonKey = defaults.string(forKey: "supabaseAnonKey") ?? ""
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
    }

    func heartRateProfile(restingHeartRate: Double?) -> HeartRateProfile {
        HeartRateProfile(
            age: age,
            sex: sex,
            restingHeartRate: restingHeartRate ?? 60,
            maxHeartRateOverride: maxHeartRate > 0 ? Double(maxHeartRate) : nil
        )
    }
}
