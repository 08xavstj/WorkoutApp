import AppCore
import SwiftData
import SwiftUI

/// Every activity in one month grid: logged gym sessions and the cardio and
/// sports workouts in Apple Health, a coloured dot per kind on each day.
/// Tap a day to list its activities; each opens its own detail page
/// (`ActivityCalendar`; competitor-features-2026-11.md, B6). It shows days
/// trained, never a streak (behaviour-change.md).
struct ActivityCalendarView: View {
    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selected: Date?
    @State private var workouts: [ExternalWorkout] = []

    private let calendar = Calendar.current

    /// Logged sessions and Health workouts this month as calendar activities,
    /// with what each one opens.
    private var model: CalendarMonthModel {
        CalendarMonthModel(sessions: sessions.filter { !$0.isActive }, workouts: workouts, month: month, calendar: calendar)
    }

    var body: some View {
        let model = self.model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    monthHeader
                    CalendarMonthGrid(month: month, days: model.days, selected: $selected)
                    CalendarLegend(kinds: model.summary.byKind.map(\.kind))
                }
                .card()
                CalendarMonthSummaryCard(summary: model.summary)
                if let selected {
                    CalendarDayList(date: selected, day: model.days[selected], model: model)
                }
                Text("Gym sessions come from your log; runs, rides and sports from Apple Health. The calendar shows days trained, not streaks.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: month) { await load() }
    }

    private var monthHeader: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") { move(by: -1) }
                .labelStyle(.iconOnly)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Next month", systemImage: "chevron.right") { move(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .font(.body.weight(.semibold))
        .tint(Theme.primaryText)
    }

    private func move(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = next
        selected = nil
    }

    private func load() async {
        if let health, let interval = calendar.dateInterval(of: .month, for: month), interval.start < .now {
            workouts = (try? await health.externalWorkouts(from: interval.start, to: min(interval.end, .now))) ?? []
        }
        // Open on today, or on the month's last active day.
        if selected == nil {
            let days = model.days
            let today = calendar.startOfDay(for: .now)
            selected = days[today] != nil ? today : days.keys.max()
        }
    }
}

/// The month's activities and where each leads.
struct CalendarMonthModel {
    let days: [Date: ActivityCalendar.Day]
    let summary: ActivityCalendar.MonthSummary
    let sessionsByID: [String: WorkoutSession]
    let workoutsByID: [String: ExternalWorkout]

    init(sessions: [WorkoutSession], workouts: [ExternalWorkout], month: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .month, for: month)
        var sessionsByID: [String: WorkoutSession] = [:]
        var lifting: [ActivityCalendar.Activity] = []
        for session in sessions where interval?.contains(session.startedAt) ?? false {
            let id = String(describing: session.persistentModelID)
            sessionsByID[id] = session
            let linked = Set([session.linkedWorkoutUUID, session.watchWorkoutUUID].compactMap { $0?.uuidString })
            lifting.append(ActivityCalendar.Activity(
                id: id, kind: .lifting, title: session.name, start: session.startedAt,
                end: session.endedAt ?? session.startedAt, linkedWorkoutIDs: linked
            ))
        }
        let other = workouts.filter { interval?.contains($0.start) ?? false }.map { workout in
            ActivityCalendar.Activity(id: workout.uuid.uuidString, kind: workout.kind, title: workout.name,
                                      start: workout.start, end: workout.end, distanceMeters: workout.distanceKm.map { $0 * 1000 })
        }
        let merged = ActivityCalendar.merged(lifting: lifting, health: other)
        let days = ActivityCalendar.days(merged, calendar: calendar)
        self.days = days
        summary = ActivityCalendar.summary(days, month: month, calendar: calendar)
        self.sessionsByID = sessionsByID
        workoutsByID = Dictionary(workouts.map { ($0.uuid.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

extension ActivityKind {
    /// The kind's dot and icon colour (Theme accents only).
    var color: Color {
        switch self {
        case .lifting: Theme.lifting
        case .run: Theme.oxygen
        case .walk: Theme.recoveryHigh
        case .ride: Theme.strain
        case .swim: Theme.sleepLight
        case .otherCardio: Theme.heart
        case .sport: Theme.recoveryModerate
        case .snow: Theme.sleep
        case .other: Theme.neutralIcon
        }
    }
}
