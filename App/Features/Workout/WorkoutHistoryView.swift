import SwiftUI
import SwiftData

/// Past gym sessions, newest first.
struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var finished: [WorkoutSession] { sessions.filter { !$0.isActive } }

    var body: some View {
        List {
            if finished.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "dumbbell",
                    description: Text("Finished workouts show up here.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(finished) { session in
                NavigationLink(value: session) {
                    SessionRow(session: session, unit: settings.weightUnit)
                }
            }
            .onDelete(perform: delete)
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("History")
        .navigationDestination(for: WorkoutSession.self) { session in
            WorkoutDetailView(session: session)
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
