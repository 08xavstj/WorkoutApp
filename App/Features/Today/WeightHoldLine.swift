import SwiftUI
import AppCore

/// On the Nutrition card, only when it applies (`WeightHold`): the offer to
/// hold once the weight trend reaches the target, and later one line if the
/// trend has sat more than about 2 kg above the held weight for two weeks.
/// Trend only, never red, nothing with Hide calories on or after weigh-ins
/// stop, and no regain line during a planned gain (healthy-living-2026-11.md
/// §3 item 6; Anderberg et al., Body Image 2025).
struct WeightHoldLine: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @AppStorage(HealthyLivingSettings.weightHoldKey) private var holdData: Data?
    @AppStorage(HealthyLivingSettings.holdOfferSnoozeKey) private var snoozedUntil: Double = 0

    private var holding: WeightHold.State? { HealthyLivingSettings.decodeHold(holdData) }

    var body: some View {
        let held = holding
        if let offer = WeightHold.offer(weights: metrics.recentWeights, goals: settings.goalsSet ? settings.goals : nil, holding: held,
                                        hideCalories: settings.hideCalories,
                                        snoozedUntil: snoozedUntil > 0 ? Date(timeIntervalSince1970: snoozedUntil) : nil) {
            line(icon: "scalemass") {
                Text("Your weight trend has reached your \(kg(offer.targetKg)) target.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Hold here: calories move to your measured maintenance, and one weigh-in a week keeps the trend current.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("Hold here") { hold(offer) }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("today-weight-hold")
                    Button("Not now") {
                        snoozedUntil = Date.now.addingTimeInterval(Double(WeightHold.offerAgainAfterDays) * 86_400).timeIntervalSince1970
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("today-weight-hold-not-now")
                }
                .buttonStyle(.borderless)
            }
        } else if let held,
                  let regain = WeightHold.regain(weights: metrics.recentWeights, holding: held, goals: settings.goals, hideCalories: settings.hideCalories) {
            let rate = shortCutRate
            line(icon: "scalemass") {
                Text("For two weeks your trend has sat \(kg(regain.aboveKg)) above the \(kg(held.targetKg)) you're holding.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Two ways from here: a short cut back, or keep the new weight. Either is fine.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { regainButtons(regain, holding: held, rate: rate) }
                    VStack(alignment: .leading, spacing: 8) { regainButtons(regain, holding: held, rate: rate) }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func regainButtons(_ regain: WeightHold.Regain, holding: WeightHold.State, rate: Double) -> some View {
        Button("Short cut, about \(WeightHold.shortCutWeeks(regain, ratePercent: rate)) weeks") {
            settings.goals = WeightHold.shortCutGoals(from: settings.goals, holding: holding, maximumPercent: rate)
            // The cut ends at the held weight, where the hold is offered again.
            holdData = nil
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("today-weight-short-cut")
        Button("Keep \(kg(WeightHold.accepted(regain).targetKg))") {
            holdData = HealthyLivingSettings.encodeHold(WeightHold.accepted(regain))
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("today-weight-accept")
    }

    private func line<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 6) { content() }
        } icon: {
            // Neutral, never red: a trend to act on, not a warning.
            Image(systemName: icon)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// The short cut's pace: 0.5% a week, or the person's own limit when lower.
    private var shortCutRate: Double {
        var cut = settings.goals
        cut.weight = .lose
        return min(WeightHold.shortCutRatePercent, metrics.rateLimit(for: cut).percent)
    }

    private func hold(_ offer: WeightHold.Offer) {
        settings.goals = WeightHold.holdGoals(from: settings.goals)
        holdData = HealthyLivingSettings.encodeHold(WeightHold.State(targetKg: offer.targetKg, since: .now))
    }

    private func kg(_ value: Double) -> String {
        let unit = settings.weightUnit
        return "\(unit.display(value).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)"
    }
}
