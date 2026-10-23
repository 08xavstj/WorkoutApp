import SwiftUI
import AppCore

/// Illness watch on Home. Major signs (two or more together) get a full card
/// with a rest-mode button; a single minor sign is one quiet line. While rest
/// mode is on, a banner shows instead, with a button to end it.
struct IllnessAlertCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns
    @Environment(UserSettings.self) private var settings

    var body: some View {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let alert = vitals.illnessAlert(
            metrics: metrics,
            drinksLastNight: checkIns.evening(on: yesterday)?.drinks,
            reportedSymptoms: checkIns.morning()?.isSick ?? false
        )
        if settings.isRestMode {
            RestModeBanner()
        } else if let alert, alert.level == .major {
            majorCard(alert)
        } else if let alert {
            minorRow(alert)
        }
    }

    private func majorCard(_ alert: IllnessWatch.Alert) -> some View {
        let color = Theme.recoveryLow
        let immune = Micronutrients.notes(metrics.micronutrients, area: .immune)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Major signs: your body may be fighting something", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(Theme.textColor(for: color))
            Text(alert.message)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            // Wraps onto more lines instead of squeezing long signals.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(alert.signals, id: \.self) { Chip(text: $0, color: color) }
            }
            if !immune.isEmpty {
                Text("From your food log: " + immune.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                settings.setRestMode(true)
                metrics.restMode = true
            } label: {
                Label("Turn on rest mode for 3 days", systemImage: "bed.double.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(color)
            Text("Rest mode pauses strain targets and workout nudges. Not a diagnosis: see a doctor if you feel unwell or it lasts.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            ReportedSymptomsRow()
        }
        .card(tint: color)
    }

    private func minorRow(_ alert: IllnessWatch.Alert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.case")
                .foregroundStyle(Theme.recoveryModerateText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Minor sign: \(alert.signals.joined(separator: ", "))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                ReportedSymptomsRow()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Says which symptoms this morning's check-in has, with a button to clear
/// them if that's wrong.
private struct ReportedSymptomsRow: View {
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        if let morning = checkIns.morning(), morning.isSick {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("This morning's check-in: \(morning.symptoms.map(\.rawValue).joined(separator: ", ").lowercased()).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 4)
                Button("I feel fine") {
                    var cleared = morning
                    cleared.symptoms = []
                    checkIns.save(cleared)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}

/// Shown while rest mode is on.
struct RestModeBanner: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "bed.double.fill", color: Theme.sleep, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest mode")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(settings.restModeUntil.map { "Strain targets and workout nudges are paused until \($0.formatted(.dateTime.weekday(.wide)))." }
                     ?? "Strain targets and workout nudges are paused.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)
            Button("End") {
                settings.setRestMode(false)
                metrics.restMode = false
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(minHeight: 44)
        }
        .card(tint: Theme.sleep)
    }
}
