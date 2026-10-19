import SwiftUI
import AppCore

/// Your own next-morning numbers after drinking vs not.
struct AlcoholEffectCard: View {
    let findings: [AlcoholEffect.Finding]
    let nightsLogged: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "How alcohol affects you", color: Theme.lifting)
            if findings.isEmpty {
                Text(nightsLogged == 0
                     ? "Log drinks in the evening check-in (zero counts too) and after 5 nights with and 5 without, you'll see what drinking does to your next morning."
                     : "Needs at least 5 nights with a drink and 5 without. \(nightsLogged) night\(nightsLogged == 1 ? "" : "s") logged so far.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: finding.isWorse ? "arrow.down.heart.fill" : "equal.circle.fill")
                        .foregroundStyle(finding.isWorse ? Theme.recoveryModerateText : Theme.secondaryText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.sentence)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(finding.isClear ? "A clear difference for you." : "Not a clear difference yet; it may be chance.")
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
        .card(tint: Theme.lifting)
    }
}
