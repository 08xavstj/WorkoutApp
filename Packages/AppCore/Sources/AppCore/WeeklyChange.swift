import Foundation

// MARK: - The model

/// One change chosen at the Monday review (`WeeklyPlan.changes`).
///
/// Most kinds are things the app can check from data it already reads, with
/// no ticking: next Monday the review says how many days it was kept
/// (`WeeklyChangeReview`). `custom` is free text and is never measured.
///
/// Why measured choices: reviewing a goal and seeing recorded progress
/// against it is what makes self-monitoring work (Michie et al., Health
/// Psychol 2009: 0.42 against 0.26; Harkin et al., Psychol Bull 2016,
/// d = 0.40), and self-chosen habits form more strongly (Singh et al.,
/// Healthcare 2024). Evidence for one-week personal experiments as such is
/// weak: no meta-analysis was found (docs/research/healthy-living-2026-11.md
/// §3 item 4), so the report never says a change caused anything.
///
/// Plans saved before this type existed hold plain strings; each decodes as
/// a `custom` change with that text.
public struct WeeklyChange: Codable, Sendable, Equatable, Identifiable, ExpressibleByStringLiteral {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Last caffeine by a time (`CaffeineTiming`; Gardiner et al., Sleep Med Rev 2023).
        case caffeineCutoff
        /// In bed by the end of the bed-by window on N nights (`BedtimeWindow`).
        case bedByWindow
        /// Up within an hour of one wake time (regular timing: Windred et al., Sleep 2024).
        case wakeTime
        /// The per-meal protein dose at N meals a day (`ProteinMeals`; Schoenfeld & Aragon, JISSN 2018).
        case proteinMeals
        /// A weekly average of steps a day (`HealthFloors.dailySteps`; Ding et al. 2025).
        case stepsAverage
        /// One hard cardio session, found in recorded workouts (`WeeklyChangeReview.hardSessionVigorousMinutes`).
        case hardCardio
        /// Drinks at or under a weekly limit (`DrinkLimit`; Kaner et al., Cochrane 2017).
        case drinksLimit
        /// The 150-minute floor (`HealthFloors.activeMinutes`; WHO 2020).
        case activeMinutes
        /// Strength training on 2 days (`HealthFloors.strengthDays`; WHO 2020).
        case strengthDays
        /// Free text. Not measured.
        case custom
    }

    public var kind: Kind
    /// The line shown, e.g. "Last caffeine by 2:25 pm".
    public var title: String
    /// What it is checked against: minutes after midnight (caffeine, bed, wake;
    /// over 1440 for after midnight), steps a day, drinks a week, minutes a
    /// week, days a week or meals a day. Nil for free text.
    public var target: Double?
    /// Days or nights of the week it is meant to be kept; nil means every one.
    public var days: Int?

    /// One of each measured kind per week; free text is told apart by its words.
    public var id: String { kind == .custom ? "custom|" + title : kind.rawValue }
    public var isMeasured: Bool { kind != .custom }

    /// Changes tracked when a week starts (one: three can feel like homework,
    /// healthy-living-2026-11.md §3 item 4) and the most the owner can choose.
    public static let defaultCount = 1
    public static let maximumCount = 3

    public init(kind: Kind, title: String, target: Double? = nil, days: Int? = nil) {
        self.kind = kind
        self.title = title
        self.target = target
        self.days = days
    }

    /// Free text, unmeasured.
    public init(text: String) {
        self.init(kind: .custom, title: text)
    }

    public init(stringLiteral value: String) {
        self.init(text: value)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, title, target, days
    }

    /// A plain string (plans saved before the typed model) is a free-text
    /// change. A kind this version doesn't know keeps its words and is
    /// treated as free text.
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            kind = .custom
            title = text
            target = nil
            days = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kind = Kind(rawValue: raw) ?? .custom
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        target = try container.decodeIfPresent(Double.self, forKey: .target)
        days = try container.decodeIfPresent(Int.self, forKey: .days)
    }
}

// MARK: - The choices

extension WeeklyChange {
    /// Nights a week for "in bed by" unless the owner picks another number
    /// (app's choice: the work nights; regular timing argues for all seven,
    /// but a plan that allows a late Friday is the one that gets kept).
    public static let defaultBedNights = 5
    public static let bedNightsRange = 3...7
    /// Meals a day at the per-meal dose for the day to count. The paper's
    /// figure for the most muscle is four (Schoenfeld & Aragon, JISSN 2018);
    /// three is the app's choice for a change to keep, since most days have
    /// three main meals.
    public static let defaultProteinMeals = 3

    public static func caffeineCutoff(byMinutes minutes: Int) -> WeeklyChange {
        WeeklyChange(kind: .caffeineCutoff, title: "Last caffeine by \(CaffeineTiming.clockText(minutes))", target: Double(minutes))
    }

    /// - Parameter minutes: the end of the bed-by window, minutes after the
    ///   evening's midnight (over 1440 when it falls after midnight).
    public static func bedBy(minutes: Int, nights: Int = defaultBedNights) -> WeeklyChange {
        let count = min(bedNightsRange.upperBound, max(bedNightsRange.lowerBound, nights))
        return WeeklyChange(kind: .bedByWindow,
                            title: "In bed by \(CaffeineTiming.clockText(minutes)) on \(count == 7 ? "every night" : "\(count) nights")",
                            target: Double(minutes), days: count)
    }

    public static func wakeTime(minutes: Int) -> WeeklyChange {
        WeeklyChange(kind: .wakeTime,
                     title: "Up within an hour of \(CaffeineTiming.clockText(minutes)), every day",
                     target: Double(minutes))
    }

    public static func proteinMeals(_ meals: Int = defaultProteinMeals) -> WeeklyChange {
        WeeklyChange(kind: .proteinMeals, title: "Protein at \(meals) meals a day", target: Double(meals))
    }

    public static func stepsAverage(_ steps: Double = HealthFloors.dailySteps) -> WeeklyChange {
        WeeklyChange(kind: .stepsAverage, title: "Average \(Longevity.grouped(steps)) steps a day", target: steps)
    }

    public static let hardCardio = WeeklyChange(kind: .hardCardio, title: "One hard cardio session", target: 1)

    public static func drinksLimit(_ limit: Double) -> WeeklyChange {
        let amount = Longevity.one(max(0, limit))
        return WeeklyChange(kind: .drinksLimit, title: limit <= 0 ? "No drinks this week" : "Up to \(amount) drink\(limit == 1 ? "" : "s") this week",
                            target: max(0, limit))
    }

    public static let activeMinutes = WeeklyChange(kind: .activeMinutes, title: "\(HealthFloors.activeMinutes) cardio minutes",
                                                   target: Double(HealthFloors.activeMinutes))

    public static let strengthDays = WeeklyChange(kind: .strengthDays, title: "Strength training on \(HealthFloors.strengthDays) days",
                                                  target: Double(HealthFloors.strengthDays))

    /// A time of the evening as minutes after that evening's midnight: 22:30
    /// is 1350, 00:20 the next morning is 1460. Times before noon belong to
    /// the evening before.
    public static func eveningMinutes(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes < 12 * 60 ? minutes + 1440 : minutes
    }
}

// MARK: - What to suggest

/// The choices offered at the review and which comes first.
public enum WeeklyChangeSuggestions {
    /// What the app knows when the review opens. Nil means that choice can't
    /// be checked yet, so it isn't offered.
    public struct Context: Sendable, Equatable {
        /// Last coffee by this time for the usual bedtime (`CaffeineTiming.cutoffMinutes`).
        public var caffeineCutoffMinutes: Int?
        /// The end of the bed-by window, as `WeeklyChange.eveningMinutes`.
        public var bedByMinutes: Int?
        /// The usual wake time (`BedtimeWindow.usualWakeMinutes`).
        public var usualWakeMinutes: Int?
        /// The food app sends meal times, so protein per meal can be counted.
        public var hasMealTimes = false
        /// The owner's own weekly drink limit (`DrinkLimit`), if set.
        public var drinkLimit: Double?
        /// Last week's drinks, when enough evenings were logged.
        public var lastWeekDrinks: Double?
        /// Drinks are being logged at all (so a limit can be checked).
        public var logsDrinks = false
        /// Last week's vigorous minutes, when there was heart rate.
        public var vigorousMinutes: Int?
        /// Extra minutes a night the sleep-debt plan asks for, when the debt is moderate or high.
        public var sleepDebtExtraMinutes: Int?
        /// The latest logged day's protein was under 80% of the target.
        public var proteinLow = false
        /// Last week had a plan and wasn't kept (`Consistency.weekKept`).
        public var weekNotKept = false
        /// 7-day HRV is below the normal range.
        public var trainEasy = false
        public var weightPace: WeightPace.Status = .fine

        public init() {}
    }

    /// The limit a drinks change starts from: the owner's own when set,
    /// else one tier down in Canada's guidance (7 or more → 6, otherwise 2;
    /// `AlcoholWeek`, CCSA 2023). A self-set goal is the part of digital
    /// alcohol tools tied to larger effects (Kaner et al., Cochrane 2017).
    public static func drinkLimit(_ context: Context) -> Double {
        if let limit = context.drinkLimit { return limit }
        if let drinks = context.lastWeekDrinks, AlcoholWeek.tier(drinks: drinks) == .high { return AlcoholWeek.moderateMax }
        return AlcoholWeek.lowMax
    }

    /// The change that answers an unmet floor.
    public static func change(for floor: HealthFloors.Floor, context: Context) -> WeeklyChange? {
        switch floor {
        case .activeMinutes: return WeeklyChange.activeMinutes
        case .strengthDays: return WeeklyChange.strengthDays
        case .steps: return WeeklyChange.stepsAverage()
        // One wake time moves the index most; without sleep data there is no wake time to hold.
        case .sleepRegularity: return context.usualWakeMinutes.map { WeeklyChange.wakeTime(minutes: $0) }
        case .drinks: return WeeklyChange.drinksLimit(drinkLimit(context))
        }
    }

    /// Every change the app can check with the data on hand, in menu order.
    public static func measurable(_ context: Context) -> [WeeklyChange] {
        var options: [WeeklyChange] = []
        if let cutoff = context.caffeineCutoffMinutes { options.append(.caffeineCutoff(byMinutes: cutoff)) }
        if let bedBy = context.bedByMinutes { options.append(.bedBy(minutes: bedBy)) }
        if let wake = context.usualWakeMinutes { options.append(.wakeTime(minutes: wake)) }
        if context.hasMealTimes { options.append(.proteinMeals()) }
        options.append(.stepsAverage())
        options.append(.hardCardio)
        if context.logsDrinks || context.drinkLimit != nil { options.append(.drinksLimit(drinkLimit(context))) }
        options.append(.activeMinutes)
        options.append(.strengthDays)
        return options
    }

    /// Unmeasured lines the review has always offered, for the menu.
    public static let plainIdeas: [WeeklyChange] = [
        "Train at the planned time, even if shorter", "A walk after lunch", "Phone out of the bedroom",
    ]

    /// Suggestions, best first: the unmet floors in list order, then what
    /// the week's other numbers point at, then plain ideas. The first one is
    /// tracked by default. No duplicates.
    public static func suggested(basics: HealthFloors.Result?, context: Context) -> [WeeklyChange] {
        var result: [WeeklyChange] = []
        func add(_ change: WeeklyChange?) {
            guard let change, !result.contains(where: { $0.id == change.id }) else { return }
            result.append(change)
        }
        for floor in basics?.unmet ?? [] {
            add(change(for: floor, context: context))
        }
        if context.weekNotKept { add(WeeklyChange(text: "Keep the 15-minute version ready for busy days")) }
        if let extra = context.sleepDebtExtraMinutes {
            if let bedBy = context.bedByMinutes {
                add(WeeklyChange.bedBy(minutes: bedBy))
            } else {
                add(WeeklyChange(text: "In bed \(extra) minutes earlier on three nights"))
            }
        }
        if context.proteinLow {
            add(context.hasMealTimes ? WeeklyChange.proteinMeals() : WeeklyChange(text: "Protein with every meal"))
        }
        if context.trainEasy { add(WeeklyChange(text: "Keep the first session of the week easy")) }
        switch context.weightPace {
        case .losingTooFast: add(WeeklyChange(text: "Eat a little more; the pace is faster than planned"))
        case .gainingTooFast: add(WeeklyChange(text: "Trim a little; the pace is faster than planned"))
        case .fine: break
        }
        // A lifter usually passes strength and misses hard minutes: offer the
        // session, never schedule it (healthy-living-2026-11.md §3 item 3).
        if let vigorous = context.vigorousMinutes, vigorous < IntensityMinutes.vigorousReferenceMinutes.lowerBound {
            add(WeeklyChange.hardCardio)
        }
        for idea in plainIdeas { add(idea) }
        return result
    }
}

// MARK: - Reported back

/// Next Monday: how many days each tracked change was kept and what moved.
///
/// One week proves nothing, and the report says so (`caveat`). Where a
/// change can be judged day by day and there is an outcome to compare
/// (sleep), the days it was kept are compared with the days it wasn't with
/// the patterns engine's own test and limits (`CheckInInsights`): at least 7
/// days each way, a gap bigger than half the day-to-day spread (Plews et
/// al., Sports Med 2013), and a Welch t-test corrected for the number of
/// changes tested (Benjamini-Hochberg). Short of that it reports the numbers
/// and declines to say more.
public enum WeeklyChangeReview {
    /// Minutes either side of the wake time that still count as kept: "within
    /// an hour". App's choice; the cohort behind sleep regularity gives no
    /// figure (Windred et al., Sleep 2024), and the weekend-shift note
    /// (`SleepRegularity.midpointShift`) also treats about an hour as the line.
    public static let wakeToleranceMinutes = 60

    /// Vigorous minutes inside one recorded cardio workout for it to count as
    /// a hard session. App's choice, anchored on two findings: intervals did
    /// most for VO₂ max with 15 minutes or more of hard work a session (Wen
    /// et al., J Sci Med Sport 2019), and about 15 vigorous minutes a week is
    /// where the mortality link begins (Ahmadi et al., Eur Heart J 2022).
    /// "Vigorous" is the app's 60%+ of heart-rate reserve (`IntensityMinutes`),
    /// lower than the 85-95% of maximum the interval trials used.
    public static let hardSessionVigorousMinutes = 15
    /// Shorter recorded workouts aren't looked at (app's choice).
    public static let hardSessionMinimumMinutes = 10

    /// Days each way before kept days are compared with the rest
    /// (`CheckInInsights.analyze`'s own minimum).
    public static let minimumDays = 7
    /// False-discovery rate across the changes tested, as in `CheckInInsights`.
    public static let falseDiscoveryRate = 0.1
    /// Days of earlier data before "the four weeks before" is quoted (app's choice).
    public static let minimumEarlierDays = 7

    public static let caveat = "One week can't prove anything: sleep, steps and recovery move for many reasons. This is a record of what you did, not of what it caused."

    /// One calendar day of what the app already reads. Nil means not known,
    /// never "not kept".
    public struct Day: Sendable, Equatable {
        /// Start of the day.
        public var date: Date
        /// The day's last caffeine, minutes after midnight.
        public var lastCaffeineMinutes: Int?
        /// The day is known to have had no caffeine.
        public var noCaffeine = false
        /// When that evening's sleep began, as `WeeklyChange.eveningMinutes`.
        public var bedtimeMinutes: Int?
        /// When the day began: that morning's wake time, minutes after midnight.
        public var wakeMinutes: Int?
        /// Meals at or over the per-meal protein dose; nil without meal times.
        public var proteinMeals: Int?
        public var proteinGrams: Double?
        public var steps: Double?
        public var moderateMinutes: Int?
        public var vigorousMinutes: Int?
        /// The most vigorous minutes inside one recorded cardio workout that
        /// day; nil without such a workout.
        public var cardioVigorousMinutes: Int?
        /// A strength session that day; nil when sessions aren't known.
        public var strengthSession: Bool?
        /// Standard drinks that evening; nil when not logged.
        public var drinks: Double?
        /// Hours asleep in the night that began that evening.
        public var sleepHours: Double?

        public init(date: Date) {
            self.date = date
        }
    }

    public enum Verdict: String, Sendable, Equatable {
        /// Free text.
        case notMeasured
        /// A measured change with nothing to check it against last week.
        case noData
        /// The numbers, with no comparison to make (weekly totals).
        case numbersOnly
        /// Kept days and other days were compared, but there are too few.
        case tooFewDays
        case noClearDifference
        case clearDifference
    }

    public struct Report: Sendable, Equatable, Identifiable {
        public var change: WeeklyChange
        /// "Kept on 5 of 7 days", "Averaged 7,400 steps a day", "Not measured".
        public var kept: String
        /// Whether the week met the change; nil when unmeasured or unknown.
        public var wasKept: Bool?
        /// What moved, in numbers; nil when there is nothing to say.
        public var moved: String?
        public var verdict: Verdict

        public var id: String { change.id }
        public var title: String { change.title }
    }

    // MARK: Day by day

    /// Whether a day kept a change that is judged per day; nil when the day
    /// has no data for it, or the change is judged over the whole week.
    public static func kept(_ change: WeeklyChange, on day: Day) -> Bool? {
        switch change.kind {
        case .caffeineCutoff:
            guard let target = change.target else { return nil }
            if let last = day.lastCaffeineMinutes { return Double(last) <= target }
            return day.noCaffeine ? true : nil
        case .bedByWindow:
            guard let target = change.target, let bedtime = day.bedtimeMinutes else { return nil }
            return Double(bedtime) <= target
        case .wakeTime:
            guard let target = change.target, let wake = day.wakeMinutes else { return nil }
            // On the 24-hour circle, so 23:50 and 00:10 are 20 minutes apart.
            let gap = abs(Double(wake) - target).truncatingRemainder(dividingBy: 1440)
            return min(gap, 1440 - gap) <= Double(wakeToleranceMinutes)
        case .proteinMeals:
            guard let meals = day.proteinMeals else { return nil }
            return Double(meals) >= (change.target ?? Double(WeeklyChange.defaultProteinMeals))
        case .stepsAverage, .hardCardio, .drinksLimit, .activeMinutes, .strengthDays, .custom:
            return nil
        }
    }

    // MARK: The report

    /// - Parameters:
    ///   - changes: the changes saved on last week's plan.
    ///   - week: last week's days (Monday to Sunday).
    ///   - earlier: the days before it, up to four weeks, for comparison.
    public static func report(changes: [WeeklyChange], week: [Day], earlier: [Day]) -> [Report] {
        var reports = changes.map { change -> Report in
            switch change.kind {
            case .custom:
                Report(change: change, kept: "Not measured", wasKept: nil, moved: nil, verdict: .notMeasured)
            case .caffeineCutoff, .bedByWindow, .wakeTime, .proteinMeals:
                dailyReport(change, week: week, earlier: earlier)
            case .stepsAverage:
                stepsReport(change, week: week, earlier: earlier)
            case .hardCardio:
                hardCardioReport(change, week: week)
            case .drinksLimit:
                drinksReport(change, week: week, earlier: earlier)
            case .activeMinutes:
                activeMinutesReport(change, week: week)
            case .strengthDays:
                strengthReport(change, week: week, earlier: earlier)
            }
        }
        // Kept days against the rest, for the changes with a sleep outcome.
        let tested: [(index: Int, comparison: Comparison)] = reports.indices.compactMap { index in
            guard let comparison = sleepComparison(reports[index].change, days: week + earlier) else { return nil }
            return (index, comparison)
        }
        let enough = tested.filter { $0.comparison.hasEnoughDays }
        // A gap inside the usual day-to-day swing was still tested, so it counts
        // toward the correction and is never kept (as in `CheckInInsights.analyze`).
        let passing = CheckInInsights.benjaminiHochberg(
            enough.map { $0.comparison.isBiggerThanUsualSwing ? $0.comparison.pValue : Double.infinity }, rate: falseDiscoveryRate)
        for item in tested {
            let comparison = item.comparison
            guard comparison.hasEnoughDays else {
                reports[item.index].verdict = .tooFewDays
                reports[item.index].moved = join(reports[item.index].moved,
                    "Too few days to compare sleep: \(comparison.with.count) kept and \(comparison.without.count) not, and a pattern needs \(minimumDays) of each.")
                continue
            }
            let position = enough.firstIndex { $0.index == item.index } ?? 0
            if comparison.isBiggerThanUsualSwing, passing.contains(position) {
                let minutes = Int((abs(comparison.difference) * 60).rounded())
                reports[item.index].verdict = .clearDifference
                reports[item.index].moved = join(reports[item.index].moved,
                    "On the \(comparison.with.count) days you kept it, sleep was \(minutes) min \(comparison.difference > 0 ? "longer" : "shorter") than on the \(comparison.without.count) you didn't. A pattern in your own data, not proof.")
            } else {
                reports[item.index].verdict = .noClearDifference
                reports[item.index].moved = join(reports[item.index].moved,
                    "No clear difference in sleep between the days you kept it and the days you didn't; any gap may be chance.")
            }
        }
        return reports
    }

    // MARK: Kinds judged per day

    static func dailyReport(_ change: WeeklyChange, week: [Day], earlier: [Day]) -> Report {
        let flags = week.compactMap { kept(change, on: $0) }
        let unit = change.kind == .bedByWindow ? "nights" : "days"
        guard !flags.isEmpty else {
            return Report(change: change, kept: "No data last week", wasKept: nil, moved: missingDataHint(change.kind), verdict: .noData)
        }
        let count = flags.filter { $0 }.count
        let known = flags.count
        var line = "Kept on \(count) of \(known) \(unit)"
        if known < week.count { line += " with data" }
        // "On N nights" is met at N; "every day" is met when every day with data kept it.
        let wasKept = change.days.map { count >= $0 } ?? (count == known)
        var moved: String?
        if change.kind == .proteinMeals {
            moved = averageLine(label: "Protein", unit: "g a day", week: week.compactMap(\.proteinGrams), earlier: earlier.compactMap(\.proteinGrams))
        } else {
            let hours = week.compactMap(\.sleepHours)
            let before = earlier.compactMap(\.sleepHours)
            if let now = mean(hours) {
                moved = "Sleep averaged \(Longevity.hoursText(now)) a night last week"
                    + (before.count >= minimumEarlierDays ? ", \(Longevity.hoursText(mean(before) ?? now)) over the four weeks before." : ".")
            }
        }
        return Report(change: change, kept: line, wasKept: wasKept, moved: moved, verdict: .numbersOnly)
    }

    static func missingDataHint(_ kind: WeeklyChange.Kind) -> String? {
        switch kind {
        case .caffeineCutoff: "Needs caffeine times from your food app, or the evening check-in."
        case .bedByWindow, .wakeTime: "Needs sleep from your watch or ring."
        case .proteinMeals: "Needs meal times from your food app."
        default: nil
        }
    }

    // MARK: Kinds judged over the week

    static func stepsReport(_ change: WeeklyChange, week: [Day], earlier: [Day]) -> Report {
        let steps = week.compactMap(\.steps).filter { $0 > 0 }
        guard steps.count >= HealthFloors.stepsMinimumDays, let average = mean(steps) else {
            return Report(change: change, kept: "No data last week", wasKept: nil, moved: nil, verdict: .noData)
        }
        let target = change.target ?? HealthFloors.dailySteps
        let before = earlier.compactMap(\.steps).filter { $0 > 0 }
        var moved: String?
        if before.count >= minimumEarlierDays, let earlierAverage = mean(before) {
            let gap = average - earlierAverage
            // Under 250 steps a day rounds to nothing worth reporting (app's choice).
            moved = abs(gap) < 250
                ? "About the same as the four weeks before (\(Longevity.grouped(earlierAverage)))."
                : "\(gap > 0 ? "Up" : "Down") from \(Longevity.grouped(earlierAverage)) over the four weeks before."
        }
        return Report(change: change, kept: "Averaged \(Longevity.grouped(average)) steps a day", wasKept: average >= target,
                      moved: moved, verdict: .numbersOnly)
    }

    static func hardCardioReport(_ change: WeeklyChange, week: [Day]) -> Report {
        let vigorous = week.compactMap(\.vigorousMinutes)
        let sessions = week.compactMap(\.cardioVigorousMinutes).filter { $0 >= hardSessionVigorousMinutes }
        // Without heart rate all week there is nothing to find a session in.
        guard !vigorous.isEmpty || !sessions.isEmpty else {
            return Report(change: change, kept: "No data last week", wasKept: nil, moved: "Needs a recorded workout with heart rate.", verdict: .noData)
        }
        let wanted = Int(change.target ?? 1)
        let line = sessions.isEmpty
            ? "No hard session recorded"
            : "\(sessions.count) hard session\(sessions.count == 1 ? "" : "s"): \(sessions.max() ?? 0) vigorous minutes in the longest"
        let total = vigorous.reduce(0, +)
        return Report(change: change, kept: line, wasKept: sessions.count >= wanted,
                      moved: vigorous.isEmpty ? nil : "Vigorous minutes last week: \(total).", verdict: .numbersOnly)
    }

    static func drinksReport(_ change: WeeklyChange, week: [Day], earlier: [Day]) -> Report {
        let logged = week.compactMap(\.drinks)
        guard logged.count >= HealthFloors.drinksMinimumNights else {
            return Report(change: change, kept: "No data last week", wasKept: nil,
                          moved: "Needs \(HealthFloors.drinksMinimumNights) evenings logged. Zero counts.", verdict: .noData)
        }
        let total = logged.reduce(0, +)
        let limit = change.target ?? HealthFloors.drinks
        var line = "\(Longevity.one(total)) against a limit of \(Longevity.one(limit))"
        if logged.count < week.count { line += " (\(logged.count) of \(week.count) evenings logged)" }
        let before = earlier.compactMap(\.drinks)
        var moved: String?
        // Two weeks of logged evenings before a weekly rate is quoted (app's choice).
        if before.count >= 14 {
            let weekly = before.reduce(0, +) / Double(before.count) * 7
            moved = "The four weeks before averaged \(Longevity.one(weekly)) a week."
        }
        return Report(change: change, kept: line, wasKept: total <= limit, moved: moved, verdict: .numbersOnly)
    }

    static func activeMinutesReport(_ change: WeeklyChange, week: [Day]) -> Report {
        let days = week.filter { $0.moderateMinutes != nil || $0.vigorousMinutes != nil }
        guard !days.isEmpty else {
            return Report(change: change, kept: "No data last week", wasKept: nil, moved: "Needs heart rate from your watch.", verdict: .noData)
        }
        let moderate = days.compactMap(\.moderateMinutes).reduce(0, +)
        let vigorous = days.compactMap(\.vigorousMinutes).reduce(0, +)
        let total = IntensityMinutes.Result(moderate: moderate, vigorous: vigorous).total
        let target = Int(change.target ?? Double(HealthFloors.activeMinutes))
        return Report(change: change, kept: "\(total) cardio minutes", wasKept: total >= target,
                      moved: "\(moderate) moderate and \(vigorous) vigorous, which count double.", verdict: .numbersOnly)
    }

    static func strengthReport(_ change: WeeklyChange, week: [Day], earlier: [Day]) -> Report {
        let known = week.compactMap(\.strengthSession)
        guard !known.isEmpty else {
            return Report(change: change, kept: "No data last week", wasKept: nil, moved: nil, verdict: .noData)
        }
        let days = known.filter { $0 }.count
        let target = Int(change.target ?? Double(HealthFloors.strengthDays))
        let before = earlier.compactMap(\.strengthSession)
        var moved: String?
        if before.count >= 14 {
            let weekly = Double(before.filter { $0 }.count) / Double(before.count) * 7
            moved = "The four weeks before averaged \(Longevity.one(weekly)) a week."
        }
        return Report(change: change, kept: "\(days) strength day\(days == 1 ? "" : "s")", wasKept: days >= target, moved: moved, verdict: .numbersOnly)
    }

    // MARK: Kept days against the rest

    struct Comparison {
        var with: [Double]
        var without: [Double]
        var hasEnoughDays: Bool { with.count >= WeeklyChangeReview.minimumDays && without.count >= WeeklyChangeReview.minimumDays }
        /// Hours: kept days minus the rest.
        var difference: Double { (WeeklyChangeReview.mean(with) ?? 0) - (WeeklyChangeReview.mean(without) ?? 0) }
        /// Bigger than half the day-to-day spread (`CheckInInsights.analyze`).
        var isBiggerThanUsualSwing: Bool {
            let (_, varianceWith) = CheckInInsights.meanVariance(with)
            let (_, varianceWithout) = CheckInInsights.meanVariance(without)
            let pooled = ((varianceWith + varianceWithout) / 2).squareRoot()
            return abs(difference) > 0 && abs(difference) >= 0.5 * pooled
        }
        var pValue: Double {
            let (meanWith, varianceWith) = CheckInInsights.meanVariance(with)
            let (meanWithout, varianceWithout) = CheckInInsights.meanVariance(without)
            return CheckInInsights.welchPValue(meanA: meanWith, varA: varianceWith, nA: with.count,
                                               meanB: meanWithout, varB: varianceWithout, nB: without.count)
        }
    }

    /// Sleep on the days a change was kept and on the days it wasn't, for the
    /// kinds where sleep is the outcome. Nil for the others, and when no day
    /// has both.
    static func sleepComparison(_ change: WeeklyChange, days: [Day]) -> Comparison? {
        guard [.caffeineCutoff, .bedByWindow, .wakeTime].contains(change.kind) else { return nil }
        var with: [Double] = []
        var without: [Double] = []
        for day in days {
            guard let wasKept = kept(change, on: day), let hours = day.sleepHours else { continue }
            if wasKept { with.append(hours) } else { without.append(hours) }
        }
        return with.isEmpty && without.isEmpty ? nil : Comparison(with: with, without: without)
    }

    // MARK: Building the days

    /// The day's last caffeine from what the app has, most trusted first:
    /// the food app's timed entries (only when it sends real meal times),
    /// then the evening check-in. A day the food log covers with no caffeine
    /// entry counts as none, but only when that log records caffeine at all.
    /// - Parameters:
    ///   - samples: the day's caffeine entries from the food app.
    ///   - timesAreReal: false when the food app writes everything at one time of day.
    ///   - foodLogged: the food log has entries for the day.
    ///   - foodLogHasCaffeine: the food log has caffeine on some day in the window.
    public static func caffeine(samples: [(date: Date, mg: Double)], timesAreReal: Bool, evening: EveningCheckIn?,
                                foodLogged: Bool, foodLogHasCaffeine: Bool,
                                calendar: Calendar = .current) -> (lastMinutes: Int?, none: Bool) {
        if timesAreReal, let last = samples.filter({ $0.mg > 0 }).map(\.date).max() {
            let parts = calendar.dateComponents([.hour, .minute], from: last)
            return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0), false)
        }
        if let mg = evening?.caffeineMg {
            return mg > 0 ? (evening?.lastCaffeineMinutes, false) : (nil, true)
        }
        if foodLogged, foodLogHasCaffeine, !samples.contains(where: { $0.mg > 0 }) {
            return (nil, true)
        }
        return (nil, false)
    }

    /// The most vigorous minutes inside one recorded cardio workout, from the
    /// heart rate during it; nil when no workout is long enough or none has
    /// heart rate.
    /// - Parameter lifting: logged lifting sessions. A recorded workout that
    ///   overlaps one is the watch's record of that session, not cardio, so it
    ///   is left out (hard sets raise heart rate too).
    public static func cardioVigorousMinutes(workouts: [DateInterval], lifting: [DateInterval] = [],
                                             heartRate: [HeartRateSample], profile: HeartRateProfile) -> Int? {
        let cardio = workouts.filter { workout in
            workout.duration >= Double(hardSessionMinimumMinutes) * 60
                && !lifting.contains { $0.start < workout.end && workout.start < $0.end }
        }
        let counts = cardio.compactMap { workout -> Int? in
            let inside = heartRate.filter { workout.contains($0.date) }
            return inside.isEmpty ? nil : IntensityMinutes.count(inside, profile: profile).vigorous
        }
        return counts.max()
    }

    // MARK: Pieces

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func join(_ first: String?, _ second: String) -> String {
        first.map { $0 + " " + second } ?? second
    }

    /// "Protein averaged 142 g a day last week, 128 over the four weeks before."
    static func averageLine(label: String, unit: String, week: [Double], earlier: [Double]) -> String? {
        guard let now = mean(week.filter { $0 > 0 }) else { return nil }
        let before = earlier.filter { $0 > 0 }
        let tail = before.count >= minimumEarlierDays ? ", \(Longevity.whole(mean(before) ?? now)) over the four weeks before." : "."
        return "\(label) averaged \(Longevity.whole(now)) \(unit) last week" + tail
    }
}
