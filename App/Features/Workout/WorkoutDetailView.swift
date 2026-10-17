import SwiftUI

/// Read-only view of a finished session.
struct WorkoutDetailView: View {
    let session: WorkoutSession
    @Environment(UserSettings.self) private var settings

    var body: some View {
        let unit = settings.weightUnit
        List {
            Section {
                Text(session.startedAt.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                HStack {
                    StatView(label: "Duration", value: Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                    StatView(label: "Volume", value: "\(unit.format(session.totalVolumeKg)) \(unit.rawValue)")
                    StatView(label: "RPE", value: session.sessionRPE.map { "\($0)/10" } ?? "--", color: Theme.lifting)
                }
            }
            .listRowBackground(Theme.card)

            ForEach(session.orderedExercises) { exercise in
                Section(exercise.name) {
                    ForEach(exercise.orderedSets) { set in
                        HStack {
                            Text(set.isWarmup ? "W" : "\(set.order + 1)")
                                .foregroundStyle(set.isWarmup ? Theme.recoveryModerate : Theme.secondaryText)
                                .frame(width: 28, alignment: .leading)
                            Text("\(unit.format(set.weightKg)) \(unit.rawValue) × \(set.reps)")
                                .monospacedDigit()
                            Spacer()
                            if let rpe = set.rpe {
                                Text("RPE \(rpe.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.name)
    }
}
