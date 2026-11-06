import SwiftUI
import AppCore

/// The extra Health monitor tiles on Today, beyond the four signals that
/// are always shown (resting heart rate, HRV, breathing rate, sleep). They
/// are drawn from `VitalsModel`'s stats so the number, status and gauge are
/// the same ones Health shows, and only stats with a value today appear:
/// a tile that would say "No data" is skipped rather than filling a slot.
/// The user asked for more than the ux-audit.md 4.6 default of four, so the
/// card shows eight when expanded and remembers "Show less" (see
/// `HealthMonitor`).
enum HealthMonitorTiles {
    /// Stat ids in the order they fill the extra slots. Where two ids share
    /// a slot (heart rate recovery, else walking heart rate) the first with
    /// data wins. Ids are the `id:` strings in `VitalsModel` and its
    /// extensions (`VitalsModel+Breathing.swift` for "breathingDisturbances").
    static let priority: [[String]] = [
        ["temperature"],              // sleeping wrist temperature vs your usual
        ["spo2"],                     // blood oxygen
        // Steps left out: a goal, not a sign that something is off today
        // (it lives on Health › Activity and in Up next).
        ["hrr", "walkingHR"],         // heart rate recovery, else walking heart rate
        ["daylight"],                 // time in daylight (Apple Watch)
        ["breathingDisturbances"],    // nightly breathing disturbances (Builder B)
        ["hearing"],                  // headphone sound vs the WHO/ITU weekly budget
    ]

    /// Tiles shown in the collapsed card (the four fixed ones).
    static let collapsedCount = 4
    /// Tiles shown when expanded, fixed ones included.
    static let expandedCount = 8

    /// Stat ids whose "caution" tone counts towards the header verdict
    /// ("2 to watch"): the ones with a normal range or a personal baseline
    /// that marks today as off. Steps, daylight, heart rate recovery and
    /// headphone sound are goals or long-term fitness, not signs that
    /// something is off today, so they never count.
    /// - temperature: |delta vs your usual| >= 0.5 °C (`VitalsModel`, Smarr 2020)
    /// - spo2: below 95 % (`VitalsModel`, "Low"/"Very low")
    /// - breathingDisturbances: the last 7 nights well above your 30-night
    ///   usual (`IllnessWatch.breathingDisturbancesRising`)
    static let flaggedIDs: Set<String> = ["temperature", "spo2", "breathingDisturbances"]

    /// The stats with a value, in priority order, at most `limit`.
    static func extras(from vitals: VitalsModel, limit: Int) -> [VitalsModel.Stat] {
        guard limit > 0 else { return [] }
        var result: [VitalsModel.Stat] = []
        for slot in priority {
            guard result.count < limit else { break }
            if let stat = slot.lazy.compactMap({ vitals.stat($0) }).first(where: { $0.value != nil }) {
                result.append(stat)
            }
        }
        return result
    }

    /// How many of the extra tiles are outside their normal today.
    static func flagCount(_ stats: [VitalsModel.Stat]) -> Int {
        stats.filter { flaggedIDs.contains($0.id) && $0.tone == .caution }.count
    }
}

/// A `MetricTile` built from a `VitalsModel.Stat`, with its status as the
/// pill. The gauge follows the tone, so a "Good" pill never sits on a red
/// gauge: green for good (and "Normal", as on the fixed tiles), amber for
/// caution, the stat's category colours otherwise. "°C vs usual" moves
/// into the title so the unit stays on one line.
struct HealthMonitorStatTile: View {
    let stat: VitalsModel.Stat

    private var toneColors: [Color] {
        if stat.tone == .good || stat.status == "Normal" { return [Theme.recoveryHighLight, Theme.recoveryHigh] }
        if stat.tone == .caution { return [Theme.recoveryModerateLight, Theme.recoveryModerate] }
        return VitalTile.colors(for: stat.category)
    }

    var body: some View {
        let colors = toneColors
        let vsUsual = stat.unit.hasSuffix(" vs usual")
        MetricTile(
            title: vsUsual ? "Temperature vs usual" : stat.title,
            value: stat.value,
            unit: vsUsual ? String(stat.unit.dropLast(" vs usual".count)) : stat.unit,
            status: stat.status.map { text in
                MetricTile.Status(text: text, color: text == "Normal" ? Theme.recoveryHigh : VitalTile.color(for: stat.tone))
            },
            gauge: stat.gauge,
            color: colors.last ?? Theme.oxygen,
            lightColor: colors.first
        )
    }
}

/// "Show more" / "Show less" under the Health monitor grid.
struct HealthMonitorToggle: View {
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            HStack(spacing: 3) {
                Text(expanded ? "Show less" : "Show more")
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Shows four measures" : "Shows up to eight measures")
    }
}
