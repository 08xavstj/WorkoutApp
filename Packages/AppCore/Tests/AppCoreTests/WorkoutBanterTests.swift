import Foundation
import Testing
@testable import AppCore

struct WorkoutBanterTests {
    typealias Facts = WorkoutBanter.Facts

    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2027-01-11 is a Monday.
    func date(day: Int = 11, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour))!
    }

    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = parts.month! < 10 ? "0\(parts.month!)" : "\(parts.month!)"
        let day = parts.day! < 10 ? "0\(parts.day!)" : "\(parts.day!)"
        return "\(parts.year!)-\(month)-\(day)"
    }

    /// A planned session with nothing else known.
    func base(_ name: String = "Upper A") -> Facts {
        var facts = Facts()
        facts.sessionName = name
        facts.sessionMinutes = 60
        facts.shortMinutes = 15
        facts.leadMinutes = 30
        facts.hour = 13
        facts.weekday = 4
        return facts
    }

    /// Facts under which every slot has a value and `situation` fits.
    func rich(for situation: WorkoutBanter.Situation, unit: LoadUnit = .kg) -> Facts {
        var facts = base()
        facts.unit = unit
        facts.sessionsDone = 2
        facts.sessionsPlanned = 5
        facts.weeksInARow = 6
        facts.daysSinceLastSession = 5
        facts.lift = WorkoutBanter.Lift(name: "Bench Press", lastWeightKg: 82.5, lastReps: 5, nextWeightKg: 85, weeksAtWeight: nil, nearBest: true)
        facts.neglected = WorkoutBanter.Neglected(muscle: "hamstrings", days: 9)
        facts.standout = WorkoutBanter.Standout(recordLift: "Back Squat", volumeKg: 6240, daysAgo: 2)
        facts.painArea = "lower back"
        switch situation {
        case .stuckLift: facts.lift?.weeksAtWeight = 3
        case .longBreak: facts.daysSinceLastSession = 30
        case .weekStart:
            facts.sessionsDone = 0
            facts.daysLeftInWeek = 6
        case .lastOfWeek: facts.sessionsDone = 4
        case .afterVolume: facts.standout?.recordLift = nil
        case .deload: facts.isDeloadWeek = true
        case .highRecovery: facts.recovery = .high
        case .morning: facts.hour = 7
        case .evening: facts.hour = 19
        case .monday: facts.weekday = 2
        case .friday: facts.weekday = 6
        case .weekend: facts.weekday = 7
        case .lastCall: facts.lastCall = true
        case .lowRecovery: facts.recovery = .low
        case .illness: facts.illnessFlagged = true
        case .restMode: facts.restMode = true
        case .restDay: facts.isRestDay = true
        case .keepPlain: facts.keepPlain = true
        default: break
        }
        if situation != .pain { facts.painArea = nil }
        return facts
    }

    // MARK: The library

    @Test func libraryIsLargeAndSpreadAcrossRegistersAndSituations() {
        let playful = WorkoutBanterLibrary.playful
        #expect(playful.count >= 150, "\(playful.count) playful lines")
        #expect(Set(WorkoutBanterLibrary.all.map(\.id)).count == WorkoutBanterLibrary.all.count, "ids are unique")
        #expect(Set(WorkoutBanterLibrary.all.map(\.template)).count == WorkoutBanterLibrary.all.count, "no line is written twice")
        for register in WorkoutBanter.Register.allCases where register != .plain {
            #expect(playful.filter { $0.register == register }.count >= 15, "\(register)")
        }
        let cautions = Set(WorkoutBanter.Caution.allCases.map(\.situation))
        for situation in WorkoutBanter.Situation.allCases {
            let lines = WorkoutBanterLibrary.all.filter { $0.situation == situation }
            if cautions.contains(situation) {
                #expect(lines.count >= 3, "\(situation)")
                #expect(lines.allSatisfy { $0.register == .plain }, "\(situation) is plain only")
            } else {
                let comic = lines.filter { $0.register != .plain }
                #expect(comic.count >= 5, "\(situation): \(comic.count) playful lines")
                #expect(Set(comic.map(\.register)).count >= 4, "\(situation) has several registers")
            }
        }
    }

    @Test(arguments: WorkoutBanterLibrary.all)
    func everyLinePassesTheGuardrails(line: WorkoutBanter.Line) throws {
        #expect(WorkoutBanterGuard.templateProblems(line).isEmpty, "\(line.id): \(WorkoutBanterGuard.templateProblems(line))")
        #expect(!line.template.contains("  ") && line.template == line.template.trimmingCharacters(in: .whitespaces))
        #expect(".!?)'".contains(line.template.last!), "\(line.id) ends a sentence")
        // "a Upper A", "an Legs": a name after an article reads wrong for half the names.
        #expect(line.template.firstMatch(of: /\b[Aa]n? \{(session|lift|Lift|muscle|standoutLift|pain)\}/) == nil, "\(line.id)")
        for unit in LoadUnit.allCases {
            let facts = rich(for: line.situation, unit: unit)
            #expect(WorkoutBanter.situations(for: facts).contains(line.situation), "\(line.id)")
            let text = try #require(line.render(facts), "\(line.id) renders")
            #expect(WorkoutBanterGuard.problems(in: text, facts: facts).isEmpty,
                    "\(line.id): \(WorkoutBanterGuard.problems(in: text, facts: facts)) in \(text)")
            #expect(text.count <= WorkoutBanter.maxBodyCharacters, "\(line.id) is \(text.count) characters")
        }
    }

    @Test func lastCallLinesSayItOnceKindlyAndHowToComeBack() {
        let lines = WorkoutBanterLibrary.all.filter { $0.situation == .lastCall }
        #expect(lines.count >= 8)
        for line in lines {
            let text = line.template.lowercased()
            #expect(["quiet", "pause", "silent", "last", "rests"].contains { text.contains($0) }, "\(line.id)")
            #expect(text.contains("train") && text.contains("open"), "\(line.id) says how reminders come back")
        }
    }

    @Test func cautionLinesNeverPushAndAlwaysAllowRest() {
        for caution in WorkoutBanter.Caution.allCases {
            for line in WorkoutBanterLibrary.all where line.situation == caution.situation {
                let text = line.template.lowercased()
                #expect(!WorkoutBanterGuard.pushPhrases.contains { text.contains($0) }, "\(line.id)")
                #expect(!Set(CoachIntent.words(text)).isDisjoint(with: WorkoutBanterGuard.restWords), "\(line.id)")
                #expect(!text.contains("!"), "\(line.id)")
            }
        }
    }

    // MARK: Golden lines

    @Test func goldenLinesInKilogramsAndPounds() throws {
        func line(_ id: String) throws -> WorkoutBanter.Line {
            try #require(WorkoutBanterLibrary.all.first { $0.id == id })
        }
        var stuck = rich(for: .stuckLift)
        #expect(try line("st01").render(stuck)
            == "Your bench press has been at 82.5 kg for 3 weeks. It's started telling people it's a personality trait.")
        stuck.unit = .lb
        #expect(try line("st02").render(stuck) == "Bench Press: 181.9 lb, 3 weeks running. By now the plates know each other's birthdays.")
        #expect(try line("nr01").render(rich(for: .nearRecord))
            == "Your bench press did 82.5 kg × 5 last time. 85 kg is right there, looking at you. It's not blinking.")
        #expect(try line("pl01").render(base("Legs")) == "Legs in 30 minutes. The barbell has cleared its schedule.")
        #expect(try line("wp02").render(rich(for: .weekProgress))
            == "2 down, 3 to go this week. Not that anyone's counting. I'm counting. Upper A in 30 minutes.")
        #expect(try line("av01").render(rich(for: .afterVolume))
            == "Last session you moved 6,240 kg in total. The floor has confirmed it all came back down.")
        #expect(try line("cb01").render(rich(for: .comeback)) == "It's been 5 days. The barbell hasn't moved. To be fair, that's its whole thing.")
        #expect(try line("cp01").render(rich(for: .pain))
            == "Pain is logged for your lower back. Leave out or swap what aggravates it; Upper A can also wait.")
    }

    @Test func weightsAreWrittenInTheOwnersUnit() {
        #expect(WorkoutBanter.weightText(82.5, unit: .kg) == "82.5 kg")
        #expect(WorkoutBanter.weightText(100, unit: .kg) == "100 kg")
        #expect(WorkoutBanter.weightText(20.4117, unit: .lb) == "45 lb")
        #expect(WorkoutBanter.weightText(102.058, unit: .lb) == "225 lb")
        #expect(WorkoutBanter.grouped(6240) == "6,240")
        #expect(WorkoutBanter.grouped(999) == "999")
        #expect(WorkoutBanter.grouped(1_234_567) == "1,234,567")
    }

    // MARK: Situations

    @Test func situationsFollowTheFacts() {
        #expect(WorkoutBanter.situations(for: base()) == [.planned, .shortOption])
        #expect(WorkoutBanter.situations(for: rich(for: .stuckLift)).contains(.stuckLift))
        #expect(!WorkoutBanter.situations(for: rich(for: .stuckLift)).contains(.nearRecord))
        var facts = rich(for: .nearRecord)
        #expect(WorkoutBanter.situations(for: facts).isSuperset(of: [.nearRecord, .comeback, .weekProgress, .weeksInARow, .neglectedMuscle, .afterRecord]))
        // A deload week is for lighter loads: no line asks for a record.
        facts.isDeloadWeek = true
        facts.recovery = .high
        #expect(WorkoutBanter.situations(for: facts).isDisjoint(with: [.nearRecord, .stuckLift, .highRecovery]))
        #expect(WorkoutBanter.situations(for: facts).contains(.deload))
        // Two or three days off is ordinary rest; a long break is never counted out loud.
        facts.daysSinceLastSession = 3
        #expect(WorkoutBanter.situations(for: facts).isDisjoint(with: [.comeback, .longBreak]))
        facts.daysSinceLastSession = 40
        #expect(WorkoutBanter.situations(for: facts).contains(.longBreak))
        #expect(WorkoutBanterLibrary.all.filter { $0.situation == .longBreak }.allSatisfy { !$0.slots.contains(.days) })
        // A record from two weeks ago is no longer news.
        facts.standout?.daysAgo = 14
        #expect(!WorkoutBanter.situations(for: facts).contains(.afterRecord))
    }

    @Test(arguments: WorkoutBanter.Caution.allCases)
    func cautionStatesGetOnePlainKindLineWhateverTheTone(caution: WorkoutBanter.Caution) {
        let facts = rich(for: caution.situation)
        #expect(facts.caution == caution)
        #expect(WorkoutBanter.situations(for: facts) == [caution.situation])
        for tone in WorkoutBanter.Tone.allCases {
            for seed in 0..<20 {
                let pick = WorkoutBanter.pick(facts: facts, tone: tone, history: .init(), seed: UInt64(seed))
                #expect(pick.register == WorkoutBanter.Register.plain.rawValue)
                #expect(pick.situation == caution.situation.rawValue)
                #expect(WorkoutBanterGuard.problems(in: pick.text, facts: facts).isEmpty, "\(pick.text)")
            }
        }
    }

    @Test func theMostSeriousCautionWins() {
        var facts = base()
        facts.isRestDay = true
        facts.recovery = .low
        #expect(facts.caution == .lowRecovery)
        facts.painArea = ""
        #expect(facts.caution == .pain)
        // No area known: only the lines that don't name one.
        #expect(WorkoutBanter.eligible(facts: facts, tone: .playful).allSatisfy { !$0.line.slots.contains(.pain) })
        #expect(!WorkoutBanter.eligible(facts: facts, tone: .playful).isEmpty)
        facts.illnessFlagged = true
        #expect(facts.caution == .illness)
        facts.restMode = true
        #expect(facts.caution == .restMode)
    }

    // MARK: Picking

    @Test func pickIsDeterministicForASeedAndHistory() {
        let facts = rich(for: .nearRecord)
        var history = WorkoutBanter.History()
        for day in 0..<10 {
            let seed = WorkoutBanter.seed(for: "2027-01-\(day)")
            let first = WorkoutBanter.pick(facts: facts, tone: .playful, history: history, seed: seed)
            let second = WorkoutBanter.pick(facts: facts, tone: .playful, history: history, seed: seed)
            #expect(first == second)
            history.record(first.entry(dayKey: "2027-01-\(day)"))
        }
        #expect(WorkoutBanter.seed(for: "2027-01-11") == WorkoutBanter.seed(for: "2027-01-11"))
        #expect(WorkoutBanter.seed(for: "2027-01-11") != WorkoutBanter.seed(for: "2027-01-12"))
        let picks = Set((0..<40).map { WorkoutBanter.pick(facts: facts, tone: .playful, history: .init(), seed: UInt64($0)).lineID })
        #expect(picks.count > 10, "different seeds give different lines")
    }

    @Test func onlyLinesWhoseFactsArePresentAreUsed() {
        var facts = Facts()
        facts.sessionName = "Legs"
        // No lead time, minutes or weekday: only lines that need none of them.
        for seed in 0..<60 {
            let pick = WorkoutBanter.pick(facts: facts, tone: .playful, history: .init(), seed: UInt64(seed))
            #expect(!pick.text.contains("{"))
            #expect(WorkoutBanterGuard.strayNumbers(in: pick.text, facts: facts).isEmpty, "\(pick.text)")
            #expect(pick.lineID != "fallback")
        }
        // Nothing known at all: still a line, with no slot in it.
        let bare = WorkoutBanter.pick(facts: Facts(), tone: .playful, history: .init(), seed: 3)
        #expect(bare.lineID != "fallback" && !bare.text.contains("{"))
        #expect(WorkoutBanter.pick(facts: Facts(), tone: .plain, history: .init(), seed: 3).lineID != "fallback")
        #expect(WorkoutBanter.pick(facts: Facts(), tone: .playful, history: .init(), seed: 3, library: []).text == WorkoutBanter.fallbackText)
    }

    @Test func noLineRepeatsUntilEveryLineForItsSituationHasBeenUsed() {
        // One situation only, so the round is easy to see.
        let lines = WorkoutBanterLibrary.all.filter { $0.situation == .stuckLift && $0.register != .plain }
        let facts = rich(for: .stuckLift)
        var history = WorkoutBanter.History()
        var seen: [String] = []
        for day in 0..<(lines.count * 2) {
            let pick = WorkoutBanter.pick(facts: facts, tone: .playful, history: history, seed: UInt64(day) &* 7919, library: lines)
            seen.append(pick.lineID)
            history.record(pick.entry(dayKey: "d\(day)"))
        }
        #expect(Set(seen.prefix(lines.count)).count == lines.count, "the first round uses every line once")
        #expect(Set(seen.suffix(lines.count)).count == lines.count, "and so does the second")
        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 != $1 }, "never the line just used")
    }

    @Test func prefersLinesThatUseMoreOfTheDaysData() {
        let facts = rich(for: .nearRecord)
        var specific = 0
        for seed in 0..<400 {
            let pick = WorkoutBanter.pick(facts: facts, tone: .playful, history: .init(), seed: UInt64(seed) &* 104_729)
            if pick.situation != WorkoutBanter.Situation.planned.rawValue { specific += 1 }
        }
        // 53 of the eligible lines are general ones; without the preference they would win about half the time.
        #expect(specific > 280, "\(specific) of 400 picks were about the day's own data")
    }

    @Test func plainToneUsesOnlyPlainLines() {
        for seed in 0..<50 {
            for situation in [WorkoutBanter.Situation.planned, .weekProgress, .comeback, .deload, .lastCall, .longBreak] {
                let pick = WorkoutBanter.pick(facts: rich(for: situation), tone: .plain, history: .init(), seed: UInt64(seed))
                #expect(pick.register == WorkoutBanter.Register.plain.rawValue, "\(pick.text)")
            }
        }
    }

    @Test func lastCallStandsAloneInBothTones() {
        let facts = rich(for: .lastCall)
        #expect(WorkoutBanter.situations(for: facts) == [.lastCall])
        for tone in WorkoutBanter.Tone.allCases {
            let pick = WorkoutBanter.pick(facts: facts, tone: tone, history: .init(), seed: 9)
            #expect(pick.situation == WorkoutBanter.Situation.lastCall.rawValue)
            #expect(pick.text.lowercased().contains("open"))
        }
    }

    // MARK: Property tests

    /// Facts from a seed: any mix of present and missing, ordinary and extreme.
    func randomFacts(_ generator: inout WorkoutBanter.SplitMix64) -> Facts {
        func chance(_ share: Double) -> Bool { generator.unit() < share }
        func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(generator.next() % UInt64(range.count)) }
        let names = ["Upper A", "Legs", "Push", "Pull", "Full body", "Lower B", "Upper 2", "A", "",
                     "The very long session name somebody typed in once and never shortened again, ever",
                     "Hot {yoga} & abs", "Fat-loss circuit"]
        let lifts = ["Bench Press", "Back Squat", "Deadlift", "Overhead Press", "21s", "Hip Thrust",
                     "Single-Arm Dumbbell Row With A Very Long Name"]
        var facts = Facts()
        if chance(0.9) { facts.sessionName = names[int(0...(names.count - 1))] }
        if chance(0.8) { facts.sessionMinutes = int(0...180) }
        if chance(0.7) { facts.shortMinutes = int(0...30) }
        if chance(0.9) { facts.leadMinutes = int(0...90) }
        facts.isRestDay = chance(0.05)
        if chance(0.7) { facts.daysSinceLastSession = int(0...400) }
        if chance(0.8) {
            facts.sessionsPlanned = int(0...7)
            facts.sessionsDone = int(0...9)
        }
        if chance(0.5) { facts.weeksInARow = int(0...120) }
        if chance(0.6) {
            let weight = Double(int(0...6000)) / 10
            facts.lift = WorkoutBanter.Lift(name: lifts[int(0...(lifts.count - 1))], lastWeightKg: weight, lastReps: int(0...30),
                                            nextWeightKg: chance(0.7) ? weight + Double(int(-5...25)) / 2 : nil,
                                            weeksAtWeight: chance(0.5) ? int(0...60) : nil, nearBest: chance(0.6))
        }
        if chance(0.4) { facts.neglected = WorkoutBanter.Neglected(muscle: ["hamstrings", "chest", "upper back", ""][int(0...3)], days: int(0...200)) }
        if chance(0.5) {
            facts.standout = WorkoutBanter.Standout(recordLift: chance(0.5) ? lifts[int(0...(lifts.count - 1))] : nil,
                                                    volumeKg: chance(0.7) ? Double(int(0...90_000)) : nil, daysAgo: int(0...20))
        }
        if chance(0.3) { facts.recovery = [.low, .normal, .high][int(0...2)] }
        facts.isDeloadWeek = chance(0.1)
        facts.illnessFlagged = chance(0.05)
        if chance(0.05) { facts.painArea = ["lower back", "knee", ""][int(0...2)] }
        facts.restMode = chance(0.03)
        if chance(0.9) { facts.hour = int(0...23) }
        if chance(0.9) { facts.weekday = int(0...8) }
        facts.unit = chance(0.5) ? .kg : .lb
        facts.lastCall = chance(0.05)
        return facts
    }

    @Test func anyFactsGiveASendableLine() {
        var generator = WorkoutBanter.SplitMix64(seed: 2027)
        var history = WorkoutBanter.History()
        for index in 0..<3000 {
            let facts = randomFacts(&generator)
            let tone: WorkoutBanter.Tone = index % 4 == 0 ? .plain : .playful
            let pick = WorkoutBanter.pick(facts: facts, tone: tone, history: history, seed: generator.next())
            let problems = WorkoutBanterGuard.problems(in: pick.text, facts: facts)
            #expect(problems.isEmpty, "\(problems) in \(pick.text)")
            #expect(pick.lineID != "fallback")
            #expect(pick.text.count <= WorkoutBanter.maxBodyCharacters && pick.text.count >= WorkoutBanter.minBodyCharacters)
            #expect(!pick.text.contains("{") && !pick.text.contains("}"))
            // Every number said is one the facts hold.
            #expect(WorkoutBanterGuard.strayNumbers(in: pick.text, facts: facts).isEmpty, "\(pick.text)")
            // No "1 days": a slot never shows a count of one before a plural.
            #expect(pick.text.firstMatch(of: /\b[01] (days|weeks|sessions|reps|minutes)\b/) == nil, "\(pick.text)")
            if facts.caution != nil || tone == .plain {
                #expect(pick.register == WorkoutBanter.Register.plain.rawValue)
            } else {
                #expect(pick.register != WorkoutBanter.Register.plain.rawValue)
            }
            if let caution = facts.caution { #expect(pick.situation == caution.situation.rawValue) }
            history.record(pick.entry(dayKey: "d\(index)"))
        }
        #expect(history.entries.count == WorkoutBanter.History.kept)
    }

    // MARK: A year of reminders

    /// A plausible year: four sessions a week by name, the week's count, a
    /// lift that is close or stuck for stretches, breaks, records, a deload
    /// every sixth week, the odd low-recovery or ill day.
    func simulatedFacts(day: Int, generator: inout WorkoutBanter.SplitMix64) -> Facts {
        var facts = base(["Upper A", "Lower A", "Upper B", "Lower B"][day % 4])
        let weekday = day % 7 // 0 = Monday
        facts.weekday = [2, 3, 4, 5, 6, 7, 1][weekday]
        facts.hour = day % 3 == 0 ? 7 : (day % 3 == 1 ? 13 : 19)
        facts.sessionsPlanned = 4
        facts.sessionsDone = min(3, weekday * 4 / 7)
        facts.daysLeftInWeek = 7 - weekday
        let week = day / 7
        facts.isDeloadWeek = week % 6 == 5
        if week >= 2 { facts.weeksInARow = (week % 13) + 1 }
        let phase = (day / 20) % 3
        if phase == 0 {
            facts.lift = WorkoutBanter.Lift(name: "Bench Press", lastWeightKg: 80 + Double(week) * 0.5, lastReps: 5,
                                            nextWeightKg: 82.5 + Double(week) * 0.5, nearBest: true)
        } else if phase == 1 {
            facts.lift = WorkoutBanter.Lift(name: "Back Squat", lastWeightKg: 120, lastReps: 5, nextWeightKg: 122.5,
                                            weeksAtWeight: 2 + (day % 20) / 7)
        }
        let roll = generator.unit()
        if roll < 0.10 { facts.daysSinceLastSession = 4 + Int(generator.next() % 8) }
        if roll > 0.97 { facts.daysSinceLastSession = 21 }
        if day % 9 == 0 { facts.standout = WorkoutBanter.Standout(recordLift: "Deadlift", daysAgo: 2) }
        if day % 9 == 4 { facts.standout = WorkoutBanter.Standout(volumeKg: 5000 + Double(day) * 10, daysAgo: 1) }
        if day % 11 == 0 { facts.neglected = WorkoutBanter.Neglected(muscle: "hamstrings", days: 8 + day % 6) }
        if day % 5 == 0 { facts.recovery = .high }
        if day % 61 == 30 { facts.recovery = .low }
        if day % 97 == 50 { facts.illnessFlagged = true }
        if day % 83 == 40 { facts.lastCall = true }
        return facts
    }

    @Test func aYearOfDailyRemindersDoesNotLoop() {
        var generator = WorkoutBanter.SplitMix64(seed: 365)
        var history = WorkoutBanter.History()
        var picks: [WorkoutBanter.Pick] = []
        for day in 0..<365 {
            let facts = simulatedFacts(day: day, generator: &generator)
            let pick = WorkoutBanter.pick(facts: facts, tone: .playful, history: history, seed: WorkoutBanter.seed(for: "day-\(day)"))
            #expect(WorkoutBanterGuard.problems(in: pick.text, facts: facts).isEmpty, "day \(day): \(pick.text)")
            picks.append(pick)
            history.record(pick.entry(dayKey: "day-\(day)"))
        }
        let plain = WorkoutBanter.Register.plain.rawValue
        let lastCall = WorkoutBanter.Situation.lastCall.rawValue
        for day in 1..<365 {
            let today = picks[day], yesterday = picks[day - 1]
            // Caution days are plain on purpose; everything else never repeats a register back to back.
            if today.register != plain || yesterday.register != plain {
                #expect(today.register != yesterday.register, "day \(day): \(yesterday.text) / \(today.text)")
            }
            #expect(WorkoutBanter.opening(of: today.text) != WorkoutBanter.opening(of: yesterday.text), "day \(day): \(today.text)")
            #expect(today.text != yesterday.text)
        }
        // No line, and no sentence, comes back within the window. (The few
        // plain caution lines and last calls are a handful of lines by design.)
        for day in 0..<365 where picks[day].register != plain && picks[day].situation != lastCall {
            let earlier = picks[max(0, day - WorkoutBanter.recentWindow)..<day]
            #expect(!earlier.contains { $0.lineID == picks[day].lineID }, "day \(day): \(picks[day].lineID) again within \(WorkoutBanter.recentWindow)")
            #expect(!earlier.contains { $0.text == picks[day].text }, "day \(day): \(picks[day].text)")
        }
        let uses = Dictionary(grouping: picks.filter { $0.register != plain && $0.situation != lastCall }, by: \.lineID).mapValues(\.count)
        #expect(uses.count >= 150, "\(uses.count) different lines in the year")
        #expect((uses.values.max() ?? 0) <= 6, "the most-used line appeared \(uses.values.max() ?? 0) times")
        #expect(Set(picks.map(\.text)).count >= 300, "\(Set(picks.map(\.text)).count) different sentences in 365 days")
        #expect(Set(picks.map(\.register)).count == WorkoutBanter.Register.allCases.count)
    }

    // MARK: Pending reminders

    func request(_ day: Int, _ facts: Facts, today: Int) -> WorkoutBanter.DayRequest {
        WorkoutBanter.DayRequest(dayKey: dayKey(date(day: day)), fire: date(day: day, hour: 17), facts: facts, isToday: day == today)
    }

    @Test func reschedulingKeepsPendingLinesAndUsesNoneUp() {
        let requests = (11...15).map { request($0, base(["Upper A", "Lower A", "Upper B", "Lower B", "Upper A"][$0 - 11]), today: 11) }
        let first = WorkoutBanter.reconcile(.init(), requests: requests, tone: .playful, now: date(day: 11, hour: 8))
        #expect(first.pending.count == 5)
        #expect(first.history.entries.isEmpty, "nothing has gone out yet")
        #expect(Set(first.pending.map(\.pick.lineID)).count == 5, "the week ahead doesn't repeat a line")
        #expect(zip(first.pending, first.pending.dropFirst()).allSatisfy { $0.pick.register != $1.pick.register })
        // Opening the app again, ten times: nothing changes and nothing is used up.
        var store = first
        for minute in 1...10 {
            store = WorkoutBanter.reconcile(store, requests: requests, tone: .playful, now: date(day: 11, hour: 8).addingTimeInterval(Double(minute) * 60))
        }
        #expect(store == first)
        // Monday's reminder goes out; Tuesday's request keeps its line apart from the on-the-day rewrite.
        let later = WorkoutBanter.reconcile(store, requests: Array(requests.dropFirst()), tone: .playful, now: date(day: 11, hour: 18))
        #expect(later.history.entries.map(\.dayKey) == ["2027-01-11"])
        #expect(later.history.entries.first?.text == first.pending[0].pick.text)
        #expect(later.pending.map(\.pick) == Array(first.pending.dropFirst().map(\.pick)))
    }

    @Test func aReminderThatNeverWentOutIsNotUsedUp() {
        let requests = (11...13).map { request($0, base(), today: 11) }
        let first = WorkoutBanter.reconcile(.init(), requests: requests, tone: .playful, now: date(day: 11, hour: 8))
        // Trained early on Monday: its reminder is removed before it fires.
        let second = WorkoutBanter.reconcile(first, requests: Array(requests.dropFirst()), tone: .playful, now: date(day: 11, hour: 9))
        #expect(second.history.entries.isEmpty)
        #expect(second.history.cycles.isEmpty)
        #expect(second.pending.map(\.dayKey) == ["2027-01-12", "2027-01-13"])
        // Reminders switched off: nothing pending, nothing recorded.
        let off = WorkoutBanter.reconcile(second, requests: [], tone: .playful, now: date(day: 11, hour: 10))
        #expect(off == WorkoutBanter.Store())
    }

    @Test func aLineWrittenAheadIsRewrittenOnceOnItsOwnDayWithTheDaysData() {
        let ahead = WorkoutBanter.reconcile(.init(), requests: [request(12, base(), today: 11)], tone: .playful, now: date(day: 11))
        #expect(ahead.pending[0].ahead)
        // Tuesday morning the day's own data is in: a comeback and a lift near its best.
        let rich = rich(for: .nearRecord)
        let onDay = WorkoutBanter.reconcile(ahead, requests: [request(12, rich, today: 12)], tone: .playful, now: date(day: 12, hour: 8))
        #expect(!onDay.pending[0].ahead)
        // Then it stays, however often the app is opened.
        let again = WorkoutBanter.reconcile(onDay, requests: [request(12, rich, today: 12)], tone: .playful, now: date(day: 12, hour: 9))
        #expect(again == onDay)
    }

    @Test func aPendingLineChangesWhenItIsNoLongerTrue() {
        let facts = rich(for: .stuckLift)
        var library = WorkoutBanterLibrary.all.filter { $0.situation == .stuckLift || $0.register == .plain }
        library.removeAll { $0.situation == .planned && $0.register != .plain }
        let first = WorkoutBanter.reconcile(.init(), requests: [request(11, facts, today: 11)], tone: .playful, now: date(day: 11, hour: 8), library: library)
        #expect(first.pending[0].pick.situation == "stuckLift")
        // The lift moved: the line about three weeks at 82.5 kg is no longer true.
        var moved = facts
        moved.lift?.weeksAtWeight = 4
        let second = WorkoutBanter.reconcile(first, requests: [request(11, moved, today: 11)], tone: .playful, now: date(day: 11, hour: 9), library: library)
        #expect(second.pending[0].pick.text != first.pending[0].pick.text)
        #expect(second.pending[0].pick.text.contains("4 weeks"))
        // Illness flagged at noon: the joke goes, a plain line takes its place.
        var ill = moved
        ill.illnessFlagged = true
        let third = WorkoutBanter.reconcile(second, requests: [request(11, ill, today: 11)], tone: .playful, now: date(day: 11, hour: 12), library: library)
        #expect(third.pending[0].pick.situation == "illness")
        #expect(third.pending[0].pick.register == "plain")
        // Switching to Plain rewrites what is pending.
        let plain = WorkoutBanter.reconcile(second, requests: [request(11, moved, today: 11)], tone: .plain, now: date(day: 11, hour: 12), library: library)
        #expect(plain.pending[0].pick.register == "plain")
    }

    // MARK: Lines from the on-device model

    @Test func aGoodModelLineIsAccepted() {
        let facts = rich(for: .nearRecord)
        let line = "Upper A in 30 minutes. The barbell has been stretching since noon, which is odd for a barbell."
        #expect(WorkoutBanterGuard.acceptGenerated("  \"\(line)\"  ", facts: facts, recent: []) == line)
        #expect(WorkoutBanterGuard.acceptGenerated("- \(line)", facts: facts, recent: []) == line)
        // A session called "Full body" is the owner's name for it, not body talk.
        #expect(WorkoutBanterGuard.acceptGenerated("Full body in 30 minutes. The rack has ironed its best plates.", facts: base("Full body"), recent: []) != nil)
    }

    @Test(arguments: [
        "Upper A in 30 minutes. Time to burn off that pizza and earn your dinner.",
        "Upper A in 30 minutes. Your body will thank you when beach season arrives.",
        "You missed Tuesday. Upper A in 30 minutes, no excuses this time.",
        "Upper A in 30 minutes. You should really go, the barbell is disappointed in you.",
        "Upper A in 30 minutes. Don't be lazy, the couch can wait.",
        "Upper A in 30 minutes. Feeling sick? Push through, the bar doesn't care.",
        "Upper A in 30 minutes. No pain, no gain, as the dumbbells say.",
        "Upper A in 45 minutes. The barbell has cleared its diary.",
        "Upper A in 30 minutes. That's 100 kg of destiny waiting on the bar.",
        "Upper A in 30 minutes. The plates have waited seven days for this.",
        "Upper A in 30 minutes. A thousand barbells salute you.",
        "Upper A in 30 minutes. The barbell is ready 💪",
        "Upper A in 30 minutes.\nThe barbell is ready and waiting.",
        "Here's a line: Upper A in 30 minutes. The barbell is ready.",
        "Upper A in 30 minutes. Even the owl from that language app is impressed.",
        "Upper A in 30 minutes. Don't break your streak now.",
        // Skipping, quitting and thin-limb jokes (review findings).
        "Upper A in 30 minutes. Never skip leg day, as the barbell says.",
        "Upper A in 30 minutes. Don't skip it, bro.",
        "Upper A in 30 minutes. Don't miss it, the rack is waiting.",
        "Last time you quit early. Upper A in 30 minutes, the bar is ready.",
        "Upper A in 30 minutes. The rack never gave up on the barbell.",
        "Upper A in 30 minutes. No noodle legs on this barbell's watch.",
        "Upper A in 30 minutes. The barbell says chicken legs are a myth.",
        "Upper A in 30 minutes. The plates refuse to stay puny.",
        "Upper A in {lead} minutes. The barbell is ready.",
        "Go.",
        "Upper A in 30 minutes. One. Two. Many. Sentences. Here.",
        "Upper A in 30 minutes. The barbell would like a word, and the word is very long indeed, so long that it runs past the end of any notification a phone could show.",
    ])
    func aBadModelLineIsDropped(candidate: String) {
        #expect(WorkoutBanterGuard.acceptGenerated(candidate, facts: rich(for: .nearRecord), recent: []) == nil, "\(candidate)")
    }

    @Test func aModelLineTooCloseToARecentOneIsDropped() {
        let facts = base()
        let recent = ["Upper A in 30 minutes. The barbell has cleared its schedule."]
        #expect(WorkoutBanterGuard.acceptGenerated("Upper A in 30 minutes. The barbell cleared its whole schedule.", facts: facts, recent: recent) == nil)
        // The same opening as the last reminder is dropped too.
        #expect(WorkoutBanterGuard.acceptGenerated("Upper A in 30 minutes. A kettlebell is humming a fanfare for you.", facts: facts, recent: recent) == nil)
        #expect(WorkoutBanterGuard.acceptGenerated("A kettlebell is humming a fanfare. Upper A, 30 minutes.", facts: facts, recent: recent) != nil)
        // Never in a caution state or for the last call, whatever the line.
        #expect(WorkoutBanterGuard.acceptGenerated("A kettlebell is humming a fanfare. Upper A, 30 minutes.", facts: rich(for: .illness), recent: []) == nil)
        #expect(WorkoutBanterGuard.acceptGenerated("A kettlebell is humming a fanfare. Upper A, 30 minutes.", facts: rich(for: .lastCall), recent: []) == nil)
    }

    @Test func numbersInAModelLineMustBeInTheFacts() {
        let facts = rich(for: .stuckLift)
        #expect(WorkoutBanterGuard.strayNumbers(in: "Bench press at 82.5 kg for 3 weeks, Upper A in 30 minutes", facts: facts).isEmpty)
        #expect(WorkoutBanterGuard.strayNumbers(in: "Three weeks at 82.5 kg", facts: facts).isEmpty, "a number word the facts hold")
        #expect(WorkoutBanterGuard.strayNumbers(in: "Four weeks at 82.5 kg", facts: facts) == ["four"])
        #expect(WorkoutBanterGuard.strayNumbers(in: "83 kg for 3 weeks", facts: facts) == ["83"])
        #expect(WorkoutBanterGuard.strayNumbers(in: "One more rep", facts: facts).isEmpty)
        var volume = rich(for: .afterVolume)
        volume.unit = .lb
        #expect(WorkoutBanterGuard.strayNumbers(in: "13,757 lb last session, or 13757 lb if you prefer", facts: volume).isEmpty)
    }

    @Test func theModelIsAskedOnlyWhenItMayWriteTheLine() {
        let facts = rich(for: .nearRecord)
        func assigned(_ key: String, tone: WorkoutBanter.Tone = .playful) -> WorkoutBanter.Assigned {
            WorkoutBanter.Assigned(dayKey: key, fire: date(day: 20), pick: .init(lineID: "pl01", situation: "planned", register: "deadpan", text: "x"),
                                   tone: tone, ahead: false)
        }
        let keys = (1...28).map { "2027-02-\($0)" }
        let asked = keys.filter { WorkoutBanter.wantsGenerated(assigned($0), facts: facts) }
        #expect(asked.count >= 7 && asked.count <= 21, "about every other day: \(asked.count) of 28")
        let key = asked[0]
        #expect(!WorkoutBanter.wantsGenerated(assigned(key, tone: .plain), facts: facts))
        #expect(!WorkoutBanter.wantsGenerated(assigned(key), facts: rich(for: .lowRecovery)))
        #expect(!WorkoutBanter.wantsGenerated(assigned(key), facts: rich(for: .illness)))
        #expect(!WorkoutBanter.wantsGenerated(assigned(key), facts: rich(for: .pain)))
        #expect(!WorkoutBanter.wantsGenerated(assigned(key), facts: rich(for: .lastCall)))

        var store = WorkoutBanter.Store()
        store.pending = [assigned(key)]
        // The model failed or its line was dropped: asked once, the library line stays.
        let failed = WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: nil)
        #expect(failed.pending[0].pick.lineID == "pl01")
        #expect(!WorkoutBanter.wantsGenerated(failed.pending[0], facts: facts))
        // Accepted: the model's line goes in and the library line is not used up.
        let line = "Upper A in 30 minutes. The barbell has been stretching since noon, which is odd for a barbell."
        let done = WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: line)
        #expect(done.pending[0].isGenerated && done.pending[0].pick.text == line)
        #expect(!WorkoutBanter.wantsGenerated(done.pending[0], facts: facts))
        let request = WorkoutBanter.DayRequest(dayKey: key, fire: date(day: 20), facts: facts, isToday: true)
        let kept = WorkoutBanter.reconcile(done, requests: [request], tone: .playful, now: date(day: 19))
        #expect(kept.pending[0].pick.text == line, "kept across reschedules")
        let sent = WorkoutBanter.reconcile(kept, requests: [], tone: .playful, now: date(day: 21))
        #expect(sent.history.entries.first?.text == line)
        #expect(sent.history.cycles.isEmpty, "a model line uses up no library line")
        // The facts changed (a session done since): the model's line is dropped for a library one.
        var changed = facts
        changed.sessionsDone = 3
        let dropped = WorkoutBanter.reconcile(done, requests: [.init(dayKey: key, fire: date(day: 20), facts: changed, isToday: true)],
                                              tone: .playful, now: date(day: 19))
        #expect(!dropped.pending[0].isGenerated)
    }

    @Test func thePromptHoldsOnlyTrainingFacts() {
        var facts = rich(for: .nearRecord)
        facts.recovery = .high
        let lines = WorkoutBanterPrompt.factLines(facts)
        #expect(lines.contains("Session: Upper A, starts in 30 minutes, planned 60 minutes, short version 15 minutes"))
        #expect(lines.contains("Bench Press: 82.5 kg × 5 last time, next step 85 kg"))
        #expect(lines.contains("This week: 2 of 5 sessions done"))
        let text = WorkoutBanterPrompt.prompt(facts: facts, examples: WorkoutBanterPrompt.examples(facts: facts, history: .init()))
        for word in ["recovery", "readiness", "heart", "illness", "pain", "weight loss"] {
            #expect(!text.lowercased().contains(word), "\(word)")
        }
        let examples = WorkoutBanterPrompt.examples(facts: facts, history: .init())
        #expect(examples.count == 3)
        #expect(examples.filter { $0.contains("hamstrings") }.count <= 1, "examples are about different things")
        #expect(text.count < 1200, "a small prompt: \(text.count) characters")
        // A long break is never counted out to the model either.
        facts.daysSinceLastSession = 40
        #expect(!WorkoutBanterPrompt.factLines(facts).contains { $0.contains("40") })
        var other = facts
        other.sessionsDone = 3
        #expect(WorkoutBanterPrompt.signature(other) != WorkoutBanterPrompt.signature(facts))
    }

    // MARK: Facts from the log

    func session(_ day: Int, month: Int = 1, _ lifts: [(String, Double, Int)], name: String = "Upper A") -> WorkoutSummary.LoggedSession {
        let start = calendar.date(from: DateComponents(year: 2027, month: month, day: day, hour: 18))!
        return WorkoutSummary.LoggedSession(name: name, start: start, end: start.addingTimeInterval(3600), exercises: lifts.map { lift in
            WorkoutSummary.LoggedExercise(exerciseID: lift.0.lowercased(), name: lift.0,
                                          sets: (0..<3).map { _ in WorkoutSummary.LoggedSet(weightKg: lift.1, reps: lift.2, completedAt: start) })
        })
    }

    @Test func aLiftAtOneWeightForWeeksIsStuckUnlessTheRepsWentUp() throws {
        let now = date(day: 30)
        let stuck = [session(4, [("Bench Press", 82.5, 5)]), session(11, [("Bench Press", 82.5, 5)]), session(18, [("Bench Press", 82.5, 5)]),
                     session(25, [("Bench Press", 82.5, 5)])]
        let lift = try #require(WorkoutBanterFacts.lift(sessions: stuck, now: now) { _, kg in kg + 2.5 })
        #expect(lift.name == "Bench Press")
        #expect(lift.weeksAtWeight == 3)
        #expect(lift.lastWeightKg == 82.5 && lift.lastReps == 5 && lift.nextWeightKg == 85)
        // Same weight, more reps each week: that is progress, and close to the best.
        let climbing = [session(4, [("Bench Press", 82.5, 5)]), session(11, [("Bench Press", 82.5, 6)]), session(18, [("Bench Press", 82.5, 7)]),
                        session(25, [("Bench Press", 82.5, 8)])]
        let moving = try #require(WorkoutBanterFacts.lift(sessions: climbing, now: now) { _, kg in kg + 2.5 })
        #expect(moving.weeksAtWeight == nil)
        #expect(moving.nearBest)
        // Two sessions aren't a pattern; a lift not done for a month isn't news; a bodyweight lift has no next weight.
        #expect(WorkoutBanterFacts.lift(sessions: Array(stuck.prefix(2)), now: now) == nil)
        #expect(WorkoutBanterFacts.lift(sessions: stuck, now: date(day: 30).addingTimeInterval(40 * 86_400)) == nil)
        #expect(WorkoutBanterFacts.lift(sessions: stuck, traits: ["bench press": .init(isBodyweight: true)], now: now) == nil)
        // Well under its best and not stuck: nothing to say.
        let off = [session(4, [("Deadlift", 180, 5)]), session(11, [("Deadlift", 140, 5)]), session(18, [("Deadlift", 150, 5)])]
        #expect(WorkoutBanterFacts.lift(sessions: off, now: now) { _, kg in kg + 5 } == nil)
    }

    @Test func theLastSessionsStandoutIsARecordOrTheMostVolume() throws {
        let sessions = [session(4, [("Back Squat", 100, 5)]), session(11, [("Back Squat", 100, 5)]), session(18, [("Back Squat", 100, 5)]),
                        session(25, [("Back Squat", 105, 5)])]
        let record = try #require(WorkoutBanterFacts.standout(sessions: sessions, now: date(day: 27), calendar: calendar))
        #expect(record.recordLift == "Back Squat")
        #expect(record.daysAgo == 2)
        // No record, but more sets' worth of work than any recent session.
        let big = [session(4, [("Back Squat", 100, 5)]), session(11, [("Back Squat", 100, 5)]), session(18, [("Back Squat", 100, 5)]),
                   session(25, [("Back Squat", 90, 6), ("Leg Press", 150, 10)])]
        let volume = try #require(WorkoutBanterFacts.standout(sessions: Array(big.prefix(3)) + [big[3]], now: date(day: 26), calendar: calendar))
        #expect(volume.recordLift == nil)
        let expected: Double = 6120
        #expect(volume.volumeKg == expected)
        // An ordinary session: nothing stands out.
        let ordinary = Array(sessions.prefix(3)) + [session(25, [("Back Squat", 100, 5)])]
        #expect(WorkoutBanterFacts.standout(sessions: ordinary, now: date(day: 26), calendar: calendar) == nil)
        #expect(WorkoutBanterFacts.standout(sessions: [], now: date(), calendar: calendar) == nil)
        // A record from more than a week ago is no longer news.
        #expect(WorkoutBanterFacts.standout(sessions: sessions, now: date(day: 25).addingTimeInterval(10 * 86_400), calendar: calendar) == nil)
    }

    @Test func weeksInARowCountOnlyKeptWeeksAndStopAtTheFirstGap() {
        func week(_ mondayOffset: Int, planned: Int, done: Int) -> WeekRecord {
            WeekRecord(weekStart: calendar.date(byAdding: .day, value: 7 * mondayOffset, to: calendar.startOfDay(for: date()))!, planned: planned, done: done)
        }
        let now = date(day: 13)
        #expect(WorkoutBanterFacts.weeksInARow(records: [week(-3, planned: 4, done: 4), week(-2, planned: 4, done: 3), week(-1, planned: 4, done: 3),
                                                         week(0, planned: 4, done: 1)], now: now, calendar: calendar) == 3)
        // This week counts once it is kept.
        #expect(WorkoutBanterFacts.weeksInARow(records: [week(-1, planned: 4, done: 3), week(0, planned: 4, done: 3)], now: now, calendar: calendar) == 2)
        // A week under plan ends the run; so does a week with no plan.
        #expect(WorkoutBanterFacts.weeksInARow(records: [week(-3, planned: 4, done: 4), week(-2, planned: 4, done: 1), week(-1, planned: 4, done: 4)],
                                               now: now, calendar: calendar) == 1)
        #expect(WorkoutBanterFacts.weeksInARow(records: [week(-3, planned: 4, done: 4), week(-1, planned: 4, done: 4)], now: now, calendar: calendar) == 1)
        #expect(WorkoutBanterFacts.weeksInARow(records: [], now: now, calendar: calendar) == 0)
    }

    @Test func theNeglectedMuscleIsANameableOneLeftAloneLongest() {
        let now = date(day: 20)
        let last: [Muscle: Date] = [.hamstrings: date(day: 11), .chest: date(day: 18), .abdominals: date(day: 1), .glutes: date(day: 2),
                                    .calves: date(day: 14)]
        #expect(WorkoutBanterFacts.neglected(lastTrained: last, now: now, calendar: calendar) == .init(muscle: "hamstrings", days: 9))
        // Never a muscle that reads as a comment on looks, and nothing after a long absence.
        #expect(WorkoutBanterFacts.neglected(lastTrained: [.abdominals: date(day: 1), .glutes: date(day: 2)], now: now, calendar: calendar) == nil)
        #expect(WorkoutBanterFacts.neglected(lastTrained: [.chest: date(day: 1).addingTimeInterval(-90 * 86_400)], now: now, calendar: calendar) == nil)
        #expect(WorkoutBanterFacts.neglected(lastTrained: [.middleBack: date(day: 10)], now: now, calendar: calendar)?.muscle == "upper back")
    }

    @Test func theLiftIsOneTodaysSessionTrains() throws {
        let now = date(day: 30)
        // Bench press stuck for three weeks, back squat close to its best.
        let log = [session(4, [("Bench Press", 82.5, 5), ("Back Squat", 100, 5)]), session(11, [("Bench Press", 82.5, 5), ("Back Squat", 102.5, 5)]),
                   session(18, [("Bench Press", 82.5, 5), ("Back Squat", 105, 5)]), session(25, [("Bench Press", 82.5, 5), ("Back Squat", 107.5, 5)])]
        let primary: [String: [Muscle]] = ["bench press": [.chest], "back squat": [.quadriceps]]
        func lift(on focus: WorkoutFocus) -> WorkoutBanter.Lift? {
            WorkoutBanterFacts.lift(sessions: log, now: now, nextWeightKg: { _, kg in kg + 2.5 },
                                    inSession: { WorkoutBanterFacts.trains(focus, primary: primary[$0] ?? []) })
        }
        #expect(try #require(lift(on: .push)).name == "Bench Press")
        #expect(try #require(lift(on: .legs)).name == "Back Squat", "leg day never hears about the bench")
        #expect(lift(on: .pull) == nil, "nothing trained on a pull day: no lift line")
        #expect(try #require(lift(on: .fullBody)).name == "Bench Press", "the stuck one first when both are in the session")
        // What each focus trains first.
        #expect(WorkoutBanterFacts.trains(.upper, primary: [.biceps]))
        #expect(!WorkoutBanterFacts.trains(.lower, primary: [.chest]))
        #expect(!WorkoutBanterFacts.trains(.fullBody, primary: []), "unknown muscles: left out")
        #expect(WorkoutBanterFacts.catalogPrimary("Barbell_Squat") == [.quadriceps])
        #expect(WorkoutBanterFacts.catalogPrimary("Barbell_Bench_Press_-_Medium_Grip") == [.chest])
        #expect(WorkoutBanterFacts.catalogPrimary("not-a-lift").isEmpty)
    }

    @Test func aWeekStartLineOnlyWhileTheWeekCanHoldEverySession() {
        var facts = base()
        facts.sessionsDone = 0
        facts.sessionsPlanned = 4
        facts.daysLeftInWeek = 7
        #expect(WorkoutBanter.situations(for: facts).contains(.weekStart), "Monday, four planned")
        facts.daysLeftInWeek = 4
        #expect(WorkoutBanter.situations(for: facts).contains(.weekStart), "the first planned day can be Thursday")
        // Friday with none done: "the first of 4 this week" would count what's missing.
        facts.daysLeftInWeek = 3
        #expect(WorkoutBanter.situations(for: facts).isDisjoint(with: [.weekStart, .weekProgress, .lastOfWeek]))
        facts.daysLeftInWeek = nil
        #expect(!WorkoutBanter.situations(for: facts).contains(.weekStart), "unknown: no week-start line")
        for seed in 0..<40 {
            let pick = WorkoutBanter.pick(facts: facts, tone: .playful, history: .init(), seed: UInt64(seed))
            #expect(pick.situation != WorkoutBanter.Situation.weekStart.rawValue)
        }
    }

    @Test func easyDayLinesDontClaimTheScoreIsLow() {
        // `lowRecovery` is also a 7-day HRV below normal with an ordinary score.
        for line in WorkoutBanterLibrary.all where line.situation == .lowRecovery {
            let text = line.template.lowercased()
            #expect(!text.contains("recovery is low") && !text.contains("low recovery"), "\(line.id)")
        }
    }

    @Test func keepingPlainStillShowsYourIfThenLine() {
        #expect(!rich(for: .keepPlain).noPush, "the session stands; only the jokes stop")
        #expect(!base().noPush)
        for caution in WorkoutBanter.Caution.allCases where caution != .keepPlain {
            #expect(rich(for: caution.situation).noPush, "\(caution)")
        }
    }

    @Test func aNewLineStaysClearOfLinesLaterRemindersKeep() {
        // Two lines fit; Tuesday keeps one, so Monday's rewrite on the day takes the other.
        let library = WorkoutBanterLibrary.all.filter { ["pl01", "pl02"].contains($0.id) }
        #expect(library.count == 2)
        // Thirty different weeks (the day key seeds the pick).
        for week in 0..<30 {
            let monday = WorkoutBanter.DayRequest(dayKey: "w\(week)-mon", fire: date(day: 11, hour: 17), facts: base(), isToday: true)
            let tuesday = WorkoutBanter.DayRequest(dayKey: "w\(week)-tue", fire: date(day: 12, hour: 17), facts: base("Legs"), isToday: false)
            let first = WorkoutBanter.reconcile(.init(), requests: [tuesday], tone: .playful, now: date(day: 10, hour: 8), library: library)
            let held = first.pending[0].pick
            // Monday's reminder is added on Monday itself; Tuesday's stays as it is.
            let both = WorkoutBanter.reconcile(first, requests: [monday, tuesday], tone: .playful, now: date(day: 11, hour: 8), library: library)
            #expect(both.pending[1].pick == held)
            #expect(both.pending[0].pick.lineID != held.lineID, "week \(week): \(both.pending[0].pick.text)")
        }
    }

    @Test func aModelLineWaitsForFreshLinesToBeOn() {
        let facts = rich(for: .nearRecord)
        let key = dayKey(date(day: 20))
        let line = "Upper A in 30 minutes. The barbell has been stretching since noon, which is odd for a barbell."
        var store = WorkoutBanter.Store()
        store.pending = [WorkoutBanter.Assigned(dayKey: key, fire: date(day: 20, hour: 17),
                                                pick: .init(lineID: "pl01", situation: "planned", register: "deadpan", text: "x"),
                                                tone: .playful, ahead: false)]
        let done = WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: line)
        let request = WorkoutBanter.DayRequest(dayKey: key, fire: date(day: 20, hour: 17), facts: facts, isToday: true)
        #expect(WorkoutBanter.reconcile(done, requests: [request], tone: .playful, now: date(day: 20, hour: 8)).pending[0].isGenerated)
        // Switched off, or Apple Intelligence no longer available: a library line takes its place.
        let off = WorkoutBanter.reconcile(done, requests: [request], tone: .playful, now: date(day: 20, hour: 8), freshLines: false)
        #expect(!off.pending[0].isGenerated)
        // Switched off while the model was still writing: its line doesn't go in.
        #expect(!WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: line, freshLines: false).pending[0].isGenerated)
    }

    @Test func aModelLineIsUsedOnlyForTheLineItWasWrittenFor() {
        let facts = rich(for: .nearRecord)
        let key = dayKey(date(day: 20))
        let line = "Upper A in 30 minutes. The barbell has been stretching since noon, which is odd for a barbell."
        let asked = WorkoutBanter.Assigned(dayKey: key, fire: date(day: 20, hour: 17),
                                           pick: .init(lineID: "pl01", situation: "planned", register: "deadpan", text: "x"),
                                           tone: .playful, ahead: false)
        var store = WorkoutBanter.Store()
        store.pending = [asked]
        // Unchanged while the model wrote: its line goes in.
        let applied = WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: line, askedFor: asked, currentFacts: facts)
        #expect(applied.pending[0].pick.text == line)
        // Rescheduled meanwhile with another line (the facts changed): the model's line is dropped, nothing noted.
        var moved = store
        moved.pending[0].pick = .init(lineID: "pl02", situation: "planned", register: "absurd", text: "y")
        #expect(WorkoutBanter.applyGenerated(moved, dayKey: key, facts: facts, accepted: line, askedFor: asked, currentFacts: facts) == moved)
        // Same pending line, but the facts moved on (a session logged): asked once, the library line stays.
        var later = facts
        later.sessionsDone = 3
        let stale = WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: line, askedFor: asked, currentFacts: later)
        #expect(stale.pending[0].pick.lineID == "pl01")
        #expect(stale.pending[0].modelAsked == WorkoutBanterPrompt.signature(facts))
        // Illness flagged meanwhile: never a joke.
        var ill = facts
        ill.illnessFlagged = true
        #expect(!WorkoutBanter.applyGenerated(store, dayKey: key, facts: facts, accepted: line, askedFor: asked, currentFacts: ill).pending[0].isGenerated)
    }

    @Test func everyFocusHasADayNameThatReadsInALine() throws {
        let line = try #require(WorkoutBanterLibrary.all.first { $0.id == "pl05" })
        for focus in WorkoutFocus.allCases {
            let facts = base(WorkoutBanterFacts.dayName(for: focus))
            #expect(WorkoutBanterGuard.problems(in: try #require(line.render(facts)), facts: facts).isEmpty)
        }
        #expect(line.render(base(WorkoutBanterFacts.dayName(for: .legs))) == "Your Wednesday Leg day is in 30 minutes. The gym floor has been briefed.")
        // "Full body day" is the session's name, not talk about bodies.
        let pick = WorkoutBanter.pick(facts: base("Full body day"), tone: .playful, history: .init(), seed: 4)
        #expect(WorkoutBanterGuard.problems(in: pick.text, facts: base("Full body day")).isEmpty)
    }

    @Test func recoveryBandsFollowTheCalculator() {
        #expect(WorkoutBanterFacts.recoveryBand(score: 20) == .low)
        #expect(WorkoutBanterFacts.recoveryBand(score: 33) == .low)
        #expect(WorkoutBanterFacts.recoveryBand(score: 50) == .normal)
        #expect(WorkoutBanterFacts.recoveryBand(score: 67) == .high)
    }

    // MARK: Going quiet and coming back

    typealias Cadence = WorkoutReminderCadence

    func evaluate(_ state: Cadence.State, log: [Int], tapped: [Int] = [], trained: [Int] = [], today: Int, hour: Int = 9) -> Cadence.Decision {
        let fires = Dictionary(uniqueKeysWithValues: log.map { (dayKey(date(day: $0)), date(day: $0, hour: 17)) })
        return Cadence.evaluate(state, log: fires, tapped: Set(tapped.map { dayKey(date(day: $0)) }),
                                trained: Set(trained.map { dayKey(date(day: $0)) }), now: date(day: today, hour: hour),
                                calendar: calendar, dayKey: { dayKey($0) })
    }

    @Test func afterTheLastCallGoesOutNothingMoreIsScheduledUntilItIsAnswered() {
        // The last call fired at 17:00 today; the app is opened at 20:00 without training.
        let waiting = evaluate(.init(), log: [11, 12], today: 12, hour: 20)
        #expect(waiting.stage == .waiting)
        #expect(waiting.stage.maxPending == 0, "no second last call is queued behind the first")
        #expect(waiting.state == Cadence.State())
        // Tapped, or trained that evening: back to normal.
        #expect(evaluate(.init(), log: [11, 12], tapped: [12], today: 12, hour: 20).stage == .normal)
        #expect(evaluate(.init(), log: [11, 12], trained: [12], today: 12, hour: 20).stage == .normal)
        // The same while reminders come one at a time.
        let back = evaluate(.init(), log: [11, 12], today: 13)
        #expect(evaluate(back.state, log: [13], today: 13, hour: 20).stage == .waiting)
        #expect(evaluate(back.state, log: [13], tapped: [13], today: 13, hour: 20).stage == .normal)
        // An ordinary day is not held back: the week's reminders stay queued.
        #expect(evaluate(.init(), log: [12], today: 12, hour: 20).stage == .normal)
    }

    @Test func oneUnansweredReminderMakesTheNextTheLastCall() {
        #expect(evaluate(.init(), log: [], today: 11).stage == .normal)
        #expect(evaluate(.init(), log: [11], trained: [11], today: 12).stage == .normal)
        #expect(evaluate(.init(), log: [11], tapped: [11], today: 12).stage == .normal)
        let lastCall = evaluate(.init(), log: [11], today: 12)
        #expect(lastCall.stage == .lastCall)
        #expect(lastCall.stage.maxPending == 1, "only the last call stays pending, so the quiet starts by itself")
        // Today's reminder, still to come, doesn't count either way.
        #expect(evaluate(.init(), log: [11, 12], today: 12).stage == .lastCall)
        // Training on a later day answers the earlier reminder.
        #expect(evaluate(.init(), log: [11], trained: [12], today: 13).stage == .normal)
        #expect(evaluate(.init(), log: [11], trained: [12], today: 12).stage == .normal)
    }

    @Test func twoUnansweredInARowGoQuietUntilTrainingOrTheNextAppOpen() {
        // The last call (day 12) went unanswered. Nothing is pending after it, so the quiet has
        // already begun; the next time the app is opened, reminders are back, one at a time.
        let back = evaluate(.init(), log: [11, 12], today: 13)
        #expect(back.stage == .oneAtATime && back.clearLog)
        #expect(back.stage.maxPending == 1)
        #expect(back.state.quietSpells == 1)
        // Training instead brings everything back at once.
        #expect(evaluate(.init(), log: [11, 12], trained: [13], today: 13).stage == .normal)
        // That one reminder is answered: back to normal, and the count starts again.
        let answered = evaluate(back.state, log: [15], tapped: [15], today: 16)
        #expect(answered.stage == .normal && answered.state == Cadence.State())
        #expect(evaluate(back.state, log: [], trained: [14], today: 15).stage == .normal)
        // It goes unanswered: quiet again with no second last call, for three days this time.
        let quiet = evaluate(back.state, log: [15], today: 16)
        #expect(quiet.stage == .quiet && quiet.stage.maxPending == 0)
        #expect(quiet.state.quietSpells == 2)
        #expect(evaluate(quiet.state, log: [15], today: 17).stage == .quiet)
        #expect(evaluate(quiet.state, log: [15], today: 18).stage == .oneAtATime)
        // Training during a quiet spell ends it at once.
        let trained = evaluate(quiet.state, log: [15], trained: [17], today: 17)
        #expect(trained.stage == .normal && trained.clearLog && trained.state == Cadence.State())
    }

    @Test func eachQuietSpellWithoutAnAnswerLastsLonger() {
        // Days from an unanswered reminder to the first app open that brings reminders back.
        var decision = evaluate(.init(), log: [11, 12], today: 13)
        var lengths = [13 - 12]
        var sent = 13
        for _ in 0..<3 {
            // The one reminder that came back (day `sent`) goes unanswered; the app is opened every day after.
            var opened = sent + 1
            var next = evaluate(decision.state, log: [sent], today: opened)
            #expect(next.stage == .quiet)
            while next.stage == .quiet {
                opened += 1
                next = evaluate(next.state, log: [sent], today: opened)
            }
            #expect(next.stage == .oneAtATime && next.clearLog)
            lengths.append(opened - sent)
            decision = next
            sent = opened
        }
        #expect(lengths == [1, 3, 7, 14])
        #expect(Cadence.quietDays(spell: 9) == 14)
    }
}

extension WorkoutBanter.Line: CustomTestStringConvertible {
    public var testDescription: String { id }
}
