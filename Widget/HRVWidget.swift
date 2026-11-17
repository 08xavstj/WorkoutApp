import AppCore
import SwiftUI
import WidgetKit

nonisolated struct HRVEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

nonisolated struct HRVProvider: TimelineProvider {
    func placeholder(in context: Context) -> HRVEntry {
        HRVEntry(date: .now, snapshot: WidgetSnapshot(updated: .now, hrv: 58, hrvDate: .now, recovery: 72, strain: 34, hrvTrend: "within"))
    }

    func getSnapshot(in context: Context, completion: @escaping (HRVEntry) -> Void) {
        completion(HRVEntry(date: .now, snapshot: WidgetSnapshot.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HRVEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load()
        // Strain goes "--" once it's old (`GlanceFreshness`, as in the Scores widget), every score at midnight.
        let dates = [now] + GlanceFreshness.changeDates(updated: snapshot?.updated, after: now)
        let entries = dates.map { HRVEntry(date: $0, snapshot: snapshot) }
        // Redraw after midnight so "today's HRV" resets; the app also reloads it on every sync.
        let tomorrow = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }
}

// Today's recovery and the 7-day HRV trend. Not one night's HRV: a single
// night is mostly noise, and the 7-day rolling HRV against your normal range
// is what guided training in the trials (Plews et al., Eur J Appl Physiol
// 2012; Javaloyes et al., IJSPP 2019; docs/research/evidence-audit-2026-11.md,
// widgets). The kind keeps its old name so widgets already placed stay.
struct HRVWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HRVWidget", provider: HRVProvider()) { entry in
            HRVWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [WidgetPalette.peach.opacity(0.55), .white, WidgetPalette.sky.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .widgetURL(URL(string: "workoutapp://hrv"))
        }
        .configurationDisplayName("Recovery & HRV trend")
        .description("Today's recovery and your 7-day HRV against your normal range. Tap to add your HRV.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct HRVWidgetView: View {
    let entry: HRVEntry
    @Environment(\.widgetFamily) private var family

    /// The saved scores, only if the app updated them today. Yesterday's
    /// strain and recovery would otherwise show as today's after midnight.
    private var today: WidgetSnapshot? {
        guard let snapshot = entry.snapshot, Calendar.current.isDate(snapshot.updated, inSameDayAs: entry.date) else { return nil }
        return snapshot
    }

    /// Whether last night's HRV is in (only for the button's "Add" or "Edit"; the value isn't shown).
    private var hasHRVToday: Bool {
        guard let snapshot = entry.snapshot, snapshot.hrvIsFromToday else { return false }
        return snapshot.hrv != nil
    }

    private var recoveryText: String {
        guard let recovery = today?.recovery else { return "--" }
        return "\(recovery)%"
    }

    /// "7-day HRV: in range", or nil before today's recovery (or while the range is building).
    private var trendText: String? {
        switch today?.hrvTrend ?? "" {
        case "below": "7-day HRV: below range"
        case "within": "7-day HRV: in range"
        case "above": "7-day HRV: above range"
        default: nil
        }
    }

    /// Ask for a reading only from people who log HRV in the app; for a
    /// watch that writes HRV to Apple Health it's simply not synced yet.
    private var asksForHRV: Bool {
        entry.snapshot?.logsHRV ?? true
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recovery", systemImage: "heart.circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.green)
            Spacer(minLength: 0)
            Text(recoveryText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(today?.recovery == nil ? WidgetPalette.secondary : WidgetPalette.recovery(today?.recovery))
            if let trendText {
                Text(trendText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(2)
            }
            if asksForHRV, !hasHRVToday {
                addButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(WidgetPalette.secondary.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(today?.recovery ?? 0) / 100)
                    .stroke(AngularGradient(colors: [WidgetPalette.lime, WidgetPalette.recovery(today?.recovery)], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(recoveryText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.ink)
                    Text("Recovery").font(.caption2).foregroundStyle(WidgetPalette.secondary)
                }
            }
            .padding(5)
            VStack(alignment: .leading, spacing: 6) {
                Text(trendText ?? "7-day HRV: --")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.ink)
                if let strain = today?.strain, let updated = today?.updated,
                   GlanceFreshness.strainIsCurrent(updated: updated, at: entry.date) {
                    Text("Strain \(Int(strain.rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WidgetPalette.orange)
                }
                if asksForHRV || hasHRVToday {
                    Link(destination: URL(string: "workoutapp://hrv")!) {
                        addButton
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var addButton: some View {
        Label(hasHRVToday ? "Edit HRV" : "Add HRV", systemImage: "plus")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [WidgetPalette.green, WidgetPalette.indigo], startPoint: .leading, endPoint: .trailing), in: .capsule)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: !hasHRVToday && asksForHRV ? "plus" : "heart.circle")
                    .font(.caption.weight(.bold))
                Text(today?.recovery.map { "\($0)" } ?? "--")
                    .font(.system(.headline, design: .rounded))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Recovery \(recoveryText)", systemImage: "heart.circle").font(.headline)
            if let trendText {
                Text(trendText).font(.caption)
            } else if asksForHRV, !hasHRVToday {
                Text("Tap to log last night's HRV").font(.caption)
            } else {
                Text("7-day HRV: --").font(.caption)
            }
        }
    }
}
