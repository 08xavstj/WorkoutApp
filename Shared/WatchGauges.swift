import SwiftUI
import WidgetKit

// Recovery and strain gauges, drawn by the complications
// (`RecoveryStrainComplication`) and by the Watch app's Home glance, so the
// two never look different. Compiled into both watch targets (project.yml).
// `widgetAccentable()` is a no-op outside a widget.

/// A 0-100 score as a 0-1 fraction for rings and bars (never crashes on NaN).
nonisolated func faceFraction(_ value: Double) -> Double {
    value.isFinite ? min(max(value / 100, 0), 1) : 0
}

/// A ring of `segments` equal pieces with the first `fraction` of them lit,
/// starting at 12 o'clock. Unlit pieces stay as a faint track, so in a
/// tinted face the count still reads by brightness, not colour alone.
struct SegmentedRing: View {
    let fraction: Double?
    let color: Color
    var segments = 10
    /// 3.5 pt on the face; the Watch app's Home glance draws it larger.
    var width: CGFloat = 3.5
    /// Share of each segment left as a gap between pieces.
    private let gap = 0.18

    private var lit: Int {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(segments, max(0, Int((fraction * Double(segments)).rounded())))
    }

    var body: some View {
        ZStack {
            ForEach(0..<segments, id: \.self) { index in
                let from = (Double(index) + gap / 2) / Double(segments)
                let to = (Double(index + 1) - gap / 2) / Double(segments)
                if index < lit {
                    Circle()
                        .trim(from: from, to: to)
                        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
                        .widgetAccentable()
                } else {
                    Circle()
                        .trim(from: from, to: to)
                        .stroke(WatchPalette.track, style: StrokeStyle(lineWidth: width, lineCap: .butt))
                }
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(width / 2)
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
                    .stroke(WatchPalette.track, lineWidth: width)
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
                    .fill(WatchPalette.track)
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

