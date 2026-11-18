import SwiftUI
import WidgetKit

/// Recovery in the middle, today's strain as the ring around it, with
/// today's strain target marked as an arc outside the ring. Made for a
/// circular subdial (e.g. Wayfinder's bottom right). A corner shows recovery
/// as a segmented ring with strain as its curved label; the rectangular slot
/// gets the same numbers in words.
struct RecoveryStrainComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecoveryStrain", provider: FaceProvider(kind: .recoveryStrain)) { entry in
            RecoveryStrainView(entry: entry)
                .containerBackground(for: .widget) { }
                .widgetURL(URL(string: "tensile://start"))
        }
        .configurationDisplayName("Recovery & strain")
        .description("Today's recovery, with strain filling the ring toward today's target.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

struct RecoveryStrainView: View {
    let entry: FaceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Today's numbers only: yesterday's would read as today's after midnight.
    private var data: WatchFaceData? {
        guard let data = entry.data, data.scoresAreCurrent(at: entry.date) else { return nil }
        return data
    }

    /// Strain only while it's current: it rises through the day, so an old
    /// value reads low (`GlanceFreshness.strainMaxAge`, the iPhone widgets' rule).
    private var strain: Double? {
        guard let data, GlanceFreshness.strainIsCurrent(updated: data.updated, at: entry.date) else { return nil }
        return data.strain.flatMap { $0.isFinite ? $0 : nil }
    }

    private var fullColor: Bool { renderingMode == .fullColor }

    private var recoveryColor: Color {
        fullColor ? WatchPalette.band(data?.band) : Color.primary
    }

    private var strainColor: Color {
        fullColor ? WatchPalette.strain : Color.primary
    }

    private var recoveryNumber: String {
        guard let recovery = data?.recovery else { return "--" }
        return "\(recovery)"
    }

    private var recoveryPercent: String {
        guard let recovery = data?.recovery else { return "--" }
        return "\(recovery)%"
    }

    private var strainPercent: String {
        guard let strain else { return "--" }
        return facePercent(strain)
    }

    /// "Normal", "Calibrating", or "Easy day" on an HRV-guided easy day.
    private var bandText: String? {
        guard let data, data.recovery != nil else { return nil }
        if data.calibrating { return "Calibrating" }
        if data.easyDay { return "Easy day" }
        return data.bandLabel
    }

    private var accessibilityText: String {
        var parts = ["Recovery \(recoveryPercent)"]
        if let bandText { parts.append(bandText) }
        parts.append("Strain \(strainPercent)")
        if let target = data?.target { parts.append("target \(faceRange(target))") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner: corner
            case .accessoryRectangular: rectangular
            default: circular
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Circular (the subdial)

    private var circular: some View {
        ZStack {
            StrainRing(strain: strain, target: data?.target, color: strainColor)
            VStack(spacing: -2) {
                Text(recoveryNumber)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(recoveryColor)
                Text("REC")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 9)
        }
    }

    // MARK: Corner

    /// Recovery as a ring of ten segments with the number inside, and
    /// strain as the curved label along the edge ("STRAIN 5%"). watchOS
    /// centres the circle over the label, so the two line up in any corner.
    /// Segments, not a smooth fill: recovery is read in bands, and a lit
    /// segment count reads at a glance where a thin arc doesn't (HIG,
    /// Complications: the segmented gauge style is for app-defined ranges).
    private var corner: some View {
        ZStack {
            SegmentedRing(fraction: data?.recovery.map { Double($0) / 100 }, color: recoveryColor)
            Text(recoveryNumber)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 7)
        }
        .widgetLabel {
            Text("STRAIN \(strainPercent)")
                .foregroundStyle(strainColor)
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("Recovery")
                Text(recoveryPercent)
                    .foregroundStyle(recoveryColor)
                    .widgetAccentable()
                if let bandText {
                    Text("· \(bandText)")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Text("Strain")
                Text(strainPercent)
                    .foregroundStyle(strainColor)
                    .widgetAccentable()
                if let target = data?.target {
                    Text("of \(faceRange(target))")
                        .foregroundStyle(.secondary)
                }
            }
            StrainBar(strain: strain, target: data?.target, color: strainColor)
                .frame(height: 6)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// `SegmentedRing`, `StrainRing` and `StrainBar` live in Shared/WatchGauges.swift,
// which the Watch app's Home glance draws too.
