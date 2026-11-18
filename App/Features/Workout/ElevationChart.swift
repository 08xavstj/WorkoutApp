import AppCore
import Charts
import SwiftUI

/// Elevation along the route in metres or feet, filled down to the lowest point.
struct ElevationChart: View {
    let points: [RouteSeries.Point]
    let scale: RouteChartScale

    private var factor: Double { scale.miles ? CardioSummary.feetPerMeter : 1 }

    /// Lowest to highest, in display units.
    private var range: ClosedRange<Double>? {
        let altitudes = points.compactMap(\.altitude).map { $0 * factor }
        guard let low = altitudes.min(), let high = altitudes.max() else { return nil }
        return low...high
    }

    /// The range padded so a flat route doesn't fill the whole height.
    private var domain: ClosedRange<Double>? {
        guard let range else { return nil }
        let pad = max((range.upperBound - range.lowerBound) * 0.15, scale.miles ? 15 : 5)
        return (range.lowerBound - pad)...(range.upperBound + pad)
    }

    var body: some View {
        if let domain {
            Chart {
                ForEach(points) { point in
                    if let altitude = point.altitude {
                        AreaMark(x: .value(scale.title, scale.x(point)),
                                 yStart: .value("Base", domain.lowerBound),
                                 yEnd: .value("Elevation", altitude * factor))
                            .foregroundStyle(LinearGradient(colors: [Theme.recoveryHigh.opacity(0.35), Theme.recoveryHigh.opacity(0.05)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value(scale.title, scale.x(point)), y: .value("Elevation", altitude * factor))
                            .foregroundStyle(Theme.recoveryHighText)
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(whole(number)) \(scale.miles ? "ft" : "m")")
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
            .accessibilityLabel("Elevation along the route")
            .accessibilityValue(range.map { "\(whole($0.lowerBound)) to \(whole($0.upperBound)) \(scale.miles ? "feet" : "metres")" } ?? "")
        }
    }
}
