import AppCore
import Foundation
import HealthKit

/// How a Health workout was split up: the segments the recording app saved
/// (Apple's custom workouts save segments), its pauses, and the interval
/// session it ran if Tensile's Watch recorded one. Lap events are left out:
/// a watch's auto-lap each kilometre is what the splits table shows already.
nonisolated struct WorkoutStructure: Sendable {
    var start: Date
    var end: Date
    /// Segment events without a step index, in time order.
    var segments: [DateInterval]
    /// Segment events the Watch saved for interval steps, with the step's
    /// index (`IntervalSession.stepMetadataKey`), in time order.
    var steps: [IntervalBouts.RecordedStep] = []
    var pauses: [DateInterval]
    /// `IntervalSession.id` from the workout's metadata (`IntervalSession.metadataKey`).
    var intervalSessionID: String?
}

nonisolated extension HealthKitClient {
    /// The workout's segments, interval steps, pauses and interval session; nil if it is gone.
    @concurrent
    func workoutStructure(id: UUID) async throws -> WorkoutStructure? {
        if let demo = DemoHealth.active { return demo.workoutStructure(id: id) }
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: []
        ).result(for: store)
        guard let workout = workouts.first else { return nil }
        let events = (workout.workoutEvents ?? []).sorted { $0.dateInterval.start < $1.dateInterval.start }
        let segmentEvents = events.filter { $0.type == .segment && $0.dateInterval.duration > 0 }
        var segments: [DateInterval] = []
        var steps: [IntervalBouts.RecordedStep] = []
        for event in segmentEvents {
            if let index = Self.stepIndex(event.metadata?[IntervalSession.stepMetadataKey]) {
                steps.append(IntervalBouts.RecordedStep(index: index, start: event.dateInterval.start, end: event.dateInterval.end))
            } else {
                segments.append(event.dateInterval)
            }
        }
        return WorkoutStructure(
            start: workout.startDate, end: workout.endDate,
            segments: segments,
            steps: steps,
            pauses: Self.pauses(events, end: workout.endDate),
            intervalSessionID: workout.metadata?[IntervalSession.metadataKey] as? String
        )
    }

    /// A step index saved as a number (or, to be safe, as text).
    static func stepIndex(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    /// Pause-to-resume spans (a pause with no resume runs to the end).
    static func pauses(_ events: [HKWorkoutEvent], end: Date) -> [DateInterval] {
        var result: [DateInterval] = []
        var pausedAt: Date?
        for event in events {
            switch event.type {
            case .pause, .motionPaused:
                if pausedAt == nil { pausedAt = event.dateInterval.start }
            case .resume, .motionResumed:
                if let start = pausedAt, event.dateInterval.start > start {
                    result.append(DateInterval(start: start, end: event.dateInterval.start))
                }
                pausedAt = nil
            default:
                break
            }
        }
        if let start = pausedAt, end > start { result.append(DateInterval(start: start, end: end)) }
        return result
    }

    /// Only the GPS route of a workout (no heart rate or VO₂ max), for best
    /// efforts worked out in the background; empty for an indoor workout.
    @concurrent
    func workoutRoute(id: UUID) async throws -> [RoutePoint] {
        if let demo = DemoHealth.active { return demo.cardioWorkoutDetail(id: id)?.route ?? [] }
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: []
        ).result(for: store)
        guard let workout = workouts.first else { return [] }
        let routes = try await HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store).compactMap { $0 as? HKWorkoutRoute }
        var points: [RoutePoint] = []
        for route in routes {
            points += try await routePoints(route)
        }
        return points
    }
}

nonisolated extension DemoHealth {
    /// Every other long run in demo mode is a 4 × 4 interval session, so the
    /// bouts table has something to show in the screenshot tour.
    func isIntervalDemo(_ workout: Cardio) -> Bool {
        workout.name == "Run" && workout.daysAgo % 14 == 4
    }

    static let intervalDemoSession = IntervalSession.fourByFour(.outdoorRun)

    func workoutStructure(id: UUID) -> WorkoutStructure? {
        guard let workout = cardio.first(where: { $0.id == id }), workout.end <= now else { return nil }
        return WorkoutStructure(start: workout.start, end: workout.end, segments: [], pauses: [],
                                intervalSessionID: isIntervalDemo(workout) ? Self.intervalDemoSession.id : nil)
    }

    /// Demo heart rate in an interval run: it climbs through each hard
    /// interval (it lags the effort) and falls in each easy one.
    static func intervalBpm(minutesIn: Double) -> Double {
        guard let current = intervalDemoSession.step(at: minutesIn * 60) else { return 118 }
        let progress = 1 - Double(current.remaining) / Double(max(1, current.step.seconds))
        switch current.step.phase {
        case .warmUp: return 108 + 34 * progress
        case .work: return 148 + 26 * progress
        case .recovery: return 168 - 32 * progress
        case .coolDown: return 132 - 14 * progress
        }
    }
}
