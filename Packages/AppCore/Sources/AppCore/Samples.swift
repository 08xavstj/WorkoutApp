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

    public init(
        start: Date,
        end: Date,
        sessionRPE: Double? = nil,
        setRPEs: [Double] = [],
        workingSets: Int = 0,
        totalVolumeKg: Double = 0
    ) {
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
