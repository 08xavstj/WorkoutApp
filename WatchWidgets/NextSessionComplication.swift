import SwiftUI
import WidgetKit

/// Today's plan on the watch face and in the Smart Stack, worded exactly as
/// the iPhone's Plan widget (`PlanGlance`, compiled into this target): the
/// session and its time, "Rest day", after training tonight's bed-by window,
/// and "--" when what the phone sent is too old to trust. The kind stays
/// "NextSession" so faces that already carry it keep it.
struct NextSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSession", provider: FaceProvider(kind: .nextSession)) { entry in
            NextSessionView(entry: entry)
                .containerBackground(for: .widget) { }
                .widgetURL(URL(string: "tensile://start"))
        }
        .configurationDisplayName("Today's plan")
        .description("Today's session and its time, a rest day, or tonight's bed-by time once you've trained.")
        .supportedFamilies([.accessoryRectangular, .accessoryCorner, .accessoryCircular, .accessoryInline])
    }
}

struct NextSessionView: View {
    let entry: FaceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var plan: PlanGlance.Plan? { entry.data?.plan }

    private var state: PlanGlance.State {
        PlanGlance.state(of: plan, at: entry.date, alsoDoneAt: entry.doneAt)
    }

    private var symbolColor: Color {
        guard renderingMode == .fullColor else { return .primary }
        switch state {
        case .bedBy: return WatchPalette.sleep
        case .done: return WatchPalette.recovered
        case .session, .next: return WatchPalette.lifting
        case .rest, .noPlan, .stale: return .secondary
        }
    }

    var body: some View {
        let lines = PlanGlance.lines(for: state, at: entry.date, onWatch: true)
        let week = PlanGlance.week(of: plan, at: entry.date, alsoDoneAt: entry.doneAt)
        Group {
            switch family {
            case .accessoryInline:
                Label(lines.inline, systemImage: lines.symbol)
            case .accessoryCircular:
                circular(lines)
            case .accessoryRectangular:
                rectangular(lines, week: week)
            default:
                corner(lines)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(lines, week: week))
    }

    /// What VoiceOver reads: the state, then the week's count when it's known.
    static func spoken(_ lines: PlanGlance.Lines, week: PlanGlance.Week?) -> String {
        guard let week else { return lines.spoken }
        return "\(lines.spoken) \(week.done) of \(week.planned) sessions done this week."
    }

    private func circular(_ lines: PlanGlance.Lines) -> some View {
        VStack(spacing: 1) {
            Image(systemName: lines.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(symbolColor)
                .widgetAccentable()
            Text(lines.short)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(4)
    }

    private func corner(_ lines: PlanGlance.Lines) -> some View {
        Image(systemName: lines.symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(symbolColor)
            .widgetAccentable()
            .widgetLabel {
                Text(lines.brief)
            }
    }

    /// Eyebrow with the week's count, the title, and the detail line.
    private func rectangular(_ lines: PlanGlance.Lines, week: PlanGlance.Week?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Label(lines.eyebrow, systemImage: lines.symbol)
                    .foregroundStyle(symbolColor)
                    .widgetAccentable()
                Spacer(minLength: 2)
                if let week {
                    Text("\(week.done)/\(week.planned)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote.weight(.semibold))
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
#Preview("Plan, rectangular", as: .accessoryRectangular) {
    NextSessionComplication()
} timeline: {
    FaceEntry(date: .now, data: WatchFaceData.sample(), doneAt: nil)
    FaceEntry(date: .now, data: nil, doneAt: nil)
}
#endif
