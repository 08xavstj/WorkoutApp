import AppCore
import SwiftUI
import WidgetKit

/// The Scores widget in every size.
struct ScoresWidgetView: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let shown = ScoresShown(entry.snapshot, at: entry.date)
        Group {
            switch family {
            case .accessoryInline:
                Label("Recovery \(shown.recoveryText) · Sleep \(shown.sleepText)", systemImage: "heart.fill")
            case .accessoryCircular:
                ScoresCircularView(shown: shown)
            case .accessoryRectangular:
                ScoresRectangularView(shown: shown)
            case .systemMedium:
                ScoresMediumView(shown: shown)
            default:
                ScoresSmallView(shown: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
    }
}

/// Home Screen small, and StandBy: the recovery ring, with sleep and strain under it.
struct ScoresSmallView: View {
    let shown: ScoresShown
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // Without its background (StandBy) the widget sits on black.
        let palette = GlancePalette(dark: colorScheme == .dark || !showsBackground)
        let fullColor = renderingMode == .fullColor
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                GlanceRing(fraction: shown.recovery.map { Double($0) / 100 }, colors: palette.recoveryRing(shown.band), track: palette.track, lineWidth: 7) {
                    Text(shown.recovery.map { "\($0)" } ?? "--")
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(fullColor ? AnyShapeStyle(palette.ink) : AnyShapeStyle(Color.primary))
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8)
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovery")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
                    if let band = shown.bandLabel {
                        Text(band)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(fullColor ? AnyShapeStyle(palette.recoveryText(shown.band)) : AnyShapeStyle(Color.primary))
                            .widgetAccentable()
                    }
                }
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ScoreFigure(title: "Sleep", value: shown.sleepText, color: palette.sleepText, palette: palette)
                Spacer(minLength: 0)
                ScoreFigure(title: "Strain", value: shown.strainText, color: palette.strainText, palette: palette)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A score as a small label over its number ("Sleep" / "81").
struct ScoreFigure: View {
    let title: String
    let value: String
    let color: Color
    let palette: GlancePalette
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let fullColor = renderingMode == .fullColor
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
            Text(value)
                .font(.headline.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(fullColor ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Home Screen medium: the three rings of the Today tab.
struct ScoresMediumView: View {
    let shown: ScoresShown
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        let palette = GlancePalette(dark: colorScheme == .dark || !showsBackground)
        HStack(alignment: .top, spacing: 12) {
            ScoreRingColumn(
                title: "Recovery", value: shown.recovery.map { "\($0)" } ?? "--", unit: shown.recovery == nil ? "" : "%",
                caption: shown.bandLabel, fraction: shown.recovery.map { Double($0) / 100 },
                colors: palette.recoveryRing(shown.band), palette: palette
            )
            ScoreRingColumn(
                title: "Strain", value: shown.strain.map { "\(Int($0.rounded()))" } ?? "--", unit: shown.strain == nil ? "" : "%",
                caption: shown.targetText.map { "Range \($0)" }, fraction: shown.strain.map { $0 / 100 },
                colors: palette.strainRing, palette: palette
            )
            ScoreRingColumn(
                title: "Sleep", value: shown.sleepText, unit: "",
                caption: nil, fraction: shown.sleep.map { Double($0) / 100 },
                colors: palette.sleepRing, palette: palette
            )
        }
    }
}

/// One ring with its name and a short caption under it.
struct ScoreRingColumn: View {
    let title: String
    let value: String
    let unit: String
    let caption: String?
    let fraction: Double?
    let colors: [Color]
    let palette: GlancePalette
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let fullColor = renderingMode == .fullColor
        VStack(spacing: 4) {
            GlanceRing(fraction: fraction, colors: colors, track: palette.track, lineWidth: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.ink) : AnyShapeStyle(Color.primary))
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: 76, maxHeight: 76)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.ink) : AnyShapeStyle(Color.primary))
            // The line is kept (blank) so the three names stay level.
            Text(caption ?? " ")
                .font(.caption2)
                .foregroundStyle(fullColor ? AnyShapeStyle(palette.secondary) : AnyShapeStyle(Color.secondary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }
}

/// Lock Screen, circular: recovery as a gauge.
struct ScoresCircularView: View {
    let shown: ScoresShown

    var body: some View {
        Gauge(value: Double(shown.recovery ?? 0), in: 0...100) {
            Image(systemName: "heart.fill")
        } currentValueLabel: {
            Text(shown.recovery.map { "\($0)" } ?? "--")
                .fontDesign(.rounded)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

/// Lock Screen, rectangular: recovery first, then sleep and strain.
struct ScoresRectangularView: View {
    let shown: ScoresShown

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(shown.recoveryLine)
                .font(.headline)
                .widgetAccentable()
            Text("Sleep \(shown.sleepText) · Strain \(shown.strainText)")
                .font(.subheadline)
            if let target = shown.targetText {
                Text("Strain range \(target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
