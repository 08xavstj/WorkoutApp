import AppCore
import Charts
import SwiftUI

/// Pace (faster up) or speed along the route, with heart rate drawn over it
/// on the same height when asked: its own bpm range is printed beside it, as
/// a chart has one y axis. The y unit (min/km, km/h...) is in the card's
/// header (`RouteChartScale.paceUnit`, `speedUnit`).
struct PaceChart: View {
    let points: [RouteSeries.Point]
    let scale: RouteChartScale
    let showsPace: Bool
    let showsHeartRate: Bool

    /// Share of values cut at each end of the y axis, so one stop or one GPS
    /// spike doesn't squash the line (the app's choice).
    static let trimmedShare = 0.05

    /// The plotted value: minus the pace in seconds per unit (so faster is
    /// higher, as with speed), or speed in km/h or mph.
    private func value(_ point: RouteSeries.Point) -> Double? {
        guard let speed = point.speed else { return nil }
        if showsPace { return RouteSeries.pace(speed: speed, unitMeters: scale.unitMeters).map { -$0 } }
        return speed * 3.6 / (scale.miles ? 1.609344 : 1)
    }

    /// The 5th to 95th percentile of the values, padded a little.
    private var domain: ClosedRange<Double>? {
        let values = points.compactMap(value).sorted()
        guard let first = values.first, let last = values.last else { return nil }
        let cut = Int(Double(values.count) * Self.trimmedShare)
        let low = values.count > 20 ? values[cut] : first
        let high = values.count > 20 ? values[values.count - 1 - cut] : last
        let pad = max((high - low) * 0.1, showsPace ? 5 : 0.5)
        return (low - pad)...(high + pad)
    }

    private var bpmRange: ClosedRange<Double>? {
        let bpms = points.compactMap(\.bpm)
        guard let low = bpms.min(), let high = bpms.max(), high > low else { return nil }
        return low...high
    }

    var body: some View {
        if let domain {
            VStack(alignment: .leading, spacing: 4) {
                chart(domain: domain)
                if showsHeartRate, let bpmRange {
                    Text("Heart rate \(whole(bpmRange.lowerBound))–\(whole(bpmRange.upperBound)) bpm, scaled to the chart's height")
                        .font(.caption2)
                        .foregroundStyle(Theme.heartText)
                }
            }
        }
    }

    /// A point with its plotted value and the unbroken run it belongs to.
    struct Plotted: Identifiable {
        let point: RouteSeries.Point
        let value: Double
        let run: Int
        var id: Int { point.id }
    }

    /// Points with a value, each tagged with its unbroken run, so a stop
    /// (no speed) leaves a gap instead of a straight line across it.
    private var runs: [Plotted] {
        var result: [Plotted] = []
        var run = 0
        var broken = false
        for point in points {
            guard let raw = value(point) else {
                broken = true
                continue
            }
            if broken, !result.isEmpty { run += 1 }
            broken = false
            result.append(Plotted(point: point, value: raw, run: run))
        }
        return result
    }

    private func chart(domain: ClosedRange<Double>) -> some View {
        Chart {
            ForEach(runs) { item in
                LineMark(x: .value(scale.title, scale.x(item.point)), y: .value(showsPace ? "Pace" : "Speed", clamp(item.value, domain)),
                         series: .value("Series", "pace-\(item.run)"))
                    .foregroundStyle(Theme.oxygen)
                    .interpolationMethod(.monotone)
            }
            if showsHeartRate, let bpmRange {
                ForEach(points) { point in
                    if let bpm = point.bpm {
                        LineMark(x: .value(scale.title, scale.x(point)), y: .value("Heart rate", scaled(bpm, from: bpmRange, to: domain)),
                                 series: .value("Series", "heart"))
                            .foregroundStyle(Theme.heart.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartYScale(domain: domain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(showsPace ? CardioBests.timeText(-number) : number.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(number.formatted(.number.precision(.fractionLength(0...1)))) \(scale.title)")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsPace ? "Pace along the route" : "Speed along the route")
    }

    private func clamp(_ value: Double, _ domain: ClosedRange<Double>) -> Double {
        min(domain.upperBound, max(domain.lowerBound, value))
    }

    /// Heart rate placed on the pace or speed axis (lowest bpm at the bottom).
    private func scaled(_ bpm: Double, from range: ClosedRange<Double>, to domain: ClosedRange<Double>) -> Double {
        let fraction = (bpm - range.lowerBound) / (range.upperBound - range.lowerBound)
        return domain.lowerBound + fraction * (domain.upperBound - domain.lowerBound)
    }
}
