import AppCore
import SwiftUI

/// The month as a grid of days, each with a dot per activity kind.
struct CalendarMonthGrid: View {
    let month: Date
    let days: [Date: ActivityCalendar.Day]
    @Binding var selected: Date?

    private let calendar = Calendar.current
    /// At most this many dots in a cell; more shows as "+".
    private let maximumDots = 3

    var body: some View {
        let cells = ActivityCalendar.monthGrid(containing: month, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(ActivityCalendar.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    cell(date)
                } else {
                    Color.clear.frame(height: 48).accessibilityHidden(true)
                }
            }
        }
    }

    private func cell(_ date: Date) -> some View {
        let day = days[date]
        let kinds = day?.kinds ?? []
        let isToday = calendar.isDateInToday(date)
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isFuture = date > .now
        return Button {
            selected = date
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isFuture ? Theme.secondaryText : Theme.primaryText)
                HStack(spacing: 3) {
                    ForEach(kinds.prefix(maximumDots), id: \.self) { kind in
                        Circle().fill(kind.color).frame(width: 6, height: 6)
                    }
                    if kinds.count > maximumDots {
                        Text("+")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.cardRaised : Color.clear)
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10).stroke(Theme.strain.opacity(0.6), lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(spoken(date, day: day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func spoken(_ date: Date, day: ActivityCalendar.Day?) -> String {
        let name = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let day, !day.activities.isEmpty else { return "\(name), no activities" }
        let count = day.activities.count
        return "\(name), \(count) \(count == 1 ? "activity" : "activities"): \(day.kinds.map(\.title).joined(separator: ", "))"
    }
}

/// Which colour is which kind, for the kinds this month has.
struct CalendarLegend: View {
    let kinds: [ActivityKind]

    var body: some View {
        if !kinds.isEmpty {
            // Wraps onto more lines rather than widening the page.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { items }
                VStack(alignment: .leading, spacing: 6) { items }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var items: some View {
        ForEach(kinds) { kind in
            HStack(spacing: 4) {
                Circle().fill(kind.color).frame(width: 8, height: 8)
                Text(kind.title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// Sessions, active days and time this month.
struct CalendarMonthSummaryCard: View {
    let summary: ActivityCalendar.MonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "This month")
            HStack(spacing: 0) {
                stat("\(summary.activeDays)", "active days")
                stat("\(summary.sessions)", summary.sessions == 1 ? "session" : "sessions")
                stat(Duration.seconds(summary.minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow)), "total time")
            }
            if !summary.byKind.isEmpty {
                Text(summary.byKind.map { "\($0.kind.title) \($0.sessions)" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One day's activities; each opens its detail page.
struct CalendarDayList: View {
    let date: Date
    let day: ActivityCalendar.Day?
    let model: CalendarMonthModel

    /// Miles where distances are in miles, as on the cardio pages.
    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .padding(.bottom, 8)
            if let day, !day.activities.isEmpty {
                ForEach(Array(day.activities.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    link(activity)
                }
            } else {
                Text("No activities this day.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    @ViewBuilder
    private func link(_ activity: ActivityCalendar.Activity) -> some View {
        if let session = model.sessionsByID[activity.id] {
            NavigationLink {
                WorkoutDetailView(session: session)
            } label: {
                row(activity, detail: sessionDetail(session))
            }
            .buttonStyle(.plain)
        } else if let workout = model.workoutsByID[activity.id] {
            NavigationLink {
                CardioWorkoutDetailView(workoutID: workout.uuid, title: workout.name)
            } label: {
                row(activity, detail: workoutDetail(activity))
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ activity: ActivityCalendar.Activity, detail: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: activity.kind.systemImage, color: activity.kind.color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func sessionDetail(_ session: WorkoutSession) -> String {
        let time = session.startedAt.formatted(date: .omitted, time: .shortened)
        let length = Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return "\(time) · \(length) · \(session.effortSets.count) sets"
    }

    private func workoutDetail(_ activity: ActivityCalendar.Activity) -> String {
        var parts = [activity.start.formatted(date: .omitted, time: .shortened),
                     Duration.seconds(activity.seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))]
        if let meters = activity.distanceMeters, meters >= 100 {
            parts.append(CardioSummary.distanceText(meters: meters, miles: miles))
        }
        return parts.joined(separator: " · ")
    }
}
