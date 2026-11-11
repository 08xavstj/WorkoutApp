import SwiftUI
import AppCore

/// Oura's own numbers for the latest night, from the direct link
/// (`OuraLink`): readiness, sleep score, overnight HRV and temperature
/// change. Shown as Oura reports them; Tensile's recovery and sleep scores
/// use their own math. Hidden until the ring is connected and synced.
struct OuraCard: View {
    @State private var link = OuraLink.shared

    private struct Night {
        var day: String
        var readiness: Int?
        var sleepScore: Int?
        var hrv: Double?
        var temperature: Double?
    }

    /// The newest day with a readiness or sleep score, plus that morning's HRV.
    private var latest: Night? {
        _ = link.syncedAt // re-read after each sync
        let contents = OuraCache.shared.contents
        let days = Set(contents.readiness.map(\.day)).union(contents.dailySleep.map(\.day))
        guard let day = days.max() else { return nil }
        let readiness = contents.readiness.first { $0.day == day }
        let main = contents.periods.filter { $0.day == day && $0.type == "long_sleep" }
            .max { $0.bedtimeEnd.timeIntervalSince($0.bedtimeStart) < $1.bedtimeEnd.timeIntervalSince($1.bedtimeStart) }
        return Night(day: day, readiness: readiness?.score, sleepScore: contents.dailySleep.first { $0.day == day }?.score,
                     hrv: main?.averageHRV, temperature: readiness?.temperatureDeviation)
    }

    var body: some View {
        if link.status == .connected, let night = latest {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "Oura ring")
                    Spacer()
                    Text(dayText(night.day))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack(alignment: .top, spacing: 12) {
                    stat("Readiness", night.readiness.map(String.init))
                    stat("Sleep score", night.sleepScore.map(String.init))
                    stat("HRV", night.hrv.map { "\(Int($0.rounded())) ms" })
                    stat("Temp.", night.temperature.map(temperatureText))
                }
                // HRV is RMSSD (Shaffer & Ginsberg, Front Public Health 2017: not interchangeable with SDNN).
                Text("Oura's own scores, as Oura reports them. HRV is the night's average RMSSD; temperature is the change from your usual. Tensile's recovery uses its own math.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "–")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "+0.3 °C", or °F where the phone uses them (a change, so ×1.8 without the offset).
    private func temperatureText(_ celsius: Double) -> String {
        let fahrenheit = Locale.current.measurementSystem == .us
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
