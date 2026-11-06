import Foundation

/// The one way the phone writes reps in reserve (RIR): "2 in reserve",
/// "2-3 in reserve" for a half-point target (RPE 7.5), "to failure" for none.
/// A half-rep can't be done, so a half shows as the two whole reps around it.
public enum ReserveText {
    /// "2 in reserve", "2-3 in reserve", "to failure". Rounded to the nearest half rep first.
    public static func text(_ reserve: Double) -> String {
        let halves = (max(0, reserve) * 2).rounded() / 2
        let low = Int(halves.rounded(.down))
        let high = Int(halves.rounded(.up))
        if high == 0 { return "to failure" }
        return low == high ? "\(low) in reserve" : "\(low)-\(high) in reserve"
    }

    /// The same from a planned RPE (reps in reserve = 10 − RPE).
    public static func text(rpe: Double) -> String {
        text(10 - rpe)
    }

    /// The range the sets actually ask for, from each one's planned RPE:
    /// "3 in reserve" when they agree, "2-3 in reserve" when big and small
    /// lifts differ. `fallback` (an RPE) when there are none.
    public static func text(rpes: [Double], fallback: Double) -> String {
        let reserves = rpes.map { (max(0, 10 - $0) * 2).rounded() / 2 }
        guard let least = reserves.min(), let most = reserves.max() else { return text(rpe: fallback) }
        let low = Int(least.rounded(.down))
        let high = Int(most.rounded(.up))
        if high == 0 { return "to failure" }
        return low == high ? "\(low) in reserve" : "\(low)-\(high) in reserve"
    }
}
