import SwiftUI
import AppCore

/// The latest night as the Oura ring measured it, from the direct link
/// (`OuraLink`): sleep time and stages, overnight HRV, sleeping heart rate,
/// breathing rate and temperature change, each labelled as Oura's.
/// Hidden until the ring is connected and synced.
///
/// Oura's Readiness and Sleep scores are not on this card: they are
/// proprietary composites with unpublished weights and no published
/// validation (docs/research/oura-ring-2026-11.md §5-6, [R49]). On the
/// owner's request they are shown apart, in `OuraOwnNumbersCard`. The measurements below
/// are the validated parts: HRV and heart rate against ECG (Dial et al.,
/// Physiol Rep 2025), total sleep against polysomnography (Robbins et al.,
/// Sensors 2024); stages and breathing rate have weaker evidence.
struct OuraCard: View {
    @State private var link = OuraLink.shared

    /// The newest main sleep (`Oura.mainSleep`, as the rest of the app files nights).
    private var latest: Oura.SleepPeriod? {
        _ = link.syncedAt // re-read after each sync
        let nights = Oura.mainSleep(OuraCache.shared.contents.periods)
        return nights.keys.max().flatMap { nights[$0] }
    }

    var body: some View {
        if link.status == .connected, let night = latest {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "From Oura")
                    Spacer()
                    Text(dayText(night.day))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack(alignment: .top, spacing: 12) {
                    stat("Asleep", night.totalSleepDuration.map(durationText))
                    stat("Deep", night.deepSleepDuration.map(durationText))
                    stat("Light", night.lightSleepDuration.map(durationText))
                    stat("REM", night.remSleepDuration.map(durationText))
                }
                HStack(alignment: .top, spacing: 12) {
                    // HRV is RMSSD (Shaffer & Ginsberg, Front Public Health 2017: not interchangeable with SDNN).
                    stat("HRV", night.averageHRV.map { "\(Int($0.rounded())) ms" })
                    stat("Sleeping HR", night.averageHeartRate.map { "\(Int($0.rounded())) bpm" })
                    stat("Breathing", night.averageBreath.map { "\($0.formatted(.number.precision(.fractionLength(1))))/min" })
                    stat("Temp.", night.temperatureDeviation.map(temperatureText))
                }
                if night.lowBatteryAlert == true {
                    // Oura's `low_battery_alert` on the sleep period (Oura API spec 1.43).
                    Label("The ring's battery ran low, so this night may be incomplete.", systemImage: "battery.25percent")
                        .font(.caption)
                        .foregroundStyle(Theme.recoveryModerateText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(footnote(night))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if link.needsReconnect {
                    Text("Reconnect Oura once in Settings › Oura Ring so its permissions match what Tensile now uses.")
                        .font(.caption)
                        .foregroundStyle(Theme.recoveryModerateText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private func footnote(_ night: Oura.SleepPeriod) -> String {
        let lowest = night.lowestHeartRate.map { " Lowest heart rate \(Int($0.rounded())) bpm." } ?? ""
        return "As the ring measured it. HRV is the night's average RMSSD; stages are estimates; temperature is the change from your usual.\(lowest) Oura's own scores are in their own card below and don't feed Tensile's."
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "–")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "7h 12m" or "48m", from Oura's seconds.
    private func durationText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// "+0.3 °C", or °F where the phone uses them (a change, so ×1.8 without the offset).
    private func temperatureText(_ celsius: Double) -> String {
        let fahrenheit = UnitText.usesFahrenheit // the app's Temperature setting, as everywhere else
        let value = fahrenheit ? celsius * 1.8 : celsius
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1)))) °\(fahrenheit ? "F" : "C")"
    }

    /// "Today", "Yesterday" or the date, from Oura's "YYYY-MM-DD".
    private func dayText(_ day: String) -> String {
        let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        guard let date = try? style.parse(day) else { return day }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
