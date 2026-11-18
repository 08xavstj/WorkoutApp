import AppCore
import SwiftUI

/// The workout's fastest 400 m, 1 km, mile, 5 km and 10 km (or ride
/// distances), with a "Best" chip where it beats every other workout of its
/// kind (`CardioBests`, cached in `CardioBestsStore`). Nothing shows for a
/// workout without a route or of a kind without bests.
struct CardioBestsCard: View {
    let workoutID: UUID
    let date: Date
    let kind: ActivityKind
    let route: CardioRoute

    @State private var efforts: CardioBests.WorkoutEfforts?
    @State private var newBests: Set<Double> = []

    /// Miles where distances are in miles (the US and the UK), as on the rest of the page.
    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    var body: some View {
        Group {
            if let efforts, !efforts.efforts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Best efforts")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(efforts.efforts, id: \.distanceMeters) { effort in
                            GridRow {
                                Text(CardioBests.distanceLabel(effort.distanceMeters))
                                    .foregroundStyle(Theme.secondaryText)
                                Text(CardioBests.timeText(effort.seconds))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.primaryText)
                                Text(speedText(effort, sport: efforts.sport))
                                    .foregroundStyle(Theme.secondaryText)
                                if newBests.contains(effort.distanceMeters) {
                                    Chip(text: "Best", color: Theme.strain)
                                } else {
                                    Color.clear.frame(width: 1, height: 1)
                                }
                            }
                            .font(.subheadline.monospacedDigit())
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text(CardioBests.evidenceNote)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
        }
        .task(id: workoutID) { await load() }
    }

    private func load() async {
        let id = workoutID, date = date, kind = kind, route = route
        let found = await Task.detached(priority: .utility) {
            CardioBestsStore.efforts(id: id, date: date, kind: kind, route: route)
        }.value
        CardioBestsStore.store([id: found])
        efforts = found
        if let found {
            newBests = Set(CardioBests.newBests(for: found, among: CardioBestsStore.workouts()))
        }
    }

    /// Pace on foot ("4:52 /km"), speed on a bike ("31.2 km/h").
    private func speedText(_ effort: CardioBests.Effort, sport: CardioBests.Sport) -> String {
        guard effort.speed > 0 else { return "–" }
        if sport == .ride { return CardioSummary.speedText(metersPerSecond: effort.speed, miles: miles) }
        let unit = miles ? CardioBests.metersPerMile : 1000
        return CardioSummary.paceText(unit / effort.speed, miles: miles)
    }
}
