import SwiftUI

// The Watch app's chart and ring shapes. Every one is a `nonisolated` Shape:
// SwiftUI draws shapes on a background render thread, and a main-actor
// `path(in:)` crashes at launch (CLAUDE.md). No `Canvas`, for the same reason.

/// An arc of a full circle from 12 o'clock, clockwise, for `fraction` (0-1).
nonisolated struct RingArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard clamped > 0 else { return path }
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        return path
    }
}

/// One stretch of a horizontal bar, from `start` to `end` (fractions of the
/// width), as a rounded rectangle. The zones bar draws five of them.
nonisolated struct ZoneBar: Shape {
    var start: Double
    var end: Double
    var cornerRadius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let from = min(1, max(0, start.isFinite ? start : 0))
        let to = min(1, max(from, end.isFinite ? end : from))
        let width = rect.width * (to - from)
        guard width > 0.5 else { return Path() }
        let segment = CGRect(x: rect.minX + rect.width * from, y: rect.minY, width: width, height: rect.height)
        return Path(roundedRect: segment, cornerRadius: min(cornerRadius, width / 2, rect.height / 2))
    }
}

/// A line through `values`, spread evenly across the width, scaled to `range`
/// (bottom to top). Fewer than two values draw nothing.
nonisolated struct Sparkline: Shape {
    var values: [Double]
    var range: ClosedRange<Double>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, finite.count == values.count else { return path }
        let span = max(range.upperBound - range.lowerBound, 1)
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let share = (value - range.lowerBound) / span
            let point = CGPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.maxY - rect.height * CGFloat(min(1, max(0, share))))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Vertical bars for `values` (taller = larger), side by side with a gap.
/// `only` draws just the bars at those indices, so a highlighted bar can be
/// stroked in another colour over the rest.
nonisolated struct SplitBars: Shape {
    var values: [Double]
    var gap: CGFloat = 3
    var only: Set<Int>?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let usable = values.map { $0.isFinite ? max(0, $0) : 0 }
        guard !usable.isEmpty, let top = usable.max(), top > 0 else { return path }
        let count = CGFloat(usable.count)
        let width = max(1, (rect.width - gap * (count - 1)) / count)
        for (index, value) in usable.enumerated() where only?.contains(index) ?? true {
            let height = max(2, rect.height * CGFloat(value / top))
            let bar = CGRect(x: rect.minX + CGFloat(index) * (width + gap), y: rect.maxY - height, width: width, height: height)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: min(3, width / 2), height: min(3, width / 2)))
        }
        return path
    }
}
