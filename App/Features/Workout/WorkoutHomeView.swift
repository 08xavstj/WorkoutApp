import SwiftUI
import SwiftData

/// Start or resume a workout, and browse past sessions.
struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var activeSession: WorkoutSession?

    private var inProgress: WorkoutSession? { sessions.first { $0.isActive } }
    private var finished: [WorkoutSession] { sessions.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let inProgress {
                        Button {
                            activeSession = inProgress
                        } label: {
                            Label("Resume \(inProgress.name)", systemImage: "play.circle.fill")
                                .font(.headline)
                        }
                    } else {
                        Button(action: startWorkout) {
                            Label("Start workout", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section("History") {
                    if finished.isEmpty {
                        Text("Your finished workouts will show up here.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(finished) { session in
                        NavigationLink(value: session) {
                            SessionRow(session: session, unit: settings.weightUnit)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Workout")
            .navigationDestination(for: WorkoutSession.self) { session in
                WorkoutDetailView(session: session)
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session)
            }
        }
    }

    private func startWorkout() {
        let session = WorkoutSession(name: defaultName())
        modelContext.insert(session)
        try? modelContext.save()
        activeSession = session
    }

    private func defaultName() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        default: return "Evening Workout"
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(finished[index])
        }
        try? modelContext.save()
    }
}

private struct SessionRow: View {
    let session: WorkoutSession
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.name).font(.headline)
                Spacer()
                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(session.orderedExercises.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            HStack(spacing: 12) {
                Label(Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow)), systemImage: "clock")
                Label("\(session.workingSets.count) sets", systemImage: "square.stack.3d.up")
                Label("\(unit.format(session.totalVolumeKg)) \(unit.rawValue)", systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }
}
