import SwiftUI
import Charts

// MARK: - Rings

/// Gradient progress ring with a soft glow and a white inner disk.
struct GradientRing<Content: View>: View {
    /// 0...1
    let progress: Double
    let colors: [Color]
    var lineWidth: CGFloat = 12
    var showsDisk = true
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(1, max(0, progress))
        let gradient = AngularGradient(
            colors: colors,
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(max(1, 360 * clamped))
        )
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: lineWidth * 0.6)
                .opacity(0.45)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsDisk {
                Circle()
                    .fill(Theme.card)
                    .padding(lineWidth * 1.15)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
            }
            content
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.9), value: clamped)
    }
}

/// A score ring with a title and subtitle underneath (Today's top card).
struct ScoreRing: View {
    let title: String
    let value: String
    var unit: String = ""
    var subtitle: String?
    let progress: Double
    let colors: [Color]
    var size: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            GradientRing(progress: progress, colors: colors, lineWidth: size * 0.1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value)
                        .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: size * 0.13, weight: .semibold, design: .rounded))
                    }
                }
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, size * 0.16)
                .foregroundStyle(Theme.primaryText)
            }
            .frame(width: size, height: size)

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)\(unit)")
    }
}

// MARK: - Arc gauge (270°)

/// An arc from bottom-left round to bottom-right, as a fraction 0...1 of the sweep.
nonisolated struct GaugeArc: Shape {
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(135 + 270 * from),
            endAngle: .degrees(135 + 270 * max(from, to)),
            clockwise: false
        )
        return path
    }
}

/// 270° gauge with an optional target band drawn just outside the track.
struct ArcGauge<Content: View>: View {
    /// 0...1
    let value: Double
    var band: ClosedRange<Double>?
    let colors: [Color]
    var lineWidth: CGFloat = 16
    var bandColor: Color = Theme.recoveryHigh
    @ViewBuilder var content: Content

    var body: some View {
        let v = min(1, max(0, value))
        ZStack {
            GaugeArc(from: 0, to: 1)
                .stroke(Theme.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let band {
                GaugeArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(bandColor.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                GaugeArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(bandColor, style: StrokeStyle(lineWidth: max(3, lineWidth * 0.22), lineCap: .round))
                    .padding(-lineWidth * 0.95)
            }
            GaugeArc(from: 0, to: v)
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .blur(radius: lineWidth * 0.5)
                .opacity(0.4)
            GaugeArc(from: 0, to: v)
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // Knob: a short white arc segment with a coloured rim.
            GaugeArc(from: max(0, v - 0.0001), to: v)
                .stroke(colors.last ?? Theme.strain, style: StrokeStyle(lineWidth: lineWidth * 1.35, lineCap: .round))
            GaugeArc(from: max(0, v - 0.0001), to: v)
                .stroke(Theme.card, style: StrokeStyle(lineWidth: lineWidth * 0.75, lineCap: .round))
            content
        }
    }
}

// MARK: - Bars and gauges

/// Strain progress on 0-21 with the target band shaded (Today's strain goal card).
struct StrainGoalBar: View {
    let current: Double
    let target: ClosedRange<Double>
    var maximum: Double = 21

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (value: Double) in w * min(1, max(0, value / maximum)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 12)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.recoveryHigh.opacity(0.16))
                        .strokeBorder(Theme.recoveryHigh, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: max(8, x(target.upperBound) - x(target.lowerBound)), height: 22)
                        .offset(x: x(target.lowerBound))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.strainLight, Theme.strain], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, x(current)), height: 12)
                    Circle()
                        .fill(Theme.card)
                        .strokeBorder(Theme.strain, lineWidth: 4)
                        .frame(width: 26, height: 26)
                        .shadow(color: Theme.strain.opacity(0.35), radius: 6)
                        .offset(x: x(current) - 13)
                }
                .frame(height: 28)
            }
            .frame(height: 28)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    ForEach([0.0, 7.0], id: \.self) { tick in
                        Text("\(Int(tick))").offset(x: w * tick / maximum)
                    }
                    Text("\(Int(target.lowerBound))")
                        .foregroundStyle(Theme.recoveryHigh)
                        .offset(x: w * target.lowerBound / maximum - 6)
                    Text("\(Int(target.upperBound))")
                        .foregroundStyle(Theme.recoveryHigh)
                        .offset(x: w * target.upperBound / maximum - 6)
                    Text("\(Int(maximum))")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strain \(current.formatted(.number.precision(.fractionLength(1)))) of 21, target \(Int(target.lowerBound)) to \(Int(target.upperBound))")
    }
}

/// Small vertical gauge: a track, the normal range highlighted, and today's value.
struct VerticalRangeGauge: View {
    /// 0 (bottom) ... 1 (top)
    let value: Double?
    var normal: ClosedRange<Double> = 0.3...0.7
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color.opacity(0.35))
                    .frame(height: h * (normal.upperBound - normal.lowerBound))
                    .offset(y: -h * normal.lowerBound)
                if let value {
                    Circle()
                        .fill(Theme.card)
                        .strokeBorder(color, lineWidth: 3)
                        .frame(width: 16, height: 16)
                        .offset(y: -(h - 16) * min(1, max(0, value)))
                }
            }
        }
        .frame(width: 10)
        .accessibilityHidden(true)
    }
}

/// A thin horizontal bar split into colored segments (zones, sleep stages).
struct SegmentedBar: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        let visible = segments.filter { $0.value > 0 }
        let total = visible.map(\.value).reduce(0, +)
        Canvas { context, size in
            guard total > 0 else {
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2), with: .color(Theme.track))
                return
            }
            let gap: CGFloat = 2
            let usable = size.width - gap * CGFloat(max(0, visible.count - 1))
            var x: CGFloat = 0
            for segment in visible {
                let width = max(2, usable * segment.value / total)
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: size.height / 2), with: .color(segment.color))
                x += width + gap
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Horizontal progress bar with a value and optional goal.
struct ProgressRow: View {
    let label: String
    let value: Double
    var goal: Double?
    var unit: String = "g"
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(LocalizedStringKey(goal.map { "**\(Int(value))** / \(Int($0)) \(unit)" } ?? "**\(Int(value))** \(unit)"))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1, value / max(goal ?? value * 1.4, 1)))
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: - Small pieces

/// Small label + value pair used inside cards.
struct StatView: View {
    let label: String
    let value: String
    var detail: String?
    var color: Color = Theme.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rounded pill label, e.g. "2.6 to go" or "Optimal".
struct Chip: View {
    let text: String
    var color: Color = Theme.strain
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? color : color.opacity(0.13), in: .capsule)
    }
}

/// Coloured rounded-square icon used in list rows.
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Uppercase small caption used as a card header.
struct CardLabel: View {
    let text: String
    var color: Color = Theme.secondaryText

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Large section title between cards.
struct SectionTitle: View {
    let text: String
    var trailing: String?
    var trailingColor: Color = Theme.secondaryText

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trailingColor)
            }
        }
        .padding(.top, 8)
    }
}

/// Mini trend line for biomarker rows.
struct Sparkline: View {
    let values: [DatedValue]
    let color: Color
    var showsArea = false

    var body: some View {
        Chart {
            ForEach(values) { point in
                if showsArea {
                    AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let last = values.last {
                PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                    .symbol {
                        Circle()
                            .fill(Theme.card)
                            .strokeBorder(color, lineWidth: 2.5)
                            .frame(width: 11, height: 11)
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}
