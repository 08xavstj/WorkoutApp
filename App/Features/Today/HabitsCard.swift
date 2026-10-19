import SwiftUI
import HealthKit
import AppCore

/// Small daily habits with research behind them: when to stop caffeine,
/// protein spread over meals, and whether weight is changing too fast.
struct HabitsCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns
    @Environment(\.healthClient) private var health
    @State private var caffeineToday: [DatedValue] = []
    @State private var proteinToday: [DatedValue] = []

    private var bedtime: Int { CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes) }

    /// The latest caffeine today: from your food app if it sends times, else the evening check-in.
    private var latestCaffeine: (minutes: Int, mg: Double)? {
        if let last = caffeineToday.last(where: { $0.value > 0 }) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: last.date)
            return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0), last.value)
        }
        if let evening = checkIns.evening(), let minutes = evening.lastCaffeineMinutes, let mg = evening.caffeineMg, mg > 0 {
            return (minutes, mg)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Daily habits", color: Theme.sleep)
            caffeineRow
            proteinRow
            if let message = weightMessage {
                row(icon: "scalemass.fill", color: Theme.recoveryModerateText, title: "Weight is changing fast", detail: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
        .task(id: metrics.nutritionToday?.proteinGrams) { await load() }
    }

    // MARK: Caffeine

    @ViewBuilder
    private var caffeineRow: some View {
        let coffee = CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 100)
        let preWorkout = CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 200)
        let bed = CaffeineTiming.clockText(bedtime)
        if let latest = latestCaffeine, CaffeineTiming.isTooLate(minutes: latest.minutes, mg: latest.mg, bedtimeMinutes: bedtime) {
            row(icon: "cup.and.saucer.fill", color: Theme.recoveryModerateText,
                title: "Caffeine at \(CaffeineTiming.clockText(latest.minutes)) is late for a \(bed) bedtime",
                detail: "It can cut your sleep tonight. Next time, last coffee by \(CaffeineTiming.clockText(coffee)).")
        } else {
            row(icon: "cup.and.saucer.fill", color: Theme.sleep,
                title: "Last coffee by \(CaffeineTiming.clockText(coffee))",
                detail: "Pre-workout by \(CaffeineTiming.clockText(preWorkout)), for your usual \(bed) bedtime. Caffeine closer to bed cut sleep by about 45 minutes in studies.")
        }
    }

    // MARK: Protein per meal

    @ViewBuilder
    private var proteinRow: some View {
        if let weight = metrics.bodyMassKg,
           let result = ProteinMeals.assess(proteinToday.map { (date: $0.date, grams: $0.value) }, bodyMassKg: weight) {
            switch result {
            case .noMealTimes:
                row(icon: "fork.knife", color: Theme.nutrition, title: "Protein per meal",
                    detail: "Your food app doesn't send meal times, so meals can't be told apart. Aim for about \(whole(weight * ProteinMeals.gramsPerKgPerMeal)) g at each of 4 meals.")
            case .meals(let meals, goodMeals: let good, perMealTarget: let target):
                row(icon: "fork.knife", color: Theme.nutrition,
                    title: "\(good) of \(ProteinMeals.targetMeals) meals with \(whole(target)) g+ protein",
                    detail: "\(meals.count) meal\(meals.count == 1 ? "" : "s") logged today. Spreading protein over 4 meals of about \(whole(target)) g builds the most muscle.")
            }
        }
    }

    // MARK: Weight pace

    private var weightMessage: String? {
        guard let weekly = metrics.weightTrendWeekly, let weight = metrics.bodyMassKg else { return nil }
        return WeightPace.message(WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: weight, goals: metrics.goals))
    }

    // MARK: Pieces

    private func row(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let health else { return }
        let start = Calendar.current.startOfDay(for: .now)
        caffeineToday = (try? await health.timedSamples(.dietaryCaffeine, unit: .gramUnit(with: .milli), from: start, to: .now)) ?? []
        proteinToday = (try? await health.timedSamples(.dietaryProtein, unit: .gram(), from: start, to: .now)) ?? []
    }
}
