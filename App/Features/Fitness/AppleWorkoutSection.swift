import SwiftUI
import AppCore

// The optional "Also add to Apple's Workout app" action for a planned cardio
// session (docs/research/next-features-2026-11.md W1; `StructuredWorkout`,
// `AppleWorkoutExport`). Tensile's own Watch app stays the default way to run
// it (owner's decision, 18 Nov 2026).

/// One session to offer, with the day it's planned for.
struct AppleWorkoutTarget {
    var workout: StructuredWorkout
    /// Its day (start of day); nil once that day has passed this week.
    var day: Date?
    /// A flexible week: any day left this week will do.
    var anyDay: Bool
    var weekStart: Date
    var weekEnd: Date
    /// Minutes after midnight to start from (`StructuredWorkout.startMinutes`).
    var startMinutes: Int

    init(workout: StructuredWorkout, weekday: Int?, plan: WeeklyPlan, now: Date = .now, calendar: Calendar = .current) {
        self.workout = workout
        day = StructuredWorkout.day(weekday: weekday, weekStart: plan.weekStart, now: now, calendar: calendar)
        anyDay = weekday == nil
        weekStart = plan.weekStart
        weekEnd = calendar.date(byAdding: .day, value: 7, to: plan.weekStart) ?? plan.weekStart.addingTimeInterval(7 * 86_400)
        startMinutes = StructuredWorkout.startMinutes(plan: plan, weekday: weekday)
    }

    /// The day at the start time.
    func defaultDate(calendar: Calendar = .current) -> Date {
        guard let day else { return .now }
        return calendar.date(byAdding: .minute, value: startMinutes, to: day) ?? day
    }
}

/// A list section: what Apple's app would add, a time (or day) picker, the
/// button, and the result in plain words.
struct AppleWorkoutSection: View {
    let target: AppleWorkoutTarget
    @State private var date: Date
    @State private var outcome: AppleWorkoutExport.Outcome?
    @State private var isAdding = false

    init(target: AppleWorkoutTarget) {
        self.target = target
        // Never a time that has passed (the planned time today may be over).
        _date = State(initialValue: max(target.defaultDate(), .now))
    }

    var body: some View {
        Section {
            if let day = target.day {
                picker(day: day)
                Button {
                    Task { await add() }
                } label: {
                    HStack {
                        Label("Also add to Apple's Workout app", systemImage: "applewatch")
                        Spacer(minLength: 8)
                        if isAdding { ProgressView() }
                    }
                }
                .disabled(isAdding)
                .accessibilityIdentifier("appleWorkout.add")
                if let outcome {
                    Label(outcome.text, systemImage: outcome.isAdded ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(outcome.isAdded ? Theme.recoveryHighText : Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("appleWorkout.result")
                }
            } else {
                Text("Its day has passed this week, so there's nothing to add to Apple's Workout app.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Apple's Workout app (optional)")
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private func picker(day: Date) -> some View {
        // From now at the earliest: Apple's app can't run a workout scheduled in the past.
        let start = max(day, .now)
        if target.anyDay {
            let end = target.weekEnd.addingTimeInterval(-60)
            DatePicker("Day and time", selection: $date, in: start...max(start, end), displayedComponents: [.date, .hourAndMinute])
        } else {
            let end = (Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)).addingTimeInterval(-60)
            DatePicker("Time on \(day.formatted(.dateTime.weekday(.wide)))", selection: $date, in: start...max(start, end),
                       displayedComponents: .hourAndMinute)
        }
    }

    private var footer: String {
        let intervals = target.workout.unrolledSteps.contains { $0.kind == .recovery }
        let alerts = intervals ? "alerts you outside your Tensile heart-rate band on the hard steps" : "alerts you outside your Tensile easy band"
        var text = "Tensile's Watch app is the default way to run this, with your zones. Apple's Workout app is an extra if you'd like it: it runs the same steps, \(alerts), and can add Workout Buddy's spoken coaching."
        if target.workout.workoutBuddySpeaks {
            text += " Workout Buddy needs Bluetooth headphones and an Apple Intelligence iPhone nearby."
        } else {
            text += " Apple lists Workout Buddy for runs, walks, outdoor rides, HIIT and strength, so it may not speak on this one."
        }
        text += target.anyDay
            ? " Either way, the finished workout reaches Apple Health and ticks the plan here."
            : " Either way, the finished workout reaches Apple Health and ticks the plan here when it's done on its day."
        return text
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        var when = date
        // A time picked for a fixed day stays on that day.
        if !target.anyDay, let day = target.day {
            let calendar = Calendar.current
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            when = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? date
        }
        guard when > .now, let day = target.day else {
            outcome = .failed("That time has passed. Pick a later time.")
            return
        }
        let window = StructuredWorkout.replaceWindow(anyDay: target.anyDay, day: day, weekStart: target.weekStart)
        outcome = await AppleWorkoutExport.add(target.workout, at: when, replacing: window)
    }
}

extension AppleWorkoutExport.Outcome {
    var isAdded: Bool {
        if case .added = self { return true }
        return false
    }
}
