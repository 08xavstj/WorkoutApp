import AppCore
import Charts
import SwiftData
import SwiftUI

/// Fitness › Progress › Year in review: one year's sessions, time and
/// distance per activity type, records set, and the busiest month
/// (`YearInReview`; competitor-features-2026-11.md, B12). The evidence for
/// recaps is weak, so the page stays short and says so.
struct YearInReviewView: View {
    @Environment(\.healthClient) private var health
    @Environment(ExerciseLibrary.self) private var library
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var summary: YearInReview.Summary?

    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    /// This year, last year, and any earlier year with a logged session.
    private var years: [Int] {
        let calendar = Calendar.current
        let current = calendar.component(.year, from: .now)
        let logged = sessions.map { calendar.component(.year, from: $0.startedAt) }
        return Array(Set(logged + [current, current - 1])).sorted(by: >)
    }

    var body: some View {
        FitnessDetailPage(title: "Year in review") {
            Picker("Year", selection: $year) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let summary {
                if summary.sessions == 0 {
                    Text("Nothing logged or recorded in \(String(summary.year)).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .card()
                } else {
                    YearTotalsCard(summary: summary, miles: miles)
                    YearKindsCard(summary: summary, miles: miles)
                    YearMonthsCard(summary: summary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
            Text(YearInReview.evidenceNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: year) { await load() }
    }

    private func load() async {
        summary = nil
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .year, for: calendar.date(from: DateComponents(year: year, month: 6)) ?? .now) else { return }
        let finished = sessions.filter { !$0.isActive }
        let lifting = finished.filter { interval.contains($0.startedAt) }.map { session in
            ActivityCalendar.Activity(
                id: String(describing: session.persistentModelID), kind: .lifting, title: session.name,
                start: session.startedAt, end: session.endedAt ?? session.startedAt,
                linkedWorkoutIDs: Set([session.linkedWorkoutUUID, session.watchWorkoutUUID].compactMap { $0?.uuidString })
            )
        }
        var other: [ActivityCalendar.Activity] = []
        if let health, interval.start < .now {
            let found = (try? await health.externalWorkouts(from: interval.start, to: min(interval.end, .now))) ?? []
            other = found.map {
                ActivityCalendar.Activity(id: $0.uuid.uuidString, kind: $0.kind, title: $0.name, start: $0.start, end: $0.end,
                                          distanceMeters: $0.distanceKm.map { $0 * 1000 })
            }
        }
        // Lift records (`PRHistory`) and new cardio bests (`CardioBests`) set this year.
        let logged = LiftRecordInputs.sessions(finished)
        let liftRecords = PRHistory.events(logged, traits: LiftRecordInputs.traits(logged, library: library))
            .filter { interval.contains($0.date) }.count
        let cardioRecords = CardioBests.recordsSet(CardioBestsStore.workouts()).filter { interval.contains($0.date) }.count
        summary = YearInReview.summary(year: year, activities: ActivityCalendar.merged(lifting: lifting, health: other),
                                       records: liftRecords + cardioRecords, calendar: calendar)
    }
}

/// Sessions, active days, time, distance and records.
private struct YearTotalsCard: View {
    let summary: YearInReview.Summary
    let miles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: String(summary.year))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    tile("\(summary.sessions)", "sessions")
                    tile("\(summary.activeDays)", "active days")
                }
                GridRow {
                    tile(Duration.seconds(summary.seconds).formatted(.units(allowed: [.hours], width: .abbreviated)), "total time")
                    tile(summary.meters > 0 ? CardioSummary.distanceText(meters: summary.meters, miles: miles) : "–", "distance")
                }
                GridRow {
                    tile("\(summary.records)", "records set")
                    tile(summary.busiestMonth.map(monthName) ?? "–", "busiest month")
                }
            }
        }
        .card()
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func monthName(_ month: Int) -> String {
        Calendar.current.standaloneMonthSymbols[safe: month - 1] ?? "–"
    }
}

/// Sessions, time and distance per activity type.
private struct YearKindsCard: View {
    let summary: YearInReview.Summary
    let miles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "By activity").padding(.bottom, 8)
            ForEach(Array(summary.byKind.enumerated()), id: \.element.id) { index, total in
                if index > 0 { Divider().overlay(Theme.separator) }
                HStack(spacing: 12) {
                    IconBadge(systemName: total.kind.systemImage, color: total.kind.color, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(total.kind.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(detail(total))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func detail(_ total: YearInReview.KindTotal) -> String {
        var parts = ["\(total.sessions) \(total.sessions == 1 ? "session" : "sessions")",
                     Duration.seconds(total.seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))]
        if total.kind.hasDistance, let meters = total.meters {
            parts.append(CardioSummary.distanceText(meters: meters, miles: miles))
        }
        return parts.joined(separator: " · ")
    }
}

/// Sessions per month, the busiest one highlighted.
private struct YearMonthsCard: View {
    let summary: YearInReview.Summary

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneMonthSymbols
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Sessions per month")
            Chart {
                ForEach(Array(summary.sessionsPerMonth.enumerated()), id: \.offset) { index, count in
                    BarMark(x: .value("Month", "\(index)"), y: .value("Sessions", count))
                        .foregroundStyle(index + 1 == summary.busiestMonth ? Theme.strain : Theme.oxygen.opacity(0.7))
                        .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let key = value.as(String.self), let index = Int(key) {
                            Text(symbols[safe: index] ?? "")
                        }
                    }
                }
            }
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sessions per month")
            .accessibilityValue(summary.sessionsPerMonth.enumerated()
                .map { "\(Calendar.current.standaloneMonthSymbols[safe: $0.offset] ?? ""): \($0.element)" }
                .joined(separator: ", "))
        }
        .card()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
