import SwiftUI
import AppCore

/// Your own next-morning numbers after drinking vs not.
struct AlcoholEffectCard: View {
    let findings: [AlcoholEffect.Finding]
    let nightsLogged: Int

    @Environment(CheckInStore.self) private var checkIns

    /// Standard drinks over the last 7 evenings from the check-ins (itemised
    /// log where there is one, else the quick count), for `AlcoholWeek`.
    private var weekTotal: AlcoholWeek.Total {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let evenings = (0..<AlcoholWeek.nights)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .compactMap { checkIns.evening(on: $0) }
        return AlcoholWeek.total(evenings: evenings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "How alcohol affects you")
            weekRow
            if findings.isEmpty {
                Text(nightsLogged == 0
                     ? "Log drinks in the evening check-in (zero counts too). After 5 nights with and 5 without, you'll see what drinking does to your next morning."
                     : "Needs at least 5 nights with a drink and 5 without. \(nightsLogged) night\(nightsLogged == 1 ? "" : "s") logged so far.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 10) {
                    // The "worse" icon and a bold line only for a clear difference;
                    // a maybe-chance one stays neutral.
                    let clearlyWorse = finding.isWorse && finding.isClear
                    Image(systemName: clearlyWorse ? "exclamationmark.circle.fill" : "equal.circle.fill")
                        .foregroundStyle(clearlyWorse ? Theme.recoveryModerateText : Theme.secondaryText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.sentence)
                            .font(finding.isClear ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Self.clarity(finding))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Text("In studies, alcohol lowers overnight HRV and raises heart rate in step with how much you drink, even in fit people, and from about two drinks it shortens dream (REM) sleep.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Neutral: pink means lifting only (ux-audit.md 4.5 colour rules, X3).
        .card()
    }

    /// Same rule as the patterns list (`AlcoholEffect.Finding.isClear`).
    private static func clarity(_ finding: AlcoholEffect.Finding) -> String {
        if finding.isClear { return "A clear difference for you." }
        if finding.nightsWith < 7 || finding.nightsWithout < 7 { return "Not clear yet: needs 7 nights each way." }
        return "Not a clear difference; it may be chance."
    }

    /// This week's total against Canada's 2023 tiers (0–2 low, 3–6 moderate,
    /// 7+ increasingly high; CCSA 2023), worded as a reference band.
    @ViewBuilder
    private var weekRow: some View {
        let total = weekTotal
        if total.nightsLogged > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Last 7 nights")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Chip(text: "\(total.drinks.formatted(.number.precision(.fractionLength(0...1)))) · \(total.tier.rawValue)",
                         color: tierColor(total.tier))
                }
                Text(AlcoholWeek.sentence(total))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Divider().overlay(Theme.separator)
        }
    }

    private func tierColor(_ tier: AlcoholWeek.Tier) -> Color {
        switch tier {
        case .low: Theme.recoveryHigh
        case .moderate: Theme.strain
        case .high: Theme.recoveryModerate
        }
    }
}
