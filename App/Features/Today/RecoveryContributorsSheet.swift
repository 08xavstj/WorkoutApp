import SwiftUI
import AppCore

/// What moved today's recovery, in plain words, biggest effect first.
struct RecoveryContributorsSheet: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(CheckInStore.self) private var checkIns
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let drinks = checkIns.evening(on: yesterday)?.drinks
        let illness = vitals.illnessAlert(metrics: metrics, drinksLastNight: drinks, reportedSymptoms: checkIns.morning()?.isSick ?? false)
        let items = metrics.recoveryContributors(drinksLastNight: drinks, illness: illness)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let recovery = metrics.recovery {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(recovery.score)%")
                                .font(.largeTitle.weight(.bold))
                                .fontDesign(.rounded)
                                .foregroundStyle(Theme.primaryText)
                            Text(recovery.isCalibrated ? recovery.status.rawValue.capitalized : "Still learning your normal")
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
                    if let metric = metrics.hrvMetric {
                        Text(metric == "RMSSD"
                             ? "HRV is RMSSD (from your watch app, the camera reading or Apple Watch beat-to-beat data). Apple Health's SDNN isn't mixed in, since the two aren't comparable."
                             : "HRV is Apple Health's SDNN. If you add RMSSD readings (Garmin or the camera), the app switches to those.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text("The 7-day HRV trend against your normal range is the research-backed part (Plews et al., Eur J Appl Physiol 2012). The 0-100 score is the app's own summary of these inputs.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
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
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(label). \(item.detail)")
    }

    private var icon: String {
        switch item.effect {
        case .raises: "arrow.up.circle.fill"
        case .lowers: "arrow.down.circle.fill"
        case .neutral: "minus.circle.fill"
        }
    }

    private var color: Color {
        switch item.effect {
        case .raises: Theme.recoveryHighText
        case .lowers: Theme.recoveryLowText
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
