import Foundation
import HealthKit
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
    /// Copy age, sex, height and weight from Apple Health whenever the app syncs.
    var profileFromHealth: Bool { didSet { defaults.set(profileFromHealth, forKey: "profileFromHealth") } }
    /// Which profile fields Apple Health filled in last time (shown in Settings).
    var healthFilledFields: Set<String> { didSet { defaults.set(Array(healthFilledFields), forKey: "healthFilledFields") } }
    /// Daily "log your HRV" reminder.
    var hrvReminderOn: Bool { didSet { defaults.set(hrvReminderOn, forKey: "hrvReminderOn") } }
    /// Minutes after midnight for the reminder (default 7:30).
    var hrvReminderMinutes: Int { didSet { defaults.set(hrvReminderMinutes, forKey: "hrvReminderMinutes") } }
    var name: String { didSet { defaults.set(name, forKey: "name") } }
    var placeName: String { didSet { defaults.set(placeName, forKey: "placeName") } }
    var latitude: Double { didSet { defaults.set(latitude, forKey: "latitude") } }
    var longitude: Double { didSet { defaults.set(longitude, forKey: "longitude") } }
    var hasLocation: Bool { !placeName.isEmpty && !(latitude == 0 && longitude == 0) }
    var checkInRemindersOn: Bool { didSet { defaults.set(checkInRemindersOn, forKey: "checkInRemindersOn") } }
    var morningCheckInMinutes: Int { didSet { defaults.set(morningCheckInMinutes, forKey: "morningCheckInMinutes") } }
    var eveningCheckInMinutes: Int { didSet { defaults.set(eveningCheckInMinutes, forKey: "eveningCheckInMinutes") } }

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
        profileFromHealth = defaults.object(forKey: "profileFromHealth") as? Bool ?? true
        healthFilledFields = Set(defaults.stringArray(forKey: "healthFilledFields") ?? [])
        hrvReminderOn = defaults.bool(forKey: "hrvReminderOn")
        hrvReminderMinutes = defaults.object(forKey: "hrvReminderMinutes") as? Int ?? 7 * 60 + 30
        name = defaults.string(forKey: "name") ?? ""
        placeName = defaults.string(forKey: "placeName") ?? ""
        latitude = defaults.double(forKey: "latitude")
        longitude = defaults.double(forKey: "longitude")
        checkInRemindersOn = defaults.bool(forKey: "checkInRemindersOn")
        morningCheckInMinutes = defaults.object(forKey: "morningCheckInMinutes") as? Int ?? 8 * 60
        eveningCheckInMinutes = defaults.object(forKey: "eveningCheckInMinutes") as? Int ?? 21 * 60 + 30
    }

    /// Fills the profile from Apple Health (only fields Health actually has).
    func syncProfile(from health: HealthKitClient) async {
        guard profileFromHealth else { return }
        let characteristics = health.profileCharacteristics()
        let height = try? await health.latest(.height, unit: .meterUnit(with: .centi))
        let weight = try? await health.latestBodyMassKg()
        var filled: Set<String> = []
        if let value = characteristics.age, (13...100).contains(value) {
            if age != value { age = value }
            filled.insert("age")
        }
        if let value = characteristics.sex {
            if sex != value { sex = value }
            filled.insert("sex")
        }
        if let value = height ?? nil, value > 100 {
            let rounded = (value * 10).rounded() / 10
            if heightCm != rounded { heightCm = rounded }
            filled.insert("height")
        }
        if let value = weight ?? nil, value > 30 {
            let rounded = (value * 10).rounded() / 10
            if weightKg != rounded { weightKg = rounded }
            filled.insert("weight")
        }
        if healthFilledFields != filled { healthFilledFields = filled }
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
