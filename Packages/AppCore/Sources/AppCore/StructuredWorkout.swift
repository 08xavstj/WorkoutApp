import Foundation

/// A planned cardio session as Apple's Workout app takes it: warm-up, blocks
/// of work and recovery steps that repeat, cool-down, and a heart-rate alert
/// on each work step. A plain value with no WorkoutKit in it, so the mapping
/// is tested here; `App/Services/AppleWorkoutExport.swift` turns it into a
/// WorkoutKit `CustomWorkout` and schedules it (docs/research/next-features-2026-11.md W1).
///
/// Tensile's own Watch app stays the default way to run the session (owner's
/// decision, 18 Nov 2026); this is an optional extra. Apple's Workout app adds
/// Workout Buddy's spoken coaching, which has no developer API (Apple
/// Newsroom, 9 Jun 2025, as read for next-features-2026-11.md [W1]).
///
/// What goes in, and why:
/// - The steps and their lengths are `IntervalSession`'s (Helgerud 2007; Wen
///   2019: see that file), so the wrist runs the same session either way.
/// - Each work step carries the session's own bpm band (`IntervalSession+Zones`),
///   so Apple's alerts match Tensile's zones and the Watch's cardio mode.
/// - Each work step starts with a ramp with no alert (`rampSeconds`): heart
///   rate takes a minute or two to climb into the band, so an alert from the
///   first second would fire for the lag. The rest of the step carries it.
/// - Warm-up, recovery and cool-down get no alert. Heart rate lags effort by a
///   minute or two in each round (see `IntervalSession`), so an easy-band alert
///   in a three-minute recovery would mostly fire for the lag, not for going
///   too hard. The cue for those steps is effort, as on Tensile's Watch.
/// - An easy session is one step at the easy band (40-60% of heart-rate
///   reserve, `HeartRateZoneScheme.easyBand`), as `EasyCardio` plans it.
public nonisolated struct StructuredWorkout: Sendable, Equatable {
    /// The Health workout type it records as.
    public nonisolated enum Activity: String, Sendable, CaseIterable {
        case cycling, rowing, running, walking

        /// The name `HealthKitClient` gives a finished workout of this type
        /// (`HealthKitClient.swift`, the activity-name switch), which is what
        /// the plan's done check (`HardCardio.weekDone`, `CardioPlanner.doneDays`)
        /// matches. So a session recorded by Apple's Workout app ticks the plan
        /// like one recorded by Tensile's Watch app.
        public var healthName: String {
            switch self {
            case .cycling: "Ride"
            case .rowing: "Row"
            case .running: "Run"
            case .walking: "Walk"
            }
        }
    }

    public nonisolated enum Location: String, Sendable {
        case indoor, outdoor
    }

    public nonisolated enum StepKind: String, Sendable {
        case warmUp, work, recovery, coolDown
    }

    /// A heart-rate alert range in whole beats per minute.
    public nonisolated struct HeartRateRange: Sendable, Equatable {
        public var lower: Int
        public var upper: Int

        public init(lower: Int, upper: Int) {
            self.lower = lower
            self.upper = upper
        }
    }

    public nonisolated struct Step: Sendable, Equatable {
        public var kind: StepKind
        public var seconds: Int
        /// The alert's range; nil for no alert.
        public var heartRate: HeartRateRange?
        /// Shown on the wrist: "Hard · Effort 8-9 of 10".
        public var name: String

        public init(kind: StepKind, seconds: Int, heartRate: HeartRateRange? = nil, name: String) {
            self.kind = kind
            self.seconds = seconds
            self.heartRate = heartRate
            self.name = name
        }
    }

    /// Steps that run `iterations` times in a row.
    public nonisolated struct Block: Sendable, Equatable {
        public var steps: [Step]
        public var iterations: Int

        public init(steps: [Step], iterations: Int) {
            self.steps = steps
            self.iterations = iterations
        }
    }

    /// "4 × 4 min · Bike".
    public var name: String
    public var activity: Activity
    public var location: Location
    public var warmUp: Step?
    public var blocks: [Block]
    public var coolDown: Step?

    public init(name: String, activity: Activity, location: Location, warmUp: Step?, blocks: [Block], coolDown: Step?) {
        self.name = name
        self.activity = activity
        self.location = location
        self.warmUp = warmUp
        self.blocks = blocks
        self.coolDown = coolDown
    }

    // MARK: Totals (for tests and the summary line)

    /// Every step in the order it runs, blocks unrolled.
    public var unrolledSteps: [Step] {
        var steps: [Step] = []
        if let warmUp { steps.append(warmUp) }
        for block in blocks {
            for _ in 0..<max(0, block.iterations) { steps += block.steps }
        }
        if let coolDown { steps.append(coolDown) }
        return steps
    }

    public var totalSeconds: Int { unrolledSteps.reduce(0) { $0 + $1.seconds } }
    public var workSeconds: Int { unrolledSteps.filter { $0.kind == .work }.reduce(0) { $0 + $1.seconds } }

    /// Whether Apple's Workout Buddy speaks during this type of workout. Apple
    /// listed "Outdoor and Indoor Run, Outdoor and Indoor Walk, Outdoor Cycle,
    /// HIIT, and Functional and Traditional Strength Training", with Bluetooth
    /// headphones and an Apple Intelligence-supported iPhone nearby, starting
    /// in English (Apple Newsroom, "watchOS 26 delivers more personalized ways
    /// to stay active and connected", 9 Jun 2025; read 18 Nov 2026). So not on
    /// an indoor bike or a rower. Apple may have added types since.
    public var workoutBuddySpeaks: Bool {
        switch activity {
        case .running, .walking: true
        case .cycling: location == .outdoor
        case .rowing: false
        }
    }

    // MARK: Building

    /// The top given to an open-ended band (zone 5 has none) when the zones
    /// carry no maximum heart rate (Apple Health's or custom zones): the top
    /// of the plausible range the zone settings accept
    /// (`HeartRateZoneScheme.plausibleRange`). Apple's range alert needs an
    /// upper edge; Tensile's own Watch target has none, so this edge is set
    /// where it shouldn't fire. App's choice.
    public static let openBandTop = Int(HeartRateZoneScheme.plausibleRange.upperBound)

    /// Longest ramp at the start of a work step, seconds. Heart rate lags
    /// effort by a minute or two (see `IntervalSession`); 90 s is the app's
    /// choice within that.
    public static let maxRampSeconds = 90

    /// The ramp for a work step of `seconds`: `maxRampSeconds`, at most half the step.
    public static func rampSeconds(forWorkSeconds seconds: Int) -> Int {
        min(maxRampSeconds, seconds / 2)
    }

    /// A work step with an alert, split into a ramp with no alert and the rest
    /// of the step with it; the total length is kept. Any other step, or one
    /// too short to split, is returned as it is.
    public static func withRamp(_ step: Step) -> [Step] {
        guard step.kind == .work, step.heartRate != nil else { return [step] }
        let ramp = rampSeconds(forWorkSeconds: step.seconds)
        guard ramp > 0, step.seconds - ramp > 0 else { return [step] }
        var rest = step
        rest.seconds = step.seconds - ramp
        var start = step
        start.seconds = ramp
        start.heartRate = nil
        return [start, rest]
    }

    /// The alert range for `band` in `scheme`; nil without a band or a scheme.
    public static func heartRateRange(_ band: IntervalSession.Band, scheme: HeartRateZoneScheme?) -> HeartRateRange? {
        guard let scheme, let bpm = band.heartRateBand(in: scheme) else { return nil }
        let lower = bpm.lower > 0 ? Int(bpm.lower.rounded()) : Int(HeartRateZoneScheme.plausibleRange.lowerBound)
        let top = scheme.reserveBasis.map { Int($0.maximum.rounded()) } ?? openBandTop
        let upper = bpm.upper >= HeartRateBand.noUpperLimit ? top : Int(bpm.upper.rounded())
        guard upper > lower else { return nil }
        return HeartRateRange(lower: lower, upper: upper)
    }

    /// The interval session, with the bpm bands of the zones the user picked.
    /// Work steps get their band as an alert after a ramp (`withRamp`); the rest none (see the type).
    /// A work step with the recovery after it is one unit; equal units in a
    /// row become one block (4 × 4: three rounds of hard + easy, then the last
    /// hard minutes on their own, since the cool-down follows them directly).
    public static func interval(_ session: IntervalSession, scheme: HeartRateZoneScheme?) -> StructuredWorkout {
        func step(_ source: IntervalSession.Step) -> Step {
            let kind: StepKind = switch source.phase {
            case .warmUp: .warmUp
            case .work: .work
            case .recovery: .recovery
            case .coolDown: .coolDown
            }
            let alert = kind == .work ? heartRateRange(source.target.band, scheme: scheme) : nil
            return Step(kind: kind, seconds: source.seconds, heartRate: alert,
                        name: "\(source.phase.label) · \(source.target.effortText)")
        }
        var steps = session.steps.map(step)
        let warmUp = steps.first?.kind == .warmUp ? steps.removeFirst() : nil
        let coolDown = steps.last?.kind == .coolDown ? steps.removeLast() : nil
        var units: [[Step]] = []
        var index = 0
        while index < steps.count {
            if steps[index].kind == .work, index + 1 < steps.count, steps[index + 1].kind == .recovery {
                units.append([steps[index], steps[index + 1]])
                index += 2
            } else {
                units.append([steps[index]])
                index += 1
            }
        }
        // Ramps go in after grouping, so a work step and its ramp stay one unit.
        units = units.map { $0.flatMap(withRamp) }
        var blocks: [Block] = []
        for unit in units {
            if let last = blocks.last, last.steps == unit {
                blocks[blocks.count - 1].iterations += 1
            } else {
                blocks.append(Block(steps: unit, iterations: 1))
            }
        }
        return StructuredWorkout(name: session.title, activity: session.modality.structuredActivity,
                                 location: session.modality.isOutdoor ? .outdoor : .indoor,
                                 warmUp: warmUp, blocks: blocks, coolDown: coolDown)
    }

    /// An easy session: one step of `minutes` at the easy band, after a ramp (`withRamp`).
    /// - Parameter indoor: on a gym machine (the gym has a bike for an easy
    ///   ride, a treadmill for an incline walk); a row is always indoors.
    public static func easy(_ kind: EasyCardio.Kind, minutes: Int, indoor: Bool, scheme: HeartRateZoneScheme?) -> StructuredWorkout {
        let step = Step(kind: .work, seconds: max(1, minutes) * 60,
                        heartRate: heartRateRange(.easy, scheme: scheme),
                        name: "Easy · you can talk in full sentences")
        return StructuredWorkout(name: "\(kind.title) · \(minutes) min", activity: kind.structuredActivity,
                                 location: kind == .row || indoor ? .indoor : .outdoor,
                                 warmUp: nil, blocks: [Block(steps: withRamp(step), iterations: 1)], coolDown: nil)
    }

    // MARK: When

    /// The day to put it on: its weekday in the week starting `weekStart`
    /// (`WeeklyPlan.order`, as `HardCardio.weekDone` reads it), or, for any
    /// day (a flexible week), today. Nil once that day has passed or the week
    /// is over: the plan only counts it as done on its own day.
    public static func day(weekday: Int?, weekStart: Date, now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart), today < weekEnd,
              today >= calendar.startOfDay(for: weekStart) else { return nil }
        guard let weekday else { return today }
        guard let day = calendar.date(byAdding: .day, value: WeeklyPlan.order(weekday), to: weekStart) else { return nil }
        let start = calendar.startOfDay(for: day)
        return start >= today ? start : nil
    }

    /// Where an earlier copy of the same session is replaced when it's added
    /// again: the whole week in a flexible week (it may have gone on another
    /// day), else its own day. So a second add never leaves two copies.
    public static func replaceWindow(anyDay: Bool, day: Date, weekStart: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: anyDay ? weekStart : day)
        let end = calendar.date(byAdding: .day, value: anyDay ? 7 : 1, to: start) ?? start.addingTimeInterval(anyDay ? 7 * 86_400 : 86_400)
        return DateInterval(start: start, end: end)
    }

    /// Whether a copy scheduled at `scheduled` falls in `window` (end not included).
    public static func isInReplaceWindow(_ scheduled: Date, window: DateInterval) -> Bool {
        scheduled >= window.start && scheduled < window.end
    }

    /// Minutes after midnight to offer as the start time when no time is
    /// planned for that day and the plan has none at all. App's choice.
    public static let fallbackStartMinutes = 18 * 60

    /// The start time to offer, in minutes after midnight: the lifting
    /// session's on that weekday, else the plan's first session's (when you
    /// usually train), else `fallbackStartMinutes`.
    public static func startMinutes(plan: WeeklyPlan, weekday: Int?) -> Int {
        if let weekday, let day = plan.day(for: weekday) { return day.time }
        return plan.sortedDays.first?.time ?? fallbackStartMinutes
    }
}

extension IntervalSession.Modality {
    /// The Health workout type a session on it records as.
    public nonisolated var structuredActivity: StructuredWorkout.Activity {
        switch self {
        case .bike, .outdoorRide: .cycling
        case .rower: .rowing
        case .treadmill, .outdoorRun: .running
        }
    }
}

extension EasyCardio.Kind {
    /// The Health workout type an easy session of this kind records as.
    public nonisolated var structuredActivity: StructuredWorkout.Activity {
        switch self {
        case .bike: .cycling
        case .row: .rowing
        case .inclineWalk: .walking
        }
    }
}
