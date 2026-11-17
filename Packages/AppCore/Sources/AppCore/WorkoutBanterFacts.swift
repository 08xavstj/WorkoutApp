import Foundation

/// Works out, from the training log, the facts a reminder line can be about
/// (`WorkoutBanter.Facts`): a lift that is stuck or close to its best, what
/// stood out last session, weeks on plan in a row, a muscle group left alone.
/// The thresholds are app choices for what is worth a joke, not training
/// advice; the planner decides the training.
public enum WorkoutBanterFacts {
    /// A lift needs this many logged sessions before it gets a line.
    public static let minimumSessions = 3
    /// …and a session in the last two weeks: a lift not done lately isn't news.
    public static let liftRecentDays = 14
    /// Within this share of the best estimated 1RM counts as close to a record.
    public static let nearBestFraction = 0.97
    /// Longer names don't fit a notification line.
    public static let maxNameCharacters = 28
    /// A session's volume stands out when it is the most of this many recent sessions.
    public static let volumeWindow = 8
    public static let volumeMinimumSessions = 4

    /// The lift to mention: one whose top weight hasn't moved (and whose reps
    /// haven't gone up either) for the longest, else the most-trained lift
    /// whose last top set is close to its best. Bodyweight lifts and timed
    /// holds are left out (no weight to step up).
    /// - Parameter nextWeightKg: the next weight the gym can load above a
    ///   weight for an exercise id (`GymProfile.nextLoad`), in kilograms.
    public static func lift(sessions: [WorkoutSummary.LoggedSession], traits: [String: PRHistory.Traits] = [:], now: Date,
                            nextWeightKg: (_ exerciseID: String, _ aboveKg: Double) -> Double? = { _, _ in nil }) -> WorkoutBanter.Lift? {
        let holds = Set(sessions.flatMap(\.exercises).filter(\.isHold).map(\.exerciseID))
        var stuck: [(lift: WorkoutBanter.Lift, weeks: Int)] = []
        var near: [(lift: WorkoutBanter.Lift, sessions: Int)] = []
        for (id, entry) in PRHistory.history(sessions) {
            guard !holds.contains(id), traits[id]?.isBodyweight != true,
                  let name = WorkoutBanter.clean(entry.name), name.count <= maxNameCharacters else { continue }
            let points = LiftProgress.points(entry.sessions)
            guard points.count >= minimumSessions, let last = points.last, last.bestWeight > 0,
                  now.timeIntervalSince(last.date) <= Double(liftRecentDays) * 86_400, last.date <= now else { continue }
            var lift = WorkoutBanter.Lift(name: name, lastWeightKg: last.bestWeight, lastReps: last.bestReps,
                                          nextWeightKg: nextWeightKg(id, last.bestWeight))
            // The trailing run of sessions at the same top weight.
            let run = Array(points.reversed().prefix(while: { abs($0.bestWeight - last.bestWeight) < 0.01 }).reversed())
            let best = points.map(\.estimatedOneRepMax).max() ?? 0
            lift.nearBest = best > 0 && last.estimatedOneRepMax >= best * nearBestFraction
            if run.count >= minimumSessions, let first = run.first, last.bestReps <= first.bestReps {
                // More reps at the same weight is progress, not a plateau.
                let weeks = Int(now.timeIntervalSince(first.date) / (7 * 86_400))
                if weeks >= WorkoutBanter.stuckFromWeeks {
                    lift.weeksAtWeight = weeks
                    stuck.append((lift, weeks))
                    continue
                }
            }
            if lift.nearBest, lift.nextWeightKg != nil { near.append((lift, points.count)) }
        }
        if let longest = stuck.max(by: { $0.weeks != $1.weeks ? $0.weeks < $1.weeks : $0.lift.name > $1.lift.name }) {
            return longest.lift
        }
        return near.max { $0.sessions != $1.sessions ? $0.sessions < $1.sessions : $0.lift.name > $1.lift.name }?.lift
    }

    /// What stood out in the most recent session: a record on a lift (the
    /// same records as the summary, `PRHistory.events`), else the most total
    /// volume of the recent sessions.
    public static func standout(sessions: [WorkoutSummary.LoggedSession], traits: [String: PRHistory.Traits] = [:], now: Date,
                                calendar: Calendar = .current) -> WorkoutBanter.Standout? {
        let finished = sessions.filter { $0.start <= now }.sorted { $0.start < $1.start }
        guard let last = finished.last else { return nil }
        let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.start), to: calendar.startOfDay(for: now)).day ?? 0
        guard (0...WorkoutBanter.standoutMaxDays).contains(daysAgo) else { return nil }
        // Only the last session's lifts matter here, so only their history is gone through.
        let ids = Set(last.exercises.map(\.exerciseID))
        let relevant = finished.map { session in
            var copy = session
            copy.exercises = session.exercises.filter { ids.contains($0.exerciseID) }
            return copy
        }
        let records = PRHistory.events(relevant, traits: traits).filter { event in
            guard event.date == last.start else { return false }
            switch event.record {
            case .estimatedOneRepMax, .heaviest: return true
            case .reps, .volume: return false
            }
        }
        // The first such lift in session order, with a name that fits.
        let order = last.exercises.map(\.exerciseID)
        let named = records.compactMap { event -> (index: Int, name: String)? in
            guard let name = WorkoutBanter.clean(event.name), name.count <= maxNameCharacters else { return nil }
            return (order.firstIndex(of: event.exerciseID) ?? Int.max, name)
        }
        if let first = named.min(by: { $0.index < $1.index }) {
            return WorkoutBanter.Standout(recordLift: first.name, daysAgo: daysAgo)
        }
        let recent = finished.suffix(volumeWindow)
        let volumes = recent.map(volume)
        guard recent.count >= volumeMinimumSessions, let lastVolume = volumes.last, lastVolume > 0,
              volumes.dropLast().allSatisfy({ $0 < lastVolume }) else { return nil }
        return WorkoutBanter.Standout(volumeKg: lastVolume, daysAgo: daysAgo)
    }

    /// Weight × reps over the working sets (timed holds left out), in kilograms.
    static func volume(_ session: WorkoutSummary.LoggedSession) -> Double {
        var total = 0.0
        for exercise in session.exercises where !exercise.isHold {
            for set in exercise.working { total += max(0, set.weightKg) * Double(set.reps) }
        }
        return total
    }

    /// Weeks in a row the plan was kept (`Consistency.weekKept`), ending with
    /// last week, plus this week once it is kept. A week without a plan ends
    /// the run. Only ever reported while it stands.
    public static func weeksInARow(records: [WeekRecord], now: Date, calendar: Calendar = .current) -> Int {
        let thisWeek = WeeklyPlan.weekStart(containing: now, calendar: calendar)
        let byWeek = Dictionary(records.map { (calendar.startOfDay(for: $0.weekStart), $0) }, uniquingKeysWith: { first, _ in first })
        var count = 0
        if let current = byWeek[thisWeek], Consistency.weekKept(planned: current.planned, done: current.done) { count += 1 }
        var week = thisWeek
        while let previous = calendar.date(byAdding: .day, value: -7, to: week), let record = byWeek[calendar.startOfDay(for: previous)],
              Consistency.weekKept(planned: record.planned, done: record.done) {
            count += 1
            week = previous
        }
        return count
    }

    /// Muscle groups a line may name. The ones people train on purpose in the
    /// gym; none that reads as a comment on looks (app choice).
    public static let nameableMuscles: [Muscle] = [.chest, .shoulders, .lats, .middleBack, .quadriceps, .hamstrings,
                                                   .biceps, .triceps, .calves]

    /// The nameable muscle group trained before but left alone the longest,
    /// when that is between `neglectedFromDays` and `neglectedMaxDays`.
    public static func neglected(lastTrained: [Muscle: Date], now: Date, calendar: Calendar = .current) -> WorkoutBanter.Neglected? {
        let today = calendar.startOfDay(for: now)
        let candidates = nameableMuscles.compactMap { muscle -> WorkoutBanter.Neglected? in
            guard let last = lastTrained[muscle],
                  let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day,
                  (WorkoutBanter.neglectedFromDays...WorkoutBanter.neglectedMaxDays).contains(days) else { return nil }
            return WorkoutBanter.Neglected(muscle: muscle.name.lowercased(), days: days)
        }
        return candidates.max { $0.days != $1.days ? $0.days < $1.days : $0.muscle > $1.muscle }
    }

    /// How a session is named mid-sentence, the way a gym says it: "Leg day",
    /// "Push day". ("Legs in 30 minutes" reads fine; "Upper in 30 minutes" doesn't.)
    public static func dayName(for focus: WorkoutFocus) -> String {
        switch focus {
        case .push: "Push day"
        case .pull: "Pull day"
        case .legs: "Leg day"
        case .upper: "Upper day"
        case .lower: "Lower day"
        case .fullBody: "Full body day"
        }
    }

    /// Low, normal or high from a recovery score (`RecoveryCalculator`'s bands).
    public static func recoveryBand(score: Int) -> WorkoutBanter.RecoveryBand {
        if RecoveryCalculator.lowBand.contains(score) || score < RecoveryCalculator.lowBand.lowerBound { return .low }
        return score >= RecoveryCalculator.highBand.lowerBound ? .high : .normal
    }
}
