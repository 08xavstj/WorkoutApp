import AppCore
import SwiftUI
import WidgetKit

/// The Plan widget in every size. The words come from `PlanGlance.lines`; a
/// tap opens the screen the state is about: Today for a session to start,
/// last night's sleep for the bed-by window, this week's plan otherwise.
struct PlanWidgetView: View {
    let entry: PlanEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let state = PlanGlance.state(of: entry.plan, at: entry.date)
        let lines = PlanGlance.lines(for: state, at: entry.date)
        let week = PlanGlance.week(of: entry.plan, at: entry.date)
        Group {
            switch family {
            case .accessoryInline:
                Label(lines.inline, systemImage: lines.symbol)
            case .accessoryCircular:
                PlanCircularView(lines: lines)
            case .accessoryRectangular:
                PlanRectangularView(lines: lines)
            case .systemMedium:
                PlanMediumView(lines: lines, week: week, tone: PlanTone(state))
            default:
                PlanSmallView(lines: lines, week: week, tone: PlanTone(state))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(lines, week: week))
        .widgetURL(Self.link(for: state))
    }

    /// What VoiceOver reads: the state, then the week's count when it's shown.
    static func spoken(_ lines: PlanGlance.Lines, week: PlanGlance.Week?) -> String {
        guard let week else { return lines.spoken }
        return "\(lines.spoken) \(week.done) of \(week.planned) sessions done this week."
    }

    static func link(for state: PlanGlance.State) -> URL? {
        switch state {
        case .session, .done, .stale: URL(string: "workoutapp://today")
        case .bedBy: URL(string: "workoutapp://sleep")
        case .rest, .next, .noPlan: URL(string: "workoutapp://plan")
        }
    }
}

/// Which accent a state takes on the Home Screen: lifting pink for a
/// session, sleep indigo for the bed-by window, green once today is done,
/// grey for everything that is only information.
nonisolated enum PlanTone {
    case lifting, sleep, done, neutral

    init(_ state: PlanGlance.State) {
        switch state {
        case .session, .next: self = .lifting
        case .bedBy: self = .sleep
        case .done: self = .done
        case .rest, .noPlan, .stale: self = .neutral
        }
    }

    func color(in palette: GlancePalette) -> Color {
        switch self {
        case .lifting: palette.liftingText
        case .sleep: palette.sleepText
        case .done: palette.doneText
        case .neutral: palette.secondary
        }
    }
}

/// Eyebrow, title and detail: the block the small and medium sizes share.
struct PlanHeadline: View {
    let lines: PlanGlance.Lines
    let tone: PlanTone
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // Without its background (StandBy) the widget sits on black.
        let palette = GlancePalette(dark: colorScheme == .dark || !showsBackground)
        let fullColor = renderingMode == .fullColor
        VStack(alignment: .leading, spacing: 2) {
            Label(lines.eyebrow, systemImage: lines.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(fullColor ? AnyShapeStyle(tone.color(in: palette)) : AnyShapeStyle(Color.primary))
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 4)
            Text(lines.title)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.ink) : AnyShapeStyle(Color.primary))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let detail = lines.detail {
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Home Screen small, and StandBy.
struct PlanSmallView: View {
    let lines: PlanGlance.Lines
    let week: PlanGlance.Week?
    let tone: PlanTone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlanHeadline(lines: lines, tone: tone)
            // Room for the week's count only when there's no second line.
            if let week, lines.detail == nil {
                PlanWeekLine(week: week)
            }
        }
    }
}

/// Home Screen medium: the plan on the left, this week's sessions on the right.
struct PlanMediumView: View {
    let lines: PlanGlance.Lines
    let week: PlanGlance.Week?
    let tone: PlanTone

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PlanHeadline(lines: lines, tone: tone)
            if let week {
                PlanWeekColumn(week: week)
                    .frame(maxWidth: 120, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// "2 of 4 this week", one line.
struct PlanWeekLine: View {
    let week: PlanGlance.Week
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let palette = GlancePalette(dark: colorScheme == .dark || !showsBackground)
        Text("\(week.done) of \(week.planned) this week")
            .font(.caption.weight(.medium))
            .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// This week's sessions: the count and one bar per planned session.
struct PlanWeekColumn: View {
    let week: PlanGlance.Week
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let palette = GlancePalette(dark: colorScheme == .dark || !showsBackground)
        let fullColor = renderingMode == .fullColor
        VStack(alignment: .leading, spacing: 4) {
            Text("This week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
            Text("\(week.done) of \(week.planned)")
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.ink) : AnyShapeStyle(Color.primary))
            HStack(spacing: 3) {
                ForEach(0..<min(week.planned, 7), id: \.self) { index in
                    PlanWeekBar(filled: index < week.done, palette: palette, fullColor: fullColor)
                }
            }
            .frame(height: 6)
            Text(week.planned == 1 ? "session" : "sessions")
                .font(.caption)
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// One planned session in the week's row: filled once done. On a tinted Home
/// Screen the filled ones take the tint and the rest stay faint.
struct PlanWeekBar: View {
    let filled: Bool
    let palette: GlancePalette
    let fullColor: Bool

    var body: some View {
        if filled {
            Capsule()
                .fill(fullColor ? AnyShapeStyle(palette.liftingText) : AnyShapeStyle(Color.primary))
                .widgetAccentable()
        } else {
            Capsule()
                .fill(fullColor ? AnyShapeStyle(palette.track) : AnyShapeStyle(Color.primary.opacity(0.2)))
        }
    }
}

/// Lock Screen, rectangular: three short lines.
struct PlanRectangularView: View {
    let lines: PlanGlance.Lines

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(lines.eyebrow, systemImage: lines.symbol)
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(lines.title)
                .font(.headline)
                .minimumScaleFactor(0.7)
            if let detail = lines.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lock Screen, circular: the symbol over a time or a word.
struct PlanCircularView: View {
    let lines: PlanGlance.Lines

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: lines.symbol)
                    .font(.caption.weight(.bold))
                    .widgetAccentable()
                Text(lines.short)
                    .font(.caption.weight(.semibold))
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 5)
        }
    }
}
