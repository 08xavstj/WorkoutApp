import SwiftUI
import AppCore

/// One compact weather row on Today; tapping it opens the full weather card.
/// Weather used to be a daily card, though it matters for training only on
/// hot, high-UV or poor-air days (docs/research/ux-audit.md 4.6, H9). On those
/// days the row is a standard card leading with that tip. On days with only
/// info-level tips (morning light, rain, short days) it stays, so the weather
/// sheet can always be reached, but as a quieter flat row. "Add your city"
/// moved to the Finish setting up card and Settings.
struct ConditionsRow: View {
    @Environment(ConditionsModel.self) private var conditions
    @Environment(UserSettings.self) private var settings
    @State private var showingDetails = false

    var body: some View {
        if settings.hasLocation, let current = conditions.current, let first = conditions.tips.first {
            let notable = Self.todayTip(conditions.tips, uvIndex: current.uvIndexMax)
            Button { showingDetails = true } label: {
                ConditionsRowLabel(conditions: current, tip: notable ?? first, isNotable: notable != nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows today's weather")
            .sheet(isPresented: $showingDetails) {
                WeatherDetailSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// The tip worth a row on Today: heat (it also lowers the strain range;
    /// ACSM WBGT bands, Roberts et al. 2021, via `HeatAdvice`), poor air (US
    /// EPA AQI over 100), UV 6 or more (WHO "High" and above), and any other
    /// caution or warning (e.g. very cold). Info-only tips (morning light,
    /// rain, short days) get the calm row instead. Tips come most important
    /// first.
    static func todayTip(_ tips: [WeatherAdvice.Tip], uvIndex: Double?) -> WeatherAdvice.Tip? {
        tips.first { tip in
            switch tip.id {
            case "heat", "air":
                return true
            case "uv":
                return (uvIndex ?? 0) >= 6
            default:
                return tip.level >= .caution
            }
        }
    }
}

/// The row itself. A notable tip (heat, UV, air, cold) gets the standard card;
/// an info-only day gets a flat, quieter row so it doesn't compete with the
/// cards above it (ux-audit.md P7: one primary element per screen).
private struct ConditionsRowLabel: View {
    let conditions: Conditions
    let tip: WeatherAdvice.Tip
    let isNotable: Bool

    var body: some View {
        styled
            .contentShape(.rect(cornerRadius: Theme.cornerRadius))
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var styled: some View {
        if isNotable {
            content.card()
        } else {
            content
                .padding(Theme.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card.opacity(0.6), in: .rect(cornerRadius: Theme.cornerRadius))
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: conditions.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
                .frame(minWidth: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(conditions.temperature.rounded()))° · \(conditions.summary)")
                    .font(isNotable ? Font.subheadline.weight(.semibold) : Font.subheadline)
                    .foregroundStyle(Theme.primaryText)
                Text(tip.text)
                    .font(Theme.Typography.context)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
    }
}

/// The full weather card (was Today's daily weather card), in a sheet.
private struct WeatherDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                WeatherCard()
                    .padding()
                    .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Temperature, UV, air quality, daylight and every weather tip for today.
private struct WeatherCard: View {
    @Environment(ConditionsModel.self) private var conditions
    @Environment(UserSettings.self) private var settings

    var body: some View {
        if let c = conditions.current {
            VStack(alignment: .leading, spacing: 12) {
                header(c)
                // Wraps at large text sizes.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    if let uv = c.uvIndexMax { pill("sun.max", "UV \(Int(uv.rounded())) · \(uvWord(uv))") }
                    if let aqi = c.usAQI { pill("aqi.medium", "Air \(Int(aqi)) · \(airWord(Double(aqi)))") }
                    if let daylight = c.daylightHours { pill("sunrise", String(format: "%.1f h light", daylight)) }
                }
                if let sunrise = c.sunrise, let sunset = c.sunset {
                    Text("Sunrise \(sunrise.formatted(date: .omitted, time: .shortened)) · Sunset \(sunset.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(conditions.tips) { tip in
                    Label {
                        Text(tip.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: tip.level == .info ? "lightbulb.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(tip.level == .info ? Theme.oxygen : Theme.recoveryModerate)
                    }
                }
            }
            .card()
        } else {
            Text("No weather yet. It loads for the city in Settings when you're online.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .card()
        }
    }

    private func header(_ c: Conditions) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: c.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.largeTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(c.temperature.rounded()))° · \(c.summary)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Text("Feels \(Int(c.feelsLike.rounded()))°\(c.high.map { " · H \(Int($0.rounded()))°" } ?? "")\(c.low.map { " L \(Int($0.rounded()))°" } ?? "") · \(settings.placeName)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    /// WHO UV index categories.
    private func uvWord(_ uv: Double) -> String {
        switch uv {
        case ..<3: "Low"
        case ..<6: "Moderate"
        case ..<8: "High"
        case ..<11: "Very high"
        default: "Extreme"
        }
    }

    /// US EPA air quality index categories.
    private func airWord(_ aqi: Double) -> String {
        switch aqi {
        case ...50: "Good"
        case ...100: "Moderate"
        case ...150: "Unhealthy for some"
        case ...200: "Unhealthy"
        default: "Very unhealthy"
        }
    }

    /// Text in `oxygenText`, which passes 4.5:1 on its pill (ux-audit.md X4).
    private func pill(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.oxygenText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.oxygen.opacity(0.1), in: .capsule)
    }
}
