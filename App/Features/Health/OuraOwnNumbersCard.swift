import AppCore
import SwiftUI

/// "Oura's own numbers": Readiness and Sleep scores, stress, resilience,
/// cardiovascular age, Cardio Capacity (VO₂ max) and the breathing
/// disturbance index, as Oura reports them.
///
/// Added on the owner's explicit request (18 Nov 2026), overriding the
/// evidence review that left them out (docs/research/oura-ring-2026-11.md
/// §5-6): none has published validation of the number itself. So the card
/// says so on every row, sits apart from Tensile's own cards, and nothing in
/// Tensile's scores, baselines, coach or recommendations reads these values
/// (`OuraOwnNumbers`). Hidden until Oura is connected and the panel is on
/// (Settings › Oura Ring).
struct OuraOwnNumbersCard: View {
    @State private var link = OuraLink.shared
    @Environment(UserSettings.self) private var settings
    @AppStorage(OuraOwnNumbersSetting.key) private var isOn = true

    private var rows: [OuraOwnNumbers.Row] {
        _ = link.syncedAt // re-read after each sync
        return OuraOwnNumbersStore.shared.numbers.rows(age: settings.heartRateProfile(restingHeartRate: nil).age)
    }

    var body: some View {
        if isOn, link.status == .connected {
            let rows = rows
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(text: "Oura's own numbers")
                Text("Oura's formulas, shown as Oura reports them. None has been validated in a published study, so Tensile's scores and advice don't use them.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if rows.isEmpty {
                    Text(link.needsReconnect
                         ? "\(link.reconnectPrompt ?? "Oura's permissions don't match what Tensile asks for.") Reconnect in Settings › Data & privacy › Oura Ring to load these."
                         : "Nothing yet. They appear after the next sync, once Oura has worked them out.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows) { row in
                    OuraOwnNumberRow(row: row)
                    if row.id != rows.last?.id {
                        Divider().overlay(Theme.separator)
                    }
                }
                if !rows.isEmpty, link.needsReconnect {
                    Text("Some may be missing: reconnect Oura in Settings › Oura Ring to allow them.")
                        .font(.caption)
                        .foregroundStyle(Theme.recoveryModerateText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }
}

private struct OuraOwnNumberRow: View {
    let row: OuraOwnNumbers.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.id.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Text(dayText(row.day))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .center, spacing: 10) {
                Text(row.value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if row.recent.count >= 2 {
                    MiniBars(values: row.recent)
                        .frame(width: 64, height: 22)
                        .accessibilityHidden(true)
                }
            }
            Text(row.id.evidence)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Today", "Yesterday" or the date, from Oura's "YYYY-MM-DD".
    private func dayText(_ day: String) -> String {
        let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        guard let date = try? style.parse(day) else { return day }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The last week as small bars, scaled to its own range: a shape, not a scale.
private struct MiniBars: View {
    let values: [Double]

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let share = high > low ? (value - low) / (high - low) : 0.5
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == values.count - 1 ? Theme.neutralIcon : Theme.track)
                    .frame(height: max(3, 22 * (0.25 + 0.75 * share)))
            }
        }
    }
}
