import SwiftUI
import SwiftData
import AppCore

// The end-of-workout summary: total weight lifted, the session's stats, each
// exercise against last time with its records, the muscles worked and how
// the week's sets moved, and lift-goal progress. Shown right after Finish
// (`WorkoutSummaryPresenter`) and from History › workout. The maths and its
// evidence notes are in `WorkoutSummary` (AppCore).

// MARK: - Presenting after Finish

/// Holds the finished session until the workout screen has closed: the
/// finish sheet sets `pending`, and the workout cover's `onDismiss` calls
/// `showPending()`, so the summary sheet never fights the closing cover.
@Observable
final class WorkoutSummaryPresenter {
    static let shared = WorkoutSummaryPresenter()

    @ObservationIgnored var pending: WorkoutSession?
    var shown: WorkoutSession?

    /// Shows the pending summary, if the session still exists.
    func showPending() {
        guard let session = pending else { return }
        pending = nil
        guard !session.isDeleted, session.modelContext != nil, !session.isActive else { return }
        shown = session
    }
}

/// Presents the summary sheet that `WorkoutSummaryPresenter` asks for.
struct WorkoutSummaryCover: ViewModifier {
    @State private var presenter = WorkoutSummaryPresenter.shared

    func body(content: Content) -> some View {
        @Bindable var presenter = presenter
        return content.sheet(item: $presenter.shown) { session in
            WorkoutSummarySheet(session: session)
        }
    }
}

/// The summary in its own navigation stack, with Done; one calm success tap.
struct WorkoutSummarySheet: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            WorkoutSummaryView(session: session)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared = true }
    }
}

// MARK: - Summary

struct WorkoutSummaryView: View {
    let session: WorkoutSession

    @Environment(GymStore.self) private var gym
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(ExerciseLibrary.self) private var library
    @Environment(WeeklyPlanStore.self) private var weeklyPlans
    @Environment(MuscleModel.self) private var muscles
    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var data: SummaryData?
    @State private var heart: SummaryHeart?
    @State private var reload = 0

    private var unit: WeightUnit { gym.liftingUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data {
                    SummaryContent(data: data, heart: heart, unit: unit)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .lockedToScreenWidth()
        }
        .background(alignment: .top) {
            TopGlow(colors: [Theme.Wash.rose, Theme.Wash.peach, Theme.Wash.butter])
        }
        .background(Theme.background)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let data {
                    ShareLink(item: SummaryFormat.shareText(data, heart: heart, unit: unit)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        // Heart rate from a watch can arrive after its app syncs.
        .refreshable { reload += 1 }
        .task(id: reload) {
            data = makeData()
            heart = await loadHeart()
        }
    }

    // MARK: Data

    private func makeData() -> SummaryData {
        let finished = sessions.filter { !$0.isActive }
        let today = session.summaryInput
        let earlier = finished.filter { $0.startedAt < session.startedAt }.map(\.summaryInput)
        let ordered = session.orderedExercises

        let exercises = WorkoutSummary.exerciseResults(today).map { result -> SummaryExercise in
            var change: WorkoutSummary.Change?
            if result.index < today.exercises.count,
               let last = WorkoutSummary.previous(exerciseID: result.exerciseID, before: today.start, in: earlier) {
                change = WorkoutSummary.change(today: today.exercises[result.index], last: last.exercise, lastDate: last.date)
            }
            var records: [String] = []
            if result.index < ordered.count {
                // Same records as the banner and the finish sheet (`SetFeedback.records`).
                records = LiveSetCoach.records(for: ordered[result.index], sessionStart: session.startedAt,
                                               sessions: sessions, unit: unit)
                    .map { $0.message(unit: unit.rawValue) }
            }
            return SummaryExercise(result: result, change: change, records: records)
        }

        let last = WorkoutSummary.comparableSession(to: today, in: earlier)
        let totals = WorkoutSummary.totals(today)
        let muscleData = muscleLines(finished: finished)
        return SummaryData(
            title: session.name,
            date: session.startedAt,
            totals: totals,
            comparison: WorkoutSummary.comparison(volumeKg: totals.volumeKg)?.text,
            rpe: session.sessionRPE,
            exercises: exercises,
            muscles: muscleData.lines,
            usesBlockTargets: muscleData.usesBlock,
            sessionChange: last.map { WorkoutSummary.sessionChange(today: today, last: $0) },
            lastName: last?.name,
            goals: goals(finished: finished, trained: Set(exercises.map(\.result.exerciseID)))
        )
    }

    /// This session's hard sets per muscle, and the week's count before it
    /// (`MuscleCoverage.setsThisWeek`, the count Fitness › Muscles uses),
    /// against this week's block targets when the session is this week's.
    private func muscleLines(finished: [WorkoutSession]) -> (lines: [WorkoutSummary.MuscleLine], usesBlock: Bool) {
        let weekStart = WeeklyPlan.weekStart(containing: session.startedAt)
        let sessionSets = MuscleCoverage.setsThisWeek(Self.workSets(session, library: library),
                                                      weekStart: .distantPast, now: .distantFuture)
        let earlierThisWeek = finished.filter { $0.startedAt >= weekStart && $0.startedAt < session.startedAt }
        let before = MuscleCoverage.setsThisWeek(earlierThisWeek.flatMap { Self.workSets($0, library: library) },
                                                 weekStart: weekStart, now: session.startedAt)
        var targets: [Muscle: ClosedRange<Int>] = [:]
        if weekStart == WeeklyPlan.weekStart(containing: .now), let week = weeklyPlans.volumeTargets(muscles: muscles) {
            for target in week.targets { targets[target.muscle] = target.band }
        }
        let lines = WorkoutSummary.muscleLines(sessionSets: sessionSets, weekBefore: before, targets: targets)
        return (lines, !targets.isEmpty)
    }

    /// Completed working sets as `MuscleModel.refresh` counts them: drop
    /// stages add no set, the set they follow counts its `hardSetCredit`.
    private static func workSets(_ session: WorkoutSession, library: ExerciseLibrary) -> [MuscleRecovery.WorkSet] {
        var sets: [MuscleRecovery.WorkSet] = []
        for exercise in session.exercises {
            guard let info = library.exercise(id: exercise.exerciseID) else { continue }
            let ordered = exercise.orderedSets
            let positions = SetStructure.positions(LiveSetCoach.structureItems(ordered))
            for (index, set) in ordered.enumerated() where set.isCompleted && !set.isWarmup && !positions[index].isStage {
                sets.append(MuscleRecovery.WorkSet(
                    date: set.completedAt ?? session.startedAt,
                    primary: info.primaryMuscles,
                    secondary: info.secondaryMuscles,
                    rpe: set.rpe,
                    volumeCredit: SetStructure.hardSetCredit(stages: positions[index].stages)
                ))
            }
        }
        return sets
    }

    /// Lift goals whose lift was trained today, with today's estimated 1RM
    /// (sets of 10 reps or fewer, `LiftGoalHistory.samples`).
    private func goals(finished: [WorkoutSession], trained: Set<String>) -> [SummaryGoal] {
        let bodyMassKg = metrics.bodyMassKg ?? settings.weightKg
        let upToToday = finished.filter { $0.startedAt <= session.startedAt }
        return settings.goals.liftGoals.filter { trained.contains($0.exerciseID) }.compactMap { goal -> SummaryGoal? in
            guard let target = goal.resolvedTargetKg(bodyMassKg: bodyMassKg) else { return nil }
            let samples = LiftGoalHistory.samples(exerciseID: goal.exerciseID, sessions: upToToday)
            guard let current = samples.first(where: { $0.date == session.startedAt }) else { return nil }
            let previous = samples.last { $0.date < session.startedAt }
            return SummaryGoal(id: goal.id, title: LiftGoalHistory.title(goal, unit: unit), currentKg: current.kg,
                               targetKg: target, changeKg: previous.map { current.kg - $0.kg })
        }
    }

    /// The merged heart rate (`HeartRateMerge`, as History › workout), the
    /// strain this workout alone makes (`StrainCalculator`, the larger of its
    /// heart-rate load and its session-RPE load), zones and active calories.
    private func loadHeart() async -> SummaryHeart {
        let start = session.startedAt
        let end = session.endedAt ?? .now
        let profile = metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
        let strainSession = session.strainSummary
        let linkedIDs = [session.linkedWorkoutUUID, session.watchWorkoutUUID].compactMap { $0 }
        var merged = HeartRateMerge.Result.empty
        var kcal: Double?
        if let health, end > start {
            let sources = (try? await health.heartRateBySource(from: start, to: end)) ?? []
            merged = HeartRateMerge.merge(sources: sources.map(\.mergeSource),
                                          liftingWindows: [DateInterval(start: start, end: end)])
            if !linkedIDs.isEmpty {
                let margin = WorkoutLinker.searchMargin
                let workouts = (try? await health.externalWorkouts(from: start.addingTimeInterval(-margin),
                                                                   to: end.addingTimeInterval(margin))) ?? []
                kcal = workouts.first { linkedIDs.contains($0.uuid) }?.activeKcal
            }
            if kcal == nil, let energy = try? await health.deviceEnergy(from: start, to: end) {
                kcal = energy.active
            }
        }
        let result = StrainCalculator().dailyStrain(heartRate: merged.samples, strengthSessions: [strainSession], profile: profile)
        let stats = HeartRateComparison.summary(merged.samples)
        var activeKcal: Double?
        if let kcal, kcal >= 1 { activeKcal = kcal }
        return SummaryHeart(
            average: stats?.average,
            maximum: stats?.maximum,
            zoneMinutes: result.zoneMinutes,
            strain: result.strain,
            strainFromHeartRate: !merged.samples.isEmpty,
            activeKcal: activeKcal
        )
    }
}

// MARK: - Values

struct SummaryData {
    var title: String
    var date: Date
    var totals: WorkoutSummary.Totals
    var comparison: String?
    var rpe: Int?
    var exercises: [SummaryExercise]
    var muscles: [WorkoutSummary.MuscleLine]
    var usesBlockTargets: Bool
    var sessionChange: WorkoutSummary.SessionChange?
    var lastName: String?
    var goals: [SummaryGoal]
}

struct SummaryExercise: Identifiable {
    var result: WorkoutSummary.ExerciseResult
    var change: WorkoutSummary.Change?
    /// "Best estimated 1RM: 103 kg"…
    var records: [String]
    var id: Int { result.index }
}

struct SummaryGoal: Identifiable {
    var id: UUID
    var title: String
    var currentKg: Double
    var targetKg: Double
    var changeKg: Double?
}

struct SummaryHeart {
    var average: Double?
    var maximum: Double?
    var zoneMinutes: [Double]
    var strain: Double
    var strainFromHeartRate: Bool
    var activeKcal: Double?
}

extension WorkoutSession {
    /// This session as `WorkoutSummary` reads it.
    var summaryInput: WorkoutSummary.LoggedSession {
        WorkoutSummary.LoggedSession(
            name: name,
            start: startedAt,
            end: endedAt ?? .now,
            exercises: orderedExercises.map { exercise in
                WorkoutSummary.LoggedExercise(
                    exerciseID: exercise.exerciseID,
                    name: exercise.name,
                    sets: exercise.orderedSets.map { set in
                        WorkoutSummary.LoggedSet(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup,
                                                 isStage: set.kind.isStage, completedAt: set.completedAt)
                    }
                )
            }
        )
    }
}

// MARK: - Formatting

private enum SummaryFormat {
    static func weight(_ kilograms: Double, _ unit: WeightUnit) -> String {
        "\(unit.format(kilograms)) \(unit.rawValue)"
    }

    /// The total, whole units with grouping: "6,240".
    static func volume(_ kilograms: Double, _ unit: WeightUnit) -> String {
        unit.display(kilograms).formatted(.number.precision(.fractionLength(0)))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    static func rest(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "▲ 120 kg", "▼ 40 kg" or "Same" (under half a display unit).
    static func delta(_ kilograms: Double, _ unit: WeightUnit) -> String {
        let shown = unit.display(kilograms)
        if abs(shown) < 0.5 { return "Same" }
        let arrow = shown > 0 ? "▲" : "▼"
        return "\(arrow) \(weight(abs(kilograms), unit))"
    }

    /// "▲ 5 min", "▼ 3 min" or "Same".
    static func durationDelta(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes == 0 { return "Same" }
        let arrow = minutes > 0 ? "▲" : "▼"
        return "\(arrow) \(abs(minutes)) min"
    }

    /// "3 × 8 · 60 kg, 1 × 6 · 60 kg"; bodyweight sets show reps only.
    static func sets(_ result: WorkoutSummary.ExerciseResult, _ unit: WeightUnit) -> String {
        var parts = result.groups.map { group -> String in
            let reps = "\(group.count) × \(group.reps)"
            return group.weightKg > 0 ? "\(reps) · \(weight(group.weightKg, unit))" : reps
        }
        if result.stages > 0 {
            parts.append(result.stages == 1 ? "+1 drop or mini-set" : "+\(result.stages) drops or mini-sets")
        }
        return parts.joined(separator: ", ")
    }

    /// "Best 65 kg × 5 · est. 1RM 80 kg", or "Best 12 reps".
    static func best(_ result: WorkoutSummary.ExerciseResult, _ unit: WeightUnit) -> String? {
        guard let best = result.bestSet else { return nil }
        guard best.weightKg > 0 else { return "Best \(best.reps) reps" }
        let set = "\(weight(best.weightKg, unit)) × \(best.reps)"
        guard result.estimatedOneRepMaxKg > 0 else { return "Best \(set)" }
        let estimate = weight(result.estimatedOneRepMaxKg.rounded(), unit)
        return "Best \(set) · est. 1RM \(estimate)"
    }

    /// "vs 3 Nov: volume ▲ 120 kg · 1RM ▲ 2.5 kg".
    static func change(_ change: WorkoutSummary.Change, _ unit: WeightUnit) -> String {
        let date = shortDate(change.lastDate)
        let volume = delta(change.volumeKg, unit)
        var text = "vs \(date): volume \(volume)"
        if let estimate = change.estimatedOneRepMaxKg {
            let moved = delta(estimate, unit)
            text += " · 1RM \(moved)"
        }
        return text
    }

    /// "+2.5 kg", "+1 rep", "+1 set".
    static func progression(_ progression: WorkoutSummary.Progression, _ unit: WeightUnit) -> String {
        switch progression {
        case let .heavier(kilograms): "+\(weight(kilograms, unit))"
        case let .moreReps(reps): reps == 1 ? "+1 rep" : "+\(reps) reps"
        case let .moreSets(sets): sets == 1 ? "+1 set" : "+\(sets) sets"
        }
    }

    /// Plain text for the share sheet.
    static func shareText(_ data: SummaryData, heart: SummaryHeart?, unit: WeightUnit) -> String {
        let date = data.date.formatted(date: .abbreviated, time: .omitted)
        let total = volume(data.totals.volumeKg, unit)
        let time = duration(data.totals.duration)
        var lines = ["\(data.title) · \(date)", "Total lifted: \(total) \(unit.rawValue)",
                     "\(data.totals.workingSets) sets · \(data.totals.reps) reps · \(time)"]
        if let heart {
            let strain = whole(heart.strain)
            lines.append("Strain: \(strain)%")
        }
        lines.append("")
        for item in data.exercises {
            let setsText = sets(item.result, unit)
            lines.append("\(item.result.name): \(setsText)")
            for record in item.records {
                lines.append("  PR · \(record)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Sections

private struct SummaryContent: View {
    let data: SummaryData
    let heart: SummaryHeart?
    let unit: WeightUnit

    var body: some View {
        SummaryHero(data: data, heart: heart, unit: unit)
        SummaryStatsGrid(totals: data.totals, rpe: data.rpe, heart: heart)
        if let heart, heart.strainFromHeartRate, heart.zoneMinutes.reduce(0, +) > 0 {
            SummaryZonesCard(minutes: heart.zoneMinutes)
        }
        if !data.exercises.isEmpty {
            SummaryExercisesCard(exercises: data.exercises, unit: unit)
        }
        if !data.muscles.isEmpty {
            SummaryMusclesCard(lines: data.muscles, usesBlockTargets: data.usesBlockTargets)
        }
        if let change = data.sessionChange, let name = data.lastName {
            SummaryLastSessionCard(change: change, name: name, unit: unit)
        }
        if !data.goals.isEmpty {
            SummaryGoalsCard(goals: data.goals, unit: unit)
        }
        SummaryNotes(unit: unit)
    }
}

/// "Workout done", then the total in big type and this workout's strain ring.
private struct SummaryHero: View {
    let data: SummaryData
    let heart: SummaryHeart?
    let unit: WeightUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            totalLayout {
                total
                if let heart {
                    ScoreRing(
                        title: "Strain",
                        value: "\(whole(heart.strain))",
                        unit: "%",
                        subtitle: heart.strainFromHeartRate ? "This workout" : "From your rating",
                        progress: heart.strain / StrainCalculator.maximum,
                        colors: Theme.strainColors,
                        size: 84
                    )
                    .frame(width: 112)
                }
            }
        }
        .card(tint: Theme.lifting)
    }

    private var totalLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private var header: some View {
        let date = data.date.formatted(date: .abbreviated, time: .shortened)
        return HStack(spacing: 10) {
            IconBadge(systemName: "checkmark", color: Theme.lifting, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout done")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("\(data.title) · \(date)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: "Total lifted", color: Theme.liftingText)
            MetricValueText(value: SummaryFormat.volume(data.totals.volumeKg, unit), unit: unit.rawValue, style: .hero)
            if let comparison = data.comparison {
                Text(comparison)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Sets, reps, exercises, time, effort, heart rate and calories as tiles.
private struct SummaryStatsGrid: View {
    let totals: WorkoutSummary.Totals
    let rpe: Int?
    let heart: SummaryHeart?

    var body: some View {
        TileGrid {
            tile("Working sets", "\(totals.workingSets)")
            tile("Reps", "\(totals.reps)")
            tile("Exercises", "\(totals.exercises)")
            tile("Duration", SummaryFormat.duration(totals.duration))
            if let rest = totals.typicalRest {
                tile("Typical rest", SummaryFormat.rest(rest), detail: "Between ticks")
            }
            if let rpe {
                tile("Effort", "\(rpe)/10", detail: RPEScale.sessionLabel(rpe))
            }
            if let average = heart?.average {
                tile("Avg heart rate", "\(whole(average)) bpm")
            }
            if let maximum = heart?.maximum {
                tile("Max heart rate", "\(whole(maximum)) bpm")
            }
            if let kcal = heart?.activeKcal {
                tile("Active energy", "\(whole(kcal)) kcal", detail: "From Apple Health")
            }
        }
    }

    private func tile(_ label: String, _ value: String, detail: String? = nil) -> some View {
        StatView(label: label, value: value, detail: detail)
            .card()
            .accessibilityElement(children: .combine)
    }
}

/// Minutes in zones 1-5 (by heart-rate reserve, `HeartRateProfile.zone`).
private struct SummaryZonesCard: View {
    let minutes: [Double]

    private var total: Double { minutes.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Heart-rate zones", color: Theme.heartText)
            Text("\(whole(total)) min in zones")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    column(index)
                }
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func value(_ index: Int) -> Double {
        index < minutes.count ? minutes[index] : 0
    }

    private func column(_ index: Int) -> some View {
        let minutes = value(index)
        let peak = max(self.minutes.max() ?? 1, 1)
        return VStack(spacing: 3) {
            Text(minutes >= 0.5 ? "\(whole(minutes.rounded()))m" : "")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.track)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.zoneColors[index])
                    .frame(height: max(3, 40 * minutes / peak))
            }
            .frame(height: 40)
            Text("Z\(index + 1)")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var spoken: String {
        let parts = (0..<5).compactMap { index -> String? in
            let minutes = value(index)
            return minutes >= 0.5 ? "zone \(index + 1) \(whole(minutes.rounded())) minutes" : nil
        }
        return "\(whole(total)) minutes in heart-rate zones: " + parts.joined(separator: ", ")
    }
}

/// Each exercise: sets, best set, change since last time and records.
private struct SummaryExercisesCard: View {
    let exercises: [SummaryExercise]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardLabel(text: "Exercises", color: Theme.liftingText)
            ForEach(exercises) { item in
                SummaryExerciseRow(item: item, unit: unit)
                if item.id != exercises.last?.id {
                    Divider().overlay(Theme.separator)
                }
            }
        }
        .card()
    }
}

private struct SummaryExerciseRow: View {
    let item: SummaryExercise
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.result.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                if let progression = item.change?.progression {
                    Chip(text: SummaryFormat.progression(progression, unit), color: Theme.recoveryHigh)
                }
                if !item.records.isEmpty {
                    Chip(text: "PR", color: Theme.lifting, filled: true)
                }
            }
            Text(SummaryFormat.sets(item.result, unit))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            if let best = SummaryFormat.best(item.result, unit) {
                Text(best)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let change = item.change {
                Text(SummaryFormat.change(change, unit))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(item.records, id: \.self) { record in
                Label(record, systemImage: "star.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.liftingText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hard sets per muscle from this workout and where the week now stands.
private struct SummaryMusclesCard: View {
    let lines: [WorkoutSummary.MuscleLine]
    let usesBlockTargets: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Muscles worked", color: Theme.liftingText)
            ForEach(lines) { line in
                SummaryMuscleRow(line: line)
            }
            Text(usesBlockTargets
                 ? "Hard sets this week against your block's target. Helper muscles count half."
                 : "Hard sets this week against 10–20, the range linked to the most muscle growth. Helper muscles count half.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

private struct SummaryMuscleRow: View {
    let line: WorkoutSummary.MuscleLine

    private var sessionText: String {
        let sets = line.sessionSets.formatted(.number.precision(.fractionLength(0...1)))
        return "+\(sets) sets"
    }

    private var weekText: String {
        let before = Int(line.weekBefore.rounded())
        let after = Int(line.weekAfter.rounded())
        return "This week \(before) → \(after) of \(line.target.lowerBound)–\(line.target.upperBound)"
    }

    private var status: (text: String, color: Color) {
        switch line.status {
        case .reached:
            return ("Reached range", Theme.recoveryHigh)
        case .inRange:
            return ("In range", Theme.recoveryHigh)
        case .above:
            return ("Above range", Theme.recoveryModerate)
        case .below:
            let left = max(1, line.target.lowerBound - Int(line.weekAfter.rounded()))
            return ("\(left) to go", Theme.sleep)
        }
    }

    var body: some View {
        let upper = Double(max(1, line.target.upperBound))
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.muscle.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(sessionText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.liftingText)
                Spacer(minLength: 8)
                Chip(text: status.text, color: status.color)
            }
            ProgressView(value: min(line.weekAfter, upper), total: upper)
                .tint(status.color)
            Text(weekText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The last session like this one: total lifted and duration, ▲/▼.
private struct SummaryLastSessionCard: View {
    let change: WorkoutSummary.SessionChange
    let name: String
    let unit: WeightUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let date = SummaryFormat.shortDate(change.lastDate)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Vs last time", color: Theme.liftingText)
            Text("\(name), \(date)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            layout {
                StatView(label: "Total lifted", value: SummaryFormat.delta(change.volumeKg, unit))
                StatView(label: "Duration", value: SummaryFormat.durationDelta(change.duration))
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Lift goals trained today: today's estimated 1RM against the target.
private struct SummaryGoalsCard: View {
    let goals: [SummaryGoal]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Lift goals", color: Theme.liftingText)
            ForEach(goals) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    ProgressView(value: WorkoutSummary.goalFraction(currentKg: goal.currentKg, targetKg: goal.targetKg))
                        .tint(Theme.lifting)
                    Text(detail(goal))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    /// "Est. 1RM 92 kg of 100 kg · ▲ 2 kg since last time".
    private func detail(_ goal: SummaryGoal) -> String {
        let current = LiftGoalHistory.weightText(goal.currentKg, unit: unit)
        let target = LiftGoalHistory.weightText(goal.targetKg, unit: unit)
        var text = "Est. 1RM \(current) of \(target)"
        if let change = goal.changeKg {
            let moved = SummaryFormat.delta(change, unit)
            text += moved == "Same" ? " · same as last time" : " · \(moved) since last time"
        }
        return text
    }
}

/// How the numbers are made, in two lines.
private struct SummaryNotes: View {
    let unit: WeightUnit

    var body: some View {
        // Epley/Brzycki are within about 3 kg from 3-5RM (`LiftGoalProjection.maximumReps`).
        let accuracy = LiftGoalHistory.weightText(3, unit: unit)
        Text("Total lifted is weight × reps over your working sets. Estimated 1RM uses the Epley formula: about ±\(accuracy) from sets of 3–5 reps, less past 10.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
