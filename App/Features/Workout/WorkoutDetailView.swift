import SwiftUI
import SwiftData
import AppCore

/// Read-only view of a finished session.
struct WorkoutDetailView: View {
    let session: WorkoutSession
    @Environment(GymStore.self) private var gym
    @Environment(\.modelContext) private var modelContext
    @State private var reloadToken = 0
    @State private var savedTemplate = false
    @State private var supersetGroups: [Int: Int] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Fits the set number ("W", "12") at every text size.
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 28

    var body: some View {
        List {
            summarySection

            HeartRateSourcesSection(
                start: session.startedAt, end: session.endedAt ?? session.startedAt,
                linkedWorkoutUUID: session.linkedWorkoutUUID, linkedWorkoutSource: session.linkedWorkoutSource,
                reload: reloadToken
            )

            ForEach(session.orderedExercises) { exercise in
                exerciseSection(exercise)
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
                    Label("Add to saved workouts", systemImage: "square.and.arrow.down")
                }
            }
        }
        .alert("Added to saved workouts", isPresented: $savedTemplate) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Start it again any time from Log › Saved workouts (also under Fitness › Workouts).")
        }
        // On the List itself: a Section's .refreshable is never used.
        .refreshable { reloadToken += 1 }
        .task { supersetGroups = SupersetRegistry.groups(for: session.startedAt) }
    }

    /// The gym's unit, as on every lifting screen (`GymStore.liftingUnit`).
    private var unit: WeightUnit { gym.liftingUnit }

    /// Date, then duration, total lifted and effort; the three stats stack at
    /// accessibility text sizes so none is cut off (ux-audit.md 4.8, P22).
    private var summarySection: some View {
        Section {
            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            summaryStats
        }
        .listRowBackground(Theme.card)
    }

    private var summaryStats: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return layout {
            StatView(label: "Duration", value: Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
            StatView(label: "Total lifted", value: "\(unit.format(session.totalVolumeKg)) \(unit.rawValue)")
            StatView(label: "Effort", value: session.sessionRPE.map { "\($0)/10" } ?? "--", color: Theme.liftingText)
        }
    }

    private func exerciseSection(_ exercise: ExerciseLog) -> some View {
        let sets = exercise.orderedSets
        // Drop stages and mini-sets carry their set's number (`SetStructure`).
        let positions = SetStructure.positions(LiveSetCoach.structureItems(sets))
        return Section {
            ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                setRow(set, position: positions[index])
            }
            NavigationLink {
                LiftProgressView(exerciseID: exercise.exerciseID, name: exercise.name)
            } label: {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("lift-progress-link")
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

    /// One set; VoiceOver hears "Set 2, 8 reps at 60 kilograms, RPE 8"
    /// (ux-audit.md 4.8, P27).
    private func setRow(_ set: SetLog, position: SetStructure.Position) -> some View {
        let number = position.number ?? 1
        let label = set.isWarmup ? "W" : (position.isStage ? set.kind.shortLabel : "\(number)")
        return HStack {
            Text(label)
                // Text colour for the amber accent (ux-audit.md X4, P24).
                .foregroundStyle(set.isWarmup ? Theme.recoveryModerateText : Theme.secondaryText)
                .frame(width: numberWidth, alignment: .leading)
            Text("\(unit.format(set.weightKg)) \(unit.rawValue) × \(set.reps)")
                .monospacedDigit()
            if set.kind != .straight {
                Text(set.kind.title)
                    .font(.caption)
                    .foregroundStyle(Theme.liftingText)
            }
            Spacer()
            if let rpe = set.rpe {
                Text("RPE \(rpe.formatted())")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSet(set, number: number, isStage: position.isStage))
    }

    private func spokenSet(_ set: SetLog, number: Int, isStage: Bool) -> String {
        var parts = [set.isWarmup ? "Warm-up set" : (isStage ? "\(set.kind.stageName) after set \(number)" : "Set \(number)")]
        if set.kind != .straight, !isStage { parts.append(set.kind.title) }
        let reps = set.reps == 1 ? "1 rep" : "\(set.reps) reps"
        parts.append(set.weightKg > 0 ? "\(reps) at \(unit.format(set.weightKg)) \(unit.spokenName)" : reps)
        if let rpe = set.rpe { parts.append("RPE \(rpe.formatted())") }
        return parts.joined(separator: ", ")
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
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @State private var sources: [HeartRateSource] = []
    @State private var merged: HeartRateMerge.Result = .empty
    /// Minutes in zones 1-5 during this workout, from the merged heart rate,
    /// so a past workout keeps its zones whatever today's total says.
    @State private var zoneMinutes: [Double] = []
    @State private var linkedWorkout: ExternalWorkout?
    @State private var loaded = false
    /// Avg and Max columns widen with the text instead of clipping.
    @ScaledMetric(relativeTo: .title3) private var statWidth: CGFloat = 50

    var body: some View {
        Section {
            if !loaded {
                ProgressView()
            } else if sources.isEmpty {
                Text("No heart rate recorded during this workout. Wear AirPods Pro 3 while logging, or sync your watch's app and pull to refresh.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                // With one source and nothing linked, its own row below says it all.
                if merged.sourceNames.count != 1 || !merged.disagreements.isEmpty || linkedWorkoutSource != nil {
                    MergedHeartRateRow(merged: merged, linkedWorkout: linkedWorkout, linkedSource: linkedWorkoutSource)
                }
                WorkoutZonesRow(minutes: zoneMinutes)
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
                            StatView(label: "Avg", value: "\(whole(summary.average))").frame(width: statWidth)
                            StatView(label: "Max", value: "\(whole(summary.maximum))").frame(width: statWidth)
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
            // Only when no source has near minute-by-minute readings (a sparse or missing sync).
            if loaded, !hasPerMinuteSource {
                Text("Some watches (like Garmin) send heart rate to Apple Health only when their app syncs, sometimes only as a summary for strength workouts. Open your watch's app, then come back here.")
            }
        }
        .listRowBackground(Theme.card)
        .task(id: reload) { await load() }
    }

    /// A source with at least one reading every two minutes of the workout
    /// (an app choice for "per-minute", not a published cut-off).
    private var hasPerMinuteSource: Bool {
        let minutes = end.timeIntervalSince(start) / 60
        return sources.contains { Double($0.samples.count) >= max(2, minutes / 2) }
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
        // The same zones strain uses (`StrainCalculator.dailyStrain`, `HeartRateProfile.zone`),
        // with today's profile, or the settings profile before the first refresh.
        let profile = metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
        zoneMinutes = StrainCalculator().dailyStrain(heartRate: merged.samples, strengthSessions: [], profile: profile).zoneMinutes
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

/// Minutes in each heart-rate zone during this workout (zones 1-5 by
/// heart-rate reserve, `HeartRateProfile.zone`), as small bars, or one line
/// when the heart rate stayed below zone 1.
private struct WorkoutZonesRow: View {
    let minutes: [Double]

    private var total: Double { minutes.reduce(0, +) }

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(whole(total)) min in heart-rate zones")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        zoneColumn(index)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenZones)
        } else {
            Text("Heart rate stayed below zone 1 (50% of your heart-rate reserve), so no zone minutes.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func zoneMinutes(_ index: Int) -> Double {
        index < minutes.count ? minutes[index] : 0
    }

    private func zoneColumn(_ index: Int) -> some View {
        let value = zoneMinutes(index)
        let peak = max(minutes.max() ?? 1, 1)
        return VStack(spacing: 3) {
            Text(value > 0 ? "\(whole(value.rounded()))m" : "")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.track)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.zoneColors[index])
                    .frame(height: max(3, 40 * value / peak))
            }
            .frame(height: 40)
            Text("Z\(index + 1)")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var spokenZones: String {
        let parts = (0..<5).compactMap { index -> String? in
            let value = zoneMinutes(index)
            return value >= 0.5 ? "zone \(index + 1) \(whole(value.rounded())) minutes" : nil
        }
        return "\(whole(total)) minutes in heart-rate zones: " + parts.joined(separator: ", ")
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
            // One source is already named on its own row below; say it once.
            if let mergedText {
                Text(mergedText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
            }
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

    private var mergedText: String? {
        let names = merged.sourceNames
        switch names.count {
        case 0: return "Heart rate: no usable readings"
        case 1: return nil
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
