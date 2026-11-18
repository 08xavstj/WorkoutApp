import AppCore
import SwiftUI

/// Cardio and sports from Apple Health over the last 90 days (Tensile's
/// Watch cardio mode, Apple's Workout app, Garmin...), newest first. Each
/// opens its summary: map, heart rate and splits (`CardioWorkoutDetailView`).
struct CardioHistoryView: View {
    @Environment(\.healthClient) private var health
    @State private var workouts: [ExternalWorkout] = []
    @State private var loaded = false

    static let days = 90

    var body: some View {
        List {
            if loaded, workouts.isEmpty {
                ContentUnavailableView(
                    "No cardio yet",
                    systemImage: "figure.run",
                    description: Text("Runs, rides and sports from your watch show up here. Start one from Log › Cardio & sports on Watch.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(workouts) { workout in
                NavigationLink {
                    CardioWorkoutDetailView(workoutID: workout.uuid, title: workout.name)
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: workout.tensileActivity?.systemImage ?? "figure.mixed.cardio", color: Theme.oxygen, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text(detail(workout))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Cardio & sports")
        .overlay {
            if !loaded { ProgressView() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        defer { loaded = true }
        guard let health else { return }
        let now = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -Self.days, to: now) ?? now.addingTimeInterval(-Double(Self.days) * 86_400)
        let found = (try? await health.externalWorkouts(from: start, to: now)) ?? []
        workouts = found.filter { !$0.isStrength }.sorted { $0.start > $1.start }
    }

    private func detail(_ workout: ExternalWorkout) -> String {
        var parts = [workout.start.formatted(date: .abbreviated, time: .shortened), "\(workout.minutes) min"]
        if let km = workout.distanceKm, km > 0.1 {
            let system = Locale.current.measurementSystem
            let miles = system == .us || system == .uk
            parts.append(CardioSummary.distanceText(meters: km * 1000, miles: miles))
        }
        return parts.joined(separator: " · ")
    }
}
