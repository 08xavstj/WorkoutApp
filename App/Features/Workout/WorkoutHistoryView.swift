import SwiftUI
import SwiftData

/// Past gym sessions, newest first.
struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GymStore.self) private var gym
    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var pendingDelete: IndexSet?

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
                // Closure-based: this page is itself pushed with
                // navigationDestination(isPresented:), where a value link
                // plus navigationDestination(for:) did not open reliably.
                NavigationLink {
                    WorkoutDetailView(session: session)
                } label: {
                    SessionRow(session: session, unit: gym.liftingUnit)
                }
                .accessibilityIdentifier("history-session") // UI tests (ScreenshotTests)
            }
            .onDelete { pendingDelete = $0 }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("History")
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if pendingHasHealthWorkout {
                // Only the workouts Tensile saved (the iPhone's, the Tensile Watch app's) can go;
                // one from another app (Garmin, Apple's Workout app) stays (`deleteOwnWorkouts`).
                Button("Delete here and in Apple Health", role: .destructive) {
                    if let offsets = pendingDelete { delete(at: offsets, fromHealth: true) }
                    pendingDelete = nil
                }
                Button("Delete in Tensile only", role: .destructive) {
                    if let offsets = pendingDelete { delete(at: offsets, fromHealth: false) }
                    pendingDelete = nil
                }
            } else {
                Button("Delete", role: .destructive) {
                    if let offsets = pendingDelete { delete(at: offsets, fromHealth: false) }
                    pendingDelete = nil
                }
            }
        } message: {
            Text(deleteMessage)
        }
        // Watch workouts can sync days late (Garmin), so pair recent sessions on each load (`WorkoutLinker`).
        .task {
            guard let health else { return }
            let since = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
            await WorkoutLinker.linkRecent(sessions, since: since, health: health, context: modelContext)
        }
    }

    /// The workouts being deleted, while the question is up.
    private var pendingSessions: [WorkoutSession] {
        guard let pendingDelete else { return [] }
        let list = finished
        return pendingDelete.filter { $0 < list.count }.map { list[$0] }
    }

    /// True when Tensile saved a workout to Apple Health for one of them.
    private var pendingHasHealthWorkout: Bool {
        pendingSessions.contains { $0.savedToHealth || $0.watchWorkoutUUID != nil }
    }

    private var deleteMessage: String {
        var text = "Its sets are removed from Tensile. This can't be undone."
        if pendingHasHealthWorkout {
            text += " The workout Tensile saved in Apple Health, which counts toward strain, can go too."
        }
        if pendingSessions.contains(where: { $0.linkedWorkoutSource != nil }) {
            text += " A workout from another app stays in Apple Health."
        }
        return text
    }

    /// Deletes the sessions; with `fromHealth`, also the Apple Health workouts
    /// Tensile saved for them (the user chose it in the question above).
    private func delete(at offsets: IndexSet, fromHealth: Bool) {
        let list = finished
        for index in offsets where index < list.count {
            let session = list[index]
            if fromHealth, session.savedToHealth || session.watchWorkoutUUID != nil, let health {
                let start = session.startedAt
                let end = session.endedAt ?? session.startedAt
                let watchID = session.watchWorkoutUUID
                Task { _ = await health.deleteOwnWorkouts(start: start, end: end, watchWorkoutUUID: watchID) }
            }
            modelContext.delete(session)
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
                Label("\(session.effortSets.count) sets", systemImage: "square.stack.3d.up")
                // "Volume" so the number isn't read as a body weight next to a scale icon.
                // Whole units, on one line, so the row never stacks.
                Label("Volume \(Int(unit.display(session.totalVolumeKg).rounded()).formatted()) \(unit.rawValue)", systemImage: "scalemass")
                    .lineLimit(1)
                    .fixedSize()
                if let source = session.linkedWorkoutSource {
                    Label(source, systemImage: "applewatch")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }
}
