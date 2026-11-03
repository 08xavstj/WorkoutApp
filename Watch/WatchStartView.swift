import SwiftUI

/// Today's session from the phone, if one is running, else an empty workout.
struct WatchStartView: View {
    @Environment(WatchWorkoutModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let session = model.snapshot, !session.isFinished {
                    Text(session.name)
                        .font(.headline)
                    Text("\(session.exercises.count) exercises · \(session.totalSets) sets")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.start(sessionID: session.id) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTheme.lifting)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase == .starting)
                } else {
                    Text("No workout on your iPhone")
                        .font(.headline)
                    Text("Start one there, or record heart rate and calories from here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.start(sessionID: nil) }
                    } label: {
                        Label("Start empty", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTheme.strain)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase == .starting)
                }
                if model.phase == .starting {
                    Text("Starting…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let problem = model.problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.heart)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Tensile")
    }
}
