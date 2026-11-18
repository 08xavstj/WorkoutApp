import SwiftUI
import AppCore

/// Today's one jet-lag card, after a time-zone shift of 5 hours or more
/// (`TravelShift.jetLagCard`; docs/research/next-features-2026-11.md, I3):
/// how the app's times move onto local time, melatonin near the local
/// bedtime (Herxheimer & Petrie, Cochrane 2002) with its safety lines, and
/// when to seek and avoid light (Roach & Sargent 2019; weak to moderate).
/// "Got it" hides it for this trip; the times keep moving either way.
struct TravelZoneCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @State private var store = TravelZoneStore.shared

    var body: some View {
        if let change = store.jetLagCard() {
            content(change)
        }
    }

    private func content(_ change: TravelShift.Change) -> some View {
        let calendar = Calendar.current
        let remaining = change.remainingHours(on: .now, calendar: calendar)
        let extra = store.demoExtraMinutes
        let onLocal = calendar.date(byAdding: .day, value: 1, to: change.lastShiftDay(calendar: calendar)) ?? .now
        return VStack(alignment: .leading, spacing: 10) {
            Label("Jet lag: \(hoursText(abs(change.hours))) \(change.isEastward ? "east" : "west")", systemImage: "airplane")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Your body clock is still about \(hoursText(abs(remaining))) \(change.isEastward ? "behind" : "ahead of") local time. Bed-by, the caffeine cut-off and dose reminders move onto local time about \(change.isEastward ? "an hour a day after flying east" : "an hour and a half a day after flying west"), and are there from \(onLocal.formatted(.dateTime.weekday(.wide))). Dose reminders move only between 7 am and 10 pm; otherwise they stay at their set local time.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(TravelShift.doseTimingAdvice)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let tonight = tonightText(extra: extra) {
                Text(tonight)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("Melatonin · moderate evidence", lines: TravelShift.melatoninLines)
            Label {
                Text(TravelShift.melatoninSafety)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(Theme.recoveryModerate)
            }
            light(change, extra: extra)
            Text("Need to be on local time sooner? Go to bed at the local time you're aiming for and use melatonin and light as above; the times in the app follow your body clock instead.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            EvidenceDisclosure(points: [
                "Melatonin: Herxheimer & Petrie, Cochrane Database Syst Rev 2002 (10 trials). Small trials; occasional short-term use appeared safe.",
                "Light: Roach & Sargent, Front Physiol 2019, a review built mostly on lab studies and models; light timing hasn't been tested in field trials, so treat it as weak to moderate.",
                "The pace of an hour a day east and an hour and a half west is the app's choice from the usual description of how fast the body clock adjusts; it wasn't checked at a source.",
            ])
            Button("Got it") { store.dismissCard() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(Theme.sleep)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
        .accessibilityIdentifier("travel-card")
    }

    /// Today's moved times, as the rest of the app shows them: "Today: in
    /// bed by 02:10–02:40, coffee by 17:20."
    private func tonightText(extra: Int) -> String? {
        var parts: [String] = []
        if let window = metrics.bedtimeWindow, !window.isSleepWindow {
            let start = window.start.addingTimeInterval(TimeInterval(extra * 60))
            let end = window.end.addingTimeInterval(TimeInterval(extra * 60))
            parts.append("in bed by \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
        }
        if !metrics.recentBedtimes.isEmpty {
            let bedtime = CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes) + extra
            parts.append("coffee by \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 100)))")
        }
        return parts.isEmpty ? nil : "Today: " + parts.joined(separator: ", ") + "."
    }

    @ViewBuilder
    private func light(_ change: TravelShift.Change, extra: Int) -> some View {
        let wakes = store.habitualNights(metrics.sleepNights).suffix(14).map(\.wake)
        if let wake = BedtimeWindow.usualWakeMinutes(wakes) {
            let advice = TravelShift.lightAdvice(isEastward: change.isEastward, shiftedWakeMinutes: wake + extra)
            section("Light · weak to moderate evidence", lines: [
                "Get daylight \(span(advice.seekStart, advice.seekEnd)) and keep bright light low \(span(advice.avoidStart, advice.avoidEnd)) (indoors with lights dim, or dark glasses outside). Skip a window that falls while you're asleep.",
                change.isEastward
                    ? "After flying east, seeking sunlight all day can work against you: morning light can hold your body clock back."
                    : "After flying west, daylight later in the day helps your body clock move later.",
            ])
        }
    }

    private func section(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: title, color: Theme.sleep)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func span(_ start: Int, _ end: Int) -> String {
        "\(CaffeineTiming.clockText(start))–\(CaffeineTiming.clockText(end))"
    }

    /// "6 h", "5.5 h", "45 min".
    private func hoursText(_ hours: Double) -> String {
        if hours < 1 { return "\(Int((hours * 60).rounded())) min" }
        return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) h"
    }
}
