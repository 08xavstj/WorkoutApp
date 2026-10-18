import SwiftUI
import Charts

// MARK: - Rings

/// Thick gradient ring on a recessed track, with a glowing end cap and a
/// raised white disk in the middle.
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
        let end = colors.last ?? Theme.strain
        let gradient = AngularGradient(
            colors: colors,
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(max(1, 360 * clamped))
        )
        ZStack {
            // Recessed track.
            Circle()
                .stroke(Theme.track.shadow(.inner(color: Color.black.opacity(0.13), radius: lineWidth * 0.18, y: lineWidth * 0.1)), lineWidth: lineWidth)
            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: end.opacity(0.35), radius: lineWidth * 0.45)
                // Glowing end cap.
                GeometryReader { geo in
                    let radius = min(geo.size.width, geo.size.height) / 2
                    Circle()
                        .fill(end)
                        .overlay(Circle().fill(Color.white.opacity(0.55)).padding(lineWidth * 0.3))
                        .frame(width: lineWidth, height: lineWidth)
                        .shadow(color: end.opacity(0.6), radius: lineWidth * 0.35)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2 - radius)
                        .rotationEffect(.degrees(360 * clamped))
                }
            }
            if showsDisk {
                Circle()
                    .fill(LinearGradient(colors: [Theme.card, Theme.cardRaised.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .padding(lineWidth * 1.2)
                    .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
            }
            content
        }
        .padding(lineWidth / 2)
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

/// 270° gauge on a recessed track, with an optional target band just outside it.
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
        let end = colors.last ?? Theme.strain
        ZStack {
            GaugeArc(from: 0, to: 1)
                .stroke(Theme.track.shadow(.inner(color: Color.black.opacity(0.13), radius: lineWidth * 0.18, y: lineWidth * 0.1)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let band {
                GaugeArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(bandColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                GaugeArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(LinearGradient(colors: [Theme.recoveryHighLight, bandColor], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: max(4, lineWidth * 0.26), lineCap: .round))
                    .padding(-lineWidth * 0.95)
            }
            if v > 0 {
                GaugeArc(from: 0, to: v)
                    .stroke(LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: end.opacity(0.35), radius: lineWidth * 0.45)
            }
            // Knob: white centre with a coloured rim and glow.
            GaugeArc(from: max(0, v - 0.0001), to: v)
                .stroke(end, style: StrokeStyle(lineWidth: lineWidth * 1.35, lineCap: .round))
                .shadow(color: end.opacity(0.6), radius: 6)
            GaugeArc(from: max(0, v - 0.0001), to: v)
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round))
            content
        }
    }
}

/// Radial tick marks around a 270° dial, for tick fractions in `from...to`.
nonisolated struct DialTicks: Shape {
    var count: Int
    var length: CGFloat
    var from: Double = 0
    var to: Double = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer - length
        for index in 0..<max(2, count) {
            let fraction = Double(index) / Double(max(2, count) - 1)
            guard fraction >= from - 0.0001, fraction <= to + 0.0001 else { continue }
            let angle = (135 + 270 * fraction) * .pi / 180
            path.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
            path.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
        }
        return path
    }
}

/// A dial of radial tick marks over 270°. Ticks up to `value` light up in a
/// gradient; an optional band (e.g. the optimal range) is drawn outside.
struct TickDial<Content: View>: View {
    /// 0...1
    let value: Double?
    var band: ClosedRange<Double>?
    let colors: [Color]
    var tickCount = 44
    var tickLength: CGFloat = 12
    var bandColor: Color = Theme.recoveryHigh
    @ViewBuilder var content: Content

    var body: some View {
        let style = StrokeStyle(lineWidth: 3.2, lineCap: .round)
        // Spread the colors over the dial's 270° (the conic gradient starts at 135°).
        let stops = colors.enumerated().map { index, color in
            Gradient.Stop(color: color, location: 0.75 * Double(index) / Double(max(1, colors.count - 1)))
        }
        let lit = AngularGradient(gradient: Gradient(stops: stops), center: .center, startAngle: .degrees(135), endAngle: .degrees(495))
        ZStack {
            DialTicks(count: tickCount, length: tickLength)
                .stroke(Theme.track, style: style)
            if let value {
                DialTicks(count: tickCount, length: tickLength, from: 0, to: min(1, max(0, value)))
                    .stroke(lit, style: style)
                    .shadow(color: (colors.last ?? Theme.strain).opacity(0.3), radius: 4)
            }
            if let band {
                GaugeArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(LinearGradient(colors: [Theme.recoveryHighLight, bandColor], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(-8)
            }
            content
        }
        .padding(8)
    }
}

/// Soft pastel gradient wash at the top of a tab, fading into the background.
struct TopGlow: View {
    /// Three pastel colors, left to right (see `Theme.Wash`).
    let colors: [Color]
    var height: CGFloat = 460

    var body: some View {
        let a = colors.first ?? Theme.Wash.peach
        let b = colors.count > 1 ? colors[1] : a
        let c = colors.last ?? b
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                a, b, c,
                b, c, a,
                Theme.background, Theme.background, Theme.background
            ]
        )
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .frame(height: height)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Round Liquid Glass button for screen headers.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The glass circle itself, for use inside a NavigationLink.
struct GlassIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 46, height: 46)
            .glassEffect(.regular.interactive(), in: .circle)
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
                        Text("\(whole(tick))").offset(x: w * tick / maximum)
                    }
                    Text("\(whole(target.lowerBound))")
                        .foregroundStyle(Theme.recoveryHigh)
                        .offset(x: w * target.lowerBound / maximum - 6)
                    Text("\(whole(target.upperBound))")
                        .foregroundStyle(Theme.recoveryHigh)
                        .offset(x: w * target.upperBound / maximum - 6)
                    Text("\(whole(maximum))")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strain \(current.formatted(.number.precision(.fractionLength(1)))) of 21, target \(whole(target.lowerBound)) to \(whole(target.upperBound))")
    }
}

/// Vertical pill gauge: a recessed track, gradient fill up to today's value,
/// the usual range faintly marked, and a glowing knob.
struct VerticalRangeGauge: View {
    /// 0 (bottom) ... 1 (top)
    let value: Double?
    var normal: ClosedRange<Double> = 0.3...0.7
    let color: Color
    var lightColor: Color?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let v = value.map { min(1, max(0, $0)) }
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.track.shadow(.inner(color: Color.black.opacity(0.14), radius: 2, y: 1)))
                Capsule()
                    .fill(color.opacity(0.12))
                    .frame(height: h * (normal.upperBound - normal.lowerBound))
                    .offset(y: -h * normal.lowerBound)
                if let v {
                    Capsule()
                        .fill(LinearGradient(colors: [color, lightColor ?? color.opacity(0.45)], startPoint: .bottom, endPoint: .top))
                        .frame(height: max(w, h * v))
                    Circle()
                        .fill(Color.white)
                        .strokeBorder(color, lineWidth: 3)
                        .frame(width: w + 6, height: w + 6)
                        .shadow(color: color.opacity(0.55), radius: 5)
                        .offset(y: -(h - w) * v + 3)
                }
            }
            .frame(width: w)
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

/// Thin vertical ticks across a rect, for positions in `from...to` (0...1).
nonisolated struct TickRow: Shape {
    var from: Double = 0
    var to: Double = 1
    var tickWidth: CGFloat = 3.5
    var gap: CGFloat = 2.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(1, Int((rect.width + gap) / (tickWidth + gap)))
        for index in 0..<count {
            let position = (Double(index) + 0.5) / Double(count)
            guard position > from, position <= to else { continue }
            let tick = CGRect(x: rect.minX + CGFloat(index) * (tickWidth + gap), y: rect.minY, width: tickWidth, height: rect.height)
            path.addRoundedRect(in: tick, cornerSize: CGSize(width: tickWidth / 2, height: tickWidth / 2))
        }
        return path
    }
}

/// A row of thin vertical ticks, colored by segment (energy split, zones).
struct SegmentedBar: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 26

    var body: some View {
        let visible = segments.filter { $0.value > 0 }
        let total = visible.map(\.value).reduce(0, +)
        let spans: [(from: Double, to: Double, color: Color)] = {
            var running = 0.0
            return visible.map { segment in
                let start = running
                running += segment.value / max(total, 0.0001)
                return (start, running, segment.color)
            }
        }()
        ZStack {
            if spans.isEmpty {
                TickRow().fill(Theme.track)
            }
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                TickRow(from: span.from, to: span.to).fill(span.color)
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
                Text(LocalizedStringKey(goal.map { "**\(whole(value))** / \(whole($0)) \(unit)" } ?? "**\(whole(value))** \(unit)"))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(7, geo.size.width * min(1, value / max(goal ?? value * 1.4, 1))))
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
            .background(LinearGradient(colors: [color.opacity(0.24), color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: size * 0.3))
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

/// Mini trend line with a gradient fill, a dotted average line and a glowing
/// dot on the latest value.
struct Sparkline: View {
    let values: [DatedValue]
    let color: Color
    var showsArea = true

    var body: some View {
        let average = values.isEmpty ? nil : values.map(\.value).reduce(0, +) / Double(values.count)
        Chart {
            if let average, values.count > 1 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Theme.secondaryText.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(values) { point in
                if showsArea {
                    AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)], startPoint: .top, endPoint: .bottom))
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
                            .fill(Color.white)
                            .strokeBorder(color, lineWidth: 2.5)
                            .frame(width: 11, height: 11)
                            .shadow(color: color.opacity(0.7), radius: 4)
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}
