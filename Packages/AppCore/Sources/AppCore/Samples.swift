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
    /// - Parameter manualOnlyHRV: drop Health's HRV when the user types HRV in.
    ///   Garmin reports RMSSD and Apple Health stores SDNN; the two differ, so
    ///   mixing them would skew the baseline.
    public static func merging(
        _ vitals: [DailyVitals],
        manualHRV: [Date: Double],
        manualOnlyHRV: Bool = false,
        calendar: Calendar = .current
    ) -> [DailyVitals] {
        var byNight: [Date: DailyVitals] = [:]
        let dropHealthHRV = manualOnlyHRV && manualHRV.values.contains { $0 > 0 }
        for var entry in vitals {
            if dropHealthHRV { entry.hrvMilliseconds = nil }
            byNight[calendar.startOfDay(for: entry.date)] = entry
        }
        for (date, milliseconds) in manualHRV where milliseconds > 0 {
            let night = calendar.startOfDay(for: date)
            var entry = byNight[night] ?? DailyVitals(date: night, hrvMilliseconds: nil, restingHeartRate: nil)
            if entry.hrvMilliseconds == nil {
                entry.hrvMilliseconds = milliseconds
            }
            byNight[night] = entry
        }
        return byNight.values.sorted { $0.date > $1.date }
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

    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
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

    public init(
        name: String? = nil,
        start: Date,
        end: Date,
        sessionRPE: Double? = nil,
        setRPEs: [Double] = [],
        workingSets: Int = 0,
        totalVolumeKg: Double = 0
    ) {
        self.name = name
        self.start = start
        self.end = end
        self.sessionRPE = sessionRPE
        self.setRPEs = setRPEs
        self.workingSets = workingSets
        self.totalVolumeKg = totalVolumeKg
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}
