import AppCore
import SwiftUI

/// Pace (or speed) and elevation along the route, over distance or time
/// (`RouteSeries`; competitor-features-2026-11.md, B11). These only show
/// what the route recorded; there is no health claim to make about them.
struct RouteChartsCard: View {
    let route: CardioRoute
    let showsPace: Bool

    @State private var axis: RouteSeries.Axis = .distance
    @State private var showsHeartRate = false

    /// Miles and feet where distances are in miles (the US and the UK), as on the rest of the page.
    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    var body: some View {
        let points = RouteSeries.points(route, axis: axis)
        let scale = RouteChartScale(axis: axis, miles: miles)
        if RouteSeries.hasSpeed(points) || RouteSeries.hasAltitude(points) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Along", selection: $axis) {
                    ForEach(RouteSeries.Axis.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if RouteSeries.hasSpeed(points) {
                    HStack {
                        Text(showsPace ? "Pace" : "Speed")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        if RouteSeries.hasHeartRate(points) {
                            Toggle("Heart rate", isOn: $showsHeartRate)
                                .toggleStyle(.button)
                                .font(.caption.weight(.semibold))
                                .tint(Theme.heart)
                        }
                    }
                    PaceChart(points: points, scale: scale, showsPace: showsPace, showsHeartRate: showsHeartRate)
                        .frame(height: 170)
                }
                if RouteSeries.hasAltitude(points) {
                    Text("Elevation")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    ElevationChart(points: points, scale: scale)
                        .frame(height: 120)
                }
                Text("Smoothed over each stretch of the route. Stops leave gaps, and the slowest and fastest 5% are drawn at the chart's edge so one stop or GPS spike doesn't flatten the line.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
}

/// The x axis in display units: km or miles, or minutes.
struct RouteChartScale {
    let axis: RouteSeries.Axis
    let miles: Bool

    func x(_ point: RouteSeries.Point) -> Double {
        switch axis {
        case .distance: point.meters / (miles ? CardioBests.metersPerMile : 1000)
        case .time: point.seconds / 60
        }
    }

    var title: String {
        switch axis {
        case .distance: miles ? "mi" : "km"
        case .time: "min"
        }
    }

    /// Metres per pace unit (km or mile).
    var unitMeters: Double { miles ? CardioBests.metersPerMile : 1000 }
}
