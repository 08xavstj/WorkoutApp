import SwiftUI
import SwiftData
import Charts
import AppCore

// Personal records: each lift's bests this year, over the last 12 months,
// all time or in an earlier year, with a month-by-month count of records.
// The rules (working sets only, no warm-ups or drop stages, nothing on a
// lift's first session) are `PRHistory`'s, the same as after a set.

// MARK: - Shared helpers

/// Logged sessions and per-lift traits as AppCore takes them.
enum LiftRecordInputs {
    /// Finished sessions, oldest first.
    static func sessions(_ all: [WorkoutSession]) -> [WorkoutSummary.LoggedSession] {
        all.filter { !$0.isActive }
            .sorted { $0.startedAt < $1.startedAt }
            .map(\.summaryInput)
    }

    /// Bodyweight and per-hand lifts, from the exercise library's equipment.
    static func traits(_ sessions: [WorkoutSummary.LoggedSession], library: ExerciseLibrary) -> [String: PRHistory.Traits] {
        var result: [String: PRHistory.Traits] = [:]
        let ids = Set(sessions.flatMap { $0.exercises.map(\.exerciseID) })
        for id in ids {
            let kind = EquipmentKind.fromLibrary(library.exercise(id: id)?.equipment)
            let catalogLoad = ExerciseCatalog.slot(for: id).flatMap { slot in
                ExerciseCatalog.options[slot]?.first { $0.id == id }
            }
            // The planner's catalog says "no load" for push-ups, pull-ups and dips.
            let bodyweight = kind == .bodyweight || (catalogLoad != nil && catalogLoad?.load == nil)
            result[id] = PRHistory.Traits(isBodyweight: bodyweight, isPerHand: Prescription.isPerHand(kind))
        }
        return result
    }
}

/// Record and weight wording in the gym's unit.
enum PRFormat {
    static func weight(_ kilograms: Double, _ unit: WeightUnit, perHand: Bool = false) -> String {
        let text = "\(unit.format(kilograms)) \(unit.rawValue)"
        return perHand ? text + " per hand" : text
    }

    static func volume(_ kilograms: Double, _ unit: WeightUnit) -> String {
        let value = unit.display(kilograms).formatted(.number.precision(.fractionLength(0)))
        return "\(value) \(unit.rawValue)"
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func record(_ record: PRHistory.Record, unit: WeightUnit, traits: PRHistory.Traits) -> String {
        switch record {
        case let .estimatedOneRepMax(value):
            return "Best estimated 1RM: \(weight(value, unit, perHand: traits.isPerHand))"
        case let .heaviest(kilograms, reps):
            let label = traits.isBodyweight ? "Most added weight" : "Heaviest"
            return "\(label): \(weight(kilograms, unit, perHand: traits.isPerHand)) × \(reps)"
        case let .reps(kilograms, reps):
            if kilograms <= 0 { return "Most reps in a set: \(reps)" }
            return "Most reps at \(weight(kilograms, unit, perHand: traits.isPerHand)): \(reps)"
        case let .volume(value):
            return "Most volume in a session: \(volume(value, unit))"
        }
    }
}

// MARK: - Entry rows (for Fitness › Progress)

/// "Personal records" and "Past blocks" rows, in one card.
struct ProgressRecordsCard: View {
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                PRYearView()
            } label: {
                RecordsLinkRow(title: "Personal records", detail: "Your bests by year", systemImage: "trophy")
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.separator)
            NavigationLink {
                PastBlocksView()
            } label: {
                RecordsLinkRow(title: "Past blocks", detail: "What each training block did", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}

/// Neutral icon, title, one line of detail and a chevron (as Fitness's link rows).
struct RecordsLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: systemImage, color: Theme.secondaryText, size: badgeSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
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
}

// MARK: - PR view

struct PRYearView: View {
    @Environment(GymStore.self) private var gym
    @Environment(ExerciseLibrary.self) private var library
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var period: PRHistory.Period = .thisYear
    @State private var data: PRPageData?

    private var unit: WeightUnit { gym.liftingUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data {
                    PRPeriodPicker(periods: data.periods, selection: $period)
                    PRTimelineCard(months: data.months, total: data.recordSessions)
                    PRLiftList(lifts: data.lifts, unit: unit)
                    PRFootnote()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .lockedToScreenWidth()
        }
        .background(alignment: .top) {
            TopGlow(colors: [Theme.Wash.butter, Theme.Wash.peach, Theme.Wash.rose])
        }
        .background(Theme.background)
        .navigationTitle("Personal records")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: PRTaskKey(period: period, count: sessions.count)) {
            data = makeData()
        }
    }

    private func makeData() -> PRPageData {
        let logged = LiftRecordInputs.sessions(sessions)
        let traits = LiftRecordInputs.traits(logged, library: library)
        let events = PRHistory.events(logged, traits: traits)
        let interval = period.interval()
        let months = PRHistory.timeline(events, interval: interval)
        return PRPageData(
            periods: PRHistory.periods(logged),
            months: months,
            recordSessions: months.reduce(0) { $0 + $1.count },
            lifts: PRHistory.bests(logged, traits: traits, in: interval, events: events)
        )
    }
}

private struct PRTaskKey: Hashable {
    var period: PRHistory.Period
    var count: Int
}

struct PRPageData {
    var periods: [PRHistory.Period]
    var months: [PRHistory.MonthCount]
    var recordSessions: Int
    var lifts: [PRHistory.ExerciseBests]
}

private struct PRPeriodPicker: View {
    let periods: [PRHistory.Period]
    @Binding var selection: PRHistory.Period

    var body: some View {
        Picker("Period", selection: $selection) {
            ForEach(periods) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.liftingText)
        .padding(.top, 8)
    }
}

/// Bars per month: lift sessions that set at least one record.
private struct PRTimelineCard: View {
    let months: [PRHistory.MonthCount]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Records by month", color: Theme.liftingText)
            Text(total == 1 ? "1 lift session with a record" : "\(total) lift sessions with a record")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            if months.isEmpty {
                Text("No records in this period yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                chart
            }
        }
        .card(tint: Theme.lifting)
    }

    private var chart: some View {
        Chart(months) { month in
            BarMark(x: .value("Month", month.month, unit: .month), y: .value("Records", month.count))
                .foregroundStyle(LinearGradient(colors: Theme.liftingColors, startPoint: .bottom, endPoint: .top))
                .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow))
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Records by month")
    }
}

private struct PRLiftList: View {
    let lifts: [PRHistory.ExerciseBests]
    let unit: WeightUnit

    var body: some View {
        if lifts.isEmpty {
            ContentUnavailableView(
                "No lifts in this period",
                systemImage: "trophy",
                description: Text("Finish a workout and your bests show up here.")
            )
        } else {
            VStack(spacing: 0) {
                ForEach(lifts) { lift in
                    NavigationLink {
                        LiftProgressView(exerciseID: lift.exerciseID, name: lift.name)
                    } label: {
                        PRLiftRow(lift: lift, unit: unit)
                    }
                    .buttonStyle(.plain)
                    if lift.id != lifts.last?.id {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .card()
        }
    }
}

private struct PRLiftRow: View {
    let lift: PRHistory.ExerciseBests
    let unit: WeightUnit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(lift.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    if lift.recordSessions > 0 {
                        Chip(text: lift.recordSessions == 1 ? "1 PR" : "\(lift.recordSessions) PRs", color: Theme.lifting)
                    }
                }
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows this lift's progress")
    }

    private var perHand: Bool { lift.traits.isPerHand }

    private var lines: [String] {
        var result: [String] = []
        if let best = lift.estimatedOneRepMax {
            let value = PRFormat.weight(best.value, unit, perHand: perHand)
            result.append("Est. 1RM \(value) · \(PRFormat.date(best.date))")
        }
        if let heaviest = lift.heaviest {
            let label = lift.traits.isBodyweight ? "Most added" : "Heaviest"
            let value = PRFormat.weight(heaviest.weightKg, unit, perHand: perHand)
            result.append("\(label) \(value) × \(heaviest.reps) · \(PRFormat.date(heaviest.date))")
        }
        let reps = lift.repMaxes.prefix(3).map(repText)
        if !reps.isEmpty { result.append("Most reps: " + reps.joined(separator: ", ")) }
        if let volume = lift.volume {
            result.append("Best session \(PRFormat.volume(volume.value, unit)) · \(PRFormat.date(volume.date))")
        }
        return result
    }

    private func repText(_ best: PRHistory.Best) -> String {
        if best.weightKg <= 0 { return "\(best.reps) at body weight" }
        let value = PRFormat.weight(best.weightKg, unit, perHand: perHand)
        return "\(best.reps) at \(value)"
    }
}

private struct PRFootnote: View {
    var body: some View {
        EvidenceDisclosure(points: [
            "Records count working sets only: no warm-ups, drop sets or mini-sets, and nothing on a lift's first session.",
            "Estimated 1RM is worked out from a set and the reps you had left (Epley with RPE). It's for comparing sessions, not a test.",
            "Bodyweight lifts show reps and any added weight. Dumbbell weights are per hand.",
            "Seeing how you compare with earlier sessions helps over a training cycle (Weakley et al., Sports Med 2023).",
        ], title: "How records count")
        .card()
    }
}
