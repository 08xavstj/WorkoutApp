import SwiftUI

/// Every exercise in the session, in a list the crown scrolls (no double-tap
/// action here: HIG Gestures). A ring shows working sets done; tap a row to
/// lift it on the Set page; swipe the exercise on screen to skip it (its sets
/// stay open; Finish drops any left). Sets already logged are changed on the
/// phone.
struct LiftExercisesPage: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Binding var page: LiftPage

    var body: some View {
        if let session = model.snapshot, !session.exercises.isEmpty {
            List {
                ForEach(Array(session.exercises.enumerated()), id: \.offset) { index, exercise in
                    Button {
                        model.selectedExercise = index
                        page = .set
                    } label: {
                        ExerciseRow(session: session, index: index, isShown: index == model.shownExercise)
                    }
                    .swipeActions(edge: .trailing) {
                        if index == model.shownExercise, model.exerciseAfterShown != nil {
                            Button {
                                model.skipExercise()
                            } label: {
                                Label("Skip", systemImage: "forward.fill")
                            }
                            .tint(.gray)
                        }
                    }
                }
                Text("Change a logged set on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No exercises: your iPhone has no workout running.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct ExerciseRow: View {
    let session: WatchSession
    let index: Int
    let isShown: Bool

    private var exercise: WatchSession.ExerciseSnapshot { session.exercises[index] }
    /// Working sets; a drop set or rest-pause set counts once, not once per stage.
    private var working: [WatchSession.SetSnapshot] { exercise.sets.filter { !$0.isWarmup && !$0.isStage } }
    private var done: Int { working.filter(\.isCompleted).count }
    private var isDone: Bool { !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted) }

    /// "3 of 4 · next 82.5 × 8", "4 of 4 · done".
    private var detail: String {
        var line = "\(done) of \(working.count)"
        if isDone {
            line += " · done"
        } else if let next = exercise.sets.first(where: { !$0.isCompleted }) {
            line += " · next " + exercise.setText(reps: next.reps, weightKg: next.weightKg, unit: session.unit)
        }
        return line
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(WatchPalette.track, lineWidth: 3)
                RingArc(fraction: working.isEmpty ? 0 : Double(done) / Double(working.count))
                    .stroke(isDone ? WatchPalette.recovery : WatchPalette.lifting, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WatchPalette.recovery)
                } else if let label = exercise.supersetLabel {
                    Text(label)
                        .font(.footnote.weight(.bold))
                        .minimumScaleFactor(0.9)
                }
            }
            .frame(width: 28, height: 28)
            .padding(1.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(isShown ? WatchPalette.lifting : .primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isShown ? "On the set page" : "")
    }
}
