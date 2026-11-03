import Foundation

/// Waist circumference and the waist-to-height ratio (WHtR), typed in by hand
/// about once a month.
///
/// Keep your waist under half your height: WHtR under 0.5. Across 31 studies
/// (over 300,000 adults) WHtR picked out diabetes, high blood pressure and
/// heart-disease risk better than BMI and slightly better than waist alone
/// (Ashwell, Gunn & Gibson, Obes Rev 2012); 0.5 was proposed as the global
/// boundary by Browning, Hsieh & Ashwell (Nutr Res Rev 2010). It ignores
/// muscle mass, so it suits lifters where BMI doesn't. The bands below are
/// the ones Ashwell's group use for adults: under 0.4 "take care" (low),
/// 0.4-0.5 healthy, 0.5-0.6 raised ("consider action"), over 0.6 high
/// ("take action"). A tape measure, not a diagnosis.
public enum WaistToHeightRatio {
    /// The boundary: waist less than half your height (Browning 2010; Ashwell 2012).
    public static let target = 0.5

    public enum Category: String, Sendable, Equatable, CaseIterable {
        case low = "Low"
        case healthy = "Healthy"
        case raised = "Raised"
        case high = "High"
    }

    /// Waist divided by height, both in the same unit; nil for bad input.
    public static func ratio(waistCm: Double, heightCm: Double) -> Double? {
        guard waistCm > 20, heightCm > 100 else { return nil }
        return waistCm / heightCm
    }

    /// Ashwell's adult bands (Ashwell 2012; Browning 2010 for the 0.5 line).
    public static func category(_ ratio: Double) -> Category {
        if ratio < 0.4 { return .low }
        if ratio < target { return .healthy }
        if ratio < 0.6 { return .raised }
        return .high
    }

    /// Waist in cm at the 0.5 line for this height (the number to stay under).
    public static func waistAtTarget(heightCm: Double) -> Double {
        heightCm * target
    }

    /// Plain reading of the category, tailored to the goal: for a gain goal the
    /// 0.5-0.52 line is the guard rail for a bulk; when losing, WHtR is the
    /// progress number once the scale stalls (docs/research/health-metrics.md, section 4).
    public static func advice(_ category: Category, goals: Goals?) -> String {
        switch category {
        case .low:
            return "Under 0.4. Fine for most lifters, but if you're losing weight, this is low enough; there's no health gain from going lower."
        case .healthy:
            switch goals?.weight {
            case .gain:
                return "Under 0.5: waist less than half your height. On a bulk, this is the number to watch; most people do best to stop gaining and recomp when it crosses about 0.5."
            case .lose:
                return "Under 0.5: waist less than half your height. When the scale stalls, a falling waist still shows fat loss."
            default:
                return "Under 0.5: waist less than half your height, the range linked with the lowest heart and metabolic risk."
            }
        case .raised:
            switch goals?.weight {
            case .gain:
                return "0.5 or more. This is where a bulk starts adding risk, not muscle: worth pausing the surplus and recomping until it's under 0.5."
            default:
                return "0.5 or more. Getting your waist under half your height lowers heart and diabetes risk more than any scale number; a modest deficit with lifting does it."
            }
        case .high:
            return "Over 0.6, the band with the highest heart and metabolic risk. Worth a conversation with your doctor alongside a steady fat-loss plan."
        }
    }

    // MARK: Cadence

    /// Measure about monthly: a tape reading moves by a centimetre with the
    /// time of day and how you breathe, so weekly changes are noise, and a
    /// bulk or a cut shows in a month (app choice from the research round).
    public static let intervalDays = 30

    /// When the next measurement is due (a month after the last one). Nil without one.
    public static func nextDue(lastMeasured: Date?, calendar: Calendar = .current) -> Date? {
        guard let lastMeasured else { return nil }
        return calendar.date(byAdding: .day, value: intervalDays, to: calendar.startOfDay(for: lastMeasured))
    }

    /// True when there's no measurement or the last one is a month or more old.
    public static func isDue(lastMeasured: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due = nextDue(lastMeasured: lastMeasured, calendar: calendar) else { return true }
        return calendar.startOfDay(for: now) >= due
    }

    /// Days the body-age estimate treats a waist reading as current (body age
    /// uses WHtR instead of BMI only while a reading this fresh exists).
    public static let freshDays = 90

    public static func isFresh(_ measured: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: measured), to: calendar.startOfDay(for: now)).day ?? 0
        return days <= freshDays
    }
}

/// Centimetres or inches for typing a waist measurement. Stored in cm; the
/// default follows the phone's measurement system (the app passes it in).
public enum LengthUnit: String, Sendable, CaseIterable, Identifiable {
    case centimeters = "cm"
    case inches = "in"

    public var id: String { rawValue }

    public static let centimetersPerInch = 2.54

    public func display(_ centimeters: Double) -> Double {
        self == .centimeters ? centimeters : centimeters / Self.centimetersPerInch
    }

    public func toCentimeters(_ value: Double) -> Double {
        self == .centimeters ? value : value * Self.centimetersPerInch
    }

    /// "84 cm" or "33.1 in".
    public func format(_ centimeters: Double) -> String {
        let value = display(centimeters)
        let digits = self == .centimeters ? 0 : 1
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(rawValue)"
    }
}
