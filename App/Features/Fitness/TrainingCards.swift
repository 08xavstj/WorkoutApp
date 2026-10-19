import SwiftUI
import SwiftData
import AppCore

// MARK: - Your workouts

/// Shortcut to your own workouts and an empty workout.
struct YourWorkoutsCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkoutLauncher.self) private var launcher
    @Query private var templates: [WorkoutTemplate]

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                MyWorkoutsView()
            } label: {
                HStack(spacing: 10) {
                    IconBadge(systemName: "list.bullet.rectangle.portrait.fill", color: Theme.sleep, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("My workouts")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(templates.isEmpty ? "Build your own" : "\(templates.count) saved")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                launcher.startEmpty(in: modelContext)
            } label: {
                Label("Empty", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start an empty workout")
        }
        .card()
    }
}

// MARK: - Weekly sets per muscle

/// Hard sets per muscle this week against the 10-20 range, with helper
/// muscles counted as half a set (Pelland et al., Sports Med 2026).
struct WeeklySetsCard: View {
    @Environment(MuscleModel.self) private var muscles

    private static let shown: [Muscle] = [.chest, .shoulders, .triceps, .lats, .middleBack, .biceps, .quadriceps, .hamstrings, .glutes, .calves, .abdominals]
    /// The bar's right end, in sets.
    private static let scale = 25.0

    var body: some View {
        let states = Self.shown.compactMap { muscles.states[$0] }
        let anyTrained = states.contains { $0.weeklySets >= 0.5 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Hard sets this week", color: Theme.lifting)
                Spacer()
                Text("Target 10-20")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.recoveryHighText)
            }
            if !anyTrained {
                Text("Log a gym session and each muscle's sets for the last 7 days show here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(states) { state in
                    row(state)
                }
                Text("A hard set is one taken within about 4 reps of failure. About 10-20 a week per muscle builds the most muscle for most people (Schoenfeld et al., J Sports Sci 2017); more still helps a little, with diminishing returns past 20 (Pelland et al., Sports Med 2026). Sets for helper muscles (e.g. triceps on bench press) count as half.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private func row(_ state: MuscleRecovery.State) -> some View {
        let sets = state.weeklySets
        let color: Color = switch state.volume {
        case .none, .low: Theme.oxygen
        case .productive: Theme.recoveryHigh
        case .high: Theme.strain
        }
        return HStack(spacing: 10) {
            Text(state.muscle.name)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    // The 10-20 band.
                    Rectangle()
                        .fill(Theme.recoveryHigh.opacity(0.18))
                        .frame(width: width * 10 / Self.scale)
                        .offset(x: width * 10 / Self.scale)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, width * min(1, sets / Self.scale)))
                }
            }
            .frame(height: 10)
            Text(sets.formatted(.number.precision(.fractionLength(0...1))))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.muscle.name): \(sets.formatted(.number.precision(.fractionLength(0...1)))) hard sets this week, \(state.volume.rawValue.lowercased())")
    }
}

// MARK: - Strength days

/// Strength training on 2+ days a week (WHO 2020).
struct StrengthDaysCard: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        let dates = sessions.filter { !$0.isActive && !$0.workingSets.isEmpty }.map(\.startedAt)
        let thisWeek = StrengthDays.lastSevenDays(dates)
        let weeks = StrengthDays.weekly(dates, weeks: 4)
        let met = thisWeek >= StrengthDays.weeklyTarget
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Strength days", color: Theme.lifting)
                Spacer()
                Chip(text: met ? "Goal reached" : "\(StrengthDays.weeklyTarget - thisWeek) more this week", color: met ? Theme.recoveryHigh : Theme.lifting)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(thisWeek)")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                Text("of \(StrengthDays.weeklyTarget)+ days in the last 7")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, days in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(days >= StrengthDays.weeklyTarget ? Theme.recoveryHigh : Theme.track)
                            .frame(height: 8)
                        Text(index == weeks.count - 1 ? "This week" : "\(weeks.count - 1 - index)w ago")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(index == weeks.count - 1 ? "This week" : "\(weeks.count - 1 - index) weeks ago"): \(days) strength days")
                }
            }
            Text("Health guidelines recommend strength training on 2 or more days a week (WHO 2020). It's linked with 10-17% lower risk of early death, with most of the benefit by 30-60 minutes a week (Momma et al., Br J Sports Med 2022).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

// MARK: - Cardio fitness

/// VO₂ max against your age group, and what to do when it stalls.
struct CardioFitnessCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(UserSettings.self) private var settings

    var body: some View {
        let series = (vitals.stat("vo2")?.series ?? []).map { DayValue(date: $0.date, value: $0.value) }
        let result = CardioFitness.assess(series, age: settings.age, sex: settings.sex)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Cardio fitness (VO₂ max)", color: Theme.oxygen)
                Spacer()
                if let result {
                    Chip(text: result.label, color: result.label == "Poor" ? Theme.recoveryModerate : Theme.recoveryHigh)
                }
            }
            if let result {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(result.latest.formatted(.number.precision(.fractionLength(1))))
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.primaryText)
                    Text("ml/kg/min")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    if let change = result.change {
                        Text("\(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(1)))) in 8 weeks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change >= CardioFitness.meaningfulChange ? Theme.recoveryHighText : Theme.secondaryText)
                    }
                }
                Text("The typical \(settings.sex == .male ? "man" : "woman") your age is about \(result.median.formatted(.number.precision(.fractionLength(0)))); you're at \(Int(result.percentOfMedian.rounded()))% of that (FRIEND registry, Kaminsky et al., Mayo Clin Proc 2015).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Label {
                    Text(advice(result))
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: result.isPlateau ? "arrow.up.right.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(result.isPlateau ? Theme.strain : Theme.recoveryHigh)
                }
                Text("Higher fitness is strongly linked with longer life, with no upper limit found (Mandsager et al., JAMA Netw Open 2018). Watch VO₂ max is an estimate; watch the trend.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("No VO₂ max yet. Your watch estimates it from outdoor walks and runs with heart rate; it appears here once it's in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.oxygen)
    }

    private func advice(_ result: CardioFitness.Result) -> String {
        if result.isPlateau {
            return "It hasn't risen in about 8 weeks. Add 1-2 interval sessions a week (for example 4 × 4 minutes hard with 3 minutes easy between): intervals raise VO₂ max more than steady cardio (Milanović et al., Sports Med 2015). Keep easy, conversational cardio as your base, not as the way to push VO₂ max up (Storoschuk et al., Sports Med 2025)."
        }
        if let change = result.change, change >= CardioFitness.meaningfulChange {
            return "It's rising. Keep the mix of easy cardio and 1-2 harder sessions a week."
        }
        return "Keep at least 150 minutes of moderate cardio a week, with 1-2 harder interval sessions to keep it improving."
    }
}
