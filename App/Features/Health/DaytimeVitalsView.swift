import SwiftUI
import SwiftData
import AppCore

/// Health › All measures › Daytime vitals: the row that opens the page.
struct DaytimeVitalsRow: View {
    var body: some View {
        // The identifier is "row-Daytime vitals" (`HealthNavigationRow`).
        HealthNavigationRow(
            title: "Daytime vitals",
            detail: "Heart rate, HRV and blood oxygen while awake",
            icon: "sun.max.fill",
            color: Theme.heart,
            hint: "Shows today's readings against your usual"
        ) {
            DaytimeVitalsView()
        }
    }
}

/// Vitals while awake, the counterpart of the overnight numbers: heart rate
/// at rest, HRV and blood oxygen for today or yesterday, each against the
/// same hours of the last four weeks, and the day hour by hour
/// (`DaytimeVitals` has the rules and their sources).
///
/// A description, not a score: daytime HRV as a stress read-out has tested
/// poorly (docs/research/watch-features.md §3.1, [B20]). So a day outside the
/// usual range gets a neutral chip, never amber or red, and the page says
/// what the readings can't tell you.
struct DaytimeVitalsView: View {
    enum DayChoice: String, CaseIterable, Identifiable {
        case today = "Today"
        case yesterday = "Yesterday"
        var id: String { rawValue }
        /// "today" or "yesterday", inside a sentence.
        var word: String { rawValue.lowercased() }
    }

    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var model = DaytimeVitalsModel()
    @State private var choice = DayChoice.today

    private var summary: DaytimeVitals.Summary? {
        choice == .today ? model.today : model.yesterday
    }

    var body: some View {
        HealthDetailPage(title: "Daytime vitals") {
            Picker("Day", selection: $choice) {
                ForEach(DayChoice.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("daytime-day-picker")
            content
        }
        .task { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private var content: some View {
        if let summary, summary.hasHeartRate {
            DaytimeHeartCard(summary: summary, day: choice, readingEarlierDays: model.isReadingEarlierDays)
            DaytimeHRVCard(summary: summary, day: choice, readingEarlierDays: model.isReadingEarlierDays)
            if summary.bloodOxygen.count > 0 {
                DaytimeOxygenCard(summary: summary, day: choice)
            }
            DaytimeChartCard(summary: summary, day: choice)
            DaytimeNotesCard()
        } else if model.isLoading || !model.hasLoaded {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading \(choice.word)'s heart rate…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("daytime-loading")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No heart rate for \(choice.word) yet")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("Wear your watch while you're awake. Its readings appear here once it has synced with Apple Health and Tensile can read heart rate (Apple Health → profile → Apps → Tensile).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("daytime-empty")
        }
    }

    private func load(force: Bool) async {
        guard let health else { return }
        // Sessions logged here in the window the page reads, in case one was not saved to Health.
        let cutoff = Calendar.current.date(byAdding: .day, value: -(DaytimeVitals.baselineWindowDays + 3), to: .now) ?? .now
        let logged: [DateInterval] = sessions.compactMap { session in
            guard session.startedAt >= cutoff, let ended = session.endedAt else { return nil }
            return DateInterval(start: session.startedAt, end: max(session.startedAt, ended))
        }
        await model.load(health: health, logged: logged, force: force)
    }
}

// MARK: - Wording shared by the cards

/// The words and numbers the daytime cards share.
enum DaytimeVitalsText {
    /// "58–64".
    static func range(_ usual: DaytimeVitals.Usual) -> String {
        "\(whole(usual.low))–\(whole(usual.high))"
    }

    /// The chip for a value with a usual range; nil while there is none.
    /// Inside the range is green; outside it is neutral, never amber or red:
    /// a daytime value off your usual has too many ordinary causes to be a
    /// warning (`DaytimeVitals`).
    static func chip(_ standing: DaytimeVitals.Standing) -> (text: String, color: Color)? {
        switch standing {
        case .within: return (text: "In your usual range", color: Theme.recoveryHigh)
        case .below: return (text: "Below your usual", color: Theme.secondaryText)
        case .above: return (text: "Above your usual", color: Theme.secondaryText)
        case .notEnoughReadings, .buildingUsual: return nil
        }
    }

    /// For VoiceOver.
    static func spoken(_ standing: DaytimeVitals.Standing) -> String? {
        chip(standing)?.text.lowercased()
    }

    /// Under a value that has no usual range yet.
    static func building(_ standing: DaytimeVitals.Standing, readingEarlierDays: Bool) -> String? {
        guard case .buildingUsual(let daysLeft) = standing else { return nil }
        if readingEarlierDays { return "Reading your earlier days…" }
        return "Your usual range appears after \(daysLeft) more day\(daysLeft == 1 ? "" : "s") with enough readings."
    }

    /// "From 21 of your last 28 days, same hours of the day."
    static func source(_ usual: DaytimeVitals.Usual) -> String {
        "From \(usual.days) of your last \(DaytimeVitals.baselineWindowDays) days, same hours of the day."
    }
}

// MARK: - Heart rate

/// The page's primary card: heart rate at rest while awake, against the
/// usual, with the awake average and range under it.
private struct DaytimeHeartCard: View {
    let summary: DaytimeVitals.Summary
    let day: DaytimeVitalsView.DayChoice
    let readingEarlierDays: Bool

    private var measure: DaytimeVitals.Measure { summary.restingLevel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Resting while awake", color: Theme.heartText)
                Spacer()
                Text("\(measure.count) still min\(day == .today ? " so far" : "")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let value = measure.value {
                DaytimeValueBlock(
                    value: value, unit: "bpm", spokenUnit: "beats per minute", title: "Resting while awake",
                    measure: measure, colors: Theme.heartColors, readingEarlierDays: readingEarlierDays
                )
                .accessibilityIdentifier("daytime-resting-value")
            } else {
                DaytimeShortfall(
                    title: "Not enough still minutes \(day.word)",
                    detail: "\(measure.count) of \(measure.needed) so far. It needs half an hour of heart rate while you're awake and still."
                )
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
                StatView(
                    label: "Awake average",
                    value: summary.awakeAverage.value.map { "\(whole($0)) bpm" } ?? "--",
                    detail: summary.awakeAverage.usual.map { "usual \(DaytimeVitalsText.range($0))" }
                )
                StatView(
                    label: "Awake range",
                    value: summary.awakeRange.map { "\(whole($0.lowerBound))–\(whole($0.upperBound)) bpm" } ?? "--",
                    detail: "workouts and walks included"
                )
            }
            Text("The level your heart rate settles to when you're awake and still. It sits a few beats above your sleeping heart rate.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(tint: Theme.heart)
    }
}

// MARK: - HRV

/// HRV while awake: the median of the day's readings, or "not enough
/// readings" on a watch that takes only a few a day.
private struct DaytimeHRVCard: View {
    let summary: DaytimeVitals.Summary
    let day: DaytimeVitalsView.DayChoice
    let readingEarlierDays: Bool

    private var measure: DaytimeVitals.Measure { summary.hrv }

    private var countText: String {
        let readings = "\(measure.count) reading\(measure.count == 1 ? "" : "s")"
        // SDNN or RMSSD: the two are not the same number, so the card says which.
        return summary.hrvMetric.map { "\(readings) · \($0.rawValue)" } ?? readings
    }

    private var shortfall: String {
        if measure.count == 0 {
            return "No HRV readings while you were awake and still. Apple Watch Series 12 and Ultra 4 take one about every five minutes."
        }
        if measure.count < measure.needed {
            return "\(measure.count) of \(measure.needed) readings while awake and still. Apple Watch Series 12 and Ultra 4 take one about every five minutes. Earlier watches take one every few hours, too few for a daytime number."
        }
        return "Readings from \(measure.hours) hour\(measure.hours == 1 ? "" : "s") so far. It needs \(measure.neededHours) different hours, so one sitting isn't taken for the day."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "HRV while awake", color: Theme.recoveryHighText)
                Spacer()
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let value = measure.value {
                DaytimeValueBlock(
                    value: value, unit: "ms", spokenUnit: "milliseconds", title: "HRV while awake",
                    measure: measure, colors: [Theme.recoveryHigh, Theme.oxygen], readingEarlierDays: readingEarlierDays
                )
                .accessibilityIdentifier("daytime-hrv-value")
            } else {
                DaytimeShortfall(title: "Not enough readings \(day.word)", detail: shortfall)
                    .accessibilityIdentifier("daytime-hrv-shortfall")
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    /// After a workout HRV can stay lower for hours (Stanley, Peake &
    /// Buchheit, Sports Med 2013), so the card says so on a day with one.
    private var footnote: String {
        let base = "The middle value of the readings taken while you were awake and still. It runs lower than your overnight HRV."
        return summary.workouts.isEmpty ? base : base + " After a hard session it can stay lower for hours; that is expected."
    }
}

// MARK: - Blood oxygen

/// Blood oxygen while awake, shown only when there are daytime readings.
private struct DaytimeOxygenCard: View {
    let summary: DaytimeVitals.Summary
    let day: DaytimeVitalsView.DayChoice

    private var measure: DaytimeVitals.Measure { summary.bloodOxygen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Blood oxygen while awake", color: Theme.oxygenText)
                Spacer()
                Text("\(measure.count) reading\(measure.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let value = measure.value {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(whole(value))")
                        .tileNumberFont()
                        .foregroundStyle(Theme.primaryText)
                    Text("%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 8)
                    // The same line as the overnight stat: 95% and above is normal near sea level.
                    Chip(text: value >= 95 ? "Normal" : "Low", color: value >= 95 ? Theme.recoveryHigh : Theme.recoveryModerate)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Blood oxygen while awake, \(whole(value)) percent, \(value >= 95 ? "normal" : "low")")
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                DaytimeShortfall(
                    title: "Not enough readings \(day.word)",
                    detail: "\(measure.count) of \(measure.needed) readings while awake."
                )
            }
            Text("95–100% is normal near sea level. Wrist readings are least reliable while moving or with cold hands.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var detail: String {
        var parts: [String] = []
        if let lowest = summary.lowestBloodOxygen { parts.append("Lowest \(whole(lowest))%") }
        if let usual = measure.usual { parts.append("your usual \(DaytimeVitalsText.range(usual))%") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Pieces

/// A hero number with its chip, the usual-range bar and what the usual is
/// built from; one element for VoiceOver.
private struct DaytimeValueBlock: View {
    let value: Double
    let unit: String
    let spokenUnit: String
    let title: String
    let measure: DaytimeVitals.Measure
    let colors: [Color]
    let readingEarlierDays: Bool

    private var spoken: String {
        var parts = ["\(title), \(whole(value)) \(spokenUnit)"]
        if let standing = DaytimeVitalsText.spoken(measure.standing) { parts.append(standing) }
        if let usual = measure.usual {
            parts.append("usual \(whole(usual.low)) to \(whole(usual.high)) at these hours")
        } else if let building = DaytimeVitalsText.building(measure.standing, readingEarlierDays: readingEarlierDays) {
            parts.append(building)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(whole(value))")
                    .heroNumberFont()
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(Theme.Typography.heroUnit)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let chip = DaytimeVitalsText.chip(measure.standing) {
                Chip(text: chip.text, color: chip.color)
            }
            if let usual = measure.usual {
                DaytimeUsualBar(value: value, usual: usual, color: colors.last ?? Theme.heart)
                Text("Your usual at these hours: \(DaytimeVitalsText.range(usual)) \(unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(DaytimeVitalsText.source(usual))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else if let building = DaytimeVitalsText.building(measure.standing, readingEarlierDays: readingEarlierDays) {
                Text(building)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// "Not enough readings today" and why, in place of a number.
private struct DaytimeShortfall: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where the day's value sits against the usual range: a track, the range as
/// a band and a dot for the value. Decorative: the words beside it say the same.
private struct DaytimeUsualBar: View {
    let value: Double
    let usual: DaytimeVitals.Usual
    let color: Color

    /// The track runs a little past the wider of the range and the value.
    private var bounds: ClosedRange<Double> {
        let span = max(usual.high - usual.low, 1)
        return (min(usual.low, value) - span * 0.6)...(max(usual.high, value) + span * 0.6)
    }

    private func fraction(_ number: Double) -> CGFloat {
        let width = bounds.upperBound - bounds.lowerBound
        guard width > 0 else { return 0.5 }
        return CGFloat(min(1, max(0, (number - bounds.lowerBound) / width)))
    }

    var body: some View {
        GeometryReader { geo in
            let low = geo.size.width * fraction(usual.low)
            let high = geo.size.width * fraction(usual.high)
            let dot = geo.size.width * fraction(value)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                    .frame(height: 8)
                Capsule()
                    .fill(color.opacity(0.35))
                    .frame(width: max(8, high - low), height: 8)
                    .offset(x: low)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().stroke(Theme.card, lineWidth: 2)
                    }
                    .offset(x: min(max(0, dot - 7), max(0, geo.size.width - 14)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - What it can and can't tell you

/// The page's note: what the numbers are, what moves them, and that this is
/// not a stress score (docs/research/watch-features.md §3.1, [B20]).
private struct DaytimeNotesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "What this can tell you")
            Group {
                Text("These are readings from minutes you were awake and still: no workouts, no walking, and not the 90 minutes after a workout.")
                Text("Each number is set against the same hours of your last four weeks, because heart rate and HRV change through the day.")
                Text("A day outside your usual range can follow a short night, alcohol, a hard session, a coming illness or a tense day. It can just as well follow coffee, a big meal, heat or more time on your feet. The watch can't tell these apart.")
                Text("So this is not a stress score, and one day is not a verdict. Stress scores built on daytime HRV have tested poorly in studies (Shterev 2025, a review). For recovery, your overnight numbers are steadier.")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            Text("\"Resting while awake\" is the calmest tenth of your still minutes. That rule is Tensile's own choice, not a standard, and Apple's resting heart rate uses Apple's own method, so the two can differ.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
