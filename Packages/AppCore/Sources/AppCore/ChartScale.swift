import Foundation

/// The y-axis range for a trend chart. Charts that start at zero flatten a
/// resting heart rate of 52-58 bpm into a straight line, and charts that zoom
/// to the data turn ±1 bpm of noise into a zig-zag. This pads the data by a
/// share of its spread and widens it to a minimum span per measure, so a
/// change looks as big as it is (Cleveland, *The Elements of Graphing Data*,
/// 1994: fill the data region, but don't exaggerate small differences).
/// The minimum spans are the app's choice, set near each measure's ordinary
/// day-to-day variation; they are display settings, not health thresholds.
public enum ChartScale {
    /// The data's range padded by `padding` of its spread on each side,
    /// widened (around its middle) to at least `minimumSpan`. Never goes below
    /// zero for data that is all zero or above. Nil for no finite values.
    public static func domain(_ values: [Double], minimumSpan: Double, padding: Double = 0.1) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return nil }
        let pad = (high - low) * padding
        var lo = low - pad
        var hi = high + pad
        let span = max(minimumSpan, 0)
        if hi - lo < span {
            let middle = (low + high) / 2
            lo = middle - span / 2
            hi = middle + span / 2
        }
        if low >= 0, lo < 0 {
            hi -= lo
            lo = 0
        }
        if hi <= lo { hi = lo + max(span, 1) }
        return lo...hi
    }

    /// The smallest y span for a measure, by its unit (app choice; see above).
    /// Unknown units get 10% of the typical value, at least 1.
    public static func minimumSpan(unit: String, typical: Double) -> Double {
        switch unit.lowercased() {
        case "bpm": 4                       // resting/sleeping heart rate
        case "ms": 10                       // HRV
        case "kg": 2
        case "lb", "lbs": 4
        case "ml/kg/min": 3                 // VO2 max
        case "/min", "br/min", "breaths/min": 4 // breathing rate (12-20 typical)
        case "°c": 1
        case "°f": 2
        case "%": 4
        case "mmhg": 20
        case "h", "hours": 2
        case "cm": 4
        case "in": 2
        default: max(abs(typical) * 0.1, 1)
        }
    }
}
