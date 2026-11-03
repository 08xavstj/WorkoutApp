import SwiftUI

/// After Finish: what was recorded. The phone gets the same summary.
struct WatchEndView: View {
    @Environment(WatchWorkoutModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.summary?.workoutUUID == nil ? "Workout ended" : "Workout saved")
                    .font(.headline)
                if let summary = model.summary {
                    WatchStatRow(label: "Duration", value: "\(summary.minutes) min")
                    WatchStatRow(label: "Sets", value: "\(setsDone)")
                    WatchStatRow(label: "Avg HR", value: bpm(summary.averageHeartRate))
                    WatchStatRow(label: "Max HR", value: bpm(summary.maximumHeartRate))
                    WatchStatRow(label: "Calories", value: summary.activeKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "–")
                }
                if let problem = model.problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.heart)
                }
                Button("Done") { model.reset() }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.lifting)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    private var setsDone: Int {
        max(model.setsCompletedHere, model.snapshot?.completedSets ?? 0)
    }

    private func bpm(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) bpm" } ?? "–"
    }
}

private struct WatchStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.footnote)
    }
}
