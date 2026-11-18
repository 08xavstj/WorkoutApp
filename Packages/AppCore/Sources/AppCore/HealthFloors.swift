import Foundation

/// The five plain health floors, in one place: weekly active minutes,
/// strength days, steps, sleep regularity and drinks.
///
/// Two screens judge the same five things: the Monday review's "Basics" row
/// (last Monday to Sunday) and the Longevity page (`Longevity`, a standing
/// view over the last weeks). Both take their lines from the constants and
/// the `...Met` functions here, so a number that passes on one cannot fail on
/// the other (docs/research/healthy-living-2026-11.md §3 item 1).
///
/// What the two legitimately do differently, and why:
/// - **The window.** The review looks at one finished week, because it
///   reviews that week. Longevity looks further back where one week is too
///   noisy to describe a person: steps over 30 days, strength days as a
///   4-week average. Same line, different stretch of time, so a good week
///   after three thin ones can tick here while Longevity still says "close".
/// - **Three bands against a tick.** Longevity also has "close" and "off".
///   The review only ticks: a floor is met or it is not, with the number
///   beside it. Its tick is exactly Longevity's "on target".
/// - **A stamina goal.** Longevity asks 300 active minutes of someone whose
///   goal is stamina (`Longevity.activeMinutesTarget`). That is a target
///   above the floor; the floor is 150 for everyone.
/// - **Which days count as strength days.** The review counts what its own
///   "Training days" line counts (gym sessions plus strength workouts the
///   watch recorded); Longevity counts sessions logged in the app.
///
/// Everything here is observational: people who met these lines lived
/// longer, which is not proof that meeting them is the cause (`evidenceNote`).
public enum HealthFloors {
    // MARK: The lines

    /// Moderate-equivalent minutes a week (moderate + 2 x vigorous): the
    /// bottom of the WHO range (Bull et al., Br J Sports Med 2020). At 150 a
    /// week all-cause mortality was 31% lower than with none, with smaller
    /// gains up to twice that (Garcia et al., Br J Sports Med 2023).
    public static let activeMinutes = IntensityMinutes.weeklyGoal

    /// Days a week with muscle-strengthening work: the WHO guideline (Bull
    /// 2020). The mortality benefit was largest at about 30-60 minutes a week
    /// (Momma et al., Br J Sports Med 2022).
    public static let strengthDays = StrengthDays.weeklyTarget

    /// Steps a day, judged as an average, never as a daily tick.
    ///
    /// One line for the review and for Longevity: 7,000. Against 2,000 a day
    /// it went with 47% lower all-cause mortality, 25% less cardiovascular
    /// disease and 38% less dementia, and the curve bends at about
    /// 5,000-7,000 (Ding et al., Lancet Public Health 2025: 31 studies from
    /// 24 cohorts). Longevity first used 8,000 under age 60, from the older
    /// and smaller pooled analysis in which risk went on falling to
    /// 8,000-10,000 in that age group (Paluch et al., Lancet Public Health
    /// 2022: 15 cohorts). That is where more stops helping, not where most of
    /// the benefit is in, and a floor is the second of those. So 7,000 is the
    /// floor at every age, and the step goal that grows with the user
    /// (`StepGoal`, which starts at 8,000 under 60) stays what it is: a goal
    /// to walk toward, never below this floor.
    public static let dailySteps = StepGoal.minimumGoal

    /// Days with a step count before a week's average is judged (app's choice).
    public static let stepsMinimumDays = 4

    /// Sleep Regularity Index, 0-100: 87, the start of the most regular
    /// fifth in the one cohort that tied regularity to mortality, where risk
    /// was lowest (`SleepRegularity.benefitIndex`; Windred et al., Sleep 2024,
    /// full text). The paper states no target; risk fell across every fifth,
    /// so this is the evidence's best, not a pass mark it sets. Shared with
    /// Longevity (`Longevity.sleepRegularityTarget`), and the UI says so.
    public static let sleepRegularity = SleepRegularity.benefitIndex

    /// Standard drinks a week: the top of the low-risk tier in Canada's 2023
    /// guidance (`AlcoholWeek.lowMax`; CCSA 2023, whose authors rate their
    /// own evidence as low quality).
    public static let drinks = AlcoholWeek.lowMax

    /// Evenings logged in a week before its drinks total is judged (app's
    /// choice; shared with Longevity). A logged zero counts.
    public static let drinksMinimumNights = 4

    // MARK: Met or not (the rule both screens use)

    public static func activeMinutesMet(moderate: Int, vigorous: Int) -> Bool {
        IntensityMinutes.Result(moderate: moderate, vigorous: vigorous).total >= activeMinutes
    }

    /// - Parameter days: days in one week, or an average over several weeks.
    public static func strengthDaysMet(_ days: Double) -> Bool { days >= Double(strengthDays) }

    /// - Parameter average: steps a day, averaged over the days counted.
    public static func stepsMet(_ average: Double) -> Bool { average >= dailySteps }

    public static func sleepRegularityMet(_ index: Int) -> Bool { index >= sleepRegularity }

    /// Fractions count up, as in `AlcoholWeek.tier`: 2.5 is past the line.
    public static func drinksMet(_ drinks: Double) -> Bool { drinks <= HealthFloors.drinks }

    // MARK: One week

    public enum Floor: String, CaseIterable, Sendable, Codable, Identifiable {
        case activeMinutes, strengthDays, steps, sleepRegularity, drinks

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .activeMinutes: IntensityMinutes.title
            case .strengthDays: "Strength days"
            case .steps: "Steps"
            case .sleepRegularity: "Sleep regularity"
            case .drinks: "Drinks"
            }
        }
    }

    /// One finished week's numbers. Nil means not known, never zero.
    public struct Week: Sendable, Equatable {
        /// From heart rate over the week's seven days.
        public var moderateMinutes: Int?
        public var vigorousMinutes: Int?
        /// Different days with a strength session.
        public var strengthDays: Int?
        /// The week's average of full days, and how many days it covers.
        public var averageSteps: Double?
        public var stepDays = 0
        /// Sleep Regularity Index, 0-100.
        public var sleepRegularity: Int?
        /// Standard drinks over the week's evenings, and how many were logged.
        public var drinks: Double?
        public var drinkNightsLogged = 0

        public init(moderateMinutes: Int? = nil, vigorousMinutes: Int? = nil, strengthDays: Int? = nil,
                    averageSteps: Double? = nil, stepDays: Int = 0, sleepRegularity: Int? = nil,
                    drinks: Double? = nil, drinkNightsLogged: Int = 0) {
            self.moderateMinutes = moderateMinutes
            self.vigorousMinutes = vigorousMinutes
            self.strengthDays = strengthDays
            self.averageSteps = averageSteps
            self.stepDays = stepDays
            self.sleepRegularity = sleepRegularity
            self.drinks = drinks
            self.drinkNightsLogged = drinkNightsLogged
        }
    }

    /// One row of the opened "Basics" list: a tick or no tick, and the number.
    public struct Check: Sendable, Equatable, Identifiable {
        public var floor: Floor
        /// "132 min", "6,400 a day", "78 of 100"; "No data" without a value.
        public var valueText: String
        /// "150 a week"
        public var targetText: String
        /// Nil when the week has no value to judge.
        public var met: Bool?
        /// A second line under the row (the vigorous line, or why there is no value).
        public var note: String?

        public var id: Floor { floor }
        public var title: String { floor.title }
    }

    public struct Result: Sendable, Equatable {
        public var checks: [Check]

        public var metCount: Int { checks.filter { $0.met == true }.count }
        /// Checks with a value to judge.
        public var knownCount: Int { checks.filter { $0.met != nil }.count }

        /// "4 of 5": met of the ones with a value. Never a percentage.
        public var summary: String {
            knownCount == 0 ? "No data yet" : "\(metCount) of \(knownCount)"
        }

        /// The first floor that has a value and isn't met, in list order: it
        /// becomes the first suggested change for the week.
        public var firstUnmet: Floor? { checks.first { $0.met == false }?.floor }

        public var unmet: [Floor] { checks.filter { $0.met == false }.map(\.floor) }

        public func check(_ floor: Floor) -> Check? { checks.first { $0.floor == floor } }
    }

    /// The week against the five floors, in list order.
    public static func assess(_ week: Week) -> Result {
        Result(checks: [activeMinutesCheck(week), strengthDaysCheck(week), stepsCheck(week),
                        sleepRegularityCheck(week), drinksCheck(week)])
    }

    /// Days with heart rate before a week's active minutes are judged: a
    /// week with fewer would undercount (app's choice).
    public static let activeMinutesMinimumDays = 5

    /// The week's numbers from its seven days, as the weekly-change report
    /// reads them (`WeeklyChangeReview.Day`), so the "Basics" row and the
    /// report on a steps or drinks change count the same days.
    /// - Parameter sleepRegularity: the week's Sleep Regularity Index, which
    ///   needs the nights' sleep intervals rather than a number per day.
    public static func week(from days: [WeeklyChangeReview.Day], sleepRegularity: Int?) -> Week {
        var week = Week(sleepRegularity: sleepRegularity)
        let withHeartRate = days.filter { $0.moderateMinutes != nil || $0.vigorousMinutes != nil }
        if withHeartRate.count >= activeMinutesMinimumDays {
            week.moderateMinutes = withHeartRate.compactMap(\.moderateMinutes).reduce(0, +)
            week.vigorousMinutes = withHeartRate.compactMap(\.vigorousMinutes).reduce(0, +)
        }
        let strength = days.compactMap(\.strengthSession)
        if !strength.isEmpty { week.strengthDays = strength.filter { $0 }.count }
        let steps = days.compactMap(\.steps).filter { $0 > 0 }
        if !steps.isEmpty {
            week.averageSteps = steps.reduce(0, +) / Double(steps.count)
            week.stepDays = steps.count
        }
        let drinks = days.compactMap(\.drinks)
        if !drinks.isEmpty {
            week.drinks = drinks.reduce(0, +)
            week.drinkNightsLogged = drinks.count
        }
        return week
    }

    /// The Sleep Regularity Index of one Monday-to-Sunday week: noon on the
    /// Sunday before through noon on the Monday after, so all seven nights
    /// that begin in the week are compared with the one before (eight
    /// noon-to-noon days, as the rolling score on the Sleep page uses eight
    /// nights).
    public static func sleepRegularity(asleep: [DateInterval], weekStart: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: weekStart))
            .flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
        guard let start else { return nil }
        return SleepRegularity.score(asleep: asleep, start: start, days: 8, calendar: calendar)
    }

    /// One sentence for under the opened list.
    public static let evidenceNote = "These lines come from the WHO guideline and large cohort studies: people who met them lived longer. That is a link, not proof that meeting them is the cause."

    // MARK: Checks

    static func activeMinutesCheck(_ week: Week) -> Check {
        let target = "\(activeMinutes) a week"
        guard let moderate = week.moderateMinutes, let vigorous = week.vigorousMinutes else {
            return Check(floor: .activeMinutes, valueText: "No data", targetText: target, met: nil,
                         note: "Needs heart rate from your watch.")
        }
        let total = IntensityMinutes.Result(moderate: moderate, vigorous: vigorous).total
        return Check(floor: .activeMinutes, valueText: "\(total) min", targetText: target,
                     met: activeMinutesMet(moderate: moderate, vigorous: vigorous),
                     note: IntensityMinutes.vigorousLine(vigorous))
    }

    static func strengthDaysCheck(_ week: Week) -> Check {
        let target = "\(strengthDays) a week"
        guard let days = week.strengthDays else {
            return Check(floor: .strengthDays, valueText: "No data", targetText: target, met: nil, note: nil)
        }
        return Check(floor: .strengthDays, valueText: "\(days)", targetText: target,
                     met: strengthDaysMet(Double(days)), note: nil)
    }

    static func stepsCheck(_ week: Week) -> Check {
        let target = "\(Longevity.grouped(dailySteps)) a day, as the week's average"
        guard let average = week.averageSteps, average > 0, week.stepDays >= stepsMinimumDays else {
            return Check(floor: .steps, valueText: "No data", targetText: target, met: nil,
                         note: "Needs \(stepsMinimumDays) days of step counts.")
        }
        return Check(floor: .steps, valueText: "\(Longevity.grouped(average)) a day", targetText: target,
                     met: stepsMet(average), note: nil)
    }

    static func sleepRegularityCheck(_ week: Week) -> Check {
        // 87 starts the most regular fifth, where risk was lowest; 81 was typical (Windred 2024).
        let target = "\(sleepRegularity)+, where risk was lowest in one large study (\(SleepRegularity.typicalIndex) is typical)"
        guard let index = week.sleepRegularity else {
            return Check(floor: .sleepRegularity, valueText: "No data", targetText: target, met: nil,
                         note: "Needs a few nights of sleep from your watch or ring.")
        }
        return Check(floor: .sleepRegularity, valueText: "\(index) of 100", targetText: target,
                     met: sleepRegularityMet(index), note: nil)
    }

    static func drinksCheck(_ week: Week) -> Check {
        let target = "\(Longevity.one(drinks)) or fewer a week (Canada's low-risk line)"
        guard let total = week.drinks, total >= 0, week.drinkNightsLogged >= drinksMinimumNights else {
            return Check(floor: .drinks, valueText: "No data", targetText: target, met: nil,
                         note: "Needs \(drinksMinimumNights) evenings logged. Zero counts.")
        }
        return Check(floor: .drinks, valueText: Longevity.one(total), targetText: target, met: drinksMet(total),
                     note: week.drinkNightsLogged < AlcoholWeek.nights ? "\(week.drinkNightsLogged) of \(AlcoholWeek.nights) evenings logged." : nil)
    }
}

// MARK: - The vigorous line

extension IntensityMinutes {
    /// Vigorous minutes a week that went with lower mortality in adults
    /// wearing a wrist accelerometer for a week: about 15 a week for all-cause
    /// and cancer mortality (hazard ratios 0.82 and 0.84) and about 19 for
    /// cardiovascular mortality (0.60), against 2 minutes a week; "15-20
    /// minutes a week were associated with a 16-40% lower mortality hazard
    /// ratio" (Ahmadi et al., Eur Heart J 2022;43:4801-4814; 71,893 UK
    /// Biobank adults, median age 62.5; abstract checked on PubMed November
    /// 2026). One cohort, observational, and its vigorous minutes came from
    /// wrist movement, not from heart rate as the app's do. So this is a
    /// reference to read the count against, not a goal the app scores.
    public static let vigorousReferenceMinutes = 15...20

    /// Where the same study's risk curve was lowest: 53.6 minutes a week
    /// (95% CI 50.5-56.7; hazard ratio 0.64), rounded.
    public static let vigorousLowestRiskMinutes = 54

    /// "15-20 a week went with 16-40% lower mortality in one wearable cohort
    /// (Ahmadi 2022). A link, not proof."
    public static let vigorousReferenceNote = "\(vigorousReferenceMinutes.lowerBound)-\(vigorousReferenceMinutes.upperBound) a week went with 16-40% lower mortality in one wearable cohort (Ahmadi 2022). A link, not proof."

    /// The vigorous count on its own line, wherever weekly active minutes
    /// show: "Vigorous: 12 min. 15-20 a week went with ...".
    public static func vigorousLine(_ vigorous: Int) -> String {
        "Vigorous: \(vigorous) min. " + vigorousReferenceNote
    }
}
