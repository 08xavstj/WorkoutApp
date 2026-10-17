import Foundation
import SwiftUI
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

enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match iPhone"
        }
    }

    /// nil lets the app follow the iPhone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
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
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var supabaseURL: String { didSet { defaults.set(supabaseURL, forKey: "supabaseURL") } }
    var supabaseAnonKey: String { didSet { defaults.set(supabaseAnonKey, forKey: "supabaseAnonKey") } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    /// Used when Apple Health has no height. 0 = not set.
    var heightCm: Double { didSet { defaults.set(heightCm, forKey: "heightCm") } }
    /// Used when Apple Health has no weight. 0 = not set.
    var weightKg: Double { didSet { defaults.set(weightKg, forKey: "weightKg") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        age = defaults.object(forKey: "age") as? Int ?? 30
        sex = BiologicalSex(rawValue: defaults.string(forKey: "sex") ?? "") ?? .male
        maxHeartRate = defaults.integer(forKey: "maxHeartRate")
        weightUnit = WeightUnit(rawValue: defaults.string(forKey: "weightUnit") ?? "") ?? .pounds
        coachMode = CoachMode(rawValue: defaults.string(forKey: "coachMode") ?? "") ?? .onDevice
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .light
        supabaseURL = defaults.string(forKey: "supabaseURL") ?? ""
        supabaseAnonKey = defaults.string(forKey: "supabaseAnonKey") ?? ""
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        heightCm = defaults.double(forKey: "heightCm")
        weightKg = defaults.double(forKey: "weightKg")
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
