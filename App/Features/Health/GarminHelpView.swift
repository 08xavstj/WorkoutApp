import SwiftUI

/// What a Garmin watch shares with Apple Health and what stays in Garmin
/// Connect. Setup help, not content, so it belongs under Settings › Data
/// sources (ux-audit.md 4.3, B5), which pushes it. Works pushed onto any
/// NavigationStack.
struct GarminHelpView: View {
    var body: some View {
        HealthDetailPage(title: "Using a Garmin") {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: "Turn on sharing")
                Text("In Garmin Connect, open More › Settings › Connected Apps › Apple Health and turn sharing on.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: "What Tensile gets")
                Text("Garmin Connect shares heart rate, resting heart rate, sleep, steps, distance, floors, energy, workouts, and (on supported watches) blood oxygen and respiration with Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Body Battery, stress and HRV stay in Garmin Connect. Tensile estimates stress from heart rate; type HRV under Log › Overnight HRV.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
}
