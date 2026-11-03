import SwiftUI
import WidgetKit

/// Recovery in the middle, today's strain as the ring around it, with
/// today's strain target marked as an arc outside the ring. Made for a
/// circular subdial (e.g. Wayfinder's bottom right); corner and rectangular
/// slots get the same numbers.
struct RecoveryStrainComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecoveryStrain", provider: FaceProvider()) { entry in
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

    private var fullColor: Bool { renderingMode == .fullColor }

    private var recoveryColor: Color {
        fullColor ? FacePalette.band(data?.band) : Color.primary
    }

    private var strainColor: Color {
        fullColor ? FacePalette.strain : Color.primary
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
        guard let strain = data?.strain else { return "--" }
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
            StrainRing(strain: data?.strain, target: data?.target, color: strainColor)
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

    private var corner: some View {
        Text(recoveryPercent)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(recoveryColor)
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: faceFraction(data?.strain ?? 0)) {
                    Text("Strain")
                } currentValueLabel: {
                    Text(strainPercent)
                }
                .tint(strainColor)
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
            StrainBar(strain: data?.strain, target: data?.target, color: strainColor)
                .frame(height: 6)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Strain filling a ring 0-100, with today's target as a thin arc outside it.
struct StrainRing: View {
    let strain: Double?
    let target: ClosedRange<Double>?
    let color: Color

    private let width: CGFloat = 5

    var body: some View {
        ZStack {
            if let target {
                Circle()
                    .trim(from: faceFraction(target.lowerBound), to: faceFraction(target.upperBound))
                    .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
            }
            ZStack {
                Circle()
                    .stroke(FacePalette.track, lineWidth: width)
                if let strain, strain > 0 {
                    Circle()
                        .trim(from: 0, to: faceFraction(strain))
                        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                }
            }
            .padding(6.5)
        }
    }
}

/// Strain as a bar 0-100, with today's target outlined on it.
struct StrainBar: View {
    let strain: Double?
    let target: ClosedRange<Double>?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FacePalette.track)
                if let strain, strain > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(proxy.size.height, width * faceFraction(strain)))
                        .widgetAccentable()
                }
                if let target {
                    Capsule()
                        .stroke(color.opacity(0.8), lineWidth: 1)
                        .frame(width: max(proxy.size.height, width * (faceFraction(target.upperBound) - faceFraction(target.lowerBound))))
                        .offset(x: width * faceFraction(target.lowerBound))
                }
            }
        }
    }
}

