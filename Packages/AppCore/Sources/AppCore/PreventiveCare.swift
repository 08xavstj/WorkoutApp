import Foundation

/// The preventive-care checklist: the screening checks and vaccinations
/// recommended for an adult of a given age and sex, with when each was last
/// done and when it is next due (write-up in
/// docs/research/mind-and-prevention-2026-11.md).
///
/// **Recommendations are national**, which was the research's objection to
/// building this (docs/research/healthy-living-2026-11.md section 4). So:
/// - Every item belongs to a `Schedule` for one country, naming the body that
///   issued it, its grade and its date. Nothing is merged across countries.
/// - A country without a schedule checked at the source gets no list
///   (`schedule(forRegion:)` is nil). The page says so, and offers the United
///   States list only as a labelled reference.
/// - Each schedule stores the day it was checked (`Schedule.reviewed`). The
///   page always shows it, and flags the list once it is more than
///   `staleAfterDays` old.
///
/// **United States sources, fetched 17 Nov 2026:**
/// - US Preventive Services Task Force, "A and B Recommendations"
///   (uspreventiveservicestaskforce.org). Grade A: high certainty of
///   substantial net benefit. Grade B: at least moderate certainty of moderate
///   to substantial net benefit. Intervals come from each statement's
///   "Screening Intervals" section and are quoted beside each item; where the
///   Task Force gives none, the item says so and sets no due date.
/// - CDC, "Adult Immunization Schedule by Age … United States, 2025", with
///   the addendum of 2 July 2025, as shown on cdc.gov on 17 Nov 2026. Federal
///   vaccine advice changed several times after June 2025 and those later
///   changes were stayed by a court (Congressional Research Service, IN12684,
///   updated 29 July 2026), so COVID-19 is listed as "ask", with no due date.
///
/// **What is left out, on purpose:** pregnancy-related items (the app does not
/// know about pregnancy), counselling and medicines (statins, PrEP, folic
/// acid: decisions made with a clinician, not checks to date), anything for
/// children, and checks only for people at higher risk of an infection
/// (hepatitis B, syphilis, tuberculosis, chlamydia and gonorrhoea), which the
/// page names in one line instead of asking personal questions. The Task
/// Force has no A or B recommendation for hearing, vision, skin, prostate or
/// dental checks in adults, so none is listed.
public enum PreventiveCare {
    // MARK: Schedule

    public struct Source: Sendable, Equatable {
        /// Short name on each row: "USPSTF", "CDC".
        public var short: String
        /// Full name of the body.
        public var body: String
        /// The document.
        public var document: String

        public init(short: String, body: String, document: String) {
            self.short = short
            self.body = body
            self.document = document
        }
    }

    public struct Schedule: Sendable {
        /// ISO region code, "US".
        public var region: String
        public var country: String
        public var sources: [Source]
        /// The day the items were last checked against the sources.
        public var reviewed: Date
        public var items: [Item]
        /// One line on checks that are only for some people.
        public var riskNote: String
    }

    /// A schedule checked more than this long ago is flagged on the page
    /// (app's choice: both US sources are revised at least yearly).
    public static let staleAfterDays = 365

    public static func isStale(_ schedule: Schedule, now: Date) -> Bool {
        now.timeIntervalSince(schedule.reviewed) > Double(staleAfterDays) * 86_400
    }

    /// The schedule for a device region, or nil when none has been checked
    /// at the source for that country.
    public static func schedule(forRegion region: String?) -> Schedule? {
        guard let region, region.uppercased() == unitedStates.region else { return nil }
        return unitedStates
    }

    // MARK: The person

    public enum Smoking: String, Codable, Sendable, CaseIterable, Identifiable {
        case never, former, current

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .never: "Never smoked"
            case .former: "Used to smoke"
            case .current: "Smoke now"
            }
        }
    }

    /// The few answers the recommendations hinge on. All optional; an
    /// unanswered question leaves the checks that depend on it off the list.
    public struct Answers: Codable, Sendable, Equatable {
        public var smoking: Smoking?
        /// 20 pack-years or more (a pack a day for 20 years, two packs for 10).
        public var twentyPackYears: Bool?
        /// The year smoking stopped, for "quit within the past 15 years".
        public var quitYear: Int?

        public init(smoking: Smoking? = nil, twentyPackYears: Bool? = nil, quitYear: Int? = nil) {
            self.smoking = smoking
            self.twentyPackYears = twentyPackYears
            self.quitYear = quitYear
        }

        public var everSmoked: Bool? { smoking.map { $0 != .never } }
    }

    public struct Person: Sendable, Equatable {
        public var age: Int
        public var sex: BiologicalSex
        /// kg/m²; nil when height or weight is missing.
        public var bmi: Double?
        public var answers: Answers
        /// The calendar year now, for birth-year and quit-year rules.
        public var year: Int

        public init(age: Int, sex: BiologicalSex, bmi: Double? = nil, answers: Answers = Answers(), year: Int) {
            self.age = age
            self.sex = sex
            self.bmi = bmi
            self.answers = answers
            self.year = year
        }

        public var birthYear: Int { year - age }
    }

    // MARK: Items

    public enum Kind: String, Sendable {
        case screening, vaccine
    }

    /// A screen in the app that already tracks the same thing.
    public enum Tracked: String, Sendable {
        case bloodPressure, labsBloodSugar, labsLipids, moodScreen
    }

    public enum Interval: Sendable, Equatable {
        /// Once (a one-time test, or a vaccine series completed).
        case once
        case years(Int)
        /// The source gives no repeat interval: no due date is set.
        case notStated
    }

    /// A way of doing a check that has its own interval (stool test yearly, colonoscopy every 10 years).
    public struct Option: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var interval: Interval

        public init(id: String, title: String, interval: Interval) {
            self.id = id
            self.title = title
            self.interval = interval
        }
    }

    public struct Item: Sendable, Identifiable {
        public var id: String
        public var title: String
        public var kind: Kind
        /// Index into the schedule's `sources`.
        public var source: Int
        /// "A", "B"; nil for a vaccine schedule, which has no grades.
        public var grade: String?
        /// When the current recommendation was released, as the source prints it.
        public var released: String
        /// The recommendation in one or two plain sentences, with its interval.
        public var detail: String
        public var ages: ClosedRange<Int>
        /// nil = both sexes.
        public var sex: BiologicalSex?
        public var options: [Option]
        public var tracked: Tracked?
        /// Whether it applies to this person beyond age and sex; nil = can't
        /// tell until a question is answered.
        var applies: @Sendable (Person) -> Bool?
        /// The interval for this person when there are no options.
        var interval: @Sendable (Person) -> Interval

        init(id: String, title: String, kind: Kind, source: Int, grade: String?, released: String, detail: String,
             ages: ClosedRange<Int>, sex: BiologicalSex? = nil, options: [Option] = [], tracked: Tracked? = nil,
             applies: @escaping @Sendable (Person) -> Bool? = { _ in true },
             interval: @escaping @Sendable (Person) -> Interval) {
            self.id = id
            self.title = title
            self.kind = kind
            self.source = source
            self.grade = grade
            self.released = released
            self.detail = detail
            self.ages = ages
            self.sex = sex
            self.options = options
            self.tracked = tracked
            self.applies = applies
            self.interval = interval
        }

        /// "USPSTF grade B · May 2021"
        public func citation(in schedule: Schedule) -> String {
            let source = schedule.sources.indices.contains(self.source) ? schedule.sources[self.source].short : ""
            return grade.map { "\(source) grade \($0) · \(released)" } ?? "\(source) · \(released)"
        }
    }

    /// What applies to `person`: by age and sex first, then by the item's own
    /// rule. `needsAnswer` lists items that might apply but hinge on a
    /// question not yet answered.
    public static func applicable(_ schedule: Schedule, for person: Person) -> (items: [Item], needsAnswer: [Item]) {
        var items: [Item] = []
        var open: [Item] = []
        for item in schedule.items where item.ages.contains(person.age) && (item.sex == nil || item.sex == person.sex) {
            switch item.applies(person) {
            case true?: items.append(item)
            case nil: open.append(item)
            case false?: break
            }
        }
        return (items, open)
    }

    // MARK: The record

    /// What the person entered for one item. Kept on the phone only.
    public struct Record: Codable, Sendable, Equatable {
        public var lastDone: Date?
        /// The chosen `Option.id`, for items with options.
        public var option: String?
        /// "Not for me": already immune, advised otherwise, or declined. Hides the due date.
        public var setAside: Bool
        /// A reminder when it falls due; off unless switched on for this item.
        public var reminder: Bool

        public init(lastDone: Date? = nil, option: String? = nil, setAside: Bool = false, reminder: Bool = false) {
            self.lastDone = lastDone
            self.option = option
            self.setAside = setAside
            self.reminder = reminder
        }
    }

    public enum Status: Sendable, Equatable {
        /// Applies, nothing recorded.
        case noDate
        /// Next due on a day still ahead.
        case next(Date)
        /// The due day has passed.
        case due(since: Date)
        /// Done once; nothing further scheduled.
        case done(Date)
        /// Done on this day; the source sets no repeat interval.
        case noInterval(last: Date)
        case setAside
    }

    /// The interval in force: the chosen option's, else the item's own.
    public static func interval(for item: Item, record: Record?, person: Person) -> Interval {
        if !item.options.isEmpty {
            // Until a way is chosen, the shortest interval is assumed (the cautious reading).
            let chosen = item.options.first { $0.id == record?.option }
            return chosen?.interval ?? item.options.map(\.interval).min(by: { years($0) < years($1) }) ?? .notStated
        }
        return item.interval(person)
    }

    private static func years(_ interval: Interval) -> Int {
        switch interval {
        case .years(let n): n
        case .once, .notStated: Int.max
        }
    }

    /// - Parameter trackedDate: the latest date the app itself holds for this
    ///   item (a blood pressure reading, a lab result, a mood screen); the
    ///   later of it and the typed date counts.
    public static func status(of item: Item, record: Record?, person: Person, trackedDate: Date? = nil, now: Date,
                              calendar: Calendar = .current) -> Status {
        if record?.setAside == true { return .setAside }
        let last = [record?.lastDone, trackedDate].compactMap { $0 }.max()
        guard let last else { return .noDate }
        switch interval(for: item, record: record, person: person) {
        case .once: return .done(last)
        case .notStated: return .noInterval(last: last)
        case .years(let years):
            let due = calendar.date(byAdding: .year, value: years, to: calendar.startOfDay(for: last)) ?? last
            return due > now ? .next(due) : .due(since: due)
        }
    }

    /// The day a reminder would be for: the due day, when the item has one
    /// and its reminder is on.
    public static func reminderDue(_ status: Status, record: Record?) -> Date? {
        guard record?.reminder == true else { return nil }
        switch status {
        case .next(let date), .due(let date): return date
        default: return nil
        }
    }

    /// "Due since March 2026", "Next: March 2029", "Done · June 2024".
    public static func text(for status: Status, monthYear: (Date) -> String) -> String {
        switch status {
        case .noDate: "No date yet"
        case .next(let date): "Next: \(monthYear(date))"
        case .due(let date): "Due since \(monthYear(date))"
        case .done(let date): "Done · \(monthYear(date))"
        case .noInterval(let last): "Last: \(monthYear(last)) · no set interval"
        case .setAside: "Set aside"
        }
    }

    /// Days between reminders for a check that stays undone (`OverdueReminder`):
    /// its own interval, at most a year (app's choice).
    public static func reminderRepeatDays(_ interval: Interval) -> Int {
        switch interval {
        case .years(let years): min(365, years * 365)
        case .once, .notStated: 365
        }
    }

    // MARK: - United States

    /// BMI from which the Task Force counts "overweight" (25 kg/m²).
    public static let overweightBMI = 25.0

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public static let unitedStates = Schedule(
        region: "US",
        country: "United States",
        sources: [
            Source(short: "USPSTF", body: "US Preventive Services Task Force", document: "A and B Recommendations"),
            Source(short: "CDC", body: "Centers for Disease Control and Prevention",
                   document: "Adult Immunization Schedule by Age, United States, 2025 (addendum of 2 July 2025)"),
        ],
        reviewed: date(2026, 11, 17),
        items: usScreenings + usVaccines,
        riskNote: "Some checks are only for people at higher risk and are not listed: hepatitis B, syphilis, tuberculosis, repeat HIV tests, and chlamydia and gonorrhoea (all sexually active women to 24, older when at risk). RSV vaccine from 50 and several other vaccines depend on health conditions. Pregnancy has its own list. Your doctor can say which apply."
    )

    // Every item below was read on the Task Force's site on 17 Nov 2026: the grade and
    // release date from the A and B list, the interval from the statement's own page.
    static let usScreenings: [Item] = [
        Item(id: "us.bp", title: "Blood pressure", kind: .screening, source: 0, grade: "A", released: "April 2021",
             // "The USPSTF suggests annual screening for hypertension in adults 40 years or older and for adults at
             // increased risk … Screening less frequently (ie, every 3 to 5 years) is appropriate for adults aged 18
             // to 39 years not at increased risk for hypertension and with a prior normal blood pressure reading."
             // Overweight is one of the increased-risk groups it names; 3 years is the short end of "3 to 5".
             detail: "A blood pressure reading for every adult. Yearly from 40, or sooner if you are at higher risk such as being overweight; every 3 to 5 years from 18 to 39 after a normal reading. Evidence on the best interval is limited.",
             ages: 18...120, tracked: .bloodPressure,
             interval: { person in
                 person.age >= 40 || (person.bmi ?? 0) >= overweightBMI ? .years(1) : .years(3)
             }),
        Item(id: "us.crc", title: "Colorectal cancer", kind: .screening, source: 0, grade: "A/B", released: "May 2021",
             // Grade B for ages 45 to 49, grade A for 50 to 75. Intervals from the statement's table of strategies.
             detail: "Screening from 45 to 75 (grade B at 45 to 49, A from 50). How often depends on the test you and your doctor choose.",
             ages: 45...75,
             options: [
                 Option(id: "stool", title: "Stool test (FIT or gFOBT), every year", interval: .years(1)),
                 Option(id: "sdna", title: "Stool DNA-FIT, every 1 to 3 years", interval: .years(3)),
                 Option(id: "ctc", title: "CT colonography, every 5 years", interval: .years(5)),
                 Option(id: "sig", title: "Flexible sigmoidoscopy, every 5 years", interval: .years(5)),
                 Option(id: "colonoscopy", title: "Colonoscopy, every 10 years", interval: .years(10)),
             ],
             interval: { _ in .years(1) }),
        Item(id: "us.cervical", title: "Cervical cancer", kind: .screening, source: 0, grade: "A", released: "August 2018",
             detail: "From 21 to 29, a cervical cytology (Pap) test every 3 years. From 30 to 65, cytology every 3 years, or an HPV test alone or with cytology every 5 years.",
             ages: 21...65, sex: .female,
             options: [
                 Option(id: "cytology", title: "Cytology (Pap), every 3 years", interval: .years(3)),
                 Option(id: "hpv", title: "HPV test, alone or with cytology, every 5 years (from 30)", interval: .years(5)),
             ],
             interval: { _ in .years(3) }),
        Item(id: "us.breast", title: "Breast cancer", kind: .screening, source: 0, grade: "B", released: "April 2024",
             detail: "A screening mammogram every 2 years from 40 to 74.",
             ages: 40...74, sex: .female, interval: { _ in .years(2) }),
        Item(id: "us.diabetes", title: "Prediabetes and type 2 diabetes", kind: .screening, source: 0, grade: "B", released: "August 2021",
             // "Screening every 3 years may be a reasonable approach for adults with normal blood glucose levels."
             detail: "A blood sugar test (HbA1c or fasting glucose) from 35 to 70 for adults who are overweight (BMI 25 or more). Every 3 years may be reasonable after a normal result. BMI can't tell muscle from fat, so ask your doctor if yours is high from lifting.",
             ages: 35...70, tracked: .labsBloodSugar,
             applies: { person in person.bmi.map { $0 >= overweightBMI } },
             interval: { _ in .years(3) }),
        Item(id: "us.lipids", title: "Cholesterol and 10-year heart risk", kind: .screening, source: 0, grade: "B", released: "August 2022",
             // The B grade is for prescribing a statin to adults 40 to 75 with a risk factor and a 10-year risk of
             // 10% or more; estimating that risk needs a cholesterol test. The statement gives no testing interval.
             detail: "From 40 to 75 the Task Force recommends a statin for adults with a risk factor and a 10-year heart risk of 10% or more. Working out that risk takes a cholesterol test; it sets no interval for repeating it.",
             ages: 40...75, tracked: .labsLipids, interval: { _ in .notStated }),
        Item(id: "us.hcv", title: "Hepatitis C", kind: .screening, source: 0, grade: "B", released: "March 2020",
             // "Most adults need to be screened only once."
             detail: "One blood test for adults 18 to 79. Most adults need it only once.",
             ages: 18...79, interval: { _ in .once }),
        Item(id: "us.hiv", title: "HIV", kind: .screening, source: 0, grade: "A", released: "June 2019",
             // "The USPSTF found insufficient evidence to determine appropriate or optimal time intervals … for repeat HIV screening."
             detail: "A test at least once from 15 to 65. Repeat tests are for people at higher risk; the Task Force found too little evidence to set an interval.",
             ages: 18...65, interval: { _ in .once }),
        Item(id: "us.lung", title: "Lung cancer", kind: .screening, source: 0, grade: "B", released: "March 2021",
             detail: "A low-dose CT scan every year from 50 to 80 for people with a 20 pack-year history who smoke now or quit within the past 15 years. It stops 15 years after quitting.",
             ages: 50...80,
             applies: { person in
                 guard let smoking = person.answers.smoking else { return nil }
                 if smoking == .never { return false }
                 guard let heavy = person.answers.twentyPackYears else { return nil }
                 guard heavy else { return false }
                 if smoking == .current { return true }
                 guard let quit = person.answers.quitYear else { return nil }
                 return person.year - quit <= 15
             },
             interval: { _ in .years(1) }),
        Item(id: "us.aaa", title: "Abdominal aortic aneurysm", kind: .screening, source: 0, grade: "B", released: "December 2019",
             detail: "One ultrasound for men 65 to 75 who have ever smoked.",
             ages: 65...75, sex: .male,
             applies: { person in person.answers.everSmoked },
             interval: { _ in .once }),
        Item(id: "us.bone", title: "Osteoporosis", kind: .screening, source: 0, grade: "B", released: "January 2025",
             // "The evidence related to screening intervals for osteoporosis is limited."
             detail: "A bone density scan for women 65 and older (and for younger women after menopause who are at higher risk). The Task Force sets no interval for repeating it.",
             ages: 65...120, sex: .female, interval: { _ in .notStated }),
        Item(id: "us.mood", title: "Depression and anxiety questions", kind: .screening, source: 0, grade: "B", released: "June 2023",
             // Depression: all adults. Anxiety: adults 64 or younger. "There is little evidence regarding optimal
             // timing for screening, or screening interval."
             detail: "Screening questions for depression in all adults and for anxiety up to 64, where a positive result can be followed up. There is little evidence on how often. The app's own four-question check covers the first step.",
             ages: 18...120, tracked: .moodScreen, interval: { _ in .notStated }),
    ]

    // CDC adult schedule by age, 2025 edition with the 2 July 2025 addendum, and its notes
    // ("Routine vaccination"), read on cdc.gov on 17 Nov 2026. The adult schedule starts at 19.
    static let usVaccines: [Item] = [
        Item(id: "us.flu", title: "Flu vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "Age 19 years or older: 1 dose any influenza vaccine appropriate for age and health status annually."
             detail: "One dose every year. From 65 a high-dose or adjuvanted vaccine is preferred.",
             ages: 19...120, interval: { _ in .years(1) }),
        Item(id: "us.tdap", title: "Tetanus, diphtheria and whooping cough (Td or Tdap)", kind: .vaccine, source: 1, grade: nil,
             released: "2025 schedule",
             // "Completed primary series and received at least 1 dose Tdap at age 10 years or older: Td or Tdap every 10 years thereafter."
             detail: "One dose of Tdap if you never had one, then a Td or Tdap booster every 10 years.",
             ages: 19...120, interval: { _ in .years(10) }),
        Item(id: "us.covid", title: "COVID-19 vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule; changed since",
             // The page shows the 2024-25 formula (1 dose at 19 to 64, a second dose 6 months later from 65). In
             // October 2025 the CDC moved COVID-19 to individual decision-making; changes after 11 June 2025 were
             // stayed by a court (CRS IN12684, 29 July 2026). Too unsettled to date.
             detail: "Federal advice on this vaccine has changed more than once since 2025 and part of it is tied up in court. Ask your pharmacist or doctor what applies to you this season. The app sets no due date.",
             ages: 19...120, interval: { _ in .notStated }),
        Item(id: "us.shingles", title: "Shingles vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "Age 50 years or older: 2-dose series recombinant zoster vaccine (RZV, Shingrix) 2-6 months apart"
             detail: "From 50, two doses 2 to 6 months apart. Enter the date of the second dose.",
             ages: 50...120, interval: { _ in .once }),
        Item(id: "us.pneumococcal", title: "Pneumococcal vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "Age 50 years or older …: 1 dose PCV15 or 1 dose PCV20 or 1 dose PCV21. If PCV15 is used, administer
             // 1 dose PPSV23 at least 1 year after the PCV15 dose."
             detail: "From 50, one dose of PCV20 or PCV21 (or PCV15 followed a year later by PPSV23) if you have not had one.",
             ages: 50...120, interval: { _ in .once }),
        Item(id: "us.rsv", title: "RSV vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "Age 75 years or older … Unvaccinated: 1 dose (Arexvy or Abrysvo or mResvia). Additional doses not recommended."
             detail: "From 75, one dose if you have not had one. Further doses are not recommended.",
             ages: 75...120, interval: { _ in .once }),
        Item(id: "us.hpv", title: "HPV vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "All persons through age 26 years: complete 2- or 3-dose series"; 27 to 45 is shared clinical decision-making.
             detail: "Through age 26, complete the 2- or 3-dose series if you have not. From 27 to 45 it is a decision to make with your doctor.",
             ages: 19...26, interval: { _ in .once }),
        Item(id: "us.hepb", title: "Hepatitis B vaccine", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "Age 19 through 59 years: complete a 2- or 3- or 4-dose series"
             detail: "From 19 to 59, complete the 2-, 3- or 4-dose series if you never did. Enter the date of the last dose.",
             ages: 19...59, interval: { _ in .once }),
        Item(id: "us.mmr", title: "Measles, mumps and rubella (MMR)", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "1 or 2 doses depending on indication (if born in 1957 or later)"; "No evidence of immunity …: 1 dose"
             detail: "If you were born in 1957 or later and have no record of vaccination or immunity, one dose.",
             ages: 19...120,
             applies: { person in person.birthYear >= 1957 },
             interval: { _ in .once }),
        Item(id: "us.varicella", title: "Chickenpox (varicella)", kind: .vaccine, source: 1, grade: nil, released: "2025 schedule",
             // "2 doses (if born in 1980 or later)"; "No evidence of immunity to varicella: 2-dose series 4-8 weeks apart"
             detail: "If you were born in 1980 or later and have no record of vaccination or of chickenpox, two doses 4 to 8 weeks apart.",
             ages: 19...120,
             applies: { person in person.birthYear >= 1980 },
             interval: { _ in .once }),
    ]
}
