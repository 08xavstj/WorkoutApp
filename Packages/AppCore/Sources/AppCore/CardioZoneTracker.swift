import Foundation

// The Watch's cardio mode, as plain values: which activities it offers, the
// target band, the live zone clock with its wrist taps, and the end summary.
// Needs only Foundation and `HeartRateZoneScheme.swift`, so the Watch app
// compiles both files on its own (project.yml, `TensileWatch: sources:`).

/// The workouts the Watch app's cardio mode can record: steady cardio, court
/// and field sports, and snow sports. Each saves as its own Apple Health
/// workout type, so the phone (and Apple Health) shows "Squash", not "Other".
/// Raw values are stored (`cardioLastActivity`, workout metadata), so cases
/// can be added but never renamed.
public nonisolated enum CardioActivity: String, Codable, Sendable, CaseIterable, Identifiable {
    // Steady cardio.
    case outdoorRun, treadmill, outdoorWalk, hiking, outdoorCycle, indoorCycle, rower, elliptical, stairs, hiit
    // Court and field sports.
    case squash, badminton, tennis, pickleball, tableTennis, basketball, volleyball
    case indoorSoccer, outdoorSoccer, ultimateFrisbee, hockey, climbing
    // Snow.
    case crossCountrySkiing, downhillSkiing, snowboarding, skating
    case other

    /// How distance is measured, if at all.
    public nonisolated enum Movement: Sendable, Equatable {
        /// Walking and running: distance, shown with a pace.
        case onFoot
        /// Cycling: distance, shown with a speed.
        case cycling
        /// Cross-country skiing: distance, shown with a speed.
        case snow
        /// Machines, mixed work and court sports: no distance shown.
        case stationary

        /// Distance is shown as a speed rather than a pace.
        public var showsSpeed: Bool { self == .cycling || self == .snow }
    }

    /// The groups the pickers show, in order.
    public nonisolated enum Category: String, Sendable, CaseIterable, Identifiable {
        case cardio, sport, snow

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .cardio: "Cardio"
            case .sport: "Sports"
            case .snow: "Snow"
            }
        }
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .outdoorRun: "Outdoor run"
        case .treadmill: "Treadmill"
        case .outdoorWalk: "Outdoor walk"
        case .hiking: "Hike"
        case .outdoorCycle: "Outdoor cycle"
        case .indoorCycle: "Indoor cycle"
        case .rower: "Rower"
        case .elliptical: "Elliptical"
        case .stairs: "Stairs"
        case .hiit: "HIIT"
        case .squash: "Squash"
        case .badminton: "Badminton"
        case .tennis: "Tennis"
        case .pickleball: "Pickleball"
        case .tableTennis: "Table tennis"
        case .basketball: "Basketball"
        case .volleyball: "Volleyball"
        case .indoorSoccer: "Indoor soccer"
        case .outdoorSoccer: "Soccer"
        case .ultimateFrisbee: "Ultimate frisbee"
        case .hockey: "Hockey"
        case .climbing: "Climbing"
        case .crossCountrySkiing: "Cross-country ski"
        case .downhillSkiing: "Downhill ski"
        case .snowboarding: "Snowboard"
        case .skating: "Skating"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .outdoorRun: "figure.run"
        case .treadmill: "figure.run.treadmill"
        case .outdoorWalk: "figure.walk"
        case .hiking: "figure.hiking"
        case .outdoorCycle: "figure.outdoor.cycle"
        case .indoorCycle: "figure.indoor.cycle"
        case .rower: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stair.stepper"
        case .hiit: "figure.highintensity.intervaltraining"
        case .squash: "figure.squash"
        case .badminton: "figure.badminton"
        case .tennis: "figure.tennis"
        case .pickleball: "figure.pickleball"
        case .tableTennis: "figure.table.tennis"
        case .basketball: "figure.basketball"
        case .volleyball: "figure.volleyball"
        case .indoorSoccer: "figure.indoor.soccer"
        case .outdoorSoccer: "figure.outdoor.soccer"
        case .ultimateFrisbee: "figure.disc.sports"
        case .hockey: "figure.hockey"
        case .climbing: "figure.climbing"
        case .crossCountrySkiing: "figure.skiing.crosscountry"
        case .downhillSkiing: "figure.skiing.downhill"
        case .snowboarding: "figure.snowboarding"
        case .skating: "figure.skating"
        case .other: "figure.mixed.cardio"
        }
    }

    public var category: Category {
        switch self {
        case .outdoorRun, .treadmill, .outdoorWalk, .hiking, .outdoorCycle, .indoorCycle,
             .rower, .elliptical, .stairs, .hiit, .other:
            .cardio
        case .squash, .badminton, .tennis, .pickleball, .tableTennis, .basketball, .volleyball,
             .indoorSoccer, .outdoorSoccer, .ultimateFrisbee, .hockey, .climbing:
            .sport
        case .crossCountrySkiing, .downhillSkiing, .snowboarding, .skating:
            .snow
        }
    }

    /// Every activity in `category`, in menu order.
    public static func all(in category: Category) -> [CardioActivity] {
        allCases.filter { $0.category == category }
    }

    /// Whether a heart-rate target makes sense. Only for steady cardio: in
    /// stop-and-go sports, heart rate follows the play, not the player's
    /// choice of pace, so taps to "ease off" or "pick it up" would be noise.
    /// A sport records with no target and still counts time in each zone.
    public var takesTarget: Bool { category == .cardio }

    /// Outdoors, indoors, or not known (the Watch then doesn't assume either).
    public var isOutdoor: Bool? {
        switch self {
        case .outdoorRun, .outdoorWalk, .hiking, .outdoorCycle, .outdoorSoccer, .ultimateFrisbee,
             .crossCountrySkiing, .downhillSkiing, .snowboarding:
            true
        case .treadmill, .indoorCycle, .rower, .elliptical, .stairs, .hiit,
             .squash, .badminton, .tableTennis, .basketball, .volleyball, .indoorSoccer, .climbing:
            false
        case .tennis, .pickleball, .hockey, .skating, .other:
            nil
        }
    }

    public var movement: Movement {
        switch self {
        case .outdoorRun, .treadmill, .outdoorWalk, .hiking: .onFoot
        // An indoor bike gives the Watch no distance unless the bike itself sends it.
        case .outdoorCycle: .cycling
        case .crossCountrySkiing: .snow
        // Downhill: the average speed would include the lift rides. Court and
        // field sports: distance on a pitch says little about the game.
        default: .stationary
        }
    }
}

/// What the wrist holds you to during cardio: nothing, the easy band, or one zone.
public nonisolated enum CardioTarget: Sendable, Equatable, Hashable {
    case off
    /// `HeartRateZoneScheme.easyBand`: moderate effort, the same bpm whatever zones are shown.
    case easy
    /// One of zones 1-5 of the scheme in use.
    case zone(Int)

    /// "off", "easy" or "z2", for UserDefaults.
    public var storage: String {
        switch self {
        case .off: "off"
        case .easy: "easy"
        case .zone(let zone): "z\(zone)"
        }
    }

    public init(storage: String) {
        if storage == "easy" {
            self = .easy
        } else if storage.hasPrefix("z"), let zone = Int(storage.dropFirst()), (1...HeartRateZoneScheme.zoneCount).contains(zone) {
            self = .zone(zone)
        } else {
            self = .off
        }
    }

    /// Every choice, in menu order.
    public static let all: [CardioTarget] = [.off, .easy] + (1...HeartRateZoneScheme.zoneCount).map { CardioTarget.zone($0) }

    public var title: String {
        switch self {
        case .off: "No target"
        case .easy: "Easy"
        case .zone(let zone): "Zone \(zone)"
        }
    }

    /// The bpm band to stay in, or nil with no target.
    public func band(in scheme: HeartRateZoneScheme) -> HeartRateBand? {
        switch self {
        case .off: nil
        case .easy: scheme.easyBand
        case .zone(let zone): scheme.band(forZone: zone)
        }
    }
}

/// Keeps the live numbers of a cardio workout from the heart-rate readings as
/// they arrive: time in each zone, time in the target band, and when to tap
/// the wrist for leaving the band or coming back.
///
/// Time is counted the way the phone counts zone minutes
/// (`HeartRateZoneScheme.zoneMinutes`): a reading stands for the time until
/// the next one, at most two minutes, and nothing is counted across a gap of
/// more than ten minutes or across a pause.
public nonisolated struct CardioZoneTracker: Sendable, Equatable {
    /// A reason to tap the wrist.
    public nonisolated enum Alert: Sendable, Equatable {
        /// Heart rate has stayed above the band: ease off.
        case above
        /// Heart rate has stayed below the band: pick it up.
        case below
        /// Heart rate is in the band (first time, or back after leaving).
        case inBand
    }

    /// Where heart rate stands against the target, once it has held there.
    public nonisolated enum BandState: Sendable, Equatable {
        /// No target set.
        case off
        /// Not in the band yet (warming up, or just resumed): being under it is not a miss.
        case settling
        case inBand, above, below
    }

    // The four timings are the app's choice: no study sets how long a heart
    // rate should sit outside a band before an alert. They are long enough
    // that a hill, a noisy optical reading or a stop at a crossing doesn't
    // buzz, and short enough that a pace that is too hard is caught within
    // half a minute. An earlier note (watch-features.md §2.2) suggested 30 s
    // to leave; 20 s is used because the Watch's own heart rate already lags
    // effort by several seconds.
    /// Seconds heart rate must stay outside the band before the "above" or "below" tap.
    public static let leaveSeconds: TimeInterval = 20
    /// Seconds heart rate must stay inside the band before the "in band" tap.
    public static let returnSeconds: TimeInterval = 10
    /// While still above the band, the tap repeats this often and no more.
    /// Only "above" repeats: going too hard is the mistake an easy day can't
    /// afford, while being under the band is often on purpose (the recovery
    /// between intervals, a stop at a crossing) and one tap has said it.
    public static let remindSeconds: TimeInterval = 120
    /// A break in readings longer than this starts the count again: time that
    /// wasn't measured doesn't count as "stayed outside".
    public static let staleSeconds: TimeInterval = 30

    public let scheme: HeartRateZoneScheme
    /// The band to hold, or nil with no target. An interval session moves it
    /// from step to step (`retarget`).
    public private(set) var band: HeartRateBand?

    /// Seconds in zones 1-5 (index 0 = zone 1).
    public private(set) var zoneSeconds: [Double]
    /// Seconds with heart rate under zone 1 (always 0 for a scheme with no floor).
    public private(set) var belowZoneSeconds = 0.0
    /// Seconds inside the target band.
    public private(set) var bandSeconds = 0.0
    /// Seconds a heart rate was counted for: the zones plus below zone 1.
    public private(set) var measuredSeconds = 0.0
    public private(set) var state: BandState
    /// The latest reading and its zone (nil below zone 1 or before any reading).
    public private(set) var currentBpm: Double?
    public private(set) var currentZone: Int?
    public private(set) var maximumBpm: Double?

    private nonisolated struct Reading: Sendable, Equatable {
        var bpm: Double
        var date: Date
    }

    private nonisolated struct Pending: Sendable, Equatable {
        var side: HeartRateBand.Side
        var since: Date
    }

    private var last: Reading?
    private var pending: Pending?
    private var lastAlertAt: Date?
    private var isPaused = false
    private var weightedBpm = 0.0
    /// No taps before this (just after `retarget`).
    private var quietUntil: Date?

    /// After a step of an interval session changes the band, no tap for this
    /// long: heart rate lags effort by a minute or two in each round
    /// (`IntervalSession`'s notes, Helgerud 2007), so a "too hard" tap at the
    /// start of the easy minutes would be noise; the step's effort cue leads
    /// instead. 60 s is the app's choice, at the short end of that lag.
    public static let retargetQuietSeconds: TimeInterval = 60

    public init(scheme: HeartRateZoneScheme, target: CardioTarget = .off) {
        self.scheme = scheme
        band = target.band(in: scheme)
        zoneSeconds = Array(repeating: 0, count: scheme.boundaries.count + 1)
        state = band == nil ? .off : .settling
    }

    /// Average heart rate over the time counted, weighted by how long each reading stood.
    public var averageBpm: Double? {
        measuredSeconds > 0 ? weightedBpm / measuredSeconds : nil
    }

    /// A new heart-rate reading. Returns a tap to play, if this reading earned one.
    public mutating func reading(bpm: Double, at date: Date) -> Alert? {
        guard !isPaused, bpm.isFinite, bpm > 0 else { return nil }
        // The same reading delivered twice, or one out of order: nothing new.
        if let last, date <= last.date { return nil }
        let gap = last.map { date.timeIntervalSince($0.date) }
        credit(until: date)
        last = Reading(bpm: bpm, date: date)
        currentBpm = bpm
        currentZone = scheme.zone(for: bpm)
        maximumBpm = max(maximumBpm ?? bpm, bpm)
        guard let band else { return nil }
        if let gap, gap > Self.staleSeconds { pending = nil }
        // Just retargeted: heart rate is still catching up, so nothing is judged yet.
        if let quietUntil, date < quietUntil {
            pending = nil
            return nil
        }
        return step(side: band.side(of: bpm), at: date)
    }

    /// A new band from `date` (an interval session's next step; nil for none).
    /// Time already counted stays in its zones, and time in the band from now
    /// on counts against the new one. The band starts over as "settling", and
    /// no tap comes for `quiet` seconds while heart rate catches up.
    public mutating func retarget(_ newBand: HeartRateBand?, at date: Date, quiet: TimeInterval = retargetQuietSeconds) {
        if !isPaused, let reading = last {
            credit(until: date)
            last = Reading(bpm: reading.bpm, date: max(reading.date, date))
        }
        band = newBand
        pending = nil
        lastAlertAt = nil
        state = newBand == nil ? .off : .settling
        quietUntil = quiet > 0 ? date.addingTimeInterval(quiet) : nil
    }

    /// The workout paused: the last reading counts up to now, and nothing after.
    public mutating func pause(at date: Date) {
        guard !isPaused else { return }
        credit(until: date)
        last = nil
        pending = nil
        isPaused = true
    }

    /// The workout runs again. Heart rate has dropped during the pause, so the
    /// target starts over as "settling": no "below" tap while it climbs back.
    public mutating func resume(at date: Date) {
        guard isPaused else { return }
        isPaused = false
        lastAlertAt = nil
        if band != nil { state = .settling }
    }

    /// The workout ended: the last reading counts up to the end.
    public mutating func end(at date: Date) {
        guard !isPaused else { return }
        credit(until: date)
        last = nil
        pending = nil
        isPaused = true
    }

    /// Counts the last reading for the time up to `date` (see the type comment).
    private mutating func credit(until date: Date) {
        guard let last else { return }
        let gap = date.timeIntervalSince(last.date)
        guard gap > 0, gap <= HeartRateZoneScheme.maxSampleGap else { return }
        let seconds = min(gap, HeartRateZoneScheme.maxMinutesPerSample * 60)
        if let zone = scheme.zone(for: last.bpm), zone <= zoneSeconds.count {
            zoneSeconds[zone - 1] += seconds
        } else {
            belowZoneSeconds += seconds
        }
        measuredSeconds += seconds
        weightedBpm += last.bpm * seconds
        if band?.contains(last.bpm) == true { bandSeconds += seconds }
    }

    private mutating func step(side: HeartRateBand.Side, at date: Date) -> Alert? {
        switch state {
        case .off:
            return nil
        case .settling:
            switch side {
            case .inside: return confirm(.inside, after: Self.returnSeconds, at: date)
            case .above: return confirm(.above, after: Self.leaveSeconds, at: date)
            case .below:
                pending = nil
                return nil
            }
        case .inBand:
            if side == .inside {
                pending = nil
                return nil
            }
            return confirm(side, after: Self.leaveSeconds, at: date)
        case .above, .below:
            let held: HeartRateBand.Side = state == .above ? .above : .below
            if side == held {
                pending = nil
                guard side == .above, let lastAlertAt,
                      date.timeIntervalSince(lastAlertAt) >= Self.remindSeconds else { return nil }
                self.lastAlertAt = date
                return .above
            }
            return confirm(side, after: side == .inside ? Self.returnSeconds : Self.leaveSeconds, at: date)
        }
    }

    /// Heart rate is on `side`; once it has stayed there for `hold` seconds
    /// without a reading anywhere else, that becomes the state and earns a tap.
    private mutating func confirm(_ side: HeartRateBand.Side, after hold: TimeInterval, at date: Date) -> Alert? {
        if pending?.side != side { pending = Pending(side: side, since: date) }
        guard let since = pending?.since, date.timeIntervalSince(since) >= hold else { return nil }
        pending = nil
        lastAlertAt = date
        switch side {
        case .inside: state = .inBand
        case .above: state = .above
        case .below: state = .below
        }
        return Self.alert(for: side)
    }

    private static func alert(for side: HeartRateBand.Side) -> Alert {
        switch side {
        case .inside: .inBand
        case .above: .above
        case .below: .below
        }
    }
}

/// What a cardio workout came to, for the Watch's end screen.
public nonisolated struct CardioSummary: Sendable, Equatable {
    public var activity: CardioActivity
    /// Workout time without pauses.
    public var activeSeconds: TimeInterval
    public var distanceMeters: Double?
    public var averageBpm: Double?
    public var maximumBpm: Double?
    public var activeKilocalories: Double?
    /// Seconds in zones 1-5 (index 0 = zone 1).
    public var zoneSeconds: [Double]
    public var belowZoneSeconds: Double
    /// Seconds a heart rate was counted for.
    public var measuredSeconds: Double
    /// The target and the seconds inside its band; `.off` and 0 without one.
    public var target: CardioTarget
    public var bandSeconds: Double
    /// True when Apple Health saved the workout.
    public var saved: Bool
    /// Outdoors with GPS: metres climbed (`CardioRoute.elevation`), the top
    /// averaged speed in m/s (`CardioRoute.maximumSpeed`), and whether a
    /// route was saved with the workout.
    public var elevationGainMeters: Double?
    public var maximumSpeed: Double?
    public var hasRoute = false

    public init(
        activity: CardioActivity, activeSeconds: TimeInterval, distanceMeters: Double? = nil,
        averageBpm: Double? = nil, maximumBpm: Double? = nil, activeKilocalories: Double? = nil,
        zoneSeconds: [Double], belowZoneSeconds: Double = 0, measuredSeconds: Double,
        target: CardioTarget = .off, bandSeconds: Double = 0, saved: Bool
    ) {
        self.activity = activity
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
        self.averageBpm = averageBpm
        self.maximumBpm = maximumBpm
        self.activeKilocalories = activeKilocalories
        self.zoneSeconds = zoneSeconds
        self.belowZoneSeconds = belowZoneSeconds
        self.measuredSeconds = measuredSeconds
        self.target = target
        self.bandSeconds = bandSeconds
        self.saved = saved
    }

    /// The tracker's numbers with what HealthKit measured. HealthKit's average
    /// and maximum heart rate win when it has them (they are what Apple's
    /// Fitness app will show for the same workout).
    public init(
        activity: CardioActivity, target: CardioTarget, tracker: CardioZoneTracker, activeSeconds: TimeInterval,
        distanceMeters: Double?, averageBpm: Double?, maximumBpm: Double?, activeKilocalories: Double?, saved: Bool
    ) {
        self.init(
            activity: activity, activeSeconds: activeSeconds, distanceMeters: distanceMeters,
            averageBpm: averageBpm ?? tracker.averageBpm, maximumBpm: maximumBpm ?? tracker.maximumBpm,
            activeKilocalories: activeKilocalories, zoneSeconds: tracker.zoneSeconds,
            belowZoneSeconds: tracker.belowZoneSeconds, measuredSeconds: tracker.measuredSeconds,
            target: tracker.band == nil ? .off : target, bandSeconds: tracker.bandSeconds, saved: saved
        )
    }

    /// Minutes in zones 1-5.
    public var zoneMinutes: [Double] { zoneSeconds.map { $0 / 60 } }

    /// Share of the measured time spent inside the target band (0-1), or nil without a target.
    public var bandShare: Double? {
        guard target != .off, measuredSeconds > 0 else { return nil }
        return min(1, bandSeconds / measuredSeconds)
    }

    // MARK: Distance, pace and speed

    public static let metersPerMile = 1609.344
    /// Below this distance no pace or speed is shown: over a few metres they
    /// are noise. The app's choice.
    public static let minimumDistanceForPace = 100.0

    /// Seconds per kilometre (or per mile), or nil without enough distance.
    public static func pace(seconds: TimeInterval, meters: Double?, miles: Bool) -> Double? {
        guard let meters, meters >= minimumDistanceForPace, seconds > 0 else { return nil }
        return seconds / (meters / (miles ? metersPerMile : 1000))
    }

    /// Kilometres (or miles) per hour, or nil without enough distance.
    public static func speed(seconds: TimeInterval, meters: Double?, miles: Bool) -> Double? {
        guard let meters, meters >= minimumDistanceForPace, seconds > 0 else { return nil }
        return (meters / (miles ? metersPerMile : 1000)) / (seconds / 3600)
    }

    /// "5:32 /km" or "8:54 /mi".
    public static func paceText(_ secondsPerUnit: Double, miles: Bool) -> String {
        let whole = Int(secondsPerUnit.rounded())
        let seconds = whole % 60
        return "\(whole / 60):\(seconds < 10 ? "0" : "")\(seconds) /\(miles ? "mi" : "km")"
    }

    /// "24.6 km/h" or "15.3 mph".
    public static func speedText(_ perHour: Double, miles: Bool) -> String {
        let tenths = Int((perHour * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(miles ? "mph" : "km/h")"
    }

    /// "24.6 km/h" or "15.3 mph" from metres per second.
    public static func speedText(metersPerSecond: Double, miles: Bool) -> String {
        speedText(metersPerSecond * 3.6 / (miles ? metersPerMile / 1000 : 1), miles: miles)
    }

    public static let feetPerMeter = 3.280839895

    /// "312 m" or "1,024 ft" (feet where distances are in miles).
    public static func elevationText(meters: Double, feet: Bool) -> String {
        let value = Int((max(0, meters) * (feet ? feetPerMeter : 1)).rounded())
        return "\(value.formatted()) \(feet ? "ft" : "m")"
    }

    /// "5.02 km" or "3.12 mi".
    public static func distanceText(meters: Double, miles: Bool) -> String {
        let hundredths = Int((max(0, meters) / (miles ? metersPerMile : 1000) * 100).rounded())
        let cents = hundredths % 100
        return "\(hundredths / 100).\(cents < 10 ? "0" : "")\(cents) \(miles ? "mi" : "km")"
    }

    /// Average pace for walking and running, average speed for cycling, nil otherwise.
    public func paceOrSpeedText(miles: Bool) -> String? {
        switch activity.movement {
        case .onFoot:
            Self.pace(seconds: activeSeconds, meters: distanceMeters, miles: miles).map { Self.paceText($0, miles: miles) }
        case .cycling, .snow:
            Self.speed(seconds: activeSeconds, meters: distanceMeters, miles: miles).map { Self.speedText($0, miles: miles) }
        case .stationary:
            nil
        }
    }
}
