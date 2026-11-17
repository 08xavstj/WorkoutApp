import Foundation

/// A quarterly fitness check: a standard walking test that estimates VO₂ max
/// more dependably than an Apple Watch that only reads it on outdoor walks
/// and runs (docs/research/evidence-audit-2026-11.md, Gaps, item 5).
///
/// Why: Apple Watch Series 7 against a lab test had a mean absolute error of
/// 15.8%, ICC 0.47, and read fit people low (Caserman et al., JMIR Biomed
/// Eng 2024;9:e59459, PMID 39083800, abstract read). A lifter who rarely
/// walks or runs outdoors gets few readings at all.
///
/// Two validated submaximal tests, both read at PubMed (abstracts):
/// - **One-mile walk** (Rockport; Kline et al., Med Sci Sports Exerc
///   1987;19:253, PMID 3600239): walk one mile as fast as you can on a flat
///   track; VO₂ max (L/min) = 6.9652 + 0.0091·weight(lb) − 0.0257·age +
///   0.5955·sex(1 = male) − 0.2240·time(min) − 0.0115·HR at the end of the
///   last quarter-mile; r = 0.93, SEE 0.325 L/min; 343 adults aged 30-69.
///   Divided by body weight for mL/kg/min.
/// - **Treadmill walk, one stage** (Ebbeling et al., Med Sci Sports Exerc
///   1991;23:966, PMID 1956273): 4 minutes at a steady brisk speed (2.0-4.5
///   mph) on the flat, then 4 minutes at the same speed at 5% incline;
///   VO₂ max = 15.1 + 21.8·speed(mph) − 0.327·HR − 0.263·speed·age +
///   0.00504·HR·age + 5.98·sex(1 = male); R² 0.86, SEE 4.85 mL/kg/min; 139
///   adults aged 20-59. The heart rate is the steady rate at the end of the
///   5% stage. (The paper's warm-up target of 50-70% of predicted maximum
///   heart rate comes from secondary descriptions, not re-verified; the app
///   says "a brisk pace you could keep up for a while".)
///
/// Both are estimates with an error of about ±5 mL/kg/min, close to the
/// watch's; their value is that the same test, done the same way each
/// quarter, makes the trend believable. Every 3 months is the app's choice:
/// training changes VO₂ max over weeks to months.
public enum FitnessCheck {
    public enum Test: String, Codable, Sendable, CaseIterable, Identifiable {
        case mileWalk, treadmillWalk
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .mileWalk: "One-mile walk, outdoors"
            case .treadmillWalk: "Treadmill walk, 8 minutes"
            }
        }

        public var citation: String {
            switch self {
            case .mileWalk: "Kline et al., Med Sci Sports Exerc 1987 (Rockport walk test)"
            case .treadmillWalk: "Ebbeling et al., Med Sci Sports Exerc 1991"
            }
        }

        /// Ages the equation was built on.
        public var validAges: ClosedRange<Int> {
            switch self {
            case .mileWalk: 30...69
            case .treadmillWalk: 20...59
            }
        }

        /// The protocol, step by step, in plain words.
        public var steps: [String] {
            switch self {
            case .mileWalk: [
                "Pick a flat route of exactly one mile (1.6 km): four laps of a 400 m running track is easiest.",
                "Warm up with 5 minutes of easy walking. Wear your Apple Watch.",
                "Walk the mile as fast as you can without jogging. Keep one foot on the ground.",
                "At the finish, note your time and your heart rate straight away (the watch's live reading).",
                "Enter the time and heart rate here. Do it the same way each time: same route, rested, not after a hard leg day.",
            ]
            case .treadmillWalk: [
                "Choose a brisk walking speed between 3.2 and 7.2 km/h (2-4.5 mph) that you could keep up for a while. Wear your Apple Watch.",
                "Walk 4 minutes at that speed on the flat (0% incline).",
                "Without changing the speed, raise the incline to 5% and walk 4 more minutes.",
                "At the end, note your heart rate (the watch's live reading).",
                "Enter the speed and heart rate here. Use the same speed each time, rested, not after a hard leg day.",
            ]
            }
        }
    }

    /// Repeat every 3 months (app's choice).
    public static let intervalDays = 91

    public struct Result: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var test: Test
        public var date: Date
        /// mL/kg/min.
        public var vo2Max: Double

        public init(id: UUID = UUID(), test: Test, date: Date, vo2Max: Double) {
            self.id = id
            self.test = test
            self.date = date
            self.vo2Max = vo2Max
        }
    }

    /// Typical error either side, mL/kg/min (Ebbeling SEE 4.85; Kline's SEE
    /// of 0.325 L/min is about 4-5 mL/kg/min at 70-80 kg).
    public static let typicalError = 5.0

    static let poundsPerKilogram = 2.204_62

    /// Kline 1987: the one-mile walk. Nil for impossible inputs.
    public static func mileWalk(minutes: Double, heartRate: Double, age: Int, sex: BiologicalSex, weightKg: Double) -> Double? {
        guard minutes > 5, minutes < 40, heartRate > 40, heartRate < 230, weightKg > 30, age > 0 else { return nil }
        let pounds = weightKg * poundsPerKilogram
        let male = sex == .male ? 1.0 : 0.0
        let litres = 6.9652 + 0.0091 * pounds - 0.0257 * Double(age) + 0.5955 * male - 0.2240 * minutes - 0.0115 * heartRate
        guard litres > 0 else { return nil }
        return litres * 1000 / weightKg
    }

    /// Ebbeling 1991: the single-stage treadmill walk. Nil for inputs outside
    /// the tested speeds or impossible heart rates.
    public static func treadmillWalk(speedMph: Double, heartRate: Double, age: Int, sex: BiologicalSex) -> Double? {
        guard (2.0...4.5).contains(speedMph), heartRate > 40, heartRate < 230, age > 0 else { return nil }
        let male = sex == .male ? 1.0 : 0.0
        let a = Double(age)
        let value = 15.1 + 21.8 * speedMph - 0.327 * heartRate - 0.263 * speedMph * a + 0.00504 * heartRate * a + 5.98 * male
        return value > 10 ? value : nil
    }

    public static let kmhPerMph = 1.609_344

    /// The tests to suggest: those whose equation covers the age (the treadmill
    /// only when the gym has one, `GymProfile.cardioMachines`); every available
    /// one when none does (the page then says the age is outside the study's).
    public static func suggested(age: Int, hasTreadmill: Bool) -> [Test] {
        let available = Test.allCases.filter { $0 != .treadmillWalk || hasTreadmill }
        let fitting = available.filter { $0.validAges.contains(age) }
        return fitting.isEmpty ? available : fitting
    }

    /// Due when no check in the last `intervalDays` days.
    public static func isDue(_ results: [Result], now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let next = nextDue(results, calendar: calendar) else { return true }
        return calendar.startOfDay(for: now) >= next
    }

    public static func nextDue(_ results: [Result], calendar: Calendar = .current) -> Date? {
        guard let last = results.map(\.date).max() else { return nil }
        return calendar.date(byAdding: .day, value: intervalDays, to: calendar.startOfDay(for: last))
    }

    /// The change between the last two checks of the same test, mL/kg/min;
    /// nil without two. `typicalError` is one test against the lab; the same
    /// person repeating the same test varies less, but no figure for that was
    /// checked, so the app shows the change without calling it real.
    public static func change(_ results: [Result]) -> Double? {
        let sorted = results.sorted { $0.date < $1.date }
        guard let last = sorted.last,
              let previous = sorted.dropLast().last(where: { $0.test == last.test }) else { return nil }
        return last.vo2Max - previous.vo2Max
    }
}
