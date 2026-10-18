import SwiftUI
import WidgetKit

nonisolated struct HRVEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

nonisolated struct HRVProvider: TimelineProvider {
    func placeholder(in context: Context) -> HRVEntry {
        HRVEntry(date: .now, snapshot: WidgetSnapshot(updated: .now, hrv: 58, hrvDate: .now, recovery: 72, strain: 34))
    }

    func getSnapshot(in context: Context, completion: @escaping (HRVEntry) -> Void) {
        completion(HRVEntry(date: .now, snapshot: WidgetSnapshot.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HRVEntry>) -> Void) {
        let entry = HRVEntry(date: .now, snapshot: WidgetSnapshot.load())
        // Redraw after midnight so "today's HRV" resets; the app also reloads it on every sync.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(min(tomorrow, .now.addingTimeInterval(3 * 3600)))))
    }
}

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
        .configurationDisplayName("HRV & recovery")
        .description("Last night's HRV and today's recovery. Tap to add your HRV.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct HRVWidgetView: View {
    let entry: HRVEntry
    @Environment(\.widgetFamily) private var family

    private var hrvToday: Double? {
        guard let snapshot = entry.snapshot, snapshot.hrvIsFromToday else { return nil }
        return snapshot.hrv
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
            Label("HRV", systemImage: "waveform.path.ecg")
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.green)
            Spacer(minLength: 0)
            if let hrv = hrvToday {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(hrv.rounded()))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.ink)
                    Text("ms").font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.secondary)
                }
                if let recovery = entry.snapshot?.recovery {
                    Text("Recovery \(recovery)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.recovery(recovery))
                }
            } else {
                Text("Log last night's HRV")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.ink)
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
                    .trim(from: 0, to: Double(entry.snapshot?.recovery ?? 0) / 100)
                    .stroke(AngularGradient(colors: [WidgetPalette.lime, WidgetPalette.recovery(entry.snapshot?.recovery)], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(entry.snapshot?.recovery.map { "\($0)%" } ?? "--")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.ink)
                    Text("Recovery").font(.caption2).foregroundStyle(WidgetPalette.secondary)
                }
            }
            .padding(5)
            VStack(alignment: .leading, spacing: 6) {
                if let hrv = hrvToday {
                    Text("HRV \(Int(hrv.rounded())) ms")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.ink)
                } else {
                    Text("No HRV yet today")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.ink)
                }
                if let strain = entry.snapshot?.strain {
                    Text("Strain \(Int(strain.rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WidgetPalette.orange)
                }
                Link(destination: URL(string: "workoutapp://hrv")!) {
                    addButton
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var addButton: some View {
        Label(hrvToday == nil ? "Add HRV" : "Edit HRV", systemImage: "plus")
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
                Image(systemName: hrvToday == nil ? "plus" : "waveform.path.ecg")
                    .font(.caption.weight(.bold))
                Text(hrvToday.map { "\(Int($0.rounded()))" } ?? "HRV")
                    .font(.system(.headline, design: .rounded))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("HRV", systemImage: "waveform.path.ecg").font(.caption.weight(.bold))
            if let hrv = hrvToday {
                Text("\(Int(hrv.rounded())) ms · recovery \(entry.snapshot?.recovery.map { "\($0)%" } ?? "--")")
                    .font(.headline)
            } else {
                Text("Tap to log last night's HRV").font(.headline)
            }
        }
    }
}
