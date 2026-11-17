import Foundation
import Testing
@testable import AppCore

struct DailyInsightsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// 8 am on day `n` of the simulation.
    private func day(_ n: Int) -> Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000)).addingTimeInterval(Double(n) * 86_400 + 8 * 3_600)
    }

    /// Repeatable noise in -1...1.
    private func noise(_ seed: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 7_919 &+ salt &* 104_729 &+ 12_345)
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x = x &* 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return Double(x % 20_001) / 10_000 - 1
    }

    private func series(through last: Int, from first: Int = 0, _ value: (Int) -> Double?) -> [DayValue] {
        guard last >= first else { return [] }
        return (first...last).compactMap { n in value(n).map { DayValue(date: day(n), value: $0) } }
    }

    // MARK: A simulated 17 weeks

    /// A lifter's four months: steady at first, a short-sleep stretch
    /// (days 40-50), a rough ten days with a raised heart rate and more
    /// drinks (60-70), a desk-bound stretch (75-85), a fitter last month and
    /// two weeks off lifting (100-113).
    private func inputs(on n: Int) -> DailyInsights.Inputs {
        var i = DailyInsights.Inputs(day: day(n), calendar: calendar)
        i.restingHeartRate = series(through: n) { d in
            54 + noise(d, 1) * 1.5 + ((60...70).contains(d) ? 5 : 0) - (d >= 90 ? min(3, Double(d - 90) * 0.3) : 0)
        }
        i.hrv = series(through: n) { d in 50 + noise(d, 2) * 5 - ((60...70).contains(d) ? 9 : 0) }
        i.sleepHours = series(through: n) { d in 7.2 + noise(d, 3) * 0.6 - ((40...50).contains(d) ? 0.9 : 0) }
        i.sleepRegularity = n >= 6 ? ((40...52).contains(n) ? 71 : 82) + Int((noise(n, 4) * 1.4).rounded()) : nil
        i.steps = series(through: n - 1) { d in (75...85).contains(d) ? 5_200 + noise(d, 5) * 600 : 9_000 + noise(d, 5) * 1_500 }
        i.vo2Max = series(through: n) { d in d % 7 == 2 ? 44 + Double(d) * 0.025 + noise(d, 6) * 0.3 : nil }
        i.activeMinutes = series(through: n) { d in (75...85).contains(d) ? 7 + noise(d, 7) * 3 : 26 + noise(d, 7) * 8 }
        i.strengthSessions = (0...n).filter { [0, 1, 3, 4].contains($0 % 7) && !(100...113).contains($0) }.map(day)
        i.respiratoryRate = series(through: n) { d in 14.5 + noise(d, 8) * 0.3 }
        i.bloodOxygen = series(through: n) { d in 96 + noise(d, 9) * 0.6 }
        i.proteinGrams = series(through: n) { d in (20...34).contains(d) ? 118 + noise(d, 10) * 10 : 158 + noise(d, 10) * 14 }
        i.proteinTargetGrams = 160
        i.fiberGrams = n < 7 ? nil : (n >= 55 ? 17 : 22.5) + noise(n, 11) * 0.8
        i.drinks = series(through: n) { d in
            if (60...67).contains(d) { return d % 2 == 0 ? 3 : 1 }
            return [4, 5].contains(d % 7) ? 2 : 0
        }
        i.mood = series(through: n) { d in 0.3 + noise(d, 12) * 0.2 - ((60...70).contains(d) ? 0.4 : 0) }
        i.headphoneBudgetPercent = (88...94).contains(n) ? 120 : 45
        if n >= 30 {
            i.pattern = DailyInsights.Pattern(sentence: "HRV is 9% lower after 2 or more drinks", daysWith: 9, daysWithout: 21)
        }
        return i
    }

    private func simulate(days: Int = 120) -> [DailyInsights.Feed] {
        var state = DailyInsights.State()
        return (0..<days).map { n in
            let result = DailyInsights.evaluate(inputs(on: n), state: state)
            state = result.state
            return result.feed
        }
    }

    @Test func theFeedIsCappedAndNeverCrowdsOneCategoryOrTone() {
        for feed in simulate() {
            #expect(feed.today.count <= DailyInsights.maxShown)
            #expect(Set(feed.today.map(\.id)).count == feed.today.count)
            for category in DailyInsights.Category.allCases {
                #expect(feed.today.filter { $0.category == category }.count <= DailyInsights.maxPerCategory)
            }
            #expect(feed.today.filter { $0.tone == .watch }.count <= DailyInsights.maxWatch)
            #expect(feed.forYou.count <= DailyInsights.maxForYou)
        }
    }

    @Test func noInsightRepeatsDailyOrFlickers() {
        let feeds = simulate()
        var shownDays: [String: [(day: Int, tone: DailyInsights.Tone)]] = [:]
        for (n, feed) in feeds.enumerated() {
            for insight in feed.today where insight.id != "steady" {
                shownDays[insight.id, default: []].append((n, insight.tone))
            }
        }
        #expect(!shownDays.isEmpty)
        for (id, days) in shownDays {
            var run = 1
            for (previous, current) in zip(days, days.dropFirst()) {
                let gap = current.day - previous.day
                if gap == 1, current.tone == previous.tone {
                    run += 1
                    #expect(run <= DailyInsights.maxRunDays, "\(id) ran \(run) days")
                } else {
                    run = 1
                    // Back after a break only once it has rested, unless it changed direction.
                    #expect(gap >= DailyInsights.restDays || current.tone != previous.tone, "\(id) came back after \(gap) days")
                }
            }
        }
    }

    @Test func theFeedIsVariedAndFollowsWhatHappened() {
        let feeds = simulate()
        let ids = Set(feeds.flatMap { $0.today.map(\.id) })
        let categories = Set(feeds.flatMap { $0.today.map(\.category) })
        #expect(ids.count >= 8, "\(ids.sorted())")
        #expect(categories.count >= 6)
        // No single line makes up most of what's shown.
        let total = feeds.reduce(0) { $0 + $1.today.count }
        for id in ids {
            let count = feeds.reduce(0) { $0 + $1.today.filter { $0.id == id }.count }
            #expect(Double(count) / Double(total) < 0.4, "\(id): \(count) of \(total)")
        }
        func shown(_ id: String, _ tone: DailyInsights.Tone, in range: ClosedRange<Int>) -> Bool {
            range.contains { n in feeds[n].today.contains { $0.id == id && $0.tone == tone } }
        }
        // Each stretch of the simulation shows up, in the right direction.
        #expect(shown("proteinWeek", .watch, in: 24...40))
        #expect(shown("sleepWeek", .watch, in: 43...54))
        #expect(shown("sleepRegularity", .watch, in: 40...54))
        #expect(shown("rhrTrend", .watch, in: 62...74) || shown("hrvTrend", .watch, in: 62...74))
        #expect(shown("alcoholWeek", .watch, in: 62...72))
        #expect(shown("stepsWeek", .watch, in: 78...90))
        #expect(shown("activeMinutes", .watch, in: 78...90))
        #expect(shown("hearing", .watch, in: 88...96))
        #expect(shown("rhrTrend", .good, in: 93...112))
        #expect(shown("strengthWeeks", .watch, in: 108...119))
        #expect(shown("strengthWeeks", .good, in: 28...99))
        #expect(shown("fiberWeek", .watch, in: 55...70))
        // And never the wrong way round.
        #expect(!shown("stepsWeek", .good, in: 76...86))
        #expect(!shown("sleepWeek", .good, in: 41...50))
        #expect(!shown("rhrTrend", .good, in: 61...70))
    }

    @Test func theFeedIsNeverEmptyWithoutAReason() {
        let feeds = simulate()
        for (n, feed) in feeds.enumerated() {
            #expect(!feed.today.isEmpty || feed.emptyReason != nil, "day \(n)")
            #expect(feed.today.isEmpty || feed.emptyReason == nil, "day \(n)")
        }
        // Once there's a baseline, most days have something to say.
        let later = feeds[35...]
        let withContent = later.filter { !$0.today.isEmpty }.count
        #expect(Double(withContent) / Double(later.count) >= 0.9, "\(withContent) of \(later.count)")
    }

    @Test func theFeedNeverContradictsItself() {
        for (n, feed) in simulate().enumerated() {
            let byID = Dictionary(uniqueKeysWithValues: feed.today.map { ($0.id, $0) })
            // Resting heart rate and HRV never point opposite ways side by side.
            if let rhr = byID["rhrTrend"], let hrv = byID["hrvTrend"] {
                #expect(rhr.tone == hrv.tone, "day \(n)")
            }
            // "A steady week" only ever stands alone.
            if byID["steady"] != nil {
                #expect(feed.today.count == 1, "day \(n)")
            }
            // "For you" doesn't repeat a line shown above it.
            let covered = Set(feed.today.compactMap { DailyInsights.measureForInsight[$0.id] })
            #expect(feed.forYou.allSatisfy { $0.measure.map { !covered.contains($0) } ?? true })
            // Every line says what it is compared with; none makes a medical claim.
            for insight in feed.today {
                #expect(!insight.comparison.isEmpty)
                let text = (insight.title + " " + insight.comparison + " " + (insight.action ?? "")).lowercased()
                for word in ["diagnos", "disease", "you have", "risk of death", "adds years"] {
                    #expect(!text.contains(word), "\(insight.id): \(word)")
                }
            }
        }
    }

    @Test func evaluatingTwiceOnOneDayChangesNothing() {
        var state = DailyInsights.State()
        for n in 0..<80 {
            let first = DailyInsights.evaluate(inputs(on: n), state: state)
            let second = DailyInsights.evaluate(inputs(on: n), state: first.state)
            #expect(second.feed == first.feed, "day \(n)")
            #expect(second.state == first.state, "day \(n)")
            state = second.state
        }
    }

    @Test func stateSurvivesEncoding() throws {
        var state = DailyInsights.State()
        for n in 0..<50 { state = DailyInsights.evaluate(inputs(on: n), state: state).state }
        #expect(!state.entries.isEmpty)
        let decoded = try JSONDecoder().decode(DailyInsights.State.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    // MARK: Minimum data

    @Test func aFewDaysOfDataGiveNoTrendsAndSayWhy() {
        var i = DailyInsights.Inputs(day: day(5), calendar: calendar)
        i.restingHeartRate = series(through: 5) { _ in 54 }
        i.hrv = series(through: 5) { d in d == 5 ? 80 : 50 }
        i.sleepHours = series(through: 5) { _ in 5 }
        i.steps = series(through: 4) { _ in 2_000 }
        let feed = DailyInsights.evaluate(i).feed
        #expect(feed.today.isEmpty)
        #expect(feed.emptyReason?.contains("three weeks") == true)
        #expect(DailyInsights.evaluate(DailyInsights.Inputs(day: day(0), calendar: calendar)).feed.emptyReason != nil)
    }

    @Test func aSteadyPersonGetsOneSteadyLineNamingOnlyQuietMeasures() {
        var i = DailyInsights.Inputs(day: day(60), calendar: calendar)
        i.restingHeartRate = series(through: 60) { d in 54 + noise(d, 1) }
        i.hrv = series(through: 60) { d in 50 + noise(d, 2) * 4 }
        i.sleepHours = series(through: 60) { d in 7.3 + noise(d, 3) * 0.4 }
        let feed = DailyInsights.evaluate(i).feed
        #expect(feed.today.map(\.id) == ["steady"])
        #expect(feed.today.first?.comparison.hasPrefix("Resting heart rate 54 bpm, HRV") == true)
        #expect(feed.today.first?.comparison.contains("sleep 7 h") == true)

        // A raised heart rate that is resting after its three days isn't called steady.
        i.restingHeartRate = series(through: 60) { d in d >= 54 ? 60 : 54 + noise(d, 1) }
        let resting = DailyInsights.State(entries: ["rhrTrend": .init(variant: "up", lastActive: day(59), lastShown: day(58), runDays: 3)])
        let quiet = DailyInsights.evaluate(i, state: resting).feed
        #expect(!quiet.today.contains { $0.id == "rhrTrend" })
        #expect(quiet.today.first?.id == "steady")
        #expect(quiet.today.first?.comparison.lowercased().contains("resting heart rate") == false)
    }

    // MARK: Hysteresis and cooldown

    /// Baseline alternating 53 and 55 (mean 54, SD about 1), then a week at `recent`.
    private func heartRateInputs(recent: Double) -> DailyInsights.Inputs {
        var i = DailyInsights.Inputs(day: day(40), calendar: calendar)
        i.restingHeartRate = series(through: 40) { d in d > 33 ? recent : (d % 2 == 0 ? 53 : 55) }
        return i
    }

    @Test func aTrendTurnsOnAtOneSizeAndOffAtHalfOfIt() {
        // Up 2.5 bpm: over both the 2 bpm floor and one standard deviation.
        let on = DailyInsights.evaluate(heartRateInputs(recent: 56.5))
        #expect(on.feed.today.first?.id == "rhrTrend")
        #expect(on.feed.today.first?.title == "Resting heart rate is up 3 bpm" || on.feed.today.first?.title == "Resting heart rate is up 2 bpm")
        // Up 1.3 bpm: not enough to start a line...
        #expect(!DailyInsights.evaluate(heartRateInputs(recent: 55.3)).feed.today.contains { $0.id == "rhrTrend" })
        // ...but enough to keep one that is already showing.
        let stays = DailyInsights.evaluate(heartRateInputs(recent: 55.3), state: on.state)
        #expect(stays.feed.today.contains { $0.id == "rhrTrend" })
        // Under half the size it goes.
        #expect(!DailyInsights.evaluate(heartRateInputs(recent: 54.6), state: on.state).feed.today.contains { $0.id == "rhrTrend" })
    }

    @Test func aLineShowsThreeDaysThenRestsAWeek() {
        var state = DailyInsights.State()
        var shown: [Bool] = []
        for offset in 0..<12 {
            var i = DailyInsights.Inputs(day: day(40 + offset), calendar: calendar)
            i.headphoneBudgetPercent = 130
            let result = DailyInsights.evaluate(i, state: state)
            state = result.state
            shown.append(result.feed.today.contains { $0.id == "hearing" })
            if !shown[offset] { #expect(result.feed.emptyReason?.hasPrefix("Nothing new") == true) }
        }
        #expect(shown == [true, true, true, false, false, false, false, false, false, true, true, true])
    }

    @Test func fixedLinesHaveHysteresisToo() {
        func feed(_ change: (inout DailyInsights.Inputs) -> Void, active: (id: String, variant: String)? = nil) -> DailyInsights.Feed {
            var i = DailyInsights.Inputs(day: day(40), calendar: calendar)
            change(&i)
            var state = DailyInsights.State()
            if let active { state.entries[active.id] = .init(variant: active.variant, lastActive: day(39), lastShown: day(39), runDays: 1) }
            return DailyInsights.evaluate(i, state: state).feed
        }
        // Sleep regularity: low under 74, and it stays until 78.
        #expect(feed { $0.sleepRegularity = 73 }.today.first?.tone == .watch)
        #expect(feed { $0.sleepRegularity = 76 }.today.isEmpty)
        #expect(feed({ $0.sleepRegularity = 76 }, active: ("sleepRegularity", "low")).today.first?.tone == .watch)
        #expect(feed({ $0.sleepRegularity = 78 }, active: ("sleepRegularity", "low")).today.isEmpty)
        #expect(feed { $0.sleepRegularity = 88 }.today.first?.tone == .good)
        // Fibre: low under 20 g, on target from 25 g, nothing in between.
        #expect(feed { $0.fiberGrams = 19 }.today.first?.title == "Fibre is low: 19 g a day")
        #expect(feed { $0.fiberGrams = 22.5 }.today.isEmpty)
        #expect(feed({ $0.fiberGrams = 21 }, active: ("fiberWeek", "low")).today.first?.tone == .watch)
        #expect(feed { $0.fiberGrams = 26 }.today.first?.tone == .good)
        // Headphones: over at 100%, off again under 85%.
        #expect(feed { $0.headphoneBudgetPercent = 99 }.today.isEmpty)
        #expect(feed({ $0.headphoneBudgetPercent = 90 }, active: ("hearing", "over")).today.first?.id == "hearing")
        #expect(feed({ $0.headphoneBudgetPercent = 84 }, active: ("hearing", "over")).today.isEmpty)
    }

    @Test func mixedRecoverySignalsKeepOnlyTheLargerOne() {
        var i = DailyInsights.Inputs(day: day(40), calendar: calendar)
        // Heart rate clearly up (worse), HRV a little up (better).
        i.restingHeartRate = series(through: 40) { d in d > 33 ? 60 : (d % 2 == 0 ? 53 : 55) }
        i.hrv = series(through: 40) { d in d > 33 ? 56 : (d % 2 == 0 ? 46 : 54) }
        let ids = DailyInsights.evaluate(i).feed.today.map(\.id)
        #expect(ids.contains("rhrTrend"))
        #expect(!ids.contains("hrvTrend"))
    }

    // MARK: For you and the coach

    private var assessment: Longevity.Assessment {
        var inputs = Longevity.Inputs(age: 30, sex: .male, goals: Goals(weight: .maintain, focuses: [.muscle]))
        inputs.dailySteps = 9_000
        inputs.sleepHours = 6.5
        inputs.sleepNights = 14
        inputs.sleepRegularity = 78
        inputs.fiberGrams = 18
        inputs.restingHeartRate = 62
        return Longevity.assess(inputs)
    }

    @Test func forYouLeadsWithTheLongevityFocusAndHoldsForAWeek() {
        var lists: [[String]] = []
        for offset in 0..<7 {
            var i = DailyInsights.Inputs(day: day(40 + offset), calendar: calendar)
            i.longevity = assessment
            let feed = DailyInsights.evaluate(i).feed
            #expect(feed.forYou.count == 2)
            #expect(feed.forYou.first?.measure == .fiber)
            #expect(feed.forYou.first?.title == "Fibre: 18 g a day")
            #expect(feed.forYou.first?.detail == assessment.measure(.fiber)?.nextStep)
            lists.append(feed.forYou.map(\.id))
        }
        // Seven days straddle at most one week boundary.
        #expect(Set(lists).count <= 2)
        // Over two months the second slot visits each of the other close measures.
        var second: Set<String> = []
        for offset in stride(from: 0, to: 63, by: 7) {
            var i = DailyInsights.Inputs(day: day(40 + offset), calendar: calendar)
            i.longevity = assessment
            if let id = DailyInsights.evaluate(i).feed.forYou.last?.id { second.insert(id) }
        }
        #expect(second == ["sleepDuration", "sleepRegularity", "restingHeartRate"])
    }

    @Test func forYouSkipsWhatTodayAlreadySaysAndOffersMissingMeasures() {
        var i = DailyInsights.Inputs(day: day(40), calendar: calendar)
        i.longevity = assessment
        i.fiberGrams = 18
        let feed = DailyInsights.evaluate(i).feed
        #expect(feed.today.map(\.id) == ["fiberWeek"])
        #expect(!feed.forYou.contains { $0.measure == .fiber })

        // Everything measured on target: a missing strong-evidence measure, by name.
        var good = Longevity.Inputs(age: 30, sex: .male)
        good.dailySteps = 10_000
        var j = DailyInsights.Inputs(day: day(40), calendar: calendar)
        j.longevity = Longevity.assess(good)
        let offered = DailyInsights.evaluate(j).feed.forYou
        #expect(offered.count == 1)
        #expect(["Add a waist measurement", "Add a blood pressure check", "Get a VO₂ max reading"].contains(offered.first?.title ?? ""))

        // Nothing missing either: one line saying so. No assessment: nothing.
        good.vo2Max = 55
        good.waistToHeight = 0.45
        good.systolic = 115
        good.diastolic = 72
        good.bloodPressureIsHomeAverage = true
        j.longevity = Longevity.assess(good)
        #expect(DailyInsights.evaluate(j).feed.forYou.map(\.id) == ["allOnTarget"])
        j.longevity = nil
        #expect(DailyInsights.evaluate(j).feed.forYou.isEmpty)
    }

    @Test func coachSummaryCarriesTheTopLines() {
        let feed = DailyInsights.evaluate(heartRateInputs(recent: 58)).feed
        let summary = feed.coachSummary()
        #expect(summary?.contains("Resting heart rate is up 4 bpm") == true)
        #expect(summary?.contains("against 54") == true)
        #expect(DailyInsights.Feed().coachSummary() == nil)
    }
}
