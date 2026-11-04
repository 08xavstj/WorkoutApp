import Foundation

/// How trained someone is, from their logged lifting history. Used to pick
/// the resting-energy equation (`EnergyCalculator.bmr`) and the fastest
/// useful rate of gain (`GoalPlanner.maximumWeeklyRate`).
///
/// The rule is the app's choice; no study sets it. It borrows two anchors:
/// - "Resistance-trained" means more than 6 months of training in the
///   protein-in-a-deficit review that defines the group (Helms, Zinn,
///   Rowlands & Brown, IJSNEM 2014), so 6 consistent months is the line
///   between novice and intermediate.
/// - Advanced lifters gain muscle slowly and should gain weight more
///   slowly (Iraki et al., Sports 2019); "advanced" here is 2+ years of
///   consistent training, an app choice.
/// `estimate` counts only sessions logged in this app, so someone who lifted
/// for years before installing it would read as a novice until the history
/// builds up. `resolve` fixes that with the lifting experience they report in
/// Settings › Training (`LiftingExperience`).
public enum TrainingStatus: String, Codable, Sendable, CaseIterable, Comparable {
    case untrained, novice, intermediate, advanced

    /// Average sessions a week over the last 8 weeks below this: untrained
    /// (app choice: under one a week isn't regular training).
    public static let minimumWeeklySessions = 1.0
    /// Sessions a week over the last 8 weeks needed to count as trained
    /// (app choice; the ten Haaf equation's group averaged 5 a week).
    public static let trainedWeeklySessions = 2.0
    /// A month counts as consistent with at least this many sessions (about one a week).
    public static let sessionsPerConsistentMonth = 4
    /// Consistent months for intermediate (Helms 2014's "> 6 months").
    public static let intermediateMonths = 6
    /// Consistent months for advanced (app choice: 2 years).
    public static let advancedMonths = 24

    private var rank: Int {
        switch self {
        case .untrained: 0
        case .novice: 1
        case .intermediate: 2
        case .advanced: 3
        }
    }

    public static func < (lhs: TrainingStatus, rhs: TrainingStatus) -> Bool { lhs.rank < rhs.rank }

    /// Training regularly for 6+ months: the group the athlete equations were built on.
    public var isTrained: Bool { self >= .intermediate }

    public var label: String {
        switch self {
        case .untrained: "Not lifting regularly"
        case .novice: "Newer lifter"
        case .intermediate: "Regular lifter (6+ months)"
        case .advanced: "Experienced lifter (2+ years)"
        }
    }

    /// From the start times of finished lifting sessions (any order).
    /// - Untrained: under 1 session a week over the last 8 weeks.
    /// - Novice: under 2 a week, or under 6 consistent months.
    /// - Intermediate: 6-23 consistent months.
    /// - Advanced: 24+ consistent months.
    /// A consistent month is a 30.4-day block, counted back from `now`, with 4+ sessions.
    public static func estimate(sessionDates: [Date], now: Date = .now) -> TrainingStatus {
        let past = sessionDates.filter { $0 <= now }
        guard let first = past.min() else { return .untrained }
        let eightWeeks = now.addingTimeInterval(-56 * 86_400)
        let perWeek = Double(past.filter { $0 > eightWeeks }.count) / 8
        guard perWeek >= minimumWeeklySessions else { return .untrained }

        let month = 365.25 / 12 * 86_400
        let blocks = Int(now.timeIntervalSince(first) / month) + 1
        var consistentMonths = 0
        for index in 0..<blocks {
            let end = now.addingTimeInterval(-Double(index) * month)
            let start = end.addingTimeInterval(-month)
            if past.filter({ $0 > start && $0 <= end }).count >= sessionsPerConsistentMonth {
                consistentMonths += 1
            }
        }
        if perWeek < trainedWeeklySessions || consistentMonths < intermediateMonths { return .novice }
        return consistentMonths < advancedMonths ? .intermediate : .advanced
    }

    /// Weeks between the first logged session and now before the log can
    /// overrule the reported experience (app choice: the same 8-week window
    /// `estimate` uses to tell regular training from none).
    public static let weeksToJudgeLog = 8

    /// The training status the app uses: the logged estimate combined with
    /// the experience the user reported. The rule is the app's choice, not a
    /// study's; it reuses the anchors above (Helms, Zinn, Rowlands & Brown,
    /// IJSNEM 2014 for 6 months; Iraki et al., Sports 2019 for advanced).
    /// - Nothing reported: the logged estimate, as before.
    /// - Reported, and under 8 weeks of logged history (too short to judge):
    ///   the reported level (2+ years advanced, 6 months-2 years
    ///   intermediate, under 6 months novice).
    /// - Reported, and 8+ weeks logged: the higher of the reported level and
    ///   the estimate, unless the estimate is untrained (under one session a
    ///   week lately: they have stopped training regularly), which wins.
    public static func resolve(reported: LiftingExperience?, sessionDates: [Date], now: Date = .now) -> TrainingStatus {
        let logged = Self.estimate(sessionDates: sessionDates, now: now)
        guard let reported else { return logged }
        let window = Double(weeksToJudgeLog) * 7 * 86_400
        guard let first = sessionDates.filter({ $0 <= now }).min(),
              now.timeIntervalSince(first) >= window else { return reported.status }
        if logged == .untrained { return .untrained }
        return max(reported.status, logged)
    }
}

/// How long someone says they have lifted, set in Settings › Training, for
/// people whose training started before the app's log did
/// (docs/research/calories.md). The bands use `TrainingStatus`'s lines:
/// 6 months (Helms, Zinn, Rowlands & Brown, IJSNEM 2014: "resistance-trained"
/// means more than 6 months) and 2 years (app choice; advanced lifters should
/// gain more slowly, Iraki et al., Sports 2019).
public enum LiftingExperience: String, Codable, Sendable, CaseIterable {
    case underSixMonths, sixMonthsToTwoYears, twoYearsPlus

    public var label: String {
        switch self {
        case .underSixMonths: "Less than 6 months"
        case .sixMonthsToTwoYears: "6 months to 2 years"
        case .twoYearsPlus: "2+ years"
        }
    }

    /// The training status this much experience stands for.
    public var status: TrainingStatus {
        switch self {
        case .underSixMonths: .novice
        case .sixMonthsToTwoYears: .intermediate
        case .twoYearsPlus: .advanced
        }
    }
}
