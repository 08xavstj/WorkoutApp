import SwiftUI
import SwiftData
import AppCore

/// Read-only view of a finished session.
struct WorkoutDetailView: View {
    let session: WorkoutSession
    @Environment(UserSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var reloadToken = 0
    @State private var savedTemplate = false
    @State private var supersetGroups: [Int: Int] = [:]

    var body: some View {
        let unit = settings.weightUnit
        List {
            Section {
                Text(session.startedAt.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                HStack {
                    StatView(label: "Duration", value: Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                    StatView(label: "Total lifted", value: "\(unit.format(session.totalVolumeKg)) \(unit.rawValue)")
                    StatView(label: "Effort", value: session.sessionRPE.map { "\($0)/10" } ?? "--", color: Theme.liftingText)
                }
            }
            .listRowBackground(Theme.card)

            HeartRateSourcesSection(
                start: session.startedAt, end: session.endedAt ?? session.startedAt,
                linkedWorkoutUUID: session.linkedWorkoutUUID, linkedWorkoutSource: session.linkedWorkoutSource,
                reload: reloadToken
            )

            ForEach(session.orderedExercises) { exercise in
                Section {
                    let working = exercise.orderedSets.filter { !$0.isWarmup }
                    ForEach(exercise.orderedSets) { set in
                        HStack {
                            Text(set.isWarmup ? "W" : "\((working.firstIndex(where: { $0.persistentModelID == set.persistentModelID }) ?? 0) + 1)")
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
                    NavigationLink {
                        LiftProgressView(exerciseID: exercise.exerciseID, name: exercise.name)
                    } label: {
                        Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(exercise.name)
                        // Superset pairing from the plan, kept for recent sessions (`SupersetRegistry`).
                        if let label = SupersetRegistry.label(order: exercise.order, groups: supersetGroups) {
                            Chip(text: label, color: Theme.sleep)
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    _ = WorkoutTemplate.from(session, in: modelContext)
                    savedTemplate = true
                } label: {
                    Label("Save as my workout", systemImage: "square.and.arrow.down")
                }
            }
        }
        .alert("Saved to My workouts", isPresented: $savedTemplate) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Start it again any time from Add → My workouts.")
        }
        // On the List itself: a Section's .refreshable is never used.
        .refreshable { reloadToken += 1 }
        .task { supersetGroups = SupersetRegistry.groups(for: session.startedAt) }
    }
}

/// Heart rate recorded during the session by each source (AirPods Pro 3 via this
/// app, Garmin, a chest strap...), and how closely the two main ones agree.
private struct HeartRateSourcesSection: View {
    let start: Date
    let end: Date
    var linkedWorkoutUUID: UUID?
    var linkedWorkoutSource: String?
    var reload = 0

    @Environment(\.healthClient) private var health
    @State private var sources: [HeartRateSource] = []
    @State private var merged: HeartRateMerge.Result = .empty
    @State private var linkedWorkout: ExternalWorkout?
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
                MergedHeartRateRow(merged: merged, linkedWorkout: linkedWorkout, linkedSource: linkedWorkoutSource)
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
                            .foregroundStyle(result.meanAbsoluteDifference < 5 ? Theme.recoveryHighText : Theme.recoveryModerateText)
                        HStack {
                            StatView(label: "Avg difference", value: "\(whole(result.meanAbsoluteDifference)) bpm")
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
        .task(id: reload) { await load() }
    }

    private func load() async {
        guard let health, end > start else {
            loaded = true
            return
        }
        let found = (try? await health.heartRateBySource(from: start, to: end)) ?? []
        sources = found.sorted { $0.samples.count > $1.samples.count }
        // The same merge strain uses: ear over wrist during this lift, no averaging (`HeartRateMerge`).
        merged = HeartRateMerge.merge(sources: sources.map(\.mergeSource), liftingWindows: [DateInterval(start: start, end: end)])
        if let linkedWorkoutUUID {
            let margin = WorkoutLinker.searchMargin
            let workouts = (try? await health.externalWorkouts(from: start.addingTimeInterval(-margin), to: end.addingTimeInterval(margin))) ?? []
            linkedWorkout = workouts.first { $0.uuid == linkedWorkoutUUID }
        }
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

/// Which sources the merged series came from, any stretch where they
/// disagreed (the preferred source was kept; see `HeartRateMerge`), and the
/// watch workout linked to this session (`WorkoutLinker`).
private struct MergedHeartRateRow: View {
    let merged: HeartRateMerge.Result
    let linkedWorkout: ExternalWorkout?
    let linkedSource: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mergedText)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            if let disagreementText {
                Text(disagreementText)
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
            if let linkedText {
                Label(linkedText, systemImage: "applewatch")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var mergedText: String {
        let names = merged.sourceNames
        switch names.count {
        case 0: return "Heart rate: no usable readings"
        case 1: return "Heart rate: from \(names[0])"
        default:
            let summary = HeartRateComparison.summary(merged.samples)
            let stats = summary.map { " · avg \(whole($0.average)), max \(whole($0.maximum))" } ?? ""
            return "Heart rate: merged from \(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])\(stats)"
        }
    }

    /// The longest disagreement, e.g. "Apple Watch read 12 bpm lower during sets (3 min)".
    private var disagreementText: String? {
        guard let worst = merged.disagreements.max(by: { $0.minutes < $1.minutes }) else { return nil }
        let direction = worst.meanDifference < 0 ? "lower" : "higher"
        var text = "\(worst.otherSource) read \(whole(abs(worst.meanDifference))) bpm \(direction) during sets (\(worst.minutes) min); \(worst.preferredSource) was used."
        if merged.disagreements.count > 1 { text += " \(merged.disagreements.count) stretches disagreed." }
        return text
    }

    private var linkedText: String? {
        guard let source = linkedSource else { return nil }
        var text = "Linked to \(linkedWorkout?.name ?? "the workout") on \(source)"
        if let kcal = linkedWorkout?.activeKcal, kcal > 0 { text += " · \(whole(kcal)) kcal" }
        return text
    }
}
