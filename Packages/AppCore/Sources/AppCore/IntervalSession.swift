import Foundation

// A structured cardio session as one plain value: warm-up, work and recovery
// intervals with their targets, cool-down. Foundation only and Codable, with
// no reference to anything else in AppCore, so the Watch app (which does not
// link AppCore) can compile this one file and run the session: add
// `Packages/AppCore/Sources/AppCore/IntervalSession.swift` (and, for the bpm
// bands, `IntervalSession+Zones.swift`, which needs only
// `HeartRateZoneScheme.swift`) to its sources in project.yml, as
// `CardioZoneTracker.swift` is, and send `encoded()` over WatchConnectivity
// (`Data` is a property-list type). Every type is declared `nonisolated`, so
// in a target whose default isolation is the main actor the value still
// decodes and is read on any thread.
//
// Targets are named the way the Watch's cardio mode names them
// (`CardioTarget`): "easy" is `HeartRateZoneScheme.easyBand`, the band easy
// cardio and the Watch's Easy target use, and the hard intervals are zones of
// whichever scheme the user picked. So the phone, the Watch and the zone
// settings always agree on the numbers.
//
// The protocol itself:
// - Four rounds of four minutes at 90-95% of maximum heart rate with three
//   minutes of active rest at 70% raised VO2max by 7.2% in eight weeks, more
//   than the same work done at lactate threshold or as long slow distance
//   (Helgerud J, et al. Aerobic high-intensity intervals improve VO2max more
//   than moderate training. Med Sci Sports Exerc 2007;39(4):665-671; 40
//   moderately trained men, three sessions a week for eight weeks; abstract
//   read 2026-11-17 through PubMed E-utilities). Tensile offers one session a
//   week, a smaller dose than the trial: the app's choice, said in the UI.
// - Across 53 trials, long intervals (2 minutes or more), 15 minutes or more
//   of hard work in a session, and 4-12 weeks or more did most; short, small
//   doses still beat doing nothing (Wen D, et al. Effects of different
//   protocols of high intensity interval training for VO2max improvements in
//   adults. J Sci Med Sport 2019;22(8):941-947; abstract read 2026-11-17). So
//   the standard session has 16 hard minutes and the short one 12, under that
//   line: the UI says so.
// - Helgerud's 70% of maximum for the easy minutes sits inside the easy band
//   (40-60% of heart-rate reserve; the Watch alone uses a stand-in resting
//   rate). Zones 4-5 on the heart-rate-reserve scale cover 90-95% of maximum
//   (percent-of-maximum zones were dropped, evidence audit 17 Nov 2026). Heart rate lags a minute or two behind
//   effort in each round, so the effort cue leads. Warm-up and cool-down
//   lengths and the effort numbers are the app's choice.

/// One cardio session, step by step.
public nonisolated struct IntervalSession: Codable, Sendable, Equatable, Identifiable {
    /// What it is done on.
    public nonisolated enum Modality: String, Codable, Sendable, CaseIterable, Identifiable {
        case bike, rower, treadmill, outdoorRun, outdoorRide

        public var id: String { rawValue }

        /// "Bike", for pickers and titles.
        public var label: String {
            switch self {
            case .bike: "Bike"
            case .rower: "Rower"
            case .treadmill: "Treadmill"
            case .outdoorRun: "Outdoor run"
            case .outdoorRide: "Outdoor ride"
            }
        }

        public var isOutdoor: Bool { self == .outdoorRun || self == .outdoorRide }

        public var systemImage: String {
            switch self {
            case .bike: "figure.indoor.cycle"
            case .rower: "figure.rower"
            case .treadmill: "figure.run.treadmill"
            case .outdoorRun: "figure.run"
            case .outdoorRide: "figure.outdoor.cycle"
            }
        }

        /// The Watch cardio mode's activity (`CardioActivity.rawValue`), so
        /// the Watch can start the right workout type.
        public var watchActivity: String {
            switch self {
            case .bike: "indoorCycle"
            case .rower: "rower"
            case .treadmill: "treadmill"
            case .outdoorRun: "outdoorRun"
            case .outdoorRide: "outdoorCycle"
            }
        }
    }

    public nonisolated enum Phase: String, Codable, Sendable {
        case warmUp, work, recovery, coolDown

        public var label: String {
            switch self {
            case .warmUp: "Warm-up"
            case .work: "Hard"
            case .recovery: "Easy"
            case .coolDown: "Cool-down"
            }
        }

        /// True for the hard intervals: the minutes that count as vigorous.
        public var isHard: Bool { self == .work }
    }

    /// The heart-rate band to hold during a step.
    public nonisolated enum Band: Codable, Sendable, Equatable, Hashable {
        /// No band: slow down as you like (the cool-down).
        case none
        /// The easy band (`HeartRateZoneScheme.easyBand`, the Watch's "Easy").
        case easy
        /// From the start of zone `low` up to the end of zone `high` in the
        /// user's scheme; zone 5 has no top.
        case zones(low: Int, high: Int)

        /// The Watch cardio mode's stored target (`CardioTarget.storage`):
        /// "off", "easy", or the lower zone ("z4"). For a zone range the
        /// Watch should hold the whole range (`IntervalSession+Zones`), so
        /// going above the lower zone is never a "too hard" tap.
        public var watchStorage: String {
            switch self {
            case .none: "off"
            case .easy: "easy"
            case .zones(let low, _): "z\(low)"
            }
        }

        /// "Easy", "Zone 4-5".
        public var title: String {
            switch self {
            case .none: "Easy or slower"
            case .easy: "Easy"
            case .zones(let low, let high): low == high ? "Zone \(low)" : "Zone \(low)-\(high)"
            }
        }
    }

    /// What to hold during a step: a heart-rate band and an effort, so it
    /// can be run with or without a heart-rate reading.
    public nonisolated struct Target: Codable, Sendable, Equatable {
        public var band: Band
        /// Effort out of 10.
        public var lowEffort: Int
        public var highEffort: Int
        /// The talk test, in plain words.
        public var cue: String

        public init(band: Band, effort: ClosedRange<Int>, cue: String) {
            self.band = band
            lowEffort = effort.lowerBound
            highEffort = effort.upperBound
            self.cue = cue
        }

        /// "Effort 8-9 of 10".
        public var effortText: String {
            lowEffort == highEffort ? "Effort \(lowEffort) of 10" : "Effort \(lowEffort)-\(highEffort) of 10"
        }
    }

    public nonisolated struct Step: Codable, Sendable, Equatable, Identifiable {
        /// Position in the session, from 0.
        public var index: Int
        public var phase: Phase
        public var seconds: Int
        public var target: Target
        /// The round a work or recovery step belongs to, from 1; nil otherwise.
        public var round: Int?

        public var id: Int { index }

        public init(index: Int, phase: Phase, seconds: Int, target: Target, round: Int? = nil) {
            self.index = index
            self.phase = phase
            self.seconds = seconds
            self.target = target
            self.round = round
        }

        /// "Hard 2 of 4", "Warm-up".
        public func title(rounds: Int) -> String {
            guard let round, phase == .work else { return phase.label }
            return "\(phase.label) \(round) of \(rounds)"
        }

        /// "4 min", "90 s".
        public var lengthText: String {
            seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
        }
    }

    /// The format's version, so a reader can refuse one it doesn't know.
    public static let currentVersion = 1

    public var version: Int
    /// Stable for a kind of session on a modality, e.g. "4x4-bike".
    public var id: String
    /// "4 × 4 min · Bike".
    public var title: String
    public var modality: Modality
    /// Hard intervals in the session.
    public var rounds: Int
    public var steps: [Step]

    public init(id: String, title: String, modality: Modality, rounds: Int, steps: [Step], version: Int = IntervalSession.currentVersion) {
        self.version = version
        self.id = id
        self.title = title
        self.modality = modality
        self.rounds = rounds
        self.steps = steps
    }

    // MARK: Totals

    public var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    /// Whole minutes, rounded.
    public var totalMinutes: Int { Int((Double(totalSeconds) / 60).rounded()) }
    /// Seconds in the hard intervals.
    public var hardSeconds: Int { steps.filter(\.phase.isHard).reduce(0) { $0 + $1.seconds } }
    /// The hard minutes: what the session can promise toward vigorous minutes.
    public var hardMinutes: Int { hardSeconds / 60 }

    /// The step running `elapsed` seconds in, and the seconds left in it;
    /// nil once the session is over.
    public func step(at elapsed: TimeInterval) -> (step: Step, remaining: Int)? {
        guard elapsed >= 0 else { return steps.first.map { ($0, $0.seconds) } }
        var start = 0.0
        for step in steps {
            let end = start + Double(step.seconds)
            if elapsed < end { return (step, Int((end - elapsed).rounded(.up))) }
            start = end
        }
        return nil
    }

    // MARK: Sending

    /// JSON, for a file or a WatchConnectivity message.
    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Nil for data that isn't a session, or one of a newer format.
    public static func decoded(from data: Data) -> IntervalSession? {
        guard let session = try? JSONDecoder().decode(IntervalSession.self, from: data),
              session.version <= currentVersion else { return nil }
        return session
    }

    // MARK: The two sessions

    /// The standard session: 10 minutes of warm-up, four rounds of four hard
    /// minutes with three easy between, 5 minutes of cool-down. 40 minutes,
    /// 16 of them hard.
    public static func fourByFour(_ modality: Modality) -> IntervalSession {
        make(id: "4x4", rounds: 4, warmUp: 600, coolDown: 300, modality: modality)
    }

    /// The shorter session: 8 minutes of warm-up, three rounds, 4 minutes of
    /// cool-down. 30 minutes, 12 of them hard.
    public static func threeByFour(_ modality: Modality) -> IntervalSession {
        make(id: "3x4", rounds: 3, warmUp: 480, coolDown: 240, modality: modality)
    }

    /// Hard and easy interval lengths (Helgerud 2007).
    public static let workSeconds = 240
    public static let recoverySeconds = 180
    /// The hard band: zones 4-5 hold Helgerud's 90-95% of maximum on the
    /// reserve scale; the lower edge leaves room for heart rate climbing in each round.
    public static let workBand = Band.zones(low: 4, high: 5)

    static let warmUpTarget = Target(band: .easy, effort: 3...5,
                                     cue: "Build up slowly; you can still talk in full sentences.")
    static let workTarget = Target(band: workBand, effort: 8...9,
                                   cue: "Hard: a few words at a time, not a sentence. A pace you can hold for all four minutes; heart rate climbs toward 90-95% of your maximum by the end.")
    static let recoveryTarget = Target(band: .easy, effort: 3...4,
                                       cue: "Keep moving easily until your breathing settles.")
    static let coolDownTarget = Target(band: .none, effort: 2...3,
                                       cue: "Easy, slowing down.")

    static func make(id: String, rounds: Int, warmUp: Int, coolDown: Int, modality: Modality) -> IntervalSession {
        let rounds = max(1, rounds)
        var steps: [Step] = []
        func add(_ phase: Phase, _ seconds: Int, _ target: Target, round: Int? = nil) {
            steps.append(Step(index: steps.count, phase: phase, seconds: seconds, target: target, round: round))
        }
        add(.warmUp, warmUp, warmUpTarget)
        for round in 1...rounds {
            add(.work, workSeconds, workTarget, round: round)
            // The cool-down follows the last hard interval directly.
            if round < rounds { add(.recovery, recoverySeconds, recoveryTarget, round: round) }
        }
        add(.coolDown, coolDown, coolDownTarget)
        return IntervalSession(id: "\(id)-\(modality.rawValue)",
                               title: "\(rounds) × \(workSeconds / 60) min · \(modality.label)",
                               modality: modality, rounds: rounds, steps: steps)
    }
}
