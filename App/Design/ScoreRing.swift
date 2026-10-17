import SwiftUI

/// Circular progress ring with the score in the middle.
struct ScoreRing: View {
    let title: String
    let valueText: String
    /// 0...1
    let progress: Double
    let color: Color
    var size: CGFloat = 100

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: size * 0.09)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(duration: 0.8), value: progress)
                Text(valueText)
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, size * 0.14)
            }
            .frame(width: size, height: size)

            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(valueText)")
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
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2), with: .color(Theme.separator))
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

/// Small label + value pair used inside cards.
struct StatView: View {
    let label: String
    let value: String
    var detail: String?
    var color: Color = .white

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
