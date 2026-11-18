import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// After a cardio workout or sport: time, distance and average pace or
/// speed; time in zones; the heart-rate line; splits; climb; time in the
/// target; laps; and where to see the map. Nothing is sent to the phone: it
/// reads the saved workout from Apple Health.
struct CardioSummaryView: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .summaryDone(identifier: "watch-cardio-done") { cardio.reset() }
            .userActivity(WatchHandoff.viewWorkout, isActive: cardio.savedWorkoutID != nil) { activity in
                activity.title = cardio.summary?.activity.title ?? "Workout"
                activity.isEligibleForHandoff = true
                if let id = cardio.savedWorkoutID {
                    activity.userInfo = [WatchHandoff.workoutKey: id.uuidString]
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        let miles = watchUsesMiles()
        if let summary = cardio.summary {
            SummaryHeader(title: summary.activity.title, saved: summary.saved, facts: [], color: WatchPalette.strain)
            if let problem = cardio.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.heart)
            }
            MetricBlock(value: workoutElapsedText(summary.activeSeconds), label: "Time", role: .secondary,
                        color: WatchPalette.strain)
            if summary.activity.movement != .stationary, let meters = summary.distanceMeters {
                HStack(alignment: .bottom) {
                    let distance = CardioSummary.distanceText(meters: meters, miles: miles).split(separator: " ")
                    MetricBlock(value: String(distance.first ?? "--"), unit: String(distance.last ?? ""),
                                label: "Distance", role: .tertiary)
                    Spacer(minLength: 4)
                    if let pace = summary.paceOrSpeedText(miles: miles) {
                        MetricBlock(value: pace, label: summary.activity.movement.showsSpeed ? "Avg speed" : "Avg pace",
                                    role: .tertiary)
                    }
                }
            }
            HeartSummarySection(average: summary.averageBpm, maximum: summary.maximumBpm,
                                zoneSeconds: summary.zoneSeconds, series: cardio.heartSeries)
            let laps = cardio.laps.laps
            if summary.activity.movement != .stationary, laps.contains(where: \.isAuto) {
                SplitsSection(laps: laps.filter(\.isAuto), fastest: cardio.laps.fastestLapNumber, miles: miles)
            }
            if let gain = summary.elevationGainMeters {
                SummaryRow(label: "Climb", value: CardioSummary.elevationText(meters: gain, feet: miles))
            }
            if summary.activity.movement.showsSpeed, let top = summary.maximumSpeed {
                SummaryRow(label: "Top speed", value: CardioSummary.speedText(metersPerSecond: top, miles: miles))
            }
            if let share = summary.bandShare {
                SummaryRow(label: "In \(summary.target.title) range",
                           value: "\(watchClock(summary.bandSeconds)) · \(Int((share * 100).rounded()))%")
            }
            let marked = laps.filter { !$0.isAuto }.count
            if marked > 0 {
                SummaryRow(label: summary.activity.movement == .stationary ? "Periods" : "Laps", value: "\(marked)")
            }
            if let calories = summary.activeKilocalories {
                SummaryRow(label: "Active calories", value: "\(Int(calories.rounded())) kcal")
            }
            OpenOnPhoneRow(text: summary.hasRoute ? "Map, splits and coach notes on your iPhone"
                                                  : "Splits and coach notes on your iPhone")
        } else {
            SummaryHeader(title: "Workout ended", saved: false, facts: [])
            if let problem = cardio.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.heart)
            }
        }
    }
}
