import SwiftUI
import SwiftData
import AppCore

/// Pre-commit this week's training: 2-6 days with a time, a session and a
/// length, plus one if-then line for when the day goes wrong.
///
/// Implementation intentions ("if it's Tuesday 6 pm, I do push") raise
/// follow-through, d = 0.65 across 94 tests (Gollwitzer & Sheeran 2006;
/// d = 0.31 in physical activity, Bélanger-Gravel 2013); coping plans
/// predicted maintenance (Sniehotta 2005, from memory in the report).
struct WeeklyPlanView: View {
    /// Days to start from instead of this week's (or last week's) plan.
    var initialDays: [PlannedDay]? = nil

    @Environment(WeeklyPlanStore.self) private var store
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var days: [PlannedDay] = []
    @State private var ifThen = ""
    @State private var loaded = false

    private var weekStart: Date { WeeklyPlan.weekStart(containing: .now) }

    private var suggestedCount: Int {
        WeeklyPlan.suggestedDayCount(goals: settings.goalsSet ? settings.goals : nil)
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                daysSection
                ForEach($days) { $day in
                    PlannedDaySection(day: $day)
                }
                ifThenSection
                Section {
                    Toggle("Monday review reminder", isOn: $settings.weeklyReviewOn)
                    if settings.weeklyReviewOn {
                        DatePicker("Time", selection: reviewTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Weekly review")
                } footer: {
                    Text("Every Monday: last week in plain numbers, then three changes for this week.")
                }
            }
            .navigationTitle("This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!WeeklyPlan.dayRange.contains(days.count))
                }
            }
            .task { load() }
        }
    }

    // MARK: Sections

    private var daysSection: some View {
        Section {
            WeekdayPicker(selected: days.map(\.weekday), toggle: toggle)
        } header: {
            Text("Training days")
        } footer: {
            // Days per week from the goal: 2-3 health, 3-4 muscle/strength (report rec. 2).
            Text("\(days.count) of \(WeeklyPlan.dayRange.lowerBound)–\(WeeklyPlan.dayRange.upperBound) days. About \(suggestedCount) a week suits your goal; a plan you can keep beats a bigger one.")
        }
    }

    private var ifThenSection: some View {
        Section {
            TextField("If I'm late, the 15-minute version", text: $ifThen, axis: .vertical)
                .lineLimit(1...3)
            SuggestionChips(options: WeeklyPlan.ifThenSuggestions, selection: $ifThen)
        } header: {
            Text("If the day goes wrong")
        } footer: {
            Text("Deciding in advance what you'll do when you're late, tired or away is what keeps a plan alive. If-then plans had a medium-to-large effect on following through across 94 studies (Gollwitzer & Sheeran 2006), and coping plans like this predicted still exercising months later (Sniehotta et al. 2005).")
        }
    }

    private var reviewTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings.weeklyReviewMinutes * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.weeklyReviewMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let initialDays {
            days = initialDays
        } else if let current = store.plan(for: weekStart) {
            days = current.sortedDays
        } else if let last = store.lastPlan(before: weekStart), !last.plannedDays.isEmpty {
            days = last.sortedDays
        } else {
            let count = suggestedCount
            let focuses = WeeklyPlan.focusRotation(start: suggestedStart, count: count)
            days = zip(WeeklyPlan.suggestedWeekdays(count: count), focuses).map { weekday, focus in
                PlannedDay(weekday: weekday, time: 18 * 60, focus: focus, minutes: 45)
            }
        }
        ifThen = days.compactMap(\.ifThen).first ?? ""
    }

    /// The focus that has rested longest, so the rotation starts there.
    private var suggestedStart: WorkoutFocus {
        WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
    }

    private func toggle(_ weekday: Int) {
        if let index = days.firstIndex(where: { $0.weekday == weekday }) {
            days.remove(at: index)
            return
        }
        guard days.count < WeeklyPlan.dayRange.upperBound else { return }
        let template = days.last
        var added = days + [PlannedDay(weekday: weekday, time: template?.time ?? 18 * 60, focus: .fullBody, minutes: template?.minutes ?? 45)]
        added.sort { WeeklyPlan.order($0.weekday) < WeeklyPlan.order($1.weekday) }
        // The new day takes its place in the rotation; the others keep what the user picked.
        if let position = added.firstIndex(where: { $0.weekday == weekday }) {
            let rotation = WeeklyPlan.focusRotation(start: suggestedStart, count: added.count)
            added[position].focus = rotation[min(position, rotation.count - 1)]
        }
        days = added
    }

    private func save() {
        var plan = store.plan(for: weekStart) ?? WeeklyPlan(weekStart: weekStart)
        let text = ifThen.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.plannedDays = days.map { day in
            var copy = day
            copy.ifThen = text.isEmpty ? nil : text
            return copy
        }
        store.save(plan)
        dismiss()
    }
}

// MARK: - Pieces

/// Seven tappable day circles, Monday first.
private struct WeekdayPicker: View {
    let selected: [Int]
    let toggle: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WeeklyPlan.weekdayOrder, id: \.self) { weekday in
                let isOn = selected.contains(weekday)
                // A tap gesture, not a Button: in a Form row a tap on one button can trigger another (see ChipFlow).
                Text(String(WeeklyPlan.weekdayName(weekday).prefix(2)))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(isOn ? .white : Theme.primaryText)
                    .background(isOn ? Theme.lifting : Theme.cardRaised, in: .circle)
                    .contentShape(.circle)
                    .onTapGesture { toggle(weekday) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WeeklyPlan.weekdayName(weekday))
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { toggle(weekday) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One planned day: time, session and length.
private struct PlannedDaySection: View {
    @Binding var day: PlannedDay

    private static let lengths = [15, 20, 30, 45, 60, 75, 90]

    var body: some View {
        Section {
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            Picker("Session", selection: $day.focus) {
                ForEach(WorkoutFocus.allCases) { focus in
                    Text(focus.shortTitle).tag(focus)
                }
            }
            Picker("Length", selection: $day.minutes) {
                ForEach(Self.lengths, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
        } header: {
            Text(WeeklyPlan.weekdayName(day.weekday))
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(day.time * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                day.time = (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// Tappable suggestions that fill the if-then field.
private struct SuggestionChips: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selection == option
                Text(option)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 8)
                    .foregroundStyle(isOn ? .white : Theme.primaryText)
                    .background(isOn ? Theme.lifting : Theme.cardRaised, in: .capsule)
                    .contentShape(.capsule)
                    .onTapGesture { selection = option }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(option)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selection = option }
            }
        }
        .padding(.vertical, 4)
    }
}
