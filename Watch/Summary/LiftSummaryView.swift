import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// After a lifting workout: the session, time and sets; records; each
/// exercise's sets in one line; heart rate with time in zones and the
/// session's line; the session effort; and where to see more. The phone gets
/// the same summary (`WatchWorkoutSummary`).
struct LiftSummaryView: View {
    @Environment(WatchWorkoutModel.self) private var model

    private var session: WatchSession? { model.finishedSession }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .summaryDone(identifier: "watch-lift-done") { model.reset() }
            .userActivity(WatchHandoff.viewWorkout, isActive: model.summary?.workoutUUID != nil) { activity in
                activity.title = "Workout"
                activity.isEligibleForHandoff = true
                if let id = model.summary?.workoutUUID {
                    activity.userInfo = [WatchHandoff.workoutKey: id.uuidString]
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        let summary = model.summary
        let saved = summary?.workoutUUID != nil
        SummaryHeader(title: session?.name ?? "Workout", saved: saved, facts: facts)
        if let problem = model.problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(WatchPalette.heart)
        }
        if !model.recordLines.isEmpty {
            SummaryTitle(text: "Records")
            ForEach(model.recordLines, id: \.self) { line in
                Label(line, systemImage: "trophy.fill")
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.lifting)
            }
        } else if !model.phoneReachable, setsDone > 0 {
            Text("Records are checked on your iPhone when it's back in reach.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let session {
            let lines = SummarySets.lines(for: session)
            if !lines.isEmpty {
                SummaryTitle(text: "Sets")
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(line.name)
                            .font(.footnote.weight(.semibold))
                        Text(line.detail)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        HeartSummarySection(average: summary?.averageHeartRate, maximum: summary?.maximumHeartRate,
                            zoneSeconds: model.tracker.zoneSeconds, series: model.heartSeries)
        if let calories = summary?.activeKilocalories {
            SummaryRow(label: "Active calories", value: "\(Int(calories.rounded())) kcal")
        }
        if let rpe = summary?.sessionRPE {
            SummaryRow(label: "Session effort", value: "\(rpe) · \(WatchRPEChoice.sessionLabel(rpe))")
        }
        OpenOnPhoneRow(text: "Every set, records and coach notes on your iPhone")
    }

    private var setsDone: Int {
        max(model.setsCompletedHere, session?.completedSets ?? 0)
    }

    /// "52 min · 16 sets · 3 records".
    private var facts: [String] {
        var parts: [String] = []
        if let summary = model.summary { parts.append("\(summary.minutes) min") }
        parts.append(setsDone == 1 ? "1 set" : "\(setsDone) sets")
        if !model.recordLines.isEmpty {
            parts.append(model.recordLines.count == 1 ? "1 record" : "\(model.recordLines.count) records")
        }
        return parts
    }
}
