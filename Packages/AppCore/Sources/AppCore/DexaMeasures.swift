import Foundation

/// Two numbers from a DEXA scan report, typed in after a scan and shown
/// beside waist-to-height (docs/research/next-features-2026-11.md, I9, §4d):
/// visceral fat (VAT) and the appendicular lean mass index (ALMI).
///
/// Evidence and its limits:
/// - VAT: per standard deviation, OR 1.45 for prevalent heart and artery
///   disease; top vs bottom quarter HR 6.28 for cardiovascular death in adults
///   20-59 (NHANES 2011-2018; only 44 CV deaths; Cesaro et al., Nutr Metab
///   Cardiovasc Dis 2026). One cohort, cross-sectional for the disease link,
///   and no agreed cut-off: scanners report VAT as mass (g) or area (cm²)
///   with different software. So VAT is shown with its change between scans,
///   never graded.
/// - ALMI: arm and leg lean mass divided by height squared. A muscle-mass
///   index predicted survival in older adults (Srikanthan & Karlamangla, Am
///   J Med 2014; record only). EWGSOP2's low-muscle line by DXA is under
///   7.0 kg/m² for men and 5.5 kg/m² for women (Cruz-Jentoft et al., Age
///   Ageing 2019; from memory), a sarcopenia criterion for older adults;
///   above it says nothing finer, so the reading is only "above" or "below".
/// - Scans are optional and at most yearly (the research file); never from a
///   bathroom scale, whose lean-mass numbers aren't DEXA.
public enum DexaMeasures {
    public enum VATUnit: String, Codable, Sendable, CaseIterable, Identifiable {
        case grams = "g"
        case squareCentimeters = "cm²"
        public var id: String { rawValue }
    }

    /// EWGSOP2 low appendicular lean mass index by DXA, kg/m².
    public static func lowALMI(sex: BiologicalSex) -> Double {
        sex == .male ? 7.0 : 5.5
    }

    /// Appendicular lean mass (kg) / height (m)²; nil for implausible input.
    public static func almi(appendicularLeanKg: Double, heightCm: Double) -> Double? {
        guard appendicularLeanKg > 5, appendicularLeanKg < 80, heightCm > 100, heightCm <= 250 else { return nil }
        let meters = heightCm / 100
        return appendicularLeanKg / (meters * meters)
    }

    public enum ALMIReading: String, Sendable, Equatable {
        case below = "Below the low-muscle line"
        case above = "Above the low-muscle line"
    }

    public static func reading(almi: Double, sex: BiologicalSex) -> ALMIReading {
        almi < lowALMI(sex: sex) ? .below : .above
    }

    /// Plain words for the ALMI, with the line for this sex.
    public static func almiText(_ almi: Double, sex: BiologicalSex) -> String {
        let line = lowALMI(sex: sex).formatted(.number.precision(.fractionLength(1)))
        switch reading(almi: almi, sex: sex) {
        case .below:
            return "Under \(line) kg/m², the European low-muscle line for older adults (EWGSOP2 2019). Worth raising with your doctor; lifting and enough protein are what raise it."
        case .above:
            return "Above the \(line) kg/m² low-muscle line (EWGSOP2 2019). The line is for spotting low muscle in older adults; above it, more isn't graded. Muscle mass went with longer survival in older adults (Srikanthan 2014). Watch it over years, especially on a cut."
        }
    }

    /// VAT is never graded: one cohort and no agreed cut-off (Cesaro 2026).
    public static let vatText = "Fat around the organs. In US adults under 60, the top quarter had about 6 times the risk of heart death of the bottom quarter, but that is one study with few deaths, and there's no agreed cut-off, so the app shows your change between scans, not a grade (Cesaro et al. 2026). It falls with fat loss and aerobic exercise."

    /// "−120 g since your last scan" between two VAT values in the same unit; nil otherwise.
    public static func vatChange(latest: Double, previous: Double?, unit: VATUnit) -> String? {
        guard let previous else { return nil }
        let change = latest - previous
        let shown = abs(change).formatted(.number.precision(.fractionLength(0)))
        if abs(change) < 0.5 { return "No change since your last scan" }
        return "\(change < 0 ? "−" : "+")\(shown) \(unit.rawValue) since your last scan"
    }
}

/// Waist-to-hip ratio from a typed hip measurement, shown under waist-to-
/// height when a hip is entered. WHO's expert consultation put
/// substantially increased metabolic risk at 0.90 or more in men and 0.85
/// or more in women (WHO, Waist circumference and waist-hip ratio, 2008;
/// from memory). Waist-to-height stays the headline: it predicted risk at
/// least as well across 31 studies (Ashwell 2012).
public enum WaistToHipRatio {
    public static func threshold(sex: BiologicalSex) -> Double {
        sex == .male ? 0.90 : 0.85
    }

    /// Nil for implausible input (app's bounds: 0.5-1.5).
    public static func ratio(waistCm: Double, hipCm: Double) -> Double? {
        guard waistCm > 20, hipCm > 40 else { return nil }
        let ratio = waistCm / hipCm
        return (0.5...1.5).contains(ratio) ? ratio : nil
    }

    public static func isRaised(_ ratio: Double, sex: BiologicalSex) -> Bool {
        ratio >= threshold(sex: sex)
    }
}

/// Waist readings from Apple Health beside the ones typed here, one per day.
public enum WaistReadings {
    public struct Reading: Sendable, Equatable {
        public var date: Date
        public var centimeters: Double
        public var fromHealth: Bool

        public init(date: Date, centimeters: Double, fromHealth: Bool) {
            self.date = date
            self.centimeters = centimeters
            self.fromHealth = fromHealth
        }
    }

    /// Readings within this many cm on the same day are the same measurement (app's choice: a tape moves about 1 cm).
    public static let sameReadingCm = 1.0

    /// Typed readings plus the Health readings that aren't one of them (same
    /// day, within `sameReadingCm`), oldest first. Health readings this app
    /// wrote should already be left out by the caller (their source).
    public static func merge(typed: [Reading], health: [Reading], calendar: Calendar = .current) -> [Reading] {
        var result = typed
        for reading in health {
            let day = calendar.startOfDay(for: reading.date)
            let duplicate = result.contains { other in
                calendar.startOfDay(for: other.date) == day && abs(other.centimeters - reading.centimeters) <= sameReadingCm
            }
            if !duplicate { result.append(reading) }
        }
        return result.sorted { $0.date < $1.date }
    }
}
