import SwiftUI
import AppCore

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

            HeartRateSourcesSection(start: session.startedAt, end: session.endedAt ?? session.startedAt)

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

/// Heart rate recorded during the session by each source (AirPods Pro 3 via this
/// app, Garmin, a chest strap...), and how closely the two main ones agree.
private struct HeartRateSourcesSection: View {
    let start: Date
    let end: Date

    @Environment(\.healthClient) private var health
    @State private var sources: [HeartRateSource] = []
    @State private var loaded = false

    var body: some View {
        Section {
            if !loaded {
                ProgressView()
            } else if sources.isEmpty {
                Text("No heart rate recorded during this workout. Wear AirPods Pro 3 while logging, or sync your watch's app and pull to refresh.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(sources) { source in
                    if let summary = HeartRateComparison.summary(source.samples) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).font(.headline)
                                Text("\(summary.samples) readings")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            StatView(label: "Avg", value: "\(whole(summary.average))").frame(width: 50)
                            StatView(label: "Max", value: "\(whole(summary.maximum))").frame(width: 50)
                        }
                    }
                }
                if sources.count >= 2, let result = HeartRateComparison.compare(sources[0].samples, sources[1].samples) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verdict(result))
                            .font(.headline)
                            .foregroundStyle(result.meanAbsoluteDifference < 5 ? Theme.recoveryHigh : Theme.recoveryModerate)
                        HStack {
                            StatView(label: "Avg difference", value: "\(whole(result.meanAbsoluteDifference)) bpm")
                            StatView(label: "Agreement", value: result.correlation.map { "\(whole($0 * 100))%" } ?? "–")
                            StatView(label: "Minutes compared", value: "\(result.overlappingMinutes)")
                        }
                        Text(biasText(result))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Heart rate sources")
        } footer: {
            Text("Some watches (like Garmin) send heart rate to Apple Health only when their app syncs, sometimes only as a summary for strength workouts. Open your watch's app, then come back here.")
        }
        .listRowBackground(Theme.card)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let health, end > start else {
            loaded = true
            return
        }
        let found = (try? await health.heartRateBySource(from: start, to: end)) ?? []
        sources = found.sorted { $0.samples.count > $1.samples.count }
        loaded = true
    }

    private func verdict(_ result: HeartRateComparison.Result) -> String {
        switch result.meanAbsoluteDifference {
        case ..<3: return "\(sources[0].name) and \(sources[1].name) match closely"
        case ..<7: return "Small differences between sources"
        default: return "Sources disagree noticeably"
        }
    }

    private func biasText(_ result: HeartRateComparison.Result) -> String {
        let bias = result.bias
        if abs(bias) < 1 { return "Neither source reads consistently higher." }
        let higher = bias > 0 ? sources[0].name : sources[1].name
        return "\(higher) reads about \(whole(abs(bias))) bpm higher on average. Optical sensors often lag or drop out during heavy sets; ear and wrist can also differ in how fast they react."
    }
}
