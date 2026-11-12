import Foundation

// MARK: - Rest timer

/// Default rest between sets, from the user's training goal.
///
/// - Muscle: rest of more than 60 s gave slightly more growth than shorter
///   rest, with no clear extra benefit past ~90 s (Singer et al., Front Sports
///   Act Living 2024), so 90 s for small lifts and 2 min for big ones, which
///   need more time to keep their reps up.
/// - Strength: 3 min between heavy sets lifted more and built more muscle than
///   1 min in trained men (Schoenfeld et al., J Strength Cond Res 2016); a
///   review of trained lifters found rests over 2 min better for strength
///   (Grgic et al., Sports Med 2018); the ACSM suggests 2-3+ min for heavy
///   multi-joint lifts (position stand, Med Sci Sports Exerc 2009). So 3 min
///   on big lifts and 2 min on small ones.
/// - Balanced: 2.5 min on big lifts (between the 2-3 min the strength evidence
///   wants and the ~90 s that is enough for growth), 90 s on small ones.
/// - Endurance / general health: shorter rests (60-90 s) keep the session
///   brisk; this is common practice rather than a tested optimum.
/// - Strength + muscle: 2.5 min on big lifts (3 min on the heavy first lift,
///   `heavyLiftSeconds`), 90 s on small ones.
/// - Squats and hinges get at least 2.5 min (3 min in the balanced and
///   strength + muscle styles) in every style but endurance: heavy
///   multi-joint lifts keep their reps up with 2-3+ min (Schoenfeld et al.
///   2016; Grgic et al. 2018); the split by pattern is the app's choice
///   (audit 2026-11 §20).
///
/// These defaults are also what `WorkoutPlanner.estimatedMinutes` counts per
/// set, so the plan's length matches the timer the session actually runs.
public enum RestTimer {
    public static func defaultSeconds(style: TrainingStyle, compound: Bool) -> Int {
        switch style {
        case .muscle: compound ? 120 : 90
        case .balanced: compound ? 150 : 90
        case .strength: compound ? 180 : 120
        case .endurance: compound ? 90 : 60
        case .strengthAndMuscle: compound ? 150 : 90
        }
    }

    /// The default for one movement pattern: squats and hinges rest longer
    /// (see above). Nil slot = an exercise outside the catalog (isolation rest).
    public static func defaultSeconds(style: TrainingStyle, slot: MovementSlot?) -> Int {
        let base = defaultSeconds(style: style, compound: slot?.isCompound ?? false)
        guard style != .endurance, slot == .squat || slot == .hinge else { return base }
        return max(base, style == .muscle ? 150 : 180)
    }

    /// The default for an exercise by ID (`defaultSeconds(style:slot:)`), for the rest timer.
    public static func defaultSeconds(style: TrainingStyle, exerciseID: String) -> Int {
        defaultSeconds(style: style, slot: ExerciseCatalog.slot(for: exerciseID))
    }

    /// Rest on the heavy first lift of the strength + muscle style (4-6 reps):
    /// 3 min, as for the strength style (Schoenfeld et al. 2016).
    public static let heavyLiftSeconds = 180

    /// Rest after a warm-up ramp set (`WarmUp`). Kept short, an app choice:
    /// ramp sets are light and far from failure, and the point of a warm-up
    /// is raised muscle temperature, which starts to decay within about 15-20
    /// minutes of stopping (McGowan, Pyne, Thompson & Rattray, Sports Med
    /// 2015, review), so long waits between ramp sets would undo it.
    public static let warmUpRestSeconds = 60

    /// Choices offered for a manual override.
    public static let choices = [45, 60, 90, 120, 150, 180, 240]
}

// MARK: - Custom workouts

extension EquipmentKind {
    /// Maps the exercise library's equipment names onto the gym's equipment.
    public static func fromLibrary(_ name: String?) -> EquipmentKind? {
        switch name?.lowercased() {
        case "barbell": .barbell
        case "dumbbell": .dumbbell
        case "kettlebells": .kettlebell
        case "cable": .cable
        case "machine": .machine
        case "e-z curl bar": .ezBar
        case "bands": .bands
        case "body only": .bodyweight
        default: nil
        }
    }
}

/// One exercise in a workout the user built themselves.
public struct TemplateItem: Sendable, Equatable {
    public var exerciseID: String
    public var name: String
    public var sets: Int
    public var reps: ClosedRange<Int>
    /// Target effort (RPE, reps-in-reserve scale); nil = 8 (2 reps left).
    public var rpe: Double?
    /// A fixed weight the user chose, in the gym's unit. Nil = suggest one.
    public var weight: Double?
    /// What the weight is loaded on, when the catalog doesn't know the exercise.
    public var libraryLoad: EquipmentKind?

    public init(exerciseID: String, name: String, sets: Int, reps: ClosedRange<Int>, rpe: Double? = nil,
                weight: Double? = nil, libraryLoad: EquipmentKind? = nil) {
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.reps = reps
        self.rpe = rpe
        self.weight = weight
        self.libraryLoad = libraryLoad
    }
}

extension WorkoutPlanner {
    public static let defaultTemplateRPE = 8.0

    /// Turns a custom workout into planned exercises. The user's own choices
    /// (exercises, sets, reps, effort, fixed weights) are kept as they are;
    /// only missing weights are filled in, from history: a weight you can
    /// load for the target reps and effort, or last time's weight when the
    /// exercise isn't loaded on this gym's equipment. Catalog compound lifts
    /// with a weight get warm-up ramp sets (`WarmUp`), like planned sessions.
    /// The same never-again and pain rules as planned sessions apply
    /// (`checkedTemplate`): pass `exerciseFilter`, else the planner's own.
    public func prescribe(template items: [TemplateItem], history: [String: ExerciseHistory],
                          exerciseFilter: ExerciseFilter? = nil) -> [PlannedExercise] {
        checkedTemplate(items, history: history, exerciseFilter: exerciseFilter).exercises
    }

    /// A saved workout made safe for today: what `prescribe(template:)` returns, plus the names left out.
    public struct CheckedTemplate: Sendable, Equatable {
        public var exercises: [PlannedExercise]
        /// Exercises left out (never again, a 6+/10 sore area, or equipment
        /// the gym lacks) with nothing to swap in, by name.
        public var skipped: [String]
    }

    /// `prescribe(template:)` with the planner's rules for a saved workout:
    /// - a never-again exercise, one loading a 6+/10 sore area, or one the gym
    ///   can't do (missing equipment, nothing to load it with) is swapped for
    ///   the first allowed option for the same movement (a regression first,
    ///   `ExerciseFilter.apply`) and says so; with no option it is left out
    ///   (`skipped`);
    /// - a lift loading a 3-5/10 area gets the pain cap (`ExerciseFilter.capLoad`);
    /// - a fixed weight you set is rounded down to one the gym can load
    ///   (a 52 kg barbell becomes 50 on 2.5 kg jumps).
    public func checkedTemplate(_ items: [TemplateItem], history: [String: ExerciseHistory],
                                exerciseFilter: ExerciseFilter? = nil) -> CheckedTemplate {
        let filter = exerciseFilter ?? self.exerciseFilter
        var planner = self
        planner.exerciseFilter = filter
        var kept: [TemplateItem] = []
        var swapNotes: [String: String] = [:]
        var skipped: [String] = []
        var taken = Set(items.map(\.exerciseID))
        for item in items {
            let catalog = ExerciseCatalog.exercise(id: item.exerciseID)
            let slot = ExerciseCatalog.slot(for: item.exerciseID)
            let blocked = filter.map { filter in
                filter.neverAgain.contains(item.exerciseID)
                    || (slot.map { !filter.allows(CatalogExercise(id: item.exerciseID, name: item.name, load: catalog?.load,
                                                                 requires: catalog?.requires ?? []), slot: $0) } ?? false)
            } ?? false
            let unsupported = catalog.map { !PainGuard.gymSupports($0, gym: gym) } ?? false
            guard blocked || unsupported else {
                kept.append(item)
                continue
            }
            // Swap for the first allowed option for the same movement that isn't already in the workout.
            let replacement = slot.flatMap { slot in
                planner.alternatives(for: slot).first { !taken.contains($0.id) }
            }
            guard let replacement else {
                skipped.append(item.name)
                continue
            }
            taken.insert(replacement.id)
            var swapped = item
            swapped.exerciseID = replacement.id
            swapped.name = replacement.name
            // A fixed weight was for the old exercise.
            swapped.weight = nil
            swapped.libraryLoad = nil
            kept.append(swapped)
            let why = blocked ? "it's on your never-again list or loads a sore area" : "your gym doesn't have the equipment"
            swapNotes[replacement.id] = "Swapped in for \(item.name): \(why)."
        }
        var planned = planner.prescribeWithoutWarmUps(template: kept, history: history)
        for index in planned.indices {
            let id = planned[index].exerciseID
            if let note = swapNotes[id] {
                planned[index].note = [note, planned[index].note].compactMap { $0 }.joined(separator: " ")
            }
            if let filter, let slot = ExerciseCatalog.slot(for: id) {
                filter.capLoad(&planned[index], slot: slot, gym: gym, history: history[id])
            }
        }
        addWarmUps(&planned)
        return CheckedTemplate(exercises: planned, skipped: skipped)
    }

    func prescribeWithoutWarmUps(template items: [TemplateItem], history: [String: ExerciseHistory]) -> [PlannedExercise] {
        items.map { item in
            let rpe = item.rpe ?? Self.defaultTemplateRPE
            let catalogKind = ExerciseCatalog.exercise(id: item.exerciseID)?.load
            let kind = catalogKind ?? (item.libraryLoad == .bodyweight ? nil : item.libraryLoad)
            var planned = PlannedExercise(
                exerciseID: item.exerciseID, name: item.name, sets: max(1, item.sets), reps: item.reps,
                rpe: rpe, load: nil, loadKind: kind, note: nil
            )
            // History behind a suggested load, for the "big jump" tip.
            var suggestedFrom: ExerciseHistory?
            var suggestedMode = ProgressionMode.load
            if let fixed = item.weight, fixed > 0 {
                // Rounded down to a weight this gym can load (unchanged when it can't say).
                planned.load = kind.flatMap { gym.load(atMost: fixed, on: $0) }.map { min($0, fixed) } ?? fixed
            } else if let past = history[item.exerciseID] {
                // The lift's progression rule (`ProgressionMode`) picks the weight; the
                // template's own sets and reps stay as you set them.
                let compound = ExerciseCatalog.slot(for: item.exerciseID)?.isCompound ?? false
                let mode = progressionMode(for: item.exerciseID, kind: kind, compound: compound, at: past.lastWeight)
                if let kind, let suggested = progression(history: past, reps: item.reps, rpe: rpe, kind: kind, mode: mode) {
                    planned.load = suggested.load
                    planned.targetReps = suggested.targetReps
                    suggestedFrom = past
                    suggestedMode = mode
                } else if past.lastWeight > 0 {
                    planned.load = past.lastWeight
                }
            } else if kind != nil {
                let left = Int((10 - rpe).rounded())
                planned.note = "First time: pick a weight you could lift about \(item.reps.upperBound + left) times, and do \(item.reps.upperBound)."
            }
            if let load = planned.load, let kind {
                if let suggestedFrom {
                    planned.note = notes(load: load, history: suggestedFrom, reps: item.reps, rpe: rpe, kind: kind, mode: suggestedMode)
                    planned.progressionNote = progressionNote(load: load, history: suggestedFrom, reps: item.reps,
                                                              mode: suggestedMode, rpe: rpe, loadKind: kind)
                } else {
                    planned.note = loadNote(load: load, kind: kind)
                }
            }
            return planned
        }
    }
}

// MARK: - Lift progress

/// Per-session bests for one exercise, with personal records marked.
public enum LiftProgress {
    public struct LoggedSet: Sendable, Equatable {
        public var weight: Double
        public var reps: Int
        public var rpe: Double?
        public init(weight: Double, reps: Int, rpe: Double? = nil) {
            self.weight = weight
            self.reps = reps
            self.rpe = rpe
        }
    }

    public struct LoggedSession: Sendable, Equatable {
        public var date: Date
        /// Completed working sets (no warm-ups).
        public var sets: [LoggedSet]
        public init(date: Date, sets: [LoggedSet]) {
            self.date = date
            self.sets = sets
        }
    }

    public struct Point: Sendable, Equatable, Identifiable {
        public var date: Date
        /// Estimated one-rep max of the best set (reps left counted from RPE).
        public var estimatedOneRepMax: Double
        public var bestWeight: Double
        public var bestReps: Int
        /// Sum of weight × reps over the working sets.
        public var volume: Double
        public var sets: Int
        /// Beat every earlier session's estimated 1RM.
        public var isPR: Bool
        public var id: Date { date }
    }

    public static func points(_ sessions: [LoggedSession]) -> [Point] {
        var best = 0.0
        var result: [Point] = []
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let sets = session.sets.filter { $0.reps > 0 }
            var top: LoggedSet?
            var e1RM = 0.0
            for set in sets {
                let estimate = OneRepMax.estimate(weight: set.weight, reps: set.reps, rpe: set.rpe)
                if top == nil || estimate > e1RM {
                    top = set
                    e1RM = estimate
                }
            }
            guard let top else { continue }
            let isPR = !result.isEmpty && e1RM > best + 0.01
            best = max(best, e1RM)
            var volume = 0.0
            for set in sets { volume += set.weight * Double(set.reps) }
            result.append(Point(date: session.date, estimatedOneRepMax: e1RM, bestWeight: top.weight,
                                bestReps: top.reps, volume: volume, sets: sets.count, isPR: isPR))
        }
        return result
    }
}

// MARK: - Cardio fitness

/// VO₂ max against people your age and sex, and whether it's still improving.
///
/// Higher cardiorespiratory fitness is linked with lower mortality with no
/// upper limit (Mandsager et al., JAMA Netw Open 2018). When VO₂ max stalls,
/// interval training raises it more than steady continuous training
/// (Milanović et al., Sports Med 2015); easy "zone 2" work builds base volume
/// but isn't the best way to raise VO₂ max (Storoschuk et al., Sports Med 2025).
public enum CardioFitness {
    public struct Result: Sendable, Equatable {
        /// The newest reading.
        public var latest: Double
        /// FRIEND registry median for your age and sex.
        public var median: Double
        public var label: String
        /// The FRIEND percentile band behind `label` (`VO2Norms`).
        public var category: VO2Norms.Category
        /// Change over about 8 weeks (recent 2 weeks vs 6-10 weeks earlier), if there's data for both.
        public var change: Double?
        public var isPlateau: Bool
        public var percentOfMedian: Double { latest / max(median, 1) * 100 }
    }

    /// Smallest change treated as real (watch estimates move by ~1 ml/kg/min).
    public static let meaningfulChange = 0.5

    public static func assess(_ points: [DayValue], age: Int, sex: BiologicalSex) -> Result? {
        let sorted = points.filter { $0.value > 10 }.sorted { $0.date < $1.date }
        guard let last = sorted.last else { return nil }
        let day = 86_400.0
        let recent = sorted.filter { $0.date >= last.date.addingTimeInterval(-14 * day) }.map(\.value)
        let earlier = sorted.filter {
            $0.date >= last.date.addingTimeInterval(-70 * day) && $0.date <= last.date.addingTimeInterval(-42 * day)
        }.map(\.value)
        // The headline is the newest reading, the same number Health shows;
        // the plateau check still compares 2-week means.
        let latest = last.value
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        var change: Double?
        if !earlier.isEmpty {
            change = recentMean - earlier.reduce(0, +) / Double(earlier.count)
        }
        let median = Biomarkers.medianVO2Max(age: age, sex: sex)
        return Result(
            latest: latest,
            median: median,
            label: Biomarkers.vo2MaxLabel(latest, age: age, sex: sex),
            category: VO2Norms.category(vo2: latest, age: age, sex: sex),
            change: change,
            isPlateau: change.map { $0 < meaningfulChange } ?? false
        )
    }
}

// MARK: - Strength days

/// Muscle-strengthening on 2 or more days a week (WHO guidelines, Bull et al.,
/// Br J Sports Med 2020). Strength training is linked with 10-17% lower
/// all-cause and cardiovascular mortality, most of the benefit coming by about
/// 30-60 minutes a week (Momma et al., Br J Sports Med 2022).
public enum StrengthDays {
    public static let weeklyTarget = 2

    /// Different days with a strength session in the last 7 days (today included).
    public static func lastSevenDays(_ sessionDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return 0 }
        return Set(sessionDates.filter { $0 >= start && $0 <= now }.map { calendar.startOfDay(for: $0) }).count
    }

    /// Strength days in each of the last `weeks` 7-day blocks, oldest first.
    public static func weekly(_ sessionDates: [Date], weeks: Int = 4, now: Date = .now, calendar: Calendar = .current) -> [Int] {
        (0..<weeks).reversed().map { back in
            let end = calendar.date(byAdding: .day, value: -7 * back, to: now) ?? now
            return lastSevenDays(sessionDates, now: end, calendar: calendar)
        }
    }
}
