import SwiftUI

/// Every exercise in the session; tap one to log it on the live page.
struct WatchExerciseListView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Binding var page: WatchPage

    var body: some View {
        if let session = model.snapshot {
            List {
                ForEach(Array(session.exercises.enumerated()), id: \.offset) { index, exercise in
                    Button {
                        model.selectedExercise = index
                        page = .live
                    } label: {
                        WatchExerciseRow(exercise: exercise, position: index + 1, isNext: index == session.nextExerciseIndex)
                    }
                }
            }
            .navigationTitle("Exercises")
        } else {
            Text("No exercises: your iPhone has no workout running.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct WatchExerciseRow: View {
    let exercise: WatchSession.ExerciseSnapshot
    let position: Int
    let isNext: Bool

    /// Working sets; a drop set or rest-pause set counts once, not once per stage.
    private var working: [WatchSession.SetSnapshot] { exercise.sets.filter { !$0.isWarmup && !$0.isStage } }
    private var isDone: Bool { !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted) }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isDone ? WatchTheme.recovery : Color.white.opacity(0.12))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                } else {
                    Text(exercise.supersetLabel ?? "\(position)")
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text(isNext ? "Up next · \(working.count) sets" : "\(working.filter(\.isCompleted).count) of \(working.count) sets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
