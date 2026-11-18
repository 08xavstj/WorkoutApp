import SwiftUI

enum WatchCardioPage: Hashable {
    case controls, live, zones
}

/// A cardio workout in progress: controls, the live page, time in zones
/// (the crown scrolls between them, as in a lifting workout).
struct WatchCardioPagesView: View {
    @State private var page: WatchCardioPage = .live

    var body: some View {
        TabView(selection: $page) {
            WatchCardioControlsView()
                .tag(WatchCardioPage.controls)
            WatchCardioLiveView()
                .tag(WatchCardioPage.live)
            WatchCardioZonesView()
                .tag(WatchCardioPage.zones)
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Heart rate large, the zone by number and color, the clock, the target,
/// distance with pace or speed where the activity has them, and calories.
struct WatchCardioLiveView: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                WatchCardioClockLine()
                heartRow
                if let band = cardio.tracker.band {
                    WatchCardioTargetLine(title: cardio.target.title, band: band, state: cardio.tracker.state)
                }
                metrics
            }
            .padding(.horizontal, 4)
        }
        // Pause stays on screen without scrolling; double tap presses it.
        .safeAreaInset(edge: .bottom, spacing: 4) {
            WatchCardioPauseButton(isPrimary: true)
                .padding(.horizontal, 4)
        }
    }

    private var heartRow: some View {
        let zone = cardio.tracker.currentZone
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(cardio.heartRate.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(cardio.heartRate == nil ? Color.secondary : WatchTheme.zoneColor(zone))
            Text("bpm")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if cardio.heartRate != nil {
                WatchZoneBadge(zone: zone)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenHeart)
    }

    private var spokenHeart: String {
        guard let heartRate = cardio.heartRate else { return "No heart rate yet" }
        let zone = cardio.tracker.currentZone.map { "zone \($0)" } ?? "below zone 1"
        return "\(Int(heartRate.rounded())) beats per minute, \(zone)"
    }

    @ViewBuilder
    private var metrics: some View {
        let miles = watchUsesMiles()
        if cardio.activity.movement != .stationary, let meters = cardio.distanceMeters {
            HStack {
                Text(CardioSummary.distanceText(meters: meters, miles: miles))
                Spacer(minLength: 4)
                if let pace = paceOrSpeed(meters: meters, miles: miles) {
                    Text(pace)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
        }
        Text(cardio.activeKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "– kcal")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// Average pace on foot, average speed on a bike or skis, over the workout so far.
    private func paceOrSpeed(meters: Double, miles: Bool) -> String? {
        let seconds = cardio.elapsed(at: .now) ?? 0
        switch cardio.activity.movement {
        case .onFoot:
            return CardioSummary.pace(seconds: seconds, meters: meters, miles: miles).map { CardioSummary.paceText($0, miles: miles) }
        case .cycling, .snow:
            return CardioSummary.speed(seconds: seconds, meters: meters, miles: miles).map { CardioSummary.speedText($0, miles: miles) }
        case .stationary:
            return nil
        }
    }
}

/// The workout clock (it stands still while paused) and the activity.
private struct WatchCardioClockLine: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        if let start = cardio.startedAt {
            TimelineView(.periodic(from: start, by: 1)) { context in
                HStack {
                    Text(workoutElapsedText(cardio.elapsed(at: context.date) ?? 0))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.strain)
                    Spacer()
                    if cardio.phase == .paused {
                        Text("Paused")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: cardio.activity.systemImage)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(cardio.activity.title)
                    }
                }
            }
        }
    }
}

/// "Zone 3" on the zone's color, or "Under Z1" in grey.
private struct WatchZoneBadge: View {
    let zone: Int?

    var body: some View {
        Text(zone.map { "Zone \($0)" } ?? "Under Z1")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(WatchTheme.zoneColor(zone), in: .capsule)
    }
}

/// "Easy 107–133" and where heart rate stands against it, in words as well as color.
private struct WatchCardioTargetLine: View {
    let title: String
    let band: HeartRateBand
    let state: CardioZoneTracker.BandState

    var body: some View {
        HStack(spacing: 4) {
            Text("\(title) \(band.text)")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let status {
                Text(status.text)
                    .foregroundStyle(status.color)
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var status: (text: String, color: Color)? {
        switch state {
        case .off, .settling: return nil
        case .inBand: return (text: "In range", color: WatchTheme.recovery)
        case .above: return (text: "Ease off", color: WatchTheme.heart)
        case .below: return (text: "Pick it up", color: WatchTheme.strain)
        }
    }
}

/// Pause while running, Resume while paused.
struct WatchCardioPauseButton: View {
    @Environment(WatchCardioModel.self) private var cardio
    /// The live page's button answers to double tap (Series 9 and later); the controls page's doesn't.
    var isPrimary = false

    var body: some View {
        if cardio.phase == .paused {
            Button {
                cardio.resume()
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.recovery)
            .handGestureShortcut(.primaryAction, isEnabled: isPrimary)
        } else {
            Button {
                cardio.pause()
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.strain)
            .handGestureShortcut(.primaryAction, isEnabled: isPrimary)
        }
    }
}

/// Time in each zone so far, with the zone's bpm range, and time in the target band.
struct WatchCardioZonesView: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        let tracker = cardio.tracker
        let longest = max(tracker.zoneSeconds.max() ?? 0, 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Time in zones")
                    .font(.headline)
                ForEach(Array(tracker.zoneSeconds.enumerated()), id: \.offset) { index, seconds in
                    WatchZoneTimeRow(
                        zone: index + 1,
                        range: tracker.scheme.rangeText(forZone: index + 1),
                        seconds: seconds,
                        share: seconds / longest,
                        isCurrent: tracker.currentZone == index + 1
                    )
                }
                if tracker.belowZoneSeconds >= 1 {
                    WatchCardioStatRow(label: "Under zone 1", value: watchClock(tracker.belowZoneSeconds))
                }
                if tracker.band != nil {
                    WatchCardioStatRow(label: "In \(cardio.target.title) range", value: watchClock(tracker.bandSeconds))
                }
                Text(cardio.zoneSource.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// "Z2 133–146        12:30" over a bar in the zone's color.
struct WatchZoneTimeRow: View {
    let zone: Int
    let range: String
    let seconds: Double
    /// 0-1 against the longest zone.
    let share: Double
    var isCurrent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Z\(zone)")
                    .fontWeight(.bold)
                    .foregroundStyle(WatchTheme.zoneColor(zone))
                Text(range)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(watchClock(seconds))
                    .fontWeight(isCurrent ? .bold : .regular)
            }
            .font(.caption)
            .monospacedDigit()
            ProgressView(value: min(1, max(0, share)))
                .tint(WatchTheme.zoneColor(zone))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(zone), \(range) beats per minute, \(Int((seconds / 60).rounded())) minutes")
    }
}

/// A label and its value on one line.
struct WatchCardioStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.footnote)
    }
}

/// Pause or resume, end (saves to Apple Health) and discard.
struct WatchCardioControlsView: View {
    @Environment(WatchCardioModel.self) private var cardio
    @State private var ending = false
    @State private var discarding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchCardioPauseButton()
                Button {
                    ending = true
                } label: {
                    Label("End", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.lifting)
                .accessibilityIdentifier("watch-cardio-end")
                Button(role: .destructive) {
                    discarding = true
                } label: {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text("\(cardio.activity.title) · saved to Apple Health when you end it")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .confirmationDialog("End this workout?", isPresented: $ending, titleVisibility: .visible) {
            Button("End and save") {
                Task { await cardio.end() }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { cardio.discard() }
        }
    }
}

/// After End: time, distance, heart rate and minutes in each zone.
struct WatchCardioEndView: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let summary = cardio.summary {
                    Text(summary.saved ? "\(summary.activity.title) saved" : "\(summary.activity.title) ended")
                        .font(.headline)
                    rows(for: summary)
                } else {
                    Text("Workout ended")
                        .font(.headline)
                }
                if let problem = cardio.problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.heart)
                }
                Button("Done") { cardio.reset() }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.recovery)
                    .handGestureShortcut(.primaryAction)
                    .padding(.top, 4)
                    .accessibilityIdentifier("watch-cardio-done")
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func rows(for summary: CardioSummary) -> some View {
        let miles = watchUsesMiles()
        let longest = max(summary.zoneSeconds.max() ?? 0, 1)
        WatchCardioStatRow(label: "Time", value: workoutElapsedText(summary.activeSeconds))
        if summary.activity.movement != .stationary, let meters = summary.distanceMeters {
            WatchCardioStatRow(label: "Distance", value: CardioSummary.distanceText(meters: meters, miles: miles))
            if let pace = summary.paceOrSpeedText(miles: miles) {
                WatchCardioStatRow(label: summary.activity.movement.showsSpeed ? "Avg speed" : "Avg pace", value: pace)
            }
        }
        WatchCardioStatRow(label: "Avg HR", value: bpm(summary.averageBpm))
        WatchCardioStatRow(label: "Max HR", value: bpm(summary.maximumBpm))
        WatchCardioStatRow(label: "Calories", value: summary.activeKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "–")
        if summary.measuredSeconds > 0 {
            Text("Time in zones")
                .font(.footnote.weight(.semibold))
                .padding(.top, 4)
            ForEach(Array(summary.zoneSeconds.enumerated()), id: \.offset) { index, seconds in
                WatchZoneTimeRow(
                    zone: index + 1,
                    range: cardio.tracker.scheme.rangeText(forZone: index + 1),
                    seconds: seconds,
                    share: seconds / longest
                )
            }
            if summary.belowZoneSeconds >= 1 {
                WatchCardioStatRow(label: "Under zone 1", value: watchClock(summary.belowZoneSeconds))
            }
            if let share = summary.bandShare {
                WatchCardioStatRow(
                    label: "In \(summary.target.title) range",
                    value: "\(watchClock(summary.bandSeconds)) · \(Int((share * 100).rounded()))%"
                )
            }
        }
    }

    private func bpm(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) bpm" } ?? "–"
    }
}
