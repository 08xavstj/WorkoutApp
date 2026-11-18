import AppCore
import SwiftUI

/// The hard and easy bouts of an interval workout, one row each: length,
/// average and peak heart rate, and pace or speed when there is a route
/// (`IntervalBouts`; competitor-features-2026-11.md, B10). Bouts come from
/// Tensile's interval session when the workout names one (the steps the
/// Watch recorded, else the plan), else from the segments the recording app
/// saved. Nothing shows for a workout with neither, or when the bouts are
/// plain laps the splits table already shows.
struct IntervalBoutsCard: View {
    let workoutID: UUID
    let heartRate: [HeartRateSample]
    let route: CardioRoute?
    let showsPace: Bool
    /// The page shows a splits table, so plain laps would repeat it.
    var hasSplits = false

    @Environment(\.healthClient) private var health
    @State private var bouts: [IntervalBouts.Bout] = []
    @State private var fromSession = false
    @State private var fromRecordedSteps = false

    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    private var hasSpeed: Bool { bouts.contains { $0.speed != nil } }

    var body: some View {
        Group {
            if IntervalBouts.showsCard(bouts, fromSession: fromSession, hasSplits: hasSplits) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(IntervalBouts.isIntervalWorkout(bouts) ? "Intervals" : "Laps")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    table
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
        }
        .task(id: workoutID) { await load() }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Bout")
                Text("Time")
                Text("Avg HR")
                Text("Peak")
                if hasSpeed { Text(showsPace ? "Pace" : "Speed") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            ForEach(bouts) { bout in
                GridRow {
                    Text(bout.kind.title)
                        .fontWeight(bout.kind == .work ? .semibold : .regular)
                        .foregroundStyle(bout.kind == .work ? Theme.strainTextColor : Theme.primaryText)
                    Text(CardioBests.timeText(bout.seconds))
                    Text(bout.averageBpm.map { "\(whole($0))" } ?? "–")
                    Text(bout.peakBpm.map { "\(whole($0))" } ?? "–")
                    if hasSpeed { Text(speedText(bout)) }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func speedText(_ bout: IntervalBouts.Bout) -> String {
        guard let speed = bout.speed else { return "–" }
        if showsPace {
            let unit = miles ? CardioBests.metersPerMile : 1000
            return RouteSeries.pace(speed: speed, unitMeters: unit).map { CardioSummary.paceText($0, miles: miles) } ?? "–"
        }
        return CardioSummary.speedText(metersPerSecond: speed, miles: miles)
    }

    private var note: String {
        let source = fromSession
            ? (fromRecordedSteps
                ? "Bouts are the interval steps your Watch recorded."
                : "Bouts follow the interval session's plan from the start of the workout, moved for pauses.")
            : "Bouts are the segments the recording app saved; hard and easy are told apart by heart rate (or speed)."
        var text = source + " Heart rate lags effort by a minute or two, so a hard bout's average reads below where it ended."
        // Only under real intervals (Milanović Z, et al. Sports Med 2015;45(10):1469-1481).
        if IntervalBouts.showsIntervalEvidence(bouts, fromSession: fromSession) {
            text += " Intervals like these raise VO₂ max more than steady cardio (Milanović 2015)."
        }
        return text
    }

    private func load() async {
        guard let health, let structure = try? await health.workoutStructure(id: workoutID) else { return }
        let readings = heartRate.map { (date: $0.date, bpm: $0.bpm) }
        let segments: [IntervalBouts.Segment]
        if let id = structure.intervalSessionID, let session = IntervalSession.named(id) {
            // The steps the Watch ran, so a skipped step is left out; the plan
            // only when the workout has none (recorded before they were saved).
            let recorded = IntervalBouts.recorded(session, steps: structure.steps)
            fromRecordedSteps = !recorded.isEmpty
            segments = fromRecordedSteps ? recorded
                : IntervalBouts.planned(session, start: structure.start, end: structure.end, pauses: structure.pauses)
            fromSession = true
        } else if structure.segments.count >= 2 {
            let raw = structure.segments.map { IntervalBouts.Segment(start: $0.start, end: $0.end, kind: .lap) }
            segments = IntervalBouts.labelled(raw, heartRate: readings, route: route)
        } else {
            return
        }
        bouts = IntervalBouts.bouts(segments, heartRate: readings, route: route)
    }
}
