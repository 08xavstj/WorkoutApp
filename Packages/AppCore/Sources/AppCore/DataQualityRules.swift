import Foundation

/// Rules for data that's only partly there, so a gap isn't read as a zero.
public enum NutrientCoverage {
    /// Share of logged food days that must include a nutrient before its
    /// average is shown. Many food apps export a nutrient only for foods that
    /// list it, so a nutrient missing on some days would read as falsely low.
    /// 80% is the app's choice (no study sets it).
    public static let minimumShare = 0.8

    /// The daily average over the days that have the nutrient, or nil when
    /// fewer than `minimumShare` of logged days do ("not tracked by your food app").
    /// - Parameters:
    ///   - values: the nutrient's total on each logged day that has it.
    ///   - loggedDays: days with food logged.
    public static func average(_ values: [Double], loggedDays: Int) -> Double? {
        guard loggedDays > 0, !values.isEmpty,
              Double(values.count) >= minimumShare * Double(loggedDays) else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// Reads an amount in grams from a free-text dose ("20 g", "5g", "3000 mg", "4 x 5 g").
public enum DoseText {
    /// Grams per day the text describes, or nil when there's no number.
    /// A number without a unit is taken as grams.
    public static func grams(_ text: String) -> Double? {
        let lower = text.lowercased().replacingOccurrences(of: ",", with: ".")
        var numbers: [(value: Double, unit: String)] = []
        var index = lower.startIndex
        while index < lower.endIndex {
            guard lower[index].isNumber || lower[index] == "." else { index = lower.index(after: index); continue }
            var end = index
            while end < lower.endIndex, lower[end].isNumber || lower[end] == "." { end = lower.index(after: end) }
            let value = Double(lower[index..<end])
            var unitStart = end
            while unitStart < lower.endIndex, lower[unitStart] == " " { unitStart = lower.index(after: unitStart) }
            var unitEnd = unitStart
            while unitEnd < lower.endIndex, lower[unitEnd].isLetter || lower[unitEnd] == "µ" { unitEnd = lower.index(after: unitEnd) }
            if let value { numbers.append((value, String(lower[unitStart..<unitEnd]))) }
            index = end
        }
        guard let last = numbers.last else { return nil }
        let grams: Double
        switch last.unit {
        case "mg": grams = last.value / 1000
        case "mcg", "µg", "ug": grams = last.value / 1_000_000
        case "kg": grams = last.value * 1000
        case "", "g", "gr", "gram", "grams": grams = last.value
        default: return nil // IU, scoops, capsules: not an amount in grams
        }
        // "4 x 5 g": a count before the amount.
        if numbers.count >= 2, numbers[numbers.count - 2].unit == "x" || lower.contains("×") || lower.contains(" x ") {
            return grams * numbers[numbers.count - 2].value
        }
        return grams
    }

    /// Creatine loading is about 20 g a day (0.3 g/kg) for 5-7 days, and
    /// maintenance 3-5 g (Kreider et al., ISSN position stand, JISSN 2017).
    /// 10 g or more a day is treated as loading (the app's cut-off between the two).
    public static let creatineLoadingGrams = 10.0

    public static func isCreatineLoading(_ dose: String) -> Bool {
        (grams(dose) ?? 0) >= creatineLoadingGrams
    }
}
