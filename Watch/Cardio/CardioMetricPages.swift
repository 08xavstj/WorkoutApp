import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

// The cardio metric pages (docs/research/watch-app-redesign-2026-11.md §4.5.2).
// Each page fits the screen without scrolling and shows at most four values:
// the primary one at 40-48 pt, the others at 24-32 pt, in rounded monospaced
// numerals (app's choice following the HIG's "use large font sizes" for
// workouts). The Digital Crown moves between them, as in Apple's Workout app.
// No double-tap action on these vertical pages (HIG Gestures): the system
// uses double tap to page them.

/// One metric page.
struct CardioMetricPageView: View {
    let page: CardioMetricPage

    var body: some View {
        switch page {
        case .main: CardioMainPage()
        case .zones: CardioZonesPage()
        case .pace: CardioPacePage()
        case .speed: CardioSpeedPage()
        case .elevation: CardioElevationPage()
        case .splits: CardioSplitsPage()
        case .target: CardioTargetOrIntervalPage()
        }
    }
}

/// The workout clock with the activity glyph, or "Paused" / "Auto-paused".
struct CardioClockLine: View {
    @Environment(WatchCardioModel.self) private var cardio
    var large = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let start = cardio.clockTimerStart {
                WorkoutClockText(start: start, pausedAt: cardio.pausedAt)
                    .font(large ? .title2.weight(.bold) : .headline)
                    .monospacedDigit()
                    .alwaysOnPrimary(cardio.pausedAt == nil ? WatchPalette.strain : .secondary)
            }
            Spacer(minLength: 2)
            if cardio.isAutoPaused {
                Text("Auto-paused")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.strain)
            } else if cardio.phase == .paused {
                Text("Paused")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.strain)
            } else {
                Image(systemName: cardio.activity.systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(cardio.activity.title)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Heart rate big in its zone colour, with the zone number beside it.
private struct HeartLine: View {
    @Environment(WatchCardioModel.self) private var cardio
    var role: WatchNumeral = .primary

    var body: some View {
        let zone = cardio.tracker.currentZone
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(cardio.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                .numeral(role)
                .alwaysOnPrimary(cardio.heartRate == nil ? .secondary : WatchPalette.zoneColor(zone))
            Text("bpm")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            if cardio.heartRate != nil {
                ZoneBadge(zone: zone)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let heartRate = cardio.heartRate else { return "No heart rate yet" }
        let zone = cardio.tracker.currentZone.map { "zone \($0)" } ?? "below zone 1"
        return "\(Int(heartRate.rounded())) beats per minute, \(zone)"
    }
}

/// "Z3" on the zone's colour (black label), or "<Z1" in grey; outlined in Always On.
struct ZoneBadge: View {
    let zone: Int?
    @Environment(\.isLuminanceReduced) private var reduced

    var body: some View {
        Text(zone.map { "Z\($0)" } ?? "<Z1")
            .font(.headline)
            .foregroundStyle(reduced ? WatchPalette.zoneColor(zone) : WatchPalette.onTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                if reduced {
                    Capsule().strokeBorder(WatchPalette.zoneColor(zone), lineWidth: 1.5)
                } else {
                    Capsule().fill(WatchPalette.zoneColor(zone))
                }
            }
    }
}

/// Distance, pace and speed as the pages show them.
private enum CardioText {
    static var miles: Bool { watchUsesMiles() }

    /// "5.02" and "km".
    static func distance(_ meters: Double?) -> (value: String, unit: String) {
        guard let meters else { return ("--", miles ? "mi" : "km") }
        let text = CardioSummary.distanceText(meters: meters, miles: miles)
        let parts = text.split(separator: " ")
        return (String(parts.first ?? "--"), String(parts.last ?? ""))
    }

    /// "5:12" from seconds per unit.
    static func pace(_ secondsPerUnit: Double?) -> String {
        guard let secondsPerUnit, secondsPerUnit.isFinite, secondsPerUnit > 0, secondsPerUnit < 60 * 60 else { return "--:--" }
        let text = CardioSummary.paceText(secondsPerUnit, miles: miles)
        return String(text.split(separator: " ").first ?? "--")
    }

    static var paceUnit: String { miles ? "/mi" : "/km" }

    /// "24.6" from km/h (or mph).
    static func speed(_ perHour: Double?) -> String {
        guard let perHour, perHour.isFinite, perHour >= 0 else { return "--" }
        let text = CardioSummary.speedText(perHour, miles: miles)
        return String(text.split(separator: " ").first ?? "--")
    }

    static var speedUnit: String { miles ? "mph" : "km/h" }

    /// m/s to km/h (or mph).
    static func perHour(_ metersPerSecond: Double?) -> Double? {
        metersPerSecond.map { $0 * 3.6 / (miles ? CardioSummary.metersPerMile / 1000 : 1) }
    }
}

// MARK: Main

/// Time, heart rate with its zone, and current pace or speed with distance.
/// Sports and machines: time, heart rate and calories.
private struct CardioMainPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardioClockLine()
            Spacer(minLength: 0)
            HeartLine()
            Spacer(minLength: 0)
            if cardio.activity.movement == .stationary {
                MetricBlock(value: cardio.activeKilocalories.map { "\(Int($0.rounded()))" } ?? "--", unit: "kcal",
                            label: "Active calories", role: .secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .bottom) {
                        if cardio.activity.movement.showsSpeed {
                            MetricBlock(value: CardioText.speed(CardioText.perHour(cardio.laps.currentSpeed(at: context.date))),
                                        unit: CardioText.speedUnit, label: "Speed", role: .tertiary)
                        } else {
                            MetricBlock(value: CardioText.pace(cardio.laps.currentPace(at: context.date, miles: CardioText.miles)),
                                        unit: CardioText.paceUnit, label: "Pace", role: .tertiary)
                        }
                        Spacer(minLength: 4)
                        let distance = CardioText.distance(cardio.distanceMeters)
                        MetricBlock(value: distance.value, unit: distance.unit, label: "Distance", role: .tertiary)
                    }
                }
            }
        }
    }
}

// MARK: Heart zones

/// Apple's Heart Rate Zones layout: the five-segment bar, the current zone
/// and its bpm range, heart rate, time in the current zone, average.
private struct CardioZonesPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        let tracker = cardio.tracker
        let zone = tracker.currentZone
        VStack(alignment: .leading, spacing: 4) {
            Text(zone.map { "Zone \($0) · \(tracker.scheme.rangeText(forZone: $0))" } ?? "Under zone 1")
                .font(.headline)
                .foregroundStyle(WatchPalette.zoneColor(zone))
                .lineLimit(1)
            LiveZoneBar(zone: zone)
            HeartLine(role: .primary)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                MetricBlock(value: zone.flatMap { $0 <= tracker.zoneSeconds.count ? watchClock(tracker.zoneSeconds[$0 - 1]) : nil } ?? "--",
                            label: "In zone", role: .tertiary)
                Spacer(minLength: 4)
                MetricBlock(value: (cardio.averageHeartRate ?? tracker.averageBpm).map { "\(Int($0.rounded()))" } ?? "--",
                            label: "Average", role: .tertiary)
            }
            Text(cardio.zoneSource.caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .hiddenWhenLuminanceReduced()
        }
    }
}

// MARK: Pace

/// Current pace (the last 20 s), this lap's pace and the average.
private struct CardioPacePage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let miles = CardioText.miles
            VStack(alignment: .leading, spacing: 2) {
                CardioClockLine(large: false)
                Spacer(minLength: 0)
                MetricBlock(value: CardioText.pace(cardio.laps.currentPace(at: context.date, miles: miles)),
                            unit: CardioText.paceUnit, label: "Current pace", role: .primary, color: WatchPalette.strain)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    MetricBlock(value: CardioText.pace(cardio.laps.currentLapPace(at: context.date, miles: miles)),
                                label: "\(miles ? "Mile" : "Km") \(cardio.laps.currentLapNumber)", role: .tertiary)
                    Spacer(minLength: 4)
                    MetricBlock(value: CardioText.pace(CardioSummary.pace(seconds: cardio.elapsed(at: context.date) ?? 0,
                                                                         meters: cardio.distanceMeters, miles: miles)),
                                label: "Average", role: .tertiary)
                }
            }
        }
    }
}

// MARK: Speed

/// Current, lap and average speed, and the top speed.
private struct CardioSpeedPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let miles = CardioText.miles
            let lap = cardio.laps.currentLap(at: context.date)
            VStack(alignment: .leading, spacing: 2) {
                CardioClockLine(large: false)
                Spacer(minLength: 0)
                MetricBlock(value: CardioText.speed(CardioText.perHour(cardio.laps.currentSpeed(at: context.date))),
                            unit: CardioText.speedUnit, label: "Current speed", role: .primary, color: WatchPalette.strain)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    MetricBlock(value: CardioText.speed(CardioSummary.speed(seconds: lap.seconds, meters: lap.meters, miles: miles)),
                                label: "Lap", role: .tertiary)
                    Spacer(minLength: 2)
                    MetricBlock(value: CardioText.speed(CardioSummary.speed(seconds: cardio.elapsed(at: context.date) ?? 0,
                                                                           meters: cardio.distanceMeters, miles: miles)),
                                label: "Average", role: .tertiary)
                    Spacer(minLength: 2)
                    MetricBlock(value: CardioText.speed(CardioText.perHour(cardio.topSpeed)), label: "Top", role: .tertiary)
                }
            }
        }
    }
}

// MARK: Elevation

/// Altitude now, the climb so far, and the last 30 minutes as a line (Apple's
/// Elevation view shows the last 30 minutes).
private struct CardioElevationPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        let feet = CardioText.miles
        let elevation = cardio.elevation
        VStack(alignment: .leading, spacing: 2) {
            CardioClockLine(large: false)
            HStack(alignment: .bottom) {
                MetricBlock(value: elevation.current.map { altitudeNumber($0, feet: feet) } ?? "--", unit: feet ? "ft" : "m",
                            label: "Altitude", role: .secondary)
                Spacer(minLength: 4)
                MetricBlock(value: altitudeNumber(elevation.gain, feet: feet), unit: feet ? "ft" : "m",
                            label: "Climbed", role: .secondary, color: WatchPalette.recovery)
            }
            let profile = elevation.profile(now: .now)
            if profile.count >= 2 {
                SeriesSparkline(points: profile, color: WatchPalette.recovery,
                                spoken: "Altitude over the last 30 minutes")
                    .frame(maxHeight: .infinity)
                    .hiddenWhenLuminanceReduced()
            } else {
                Text(cardio.activity.isOutdoor == true ? "Waiting for GPS altitude" : "No altitude indoors")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func altitudeNumber(_ meters: Double, feet: Bool) -> String {
        let value = Int((meters * (feet ? CardioSummary.feetPerMeter : 1)).rounded())
        return value.formatted()
    }
}

// MARK: Splits

/// The last three splits as bars (time per km or mile, taller is slower, the
/// fastest in green), the split now running, and a big Lap button.
private struct CardioSplitsPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let miles = CardioText.miles
            let recent = Array(cardio.laps.laps.suffix(3))
            let now = cardio.laps.currentLap(at: context.date)
            VStack(alignment: .leading, spacing: 4) {
                if recent.isEmpty {
                    Text("Splits every \(miles ? "mile" : "km")")
                        .font(.headline)
                    Text("Your first shows here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    splitBars(recent, miles: miles)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(miles ? "Mile" : "Km") \(cardio.laps.currentLapNumber)")
                        .font(.headline)
                    Spacer(minLength: 2)
                    Text("\(CardioText.distance(now.meters).value) · \(workoutElapsedText(now.seconds))")
                        .font(.headline)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                PrimaryWideButton(title: "Lap", systemImage: "flag.fill", tint: WatchPalette.strain) {
                    cardio.markLap()
                }
                .disabled(cardio.phase != .running || cardio.isAutoPaused)
            }
        }
    }

    private func splitBars(_ laps: [LapTracker.Lap], miles: Bool) -> some View {
        let values = laps.map { $0.pace(miles: miles) ?? 0 }
        let fastest = cardio.laps.fastestLapNumber
        let highlight = Set(laps.indices.filter { laps[$0].number == fastest })
        return VStack(spacing: 2) {
            ZStack {
                SplitBars(values: values, gap: 8)
                    .fill(WatchPalette.strain.opacity(0.7))
                SplitBars(values: values, gap: 8, only: highlight)
                    .fill(WatchPalette.recovery)
            }
            .frame(maxHeight: .infinity)
            .dimmedWhenLuminanceReduced()
            HStack(spacing: 8) {
                ForEach(laps) { lap in
                    Text(lap.pace(miles: miles).map { CardioText.pace($0) } ?? workoutElapsedText(lap.seconds))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(laps.map { lap in
            "\(miles ? "Mile" : "Kilometre") \(lap.number), \(workoutElapsedText(lap.seconds))"
        }.joined(separator: "; "))
    }
}

// MARK: Target

/// The Target page, or with an interval session the Interval page.
private struct CardioTargetOrIntervalPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        if cardio.interval != nil {
            CardioIntervalPage()
        } else {
            CardioTargetPage()
        }
    }
}

/// An interval session's step: "Hard 2 of 4", the time left in the step as a
/// ring, the step's band and effort cue, heart rate against it, and Skip step
/// (a 44 pt button; no double tap on these vertical pages, HIG Gestures).
private struct CardioIntervalPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let interval = cardio.interval, let progress = cardio.intervalProgress(at: context.date) {
                let step = progress.step
                let tint = step.phase.isHard ? WatchPalette.heart : WatchPalette.easy
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 8) {
                        ZStack {
                            Circle().stroke(WatchPalette.track, lineWidth: 6)
                                .hiddenWhenLuminanceReduced()
                            RingArc(fraction: progress.fractionLeft)
                                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .dimmedWhenLuminanceReduced()
                            Text(watchClock(Double(progress.remaining)))
                                .font(.headline)
                                .monospacedDigit()
                                .minimumScaleFactor(0.9)
                        }
                        .frame(width: 64, height: 64)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(progress.remaining) seconds left in this step")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title(rounds: interval.rounds))
                                .font(.headline)
                                .foregroundStyle(tint)
                            Text(step.target.band.text(in: cardio.tracker.scheme))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Text(step.target.effortText)
                        .font(.footnote.weight(.semibold))
                    Text(step.target.cue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .hiddenWhenLuminanceReduced()
                    Spacer(minLength: 0)
                    HStack {
                        HeartLine(role: .tertiary)
                        Button {
                            cardio.skipIntervalStep()
                        } label: {
                            Label("Skip step", systemImage: "forward.fill")
                                .font(.footnote.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(cardio.phase != .running)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Session done", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(WatchPalette.recovery)
                    Text("Keep moving easily, and end the workout from Controls when you're ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HeartLine(role: .secondary)
                }
            }
        }
    }
}

/// The target band as a vertical gauge with heart rate as a marker, where it
/// stands in words, and the time inside the band.
private struct CardioTargetPage: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        let tracker = cardio.tracker
        HStack(spacing: 10) {
            if let band = tracker.band {
                BandGauge(band: band, bpm: cardio.heartRate)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cardio.target.title)
                    .font(.headline)
                if let band = tracker.band {
                    Text("\(band.text) bpm")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let status = status(tracker.state) {
                    Text(status.text)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(status.color)
                }
                HeartLine(role: .secondary)
                Spacer(minLength: 0)
                MetricBlock(value: watchClock(tracker.bandSeconds), label: "In range", role: .tertiary)
            }
        }
    }

    /// In words as well as colour.
    private func status(_ state: CardioZoneTracker.BandState) -> (text: String, color: Color)? {
        switch state {
        case .off: nil
        case .settling: ("Settling in", .secondary)
        case .inBand: ("In range", WatchPalette.recovery)
        case .above: ("Ease off", WatchPalette.heart)
        case .below: ("Pick it up", WatchPalette.strain)
        }
    }
}

/// A vertical track with the band lit and heart rate as a marker. The scale
/// runs 25 bpm either side of the band (an open-topped band shows 40 above
/// its floor); app's choice, so a few beats move the marker visibly.
struct BandGauge: View {
    let band: HeartRateBand
    let bpm: Double?
    @Environment(\.isLuminanceReduced) private var reduced

    var body: some View {
        let top = band.upper >= HeartRateBand.noUpperLimit ? band.lower + 40 : band.upper
        let low = band.lower - 25
        let high = top + 25
        GeometryReader { proxy in
            let height = proxy.size.height
            let y: (Double) -> CGFloat = { value in
                height * CGFloat(1 - min(1, max(0, (value - low) / max(1, high - low))))
            }
            ZStack(alignment: .top) {
                Capsule()
                    .fill(WatchPalette.track)
                    .frame(width: 10)
                    .frame(maxWidth: .infinity)
                Capsule()
                    .fill(WatchPalette.recovery.opacity(reduced ? 0.5 : 0.9))
                    .frame(width: 10, height: max(4, y(band.lower) - y(top)))
                    .offset(y: y(top))
                    .frame(maxWidth: .infinity)
                if let bpm {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                        .offset(y: y(bpm) - 10)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A split, lap or auto-pause message over the metric pages. Shown for 3 s
/// (`WatchCardioModel.bannerSeconds`); in Always On it stays until the wrist
/// is raised, so a split that arrives with the wrist down is still there.
struct CardioBannerView: View {
    @Environment(WatchCardioModel.self) private var cardio
    @Environment(\.isLuminanceReduced) private var reduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: CardioBanner?

    var body: some View {
        Group {
            if let shown {
                Text(shown.text)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(reduced ? WatchPalette.strain : WatchPalette.onTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if reduced {
                            RoundedRectangle(cornerRadius: 14).strokeBorder(WatchPalette.strain, lineWidth: 2)
                                .background(.black, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            RoundedRectangle(cornerRadius: 14).fill(WatchPalette.strain)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
                    .onTapGesture { dismiss() }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: shown)
        .onChange(of: cardio.banner, initial: true) {
            if let banner = cardio.banner {
                shown = banner
                AccessibilityNotification.Announcement(banner.text).post()
            } else if !reduced {
                shown = nil
            }
        }
        .onChange(of: reduced) {
            if !reduced, cardio.banner == nil, let shown,
               Date.now.timeIntervalSince(shown.at) >= WatchCardioModel.bannerSeconds {
                self.shown = nil
            }
        }
    }

    private func dismiss() {
        shown = nil
        cardio.clearBanner()
    }
}
