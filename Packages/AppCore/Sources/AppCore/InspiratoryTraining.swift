import Foundation

/// Inspiratory muscle strength training (IMST): 30 hard breaths a day in
/// through a handheld resistance trainer (docs/research/next-features-2026-11.md,
/// W12). Offered only when the home 7-day systolic average is 120 or more.
///
/// Evidence (moderate; small trials, mostly midlife and older adults):
/// - Li et al., J Clin Hypertens 2023 (meta-analysis with trial sequential
///   analysis of 12 RCTs, n = 386): SBP −7.9 mmHg, DBP −3.8 mmHg.
/// - Craighead et al., J Am Heart Assoc 2021;10:e020980 (PMID 34184544,
///   abstract read 18 Nov 2026): double-blind, sham-controlled; 36 people
///   aged 50-79 with SBP ≥ 120 completed it. 30 breaths a day, 6 days a
///   week, for 6 weeks at 75% of maximal inspiratory pressure (sham 15%).
///   Office systolic fell from 135 to 126 mmHg (diastolic 79 to 77), about
///   75% of it still there 6 weeks after stopping; 24-hour systolic was lower
///   than with sham; about 95% of sessions were done.
/// Nobody in these trials started below 120, so the app never offers it
/// there, and never without a reliable home average to judge by.
public enum InspiratoryTraining {
    /// Offered from this 7-day home systolic average, mmHg: the key trial's
    /// entry level (Craighead 2021: SBP ≥ 120), and the top of normal in the
    /// ACC/AHA categories (`HomeBloodPressure.category`).
    public static let systolicThreshold = 120.0
    /// Breaths a session (Craighead 2021).
    public static let breathsPerSession = 30
    /// Sessions a week (Craighead 2021).
    public static let sessionsPerWeek = 6
    /// Weeks the key trial ran (Craighead 2021).
    public static let trialWeeks = 6
    /// The trial's resistance, as a share of maximal inspiratory pressure
    /// (Craighead 2021). A home trainer can't measure that, so the app says
    /// "hard enough that the last few of 30 breaths are a real effort".
    public static let trialResistanceShare = 0.75
    /// How old the home average may be, days (app's choice: the 7-day check
    /// is repeated within a year at the latest, `HomeBloodPressure.repeatMonths`).
    public static let maxAverageAgeDays = 365

    /// Effect sizes, for the card (Li 2023; Craighead 2021).
    public static let metaAnalysisSystolicDrop = 7.9
    public static let metaAnalysisDiastolicDrop = 3.8
    public static let metaAnalysisTrials = 12
    public static let metaAnalysisParticipants = 386

    // MARK: Gate

    public enum Eligibility: Sendable, Equatable {
        /// Average at or above the threshold: offer it.
        case offered(systolic: Double, weekEnding: Date)
        /// A reliable average below the threshold: don't.
        case belowThreshold(systolic: Double, weekEnding: Date)
        /// No reliable 7-day average in the last year: don't.
        case noAverage

        public var isOffered: Bool {
            if case .offered = self { return true }
            return false
        }
    }

    /// The newest reliable 7-day home average (`HomeBloodPressure.weekCheck`
    /// with 12+ readings, day 1 left out) ending on a day with a reading in
    /// the last `maxAverageAgeDays`. A week still filling in doesn't hide
    /// the last complete one.
    public static func latestHomeAverage(_ readings: [HomeBloodPressure.Reading], now: Date = .now,
                                         calendar: Calendar = .current) -> (systolic: Double, weekEnding: Date)? {
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -maxAverageAgeDays, to: today) else { return nil }
        let days = Set(readings.filter { $0.date <= now }.map { calendar.startOfDay(for: $0.date) }).filter { $0 >= oldest }
        for day in days.sorted(by: >) {
            // The 7 days ending on that day (`weekCheck` works in whole days).
            let check = HomeBloodPressure.weekCheck(readings.filter { $0.date <= now }, asOf: day, calendar: calendar)
            if check.isReliable, let systolic = check.systolic { return (systolic, day) }
        }
        return nil
    }

    public static func eligibility(_ readings: [HomeBloodPressure.Reading], now: Date = .now,
                                   calendar: Calendar = .current) -> Eligibility {
        guard let average = latestHomeAverage(readings, now: now, calendar: calendar) else { return .noAverage }
        return average.systolic >= systolicThreshold - 1e-9
            ? .offered(systolic: average.systolic, weekEnding: average.weekEnding)
            : .belowThreshold(systolic: average.systolic, weekEnding: average.weekEnding)
    }

    // MARK: Log

    public struct Session: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var date: Date
        public var breaths: Int

        public init(id: UUID = UUID(), date: Date, breaths: Int) {
            self.id = id
            self.date = date
            self.breaths = breaths
        }

        /// A full session: all 30 breaths.
        public var isComplete: Bool { breaths >= InspiratoryTraining.breathsPerSession }
    }

    /// Days in the last 7 (today included) with a full session.
    public static func fullDaysThisWeek(_ sessions: [Session], now: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return 0 }
        return Set(sessions.filter { $0.isComplete && $0.date >= start && $0.date < end }.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Today has a full session.
    public static func doneToday(_ sessions: [Session], now: Date = .now, calendar: Calendar = .current) -> Bool {
        sessions.contains { $0.isComplete && calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Days with a full session since the first one (the trial's 6 weeks are 36 sessions).
    public static func fullDays(_ sessions: [Session], calendar: Calendar = .current) -> Int {
        Set(sessions.filter(\.isComplete).map { calendar.startOfDay(for: $0.date) }).count
    }
}
