import Foundation

// MARK: - Pain and niggle log (docs/research/lifting-features.md §3, Pick 5)
//
// Evidence, and how far it goes:
// - Strength training is the best-evidenced way to prevent sports injuries:
//   about two thirds fewer, dose-dependent. Lauersen JB, Andersen TE,
//   Andersen LB, Br J Sports Med 2018;52:1557-1563 (RR 0.34). So the aim is
//   to keep you lifting around a niggle, not to rest it outright.
// - Exercising into tolerable pain is not harmful and gives a small short-term
//   benefit in chronic musculoskeletal pain. Smith BE, Hendrick P, Smith TO et
//   al., Br J Sports Med 2017;51:1679-1687 (7 RCTs, SMD -0.27).
// - The "5 out of 10" line is the pain-monitoring model used in tendinopathy
//   rehab: a clinical convention, not a tested threshold for gym pain.
//   Silbernagel KG, Thomeé R, Eriksson BI, Karlsson J, Am J Sports Med
//   2007;35:897-906 (Achilles tendinopathy; continued activity with pain
//   kept at or under 5/10 and settling by the next morning).
// Everything else here (which lifts load which area, the regressions, the
// 20 % cap, the 7-day expiry) is coaching convention and the app's own
// choice, and the UI says so. The evidence doesn't differ by goal, so none
// of this branches on `Goals`. The app never diagnoses.

/// A body area that can hurt.
public enum PainArea: String, Codable, Sendable, CaseIterable, Identifiable {
    case shoulder, elbow, wrist, lowerBack, hip, knee, ankle, neck

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shoulder: "Shoulder"
        case .elbow: "Elbow"
        case .wrist: "Wrist"
        case .lowerBack: "Lower back"
        case .hip: "Hip"
        case .knee: "Knee"
        case .ankle: "Ankle"
        case .neck: "Neck"
        }
    }

    /// "your knee", "your lower back".
    public var possessive: String { "your " + title.lowercased() }
}

/// One answer to "Something hurts?": where, how much (0-10) and whether it
/// was worse after training. A 0 clears the area.
public struct PainReport: Codable, Sendable, Equatable, Identifiable {
    public var area: PainArea
    /// 0 = no pain, 10 = worst imaginable.
    public var level: Int
    /// Worse after (or during) training, or the next morning: a stop signal.
    public var worseAfterTraining: Bool?
    public var loggedAt: Date

    public var id: PainArea { area }

    public init(area: PainArea, level: Int, worseAfterTraining: Bool? = nil, loggedAt: Date) {
        self.area = area
        self.level = min(10, max(0, level))
        self.worseAfterTraining = worseAfterTraining
        self.loggedAt = loggedAt
    }
}

public enum PainGuard {
    /// What the trainer does for one area.
    public enum Response: Sendable, Equatable {
        /// 1-2/10: nothing changes; the rule is still shown.
        case unchanged
        /// 3-5/10: easier variant first and a lighter load.
        case regress
        /// 6+/10, or worse after training: lifts that load the area are left out.
        case avoid
    }

    // MARK: Thresholds

    /// Pain at or under 5/10 that settles by the next morning is the
    /// "acceptable" zone of the tendinopathy pain-monitoring model
    /// (Silbernagel et al. 2007; a clinical convention). Above it, the
    /// trainer leaves out lifts that load the area.
    public static let acceptablePainMax = 5
    /// From here up the trainer swaps in a regression and caps the load.
    /// App choice: 1-2/10 is treated as background noise.
    public static let regressFrom = 3
    /// Working-set loads are capped this much lighter on lifts that load a
    /// 3-5/10 area. App choice, not a tested number.
    public static let loadCapFraction = 0.8
    /// A pain report lasts this many days unless logged again. App choice.
    public static let expiryDays = 7
    /// "See a clinician if it lasts 2+ weeks". Common clinical advice, not a
    /// tested cut-off.
    public static let clinicianDays = 14

    public static func response(to report: PainReport) -> Response {
        // Pain that rises after training or by the next day is the model's
        // stop signal (Silbernagel et al. 2007).
        if report.level >= regressFrom, report.worseAfterTraining == true { return .avoid }
        if report.level > acceptablePainMax { return .avoid }
        if report.level >= regressFrom { return .regress }
        return .unchanged
    }

    // MARK: Expiry

    /// The latest report per area that is still current on `today`: logged in
    /// the last `expiryDays` calendar days and above 0. A later 0 clears an
    /// area. Sorted worst first.
    public static func active(_ reports: [PainReport], today: Date, calendar: Calendar = .current) -> [PainReport] {
        let start = calendar.startOfDay(for: today)
        guard let cutoff = calendar.date(byAdding: .day, value: -(expiryDays - 1), to: start) else { return [] }
        var latest: [PainArea: PainReport] = [:]
        for report in reports where report.loggedAt <= today.addingTimeInterval(60) {
            if let current = latest[report.area], current.loggedAt >= report.loggedAt { continue }
            latest[report.area] = report
        }
        return latest.values
            .filter { $0.level > 0 && calendar.startOfDay(for: $0.loggedAt) >= cutoff }
            .sorted { ($0.level, $1.area.rawValue) > ($1.level, $0.area.rawValue) }
    }

    /// Days the area has hurt without a clear (a 0) and without a gap longer
    /// than the expiry, up to today. Nil when it isn't hurting now.
    public static func daysHurting(_ area: PainArea, reports: [PainReport], today: Date, calendar: Calendar = .current) -> Int? {
        let mine = reports.filter { $0.area == area && $0.loggedAt <= today.addingTimeInterval(60) }.sorted { $0.loggedAt > $1.loggedAt }
        guard let newest = mine.first, active([newest], today: today, calendar: calendar).isEmpty == false else { return nil }
        var earliest = newest.loggedAt
        for report in mine.dropFirst() {
            guard report.level > 0 else { break }
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: report.loggedAt),
                                              to: calendar.startOfDay(for: earliest)).day ?? 0
            guard gap <= expiryDays else { break }
            earliest = report.loggedAt
        }
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: today)).day ?? 0) + 1
    }

    /// True when an area has hurt for `clinicianDays` or more.
    public static func seeClinician(_ area: PainArea, reports: [PainReport], today: Date, calendar: Calendar = .current) -> Bool {
        (daysHurting(area, reports: reports, today: today, calendar: calendar) ?? 0) >= clinicianDays
    }

    // MARK: What loads what

    /// Areas every exercise in a movement pattern loads. Coaching convention
    /// (which joints a pattern moves under load), not a measured map.
    public static func areas(for slot: MovementSlot) -> Set<PainArea> {
        switch slot {
        case .horizontalPress, .inclinePress, .chestFly: return [.shoulder]
        case .verticalPress: return [.shoulder, .neck]
        case .lateralRaise: return [.shoulder]
        case .triceps: return [.elbow]
        case .verticalPull: return [.shoulder, .elbow]
        case .horizontalRow: return []
        case .rearDelt: return []
        case .biceps, .hammerCurl: return [.elbow, .wrist]
        case .squat: return [.knee, .hip]
        case .hinge: return [.lowerBack, .hip]
        case .singleLeg: return [.knee, .hip, .ankle]
        case .legCurl: return [.knee]
        case .legExtension: return [.knee]
        case .calves: return [.ankle]
        case .core: return []
        case .hipThrust: return [.hip]
        }
    }

    /// Extra areas particular exercises load beyond their pattern: a bar on
    /// the back loads the lower back and neck, push-ups and straight bars the
    /// wrists, dips and overhead extensions the shoulder.
    static let extraAreas: [String: Set<PainArea>] = [
        "Barbell_Bench_Press_-_Medium_Grip": [.wrist],
        "Smith_Machine_Bench_Press": [.wrist],
        "Pushups": [.wrist],
        "Push-Ups_With_Feet_Elevated": [.wrist],
        "Barbell_Incline_Bench_Press_-_Medium_Grip": [.wrist],
        "Standing_Military_Press": [.lowerBack, .wrist],
        "Cable_Rope_Overhead_Triceps_Extension": [.shoulder],
        "Dumbbell_One-Arm_Triceps_Extension": [.shoulder],
        "EZ-Bar_Skullcrusher": [.wrist],
        "Dips_-_Triceps_Version": [.shoulder],
        "Bench_Dips": [.shoulder, .wrist],
        "Pullups": [.wrist],
        "Chin-Up": [.wrist],
        "Bent_Over_Barbell_Row": [.lowerBack],
        "Barbell_Curl": [.wrist],
        "Barbell_Squat": [.lowerBack, .neck, .ankle],
        "Box_Squat": [.lowerBack, .neck],
        "Dumbbell_Squat": [.lowerBack],
        "Goblet_Squat": [.ankle],
        "Barbell_Lunge": [.lowerBack, .neck],
        "Bodyweight_Walking_Lunge": [.ankle],
        "Standing_Calf_Raises": [.lowerBack],
        "Hanging_Leg_Raise": [.shoulder, .lowerBack],
        "Plank": [.lowerBack],
        "Floor_Press": [.wrist],
        // Core (`CoreMoves`). Repeated or loaded spine flexion and rollouts are
        // set aside for a sore lower back: McGill's caution (Strength Cond J
        // 2010). Whether flexion harms a healthy spine is disputed (Contreras
        // & Schoenfeld, Strength Cond J 2011), so this applies only to pain.
        // Crunches pull on the neck when done with hands behind the head.
        "Cable_Crunch": [.lowerBack],
        "Crunches": [.lowerBack, .neck],
        "Decline_Crunch": [.lowerBack, .neck],
        "Air_Bike": [.lowerBack, .neck],
        "Cable_Reverse_Crunch": [.lowerBack],
        "Reverse_Crunch": [.lowerBack],
        "Knee_Hip_Raise_On_Parallel_Bars": [.shoulder, .lowerBack],
        "Barbell_Ab_Rollout_-_On_Knees": [.lowerBack, .shoulder],
        "Dumbbell_Side_Bend": [.lowerBack],
        "Side_Bridge": [.shoulder],
    ]

    /// Every area an exercise loads: its pattern's plus its own extras.
    public static func areas(forExerciseID id: String, slot: MovementSlot) -> Set<PainArea> {
        areas(for: slot).union(extraAreas[id] ?? [])
    }

    // MARK: Regressions

    /// Easier variants per area and pattern, best first. Coaching convention:
    /// a shorter or supported range, a neutral grip, or less load on the
    /// spine. Only ones the gym supports are offered (trap-bar deadlifts are
    /// left out: the gym profile doesn't record a trap bar).
    public static let regressionTable: [Regression] = {
        typealias C = ExerciseCatalog
        typealias R = Regression
        return [
            // Shoulder: shorter range (floor press stops the elbows at the
            // floor) and a neutral grip; a lower angle than straight overhead.
            R(.shoulder, .horizontalPress, [
                C.ex("Dumbbell_Bench_Press_with_Neutral_Grip", "Neutral-Grip Dumbbell Press", .dumbbell, .bench),
                C.ex("Dumbbell_Floor_Press", "Dumbbell Floor Press", .dumbbell),
                C.ex("Floor_Press", "Floor Press", .barbell),
                C.ex("Leverage_Chest_Press", "Machine Chest Press", .machine),
            ]),
            R(.shoulder, .inclinePress, [
                C.ex("Hammer_Grip_Incline_DB_Bench_Press", "Neutral-Grip Incline Dumbbell Press", .dumbbell, .bench),
            ]),
            // Overhead: a machine's fixed, back-supported path. (The neutral-grip
            // incline press stays under incline press only: a regression has one
            // pattern, so swaps and muscle counts know what it replaces.)
            R(.shoulder, .verticalPress, [
                C.ex("Machine_Shoulder_Military_Press", "Machine Shoulder Press", .machine),
            ]),
            R(.shoulder, .verticalPull, [
                C.ex("Wide-Grip_Lat_Pulldown", "Lat Pulldown", .cable),
            ]),
            R(.shoulder, .lateralRaise, [
                C.ex("Cable_Seated_Lateral_Raise", "Cable Lateral Raise", .cable),
                C.ex("Lateral_Raise_-_With_Bands", "Band Lateral Raise", nil, .bands),
            ]),
            // Elbow: cable pushdowns over overhead work and skullcrushers.
            R(.elbow, .triceps, [
                C.ex("Triceps_Pushdown_-_Rope_Attachment", "Rope Pushdown", .cable),
            ]),
            R(.elbow, .verticalPull, [
                C.ex("Wide-Grip_Lat_Pulldown", "Lat Pulldown", .cable),
            ]),
            // Wrist: dumbbells or machines let the wrist sit where it's comfortable.
            R(.wrist, .horizontalPress, [
                C.ex("Dumbbell_Bench_Press_with_Neutral_Grip", "Neutral-Grip Dumbbell Press", .dumbbell, .bench),
                C.ex("Leverage_Chest_Press", "Machine Chest Press", .machine),
            ]),
            R(.wrist, .biceps, [
                C.ex("Dumbbell_Bicep_Curl", "Dumbbell Curl", .dumbbell),
                C.ex("Machine_Bicep_Curl", "Machine Curl", .machine),
            ]),
            R(.wrist, .triceps, [
                C.ex("Triceps_Pushdown_-_Rope_Attachment", "Rope Pushdown", .cable),
            ]),
            // Lower back: hip thrusts and pull-throughs for the hinge,
            // supported rows, and a leg press or goblet squat over a bar on the back.
            R(.lowerBack, .hinge, [
                C.ex("Barbell_Hip_Thrust", "Hip Thrust", .barbell, .bench),
                C.ex("Pull_Through", "Cable Pull-Through", .cable),
                C.ex("Barbell_Glute_Bridge", "Barbell Glute Bridge", .barbell),
                C.ex("Single_Leg_Glute_Bridge", "Single-Leg Glute Bridge", nil),
            ]),
            R(.lowerBack, .horizontalRow, [
                C.ex("Seated_Cable_Rows", "Seated Cable Row", .cable),
                C.ex("Leverage_Iso_Row", "Machine Row", .machine),
                C.ex("One-Arm_Dumbbell_Row", "One-Arm Dumbbell Row", .dumbbell, .bench),
            ]),
            R(.lowerBack, .squat, [
                C.ex("Leg_Press", "Leg Press", .machine),
                C.ex("Goblet_Squat", "Goblet Squat", .kettlebell),
            ]),
            // Core: a neutral spine that resists movement (McGill, Strength
            // Cond J 2010) over crunches, leg raises and rollouts.
            R(.lowerBack, .core, [
                C.ex("Dead_Bug", "Dead Bug", nil),
                C.ex("Pallof_Press", "Pallof Press", .cable),
            ]),
            // Knee: a box squat controls depth; the leg press lets you set the range.
            R(.knee, .squat, [
                C.ex("Box_Squat", "Box Squat", .barbell, .squatRack),
                C.ex("Leg_Press", "Leg Press", .machine),
            ]),
            R(.hip, .squat, [
                C.ex("Box_Squat", "Box Squat", .barbell, .squatRack),
            ]),
            R(.neck, .squat, [
                C.ex("Leg_Press", "Leg Press", .machine),
                C.ex("Goblet_Squat", "Goblet Squat", .kettlebell),
            ]),
            R(.neck, .verticalPress, [
                C.ex("Machine_Shoulder_Military_Press", "Machine Shoulder Press", .machine),
            ]),
        ]
    }()

    /// Easier variants for one area in one movement pattern.
    public struct Regression: Sendable {
        public var area: PainArea
        public var slot: MovementSlot
        public var exercises: [CatalogExercise]

        init(_ area: PainArea, _ slot: MovementSlot, _ exercises: [CatalogExercise]) {
            self.area = area
            self.slot = slot
            self.exercises = exercises
        }
    }

    /// Regressions for an area and pattern, best first (before the gym check).
    public static func regressions(for area: PainArea, slot: MovementSlot) -> [CatalogExercise] {
        regressionTable.filter { $0.area == area && $0.slot == slot }.flatMap(\.exercises)
    }

    /// The pattern a regression-only exercise (one not in `ExerciseCatalog`)
    /// belongs to, so swaps and muscle lists still work.
    public static func regressionSlot(for exerciseID: String) -> MovementSlot? {
        regressionTable.first { $0.exercises.contains { $0.id == exerciseID } }?.slot
    }

    public static func regressionExercise(id: String) -> CatalogExercise? {
        regressionTable.lazy.flatMap(\.exercises).first { $0.id == id }
    }

    /// Same test as `WorkoutPlanner.alternatives`: the gym has everything it
    /// needs and at least one load on what it's loaded with.
    static func gymSupports(_ exercise: CatalogExercise, gym: GymProfile) -> Bool {
        exercise.requires.allSatisfy { gym.has($0) } &&
            (exercise.load.map { !gym.achievableLoads(for: $0).isEmpty } ?? true)
    }

    // MARK: The rule, in plain words

    /// The pain-monitoring rule as the UI shows it.
    public static let ruleText = "Pain up to 5 out of 10 that settles by the next morning is OK to train through. Pain that climbs during a set, or is worse the next day, means stop that lift. If it lasts 2 weeks or more, see a clinician."
    /// The same rule in one line, for the trainer's row.
    public static let shortRuleText = "Up to 5/10 and settled by the next morning is OK. Stop a lift if pain climbs during the set or is worse the next day."
    /// Where the rule comes from, honestly.
    public static let sourceText = "The 5/10 line is the pain-monitoring model physios use in tendon rehab, a clinical convention rather than a tested gym rule. Lifting itself cuts injuries by about two thirds (Lauersen 2018), and training into mild pain isn't harmful (Smith 2017). Which lifts get swapped and the 20% lighter loads are the app's choices."
    public static func clinicianText(_ area: PainArea) -> String {
        "\(area.title) pain for 2 weeks or more: worth seeing a physio or doctor."
    }
}

// MARK: - Exercise filter for the planner

/// What the trainer must leave out or work around: "never again" exercises
/// and current pain. Pass it to `WorkoutPlanner.plan(exerciseFilter:)`, or
/// set `WorkoutPlanner.exerciseFilter` so swaps follow it too.
public struct ExerciseFilter: Sendable, Equatable {
    /// Exercise IDs never to plan or offer as a swap.
    public var neverAgain: Set<String>
    /// Current pain (`PainGuard.active`).
    public var pains: [PainReport]

    public init(neverAgain: Set<String> = [], pains: [PainReport] = []) {
        self.neverAgain = neverAgain
        self.pains = pains
    }

    /// From every report logged, keeping only those still current on `today`.
    public init(neverAgain: Set<String>, reports: [PainReport], today: Date, calendar: Calendar = .current) {
        self.init(neverAgain: neverAgain, pains: PainGuard.active(reports, today: today, calendar: calendar))
    }

    public var isEmpty: Bool { neverAgain.isEmpty && pains.allSatisfy { PainGuard.response(to: $0) == .unchanged } }

    public var avoidAreas: Set<PainArea> {
        Set(pains.filter { PainGuard.response(to: $0) == .avoid }.map(\.area))
    }

    /// Worst first.
    public var regressAreas: [PainArea] {
        pains.filter { PainGuard.response(to: $0) == .regress }.sorted { $0.level > $1.level }.map(\.area)
    }

    /// May this exercise be planned or offered at all?
    public func allows(_ exercise: CatalogExercise, slot: MovementSlot) -> Bool {
        !neverAgain.contains(exercise.id) &&
            PainGuard.areas(forExerciseID: exercise.id, slot: slot).isDisjoint(with: avoidAreas)
    }

    /// The gym's options for a slot, filtered and reordered: regressions for
    /// a 3-5/10 area first (only ones the gym supports; with two sore areas,
    /// those that load fewer of them first, so a box squat for the knee
    /// doesn't win over a leg press when the lower back hurts too), then the
    /// usual options; never-again exercises and anything loading a 6+/10
    /// area are removed.
    public func apply(to supported: [CatalogExercise], slot: MovementSlot, gym: GymProfile) -> [CatalogExercise] {
        let loaded = supported.reduce(into: PainGuard.areas(for: slot)) { areas, exercise in
            areas.formUnion(PainGuard.areas(forExerciseID: exercise.id, slot: slot))
        }
        let sore = Set(regressAreas)
        func soreCount(_ exercise: CatalogExercise) -> Int {
            PainGuard.areas(forExerciseID: exercise.id, slot: slot).intersection(sore).count
        }
        let preferred = regressAreas
            .filter { loaded.contains($0) }
            .flatMap { PainGuard.regressions(for: $0, slot: slot) }
            .filter { PainGuard.gymSupports($0, gym: gym) }
            .enumerated()
            .sorted { (soreCount($0.element), $0.offset) < (soreCount($1.element), $1.offset) }
            .map(\.element)
        var seen: Set<String> = []
        var result: [CatalogExercise] = []
        for exercise in preferred + supported where !seen.contains(exercise.id) && allows(exercise, slot: slot) {
            seen.insert(exercise.id)
            result.append(exercise)
        }
        return result
    }

    /// The worst 3-5/10 area this exercise loads, if any.
    public func regressArea(forExerciseID id: String, slot: MovementSlot) -> PainArea? {
        let loads = PainGuard.areas(forExerciseID: id, slot: slot)
        return regressAreas.first { loads.contains($0) }
    }

    /// Every 3-5/10 area this exercise loads, worst first.
    public func regressAreasLoaded(byExerciseID id: String, slot: MovementSlot) -> [PainArea] {
        let loads = PainGuard.areas(forExerciseID: id, slot: slot)
        return regressAreas.filter { loads.contains($0) }
    }

    /// Caps the working load at 80% of what you lifted before the pain
    /// (rounded down to a load the gym can make) on a lift that loads a
    /// 3-5/10 area, and says why. "Before the pain" is the larger of today's
    /// load and what your best estimated 1RM (`history`, which lighter capped
    /// sessions don't lower) allows for today's reps and effort, so the cap
    /// holds at about 80% session after session instead of cutting 20% off a
    /// load already built on capped sessions (80 → 60 → 45 → 35 kg); and it
    /// never goes under last session's weight when that session was clearly
    /// easier than today's effort (a capped day). Lifts
    /// with no load get the note only. The cap is kept on the exercise
    /// (`PlannedExercise.maxLoadKg`) so live autoregulation can't add it back.
    public func capLoad(_ exercise: inout PlannedExercise, slot: MovementSlot, gym: GymProfile,
                        history: ExerciseHistory? = nil) {
        let areas = regressAreasLoaded(byExerciseID: exercise.exerciseID, slot: slot)
        guard !areas.isEmpty else { return }
        let names = areas.map(\.possessive).joined(separator: " and ")
        let line: String
        if let load = exercise.load, let kind = exercise.loadKind, load > 0 {
            var reference = load
            if let history, history.bestEstimatedOneRepMax.isFinite, history.bestEstimatedOneRepMax > 0 {
                let reserve = max(0, 10 - exercise.rpe)
                let fresh = history.bestEstimatedOneRepMax / (1 + (Double(exercise.repsToday) + reserve) / 30)
                if fresh.isFinite { reference = max(reference, fresh) }
            }
            if var capped = gym.load(atMost: reference * PainGuard.loadCapFraction, on: kind),
               capped < reference - 0.001 {
                // Never under last session's weight when that was clearly easy (a capped day,
                // logged two or more points under today's effort): it must not shrink the next cap.
                if let history, history.lastWeight > 0, history.lastWeight.isFinite, let lastRPE = history.lastRPE,
                   lastRPE <= exercise.rpe - WorkoutPlanner.catchUpGap + 0.001,
                   let last = gym.load(atMost: min(load, history.lastWeight), on: kind), last > capped {
                    capped = last
                }
                if capped < load - 0.001 {
                    exercise.load = capped
                    // The progression line would contradict the cap.
                    exercise.progressionNote = nil
                }
                exercise.maxLoadKg = gym.unit.toKilograms(capped)
                line = "About 20% lighter than usual for \(names) (the app's choice). Stop the lift if pain goes above 5/10."
            } else {
                line = "Go easy for \(names): stop the lift if pain goes above 5/10."
            }
        } else {
            line = "Go easy for \(names): stop the lift if pain goes above 5/10."
        }
        if let note = exercise.note, !note.isEmpty {
            exercise.note = note + " " + line
        } else {
            exercise.note = line
        }
    }

    /// Caps every affected lift in a plan (`capLoad`, against `history`),
    /// redoes the ramp sets and the time estimate for the new loads, and
    /// adds one line to "Why this session".
    public func capLoads(_ workout: inout PlannedWorkout, planner: WorkoutPlanner,
                         history: [String: ExerciseHistory] = [:], warmUpMinutes: Int = 0) {
        for index in workout.exercises.indices {
            let id = workout.exercises[index].exerciseID
            guard let slot = ExerciseCatalog.slot(for: id) ?? PainGuard.regressionSlot(for: id) else { continue }
            capLoad(&workout.exercises[index], slot: slot, gym: planner.gym, history: history[id])
        }
        planner.addWarmUps(&workout.exercises, minutes: workout.minutes)
        if workout.estimatedMinutes != nil {
            workout.estimatedMinutes = WorkoutPlanner.estimatedMinutes(workout.exercises, style: planner.style,
                                                                       warmUpMinutes: warmUpMinutes)
        }
        if let line = rationaleLine {
            workout.rationale = workout.rationale.isEmpty ? line : workout.rationale + " " + line
        }
    }

    /// "Working around your knee (6/10): lifts that load it are left out."
    public var rationaleLine: String? {
        var parts: [String] = []
        let avoided = pains.filter { PainGuard.response(to: $0) == .avoid }
        if !avoided.isEmpty {
            let names = avoided.map { "\($0.area.title.lowercased()) (\($0.level)/10)" }.joined(separator: ", ")
            parts.append("Working around your \(names): lifts that load it are left out.")
        }
        let regressed = pains.filter { PainGuard.response(to: $0) == .regress }
        if !regressed.isEmpty {
            let names = regressed.map { "\($0.area.title.lowercased()) (\($0.level)/10)" }.joined(separator: ", ")
            parts.append("Easier variants and lighter loads for your \(names).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
