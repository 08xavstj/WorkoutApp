import Foundation

/// A body area the daily stretch routine covers.
public enum StretchArea: String, Codable, Sendable, CaseIterable, Identifiable {
    case calves, chest, lats, hipFlexors, hamstrings, glutes, adductors

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .calves: "Calves"
        case .chest: "Chest"
        case .lats: "Lats"
        case .hipFlexors: "Hip flexors"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .adductors: "Inner thighs"
        }
    }
}

/// One static stretch, done with no equipment.
public struct Stretch: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var area: StretchArea
    /// One side at a time: half the time each side.
    public var perSide: Bool
    /// How to do it, in one or two short sentences.
    public var cue: String

    /// The bundled photo's file name, without ".jpg".
    public var imageName: String { "stretch-\(id)" }
}

/// A short daily static-stretch routine, separate from the workouts.
///
/// What the evidence supports, and what it doesn't:
/// - **It improves flexibility.** Static stretching raised range of motion
///   with a large effect over weeks (Ingram LA, Tomkinson GR, d'Unienville
///   NMA, et al. Optimising the dose of static stretching to improve
///   flexibility: a systematic review, meta-analysis and multivariate
///   meta-regression. Sports Med 2025;55:597-617; 188 studies).
/// - **The weekly total is what counts.** Gains levelled off at about 10
///   minutes a week (Ingram 2025; its press release puts it at about 8
///   minutes a muscle a week), and time per week mattered where time per
///   session didn't, with 5 minutes a week per muscle as the useful floor
///   (Thomas E, Bianco A, Paoli A, Palma A. Int J Sports Med 2018;39:243-254).
///   How many days it's spread over, how hard you pull, age and sex didn't
///   change the result (Ingram 2025). So: 5 minutes a day, the weekly minutes
///   shared out by area.
/// - **Holds.** 30 seconds, twice (or once each side): 30 s was as good as
///   60 s (Bandy WD, Irion JM. Phys Ther 1994;74:845-850), and the ACSM asks
///   for 10-30 s holds adding up to 60 s per stretch, to the point of
///   tightness, not pain (Garber CE, et al. Med Sci Sports Exerc 2011;43:1334-1359).
/// - **Lifting counts too.** Strength training through a full range improved
///   range of motion about as much as stretching (Afonso J, et al. Healthcare
///   2021;9:427; Alizadeh S, et al. Sports Med 2023;53:707-722), so an area
///   you lifted through a long range this week needs less stretching and the
///   routine goes to the others. The size of that credit is the app's choice.
/// - **What it doesn't do.** Stretching doesn't speed recovery or reduce
///   next-day soreness (Afonso J, et al. Front Physiol 2021;12:677581),
///   prevent injuries in general or fix posture (Warneke K, et al. Practical
///   recommendations on stretching exercise: a Delphi consensus statement. J
///   Sport Health Sci 2025;14:101067). So the routine isn't chosen to "recover"
///   yesterday's muscles, and the app doesn't say it does.
/// - **Not right before lifting.** Long static holds (over 60 s a muscle)
///   lower strength for a while (Behm DG, et al. Appl Physiol Nutr Metab
///   2016;41:1-11), so the reminder isn't placed just before a planned session.
public enum Stretching {
    /// Minutes in one routine.
    public static let sessionMinutes = 5
    /// One hold (Bandy & Irion 1994; ACSM 2011: 10-30 s).
    public static let holdSeconds = 30
    /// Total per stretch in a session (ACSM 2011: 60 s).
    public static let secondsPerStretch = 60
    /// Seconds to get into the next position (not counted as stretching; app choice).
    public static let changeSeconds = 6
    /// Weekly minutes for an area with no focus areas picked: the floor where
    /// weekly time starts to matter (Thomas 2018).
    public static let weeklyMinutes = 5.0
    /// Weekly minutes for a focus area: about where gains level off (Ingram 2025).
    public static let focusWeeklyMinutes = 8.0
    /// Weekly minutes for the other areas once focus areas are picked (app
    /// choice: under Thomas's 5, so the focus areas can reach theirs in 35
    /// minutes a week).
    public static let otherWeeklyMinutes = 3.0
    /// Minutes of stretching one long-range lifting session stands in for,
    /// per area. App choice: the studies show similar range-of-motion gains
    /// from lifting and stretching, not a minute-for-minute rate.
    public static let liftCreditMinutes = 2.0
    /// The window the weekly minutes are counted over.
    public static let windowDays = 7

    // MARK: The stretches

    /// Two per area, so the position varies from day to day. In the order a
    /// session does them: standing, then kneeling, then on the floor. Each
    /// has a photo bundled with the app (`Stretch.imageName`), from the
    /// public-domain free-exercise-db, so they show without a connection.
    public static let catalog: [Stretch] = [
        Stretch(id: "calf-wall", name: "Wall calf stretch", area: .calves, perSide: true,
                cue: "Hands on a wall, one leg back with the heel down and the knee straight. Lean in until the calf is tight."),
        Stretch(id: "calf-bent-knee", name: "Bent-knee calf stretch", area: .calves, perSide: true,
                cue: "One foot a little in front of the other. Bend both knees and keep the back heel down: the stretch is low in the back calf."),
        Stretch(id: "chest-elbows-back", name: "Elbows-back chest stretch", area: .chest, perSide: false,
                cue: "Stand tall with both hands on your lower back, fingers down. Draw the elbows back toward each other until the chest opens."),
        Stretch(id: "chest-stick", name: "Stick chest stretch", area: .chest, perSide: false,
                cue: "Hold a broomstick or towel wider than your shoulders. Take it up and behind your head until the chest and front of the shoulders stretch."),
        Stretch(id: "lat-wall", name: "Wall lat stretch", area: .lats, perSide: true,
                cue: "Forearm on a wall or door frame above your head. Lean toward that arm and let the chest sink until the side of the back stretches."),
        Stretch(id: "lat-childs-pose", name: "Child's pose", area: .lats, perSide: false,
                cue: "Kneel, sit back on the heels and walk the hands forward on the floor. Let the chest sink. Skip it if your knees don't like it."),
        Stretch(id: "hip-half-kneeling", name: "Kneeling hip flexor stretch", area: .hipFlexors, perSide: true,
                cue: "One foot forward, the other leg stretched out behind with the knee down. Shift forward until the front of the back hip stretches."),
        Stretch(id: "hip-side-quad", name: "Side-lying quad stretch", area: .hipFlexors, perSide: true,
                cue: "On your side, bend the top knee and hold that foot behind you. Press the hip forward as you draw the foot back."),
        Stretch(id: "ham-seated", name: "Seated hamstring stretch", area: .hamstrings, perSide: true,
                cue: "Sit with one leg straight and the other foot against the thigh. Hinge forward from the hips and reach for the ankle."),
        Stretch(id: "ham-lying", name: "Lying hamstring stretch", area: .hamstrings, perSide: true,
                cue: "On your back with one foot on the floor, hold the other thigh and straighten that knee toward the ceiling."),
        Stretch(id: "glute-figure-four", name: "Figure-four stretch", area: .glutes, perSide: true,
                cue: "On your back, cross one ankle over the other knee and pull both legs in until the outer hip stretches."),
        Stretch(id: "glute-knee-across", name: "Knee across the body", area: .glutes, perSide: true,
                cue: "On your back with one leg straight, bring the other knee across your body and hold it down with the opposite hand. Shoulders stay on the floor."),
        Stretch(id: "adductor-butterfly", name: "Butterfly stretch", area: .adductors, perSide: false,
                cue: "Sit with the soles together and the knees out. Sit tall and let the knees drop; lean forward a little for more."),
        Stretch(id: "adductor-straddle", name: "Seated straddle stretch", area: .adductors, perSide: false,
                cue: "Sit with the legs in a wide V. Hands on the floor, lean forward from the hips until the inner thighs stretch."),
    ]

    public static func stretches(for area: StretchArea) -> [Stretch] {
        catalog.filter { $0.area == area }
    }

    // MARK: Inputs

    /// Stretching logged for one area in one session.
    public struct Done: Codable, Sendable, Equatable {
        public var date: Date
        public var area: StretchArea
        public var seconds: Int

        public init(date: Date, area: StretchArea, seconds: Int) {
            self.date = date
            self.area = area
            self.seconds = seconds
        }
    }

    /// A lifting session and the areas it took through a long range (`areas(for:)`).
    public struct Lift: Sendable, Equatable {
        public var date: Date
        public var areas: Set<StretchArea>

        public init(date: Date, areas: Set<StretchArea>) {
            self.date = date
            self.areas = areas
        }
    }

    /// Areas a lift takes through a long range of motion, so it stands in for
    /// some stretching (Afonso 2021; Alizadeh 2023). Which lifts count is the
    /// app's reading: a Romanian deadlift for the hamstrings, a deep squat for
    /// the glutes and inner thighs, a split squat for the back leg's hip
    /// flexors, presses and flyes for the chest, pulldowns for the lats, calf
    /// raises for the calves.
    public static func areas(for slot: MovementSlot) -> Set<StretchArea> {
        switch slot {
        case .hinge: [.hamstrings]
        case .squat: [.glutes, .adductors]
        case .singleLeg: [.hipFlexors, .glutes]
        case .horizontalPress, .inclinePress, .chestFly: [.chest]
        case .verticalPull: [.lats]
        case .calves: [.calves]
        default: []
        }
    }

    /// The same for a session's exercises (catalog exercises only).
    public static func areas(forExerciseIDs ids: [String]) -> Set<StretchArea> {
        ids.reduce(into: Set<StretchArea>()) { result, id in
            if let slot = ExerciseCatalog.slot(for: id) { result.formUnion(areas(for: slot)) }
        }
    }

    // MARK: The week

    /// Minutes an area should get this week (`focusWeeklyMinutes` and friends).
    public static func target(for area: StretchArea, focus: Set<StretchArea>) -> Double {
        if focus.isEmpty { return weeklyMinutes }
        return focus.contains(area) ? focusWeeklyMinutes : otherWeeklyMinutes
    }

    /// One area's last 7 days.
    public struct AreaWeek: Sendable, Equatable, Identifiable {
        public var area: StretchArea
        public var target: Double
        /// Minutes stretched.
        public var stretched: Double
        /// Minutes credited for long-range lifting (at most half the target).
        public var lifted: Double
        public var lastStretched: Date?

        public var id: StretchArea { area }
        public var covered: Double { stretched + lifted }
        public var remaining: Double { max(0, target - covered) }
    }

    public static func week(done: [Done], lifts: [Lift], focus: Set<StretchArea>, now: Date = .now,
                            calendar: Calendar = .current) -> [AreaWeek] {
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        return StretchArea.allCases.map { area in
            let target = target(for: area, focus: focus)
            let mine = done.filter { $0.area == area && $0.date <= now }
            let stretched = Double(mine.filter { $0.date >= start }.reduce(0) { $0 + $1.seconds }) / 60
            let sessions = lifts.filter { $0.date >= start && $0.date <= now && $0.areas.contains(area) }.count
            let lifted = min(target / 2, Double(sessions) * liftCreditMinutes)
            return AreaWeek(area: area, target: target, stretched: stretched, lifted: lifted, lastStretched: mine.map(\.date).max())
        }
    }

    /// Minutes stretched in the last 7 days against the weekly plan
    /// (`sessionMinutes` a day).
    public static func weekMinutes(done: [Done], now: Date = .now, calendar: Calendar = .current) -> (done: Int, goal: Int) {
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        let seconds = done.filter { $0.date >= start && $0.date <= now }.reduce(0) { $0 + $1.seconds }
        return (Int((Double(seconds) / 60).rounded()), sessionMinutes * windowDays)
    }

    public static func stretchedToday(_ done: [Done], now: Date = .now, calendar: Calendar = .current) -> Bool {
        done.contains { calendar.isDate($0.date, inSameDayAs: now) }
    }

    // MARK: Today's routine

    public struct Item: Sendable, Equatable, Identifiable {
        public var stretch: Stretch
        /// Total seconds (both sides together for a one-sided stretch).
        public var seconds: Int

        public var id: String { stretch.id }
    }

    public struct Routine: Sendable, Equatable {
        public var items: [Item]
        /// Areas left out today because lifting covered them this week.
        public var coveredByLifting: [StretchArea]
        /// One or two sentences on why these.
        public var reason: String

        public var minutes: Int { Int((Double(items.reduce(0) { $0 + $1.seconds }) / 60).rounded()) }
    }

    /// Today's routine: one stretch each for the areas furthest behind their
    /// weekly minutes (the longest unstretched first on a tie), as many as fit
    /// in `sessionMinutes`. Each area alternates between its two stretches.
    public static func routine(done: [Done], lifts: [Lift], focus: Set<StretchArea>, now: Date = .now,
                               calendar: Calendar = .current) -> Routine {
        let week = week(done: done, lifts: lifts, focus: focus, now: now, calendar: calendar)
        let count = min(StretchArea.allCases.count, sessionMinutes * 60 / secondsPerStretch)
        let order = Dictionary(uniqueKeysWithValues: StretchArea.allCases.enumerated().map { ($1, $0) })
        let ranked = week.sorted { a, b in
            if abs(a.remaining - b.remaining) > 0.01 { return a.remaining > b.remaining }
            let lastA = a.lastStretched ?? .distantPast
            let lastB = b.lastStretched ?? .distantPast
            if lastA != lastB { return lastA < lastB }
            return (order[a.area] ?? 0) < (order[b.area] ?? 0)
        }
        let picked = ranked.prefix(count)
        let left = ranked.dropFirst(count)
        // Done in catalog order (standing, kneeling, floor), each area on its next variation.
        let items = picked.sorted { (order[$0.area] ?? 0) < (order[$1.area] ?? 0) }.compactMap { entry -> Item? in
            let options = stretches(for: entry.area)
            guard !options.isEmpty else { return nil }
            let sessions = Set(done.filter { $0.area == entry.area }.map { calendar.startOfDay(for: $0.date) }).count
            return Item(stretch: options[sessions % options.count], seconds: secondsPerStretch)
        }
        let covered = left.filter { $0.lifted > 0 }.map(\.area)
        return Routine(items: items, coveredByLifting: covered,
                       reason: reason(picked: picked.map(\.area), covered: covered, focus: focus))
    }

    static func reason(picked: [StretchArea], covered: [StretchArea], focus: Set<StretchArea>) -> String {
        var text = "The areas furthest behind their minutes for the week"
        if !focus.isEmpty, picked.contains(where: focus.contains) { text += ", your focus areas first" }
        text += "."
        if !covered.isEmpty {
            let names = AdaptiveWeek.list(covered.map { $0.name.lowercased() })
            text += " Left out today: \(names). You lifted \(covered.count == 1 ? "it" : "them") through a long range this week, which builds flexibility much as stretching does."
        }
        return text
    }

    // MARK: How it feels (progress)

    /// How a stretch felt at its end position. Most of the range gained in
    /// the first weeks comes from tolerating the stretch better, so the same
    /// position feeling easier is the progress (Weppler CH, Magnusson SP.
    /// Increasing muscle extensibility: a matter of increasing length or
    /// modifying sensation? Phys Ther 2010;90:438-449). It's a self-rating:
    /// useful for your own trend, not a measurement. The four steps are the
    /// app's choice.
    public enum Feel: Int, Codable, Sendable, CaseIterable, Identifiable {
        case veryTight = 1, tight, aLittleTight, easy

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .veryTight: "Very tight"
            case .tight: "Tight"
            case .aLittleTight: "A little tight"
            case .easy: "Easy"
            }
        }

        /// The step nearest an average.
        static func nearest(_ value: Double) -> Feel {
            Feel(rawValue: min(4, max(1, Int(value.rounded())))) ?? .tight
        }
    }

    public struct FeelEntry: Codable, Sendable, Equatable {
        public var date: Date
        public var area: StretchArea
        public var feel: Feel

        public init(date: Date, area: StretchArea, feel: Feel) {
            self.date = date
            self.area = area
            self.feel = feel
        }
    }

    /// Ratings an area needs, over at least `progressDays`, before a trend is shown (app choice).
    public static let progressRatings = 4
    public static let progressDays = 14

    /// One area's trend: its first three ratings against its last three.
    public struct AreaProgress: Sendable, Equatable, Identifiable {
        public var area: StretchArea
        public var first: Double
        public var latest: Double
        public var since: Date
        public var ratings: Int

        public var id: StretchArea { area }
        /// Positive = feels easier.
        public var change: Double { latest - first }

        /// "Tight → A little tight" or "Steady at Tight".
        public var text: String {
            let from = Feel.nearest(first)
            let to = Feel.nearest(latest)
            return from == to ? "Steady at \(to.title.lowercased())" : "\(from.title) → \(to.title.lowercased())"
        }
    }

    /// Trends for the areas with enough ratings (`progressRatings` over `progressDays`).
    public static func progress(_ entries: [FeelEntry], calendar: Calendar = .current) -> [AreaProgress] {
        StretchArea.allCases.compactMap { area in
            let mine = entries.filter { $0.area == area }.sorted { $0.date < $1.date }
            guard mine.count >= progressRatings, let first = mine.first, let last = mine.last,
                  (calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0) >= progressDays else { return nil }
            func mean(_ slice: ArraySlice<FeelEntry>) -> Double {
                Double(slice.reduce(0) { $0 + $1.feel.rawValue }) / Double(max(1, slice.count))
            }
            let window = min(3, mine.count / 2)
            return AreaProgress(area: area, first: mean(mine.prefix(window)), latest: mean(mine.suffix(window)),
                                since: first.date, ratings: mine.count)
        }
    }

    // MARK: Reach check

    /// How far the fingertips reach in a standing toe touch with the knees
    /// straight. Toe-touch and sit-and-reach tests track hamstring
    /// flexibility moderately well (Mayorga-Vega D, Merino-Marban R, Viciana
    /// J. J Sports Sci Med 2014;13:1-14, meta-analysis; cited from memory),
    /// so it's a rough marker for your own trend.
    public enum ToeTouch: Int, Codable, Sendable, CaseIterable, Identifiable {
        case knees = 1, shins, ankles, toes, floor, palms

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .knees: "Knees"
            case .shins: "Shins"
            case .ankles: "Ankles"
            case .toes: "Toes"
            case .floor: "Fingertips on the floor"
            case .palms: "Palms flat"
            }
        }
    }

    /// One reach check: the toe touch, and the knee-to-wall distance for the
    /// ankles and calves (big toe to the wall with the knee touching it and
    /// the heel down; a reliable field test: Bennell KL, et al. Aust J
    /// Physiother 1998;44:175-180, cited from memory).
    public struct ReachCheck: Codable, Sendable, Equatable {
        public var date: Date
        public var toeTouch: ToeTouch?
        public var kneeToWallCm: Double?

        public init(date: Date, toeTouch: ToeTouch?, kneeToWallCm: Double?) {
            self.date = date
            self.toeTouch = toeTouch
            self.kneeToWallCm = kneeToWallCm
        }
    }

    /// Days between reach checks: range changes over weeks, not days (app choice).
    public static let reachCheckDays = 28

    public static func reachCheckDue(_ checks: [ReachCheck], now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let last = checks.map(\.date).max() else { return true }
        return (calendar.dateComponents([.day], from: last, to: now).day ?? 0) >= reachCheckDays
    }

    /// "Toe touch: shins → toes" and "Knee to wall: 8 → 10 cm", first check
    /// against the latest; one check shows just its values.
    public static func reachSummary(_ checks: [ReachCheck]) -> [String] {
        let sorted = checks.sorted { $0.date < $1.date }
        var lines: [String] = []
        let touches = sorted.compactMap(\.toeTouch)
        if let first = touches.first, let last = touches.last {
            lines.append(touches.count > 1 && first != last
                         ? "Toe touch: \(first.title.lowercased()) → \(last.title.lowercased())"
                         : "Toe touch: \(last.title.lowercased())")
        }
        let walls = sorted.compactMap(\.kneeToWallCm)
        if let first = walls.first, let last = walls.last {
            func cm(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
            lines.append(walls.count > 1 && abs(first - last) >= 0.5
                         ? "Knee to wall: \(cm(first)) → \(cm(last)) cm"
                         : "Knee to wall: \(cm(last)) cm")
        }
        return lines
    }

    // MARK: The session's timer

    /// One timed step of a session.
    public struct Step: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable { case change, hold }
        public var id: Int
        public var kind: Kind
        /// Index into the routine's items.
        public var item: Int
        /// "Left side", "Right side", "Hold", "Once more"; "Get into position" for a change.
        public var label: String
        public var seconds: Int
    }

    /// The routine as timed steps: a short change of position, then two
    /// `holdSeconds` holds (one each side for a one-sided stretch).
    public static func steps(for routine: Routine) -> [Step] {
        var steps: [Step] = []
        for (index, item) in routine.items.enumerated() {
            let holds = max(1, item.seconds / holdSeconds)
            steps.append(Step(id: steps.count, kind: .change, item: index, label: "Get into position", seconds: changeSeconds))
            for hold in 0..<holds {
                let label: String
                if item.stretch.perSide {
                    label = hold % 2 == 0 ? "Left side" : "Right side"
                } else {
                    label = hold == 0 ? "Hold" : "Once more"
                }
                steps.append(Step(id: steps.count, kind: .hold, item: index, label: label, seconds: holdSeconds))
            }
        }
        return steps
    }

    /// What to log for a finished (or part-finished) session: the seconds
    /// held for each area.
    public static func log(routine: Routine, completedHolds: [Int: Int], at date: Date) -> [Done] {
        routine.items.enumerated().compactMap { index, item in
            let seconds = (completedHolds[index] ?? 0) * holdSeconds
            return seconds > 0 ? Done(date: date, area: item.stretch.area, seconds: seconds) : nil
        }
    }

    // MARK: The reminder

    /// The reminder's default time: 20:30, away from most training (app
    /// choice; muscles stretch a little further warm: ACSM 2011).
    public static let defaultReminderMinutes = 20 * 60 + 30
    /// The reminder moves if it falls this close before a planned session (`reminderMinutes`).
    public static let clearBeforeSessionMinutes = 90

    /// Minutes after midnight for today's reminder: the chosen time, unless a
    /// planned session starts within `clearBeforeSessionMinutes` after it;
    /// then an hour after that session's planned end (Behm 2016: long static
    /// holds just before lifting lower strength for a while).
    public static func reminderMinutes(preferred: Int, sessionStart: Int?, sessionLength: Int?) -> Int {
        guard let start = sessionStart, preferred <= start, start - preferred < clearBeforeSessionMinutes else { return preferred }
        return min(23 * 60, start + (sessionLength ?? 60) + 60)
    }

    /// Short, honest lines for the UI.
    public static let evidence: [String] = [
        "Static stretching improves flexibility; gains level off at about 8-10 minutes a week per area (Ingram et al., Sports Med 2025, 188 studies).",
        "The weekly total matters more than how it's split up or how hard you pull (Ingram 2025; Thomas et al., Int J Sports Med 2018).",
        "30-second holds work as well as 60 (Bandy & Irion, Phys Ther 1994); stretch to tightness, not pain (ACSM 2011).",
        "Lifting through a full range builds flexibility about as well as stretching (Afonso et al., Healthcare 2021), so areas you lifted that way need less.",
        "Stretching doesn't speed recovery, reduce soreness, prevent injuries in general or fix posture (Afonso et al., Front Physiol 2021; Warneke et al., J Sport Health Sci 2025, expert consensus).",
        "Early progress is mostly the same position feeling easier, before the range itself grows (Weppler & Magnusson, Phys Ther 2010), so the app tracks how each stretch feels.",
    ]
}
