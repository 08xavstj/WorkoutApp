import SwiftUI
import AppCore

/// The owner's own weekly drink limit, on the alcohol card (`DrinkLimit`).
/// Shown only once the last four weeks average three or more a week, or
/// while a limit is set; otherwise nothing at all. A self-set goal is the
/// part of digital alcohol tools tied to larger effects, and the effect is
/// small (Kaner et al., Cochrane 2017; Oldham et al., EClinicalMedicine 2024).
struct DrinkLimitSection: View {
    @Environment(CheckInStore.self) private var checkIns
    @AppStorage(HealthyLivingSettings.drinkLimitKey) private var limit: Double?

    private var history: DrinkLimit.History {
        DrinkLimit.history(evenings: Self.evenings(checkIns, days: DrinkLimit.weeks * AlcoholWeek.nights))
    }

    var body: some View {
        let recent = history
        if DrinkLimit.isOffered(history: recent, limit: limit) {
            VStack(alignment: .leading, spacing: 8) {
                if let limit {
                    Stepper(value: Binding(get: { Int(limit) }, set: { self.limit = Double($0) }), in: DrinkLimit.range) {
                        Text("Your limit: up to \(Int(limit)) a week")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                    }
                    .accessibilityIdentifier("alcohol-limit-stepper")
                    Text(DrinkLimit.line(drinks: Self.lastSevenNights(checkIns).drinks, limit: limit))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.primaryText)
                    Button("Remove the limit") { self.limit = nil }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("alcohol-limit-remove")
                } else {
                    Text("A weekly limit you choose")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Your last four weeks averaged \(average(recent)) a week. In trials of drink-tracking tools, setting your own goal went with cutting down a little more; the effect is small.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set a limit") { limit = Double(DrinkLimit.suggested(history: recent)) }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("alcohol-limit-set")
                }
                if DrinkLimit.staysInTopTier(recent) {
                    Text(DrinkLimit.clinicianLine)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider().overlay(Theme.separator)
        }
    }

    private func average(_ history: DrinkLimit.History) -> String {
        (history.weeklyAverage ?? 0).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The check-ins from the last `days` evenings, today's included.
    static func evenings(_ checkIns: CheckInStore, days: Int, now: Date = .now) -> [EveningCheckIn] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<days)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .compactMap { checkIns.evening(on: $0) }
    }

    /// The same seven evenings the alcohol card totals.
    static func lastSevenNights(_ checkIns: CheckInStore) -> AlcoholWeek.Total {
        AlcoholWeek.total(evenings: evenings(checkIns, days: AlcoholWeek.nights))
    }
}

/// In the evening check-in: the week's count with tonight's answer, against
/// the limit. Nothing without a limit.
struct DrinkLimitEveningLine: View {
    /// The evening being answered.
    let day: Date
    /// Tonight's drinks as answered so far, nil when not answered.
    let tonight: Double?

    @Environment(CheckInStore.self) private var checkIns
    @AppStorage(HealthyLivingSettings.drinkLimitKey) private var limit: Double?

    var body: some View {
        if let limit {
            let calendar = Calendar.current
            // The six evenings before this one, from the saved check-ins, plus tonight's answer.
            let before = (1..<AlcoholWeek.nights)
                .compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: day)) }
                .compactMap { checkIns.evening(on: $0) }
            let total = AlcoholWeek.total(evenings: before).drinks + (tonight ?? 0)
            Text(DrinkLimit.eveningLine(drinks: total, limit: limit))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("checkin-drink-limit")
        }
    }
}
