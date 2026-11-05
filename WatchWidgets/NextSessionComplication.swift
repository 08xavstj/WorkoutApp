import SwiftUI
import WidgetKit

/// The next planned session from the weekly plan: "Push 6 PM" today, "Rest
/// day" when nothing is planned today, and the next one ("Tue Pull") once
/// today's is done or its time has passed.
struct NextSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSession", provider: FaceProvider(kind: .nextSession)) { entry in
            NextSessionView(entry: entry)
                .containerBackground(for: .widget) { }
                .widgetURL(URL(string: "tensile://start"))
        }
        .configurationDisplayName("Next session")
        .description("Your next planned gym session from your weekly plan.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryInline])
    }
}

struct NextSessionView: View {
    let entry: FaceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// What each slot shows.
    private struct Display {
        var symbol: String
        /// Under the symbol in the circular slot: "6 PM", "Tue", "Rest".
        var short: String
        /// Curved corner label: "Push 6 PM", "Tue Pull", "Rest day".
        var label: String
        /// One line: "Push · 6:00 PM".
        var inline: String
    }

    private var display: Display {
        guard let data = entry.data else {
            return Display(symbol: "calendar", short: "Plan", label: "Plan on iPhone", inline: "Plan your week on iPhone")
        }
        switch data.upcoming(at: entry.date, doneAt: entry.doneAt) {
        case .today(let slot):
            let symbol = slot.symbol ?? "dumbbell.fill"
            let time = Self.compactTime(slot.start)
            return Display(symbol: symbol, short: time, label: "\(slot.shortTitle) \(time)",
                           inline: "\(slot.shortTitle) · \(Self.clock(slot.start))")
        case .later(let slot):
            let symbol = slot.symbol ?? "dumbbell.fill"
            let day = Self.weekday(slot.start)
            return Display(symbol: symbol, short: day, label: "\(day) \(slot.shortTitle)",
                           inline: "\(day) \(slot.shortTitle) · \(Self.clock(slot.start))")
        case .rest(let next):
            let inline = next.map { "Rest day · next \(Self.weekday($0.start)) \($0.shortTitle)" } ?? "Rest day"
            return Display(symbol: "moon.zzz.fill", short: "Rest", label: "Rest day", inline: inline)
        case .noPlan:
            return Display(symbol: "calendar", short: "Plan", label: "No plan", inline: "No sessions planned")
        }
    }

    private var symbolColor: Color {
        renderingMode == .fullColor ? FacePalette.lifting : Color.primary
    }

    var body: some View {
        let shown = display
        switch family {
        case .accessoryInline:
            Label(shown.inline, systemImage: shown.symbol)
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: shown.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .widgetAccentable()
                Text(shown.short)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.inline)
        default:
            Image(systemName: shown.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(symbolColor)
                .widgetAccentable()
                .widgetLabel {
                    Text(shown.label)
                }
                .accessibilityLabel(shown.inline)
        }
    }

    /// "6 PM", or "6:30 PM" when not on the hour (the user's locale).
    private static func compactTime(_ date: Date) -> String {
        let minute = Calendar.current.component(.minute, from: date)
        return minute == 0
            ? date.formatted(.dateTime.hour())
            : date.formatted(.dateTime.hour().minute())
    }

    /// "6:00 PM".
    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Tue".
    private static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}
