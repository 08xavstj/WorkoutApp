import SwiftUI
import AppCore

/// What moved today's recovery, in plain words, biggest effect first.
struct RecoveryContributorsSheet: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(CheckInStore.self) private var checkIns
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The evening before the night the score is from: two days back while the score is
        // still yesterday's, so it isn't explained by drinks logged after that reading.
        let yesterday = Calendar.current.date(byAdding: .day, value: metrics.recoveryIsFromYesterday ? -2 : -1, to: .now) ?? .now
        let drinks = checkIns.evening(on: yesterday)?.drinks
        let illness = vitals.illnessAlert(metrics: metrics, drinksLastNight: drinks, reportedSymptoms: checkIns.morning()?.isSick ?? false,
                                          daysSinceLastPeriod: checkIns.daysSinceLastPeriod())
        // Luteal-phase context after a logged period (Schmalenberger 2019; weak evidence, so a note only).
        let cycle = CycleRecovery.contributor(sex: metrics.sex, daysSinceLastPeriod: checkIns.daysSinceLastPeriod())
        let items = metrics.recoveryContributors(drinksLastNight: drinks, illness: illness) + (cycle.map { [$0] } ?? [])
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let recovery = metrics.recovery {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(recovery.score)%")
                                .font(.largeTitle.weight(.bold))
                                .fontDesign(.rounded)
                                .foregroundStyle(Theme.primaryText)
                            Text(recovery.isCalibrated ? RecoveryWording.label(for: recovery.status) : "Still learning your normal")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if items.isEmpty {
                        Text("Nothing to explain yet. Recovery needs a couple of weeks of nights to learn your normal HRV and resting heart rate.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .card()
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(items) { item in
                                ContributorRow(item: item)
                            }
                        }
                        .card()
                    }
                    // The scale in one line, the method one tap away (`RecoveryCalculator.howItWorks`).
                    Text("A night like your usual scores about \(RecoveryCalculator.usualScore). Under \(RecoveryCalculator.moderateBand.lowerBound) is an easy day; \(RecoveryCalculator.highBand.lowerBound) or more is recovered.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    EvidenceDisclosure(points: RecoveryCalculator().howItWorks, title: "How this score is worked out")
                    // Which HRV measure this is: useful, but jargon, so folded away.
                    if let metric = metrics.hrvMetric {
                        EvidenceDisclosure(points: [metrics.hrvMetricNote ?? metric], title: "About this number")
                    }
                    EvidenceDisclosure(points: [
                        "In elite athletes, HRV averaged over 7 days and compared with each person's own normal range tracked how training was going better than single mornings (Plews et al., Eur J Appl Physiol 2012).",
                        "In trials of HRV-guided training, a 7-day average below that range meant swapping a hard session for an easy one (Javaloyes et al., Int J Sports Physiol Perform 2019). The trials were in endurance athletes; evidence for lifting is thinner.",
                        "This app's 0-100 score itself hasn't been tested in studies, so treat it as a summary, not a measurement.",
                    ])
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("What moved recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ContributorRow: View {
    let item: RecoveryContributor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(label). \(item.explanation)")
    }

    private var icon: String {
        switch item.effect {
        case .raises: "arrow.up.circle.fill"
        case .lowers: "arrow.down.circle.fill"
        case .neutral: "minus.circle.fill"
        }
    }

    /// Amber, not red, for what lowered recovery: it's information to plan
    /// an easier day around, not an alarm (see `RecoveryWording`).
    private var color: Color {
        switch item.effect {
        case .raises: Theme.recoveryHighText
        case .lowers: Theme.recoveryModerateText
        case .neutral: Theme.secondaryText
        }
    }

    private var label: String {
        switch item.effect {
        case .raises: "raised recovery"
        case .lowers: "lowered recovery"
        case .neutral: "no real effect"
        }
    }
}
