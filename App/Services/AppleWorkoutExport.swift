import Foundation
import HealthKit
import WorkoutKit
import AppCore

/// Optional: puts a planned cardio session into Apple's Workout app on its day
/// (WorkoutKit `CustomWorkout` + `WorkoutScheduler`; iOS 17 / watchOS 10).
/// Tensile's own Watch app stays the default way to run it (owner's decision,
/// 18 Nov 2026); Apple's app adds Workout Buddy's voice where Apple offers it.
/// The steps, bands and day come from `StructuredWorkout` (AppCore, tested);
/// this file is only the WorkoutKit mapping.
///
/// Permissions: WorkoutKit asks for its own permission to schedule
/// (`WorkoutScheduler.requestAuthorization()`); it needs no entitlement or
/// Info.plist key beyond the HealthKit ones the app already has (Apple's
/// WorkoutKit overview and sample, read 18 Nov 2026). The finished workout
/// comes back through Apple Health like any other, and the plan's done check
/// matches it by type and day (`StructuredWorkout.Activity.healthName`).
enum AppleWorkoutExport {
    enum Outcome: Equatable {
        case added(String)
        case failed(String)

        var text: String {
            switch self {
            case .added(let text), .failed(let text): text
            }
        }
    }

    // MARK: Mapping

    static func activityType(_ activity: StructuredWorkout.Activity) -> HKWorkoutActivityType {
        switch activity {
        case .cycling: .cycling
        case .rowing: .rowing
        case .running: .running
        case .walking: .walking
        }
    }

    static func locationType(_ location: StructuredWorkout.Location) -> HKWorkoutSessionLocationType {
        switch location {
        case .indoor: .indoor
        case .outdoor: .outdoor
        }
    }

    /// The heart-rate alert for a step, in beats per minute (WorkoutKit's default unit for `heartRate(_:unit:)`).
    static func alert(_ range: StructuredWorkout.HeartRateRange?) -> HeartRateRangeAlert? {
        guard let range, range.upper > range.lower else { return nil }
        return HeartRateRangeAlert.heartRate(Double(range.lower)...Double(range.upper))
    }

    static func step(_ step: StructuredWorkout.Step, alerts: Bool) -> WorkoutStep {
        WorkoutStep(goal: .time(Double(step.seconds), .seconds),
                    alert: alerts ? alert(step.heartRate) : nil,
                    displayName: step.name)
    }

    /// The `CustomWorkout`, and whether Apple's app takes heart-rate alerts for
    /// this activity here (without them it still runs the steps).
    static func customWorkout(_ workout: StructuredWorkout) -> (workout: CustomWorkout, alerts: Bool) {
        let activity = activityType(workout.activity)
        let location = locationType(workout.location)
        let sample = workout.unrolledSteps.compactMap { alert($0.heartRate) }.first
        let alerts = sample.map { CustomWorkout.supportsAlert($0, activity: activity, location: location) } ?? false
        let blocks = workout.blocks.map { block in
            IntervalBlock(steps: block.steps.map { item in
                IntervalStep(item.kind == .recovery ? .recovery : .work, step: step(item, alerts: alerts))
            }, iterations: block.iterations)
        }
        let custom = CustomWorkout(activity: activity, location: location, displayName: workout.name,
                                   warmup: workout.warmUp.map { step($0, alerts: alerts) }, blocks: blocks,
                                   cooldown: workout.coolDown.map { step($0, alerts: alerts) })
        return (custom, alerts)
    }

    // MARK: Scheduling

    /// Asks for permission if needed, replaces a copy of the same session
    /// already scheduled that day, and schedules it at `date`.
    static func add(_ workout: StructuredWorkout, at date: Date, calendar: Calendar = .current) async -> Outcome {
        if DemoHealth.active != nil {
            return .failed("Demo mode: nothing was sent to Apple's Workout app.")
        }
        guard WorkoutScheduler.isSupported else {
            return .failed("This iPhone can't add workouts to Apple's Workout app. It needs a paired Apple Watch.")
        }
        let (custom, alerts) = customWorkout(workout)
        guard CustomWorkout.supportsActivity(custom.activity) else {
            return .failed("Apple's Workout app doesn't take a structured \(workout.activity.healthName.lowercased()) workout. Run it in Tensile's Watch app.")
        }
        let scheduler = WorkoutScheduler.shared
        var state = await scheduler.authorizationState
        if state == .notDetermined {
            state = await scheduler.requestAuthorization()
        }
        switch state {
        case .authorized:
            break
        case .denied:
            return .failed("Tensile isn't allowed to add workouts to Apple's Workout app. You can allow it for Tensile in the Settings app, then try again.")
        case .restricted:
            return .failed("Adding workouts is restricted on this iPhone (for example by Screen Time).")
        case .notDetermined:
            return .failed("Tensile wasn't given permission to add workouts. Try again to see the question.")
        @unknown default:
            return .failed("Apple's Workout app didn't allow it. Try again later.")
        }
        // The same session already on that day (added before): replace it, so it isn't there twice.
        for scheduled in await scheduler.scheduledWorkouts {
            guard case .custom(let existing) = scheduled.plan.workout, existing.displayName == custom.displayName,
                  let day = calendar.date(from: scheduled.date), calendar.isDate(day, inSameDayAs: date) else { continue }
            await scheduler.remove(scheduled.plan, at: scheduled.date)
        }
        if await scheduler.scheduledWorkouts.count >= WorkoutScheduler.maxAllowedScheduledWorkoutCount {
            return .failed("Apple's Workout app already holds as many workouts from Tensile as it allows. Do or remove one in the Workout app, then try again.")
        }
        let plan = WorkoutPlan(.custom(custom))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        await scheduler.schedule(plan, at: components)
        guard await scheduler.scheduledWorkouts.contains(where: { $0.plan.id == plan.id }) else {
            return .failed("Apple's Workout app didn't confirm it. Open the Workout app on your Watch to check.")
        }
        let when = date.formatted(.dateTime.weekday(.wide).hour().minute())
        var text = "Added to Apple's Workout app for \(when). On your Watch it's in the Workout app, under Tensile."
        if !alerts, workout.unrolledSteps.contains(where: { $0.heartRate != nil }) {
            text += " Apple's app doesn't take heart-rate alerts for this activity, so it has the steps without them."
        }
        return .added(text)
    }
}
