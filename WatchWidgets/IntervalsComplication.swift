import SwiftUI
import WidgetKit

/// This week's hard cardio session in the Smart Stack and on the face: its
/// day, "Intervals today" on that day, "Not today" when the app says it waits,
/// and "Done this week" once Apple Health has it (`IntervalGlance`, in
/// Packages/AppCore/Sources/AppCore/Glances.swift, compiled into this target).
/// The Smart Stack offers it on its planned day (`FaceProvider.relevance()`).
/// Tapping opens Tensile's Watch app, whose Home has the session's Start.
struct IntervalsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Intervals", provider: FaceProvider(kind: .intervals)) { entry in
            IntervalsView(entry: entry)
                .containerBackground(for: .widget) { }
                .widgetURL(URL(string: "tensile://start"))
        }
        .configurationDisplayName("Intervals")
        .description("This week's hard cardio session and its day. It comes up in the Smart Stack on that day.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct IntervalsView: View {
    let entry: FaceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var state: IntervalGlance.State {
        IntervalGlance.state(of: entry.data?.intervalSession, at: entry.date)
    }

    private var symbolColor: Color {
        guard renderingMode == .fullColor else { return .primary }
        switch state {
        case .today, .later, .anyDay: return WatchPalette.heart
        case .done: return WatchPalette.recovered
        case .waits: return WatchPalette.easy
        case .none: return .secondary
        }
    }

    var body: some View {
        let lines = IntervalGlance.lines(for: state)
        Group {
            switch family {
            case .accessoryInline:
                Label(lines.inline, systemImage: lines.symbol)
            default:
                rectangular(lines)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken)
    }

    private func rectangular(_ lines: IntervalGlance.Lines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(lines.eyebrow, systemImage: lines.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(symbolColor)
                .widgetAccentable()
            Text(lines.title)
                .font(.headline)
                .minimumScaleFactor(0.7)
            if let detail = lines.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Intervals, rectangular", as: .accessoryRectangular) {
    IntervalsComplication()
} timeline: {
    FaceEntry(date: .now, data: WatchFaceData.sample(), doneAt: nil)
    FaceEntry(date: .now, data: nil, doneAt: nil)
}
#endif
