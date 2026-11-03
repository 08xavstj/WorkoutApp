import SwiftUI
import AppCore

/// How the recovery bands read and look.
///
/// The 0-100 score is the app's own summary, so the low band is an "easy day"
/// to plan around, not a diagnosis. Red plus "Low" reads as a stop sign and
/// pushes toward skipping rather than going easy; negative sleep/recovery
/// feedback has measurable nocebo effects (Draganich & Erdal 2014) and
/// tracker anxiety is documented (Baron et al. 2017), both cited from memory
/// in docs/research/behaviour-change.md §5. Red stays for the illness watch.
enum RecoveryWording {
    /// "Easy day", "Normal" or "Recovered".
    static func label(for status: RecoveryCalculator.Status) -> String {
        switch status {
        case .low: "Easy day"
        case .moderate: "Normal"
        case .high: "Recovered"
        }
    }

    /// Ring gradient: a cool blue for easy days instead of alarm red.
    static func colors(for status: RecoveryCalculator.Status?) -> [Color] {
        switch status {
        case .low?: [Theme.oxygenLight, Theme.oxygen]
        case .moderate?: [Theme.recoveryModerateLight, Theme.recoveryModerate]
        case .high?: [Theme.recoveryHighLight, Theme.recoveryHigh]
        case nil: [Theme.track, Theme.secondaryText]
        }
    }

    /// One accent for chips and dots.
    static func color(for status: RecoveryCalculator.Status?) -> Color {
        switch status {
        case .low?: Theme.oxygen
        case .moderate?: Theme.recoveryModerate
        case .high?: Theme.recoveryHigh
        case nil: Theme.secondaryText
        }
    }
}
