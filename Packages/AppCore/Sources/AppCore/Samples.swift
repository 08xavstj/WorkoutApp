import Foundation

/// Plain value types the scoring code works on. The app converts HealthKit
/// and SwiftData records into these, so the math can be tested without either.

public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case male
    case female
}

public struct HeartRateSample: Sendable, Equatable {
    public var date: Date
    public var bpm: Double

    public init(date: Date, bpm: Double) {
        self.date = date
        self.bpm = bpm
    }
}

/// One night's resting heart rate and HRV, used to build the personal baseline.
public struct DailyVitals: Sendable, Equatable {
    public var date: Date
    /// Apple Health reports HRV as SDNN in milliseconds.
    public var hrvMilliseconds: Double?
    public var restingHeartRate: Double?

    public init(date: Date, hrvMilliseconds: Double?, restingHeartRate: Double?) {
        self.date = date
        self.hrvMilliseconds = hrvMilliseconds
        self.restingHeartRate = restingHeartRate
    }
}

extension DailyVitals {
    /// Fills in HRV the user typed in (for watches like Garmin that don't share
    /// HRV with Apple Health). Health data wins when both exist for a night.
    /// Returned newest first.
    ///
    /// - Parameter manualOnlyHRV: treat `manualHRV` as overnight RMSSD and pick
    ///   one HRV measure for the whole baseline (`resolvingHRV`): Garmin reports
    ///   RMSSD and Apple Health stores SDNN, and mixing them would skew it. One
    ///   typed reading no longer wipes Apple Health's HRV.
    public static func merging(
        _ vitals: [DailyVitals],
        manualHRV: [Date: Double],
        manualOnlyHRV: Bool = false,
        calendar: Calendar = .current
    ) -> [DailyVitals] {
        if manualOnlyHRV {
            return resolvingHRV(vitals, overnightRMSSD: manualHRV, calendar: calendar).vitals
        }
        var byNight: [Date: DailyVitals] = [:]
        for entry in vitals {
            byNight[calendar.startOfDay(for: entry.date)] = entry
        }
        var manualNights = Set<Date>()
        // Oldest first, so with two readings on one morning the latest wins every time.
        for (date, milliseconds) in manualHRV.sorted(by: { $0.key < $1.key }) where milliseconds > 0 {
            let night = calendar.startOfDay(for: date)
            var entry = byNight[night] ?? DailyVitals(date: night, hrvMilliseconds: nil, restingHeartRate: nil)
            if entry.hrvMilliseconds == nil || manualNights.contains(night) {
                entry.hrvMilliseconds = milliseconds
                manualNights.insert(night)
            }
            byNight[night] = entry
        }
        return byNight.values.sorted { $0.date > $1.date }
    }

    /// Nights looked at when choosing the HRV measure (the recovery baseline's 30).
    public static let hrvWindowNights = 30
    /// Overnight RMSSD nights in that window before RMSSD replaces SDNN: the
    /// same 14-night minimum a recovery baseline needs (`RecoveryCalculator`).
    public static let minimumRMSSDNights = 14
    /// Nights with both overnight measures needed before one fills the other's gaps.
    public static let minimumPairedNights = 5

    /// One HRV measure for every night, so a baseline never mixes two.
    ///
    /// - Overnight RMSSD (Apple Watch beat-to-beat, or typed in from a Garmin)
    ///   is used once it covers 14 of the last 30 nights; otherwise Apple
    ///   Health's SDNN is. Only readings inside that window decide, so an old
    ///   typed value can't switch the measure.
    /// - A night missing the chosen measure but having the other one gets the
    ///   other, converted with your own median RMSSD/SDNN ratio from nights with
    ///   both (5 or more). Overnight RMSSD and SDNN track each other closely
    ///   (Shaffer & Ginsberg, Front Public Health 2017), but their size differs
    ///   from person to person, hence a personal ratio. The ratio and the 5
    ///   nights are the app's choice.
    /// - Morning readings (the camera, seated and awake) are taken under
    ///   different conditions from overnight ones (posture and sleep both change
    ///   HRV: Buchheit, Front Physiol 2014), so they are never mixed in: they
    ///   form their own baseline only when there's no overnight HRV in the window.
    ///
    /// - Parameters:
    ///   - today: the newest morning; defaults to the newest date in the inputs.
    /// - Returns: vitals newest first, and the measure they carry.
    public static func resolvingHRV(
        _ vitals: [DailyVitals],
        overnightRMSSD: [Date: Double],
        morningHRV: [Date: Double] = [:],
        today: Date? = nil,
        calendar: Calendar = .current
    ) -> HRVSelection {
        var byNight: [Date: DailyVitals] = [:]
        for entry in vitals {
            let night = calendar.startOfDay(for: entry.date)
            byNight[night] = DailyVitals(date: entry.date, hrvMilliseconds: entry.hrvMilliseconds.flatMap { $0 > 0 ? $0 : nil },
                                         restingHeartRate: entry.restingHeartRate)
        }
        // One value per morning. Readings are visited oldest first, so when a
        // morning has two (a typed value keyed at its clock time next to a
        // beat-to-beat one keyed at midnight) the latest wins, the same on
        // every launch rather than in dictionary order.
        func nights(_ values: [Date: Double]) -> [Date: Double] {
            var result: [Date: Double] = [:]
            for (date, value) in values.sorted(by: { $0.key < $1.key }) where value > 0 {
                result[calendar.startOfDay(for: date)] = value
            }
            return result
        }
        let rmssd = nights(overnightRMSSD)
        let morning = nights(morningHRV)
        let newest = today.map { calendar.startOfDay(for: $0) }
            ?? (Array(byNight.keys) + Array(rmssd.keys) + Array(morning.keys)).max()
        guard let anchor = newest else { return HRVSelection(vitals: [], metric: nil) }
        let windowStart = calendar.date(byAdding: .day, value: -(hrvWindowNights - 1), to: anchor) ?? anchor
        func inWindow(_ night: Date) -> Bool { night >= windowStart && night <= anchor }

        let sdnn = byNight.compactMapValues(\.hrvMilliseconds)
        let rmssdCount = rmssd.keys.filter(inWindow).count
        let sdnnCount = sdnn.keys.filter(inWindow).count
        let morningCount = morning.keys.filter(inWindow).count
        let metric: HRVMetric?
        if rmssdCount >= minimumRMSSDNights {
            metric = .rmssd
        } else if sdnnCount > 0 || rmssdCount > 0 {
            metric = sdnnCount >= rmssdCount ? .sdnn : .rmssd
        } else if morningCount > 0 {
            metric = .morningRMSSD
        } else {
            metric = nil
        }

        // Personal RMSSD/SDNN ratio from nights with both (window first, else any).
        let paired = rmssd.keys.filter { sdnn[$0] != nil }
        let pairedInWindow = paired.filter(inWindow)
        let ratioNights = pairedInWindow.count >= minimumPairedNights ? pairedInWindow : paired
        var ratio: Double?
        if ratioNights.count >= minimumPairedNights {
            let ratios = ratioNights.compactMap { night in sdnn[night].flatMap { s in rmssd[night].map { $0 / s } } }.sorted()
            ratio = ratios.isEmpty ? nil : ratios[ratios.count / 2]
        }

        var result: [Date: DailyVitals] = byNight
        let allNights = Set(byNight.keys).union(rmssd.keys).union(morning.keys)
        for night in allNights {
            var entry = result[night] ?? DailyVitals(date: night, hrvMilliseconds: nil, restingHeartRate: nil)
            let value: Double?
            switch metric {
            case .rmssd: value = rmssd[night] ?? sdnn[night].flatMap { s in ratio.map { s * $0 } }
            case .sdnn: value = sdnn[night] ?? rmssd[night].flatMap { r in ratio.map { r / $0 } }
            case .morningRMSSD: value = morning[night]
            case nil: value = nil
            }
            entry.hrvMilliseconds = value
            // Nights that only ever had a value of the other kind, with no conversion, add nothing.
            if value == nil, byNight[night] == nil { continue }
            result[night] = entry
        }
        return HRVSelection(vitals: result.values.sorted { $0.date > $1.date }, metric: metric, rmssdNights: rmssdCount)
    }
}

/// Which HRV measure a baseline uses. Never mixed within one baseline.
public enum HRVMetric: String, Sendable, Codable {
    /// Apple Health's overnight SDNN.
    case sdnn = "SDNN"
    /// Overnight RMSSD: Apple Watch beat-to-beat, or typed in from a Garmin.
    case rmssd = "RMSSD"
    /// Morning camera readings (RMSSD, seated and awake), kept apart from overnight HRV.
    case morningRMSSD = "RMSSD (morning)"
}

/// The vitals with one HRV measure, and which one (`DailyVitals.resolvingHRV`).
public struct HRVSelection: Sendable, Equatable {
    /// Newest first.
    public var vitals: [DailyVitals]
    public var metric: HRVMetric?
    /// Overnight RMSSD nights in the last 30.
    public var rmssdNights: Int

    public init(vitals: [DailyVitals], metric: HRVMetric?, rmssdNights: Int = 0) {
        self.vitals = vitals
        self.metric = metric
        self.rmssdNights = rmssdNights
    }
}

public enum SleepStage: String, Sendable, Codable, CaseIterable {
    case inBed
    case awake
    case core
    case deep
    case rem
    /// Asleep, but the source didn't record a stage (older devices, iPhone only).
    case unspecified

    public var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .unspecified: true
        case .inBed, .awake: false
        }
    }
}

public struct SleepSample: Sendable, Equatable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    /// The app or device that recorded it (Apple Health's source name), if known,
    /// so two trackers recording the same night aren't counted twice.
    public var source: String?

    public init(stage: SleepStage, start: Date, end: Date, source: String? = nil) {
        self.stage = stage
        self.start = start
        self.end = end
        self.source = source
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// A logged gym session, reduced to what strain needs.
public struct StrengthSessionSummary: Sendable, Equatable {
    public var start: Date
    public var end: Date
    /// How hard the whole session felt, 1-10 (session RPE).
    public var sessionRPE: Double?
    /// RPE of individual working sets, if the user logged them.
    public var setRPEs: [Double]
    public var workingSets: Int
    public var totalVolumeKg: Double
    public var name: String?
    /// The Apple Health workout another device recorded for this same session
    /// (see `WorkoutLinking`), so the activities list shows one entry, not two.
    public var linkedWorkoutUUID: UUID?
    public var linkedWorkoutSource: String?

    public init(
        name: String? = nil,
        start: Date,
        end: Date,
        sessionRPE: Double? = nil,
        setRPEs: [Double] = [],
        workingSets: Int = 0,
        totalVolumeKg: Double = 0,
        linkedWorkoutUUID: UUID? = nil,
        linkedWorkoutSource: String? = nil
    ) {
        self.name = name
        self.start = start
        self.end = end
        self.sessionRPE = sessionRPE
        self.setRPEs = setRPEs
        self.workingSets = workingSets
        self.totalVolumeKg = totalVolumeKg
        self.linkedWorkoutUUID = linkedWorkoutUUID
        self.linkedWorkoutSource = linkedWorkoutSource
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}
