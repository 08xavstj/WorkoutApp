import Foundation

/// A busy week, chosen in advance: one or two short sessions, each main lift
/// for one or two hard sets at the usual weight. It holds strength and muscle;
/// it does not build them. The same idea as `RestartPlan`'s lighter week, but
/// planned before the week instead of after a lapse.
///
/// Evidence (moderate: small studies, and no trial of a "busy week" button):
/// - After 16 weeks of training three days a week, a third or a ninth of the
///   weekly dose kept muscle size for 32 weeks in adults aged 20-35; neither
///   kept it in adults aged 60-75, who "require a higher dose" (Bickel CS,
///   Cross JM, Bamman MM. Exercise dosing to retain resistance training
///   adaptations in young and older adults. Med Sci Sports Exerc
///   2011;43(7):1177-1187; abstract read 2026-11-17).
/// - Strength and size can be held for up to 32 weeks on one session a week
///   and one set per exercise as long as the load is kept; older adults may
///   need two sessions and two or three sets (Spiering BA, Mujika I, Sharp
///   MA, Foulis SA. Maintaining physical performance: the minimal dose of
///   exercise needed to preserve endurance and strength over time. J Strength
///   Cond Res 2021;35(5):1449-1458; narrative review; abstract read 2026-11-17).
/// - One set of 6-12 reps at about 70-85% of 1RM, taken close to failure, two
///   or three times a week, still raised squat and bench 1RM in trained men
///   over 8-12 weeks (Androulakis-Korakakis P, Fisher JP, Steele J. Sports Med
///   2020;50(4):751-765; 6 studies; abstract read 2026-11-17).
/// - Ten weeks off after ten of training cost nothing by the end (Halonen EJ
///   et al., Scand J Med Sci Sports 2024;34(10):e14739; n = 42; not
///   re-verified here), so one week at a low dose is safe either way.
///
/// What the app chose inside that evidence: two sets per lift (one when the
/// time is short), the multi-joint lifts as "main lifts", full-body sessions so
/// one or two of them reach every main lift, 30 minutes, and effort no easier
/// than two reps in reserve. It lasts one week: each week is planned on its
/// own, so the next one starts from the standing plan again, and after
/// `reviewAfterWeeks` in a row the weekly review asks whether to build again.
public struct BusyWeek: Codable, Sendable, Equatable {
    /// Sessions this week: one or two.
    public var sessions: Int
    /// The week's days as they stood before it became a busy week, Monday
    /// first: what the next week is made from.
    public var standingDays: [PlannedDay]
    /// The standing quota of a flexible week.
    public var standingSessionsPerWeek: Int?
    /// The standing cardio: a busy week plans none.
    public var standingCardio: EasyCardio?
    /// The standing week's rotation, if it had been moved round.
    public var standingRotation: WeeklyPlan.Rotation?

    public init(sessions: Int, standingDays: [PlannedDay], standingSessionsPerWeek: Int? = nil,
                standingCardio: EasyCardio? = nil, standingRotation: WeeklyPlan.Rotation? = nil) {
        self.sessions = max(Self.sessionRange.lowerBound, min(Self.sessionRange.upperBound, sessions))
        self.standingDays = standingDays
        self.standingSessionsPerWeek = standingSessionsPerWeek
        self.standingCardio = standingCardio
        self.standingRotation = standingRotation
    }

    // MARK: Constants

    /// One or two sessions: one a week held strength and size in the studies
    /// Spiering 2021 reviews; two is closer to Bickel 2011's one-third dose.
    public static let sessionRange = 1...2
    /// Two sessions unless chosen otherwise: nearer "a third of the usual sets".
    public static let defaultSessions = 2
    /// About a third of the usual weekly sets (Bickel 2011's higher holding dose).
    public static let setFraction = 1.0 / 3
    /// `setFraction` as a block week's set multiplier (`TrainingBlock.WeekState`).
    public static let setMultiplier = 0.33
    /// Hard sets per main lift, and the fewest when the time is short: "one or
    /// two" (one set per exercise held strength, Spiering 2021; a single hard
    /// set still built 1RM, Androulakis-Korakakis 2020). App's choice within that.
    public static let setsPerLift = 2
    public static let minimumSetsPerLift = 1
    /// Effort: no easier than two reps in reserve. The single-set studies
    /// trained to or near failure (Androulakis-Korakakis 2020); the app stops
    /// a little short of it, as every block week does. App's choice.
    public static let maximumRIR = 2
    /// Session length, and the short version's. App's choice: four main lifts
    /// for two sets with their ramp sets come to about half an hour.
    public static let sessionMinutes = 30
    public static let shortMinutes = 15
    /// The time the planner is asked for before the session is cut down, so
    /// its own trimming for short sessions doesn't drop a main lift first.
    public static let planningMinutes = 60
    /// Most main lifts in one busy session. App's choice.
    public static let maximumLifts = 5
    /// Busy weeks in a row after which the weekly review asks whether to
    /// build again. App's choice: the studies held for months, but a mode
    /// that holds should not quietly become the plan.
    public static let reviewAfterWeeks = 3
    /// From this age one session a week may not hold muscle size (Bickel 2011:
    /// neither dose kept it at 60-75), so two are suggested.
    public static let olderAdultAge = 60

    // MARK: Words

    /// Said wherever the choice is offered.
    public static let headline = "Holds what you have; does not build."
    /// The week's line in the training block (`TrainingBlock.WeekState.note`).
    public static let blockNote = "Busy week: each main lift for one or two hard sets at your usual weights. Holds what you have; does not build."

    /// What the choice does, for the plan editor.
    public static func summary(sessions: Int) -> String {
        let count = sessions == 1 ? "One short session" : "Two short sessions"
        return "\(count) of about \(sessionMinutes) minutes: each main lift for one or two hard sets at your usual weights, about a third of your usual sets. \(headline) Next week goes back to your normal plan by itself."
    }

    /// Why it is enough, and where the evidence stops. `age` adds the caution
    /// for adults of 60 and over.
    public static func evidence(age: Int? = nil) -> String {
        var text = "A third of the usual sets, and even a ninth, kept muscle size for 32 weeks in adults aged 20-35 (Bickel 2011), and one session a week with one set per lift held strength when the weight stayed the same (Spiering 2021, a review). These are small studies; the weight on the bar is the part to keep."
        if let age, age >= olderAdultAge {
            text += " Neither dose kept muscle size in adults aged 60-75, so two sessions suit you better than one, and not for many weeks."
        }
        return text
    }

    // MARK: The plan

    /// `plan` as a busy week with `sessions` sessions (one or two): full-body
    /// holding sessions on days taken from the standing week (the first and
    /// the last for two, a middle one for one), at their usual times. The
    /// mode stays, a flexible week asks for that many on any days, cardio is
    /// left out, and the standing week is kept on `WeeklyPlan.busy` for
    /// `restored`. Works on a week that is already busy (to change the count).
    public static func plan(from plan: WeeklyPlan, sessions: Int) -> WeeklyPlan {
        let standing = restored(plan)
        let count = max(sessionRange.lowerBound, min(sessionRange.upperBound, sessions))
        let days = standing.sortedDays
        var picked: [PlannedDay]
        if days.isEmpty {
            picked = WeeklyPlan.suggestedWeekdays(count: count).map {
                PlannedDay(weekday: $0, time: 18 * 60, focus: .fullBody, minutes: sessionMinutes)
            }
        } else if count >= 2, days.count >= 2 {
            picked = [days[0], days[days.count - 1]]
        } else {
            picked = [days[days.count / 2]]
        }
        for index in picked.indices {
            picked[index].focus = .fullBody
            picked[index].minutes = sessionMinutes
            picked[index].shortVersionMinutes = shortMinutes
        }
        var result = standing
        result.plannedDays = picked
        result.sessionsPerWeek = standing.isFlexible ? picked.count : nil
        result.cardio = nil
        result.rotation = nil
        result.busy = BusyWeek(sessions: picked.count, standingDays: days,
                               standingSessionsPerWeek: standing.sessionsPerWeek,
                               standingCardio: standing.cardio, standingRotation: standing.rotation)
        return result
    }

    /// The week as it stood before it became a busy week; a normal week unchanged.
    public static func restored(_ plan: WeeklyPlan) -> WeeklyPlan {
        guard let busy = plan.busy else { return plan }
        var result = plan
        result.plannedDays = busy.standingDays
        result.sessionsPerWeek = busy.standingSessionsPerWeek
        result.cardio = busy.standingCardio
        result.rotation = busy.standingRotation
        result.busy = nil
        return result
    }

    // MARK: Weeks in a row

    /// Busy weeks in a row ending with the week before `weekStart`.
    public static func weeksInARow(plans: [WeeklyPlan], before weekStart: Date, calendar: Calendar = .current) -> Int {
        var count = 0
        var cursor = calendar.date(byAdding: .day, value: -7, to: weekStart)
        while let week = cursor,
              let plan = plans.first(where: { calendar.isDate($0.weekStart, inSameDayAs: week) }), plan.busy != nil {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -7, to: week)
        }
        return count
    }

    /// The weekly review's question after `reviewAfterWeeks` busy weeks in a
    /// row; nil before that. What to do next, never what was missed.
    public static func reviewQuestion(plans: [WeeklyPlan], thisWeek: Date, calendar: Calendar = .current) -> String? {
        let weeks = weeksInARow(plans: plans, before: thisWeek, calendar: calendar)
        guard weeks >= reviewAfterWeeks else { return nil }
        let words = ["Three", "Four", "Five", "Six"]
        let count = weeks - 3 < words.count ? words[weeks - 3] : "\(weeks)"
        return "\(count) busy weeks in a row have held what you have. Build again this week?"
    }

    /// The last training day as the restart and "first session back" rules
    /// should see it: a planned busy week counts as seen through its last
    /// day (up to today), so its planned gap never reads as time away and
    /// the seven days are counted from the end of it.
    public static func lastSeen(lastTrained: Date?, plans: [WeeklyPlan], now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let busyEnds = plans.filter(\.isBusy).compactMap { plan -> Date? in
            let start = calendar.startOfDay(for: plan.weekStart)
            guard start <= today, let sunday = calendar.date(byAdding: .day, value: 6, to: start) else { return nil }
            return min(sunday, today)
        }
        let candidates = busyEnds + (lastTrained.map { [calendar.startOfDay(for: $0)] } ?? [])
        return candidates.max()
    }

    // MARK: Sets

    /// A muscle's weekly sets in a busy week: about a third of its usual
    /// target, at least two (one lift for two sets).
    public static func weeklySets(usual: Int) -> Int {
        max(setsPerLift, Int((Double(max(0, usual)) * setFraction).rounded()))
    }

    // MARK: The session

    /// A planned session cut down to a busy week's holding session: the main
    /// (multi-joint) lifts only, `setsPerLift` hard sets each at the weights
    /// the planner chose (its exercises are ones the gym supports at loads it
    /// can make, and nothing here changes either), one set each when two
    /// would run past `minutes`. Supersets and time-saving sets are undone:
    /// with one or two sets there is nothing to save. A session with no
    /// multi-joint lift (a gym without them) keeps its lifts at the same sets.
    /// - Parameters:
    ///   - workout: the planner's session, ideally asked for `planningMinutes`.
    ///   - minutes: the time the user picked.
    ///   - planner: for the ramp sets and the time estimate.
    public static func session(from workout: PlannedWorkout, minutes: Int, planner: WorkoutPlanner,
                               warmUpMinutes: Int = 0) -> PlannedWorkout {
        guard !workout.exercises.isEmpty else { return workout }
        let main = workout.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == true }
        let kept = Array((main.isEmpty ? workout.exercises : main).prefix(maximumLifts))
        func build(sets: Int) -> (exercises: [PlannedExercise], estimate: Int) {
            var list = kept.map { exercise -> PlannedExercise in
                var copy = exercise
                copy.sets = sets
                copy.supersetGroup = nil
                copy.lastSetKind = nil
                copy.stages = nil
                copy.isFinisher = nil
                return copy
            }
            planner.addWarmUps(&list, minutes: minutes)
            return (list, WorkoutPlanner.estimatedMinutes(list, style: planner.style, warmUpMinutes: warmUpMinutes))
        }
        var built = build(sets: setsPerLift)
        // The same 10% the planner allows before it calls a plan too long (`lengthNote`).
        if Double(built.estimate) > Double(max(1, minutes)) * 1.1 + 0.5 {
            built = build(sets: minimumSetsPerLift)
        }
        var result = workout
        result.exercises = built.exercises
        result.minutes = minutes
        result.estimatedMinutes = built.estimate
        let sets = built.exercises.first?.sets ?? setsPerLift
        let lifts = built.exercises.count == 1 ? "1 main lift" : "\(built.exercises.count) main lifts"
        let each = sets == 1 ? "1 hard set each" : "\(sets) hard sets each"
        result.lengthNote = "Busy week: \(lifts), \(each) at your usual weights, about \(built.estimate) min. \(headline)"
        result.rationaleLead = "\(workout.focus.title): busy week."
        result.rationale = "\(workout.focus.title), busy week: \(lifts) for \(each) at your usual weights. \(headline)"
        return result
    }
}

extension WeeklyPlan {
    /// A planned busy week (`BusyWeek`).
    public var isBusy: Bool { busy != nil }
}
