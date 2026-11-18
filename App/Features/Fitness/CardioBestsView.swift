import AppCore
import SwiftUI

/// Fitness › Progress › Cardio bests: the fastest 400 m to 10 km on foot and
/// 5 to 40 km on a bike, all time or this year (`CardioBests`). Routes are
/// read once per workout and the efforts cached (`CardioBestsStore`); each
/// visit works through up to `CardioBestsStore.batch` workouts not seen yet,
/// newest first.
struct CardioBestsView: View {
    @Environment(\.healthClient) private var health
    @State private var workouts: [CardioBests.WorkoutEfforts] = CardioBestsStore.workouts()
    @State private var sport: CardioBests.Sport = .run
    @State private var thisYear = false
    @State private var remaining = 0
    @State private var checking = false

    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    private var sports: [CardioBests.Sport] {
        let present = Set(workouts.map(\.sport))
        return CardioBests.Sport.allCases.filter { present.contains($0) }
    }

    private var records: [CardioBests.Record] {
        let interval = thisYear ? Calendar.current.dateInterval(of: .year, for: .now) : nil
        return CardioBests.personalBests(workouts, in: interval)[sport] ?? []
    }

    var body: some View {
        FitnessDetailPage(title: "Cardio bests") {
            if sports.count > 1 {
                Picker("Activity", selection: $sport) {
                    ForEach(sports) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Picker("Period", selection: $thisYear) {
                Text("All time").tag(false)
                Text("This year").tag(true)
            }
            .pickerStyle(.segmented)
            recordsCard
            if checking || remaining > 0 {
                Text(checking ? "Checking routes of earlier workouts…" : "\(remaining) older workouts are checked next time you open this page.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(CardioBests.evidenceNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            pickSport()
            await backfill()
        }
    }

    @ViewBuilder
    private var recordsCard: some View {
        let records = self.records
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: sport.title)
                .padding(.bottom, 8)
            if records.isEmpty {
                Text(checking ? "Looking through your workouts…" : "No \(sport.title.lowercased()) with a GPS route yet. Outdoor workouts recorded with a watch show their best efforts here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Divider().overlay(Theme.separator) }
                if let id = UUID(uuidString: record.workoutID) {
                    NavigationLink {
                        CardioWorkoutDetailView(workoutID: id, title: sport.title)
                    } label: {
                        row(record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func row(_ record: CardioBests.Record) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(CardioBests.distanceLabel(record.effort.distanceMeters))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(record.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CardioBests.timeText(record.effort.seconds))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                Text(speedText(record))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func speedText(_ record: CardioBests.Record) -> String {
        let speed = record.effort.speed
        guard speed > 0 else { return "–" }
        if record.sport == .ride { return CardioSummary.speedText(metersPerSecond: speed, miles: miles) }
        return CardioSummary.paceText((miles ? CardioBests.metersPerMile : 1000) / speed, miles: miles)
    }

    /// Reads the routes of workouts not cached yet (`CardioBestsStore.backfill`).
    private func backfill() async {
        guard let health else { return }
        checking = true
        defer { checking = false }
        let left = await CardioBestsStore.backfill(health: health) { workouts = $0 }
        if let left { remaining = left }
        workouts = CardioBestsStore.workouts()
        pickSport()
    }

    /// Opens on a sport that has bests.
    private func pickSport() {
        if !sports.contains(sport), let first = sports.first { sport = first }
    }
}
