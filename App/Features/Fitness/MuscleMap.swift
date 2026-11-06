import SwiftUI
import SwiftData
import AppCore

/// Muscle recovery from logged sets (and runs/rides from the watch).
@Observable
final class MuscleModel {
    private(set) var states: [Muscle: MuscleRecovery.State] = [:]
    private(set) var deload: DeloadAdvisor.Advice?
    /// Hard sets per muscle since Monday (`MuscleCoverage.setsThisWeek`), for
    /// the coverage-driven focus; `states[].weeklySets` is the rolling 7 days.
    private(set) var weekSets: [Muscle: Double] = [:]
    /// Working sets from the last few weeks, with what the per-muscle volume
    /// rule needs (`VolumeProgression.summarize`: sets done, effort, reps).
    private(set) var loggedSets: [VolumeProgression.LoggedSet] = []
    /// Cardio workouts from Apple Health in the last 10 days, for the weekly
    /// plan's easy-cardio ticks (`CardioPlanner.doneDays`).
    private(set) var recentCardio: [CardioPlanner.Workout] = []
    /// True once `refresh` has run, so the volume targets are only saved
    /// from real data (`WeeklyPlanStore.refreshVolume`).
    private(set) var hasRefreshed = false

    var suggestedFocus: WorkoutFocus? { MuscleRecovery.suggestedFocus(states) }

    /// The focus that closes the most of this week's gap to 10-20 sets per
    /// muscle, with the movements to prioritise (`MuscleCoverage.suggest`);
    /// nil when nothing lags or every lagging muscle is still recovering.
    func coverage(sessionsLeft: Int, preferred: WorkoutFocus?) -> MuscleCoverage.Result? {
        MuscleCoverage.suggest(setsThisWeek: weekSets, states: states, sessionsLeft: sessionsLeft, preferred: preferred)
    }

    func refresh(sessions: [WorkoutSession], library: ExerciseLibrary, health: HealthKitClient?, hrvBelowNormal: Bool = false) async {
        let now = Date.now
        // Best estimated 1RM per exercise per session, for the deload check.
        let sixWeeks = now.addingTimeInterval(-42 * 86_400)
        var lifts: [DeloadAdvisor.LiftPoint] = []
        for session in sessions where session.startedAt >= sixWeeks {
            for exercise in session.exercises {
                let best = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.map(\.estimatedOneRepMax).max() ?? 0
                if best > 0 { lifts.append(.init(exercise: exercise.name, date: session.startedAt, estimatedOneRepMax: best)) }
            }
        }
        deload = DeloadAdvisor.evaluate(lifts, hrvBelowNormal: hrvBelowNormal, now: now)
        let cutoff = now.addingTimeInterval(-10 * 86_400)
        var sets: [MuscleRecovery.WorkSet] = []
        for session in sessions where session.startedAt >= cutoff {
            for exercise in session.exercises {
                guard let info = library.exercise(id: exercise.exerciseID) else { continue }
                // A drop, rest-pause or myo-rep set is one effortful set for fatigue and,
                // for weekly volume, the straight sets it stands in for (up to 3); its
                // stages add no sets of their own (`SetStructure.hardSetCredit`).
                // No set RPE logged counts as at the target: the session RPE (Foster's
                // CR-10 for the whole session) isn't a set's effort.
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
        }
        loggedSets = Self.makeLoggedSets(sessions: sessions, library: library, now: now)
        var cardio: [MuscleRecovery.Cardio] = []
        var easyCardio: [CardioPlanner.Workout] = []
        if let health, let workouts = try? await health.externalWorkouts(from: cutoff, to: now) {
            for workout in workouts where !workout.isStrength {
                easyCardio.append(CardioPlanner.Workout(name: workout.name, start: workout.start, minutes: workout.minutes))
                let kind: MuscleRecovery.Cardio.Kind? = switch workout.name {
                case "Run": .run
                case "Ride": .ride
                case "Row": .row
                case "Hike", "Stairs": .hike
                default: nil
                }
                if let kind {
                    cardio.append(MuscleRecovery.Cardio(kind: kind, end: workout.end, minutes: Double(workout.minutes)))
                }
            }
        }
        states = MuscleRecovery.evaluate(sets: sets, cardio: cardio, now: now)
        weekSets = MuscleCoverage.setsThisWeek(sets, weekStart: WeeklyPlan.weekStart(containing: now), now: now)
        recentCardio = easyCardio
        hasRefreshed = true
    }

    /// Working sets (warm-ups left out) since three weeks before last Monday:
    /// last week to judge, and the sessions before it to compare reps
    /// against. Finished sessions only hold ticked sets (the finish sheet
    /// deletes the rest), so a skipped set counts as a set not done. Superset
    /// pairing is only known for the last two days (`SupersetRegistry`).
    private static func makeLoggedSets(sessions: [WorkoutSession], library: ExerciseLibrary, now: Date) -> [VolumeProgression.LoggedSet] {
        let thisWeek = WeeklyPlan.weekStart(containing: now)
        let start = Calendar.current.date(byAdding: .day, value: -28, to: thisWeek) ?? thisWeek
        var result: [VolumeProgression.LoggedSet] = []
        for session in sessions where session.startedAt >= start && !session.isActive {
            let groups = SupersetRegistry.groups(for: session.startedAt)
            for exercise in session.exercises {
                guard let info = library.exercise(id: exercise.exerciseID) else { continue }
                let primary = info.primaryMuscles.compactMap { Muscle(rawValue: $0.lowercased()) }
                let secondary = info.secondaryMuscles.compactMap { Muscle(rawValue: $0.lowercased()) }
                let compound = ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound ?? (info.mechanic == "compound")
                // Drop stages and mini-sets aren't sets of their own here: the set they
                // follow counts as the sets it stands in for (`SetStructure.hardSetCredit`),
                // and their lighter, fatigued reps stay out of the reps-dropped comparison.
                // No set RPE = at the target (not the whole-session RPE).
                let ordered = exercise.orderedSets
                let positions = SetStructure.positions(LiveSetCoach.structureItems(ordered))
                let working = ordered.indices.filter { !ordered[$0].isWarmup && !positions[$0].isStage }
                for (index, setIndex) in working.enumerated() {
                    let set = ordered[setIndex]
                    result.append(VolumeProgression.LoggedSet(
                        exerciseID: exercise.exerciseID, name: exercise.name, sessionStart: session.startedAt,
                        order: index, primary: primary, secondary: secondary, weightKg: set.weightKg, reps: set.reps,
                        rpe: set.rpe, isCompleted: set.isCompleted,
                        isCompound: compound, supersetGroup: groups[exercise.order],
                        setCredit: SetStructure.hardSetCredit(stages: positions[setIndex].stages)
                    ))
                }
            }
        }
        return result
    }
}

// MARK: - Body drawing

/// Muscle outlines (see BodyMapData.swift), scaled to fit while keeping proportions.
nonisolated struct PolygonShape: Shape {
    let polygons: [[Double]]
    /// minX, minY, maxX, maxY of the whole figure, so every region scales the same.
    let bounds: [Double]

    func path(in rect: CGRect) -> Path {
        let width = bounds[2] - bounds[0]
        let height = bounds[3] - bounds[1]
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.midX - width * scale / 2
        let originY = rect.midY - height * scale / 2
        var path = Path()
        for polygon in polygons where polygon.count >= 6 {
            for index in stride(from: 0, to: polygon.count - 1, by: 2) {
                let point = CGPoint(x: originX + (polygon[index] - bounds[0]) * scale,
                                    y: originY + (polygon[index + 1] - bounds[1]) * scale)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        return path
    }
}

/// One side of the body, each muscle region filled by `color(for:)`.
struct BodyFigure: View {
    let data: [(String, [Double])]
    let bounds: [Double]
    /// Region names: Muscle raw values, "upperBack" (lats + upper back) or "body".
    let color: (String) -> Color

    var body: some View {
        let regions = Dictionary(grouping: data, by: \.0).mapValues { $0.map(\.1) }
        ZStack {
            ForEach(regions.keys.sorted(), id: \.self) { region in
                let shape = PolygonShape(polygons: regions[region] ?? [], bounds: bounds)
                shape.fill(color(region))
                    .overlay(shape.stroke(Theme.card, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)))
            }
        }
        .aspectRatio((bounds[2] - bounds[0]) / (bounds[3] - bounds[1]), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

/// The body map, on Fitness › Progress › Muscles (`MusclesDetailView`). A
/// plain card: heart red is for the heart only (ux-audit.md 4.5 colour rules).
struct MuscleMapCard: View {
    @Environment(MuscleModel.self) private var model
    @State private var mode = Mode.recovery

    enum Mode: String, CaseIterable, Identifiable {
        case recovery = "Rest status"
        case volume = "Last 7 days"
        var id: String { rawValue }
    }

    var body: some View {
        let states = model.states
        VStack(alignment: .leading, spacing: 14) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    BodyFigure(data: BodyMapData.front, bounds: BodyMapData.backBounds) { color(region: $0, states) }
                    Text("Front").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 6) {
                    BodyFigure(data: BodyMapData.back, bounds: BodyMapData.backBounds) { color(region: $0, states) }
                    Text("Back").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(states))
            legend
            details(states)
        }
        .card()
    }

    /// Colour for a drawn region; "upperBack" shows the more tired of lats and upper back.
    private func color(region: String, _ states: [Muscle: MuscleRecovery.State]) -> Color {
        if region == "upperBack" {
            let pair = [states[.lats], states[.middleBack]].compactMap { $0 }
            let worst = mode == .recovery ? pair.min { $0.recovery < $1.recovery } : pair.max { $0.weeklySets < $1.weeklySets }
            return color(worst)
        }
        guard let muscle = Muscle(rawValue: region) else { return Theme.bodyNeutral }
        return color(states[muscle])
    }

    private func color(_ state: MuscleRecovery.State?) -> Color {
        guard let state else { return Theme.bodyNeutral }
        switch mode {
        case .recovery:
            // Grey = not trained recently; green = trained and ready again.
            guard state.lastTrained != nil else { return Theme.bodyNeutral }
            // Overworked (`MuscleRecovery.State.isOverworked`, recovery under 60) is
            // named in red below, so it's painted red too, not amber.
            if state.isOverworked { return Theme.recoveryLow }
            if state.recovery >= 99 { return Theme.recoveryHigh }
            switch state.status {
            case .fresh: return Theme.recoveryHigh
            case .recovering: return Theme.recoveryModerate
            case .fatigued: return Theme.recoveryLow
            }
        case .volume:
            switch state.volume {
            case .none: return Theme.bodyNeutral
            case .low: return Theme.oxygenLight
            case .productive: return Theme.recoveryHigh
            case .high: return Theme.strain
            }
        }
    }

    /// What the figures show, for VoiceOver.
    private func accessibilitySummary(_ states: [Muscle: MuscleRecovery.State]) -> String {
        let trained = Muscle.allCases.compactMap { states[$0] }.filter { $0.lastTrained != nil }
        guard !trained.isEmpty else { return "Body map: no muscles trained recently." }
        let parts = trained.map { state in
            mode == .recovery
                ? "\(state.muscle.name) \(state.recovery >= 99 ? "ready" : (state.status == .fatigued || state.isOverworked ? "tired" : "recovering"))"
                : "\(state.muscle.name) \(state.weeklySets.formatted(.number.precision(.fractionLength(0...1)))) sets"
        }
        return "Body map: " + parts.joined(separator: ", ")
    }

    private var legend: some View {
        let items: [(String, Color)] = mode == .recovery
            ? [("Ready", Theme.recoveryHigh), ("Recovering", Theme.recoveryModerate), ("Tired", Theme.recoveryLow), ("Not trained", Theme.bodyNeutral)]
            : [("Under 10 sets", Theme.oxygenLight), ("10-20 sets", Theme.recoveryHigh), ("Over 20", Theme.strain)]
        // Wraps at large text sizes instead of overflowing.
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 9, height: 9)
                    Text(item.0).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func details(_ states: [Muscle: MuscleRecovery.State]) -> some View {
        let all = Muscle.allCases.compactMap { states[$0] }
        let overworked = all.filter(\.isOverworked)
        let resting = all.filter { $0.status != .fresh && !$0.isOverworked }.sorted { $0.recovery < $1.recovery }
        let major: [Muscle] = [.chest, .lats, .middleBack, .shoulders, .quadriceps, .hamstrings, .glutes, .biceps, .triceps]
        let under = all.filter { major.contains($0.muscle) && $0.volume != .productive && $0.volume != .high }
        VStack(alignment: .leading, spacing: 10) {
            if all.allSatisfy({ $0.lastTrained == nil }) {
                Text("Log a gym session and the muscles you worked light up here: red when tired, amber while recovering, green once ready again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !overworked.isEmpty {
                row("exclamationmark.triangle.fill", Theme.recoveryLow,
                    "Overworked: \(overworked.map(\.muscle.name).joined(separator: ", "))",
                    "Over 20 hard sets (sets taken close to failure) in the last 7 days and not recovered. Give them 2-3 days or cut volume; more sets past this point add fatigue, not muscle.")
            }
            if !resting.isEmpty {
                row("hourglass", Theme.recoveryModerate, "Still recovering",
                    resting.prefix(4).map { state in
                        let hours = state.hoursUntilFresh.map { " — ready in ~\(Int($0.rounded(.up))) h" } ?? ""
                        return "\(state.muscle.name)\(hours)"
                    }.joined(separator: " · "))
            }
            if mode == .volume, !under.isEmpty, !all.allSatisfy({ $0.lastTrained == nil }) {
                row("arrow.up.circle.fill", Theme.oxygen, "Could use more",
                    under.map { "\($0.muscle.name) \($0.weeklySets.formatted(.number.precision(.fractionLength(0...1))))" }.joined(separator: " · ")
                    + " in the last 7 days. Aim for 10-20 hard sets per muscle a week.")
            }
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primaryText)
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
